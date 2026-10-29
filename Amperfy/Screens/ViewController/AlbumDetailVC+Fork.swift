//
//  AlbumDetailVC+Fork.swift
//  Amperfy
//
//  Fork (TASKS F-5): "Similar on YouTube Music" below the songs of an album, from the similar
//  artists of the album artist (see YouTubeMusicSuggestions). Only online and with YouTube Music on.
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

extension AlbumDetailVC {
  func forkLoadYouTubeShelf() {
    let artistName = album.artist?.name ?? album.subtitle ?? ""
    let artistId = album.artist?.id
    let meta = appDelegate.getMeta(account.info)
    Task { @MainActor in
      let songs = await YouTubeMusicSuggestions.similarSongs(
        artistName: artistName,
        artistId: artistId,
        account: self.account,
        storage: self.appDelegate.storage,
        backendApi: meta.backendApi,
        librarySyncer: meta.librarySyncer
      )
      guard !songs.isEmpty, self.isViewLoaded else { return }
      self.forkShowYouTubeShelf(songs: songs)
    }
  }

  private func forkShowYouTubeShelf(songs: [Song]) {
    let shelf = YouTubeMusicShelfView(
      songs: songs,
      contextName: "\(album.name): \(YouTubeMusicShelfView.title)"
    )
    shelf.translatesAutoresizingMaskIntoConstraints = false
    let footer = UIView()
    footer.addSubview(shelf)
    NSLayoutConstraint.activate([
      shelf.topAnchor.constraint(equalTo: footer.topAnchor, constant: DS.Space.l),
      shelf.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -DS.Space.l),
      shelf.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: DS.Space.m),
      shelf.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -DS.Space.m),
    ])
    let width = tableView.bounds.width
    let height = footer.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
    tableView.tableFooterView = footer
  }
}
