//
//  AmperKit+ForkAutoplay.swift
//  AmperfyKit
//
//  Fork (TASKS F-5): autoplay (song radio after the end of the queue) goes on with YouTube Music
//  songs when the library has nothing new left: `getSimilarSongs2` returns nothing, or only songs
//  that already played in this queue. Placeholders have no similar songs on the server, so a radio
//  that reached YouTube stays there.
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

extension AmperKit {
  /// YouTube songs appended per autoplay round.
  private static let youTubeAutoplayCount = 10

  func forkAutoplaySongs(after song: Song) async throws -> [Song] {
    guard let accountInfo = song.account?.info else { return [] }
    let meta = getMeta(accountInfo)
    var similarError: Error?
    var similar = [Song]()
    do {
      similar = try await meta.librarySyncer.requestSimilarSongs(song: song, count: 99)
    } catch {
      similarError = error
    }
    var playedIds = Set(player.getAllPrevQueueItems().map { $0.id })
    playedIds.insert(song.id)
    if similar.contains(where: { !playedIds.contains($0.id) }) {
      return similar
    }

    let account = storage.main.library.getAccount(info: accountInfo)
    let youTubeSongs = await YouTubeMusicSuggestions.similarSongs(
      artistName: song.artist?.name ?? song.creatorName,
      artistId: song.artist?.id,
      account: account,
      storage: storage,
      backendApi: meta.backendApi,
      librarySyncer: meta.librarySyncer,
      excludingIds: playedIds,
      limit: Self.youTubeAutoplayCount
    )
    if !youTubeSongs.isEmpty {
      return youTubeSongs
    }
    if let similarError { throw similarError }
    return similar
  }
}
