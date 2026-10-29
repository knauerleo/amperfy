//
//  YouTubeMusicAlbumGaps.swift
//  AmperfyKit
//
//  Fork (TASKS F-19, F-19c): songs of a library album that are on YouTube Music but not in the
//  library. Since F-19c the proxy does the matching: `getAlbum&drift=full` returns the tracks
//  of the matching YouTube Music album, the missing ones as `ytm-` entries. The earlier search
//  over `search3` matched by name only and found e.g. a Gzuz song in a BMTH album.
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

// MARK: - YouTubeMusicAlbumGaps

public struct YouTubeMusicAlbumGaps: Sendable {
  /// The Navidrome album the gaps belong to.
  public let libraryAlbumId: String
  public let album: YouTubeAlbum
  /// In album order.
  public let missing: [YouTubeAlbumSong]
}

// MARK: - YouTubeMusicAlbumGapFinder

@MainActor
public enum YouTubeMusicAlbumGapFinder {
  /// F-19c: the proxy matches the album (`getAlbum&drift=full`) and lists the tracks of its
  /// YouTube Music album that the library doesn't have as `ytm-` entries. Asked fresh on every
  /// open, the proxy caches the match (7 days, then 10–50 ms).
  public static func gaps(
    for album: Album,
    storage: PersistentStorage,
    backendApi: BackendProxy
  ) async
    -> YouTubeMusicAlbumGaps? {
    guard SongpickerConfig.isEnabled, storage.settings.user.isOnlineMode,
          !album.id.isEmpty, !YouTubeMusic.isPlaceholderId(album.id)
    else { return nil }
    guard let ytAlbum = try? await backendApi.forkDriftFullAlbum(albumId: album.id)
    else { return nil }
    return YouTubeMusicAlbumGaps(
      libraryAlbumId: album.id,
      album: ytAlbum,
      missing: ytAlbum.songs.filter { !$0.downloaded }
    )
  }

}
