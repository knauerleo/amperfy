//
//  SearchVC+Fork.swift
//  Amperfy
//
//  Fork (design phase 4): search start page (recently searched, genre tiles), top result,
//  loading state without "No Results" flicker and the YouTube Music section.
//  SearchVC only calls into this file through small hooks.
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
import os.log
import UIKit

// MARK: - SearchItem

/// Item identifier of the search table: library objects plus the rows that are not objects.
enum SearchItem: Hashable {
  case object(NSManagedObjectID)
  case genreGrid
  case topHit
  case youTube(String)
  case youTubeStatus
}

// MARK: - SearchTopHit

enum SearchTopHit {
  case artist(Artist)
  case album(Album)
  case song(Song)
  case youTube(SongpickerHit)

  var kindName: String {
    switch self {
    case .artist: return "Artist"
    case .album: return "Album"
    case .song, .youTube: return "Song"
    }
  }
}

// MARK: - SearchForkState

@MainActor
final class SearchForkState: NSObject {
  enum YouTubeState {
    case idle
    case loading
    case loaded
    case failed
  }

  static let historyLimit = 8
  static let genreLimit = 12
  static let youTubeLimit = 15

  weak var searchVC: SearchVC?
  var genres = [Genre]()
  var topHit: SearchTopHit?
  var topHitScore = 0.0
  var youTubeHits = [SongpickerHit]()
  /// Placeholder songs (`ytm-<videoId>`) of the shown results, keyed by video ID.
  var youTubeSongs = [String: Song]()
  /// Every result shown in this session, to follow a download that starts by playing it later.
  var knownHits = [String: SongpickerHit]()
  var youTubeState = YouTubeState.idle
  var isServerSearchRunning = false
  let log = OSLog(subsystem: "Amperfy", category: "YouTubeMusic")

  @objc
  func playerDidPlay(notification: Notification) {
    searchVC?.forkTrackCurrentlyPlaying()
  }

  @objc
  func youTubeStatusChanged(notification: Notification) {
    searchVC?.forkRefreshYouTubeStatus()
  }
}

// MARK: - SearchVC + Fork

extension SearchVC {
  private var monitor: YouTubeMusicJobMonitor { .shared }

  // MARK: Setup

  func forkSetup() {
    fork.searchVC = self
    tableView.register(SearchTopHitCell.self, forCellReuseIdentifier: SearchTopHitCell.reuseID)
    tableView.register(
      SearchGenreGridCell.self,
      forCellReuseIdentifier: SearchGenreGridCell.reuseID
    )
    tableView.register(SearchStatusCell.self, forCellReuseIdentifier: SearchStatusCell.reuseID)

    appDelegate.storage.main.library.deleteUnusedYouTubeMusicSongs(for: account)
    forkLoadGenres()

    let meta = appDelegate.getMeta(account.info)
    monitor.configure(backendApi: meta.backendApi)
    let sync = YouTubeMusicLibrarySync(
      account: account,
      storage: appDelegate.storage,
      backendApi: meta.backendApi,
      librarySyncer: meta.librarySyncer
    )
    monitor.onDownloadFinished = { hit, job in
      Task { @MainActor in
        _ = await sync.syncFinishedDownload(hit: hit, job: job)
      }
    }
    NotificationCenter.default.addObserver(
      fork,
      selector: #selector(SearchForkState.youTubeStatusChanged(notification:)),
      name: .youTubeMusicStatusChanged,
      object: nil
    )
    appDelegate.notificationHandler.register(
      fork,
      selector: #selector(SearchForkState.playerDidPlay(notification:)),
      name: .playerPlay,
      object: nil
    )
  }

  func forkLoadSearchHistory() -> [SearchHistoryItem] {
    appDelegate.storage.main.library.getSearchHistory(for: account)
      .prefix(upToAsArray: SearchForkState.historyLimit)
  }

  func forkLoadGenres() {
    fork.genres = appDelegate.storage.main.library.getGenres(for: account)
      .filter { !$0.name.isEmpty }
      .sorted {
        if $0.albumCount != $1.albumCount { return $0.albumCount > $1.albumCount }
        if $0.songCount != $1.songCount { return $0.songCount > $1.songCount }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      .prefix(upToAsArray: SearchForkState.genreLimit)
  }

  // MARK: Search flow

  /// Called after the debounce, before the local search.
  func forkSearchWillStart(searchText: String, onlyCached: Bool) {
    fork.topHit = nil
    fork.topHitScore = 0
    fork.youTubeHits = []
    fork.isServerSearchRunning = !onlyCached
    // the proxy mixes the YouTube results into the server search (search3)
    let isYouTubeSearched = !onlyCached && SongpickerConfig.isEnabled &&
      appDelegate.storage.settings.user.isOnlineMode
    fork.youTubeState = isYouTubeSearched ? .loading : .idle
  }

  /// Called with the song results of the server search, before they are displayed.
  func forkDidReceiveServerSongs(_ songIDs: [NSManagedObjectID]) {
    guard fork.youTubeState == .loading else { return }
    let placeholders = songIDs
      .compactMap { appDelegate.storage.main.context.object(with: $0) as? SongMO }
      .map { Song(managedObject: $0) }
      .filter { $0.isYouTubeMusicPlaceholder }
    forkApply(youTubePlaceholders: placeholders)
    fork.youTubeState = .loaded
  }

  /// Called when the search text is empty again.
  func forkReset() {
    fork.youTubeState = .idle
    fork.youTubeHits = []
    fork.topHit = nil
    fork.topHitScore = 0
    fork.isServerSearchRunning = false
    forkLoadGenres()
  }

  /// Called after the result arrays were set, before the snapshot is built.
  func forkDidUpdateResults() {
    // placeholders belong to the YouTube Music section only
    songs.removeAll { $0.isYouTubeMusicPlaceholder }
    forkUpdateTopHit(searchText: searchController.searchBar.text ?? "")
  }

  var forkIsSearching: Bool {
    fork.isServerSearchRunning || fork.youTubeState == .loading
  }

  var forkHasResults: Bool {
    fork.topHit != nil || !fork.youTubeHits.isEmpty
  }

  private func forkApply(youTubePlaceholders songs: [Song]) {
    var seen = Set<String>()
    var newHits = [SongpickerHit]()
    for song in songs {
      let videoId = String(song.id.dropFirst(YouTubeMusic.idPrefix.count))
      guard newHits.count < SearchForkState.youTubeLimit, seen.insert(videoId).inserted,
            let hit = YouTubeMusicHitStore.shared.hit(forVideoId: videoId) ?? SongpickerHit(
              videoId: videoId,
              title: song.title,
              artist: song.creatorName,
              album: nil,
              duration: song.duration
            )
      else { continue }
      newHits.append(hit)
      fork.knownHits[videoId] = hit
      fork.youTubeSongs[videoId] = song
    }
    fork.youTubeHits = newHits
    if !newHits.isEmpty {
      monitor.refresh()
    }
  }

  // MARK: Top result

  private func forkUpdateTopHit(searchText: String) {
    let queryWords = Self.forkWords(searchText)
    guard !queryWords.isEmpty else { return }
    var candidates = [(hit: SearchTopHit, score: Double)]()
    if let artist = artists.first {
      candidates.append((.artist(artist), Self.forkScore(queryWords, name: artist.name) + 0.05))
    }
    if let song = songs.first {
      candidates.append((
        .song(song),
        Self.forkScore(queryWords, name: song.title, other: song.creatorName) + 0.03
      ))
    }
    if let album = albums.first {
      candidates.append((
        .album(album),
        Self.forkScore(queryWords, name: album.name, other: album.subtitle ?? "") + 0.02
      ))
    }
    if let hit = fork.youTubeHits.first {
      candidates.append((.youTube(hit), Self.forkScore(queryWords, name: hit.title, other: hit.artist)))
    }
    // at least half of the words must match, and a shown result is only replaced by a better one
    guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= 1.0 else { return }
    if fork.topHit == nil || best.score > fork.topHitScore {
      fork.topHit = best.hit
      fork.topHitScore = best.score
    }
  }

  /// Lowercased words without diacritics and apostrophes, "valentines" also as "valentine".
  static func forkWords(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: "'", with: "")
      .replacingOccurrences(of: "’", with: "")
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }

  /// 2 × share of the query words found in name and other text, +1 if the name is the query.
  static func forkScore(_ queryWords: [String], name: String, other: String = "") -> Double {
    let nameWords = forkWords(name)
    let words = Set(nameWords + forkWords(other))
    func matches(_ word: String) -> Bool {
      if words.contains(word) { return true }
      if word.count > 3, word.hasSuffix("s"), words.contains(String(word.dropLast())) {
        return true
      }
      // the last word may still be typed
      return word == queryWords.last && words.contains { $0.hasPrefix(word) }
    }
    let share = Double(queryWords.filter(matches).count) / Double(queryWords.count)
    return 2 * share + (nameWords == queryWords ? 1 : 0)
  }

  // MARK: Snapshot

  func forkAppendItems(to snapshot: inout NSDiffableDataSourceSnapshot<Int, SearchItem>) {
    if !isSearchActive, !fork.genres.isEmpty {
      snapshot.appendItems([.genreGrid], toSection: SearchSection.Genres.rawValue)
      snapshot.reloadItems([.genreGrid])
    }
    guard isSearchActive else { return }
    if fork.topHit != nil {
      snapshot.appendItems([.topHit], toSection: SearchSection.TopHit.rawValue)
      snapshot.reloadItems([.topHit])
    }
    snapshot.appendItems(
      fork.youTubeHits.map { .youTube($0.videoId) },
      toSection: SearchSection.YouTube.rawValue
    )
    let hasOtherResults = !artists.isEmpty || !albums.isEmpty || !playlists.isEmpty ||
      !songs.isEmpty || fork.topHit != nil
    let showsStatusRow = fork.youTubeHits.isEmpty && hasOtherResults &&
      (fork.youTubeState == .loading || fork.youTubeState == .failed)
    if showsStatusRow {
      snapshot.appendItems([.youTubeStatus], toSection: SearchSection.YouTube.rawValue)
      snapshot.reloadItems([.youTubeStatus])
    }
  }

  private func forkSectionHasRows(_ section: SearchSection) -> Bool {
    guard let snapshot = (tableView.dataSource as? SearchDiffableDataSource)?.snapshot(),
          snapshot.sectionIdentifiers.contains(section.rawValue)
    else { return false }
    return snapshot.numberOfItems(inSection: section.rawValue) > 0
  }

  // MARK: Table hooks

  func forkTitle(for section: SearchSection) -> String? {
    switch section {
    case .Genres: return "Genres"
    case .TopHit: return "Top Result"
    case .YouTube: return "YouTube Music"
    default: return nil
    }
  }

  func forkHeaderHeight(for section: SearchSection) -> CGFloat {
    switch section {
    case .Genres:
      return (!isSearchActive && !fork.genres.isEmpty) ? CommonScreenOperations
        .tableSectionHeightLarge : 0
    case .TopHit, .YouTube:
      return (isSearchActive && forkSectionHasRows(section)) ? CommonScreenOperations
        .tableSectionHeightLarge : 0
    default:
      return 0
    }
  }

  func forkRowHeight(at indexPath: IndexPath) -> CGFloat {
    switch SearchSection(rawValue: indexPath.section) {
    case .Genres: return SearchGenreGridCell.height(itemCount: fork.genres.count)
    case .TopHit: return SearchTopHitCell.rowHeight
    case .YouTube:
      return forkYouTubeHit(at: indexPath) != nil ? PlayableTableCell.rowHeight : SearchStatusCell
        .rowHeight
    default: return 0
    }
  }

  func forkCell(at indexPath: IndexPath) -> UITableViewCell {
    switch SearchSection(rawValue: indexPath.section) {
    case .Genres:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: SearchGenreGridCell.reuseID,
        for: indexPath
      ) as! SearchGenreGridCell
      cell.display(genres: fork.genres)
      cell.onSelect = { [weak self] genre in self?.forkOpen(genre: genre) }
      return cell
    case .TopHit:
      let cell = tableView.dequeueReusableCell(
        withIdentifier: SearchTopHitCell.reuseID,
        for: indexPath
      ) as! SearchTopHitCell
      switch fork.topHit {
      case let .artist(artist): cell.display(container: artist, kind: "Artist")
      case let .album(album): cell.display(container: album, kind: "Album")
      case let .song(song): cell.display(container: song, kind: "Song")
      case let .youTube(hit):
        cell.display(
          hit: hit,
          song: fork.youTubeSongs[hit.videoId],
          status: monitor.status(for: hit)
        )
      case .none: break
      }
      return cell
    case .YouTube:
      guard let hit = forkYouTubeHit(at: indexPath),
            let song = fork.youTubeSongs[hit.videoId] else {
        let cell = tableView.dequeueReusableCell(
          withIdentifier: SearchStatusCell.reuseID,
          for: indexPath
        ) as! SearchStatusCell
        if fork.youTubeState == .failed {
          cell.display(text: "YouTube Music is not reachable", isLoading: false)
        } else {
          cell.display(text: "Searching YouTube Music…", isLoading: true)
        }
        return cell
      }
      let cell: PlayableTableCell = dequeueCell(for: tableView, at: indexPath)
      cell.display(playable: song, playContextCb: convertCellViewToPlayContext, rootView: self)
      cell.accessoryView = SourceBadgeView(status: monitor.status(for: hit))
      cell.optionsButton.menu = UIMenu(children: forkYouTubeActions(for: hit))
      return cell
    default:
      return UITableViewCell()
    }
  }

  func forkContainable(at indexPath: IndexPath) -> PlayableContainable? {
    switch SearchSection(rawValue: indexPath.section) {
    case .TopHit:
      switch fork.topHit {
      case let .artist(artist): return artist
      case let .album(album): return album
      case let .song(song): return song
      case let .youTube(hit): return fork.youTubeSongs[hit.videoId]
      case .none: return nil
      }
    case .YouTube:
      return forkYouTubeHit(at: indexPath).flatMap { fork.youTubeSongs[$0.videoId] }
    default:
      return nil
    }
  }

  func forkPlayContext(at indexPath: IndexPath) -> PlayContext? {
    guard let containable = forkContainable(at: indexPath) else { return nil }
    if let hit = forkYouTubeHit(at: indexPath) ?? forkTopYouTubeHit(at: indexPath) {
      forkWillPlay(hit)
    }
    return PlayContext(containable: containable)
  }

  func forkDetermSwipeActionContext(
    at indexPath: IndexPath,
    completionHandler: @escaping (_ actionContext: SwipeActionContext?) -> ()
  ) {
    guard let containable = forkContainable(at: indexPath) else {
      completionHandler(nil)
      return
    }
    guard containable is Artist || containable is Album else {
      completionHandler(SwipeActionContext(containable: containable))
      return
    }
    Task { @MainActor in
      do {
        try await containable.fetch(
          storage: self.appDelegate.storage,
          librarySyncer: self.appDelegate.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.appDelegate.getMeta(self.account.info)
            .playableDownloadManager
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Top Result Sync", error: error)
      }
      completionHandler(SwipeActionContext(containable: containable))
    }
  }

  func forkDidSelect(at indexPath: IndexPath) {
    let library = appDelegate.storage.main.library
    switch SearchSection(rawValue: indexPath.section) {
    case .TopHit:
      switch fork.topHit {
      case let .artist(artist):
        _ = library.createOrUpdateSearchHistory(container: artist)
        navigationController?.pushViewController(
          AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
          animated: true
        )
      case let .album(album):
        _ = library.createOrUpdateSearchHistory(container: album)
        navigationController?.pushViewController(
          AppStoryboard.Main.segueToAlbumDetail(account: account, album: album),
          animated: true
        )
      case let .song(song):
        _ = library.createOrUpdateSearchHistory(container: song)
        forkPlay(song)
      case let .youTube(hit):
        forkPlay(hit)
      case .none: break
      }
    case .YouTube:
      // the song cell plays on tap itself
      if let song = forkContainable(at: indexPath) {
        _ = library.createOrUpdateSearchHistory(container: song)
      }
    default: break
    }
  }

  // MARK: Context menu

  func forkContextMenuConfiguration(at indexPath: IndexPath) -> UIContextMenuConfiguration? {
    guard let hit = forkYouTubeHit(at: indexPath) ?? forkTopYouTubeHit(at: indexPath)
    else { return nil }
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      guard let self else { return nil }
      return UIMenu(children: forkYouTubeActions(for: hit))
    }
  }

  private func forkYouTubeActions(for hit: SongpickerHit) -> [UIMenuElement] {
    let status = monitor.status(for: hit)
    let canAdd = status == .online || status == .failed
    let play = UIAction(title: "Play", image: .play) { [weak self] _ in
      self?.forkPlay(hit)
    }
    let playNext = UIAction(
      title: "Play Next",
      image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")
    ) { [weak self] _ in
      guard let self, let song = fork.youTubeSongs[hit.videoId] else { return }
      fork.knownHits[hit.videoId] = hit
      appDelegate.player.insertUserQueue(playables: [song])
      DS.haptic(.success)
    }
    let addToQueue = UIAction(
      title: "Add to Queue",
      image: UIImage(systemName: "text.line.last.and.arrowtriangle.forward")
    ) { [weak self] _ in
      guard let self, let song = fork.youTubeSongs[hit.videoId] else { return }
      fork.knownHits[hit.videoId] = hit
      appDelegate.player.appendUserQueue(playables: [song])
      DS.haptic(.success)
    }
    let addToLibrary = UIAction(
      title: status == .inLibrary ? "In Library" : "Add to Library",
      image: UIImage(systemName: status == .inLibrary ? "checkmark.circle" : "arrow.down.circle"),
      attributes: canAdd ? [] : .disabled
    ) { [weak self] _ in
      self?.forkAddToLibrary(hit)
    }
    return [
      UIMenu(options: .displayInline, children: [play, playNext, addToQueue]),
      UIMenu(options: .displayInline, children: [addToLibrary]),
    ]
  }

  // MARK: Actions

  private func forkOpen(genre: Genre) {
    _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: genre)
    appDelegate.storage.main.library.saveContext()
    navigationController?.pushViewController(
      AppStoryboard.Main.segueToGenreDetail(account: account, genre: genre),
      animated: true
    )
  }

  private func forkPlay(_ hit: SongpickerHit) {
    guard let song = fork.youTubeSongs[hit.videoId] else { return }
    _ = appDelegate.storage.main.library.createOrUpdateSearchHistory(container: song)
    appDelegate.storage.main.library.saveContext()
    forkWillPlay(hit)
    forkPlay(song)
  }

  private func forkPlay(_ song: Song) {
    guard song.isCached || appDelegate.storage.settings.user.isOnlineMode else { return }
    searchController.searchBar.endEditing(true)
    DS.haptic(.success)
    appDelegate.player.play(context: PlayContext(containable: song))
  }

  private func forkWillPlay(_ hit: SongpickerHit) {
    fork.knownHits[hit.videoId] = hit
    // the proxy starts the download when it streams; the job shows up in getYtJobs
    monitor.track(hit)
  }

  private func forkAddToLibrary(_ hit: SongpickerHit) {
    Task { @MainActor in
      do {
        try await monitor.addToLibrary(hit)
        DS.haptic(.success)
      } catch {
        appDelegate.eventLogger.report(topic: "Add to Library", error: error)
      }
    }
  }

  /// Placeholders queued with Play Next / Add to Queue start their download when they play.
  func forkTrackCurrentlyPlaying() {
    guard let playable = appDelegate.player.currentlyPlaying,
          playable.isYouTubeMusicPlaceholder
    else { return }
    let videoId = String(playable.id.dropFirst(YouTubeMusic.idPrefix.count))
    guard let hit = fork.knownHits[videoId] else { return }
    monitor.track(hit)
  }

  // MARK: Status

  func forkRefreshYouTubeStatus() {
    guard isViewLoaded, isSearchActive else { return }
    for cell in tableView.visibleCells {
      guard let indexPath = tableView.indexPath(for: cell) else { continue }
      if let hit = forkYouTubeHit(at: indexPath),
         let badge = cell.accessoryView as? SourceBadgeView {
        badge.status = monitor.status(for: hit)
      } else if let hit = forkTopYouTubeHit(at: indexPath),
                let topCell = cell as? SearchTopHitCell {
        topCell.update(status: monitor.status(for: hit))
      }
    }
  }

  private func forkYouTubeHit(at indexPath: IndexPath) -> SongpickerHit? {
    guard SearchSection(rawValue: indexPath.section) == .YouTube,
          indexPath.row < fork.youTubeHits.count
    else { return nil }
    return fork.youTubeHits[indexPath.row]
  }

  private func forkTopYouTubeHit(at indexPath: IndexPath) -> SongpickerHit? {
    guard SearchSection(rawValue: indexPath.section) == .TopHit,
          case let .youTube(hit) = fork.topHit
    else { return nil }
    return hit
  }
}
