//
//  BackendProxy+ForkAlbumCleanup.swift
//  AmperfyKit
//
//  Fork: albums whose ID Navidrome no longer knows. On 2026-10-29 up to 36 albums were briefly
//  split in two on the server (Spotify and YouTube folder), after the repair they have new IDs,
//  their songs kept theirs. The library sync only adds albums, so the old ones stayed: an album
//  page marked one as deleted only when it was opened. This compares all album IDs of the
//  server (`getAlbumList2`) with the library, hides the stale albums and reads their songs
//  again (`getSong`), which moves them to their current album.
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

import Foundation

extension BackendProxy {
  private static let albumListPageSize = 500
  /// More stale albums than this share of the library looks like an incomplete server answer.
  private static let maxStaleAlbumShare = 0.2
  /// `getSong` requests at the same time.
  private static let songRefetchBatch = 10

  /// Hides albums the server no longer has and moves their songs to their current album.
  /// Returns the number of hidden albums, 0 for other servers than Subsonic.
  @MainActor
  public func forkCleanUpStaleAlbums(account: Account, storage: PersistentStorage) async throws -> Int {
    guard let serverApi = forkSubsonicServerApi else { return 0 }
    var remoteIds = Set<String>()
    var offset = 0
    while true {
      let response = try await serverApi.requestAlbums(offset: offset, count: Self.albumListPageSize)
      if let error = checkForErrorResponse(response: response) { throw error }
      let delegate = SsIDsParserDelegate(performanceMonitor: ThreadPerformanceObserver.shared)
      let parser = XMLParser(data: response.data)
      parser.delegate = delegate
      guard parser.parse() else { throw SongpickerError.invalidResponse }
      let pageIds = delegate.prefetchIDs.albumIDs
      remoteIds.formUnion(pageIds)
      if pageIds.count < Self.albumListPageSize { break }
      offset += Self.albumListPageSize
    }
    guard !remoteIds.isEmpty else { return 0 }

    let library = storage.main.library
    let localAlbums = library.getAlbums(for: account).filter {
      $0.remoteStatus == .available && !$0.id.isEmpty && !$0.isOrphaned &&
        !YouTubeMusic.isPlaceholderId($0.id)
    }
    let staleAlbums = localAlbums.filter { !remoteIds.contains($0.id) }
    guard !staleAlbums.isEmpty else { return 0 }
    guard Double(staleAlbums.count) <= Double(localAlbums.count) * Self.maxStaleAlbumShare
    else { throw SongpickerError.invalidResponse }

    for album in staleAlbums {
      // `ndv-` IDs (a song shown in another album) answer `stale_context_id` once that album is gone
      let songIds = album.songs.filter { !$0.isYouTubeMusicPlaceholder && !$0.id.hasPrefix("ndv-") }
        .map(\.id)
      // not `markAsRemoteDeleted`: the songs still exist, only in another album
      album.remoteStatus = .deleted
      for start in stride(from: 0, to: songIds.count, by: Self.songRefetchBatch) {
        let batch = Array(songIds[start ..< min(start + Self.songRefetchBatch, songIds.count)])
        _ = await forkFetchLibrarySongs(ids: batch, account: account, storage: storage)
      }
    }
    library.saveContext()
    return staleAlbums.count
  }
}
