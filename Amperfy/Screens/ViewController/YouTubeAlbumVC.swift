//
//  YouTubeAlbumVC.swift
//  Amperfy
//
//  Fork (TASKS F-8): an album on YouTube Music (`getYtAlbum`). Cover, title, artist (opens the
//  YouTube artist), type · year · songs, the accent pill "Download Album" (`downloadYtAlbum`) and
//  the track list with the state of each song. A tap plays the album from that song: the real
//  Navidrome song where there is one, otherwise the `ytm-` placeholder through the proxy.
//  While the screen is visible and songs still load, `getYtAlbum` is asked again every 10 s,
//  the job states in between come from `YouTubeMusicJobMonitor` (getYtJobs).
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

// MARK: - YouTubeAlbumVC

final class YouTubeAlbumVC: UITableViewController {
  private static let refreshInterval: Duration = .seconds(10)
  /// The Navidrome ID follows the scan about 35 s after a download, songs that were in the
  /// library before may never get one. So it is awaited this long after the last finished song.
  private static let navidromeIdWait: TimeInterval = 120

  private let account: Account
  /// `ytm-album-…` or `ytm-<videoId>` (the album of that song).
  private let albumId: String
  private var album: YouTubeAlbum?
  private var isLoading = false
  private var loadError: String?
  private var canRetry = true
  /// Until then `getYtAlbum` is asked again for missing Navidrome IDs.
  private var navidromeIdDeadline: Date?
  private var isVisible = false
  /// Text of the pill after the download was started ("6 downloading, 9 already there").
  private var downloadSummary: String?
  private var isDownloadRunning = false
  private var isStartingPlayback = false
  private var refreshTask: Task<(), Never>?
  private let header = YouTubeAlbumHeaderView()

  private var backendApi: BackendProxy { appDelegate.getMeta(account.info).backendApi }
  private var monitor: YouTubeMusicJobMonitor { .shared }

  init(account: Account, albumId: String) {
    self.account = account
    self.albumId = albumId
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    tableView.backgroundColor = ForkSurface.background
    tableView.separatorStyle = .none
    tableView.rowHeight = ForkRowMetrics.songRowHeight
    tableView.register(YouTubeAlbumTrackCell.self, forCellReuseIdentifier: YouTubeAlbumTrackCell.reuseID)
    header.onArtist = { [weak self] in self?.openArtist() }
    header.onDownload = { [weak self] in self?.startDownload() }

    monitor.configure(backendApi: backendApi)
    YouTubeMusicDownloadCoordinator.shared.start()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(jobStatusChanged),
      name: .youTubeMusicStatusChanged,
      object: nil
    )
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerDidChange),
      name: .playerPlay,
      object: nil
    )
    load(isSilent: false)
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isVisible = true
    startRefreshing()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    isVisible = false
    refreshTask?.cancel()
    refreshTask = nil
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutHeader()
  }

  // MARK: Loading

  private func load(isSilent: Bool) {
    guard !isLoading else { return }
    guard appDelegate.storage.settings.user.isOnlineMode else {
      showUnavailable(text: String(localized: "YouTube Music is only available online.", table: "Fork"))
      return
    }
    isLoading = true
    if !isSilent { updateContentState() }
    Task { @MainActor in
      defer {
        isLoading = false
        updateContentState()
      }
      do {
        let newAlbum = try await backendApi.forkYouTubeAlbum(id: album?.id ?? albumId)
        loadError = nil
        let isFirstLoad = album == nil
        guard newAlbum != album else { return }
        noteFinishedSongs(old: album, new: newAlbum)
        album = newAlbum
        updateHeader()
        tableView.reloadData()
        if isFirstLoad { loadCover() }
        startRefreshing()
      } catch {
        // a failed refresh keeps the shown album
        if album == nil {
          loadError = error.localizedDescription
          canRetry = !((error as? YouTubeAlbumError)?.isPermanent ?? false)
        }
      }
    }
  }

  private func loadCover() {
    guard let album else { return }
    Task { @MainActor in
      let image = await YouTubeCoverCache.shared.image(id: album.coverArt ?? album.id, account: account)
      header.setCover(image)
    }
  }

  /// `getYtAlbum` again every 10 s while the screen is visible and something still changes,
  /// stops by itself when nothing does (started again by a download or a finished job).
  private func startRefreshing() {
    guard isVisible, refreshTask == nil || refreshTask?.isCancelled == true, needsRefresh
    else { return }
    refreshTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.refreshInterval)
        guard let self, !Task.isCancelled else { return }
        guard needsRefresh else {
          refreshTask = nil
          return
        }
        load(isSilent: true)
      }
    }
  }

  /// A song still has a job on the proxy (`ytState` wartet/lädt/speichert; `downloaded` is
  /// what counts once it is done), a job the monitor saw finish is not yet `downloaded`, or
  /// downloaded songs lack their Navidrome ID within 2 min after the last finished one.
  private var needsRefresh: Bool {
    guard let album else { return false }
    if album.songs.contains(where: { !$0.downloaded && $0.status.isLoading }) { return true }
    if album.songs.contains(where: { !$0.downloaded && jobStatuses[$0.videoId] == .inLibrary }) {
      return true
    }
    guard let navidromeIdDeadline, navidromeIdDeadline > Date() else { return false }
    return album.songs.contains { $0.downloaded && $0.navidromeId == nil }
  }

  /// Songs that became `downloaded` start the wait for their Navidrome ID.
  private func noteFinishedSongs(old: YouTubeAlbum?, new: YouTubeAlbum) {
    guard let old else { return }
    let wasDownloaded = Set(old.songs.filter(\.downloaded).map(\.id))
    if new.songs.contains(where: { $0.downloaded && !wasDownloaded.contains($0.id) }) {
      navidromeIdDeadline = Date().addingTimeInterval(Self.navidromeIdWait)
    }
  }

  private func updateContentState() {
    if album != nil {
      contentUnavailableConfiguration = nil
      tableView.tableHeaderView = header
      layoutHeader()
    } else if isLoading {
      tableView.tableHeaderView = nil
      var config = UIContentUnavailableConfiguration.loading()
      config.text = String(localized: "Loading album…", table: "Fork")
      contentUnavailableConfiguration = config
    } else if let loadError {
      showUnavailable(text: loadError)
    }
  }

  private func showUnavailable(text: String) {
    tableView.tableHeaderView = nil
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: "exclamationmark.icloud")
    config.text = String(localized: "Album Not Available", table: "Fork")
    config.secondaryText = text
    if appDelegate.storage.settings.user.isOnlineMode, canRetry {
      var button = UIButton.Configuration.filled()
      button.title = String(localized: "Try Again", table: "Fork")
      button.baseBackgroundColor = DS.Color.surfaceRaised
      button.baseForegroundColor = DS.Color.text
      button.cornerStyle = .capsule
      config.button = button
      config.buttonProperties.primaryAction = UIAction { [weak self] _ in
        self?.loadError = nil
        self?.canRetry = true
        self?.load(isSilent: false)
      }
    }
    contentUnavailableConfiguration = config
  }

  private func layoutHeader() {
    guard tableView.tableHeaderView === header else { return }
    let width = tableView.bounds.width
    guard width > 0 else { return }
    let size = header.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    guard header.frame.size != CGSize(width: width, height: size.height) else { return }
    header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
    tableView.tableHeaderView = header
  }

  // MARK: State

  /// Downloaded on the server wins, otherwise a job the monitor knows (it polls getYtJobs
  /// while tracked downloads run), otherwise the state of the last `getYtAlbum`.
  private func status(of song: YouTubeAlbumSong) -> YouTubeMusicStatus {
    if song.downloaded { return .inLibrary }
    if let entry = jobStatuses[song.videoId] { return entry }
    return song.status
  }

  private var jobStatuses = [String: YouTubeMusicStatus]()

  private func updateJobStatuses() {
    var result = [String: YouTubeMusicStatus]()
    for entry in monitor.jobList {
      result[entry.videoId] = entry.status
    }
    jobStatuses = result
  }

  @objc
  private func jobStatusChanged() {
    updateJobStatuses()
    updateHeader()
    refreshVisibleRows()
    startRefreshing()
  }

  @objc
  private func playerDidChange() {
    refreshVisibleRows()
  }

  private func refreshVisibleRows() {
    guard let album else { return }
    for cell in tableView.visibleCells {
      guard let cell = cell as? YouTubeAlbumTrackCell,
            let indexPath = tableView.indexPath(for: cell),
            album.songs.indices.contains(indexPath.row)
      else { continue }
      let song = album.songs[indexPath.row]
      cell.update(status: status(of: song), isPlaying: isPlaying(song))
    }
  }

  private func isPlaying(_ song: YouTubeAlbumSong) -> Bool {
    guard let current = appDelegate.player.currentlyPlaying?.id else { return false }
    return current == song.id || current == song.navidromeId
  }

  private func updateHeader() {
    guard let album else { return }
    updateJobStatuses()
    var info = [YouTubeAlbumActions.kindName(album.kind)]
    if let year = album.year { info.append(String(year)) }
    info.append(YouTubeAlbumActions.songCount(album.songs.count))
    header.display(
      title: album.name,
      artist: album.artist,
      info: info.joined(separator: " · "),
      pill: pillState(of: album)
    )
    layoutHeader()
  }

  private func pillState(of album: YouTubeAlbum) -> YouTubeAlbumHeaderView.PillState {
    if isDownloadRunning { return .running }
    if let downloadSummary { return .done(downloadSummary) }
    let statuses = album.songs.map(status(of:))
    if statuses.contains(where: { $0 == .online || $0 == .failed }) { return .download }
    if statuses.contains(where: \.isLoading) { return .loading }
    return .inLibrary
  }

  // MARK: Actions

  private func startDownload() {
    guard let album, !isDownloadRunning, appDelegate.storage.settings.user.isOnlineMode else { return }
    isDownloadRunning = true
    updateHeader()
    Task { @MainActor in
      do {
        let result = try await YouTubeAlbumActions.downloadAlbum(account: account, id: album.id)
        DS.haptic(.success)
        downloadSummary = YouTubeAlbumActions.summary(queued: result.queued, skipped: result.skipped)
        isDownloadRunning = false
        apply(download: result)
        UIAccessibility.post(notification: .announcement, argument: downloadSummary)
      } catch {
        DS.haptic(.error)
        isDownloadRunning = false
        updateHeader()
        YouTubeAlbumActions.showError(
          error,
          title: String(localized: "Album Download Failed", table: "Fork"),
          from: self
        )
      }
    }
  }

  /// The download answer carries every song with its new state.
  private func apply(download: YouTubeAlbumDownload) {
    guard let album else { return }
    self.album = album.updated(with: download)
    updateHeader()
    tableView.reloadData()
    startRefreshing()
  }

  private func openArtist() {
    guard let album else { return }
    guard let artistId = album.artistId ?? album.songs.first?.id else { return }
    // coming from that artist: back instead of a second copy
    if let stack = navigationController?.viewControllers, stack.count >= 2,
       let previous = stack[stack.count - 2] as? YouTubeArtistVC, previous.shows(artistId: artistId) {
      navigationController?.popViewController(animated: true)
      return
    }
    navigationController?.pushViewController(
      YouTubeArtistVC(account: account, artistId: artistId),
      animated: true
    )
  }

  private func play(from index: Int) {
    guard let album, album.songs.indices.contains(index), !isStartingPlayback else { return }
    guard appDelegate.storage.settings.user.isOnlineMode else {
      DS.haptic(.error)
      return
    }
    isStartingPlayback = true
    let tapped = album.songs[index]
    Task { @MainActor in
      defer { isStartingPlayback = false }
      let playables = await backendApi.forkYouTubeAlbumPlayables(
        album.songs,
        account: account,
        storage: appDelegate.storage
      )
      guard let start = playables.firstIndex(where: {
        $0.id == tapped.navidromeId || $0.id == tapped.id
      }) else {
        DS.haptic(.error)
        return
      }
      DS.haptic(.light)
      // placeholders download while they play, YouTubeMusicDownloadCoordinator follows them
      appDelegate.player.play(context: PlayContext(
        name: album.name,
        index: start,
        playables: playables
      ))
    }
  }

  // MARK: UITableViewDataSource

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    album?.songs.count ?? 0
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: YouTubeAlbumTrackCell.reuseID,
      for: indexPath
    ) as! YouTubeAlbumTrackCell
    guard let album, album.songs.indices.contains(indexPath.row) else { return cell }
    let song = album.songs[indexPath.row]
    cell.display(
      song: song,
      albumArtist: album.artist,
      status: status(of: song),
      isPlaying: isPlaying(song)
    )
    return cell
  }

  // MARK: UITableViewDelegate

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    play(from: indexPath.row)
  }
}
