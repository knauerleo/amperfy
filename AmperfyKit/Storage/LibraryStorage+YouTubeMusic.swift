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
      let entry = Entry(
        artist: hit.artist,
        thumb: hit.thumbURL?.absoluteString,
        added: Date(),
        json: hit.json
      )
      entries[YouTubeMusic.playableId(videoId: hit.videoId)] = entry
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
  /// Returns the placeholder song of the result, creating it on first use.
  public func getOrCreateYouTubeMusicSong(for account: Account, hit: SongpickerHit) -> Song {
    YouTubeMusicHitStore.shared.remember(hit)
    let id = YouTubeMusic.playableId(videoId: hit.videoId)
    let song = getSong(for: account, id: id) ?? {
      let created = createSong(account: account)
      created.id = id
      return created
    }()
    song.title = hit.title
    if hit.duration > 0 {
      song.remoteDuration = hit.duration
    }
    if song.artwork == nil {
      let remoteInfo = ArtworkRemoteInfo(id: id, type: "")
      let artwork = getArtwork(for: account, remoteInfo: remoteInfo) ?? {
        let created = createArtwork(account: account)
        created.remoteInfo = remoteInfo
        created.status = .NotChecked
        return created
      }()
      song.artwork = artwork
    }
    return song
  }

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
    guard let unused = try? context.fetch(fetchRequest), !unused.isEmpty else { return }
    for songMO in unused {
      if let artworkMO = songMO.artwork, (artworkMO.owners?.count ?? 0) <= 1 {
        context.delete(artworkMO)
      }
      context.delete(songMO)
    }
    saveContext()
  }
}
