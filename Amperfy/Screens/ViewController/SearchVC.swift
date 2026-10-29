//
//  SearchVC.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
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

// MARK: - SearchSection

public enum SearchSection: Int, CaseIterable {
  case History
  case Genres // fork
  case TopHit // fork
  case Song
  case YouTube // fork
  case Artist
  case Album
  case Playlist
}

// MARK: - SearchDiffableDataSource

class SearchDiffableDataSource: UITableViewDiffableDataSource<Int, SearchItem> {
  public var searchVC: SearchVC!

  // Fork: own item type (YouTube results are no managed objects), editable rows keep the swipes
  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    true
  }

  override func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  )
    -> String? {
    switch SearchSection(rawValue: section) {
    case .History:
      if searchVC.searchHistory.isEmpty {
        return ""
      } else {
        return "Recently Searched"
      }
    case .Playlist:
      return "Playlists"
    case .Artist:
      return "Artists"
    case .Album:
      return "Albums"
    case .Song:
      return "Songs"
    case .Genres, .TopHit, .YouTube:
      return searchVC.forkTitle(for: SearchSection(rawValue: section)!)
    case .none:
      return ""
    }
  }
}

// MARK: - SearchVC

class SearchVC: BasicTableViewController {
  override var sceneTitle: String { "Search" }

  nonisolated fileprivate static let categoryItemLimit = 10
  nonisolated fileprivate static let songItemLimit = 25
  nonisolated private static let searchDebounce: Duration = .milliseconds(300)

  private var diffableDataSource: SearchDiffableDataSource?
  fileprivate var searchHistory: [SearchHistoryItem] = []
  var artists: [Artist] = []
  var albums: [Album] = []
  var playlists: [Playlist] = []
  var songs: [Song] = []
  let fork = SearchForkState()

  private var optionsButton: UIBarButtonItem = .createOptionsBarButton()
  private var userButton: UIButton?
  private var userBarButtonItem: UIBarButtonItem?
  private(set) var isSearchActive = false
  private var accountObjectId: NSManagedObjectID?
  let account: Account
  private var accountNotificationHandler: AccountNotificationHandler?
  private var searchTask: Task<Void, Never>?

  init(account: Account) {
    self.account = account
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func createDiffableDataSource() -> SearchDiffableDataSource {
    let source =
      SearchDiffableDataSource(tableView: tableView) { tableView, indexPath, item -> UITableViewCell? in
        return self.tableView(self.tableView, cellForRowAt: indexPath)
      }
    source.searchVC = self
    return source
  }

  func updateDataSource(animated: Bool) {
    guard let dataSource = tableView?.dataSource as? UITableViewDiffableDataSource<
      Int,
      SearchItem
    > else {
      assertionFailure("The data source has not implemented snapshot support while it should")
      return
    }
    var snapshot = dataSource.snapshot() as NSDiffableDataSourceSnapshot<Int, SearchItem>
    snapshot.deleteAllItems()
    snapshot.appendSections(SearchSection.allCases.compactMap { $0.rawValue })
    snapshot.appendItems(
      searchHistory.compactMap { .object($0.managedObject.objectID) },
      toSection: SearchSection.History.rawValue
    )
    snapshot.appendItems(
      artists.compactMap { .object($0.managedObject.objectID) },
      toSection: SearchSection.Artist.rawValue
    )
    snapshot.appendItems(
      albums.compactMap { .object($0.managedObject.objectID) },
      toSection: SearchSection.Album.rawValue
    )
    snapshot.appendItems(
      playlists.compactMap { .object($0.managedObject.objectID) },
      toSection: SearchSection.Playlist.rawValue
    )
    snapshot.appendItems(
      songs.compactMap { .object($0.managedObject.objectID) },
      toSection: SearchSection.Song.rawValue
    )
    forkAppendItems(to: &snapshot)
    dataSource.apply(snapshot, animatingDifferences: animated)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    /// Store the data source in an instance property to make sure it's retained.
    diffableDataSource = createDiffableDataSource()
    /// Assign the data source to your collection view.
    tableView.dataSource = diffableDataSource

    accountObjectId = account.managedObject.objectID
    forkSetup()
    searchHistory = forkLoadSearchHistory()
    updateDataSource(animated: false)
    navigationController?.navigationItem.searchBarPlacementAllowsExternalIntegration = true

    tableView.register(nibName: PlaylistTableCell.typeName)
    tableView.register(nibName: GenericTableCell.typeName)
    tableView.register(nibName: GenericTableCell.typeName)
    tableView.register(nibName: PlayableTableCell.typeName)
    tableView.sectionHeaderHeight = 0.0
    tableView.estimatedSectionHeaderHeight = 0.0
    tableView.sectionFooterHeight = 0.0
    tableView.estimatedSectionFooterHeight = 0.0
    tableView.sectionHeaderTopPadding = 0.0

    containableAtIndexPathCallback = { indexPath in
      switch SearchSection(rawValue: indexPath.section) {
      case .History:
        return self.searchHistory[indexPath.row].searchedPlayableContainable
      case .Playlist:
        return self.playlists[indexPath.row]
      case .Artist:
        return self.artists[indexPath.row]
      case .Album:
        return self.albums[indexPath.row]
      case .Song:
        return self.songs[indexPath.row]
      case .Genres, .TopHit, .YouTube:
        return self.forkContainable(at: indexPath)
      case .none:
        return nil
      }
    }
    playContextAtIndexPathCallback = { indexPath in
      switch SearchSection(rawValue: indexPath.section) {
      case .History:
        let history = self.searchHistory[indexPath.row]
        guard let container = history.searchedPlayableContainable else { return nil }
        return PlayContext(containable: container)
      case .Playlist:
        let entity = self.playlists[indexPath.row]
        return PlayContext(containable: entity)
      case .Artist:
        let entity = self.artists[indexPath.row]
        return PlayContext(containable: entity)
      case .Album:
        let entity = self.albums[indexPath.row]
        return PlayContext(containable: entity)
      case .Song:
        let entity = self.songs[indexPath.row]
        return PlayContext(containable: entity)
      case .Genres, .TopHit, .YouTube:
        return self.forkPlayContext(at: indexPath)
      case .none:
        return nil
      }
    }
    swipeCallback = { indexPath, completionHandler in
      self.determSwipeActionContext(at: indexPath) { actionContext in
        completionHandler(actionContext)
      }
    }
    updateContentUnavailable()
    accountNotificationHandler = AccountNotificationHandler(
      storage: appDelegate.storage,
      notificationHandler: appDelegate.notificationHandler
    )
    accountNotificationHandler?.registerCallbackForActiveAccountChange { [weak self] accountInfo in
      guard let self else { return }
      setupUserNavButton(
        currentAccount: account,
        userButton: &userButton,
        userBarButtonItem: &userBarButtonItem
      )
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.navigationBar.prefersLargeTitles = true
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    extendSafeAreaToAccountForMiniPlayer()
    appDelegate.userStatistics.visited(.search)
    configureSearchController(
      placeholder: "Search in \"Library\"",
      scopeButtonTitles: ["All", "Cached"]
    )
  }

  public func activateSearchBar() {
    if isViewLoaded {
      // activate searchBar
      searchController.searchBar.becomeFirstResponder()
    }
  }

  override func configureSearchController(
    placeholder: String?,
    scopeButtonTitles: [String]? = nil
  ) {
    super.configureSearchController(
      placeholder: placeholder,
      scopeButtonTitles: scopeButtonTitles
    )

    // Install the options button
    optionsButton = UIBarButtonItem.createOptionsBarButton()
    optionsButton.menu = UIMenu(children: [
      UIAction(title: "Clear Search History", image: .clear, handler: { _ in
        self.appDelegate.storage.main.library.deleteSearchHistory()
        self.appDelegate.storage.main.library.saveContext()
        self.searchHistory = []
        self.updateDataSource(animated: true)
        self.updateContentUnavailable()
      }),
    ])

    navigationItem.rightBarButtonItem = optionsButton
  }

  func determSwipeActionContext(
    at indexPath: IndexPath,
    completionHandler: @escaping (_ actionContext: SwipeActionContext?) -> ()
  ) {
    switch SearchSection(rawValue: indexPath.section) {
    case .History:
      let history = searchHistory[indexPath.row]
      guard let container = history.searchedPlayableContainable
      else { completionHandler(nil); return }
      Task { @MainActor in
        do {
          try await container.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "History Sync", error: error)
        }
        completionHandler(SwipeActionContext(containable: container))
      }
    case .Playlist:
      let playlist = playlists[indexPath.row]
      Task { @MainActor in
        do {
          try await playlist.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Playlist Sync", error: error)
        }
        completionHandler(SwipeActionContext(containable: playlist))
      }
    case .Artist:
      let artist = artists[indexPath.row]
      Task { @MainActor in
        do {
          try await artist.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Artist Sync", error: error)
        }
        completionHandler(SwipeActionContext(containable: artist))
      }
    case .Album:
      let album = albums[indexPath.row]
      Task { @MainActor in
        do {
          try await album.fetch(
            storage: self.appDelegate.storage,
            librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
            playableDownloadManager: self.appDelegate.getMeta(self.account.info)
              .playableDownloadManager
          )
        } catch {
          self.appDelegate.eventLogger.report(topic: "Album Sync", error: error)
        }
        completionHandler(SwipeActionContext(containable: album))
      }
    case .Song:
      let song = songs[indexPath.row]
      completionHandler(SwipeActionContext(containable: song))
    case .Genres, .TopHit, .YouTube:
      forkDetermSwipeActionContext(at: indexPath, completionHandler: completionHandler)
    case .none:
      completionHandler(nil)
    }
  }

  func convertCellViewToPlayContext(cell: UITableViewCell) -> PlayContext? {
    guard let indexPath = tableView.indexPath(for: cell) else { return nil }
    if SearchSection(rawValue: indexPath.section) == .Song {
      let song = songs[indexPath.row]
      return PlayContext(containable: song)
    } else if SearchSection(rawValue: indexPath.section) == .History {
      let history = searchHistory[indexPath.row]
      guard let song = history.searchedPlayableContainable as? Song else { return nil }
      return PlayContext(containable: song)
    } else if SearchSection(rawValue: indexPath.section) == .YouTube {
      return forkPlayContext(at: indexPath)
    }
    return nil
  }

  // MARK: - Table view data source

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    switch SearchSection(rawValue: indexPath.section) {
    case .History:
      let history = searchHistory[indexPath.row]
      guard let container = history.searchedPlayableContainable else { return UITableViewCell() }
      if let playlist = container as? Playlist {
        let cell: PlaylistTableCell = dequeueCell(for: tableView, at: indexPath)
        cell.display(playlist: playlist, rootView: self)
        return cell
      } else if let song = container as? Song {
        let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
        cell.display(playable: song, playContextCb: convertCellViewToPlayContext, rootView: self)
        return cell
      } else {
        let cell: GenericTableCell = dequeueCell(for: tableView, at: indexPath)
        cell.display(container: container, rootView: self)
        return cell
      }
    case .Playlist:
      let cell: PlaylistTableCell = dequeueCell(for: tableView, at: indexPath)
      let playlist = playlists[indexPath.row]
      cell.display(playlist: playlist, rootView: self)
      return cell
    case .Artist:
      let cell: GenericTableCell = dequeueCell(for: tableView, at: indexPath)
      let artist = artists[indexPath.row]
      cell.display(container: artist, rootView: self)
      return cell
    case .Album:
      let cell: GenericTableCell = dequeueCell(for: tableView, at: indexPath)
      let album = albums[indexPath.row]
      cell.display(container: album, rootView: self)
      return cell
    case .Song:
      let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
      let song = songs[indexPath.row]
      cell.display(playable: song, playContextCb: convertCellViewToPlayContext, rootView: self)
      return cell
    case .Genres, .TopHit, .YouTube:
      return forkCell(at: indexPath)
    case .none:
      return UITableViewCell()
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    switch SearchSection(rawValue: section) {
    case .History:
      return !isSearchActive ? CommonScreenOperations.tableSectionHeightLarge : 0
    case .Playlist:
      return (isSearchActive && !playlists.isEmpty) ? CommonScreenOperations
        .tableSectionHeightLarge : 0
    case .Artist:
      return (isSearchActive && !artists.isEmpty) ? CommonScreenOperations
        .tableSectionHeightLarge : 0
    case .Album:
      return (isSearchActive && !albums.isEmpty) ? CommonScreenOperations
        .tableSectionHeightLarge : 0
    case .Song:
      return (isSearchActive && !songs.isEmpty) ? CommonScreenOperations.tableSectionHeightLarge : 0
    case .Genres, .TopHit, .YouTube:
      return forkHeaderHeight(for: SearchSection(rawValue: section)!)
    case .none:
      return 0.0
    }
  }

  override func tableView(
    _ tableView: UITableView,
    heightForRowAt indexPath: IndexPath
  )
    -> CGFloat {
    switch SearchSection(rawValue: indexPath.section) {
    case .History:
      let history = searchHistory[indexPath.row]
      guard let container = history.searchedPlayableContainable else { return 0.0 }
      if container is Playlist {
        return PlaylistTableCell.rowHeight
      } else if container is Song {
        return PlayableTableCell.rowHeight
      } else {
        return GenericTableCell.rowHeight
      }
    case .Playlist:
      return PlaylistTableCell.rowHeight
    case .Artist:
      return GenericTableCell.rowHeight
    case .Album:
      return GenericTableCell.rowHeight
    case .Song:
      return PlayableTableCell.rowHeight
    case .Genres, .TopHit, .YouTube:
      return forkRowHeight(at: indexPath)
    case .none:
      return 0.0
    }
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    switch SearchSection(rawValue: indexPath.section) {
    case .History:
      let history = searchHistory[indexPath.row]
      guard let container = history.searchedPlayableContainable else { break }
      let _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: container)
      if !(container is Song) {
        EntityPreviewActionBuilder(container: container, on: self).performPreviewTransition()
      }
    case .Playlist:
      let playlist = playlists[indexPath.row]
      let _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: playlist)
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
        animated: true
      )
    case .Artist:
      let artist = artists[indexPath.row]
      let _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: artist)
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
        animated: true
      )
    case .Album:
      let album = albums[indexPath.row]
      let _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: album)
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
        animated: true
      )
    case .Song:
      let song = songs[indexPath.row]
      let _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: song)
    case .Genres, .TopHit, .YouTube:
      forkDidSelect(at: indexPath)
    case .none: break
    }
    appDelegate.storage.main.library.saveContext()
  }

  override func tableView(
    _ tableView: UITableView,
    contextMenuConfigurationForRowAt indexPath: IndexPath,
    point: CGPoint
  )
    -> UIContextMenuConfiguration? {
    // Fork: YouTube Music results have their own menu
    forkContextMenuConfiguration(at: indexPath) ?? super.tableView(
      tableView,
      contextMenuConfigurationForRowAt: indexPath,
      point: point
    )
  }

  struct SearchResultObjectContainer: Sendable {
    var artistsIDs = [NSManagedObjectID]()
    var albumsIDs = [NSManagedObjectID]()
    var playlistsIDs = [NSManagedObjectID]()
    var songsIDs = [NSManagedObjectID]()

    /// Server results first (in server order), then local results the server did not return.
    func merged(withLocal local: SearchResultObjectContainer) -> SearchResultObjectContainer {
      func merge(_ server: [NSManagedObjectID], _ local: [NSManagedObjectID], limit: Int)
        -> [NSManagedObjectID] {
        var seen = Set<NSManagedObjectID>()
        return (server + local).filter { seen.insert($0).inserted }.prefix(upToAsArray: limit)
      }
      var result = SearchResultObjectContainer()
      result.artistsIDs = merge(artistsIDs, local.artistsIDs, limit: SearchVC.categoryItemLimit)
      result.albumsIDs = merge(albumsIDs, local.albumsIDs, limit: SearchVC.categoryItemLimit)
      result.playlistsIDs = local.playlistsIDs
      result.songsIDs = merge(songsIDs, local.songsIDs, limit: SearchVC.songItemLimit)
      return result
    }
  }

  override func updateSearchResults(for searchController: UISearchController) {
    searchTask?.cancel()
    guard let searchText = searchController.searchBar.text, let accountObjectId else { return }
    guard !searchText.isEmpty else {
      isSearchActive = false
      forkReset()
      searchHistory = forkLoadSearchHistory()
      artists = []
      albums = []
      playlists = []
      songs = []
      tableView.separatorStyle = .singleLine
      updateDataSource(animated: false)
      updateContentUnavailable()
      return
    }
    let onlyCached = searchController.searchBar.isCachedScopeSelected
    searchTask = Task { @MainActor in
      do { try await Task.sleep(for: Self.searchDebounce) } catch { return }
      self.forkSearchWillStart(searchText: searchText, onlyCached: onlyCached)

      // Local results appear right away, server results replace them once all requests finished.
      guard let localResult = try? await self.searchLocally(
        searchText: searchText,
        onlyCached: onlyCached,
        accountObjectId: accountObjectId
      ), !Task.isCancelled else { return }
      self.display(searchResult: localResult)
      guard !onlyCached else { return }

      let librarySyncer = self.appDelegate.getMeta(self.account.info).librarySyncer
      async let artistsIDs = self.searchOnServer(topic: "Artists Search") {
        try await librarySyncer.searchArtists(searchText: searchText)
      }
      async let albumsIDs = self.searchOnServer(topic: "Albums Search") {
        try await librarySyncer.searchAlbums(searchText: searchText)
      }
      async let songsIDs = self.searchOnServer(topic: "Songs Search") {
        try await librarySyncer.searchSongs(searchText: searchText)
      }
      var serverResult = SearchResultObjectContainer()
      serverResult.artistsIDs = await artistsIDs
      serverResult.albumsIDs = await albumsIDs
      serverResult.songsIDs = await songsIDs
      guard !Task.isCancelled else { return }
      self.fork.isServerSearchRunning = false
      self.forkDidReceiveServerSongs(serverResult.songsIDs)
      self.display(searchResult: serverResult.merged(withLocal: localResult))
    }
  }

  private func searchOnServer(
    topic: String,
    request: @MainActor () async throws -> [NSManagedObjectID]
  ) async
    -> [NSManagedObjectID] {
    do {
      return try await request()
    } catch {
      if !Task.isCancelled {
        appDelegate.eventLogger.report(topic: topic, error: error)
      }
      return []
    }
  }

  private func searchLocally(
    searchText: String,
    onlyCached: Bool,
    accountObjectId: NSManagedObjectID
  ) async throws
    -> SearchResultObjectContainer {
    try await appDelegate.storage.async.performAndGet { asyncCompanion in
      let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
      let playlists = asyncCompanion.library.searchPlaylists(
        for: accountAsync,
        searchText: searchText,
        playlistSearchCategory: onlyCached ? .cached : .all
      )

      var result = SearchResultObjectContainer()
      result.artistsIDs = asyncCompanion.library.multiWordSearchArtists(
        for: accountAsync,
        searchText: searchText,
        onlyCached: onlyCached,
        limit: Self.categoryItemLimit
      ).compactMap { $0.managedObject.objectID }
      result.albumsIDs = asyncCompanion.library.multiWordSearchAlbums(
        for: accountAsync,
        searchText: searchText,
        onlyCached: onlyCached,
        limit: Self.categoryItemLimit
      ).compactMap { $0.managedObject.objectID }
      result.playlistsIDs = FuzzySearcher.findBestMatch(in: playlists, search: searchText)
        .prefix(upToAsArray: Self.categoryItemLimit)
        .compactMap { $0 as? Playlist }
        .compactMap { $0.managedObject.objectID }
      result.songsIDs = asyncCompanion.library.multiWordSearchSongs(
        for: accountAsync,
        searchText: searchText,
        onlyCached: onlyCached,
        limit: Self.songItemLimit
      ).compactMap { $0.managedObject.objectID }
      return result
    }
  }

  private func display(searchResult: SearchResultObjectContainer) {
    isSearchActive = true
    searchHistory = []
    artists = searchResult.artistsIDs
      .compactMap { appDelegate.storage.main.context.object(with: $0) as? ArtistMO }
      .compactMap { Artist(managedObject: $0) }
    albums = searchResult.albumsIDs
      .compactMap { appDelegate.storage.main.context.object(with: $0) as? AlbumMO }
      .compactMap { Album(managedObject: $0) }
    playlists = searchResult.playlistsIDs
      .compactMap { appDelegate.storage.main.context.object(with: $0) as? PlaylistMO }
      .compactMap { Playlist(library: appDelegate.storage.main.library, managedObject: $0) }
    songs = searchResult.songsIDs
      .compactMap { appDelegate.storage.main.context.object(with: $0) as? SongMO }
      .compactMap { Song(managedObject: $0) }
    forkDidUpdateResults()
    tableView.separatorStyle = .singleLine
    updateDataSource(animated: false)
    updateContentUnavailable()
  }

  func updateContentUnavailable() {
    if isSearchActive {
      if artists.isEmpty, albums.isEmpty, playlists.isEmpty, songs.isEmpty, !forkHasResults {
        // Fork: no "No Results" while the server or YouTube Music search still runs
        contentUnavailableConfiguration = forkIsSearching ? searchingConfig : UIContentUnavailableConfiguration.search()
      } else {
        contentUnavailableConfiguration = nil
      }
    } else {
      contentUnavailableConfiguration = (searchHistory.isEmpty && fork.genres.isEmpty) ?
        noSearchHistoryConfig : nil
    }
  }

  lazy var searchingConfig: UIContentUnavailableConfiguration = {
    var config = UIContentUnavailableConfiguration.loading()
    config.text = String(localized: "Searching…", table: "Fork")
    return config
  }()

  lazy var noSearchHistoryConfig: UIContentUnavailableConfiguration = {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .clock
    config.text = "No Search History"
    config.secondaryText = "Your search history will appear here."
    return config
  }()
}
