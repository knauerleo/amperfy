//
//  ForkLibraryVC.swift
//  Amperfy
//
//  Fork: Library as a grid (design phase 5, measure 12). Filter chips on top (Playlists, Albums,
//  Artists, Downloads), "Favorite Songs" pinned as the first tile, recently used entries first.
//  The chip "Downloads" shows the Songpicker jobs (YouTube Music downloads).
//  The original category list (LibraryVC) stays reachable through the list button.
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

// MARK: - LibraryFilter

enum LibraryFilter: CaseIterable, Hashable {
  case playlists
  case albums
  case artists
  case downloads

  var title: String {
    switch self {
    case .playlists: String(localized: "Playlists", table: "Fork")
    case .albums: String(localized: "Albums", table: "Fork")
    case .artists: String(localized: "Artists", table: "Fork")
    case .downloads: String(localized: "Downloads", table: "Fork")
    }
  }

  /// Category with the complete, sortable list.
  var displayType: LibraryDisplayType {
    switch self {
    case .playlists: .playlists
    case .albums: .albums
    case .artists: .artists
    case .downloads: .downloads
    }
  }
}

// MARK: - LibraryGridEntry

/// A library entity in the grid, identified by its object ID.
struct LibraryGridEntry: Hashable, @unchecked Sendable {
  let objectID: NSManagedObjectID
  let container: PlayableContainable

  init?(_ container: PlayableContainable) {
    guard let objectID = (container as? AbstractLibraryEntity)?.objectID
      ?? (container as? Playlist)?.managedObject.objectID
    else { return nil }
    self.objectID = objectID
    self.container = container
  }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.objectID == rhs.objectID }
  func hash(into hasher: inout Hasher) { hasher.combine(objectID) }
}

// MARK: - ForkLibraryVC

@MainActor
final class ForkLibraryVC: UICollectionViewController {
  enum Section: Hashable {
    case chips
    case pinned
    case browse
    case showAll
    case grid
    case jobs
    case jobsInfo
    case deviceDownloads
  }

  // only used on the main actor, like HomeCellItem
  enum Item: Hashable, @unchecked Sendable {
    case chip(LibraryFilter)
    case favoriteSongs
    case entity(LibraryGridEntry)
    case category(LibraryDisplayType)
    case showAll(LibraryFilter)
    case job(String)
    case message(String)
    case deviceDownloads
  }

  private static let recentCount = 7
  private static let gridLimit = 150

  private let account: Account
  private var filter: LibraryFilter?
  private var jobEntries = [String: YouTubeMusicJobEntry]()
  private var isObservingJobs = false
  private var userButton: UIButton?
  private var userBarButtonItem: UIBarButtonItem?
  private var accountNotificationHandler: AccountNotificationHandler?
  private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

  init(account: Account) {
    self.account = account
    super.init(collectionViewLayout: UICollectionViewFlowLayout())
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var sceneTitle: String? { String(localized: "Library", table: "Fork") }

  private var monitor: YouTubeMusicJobMonitor { .shared }
  private var onlyCached: Bool { appDelegate.storage.settings.user.isOfflineMode }

  // MARK: Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    monitor.configure(backendApi: appDelegate.getMeta(account.info).backendApi)
    title = String(localized: "Library", table: "Fork")
    navigationController?.navigationBar.prefersLargeTitles = true
    collectionView.backgroundColor = ForkSurface.background
    collectionView.collectionViewLayout = createLayout()
    configureDataSource()
    configureNavigationItems()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(jobsChanged),
      name: .youTubeMusicStatusChanged,
      object: nil
    )
    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForActiveAccountChange { [weak self] _ in
      guard let self else { return }
      setupUserNavButton(
        currentAccount: account,
        userButton: &userButton,
        userBarButtonItem: &userBarButtonItem
      )
    }
    applySnapshot(animated: false)
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
    applySnapshot(animated: false)
    updateJobObservation()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    setJobObservation(false)
  }

  private func configureNavigationItems() {
    let allCategories = UIBarButtonItem(
      image: UIImage(systemName: "list.bullet"),
      primaryAction: UIAction { [weak self] _ in self?.showAllCategories() }
    )
    allCategories.accessibilityLabel = String(localized: "All Categories", table: "Fork")
    // F-13: listening statistics and year in review
    let stats = UIBarButtonItem(
      image: UIImage(systemName: "chart.bar.xaxis"),
      primaryAction: UIAction { [weak self] _ in self?.showListeningStats() }
    )
    stats.accessibilityLabel = String(localized: "Your Stats", table: "Fork")
    navigationItem.rightBarButtonItems = [allCategories, stats]
  }

  private func showListeningStats() {
    navigationController?.pushViewController(ListeningStatsVC(account: account), animated: true)
  }

  /// The original category list, including editing which categories are shown.
  private func showAllCategories() {
    let libraryVC = AppStoryboard.Main.segueToLibraryList(account: account)
    navigationController?.pushViewController(libraryVC, animated: true)
  }

  // MARK: Job polling

  private func updateJobObservation() {
    setJobObservation(filter == .downloads && viewIfLoaded?.window != nil)
  }

  /// Polls `getYtJobs` only while the overview is visible (running tracked jobs poll anyway).
  private func setJobObservation(_ isOn: Bool) {
    let shouldObserve = isOn && SongpickerConfig.isEnabled
    guard shouldObserve != isObservingJobs else { return }
    isObservingJobs = shouldObserve
    if shouldObserve {
      monitor.startObserving()
    } else {
      monitor.stopObserving()
    }
  }

  @objc
  private func jobsChanged() {
    guard filter == .downloads else { return }
    applySnapshot(animated: true)
  }

  // MARK: Layout

  private func createLayout() -> UICollectionViewLayout {
    let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
      guard let self,
            let section = dataSource?.sectionIdentifier(for: sectionIndex)
      else { return ShelfLayout.section(.tileGrid(columns: 2), withHeader: false) }
      switch section {
      case .chips:
        return Self.chipsSection()
      case .pinned:
        return ShelfLayout.section(.tileGrid(columns: 2), withHeader: false)
      case .browse:
        return ShelfLayout.section(.tileGrid(columns: 2), withHeader: true)
      case .grid:
        return Self.coverGridSection(columns: filter == .artists ? 3 : 2)
      case .showAll, .jobsInfo, .deviceDownloads:
        return Self.listSection(environment: environment, withHeader: false)
      case .jobs:
        return Self.listSection(environment: environment, withHeader: true)
      }
    }
    return layout
  }

  private static func chipsSection() -> NSCollectionLayoutSection {
    let size = NSCollectionLayoutSize(
      widthDimension: .estimated(90),
      heightDimension: .absolute(FilterChipCell.height)
    )
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: size,
      subitems: [NSCollectionLayoutItem(layoutSize: size)]
    )
    let section = NSCollectionLayoutSection(group: group)
    section.orthogonalScrollingBehavior = .continuous
    section.interGroupSpacing = DS.Space.xs
    section.contentInsets = NSDirectionalEdgeInsets(
      top: DS.Space.xxs,
      leading: DS.Space.m,
      bottom: DS.Space.m,
      trailing: DS.Space.m
    )
    return section
  }

  /// Vertical grid of big covers (albums, playlists) or round artist images.
  private static func coverGridSection(columns: Int) -> NSCollectionLayoutSection {
    let estimatedHeight: CGFloat = columns == 2 ? 230 : 150
    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
      heightDimension: .estimated(estimatedHeight)
    ))
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .estimated(estimatedHeight)
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

  private static func listSection(
    environment: NSCollectionLayoutEnvironment,
    withHeader: Bool
  )
    -> NSCollectionLayoutSection {
    var config = UICollectionLayoutListConfiguration(appearance: .plain)
    config.backgroundColor = ForkSurface.background
    config.headerMode = withHeader ? .supplementary : .none
    let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
    if withHeader {
      let header = ShelfLayout.header()
      header.contentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: DS.Space.m,
        bottom: 0,
        trailing: DS.Space.m
      )
      section.boundarySupplementaryItems = [header]
    }
    return section
  }

  // MARK: Cells

  private func configureDataSource() {
    let chipRegistration = UICollectionView.CellRegistration<FilterChipCell, LibraryFilter> {
      [weak self] cell, _, chip in
      cell.display(title: chip.title, isSelected: self?.filter == chip)
    }
    let tileRegistration = UICollectionView.CellRegistration<TileCollectionCell, Item> {
      cell, _, item in
      switch item {
      case .favoriteSongs:
        cell.display(title: String(localized: "Favorite Songs", table: "Fork"), generatedArtwork: GradientArtworkView.favoriteSongs())
      case let .entity(entry):
        cell.display(container: entry.container)
      case let .category(type):
        cell.display(
          title: ForkMenuText.upstream(type.displayName),
          generatedArtwork: GradientArtworkView(
            colors: [UIColor.systemGray2, UIColor.systemGray4],
            symbol: type.image
          )
        )
      default:
        break
      }
    }
    let albumRegistration = UICollectionView.CellRegistration<LargeAlbumCell, LibraryGridEntry> {
      cell, _, entry in
      cell.display(container: entry.container)
    }
    let artistRegistration = UICollectionView
      .CellRegistration<ArtistCircleCell, LibraryGridEntry> { cell, _, entry in
        cell.display(container: entry.container)
      }
    let jobRegistration = UICollectionView.CellRegistration<DownloadJobCell, String> {
      [weak self] cell, _, videoId in
      guard let self, let entry = jobEntries[videoId] else { return }
      cell.display(entry: entry)
      cell.onRetry = { [weak self] in self?.retry(videoId: videoId) }
      cell.configurationUpdateHandler = { cell, state in
        cell.backgroundConfiguration = ForkSurface.listCellBackground(for: state)
      }
    }
    let rowRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
      cell, _, item in
      var content = UIListContentConfiguration.cell()
      content.textProperties.font = DS.Font.rowTitle
      cell.accessories = []
      cell.configurationUpdateHandler = { cell, state in
        cell.backgroundConfiguration = ForkSurface.listCellBackground(for: state)
      }
      switch item {
      case let .showAll(filter):
        content.text = String(localized: "All \(filter.title)", table: "Fork")
        content.secondaryText = String(localized: "Sort, filter and search", table: "Fork")
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "line.3.horizontal.decrease")
        cell.accessories = [.disclosureIndicator()]
      case .deviceDownloads:
        content.text = String(localized: "Downloaded on This Device", table: "Fork")
        content.image = UIImage(systemName: "arrow.down.circle")
        cell.accessories = [.disclosureIndicator()]
      case let .message(text):
        content = UIListContentConfiguration.cell()
        content.text = text
        content.textProperties.color = .secondaryLabel
        content.textProperties.font = DS.Font.cellSubtitle
        content.textProperties.numberOfLines = 0
      default:
        break
      }
      content.imageProperties.tintColor = .label
      cell.contentConfiguration = content
    }

    dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
      [weak self] collectionView, indexPath, item in
      switch item {
      case let .chip(chip):
        return collectionView.dequeueConfiguredReusableCell(
          using: chipRegistration, for: indexPath, item: chip
        )
      case .favoriteSongs, .category:
        return collectionView.dequeueConfiguredReusableCell(
          using: tileRegistration, for: indexPath, item: item
        )
      case let .entity(entry):
        let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
        if section == .pinned {
          return collectionView.dequeueConfiguredReusableCell(
            using: tileRegistration, for: indexPath, item: item
          )
        } else if entry.container is Artist {
          return collectionView.dequeueConfiguredReusableCell(
            using: artistRegistration, for: indexPath, item: entry
          )
        }
        return collectionView.dequeueConfiguredReusableCell(
          using: albumRegistration, for: indexPath, item: entry
        )
      case let .job(videoId):
        return collectionView.dequeueConfiguredReusableCell(
          using: jobRegistration, for: indexPath, item: videoId
        )
      case .showAll, .message, .deviceDownloads:
        return collectionView.dequeueConfiguredReusableCell(
          using: rowRegistration, for: indexPath, item: item
        )
      }
    }

    let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
      elementKind: UICollectionView.elementKindSectionHeader
    ) { [weak self] header, _, indexPath in
      switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
      case .browse: header.title = String(localized: "Browse", table: "Fork")
      case .jobs: header.title = "YouTube Music"
      default: header.title = nil
      }
      header.showsRefreshButton = false
    }
    dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
      collectionView.dequeueConfiguredReusableSupplementary(
        using: headerRegistration,
        for: indexPath
      )
    }
  }

  // MARK: Snapshot

  private func applySnapshot(animated: Bool) {
    guard dataSource != nil else { return }
    var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
    snapshot.appendSections([.chips])
    snapshot.appendItems(LibraryFilter.allCases.map { .chip($0) }, toSection: .chips)

    let library = appDelegate.storage.main.library
    switch filter {
    case .none:
      let recent = library.getRecentlyPlayedContainers(
        for: account,
        count: Self.recentCount,
        onlyCached: onlyCached
      ).compactMap(LibraryGridEntry.init)
      snapshot.appendSections([.pinned])
      snapshot.appendItems([.favoriteSongs] + recent.map { .entity($0) }, toSection: .pinned)
      let shown: Set<LibraryDisplayType> = [
        .playlists, .albums, .artists, .downloads, .favoriteSongs,
      ]
      let categories = appDelegate.storage.settings.accounts.getSetting(account.info).read
        .libraryDisplaySettings.inUse
        .filter { !shown.contains($0) }
      if !categories.isEmpty {
        snapshot.appendSections([.browse])
        snapshot.appendItems(categories.map { .category($0) }, toSection: .browse)
      }
    case .albums, .artists, .playlists:
      let entries: [LibraryGridEntry]
      switch filter {
      case .albums:
        entries = library.getLibraryGridAlbums(
          for: account,
          limit: Self.gridLimit,
          onlyCached: onlyCached
        ).compactMap(LibraryGridEntry.init)
      case .artists:
        entries = library.getLibraryGridArtists(
          for: account,
          limit: Self.gridLimit,
          onlyCached: onlyCached
        ).compactMap(LibraryGridEntry.init)
      default:
        entries = library.getLibraryGridPlaylists(
          for: account,
          limit: Self.gridLimit,
          onlyCached: onlyCached
        ).compactMap(LibraryGridEntry.init)
      }
      if let filter {
        snapshot.appendSections([.showAll])
        snapshot.appendItems([.showAll(filter)], toSection: .showAll)
      }
      if entries.isEmpty {
        snapshot.appendSections([.jobsInfo])
        snapshot.appendItems([.message(String(localized: "Nothing here yet.", table: "Fork"))], toSection: .jobsInfo)
      } else {
        snapshot.appendSections([.grid])
        snapshot.appendItems(entries.map { .entity($0) }, toSection: .grid)
      }
    case .downloads:
      appendDownloads(to: &snapshot)
    }

    // the chips show their selection, the job rows their state
    snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .chips))
    if snapshot.indexOfSection(.jobs) != nil {
      let current = Set(dataSource.snapshot().itemIdentifiers)
      snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .jobs).filter {
        current.contains($0)
      })
    }
    dataSource.apply(snapshot, animatingDifferences: animated)
  }

  private func appendDownloads(to snapshot: inout NSDiffableDataSourceSnapshot<Section, Item>) {
    var message: String?
    if !SongpickerConfig.isEnabled {
      jobEntries = [:]
      message = String(localized: "YouTube Music is turned off. You can turn it on in Settings › YouTube Music.", table: "Fork")
    } else {
      let entries = monitor.jobList
      jobEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.videoId, $0) })
      if !entries.isEmpty {
        snapshot.appendSections([.jobs])
        snapshot.appendItems(entries.map { .job($0.videoId) }, toSection: .jobs)
      } else if let error = monitor.lastError {
        message = String(localized: "Downloads are not available (\(error)).", table: "Fork")
      } else if !monitor.hasLoadedJobs {
        message = String(localized: "Loading downloads…", table: "Fork")
      } else {
        message = String(localized: "No YouTube Music downloads yet. Songs you play or add from the YouTube Music results in Search show up here.", table: "Fork")
      }
    }
    if let message {
      snapshot.appendSections([.jobsInfo])
      snapshot.appendItems([.message(message)], toSection: .jobsInfo)
    }
    snapshot.appendSections([.deviceDownloads])
    snapshot.appendItems([.deviceDownloads], toSection: .deviceDownloads)
  }

  // MARK: Selection

  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)
    guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
    switch item {
    case let .chip(chip):
      DS.haptic(.selection)
      filter = (filter == chip) ? nil : chip
      updateJobObservation()
      applySnapshot(animated: false)
      // the grid has 2 columns for albums and playlists, 3 for artists
      collectionView.collectionViewLayout.invalidateLayout()
      collectionView.setContentOffset(
        CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
        animated: false
      )
    case .favoriteSongs:
      push(AppStoryboard.Main.segueToFavoriteSongs(account: account))
    case let .entity(entry):
      open(entry.container)
    case let .category(type):
      push(type.controller(account: account, settings: appDelegate.storage.settings))
    case let .showAll(filter):
      push(filter.displayType.controller(account: account, settings: appDelegate.storage.settings))
    case .deviceDownloads:
      push(LibraryDisplayType.downloads.controller(
        account: account,
        settings: appDelegate.storage.settings
      ))
    case let .job(videoId):
      if jobEntries[videoId]?.isRetryable == true {
        retry(videoId: videoId)
      }
    case .message:
      break
    }
  }

  private func open(_ container: PlayableContainable) {
    if let album = container as? Album {
      push(AppStoryboard.Main.segueToAlbumDetail(account: account, album: album))
    } else if let artist = container as? Artist {
      push(AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist))
    } else if let playlist = container as? Playlist {
      push(AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist))
    }
  }

  private func push(_ vc: UIViewController) {
    navigationController?.navigationBar.prefersLargeTitles = false
    navigationController?.pushViewController(vc, animated: true)
  }

  private func retry(videoId: String) {
    DS.haptic(.light)
    Task { @MainActor in
      do {
        try await monitor.retry(videoId: videoId)
      } catch {
        DS.haptic(.error)
        appDelegate.eventLogger.report(topic: "YouTube Music Retry", error: error)
      }
    }
  }

  // MARK: Context menu

  override func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    guard case let .entity(entry) = dataSource.itemIdentifier(for: indexPath) else { return nil }
    let containable = entry.container
    let identifier = NSString(string: TableViewPreviewInfo(
      playableContainerIdentifier: containable.containerIdentifier,
      indexPath: indexPath
    ).asJSONString())
    return UIContextMenuConfiguration(identifier: identifier, previewProvider: {
      let vc = EntityPreviewVC()
      vc.display(container: containable, on: self)
      Task { @MainActor in
        do {
          try await containable.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Preview Sync", error: error)
        }
        vc.refresh()
      }
      return vc
    }) { _ in
      EntityPreviewActionBuilder(
        container: containable,
        on: self,
        playContextCb: { PlayContext(containable: containable) }
      ).createMenu()
    }
  }

  override func collectionView(
    _ collectionView: UICollectionView,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating
  ) {
    animator.addCompletion {
      if let identifier = configuration.identifier as? String,
         let previewInfo = TableViewPreviewInfo.create(fromIdentifier: identifier),
         let containerIdentifier = previewInfo.playableContainerIdentifier,
         let container = self.appDelegate.storage.main.library
         .getContainer(identifier: containerIdentifier) {
        EntityPreviewActionBuilder(container: container, on: self).performPreviewTransition()
      }
    }
  }
}
