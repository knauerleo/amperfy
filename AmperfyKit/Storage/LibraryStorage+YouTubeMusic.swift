//
//  LibraryStorage+YouTubeMusic.swift
//  AmperfyKit
//
//  Fork: placeholder songs for YouTube Music results. A placeholder has the ID `ytm-<videoId>`,
//  which the Subsonic proxy streams right away. It has no album and no size, so the library lists
//  (`excludeServerDeleteUncachedSongsFetchPredicate`) do not show it.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import CoreData
import Foundation

// MARK: - YouTubeMusic

public enum YouTubeMusic {
  public static let idPrefix = "ytm-"

  public static func playableId(videoId: String) -> String {
    idPrefix + videoId
  }

  public static func isPlaceholderId(_ id: String) -> Bool {
    id.hasPrefix(idPrefix)
  }

  /// The proxy marks its results with " ☁︎" at the end of the title.
  private static let titleMarkers = ["\u{2601}\u{FE0E}", "\u{2601}\u{FE0F}", "\u{2601}"]

  public static func strippedTitle(_ title: String) -> String {
    var result = title.trimmingCharacters(in: .whitespaces)
    while let marker = titleMarkers.first(where: { result.hasSuffix($0) }) {
      result = String(result.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
    }
    return result
  }

  /// Attributes of a `ytm-` song from the proxy without album, artist, genre, size and date.
  /// Otherwise the parser would create the shared fake album `ytm-ytsuche0000`, artists and
  /// genres, and the songs would show up in the library lists. The artist name goes to the
  /// `YouTubeMusicHitStore` instead, the title loses its marker.
  static func sanitizedProxyAttributes(
    elementName: String,
    _ attributes: [String: String]
  )
    -> [String: String] {
    guard elementName == "song" || elementName == "entry" || elementName == "child",
          let id = attributes["id"], isPlaceholderId(id)
    else { return attributes }
    var result = attributes
    for key in [
      "albumId", "album", "artistId", "artist", "genre", "created", "path", "parent", "track",
      "discNumber", "year",
    ] {
      result.removeValue(forKey: key)
    }
    // placeholders have no size, that keeps them out of the library lists
    result["size"] = "0"
    let title = strippedTitle(attributes["title"] ?? "")
    result["title"] = title
    if let hit = SongpickerHit(
      videoId: String(id.dropFirst(idPrefix.count)),
      title: title,
      artist: attributes["artist"] ?? "Unknown Artist",
      album: attributes["album"].map(strippedTitle),
      duration: attributes["duration"].flatMap { Int($0) } ?? 0
    ) {
      YouTubeMusicHitStore.shared.remember(hit)
    }
    return result
  }
}

extension AbstractPlayable {
  /// Song created from a YouTube Music result, streamed through the proxy.
  public var isYouTubeMusicPlaceholder: Bool {
    YouTubeMusic.isPlaceholderId(id)
  }
}

// MARK: - YouTubeMusicHitStore

/// Artist name and cover URL of the placeholder songs. The data model has no field for an artist
/// name without an `Artist` object, and creating artists would add them to the library.
public final class YouTubeMusicHitStore: @unchecked Sendable {
  public static let shared = YouTubeMusicHitStore()

  private static let defaultsKey = "fork.youTubeMusic.hits"
  private static let maxEntries = 500

  private struct Entry: Codable {
    var artist: String
    var thumb: String?
    var added: Date
    /// Fork phase 5: the complete result for a retry of `POST /api/get` (optional, older entries lack it)
    var json: Data?
  }

  private let lock = NSLock()
  private var entries: [String: Entry]

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
       let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
      self.entries = decoded
    } else {
      self.entries = [:]
    }
  }

  func remember(_ hit: SongpickerHit) {
    let data: Data? = lock.withLock {
      let id = YouTubeMusic.playableId(videoId: hit.videoId)
      let entry = Entry(
        artist: hit.artist,
        thumb: hit.thumbURL?.absoluteString ?? entries[id]?.thumb,
        added: Date(),
        json: hit.json
      )
      entries[id] = entry
      if entries.count > Self.maxEntries {
        let oldest = entries.sorted { $0.value.added < $1.value.added }
          .prefix(entries.count - Self.maxEntries)
        oldest.forEach { entries.removeValue(forKey: $0.key) }
      }
      return try? JSONEncoder().encode(entries)
    }
    if let data {
      UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
  }

  public func artistName(forPlayableId id: String) -> String? {
    guard YouTubeMusic.isPlaceholderId(id) else { return nil }
    return lock.withLock { entries[id]?.artist }
  }

  /// Placeholder artworks use the playable ID as artwork ID.
  public func thumbURL(forArtworkId id: String) -> URL? {
    guard YouTubeMusic.isPlaceholderId(id) else { return nil }
    return lock.withLock { entries[id]?.thumb }.flatMap { URL(string: $0) }
  }

  /// The result as shown in an earlier search, e.g. for the download overview and its retry.
  public func hit(forVideoId videoId: String) -> SongpickerHit? {
    let json = lock.withLock { entries[YouTubeMusic.playableId(videoId: videoId)]?.json }
    guard let json,
          let dict = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
    else { return nil }
    return SongpickerHit(dict: dict)
  }
}

// MARK: - LibraryStorage

extension LibraryStorage {
  /// Placeholders that are neither queued, in a playlist, in the search history nor cached.
  public func deleteUnusedYouTubeMusicSongs(for account: Account) {
    let fetchRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K BEGINSWITH %@", #keyPath(SongMO.id), YouTubeMusic.idPrefix),
      NSPredicate(format: "%K.@count == 0", #keyPath(SongMO.playlistItems)),
      NSPredicate(format: "%K == nil", #keyPath(SongMO.searchHistory)),
      NSPredicate(format: "%K == nil", #keyPath(SongMO.relFilePath)),
      NSPredicate(format: "%K == nil", #keyPath(SongMO.download)),
    ])
    let unused = (try? context.fetch(fetchRequest)) ?? []
    for songMO in unused {
      if let artworkMO = songMO.artwork, (artworkMO.owners?.count ?? 0) <= 1 {
        context.delete(artworkMO)
      }
      context.delete(songMO)
    }
    let detached = detachProxyEntities(for: account)
    if !unused.isEmpty || detached {
      saveContext()
    }
  }

  /// Songs parsed from the proxy before `sanitizedProxyAttributes` existed: unlinks them from
  /// the fake album, artists and genres, and deletes those entities (IDs `ytm-…`).
  private func detachProxyEntities(for account: Account) -> Bool {
    let songRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K BEGINSWITH %@", #keyPath(SongMO.id), YouTubeMusic.idPrefix),
      NSCompoundPredicate(orPredicateWithSubpredicates: [
        NSPredicate(format: "%K != nil", #keyPath(SongMO.album)),
        NSPredicate(format: "%K != nil", #keyPath(SongMO.artist)),
        NSPredicate(format: "%K != nil", #keyPath(SongMO.genre)),
        NSPredicate(format: "%K > 0", #keyPath(SongMO.size)),
      ]),
    ])
    let songs = (try? context.fetch(songRequest)) ?? []
    for songMO in songs {
      let id = songMO.id
      if let artistName = songMO.artist?.name,
         YouTubeMusicHitStore.shared.artistName(forPlayableId: id) == nil,
         let hit = SongpickerHit(
           videoId: String(id.dropFirst(YouTubeMusic.idPrefix.count)),
           title: YouTubeMusic.strippedTitle(songMO.title ?? ""),
           artist: artistName,
           album: nil,
           duration: Int(songMO.remoteDuration)
         ) {
        YouTubeMusicHitStore.shared.remember(hit)
      }
      songMO.title = YouTubeMusic.strippedTitle(songMO.title ?? "")
      songMO.album = nil
      songMO.artist = nil
      songMO.genre = nil
      songMO.size = 0
    }

    let albumRequest: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    albumRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K BEGINSWITH %@", #keyPath(AlbumMO.id), YouTubeMusic.idPrefix),
    ])
    let albums = (try? context.fetch(albumRequest)) ?? []
    albums.forEach { context.delete($0) }

    let artistRequest: NSFetchRequest<ArtistMO> = ArtistMO.fetchRequest()
    artistRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K BEGINSWITH %@", #keyPath(ArtistMO.id), YouTubeMusic.idPrefix),
    ])
    let artists = (try? context.fetch(artistRequest)) ?? []
    artists.forEach { context.delete($0) }

    return !songs.isEmpty || !albums.isEmpty || !artists.isEmpty
  }
}
