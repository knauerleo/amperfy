//
//  HomeVC+Fork.swift
//  Amperfy
//
//  Fork: design phase 3 of Home. A shelf style per section (tile grid, large albums,
//  round artists, stock shelf), the Favorite Songs tile, skeletons while sections load,
//  one-tap play in the Recently Played grid and an empty state with an action.
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
import CoreData
import UIKit

// MARK: - HomeCellItem

enum HomeCellItem: Hashable, @unchecked Sendable {
  case entity(HomeItem)
  /// Fixed first tile of the Recently Played grid.
  case favoriteSongs
  case skeleton(section: HomeSection, index: Int)
  /// F-11: tile of the Decades section, opens DecadeAlbumsVC.
  case decade(AlbumDecade)
  /// F-12: tile of Made for You, plays the mix.
  case mix(HomeMix)

  var containable: PlayableContainable? {
    if case let .entity(homeItem) = self { return homeItem.playableContainable }
    return nil
  }
}

extension HomeSection {
  var shelfStyle: ShelfStyle {
    switch self {
    case .recentlyPlayed: return .tileGrid(columns: 2)
    case .recentlyAdded: return .large
    case .mixes: return .large
    case .randomArtists: return .circle
    default: return .standard
    }
  }
}

extension GradientArtworkView {
  /// F-11: one hue per decade, the 60s and 2010s are apart on the color wheel.
  static func decade(_ decade: AlbumDecade) -> GradientArtworkView {
    let hue = CGFloat((decade.startYear / 10) % 10) * 0.13 + 0.55
    return GradientArtworkView(colors: colors(hue: hue), text: decade.shortTitle)
  }
}

// MARK: - HomeVC

extension HomeVC {
  /// Grid of 2 × 3: Favorite Songs plus the five latest entries.
  private static let recentlyPlayedTileCount = 5

  func configureForkLayout() {
    collectionView.register(
      TileCollectionCell.self,
      forCellWithReuseIdentifier: TileCollectionCell.reuseID
    )
    collectionView.register(
      LargeAlbumCell.self,
      forCellWithReuseIdentifier: LargeAlbumCell.reuseID
    )
    collectionView.register(
      ArtistCircleCell.self,
      forCellWithReuseIdentifier: ArtistCircleCell.reuseID
    )
    let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
      MainActor.assumeIsolated {
        let section = self?.dataSource.sectionIdentifier(for: sectionIndex)
        return ShelfLayout.section(section?.shelfStyle ?? .standard)
      }
    }
    collectionView.setCollectionViewLayout(layout, animated: false)
  }

  // MARK: Cells

  func forkCell(
    _ collectionView: UICollectionView,
    indexPath: IndexPath,
    item: HomeCellItem
  )
    -> UICollectionViewCell {
    let style = dataSource.sectionIdentifier(for: indexPath.section)?.shelfStyle ?? .standard
    switch (item, style) {
    case let (.decade(decade), _):
      let cell = dequeue(LargeAlbumCell.self, LargeAlbumCell.reuseID, indexPath)
      cell.display(
        title: decade.title,
        subtitle: decade.albumCount == 1 ? "1 Album" : "\(decade.albumCount) Albums",
        generatedArtwork: GradientArtworkView.decade(decade)
      )
      return cell
    case let (.mix(mix), _):
      let cell = dequeue(LargeAlbumCell.self, LargeAlbumCell.reuseID, indexPath)
      cell.display(
        title: mix.title,
        subtitle: mix.subtitle,
        generatedArtwork: GradientArtworkView.mix(mix)
      )
      return cell
    case (.favoriteSongs, _):
      let cell = dequeue(TileCollectionCell.self, TileCollectionCell.reuseID, indexPath)
      cell.display(title: "Favorite Songs", generatedArtwork: GradientArtworkView.favoriteSongs())
      return cell
    case (.skeleton, .tileGrid):
      let cell = dequeue(TileCollectionCell.self, TileCollectionCell.reuseID, indexPath)
      cell.displaySkeleton()
      return cell
    case (.skeleton, .circle):
      let cell = dequeue(ArtistCircleCell.self, ArtistCircleCell.reuseID, indexPath)
      cell.displaySkeleton()
      return cell
    case (.skeleton, _):
      // sizes itself from the shelf width, so it fits the stock shelf too
      let cell = dequeue(LargeAlbumCell.self, LargeAlbumCell.reuseID, indexPath)
      cell.displaySkeleton()
      return cell
    case let (.entity(homeItem), .tileGrid):
      let cell = dequeue(TileCollectionCell.self, TileCollectionCell.reuseID, indexPath)
      cell.display(container: homeItem.playableContainable)
      return cell
    case let (.entity(homeItem), .circle):
      let cell = dequeue(ArtistCircleCell.self, ArtistCircleCell.reuseID, indexPath)
      cell.display(container: homeItem.playableContainable)
      return cell
    case let (.entity(homeItem), .large):
      let cell = dequeue(LargeAlbumCell.self, LargeAlbumCell.reuseID, indexPath)
      cell.display(container: homeItem.playableContainable)
      return cell
    case let (.entity(homeItem), .standard):
      let cell = dequeue(AlbumCollectionCell.self, AlbumCollectionCell.typeName, indexPath)
      cell.display(
        container: homeItem.playableContainable,
        rootView: self,
        itemWidth: Self.itemWidth,
        initialIndexPath: indexPath
      )
      return cell
    }
  }

  private func dequeue<Cell: UICollectionViewCell>(
    _ type: Cell.Type,
    _ reuseID: String,
    _ indexPath: IndexPath
  )
    -> Cell {
    collectionView.dequeueReusableCell(withReuseIdentifier: reuseID, for: indexPath) as! Cell
  }

  // MARK: Snapshot

  func applyForkSnapshot(animated: Bool) {
    var snapshot = NSDiffableDataSourceSnapshot<HomeSection, HomeCellItem>()
    var hasContent = false
    var isAnyLoading = false
    for section in sharedHome.orderedVisibleSections {
      // Ids are stable per entity, so a repeated entity would be a duplicate identifier (assert).
      var seenIds = Set<String>()
      var entities = (sharedHome.data[section] ?? []).filter { seenIds.insert($0.id).inserted }
      if section == .recentlyPlayed {
        entities = Array(entities.prefix(Self.recentlyPlayedTileCount))
      }
      var items = entities.map { HomeCellItem.entity($0) }
      if section == .decades {
        items = sharedHome.forkDecades.map { HomeCellItem.decade($0) }
        hasContent = hasContent || !items.isEmpty
      } else if section == .mixes {
        items = sharedHome.forkMixes.map { HomeCellItem.mix($0) }
        hasContent = hasContent || !items.isEmpty
      }
      if items.isEmpty, sharedHome.isLoading(section) {
        isAnyLoading = true
        let count = section == .recentlyPlayed
          ? Self.recentlyPlayedTileCount
          : section.shelfStyle.skeletonCount
        items = (0 ..< count).map { HomeCellItem.skeleton(section: section, index: $0) }
      }
      if section == .recentlyPlayed {
        items.insert(.favoriteSongs, at: 0)
      } else if items.isEmpty {
        // loaded but empty: no lonely header
        continue
      }
      hasContent = hasContent || !entities.isEmpty
      snapshot.appendSections([section])
      snapshot.appendItems(items, toSection: section)
    }
    let showsEmptyState = !hasContent && !isAnyLoading
    if showsEmptyState {
      // the Favorite Songs tile alone is not a Home
      snapshot = NSDiffableDataSourceSnapshot<HomeSection, HomeCellItem>()
    }

    let oldFingerprints = Dictionary(
      dataSource.snapshot().itemIdentifiers.compactMap { item -> (String, [NSManagedObjectID])? in
        guard case let .entity(homeItem) = item else { return nil }
        return (homeItem.id, homeItem.artworkFingerprint)
      }
    ) { first, _ in first }
    let changedItems = snapshot.itemIdentifiers.filter {
      guard case let .entity(homeItem) = $0, let old = oldFingerprints[homeItem.id] else {
        return false
      }
      return old != homeItem.artworkFingerprint
    }
    snapshot.reconfigureItems(changedItems)
    dataSource.apply(snapshot, animatingDifferences: animated)
    updateEmptyState(isShown: showsEmptyState)
  }

  // MARK: Empty state

  private func updateEmptyState(isShown: Bool) {
    guard isShown else {
      contentUnavailableConfiguration = nil
      return
    }
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: "music.note.house")
    config.text = "Nothing here yet"
    if sharedHome.orderedVisibleSections.isEmpty {
      config.secondaryText = "All Home sections are hidden."
      config.button = .filled()
      config.button.title = "Edit Home"
      config.buttonProperties.primaryAction = UIAction { [weak self] _ in
        self?.presentSectionEditor()
      }
    } else if sharedHome.isOfflineMode {
      config.secondaryText = "Offline mode only shows downloaded music. Download albums or playlists to see them here."
    } else {
      config.secondaryText = "Sync your library to see what you played recently, new albums and more."
      config.button = .filled()
      config.button.title = "Sync Library"
      config.buttonProperties.primaryAction = UIAction { [weak self] _ in
        DS.haptic(.light)
        self?.sharedHome.syncLibraryForHome()
      }
    }
    contentUnavailableConfiguration = config
  }

  // MARK: Selection

  /// Returns true when the tap was handled here. Albums and playlists in the Recently Played grid
  /// start playing right away, artists and everything else open as before.
  func handleForkSelection(at indexPath: IndexPath) -> Bool {
    guard let item = dataSource.itemIdentifier(for: indexPath) else { return true }
    switch item {
    case .skeleton:
      return true
    case let .decade(decade):
      navigationController?.pushViewController(
        DecadeAlbumsVC(account: account, decade: decade),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
      return true
    case let .mix(mix):
      playMix(mix)
      return true
    case .favoriteSongs:
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToFavoriteSongs(account: account),
        animated: true
      )
      navigationController?.navigationBar.prefersLargeTitles = false
      return true
    case let .entity(homeItem):
      guard dataSource.sectionIdentifier(for: indexPath.section) == .recentlyPlayed else {
        return false
      }
      let container = homeItem.playableContainable
      guard container is Album || container is Playlist else { return false }
      playFromTile(container)
      return true
    }
  }

  private func playMix(_ mix: HomeMix) {
    DS.haptic(.light)
    Task { @MainActor in
      let playables = await sharedHome.songsToPlay(mix)
      guard !playables.isEmpty else {
        DS.haptic(.error)
        return
      }
      appDelegate.player.play(context: PlayContext(name: mix.title, playables: playables))
    }
  }

  private func playFromTile(_ container: PlayableContainable) {
    DS.haptic(.light)
    Task { @MainActor in
      let isOfflineMode = appDelegate.storage.settings.user.isOfflineMode
      let needsFetch: Bool
      if let album = container as? Album {
        needsFetch = !album.isSongsMetaDataSynced
      } else {
        needsFetch = container.playables.isEmpty
      }
      if needsFetch {
        do {
          try await container.fetch(
            storage: appDelegate.storage,
            librarySyncer: appDelegate.getMeta(account.info).librarySyncer,
            playableDownloadManager: appDelegate.getMeta(account.info).playableDownloadManager
          )
        } catch {
          appDelegate.eventLogger.report(topic: "Home Play", error: error)
        }
      }
      let playables = container.playables.filterCached(dependigOn: isOfflineMode)
      guard !playables.isEmpty else {
        DS.haptic(.error)
        return
      }
      appDelegate.player.play(context: PlayContext(containable: container, playables: playables))
    }
  }
}
