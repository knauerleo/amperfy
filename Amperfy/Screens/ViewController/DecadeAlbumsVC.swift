//
//  DecadeAlbumsVC.swift
//  Amperfy
//
//  Fork (F-11): albums of one decade, opened from the Decades tiles on Home. Shows the local
//  albums by year right away, online the list of `getAlbumList2 type=byYear` replaces them.
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

final class DecadeAlbumsVC: UICollectionViewController {
  private static let maxAlbumCount = 500

  private let account: Account
  private let decade: AlbumDecade
  private var albums = [Album]()

  init(account: Account, decade: AlbumDecade) {
    self.account = account
    self.decade = decade
    super.init(collectionViewLayout: Self.createLayout())
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = decade.title
    collectionView.backgroundColor = ForkSurface.background
    collectionView.register(LargeAlbumCell.self, forCellWithReuseIdentifier: LargeAlbumCell.reuseID)
    showLocalAlbums()
    loadServerAlbums()
  }

  private static func createLayout() -> UICollectionViewLayout {
    UICollectionViewCompositionalLayout { _, environment in
      // 2 columns on the iPhone, more on wider screens
      let columns = max(2, Int(environment.container.effectiveContentSize.width / 190))
      let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
        heightDimension: .estimated(230)
      ))
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1.0),
          heightDimension: .estimated(230)
        ),
        repeatingSubitem: item,
        count: columns
      )
      group.interItemSpacing = .fixed(DS.Space.s)
      let section = NSCollectionLayoutSection(group: group)
      section.interGroupSpacing = DS.Space.m
      section.contentInsets = ShelfLayout.contentInsets
      return section
    }
  }

  private var isOfflineMode: Bool {
    appDelegate.storage.settings.user.isOfflineMode
  }

  private func showLocalAlbums() {
    albums = appDelegate.storage.main.library.getAlbums(
      for: account,
      decade: decade,
      onlyCached: isOfflineMode
    )
    reload()
  }

  private func loadServerAlbums() {
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    Task { @MainActor in
      do {
        let ids = try await appDelegate.getMeta(account.info).backendApi.forkAlbumListIds(
          type: .byYear(from: decade.startYear, to: decade.endYear),
          size: Self.maxAlbumCount
        )
        let serverAlbums = appDelegate.storage.main.library.getAlbums(
          for: account,
          orderedIds: ids,
          onlyCached: false
        )
        guard !serverAlbums.isEmpty else { return }
        albums = serverAlbums
        reload()
      } catch BackendError.notSupported {
        // Ampache: the local list stays
      } catch {
        appDelegate.eventLogger.report(topic: "Decade Albums", error: error, displayPopup: false)
      }
    }
  }

  private func reload() {
    collectionView.reloadData()
    if albums.isEmpty {
      var config = UIContentUnavailableConfiguration.empty()
      config.image = UIImage(systemName: "calendar")
      config.text = "No Albums"
      config.secondaryText = isOfflineMode
        ? "Offline mode only shows downloaded albums."
        : "No albums from the \(decade.title) in your library."
      contentUnavailableConfiguration = config
    } else {
      contentUnavailableConfiguration = nil
    }
  }

  // MARK: UICollectionViewDataSource

  override func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  )
    -> Int {
    albums.count
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  )
    -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: LargeAlbumCell.reuseID,
      for: indexPath
    ) as! LargeAlbumCell
    cell.display(container: albums[indexPath.item])
    return cell
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    let album = albums[indexPath.item]
    navigationController?.pushViewController(
      AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
      animated: true
    )
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    let album = albums[indexPath.item]
    return UIContextMenuConfiguration(identifier: nil, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: album, on: self)
      return vc
    }) { _ in
      EntityPreviewActionBuilder(container: album, on: self).createMenu()
    }
  }
}
