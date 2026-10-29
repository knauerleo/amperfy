//
//  AlbumDetailVC+Fork.swift
//  Amperfy
//
//  Fork (TASKS F-5): "Similar on YouTube Music" below the songs of an album, from the similar
//  artists of the album artist (see YouTubeMusicSuggestions). Only online and with YouTube Music on.
//  Fork (TASKS UI-23): track rows 56 pt on the iPhone.
//  Fork (TASKS F-19): above it the songs of the album that are only on YouTube Music
//  (`YouTubeAlbumGapsView`). Both load independently, the footer shows what is there.
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
  private static let footerStackTag = 0x4619

  /// UI-23: track rows 56 pt on the iPhone, other song lists keep 60 pt.
  func forkApplyAlbumRowHeight() {
    guard DS.isPhone else { return }
    tableView.rowHeight = ForkRowMetrics.albumTrackRowHeight
    tableView.estimatedRowHeight = ForkRowMetrics.albumTrackRowHeight
  }

  func forkLoadYouTubeShelf() {
    let artistName = album.artist?.name ?? album.subtitle ?? ""
    let artistId = album.artist?.id
    let meta = appDelegate.getMeta(account.info)
    Task { @MainActor in
      let gaps = await YouTubeMusicAlbumGapFinder.gaps(
        for: self.album,
        account: self.account,
        storage: self.appDelegate.storage,
        backendApi: meta.backendApi,
        librarySyncer: meta.librarySyncer
      )
      guard let gaps, !gaps.missing.isEmpty, self.isViewLoaded else { return }
      let view = YouTubeAlbumGapsView(gaps: gaps, albumArtist: artistName, account: self.account)
      self.forkAddFooterPart(view, isFirst: true)
    }
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
      let shelf = YouTubeMusicShelfView(
        songs: songs,
        contextName: "\(self.album.name): \(YouTubeMusicShelfView.title)"
      )
      let inset = UIView()
      shelf.translatesAutoresizingMaskIntoConstraints = false
      inset.addSubview(shelf)
      NSLayoutConstraint.activate([
        shelf.topAnchor.constraint(equalTo: inset.topAnchor),
        shelf.bottomAnchor.constraint(equalTo: inset.bottomAnchor),
        shelf.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: DS.Space.m),
        shelf.trailingAnchor.constraint(equalTo: inset.trailingAnchor, constant: -DS.Space.m),
      ])
      self.forkAddFooterPart(inset, isFirst: false)
    }
  }

  /// Footer with the missing songs (first) and the shelf, whichever has loaded.
  private func forkAddFooterPart(_ part: UIView, isFirst: Bool) {
    let stack: UIStackView
    if let existing = tableView.tableFooterView?.viewWithTag(Self.footerStackTag) as? UIStackView {
      stack = existing
    } else {
      stack = UIStackView()
      stack.axis = .vertical
      stack.spacing = DS.Space.l
      stack.tag = Self.footerStackTag
      stack.translatesAutoresizingMaskIntoConstraints = false
      let footer = UIView()
      footer.addSubview(stack)
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: DS.Space.l),
        stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -DS.Space.l),
        stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
      ])
      tableView.tableFooterView = footer
    }
    if isFirst {
      stack.insertArrangedSubview(part, at: 0)
    } else {
      stack.addArrangedSubview(part)
    }
    guard let footer = tableView.tableFooterView else { return }
    let width = tableView.bounds.width
    let height = footer.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
    // reassigning makes the table take the new height
    tableView.tableFooterView = footer
  }
}
