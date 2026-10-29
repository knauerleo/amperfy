//
//  LibraryStorage+YouTubeMusicSwap.swift
//  AmperfyKit
//
//  Fork (TASKS F-6): once a YouTube Music download is in the library, the placeholder
//  (`ytm-<videoId>`) is swapped for the real Navidrome song in the player queues, the playlists
//  and the search history, at the same position.
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

extension LibraryStorage {
  /// Puts `song` in every place that holds the placeholder of `videoId`.
  /// Returns the server playlists that changed: the proxy drops `ytm-` IDs from
  /// `createPlaylist`/`updatePlaylist`, so the server lacks the song until it is uploaded again.
  @discardableResult
  public func replaceYouTubeMusicPlaceholder(
    videoId: String,
    with song: Song,
    account: Account
  )
    -> [Playlist] {
    guard !song.isYouTubeMusicPlaceholder,
          let placeholder = getSong(for: account, id: YouTubeMusic.playableId(videoId: videoId))
    else { return [] }
    let placeholderMO = placeholder.managedObject
    let songMO = song.managedObject

    // queues (user, context, shuffled) and playlists are all playlist items
    var changedPlaylists = [PlaylistMO]()
    for item in Array(placeholderMO.playlistItems) {
      item.playable = songMO
      if !changedPlaylists.contains(item.playlist) {
        changedPlaylists.append(item.playlist)
      }
    }
    let playlists = changedPlaylists.map { Playlist(library: self, managedObject: $0) }
    playlists.forEach { $0.updateArtworkItems() }

    // search history: one entry per object, the newer date wins
    if let placeholderHistory = placeholderMO.searchHistory {
      if let songHistory = songMO.searchHistory {
        if let date = placeholderHistory.date, date > (songHistory.date ?? .distantPast) {
          songHistory.date = date
        }
        context.delete(placeholderHistory)
      } else {
        placeholderHistory.searchedLibraryEntity = songMO
      }
    }
    // "Recently Played" follows `lastPlayedDate`
    if let played = placeholderMO.lastPlayedDate,
       played > (songMO.lastPlayedDate ?? .distantPast) {
      songMO.lastPlayedDate = played
    }
    saveContext()

    return playlists.filter { playlist in
      let managedObject = playlist.managedObject
      return managedObject.playersUserQueuePlaylist == nil &&
        managedObject.playersContextPlaylist == nil &&
        managedObject.playersShuffledContextPlaylist == nil &&
        managedObject.playersPodcastPlaylist == nil &&
        !playlist.isSmartPlaylist
    }
  }
}
