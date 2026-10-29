//
//  ArtistsVC+Fork.swift
//  Amperfy
//
//  Fork: "Shuffle all" / "Play" row on top of the artist list (UI-8). Artist songs are usually
//  not synced yet, so a tap fetches a few albums first: Play takes the albums of the first
//  artists in list order, Shuffle one random album each from random artists.
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

import AmperfyKit
import UIKit

extension ArtistsVC {
  /// Artists looked at per tap. Covers artists without own albums (only track artists).
  private static let forkArtistPickCount = 30

  func forkInstallPlayHeader() {
    ListPlayHeaderView.install(
      in: self,
      player: appDelegate.player,
      infoCB: { [weak self] in
        let count = self?.singleFetchedResultsController?.fetchedObjects?.count ?? 0
        return "\(count) Artist\(count == 1 ? "" : "s")"
      },
      contextProvider: { [weak self] isShuffled in
        await self?.forkPlayContext(isShuffled: isShuffled)
      }
    )
  }

  /// Count text and visibility, called whenever the list content changes.
  func forkRefreshPlayHeader() {
    guard let header = tableView.tableHeaderView as? ListPlayHeaderView else { return }
    header.refresh()
    header.isHidden = singleFetchedResultsController?.fetchedObjects?.isEmpty ?? true
  }

  private func forkPlayContext(isShuffled: Bool) async -> PlayContext? {
    guard let artistsMO = singleFetchedResultsController?.fetchedObjects,
          !artistsMO.isEmpty else { return nil }
    let picked = isShuffled ? artistsMO[randomPick: Self.forkArtistPickCount] : Array(
      artistsMO.prefix(Self.forkArtistPickCount)
    )
    let groups = picked.map { Artist(managedObject: $0).albums }
    let albums = isShuffled ? ListPlayContextBuilder.randomAlbums(of: groups) : ListPlayContextBuilder
      .albumsInOrder(of: groups)
    return await ListPlayContextBuilder.context(
      name: sceneTitle ?? "Artists",
      albums: albums,
      account: account
    )
  }
}
