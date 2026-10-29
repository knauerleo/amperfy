//
//  YouTubeMusicAlbumGaps.swift
//  AmperfyKit
//
//  Fork (TASKS F-19): songs of a library album that are on YouTube Music but not in the
//  library. The album is found through the server search (`search3` at the proxy returns
//  `ytm-` results with their album): a result whose album name matches, then `getYtAlbum` with
//  that song. A song counts as present when the proxy knows it as downloaded, its Navidrome ID
//  is in the library, or the album has a song with the same title (also CD rips and other
//  sources the proxy doesn't know).
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

// MARK: - YouTubeMusicAlbumGaps

public struct YouTubeMusicAlbumGaps: Sendable {
  public let album: YouTubeAlbum
  /// In album order.
  public let missing: [YouTubeAlbumSong]
}

// MARK: - YouTubeMusicAlbumGapFinder

@MainActor
public enum YouTubeMusicAlbumGapFinder {
  /// Search results checked for a matching album, each check is a `getYtAlbum` on the Pi.
  private static let maxCandidates = 3
  /// Per library album ID for this session, nil = no album on YouTube Music. Every lookup is
  /// a YouTube Music search on the Pi, so an album page asks only once.
  private static var cache = [String: YouTubeMusicAlbumGaps?]()

  public static func cachedGaps(albumId: String) -> YouTubeMusicAlbumGaps?? {
    cache[albumId]
  }

  public static func gaps(
    for album: Album,
    account: Account,
    storage: PersistentStorage,
    backendApi: BackendProxy,
    librarySyncer: LibrarySyncer
  ) async
    -> YouTubeMusicAlbumGaps? {
    if let cached = cache[album.id] { return cached }
    guard SongpickerConfig.isEnabled, storage.settings.user.isOnlineMode,
          !YouTubeMusic.isPlaceholderId(album.id)
    else { return nil }
    let albumName = normalized(album.name)
    let artistName = album.artist?.name ?? album.subtitle ?? ""
    guard !albumName.isEmpty else { return nil }

    let query = artistName.isEmpty ? album.name : "\(artistName) \(album.name)"
    guard let ids = try? await librarySyncer.searchSongs(searchText: query) else { return nil }
    let context = storage.main.context
    let candidates = ids.compactMap { context.object(with: $0) as? SongMO }
      .map { Song(managedObject: $0) }
      .filter { song in
        guard song.isYouTubeMusicPlaceholder,
              let hit = YouTubeMusicHitStore.shared.hit(forVideoId: videoId(of: song))
        else { return false }
        let hitAlbum = hit.album ?? ""
        return normalized(hitAlbum) == albumName || editionBaseName(hitAlbum) == albumName
      }

    var result: YouTubeMusicAlbumGaps?
    // an edition ("Meteora 20th Anniversary Edition" for "Meteora") only if no exact album turns up
    var editionResult: YouTubeMusicAlbumGaps?
    var checkedAlbums = Set<String>()
    var hadError = false
    let maxLocalTrack = album.songs.filter { !$0.isYouTubeMusicPlaceholder }.map(\.track).max() ?? 0
    for candidate in candidates.prefix(maxCandidates) {
      let ytAlbum: YouTubeAlbum
      do {
        ytAlbum = try await backendApi.forkYouTubeAlbum(id: candidate.id)
      } catch {
        hadError = true
        continue
      }
      guard checkedAlbums.insert(ytAlbum.id).inserted else { continue }
      if normalized(ytAlbum.name) == albumName {
        result = YouTubeMusicAlbumGaps(
          album: ytAlbum,
          missing: missingSongs(of: ytAlbum, in: album, account: account, storage: storage)
        )
        break
      }
      // the edition adds bonus tracks and demos: only the track numbers the local album covers
      if editionResult == nil, maxLocalTrack > 0, editionBaseName(ytAlbum.name) == albumName {
        editionResult = YouTubeMusicAlbumGaps(
          album: ytAlbum,
          missing: missingSongs(of: ytAlbum, in: album, account: account, storage: storage)
            .filter { ($0.track ?? Int.max) <= maxLocalTrack }
        )
      }
    }
    result = result ?? editionResult
    // a failed request is asked again next time, "no album" is kept
    if result != nil || !hadError { cache[album.id] = .some(result) }
    return result
  }

  /// The proxy's state of the songs again (after downloads), keeps the album match.
  public static func refresh(
    _ gaps: YouTubeMusicAlbumGaps,
    for album: Album,
    account: Account,
    storage: PersistentStorage,
    backendApi: BackendProxy
  ) async
    -> YouTubeMusicAlbumGaps {
    guard let ytAlbum = try? await backendApi.forkYouTubeAlbum(id: gaps.album.id) else {
      return gaps
    }
    // songs that were missing stay listed until the page is opened again, now with their state
    let listed = Set(gaps.missing.map(\.id))
    let updated = YouTubeMusicAlbumGaps(
      album: ytAlbum,
      missing: ytAlbum.songs.filter { listed.contains($0.id) }
    )
    cache[album.id] = .some(updated)
    return updated
  }

  private static func missingSongs(
    of ytAlbum: YouTubeAlbum,
    in album: Album,
    account: Account,
    storage: PersistentStorage
  )
    -> [YouTubeAlbumSong] {
    let localSongs = album.songs.filter { !$0.isYouTubeMusicPlaceholder }
    let localIds = Set(localSongs.map(\.id))
    let localTitles = Set(localSongs.map { normalized($0.title) })
    let library = storage.main.library
    return ytAlbum.songs.filter { song in
      if song.downloaded { return false }
      if let navidromeId = song.navidromeId,
         localIds.contains(navidromeId) || library.getSong(for: account, id: navidromeId) != nil {
        return false
      }
      return !localTitles.contains(normalized(song.title))
    }
  }

  /// Like `normalized`, without an edition suffix: "Meteora 20th Anniversary Edition",
  /// "Hybrid Theory Bonus Edition", "Abbey Road Super Deluxe" all become the plain album name.
  static func editionBaseName(_ text: String) -> String {
    var result = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil
    )
    result = result.replacingOccurrences(
      of: #"\s*[\(\[][^\)\]]*[\)\]]"#,
      with: "",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"[\s\-:]+(\d+(st|nd|rd|th)\s+)?(anniversary|super deluxe|deluxe|bonus|expanded|special|remastered|remaster|collector'?s)(\s+(edition|version))?\s*$"#,
      with: "",
      options: .regularExpression
    )
    return normalized(result)
  }

  private static func videoId(of song: AbstractPlayable) -> String {
    String(song.id.dropFirst(YouTubeMusic.idPrefix.count))
  }

  /// Lower case without diacritics, bracketed parts ("(feat. …)", "[Deluxe]", "(2011 Remaster)"),
  /// suffixes like " - Remastered 2011" and punctuation.
  static func normalized(_ text: String) -> String {
    var result = text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil
    )
    result = result.replacingOccurrences(
      of: #"\s*[\(\[][^\)\]]*[\)\]]"#,
      with: "",
      options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: #"\s+-\s+[^-]*(remaster|version|edit|mix|live|mono|stereo|deluxe|edition)[^-]*$"#,
      with: "",
      options: .regularExpression
    )
    return String(result.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
      .map(Character.init))
  }
}
