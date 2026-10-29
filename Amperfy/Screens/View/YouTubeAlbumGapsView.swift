//
//  YouTubeAlbumGapsView.swift
//  Amperfy
//
//  Fork (TASKS F-19): below the track list of a library album the songs YouTube Music has for
//  this album but the library doesn't ("Missing from Your Library"), each with its state
//  (cloud, ring, check), and a pill "Download Missing" that starts one job per missing song.
//  Tap on a song plays the missing songs from there through the proxy. Jobs are followed by
//  `YouTubeMusicJobMonitor` (F-6 sync, F-7 notification) like everywhere else.
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

// MARK: - YouTubeAlbumGapsView

@MainActor
final class YouTubeAlbumGapsView: UIView {
  private static let pillHeight: CGFloat = 40
  /// Downloads started at the same time, each one holds a stream until its first audio byte.
  private static let parallelDownloads = 2

  private let account: Account
  private let backendApi: BackendProxy
  private var gaps: YouTubeMusicAlbumGaps
  private let albumArtist: String
  private var monitor: YouTubeMusicJobMonitor { .shared }

  private let titleLabel = UILabel()
  private let infoLabel = UILabel()
  private let pill = UIButton(configuration: .filled())
  private let rows = UIStackView()
  private var cells = [YouTubeAlbumTrackCell]()
  private var isDownloadRunning = false
  private var isStartingPlayback = false

  init(gaps: YouTubeMusicAlbumGaps, albumArtist: String, account: Account) {
    self.gaps = gaps
    self.albumArtist = albumArtist
    self.account = account
    self.backendApi = (UIApplication.shared.delegate as! AppDelegate).getMeta(account.info).backendApi
    super.init(frame: .zero)

    titleLabel.text = String(localized: "Missing from Your Library", table: "Fork")
    titleLabel.font = DS.Font.sectionTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = DS.Color.text
    titleLabel.accessibilityTraits = .header
    titleLabel.numberOfLines = 2

    infoLabel.font = DS.Font.rowSubtitle
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = DS.Color.text2
    infoLabel.numberOfLines = 2

    pill.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
    pill.translatesAutoresizingMaskIntoConstraints = false
    pill.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.pillHeight).isActive = true
    pill.setContentHuggingPriority(.required, for: .horizontal)
    pill.setContentCompressionResistancePriority(.required, for: .horizontal)

    let texts = UIStackView(arrangedSubviews: [titleLabel, infoLabel])
    texts.axis = .vertical
    texts.spacing = 2
    let head = UIStackView(arrangedSubviews: [texts, pill])
    head.axis = .horizontal
    head.alignment = .center
    head.spacing = DS.Space.s
    head.isLayoutMarginsRelativeArrangement = true
    head.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 0, leading: DS.Space.m, bottom: 0, trailing: DS.Space.m
    )

    rows.axis = .vertical
    for (index, song) in gaps.missing.enumerated() {
      let cell = YouTubeAlbumTrackCell(style: .default, reuseIdentifier: nil)
      cell.display(song: song, albumArtist: albumArtist, status: .online, isPlaying: false)
      cell.translatesAutoresizingMaskIntoConstraints = false
      cell.heightAnchor.constraint(equalToConstant: ForkRowMetrics.songRowHeight).isActive = true
      cell.tag = index
      cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(rowTapped)))
      cell.accessibilityHint = String(localized: "Plays the missing songs from here", table: "Fork")
      cells.append(cell)
      rows.addArrangedSubview(cell)
    }

    let stack = UIStackView(arrangedSubviews: [head, rows])
    stack.axis = .vertical
    stack.spacing = DS.Space.s
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    monitor.configure(backendApi: backendApi)
    YouTubeMusicDownloadCoordinator.shared.start()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(stateChanged),
      name: .youTubeMusicStatusChanged,
      object: nil
    )
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(stateChanged),
      name: .playerPlay,
      object: nil
    )
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: State

  /// Downloaded on the server wins, then a job of the monitor, then the last `getYtAlbum`.
  private func status(of song: YouTubeAlbumSong, jobs: [String: YouTubeMusicStatus]) -> YouTubeMusicStatus {
    if song.downloaded { return .inLibrary }
    return jobs[song.videoId] ?? song.status
  }

  private var jobStatuses: [String: YouTubeMusicStatus] {
    Dictionary(monitor.jobList.map { ($0.videoId, $0.status) }) { first, _ in first }
  }

  @objc
  private func stateChanged() {
    refresh()
  }

  private func refresh() {
    let jobs = jobStatuses
    let current = appDelegate.player.currentlyPlaying?.id
    let statuses = gaps.missing.map { status(of: $0, jobs: jobs) }
    for (index, cell) in cells.enumerated() where gaps.missing.indices.contains(index) {
      let song = gaps.missing[index]
      cell.update(status: statuses[index], isPlaying: current == song.id || current == song.navidromeId)
    }
    let open = statuses.filter { $0 == .online || $0 == .failed }.count
    infoLabel.text = open > 0
      ? String(localized: "\(YouTubeAlbumActions.songCount(open)) on YouTube Music", table: "Fork")
      : String(localized: "From YouTube Music", table: "Fork")
    applyPill(open: open, isLoading: statuses.contains(where: \.isLoading))
  }

  private func applyPill(open: Int, isLoading: Bool) {
    var config = UIButton.Configuration.filled()
    config.cornerStyle = .capsule
    config.imagePadding = 6
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 16)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = DS.Font.pill
      return attributes
    }
    let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
    let isEnabled = open > 0 && !isDownloadRunning
    if isDownloadRunning || open > 0 {
      config.title = String(localized: "Download Missing", table: "Fork")
      config.image = isDownloadRunning ? nil : UIImage(systemName: "arrow.down", withConfiguration: symbol)
      config.showsActivityIndicator = isDownloadRunning
      config.baseBackgroundColor = DS.Color.accent
      config.baseForegroundColor = DS.Color.onAccent
    } else if isLoading {
      config.title = String(localized: "Downloading…", table: "Fork")
      config.image = UIImage(systemName: "arrow.down.circle", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.surfaceRaised
      config.baseForegroundColor = DS.Color.text
    } else {
      config.title = String(localized: "In Library", table: "Fork")
      config.image = UIImage(systemName: "checkmark", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.surfaceRaised
      config.baseForegroundColor = DS.Color.text
    }
    pill.configuration = config
    // the disabled look would gray out the state, so taps are ignored instead
    pill.isUserInteractionEnabled = isEnabled
    pill.accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    pill.accessibilityLabel = config.title
    pill.accessibilityHint = isEnabled
      ? String(localized: "Downloads the missing songs into your library", table: "Fork") : nil
  }

  // MARK: Actions

  @objc
  private func pillTapped() {
    guard !isDownloadRunning, appDelegate.storage.settings.user.isOnlineMode else {
      DS.haptic(.error)
      return
    }
    let jobs = jobStatuses
    let hits = gaps.missing
      .filter { [.online, .failed].contains(status(of: $0, jobs: jobs)) }
      .compactMap { $0.hit(album: gaps.album.name) }
    guard !hits.isEmpty else { return }
    DS.haptic(.light)
    isDownloadRunning = true
    refresh()
    Task { @MainActor in
      var failure: Error?
      for batchStart in stride(from: 0, to: hits.count, by: Self.parallelDownloads) {
        let batch = hits[batchStart ..< min(batchStart + Self.parallelDownloads, hits.count)]
        let tasks = batch.map { hit in
          Task { @MainActor in try await self.monitor.addToLibrary(hit) }
        }
        for task in tasks {
          do {
            try await task.value
          } catch {
            if failure == nil { failure = error }
          }
        }
      }
      isDownloadRunning = false
      refresh()
      if let failure, let host = parentViewController {
        DS.haptic(.error)
        YouTubeAlbumActions.showError(
          failure,
          title: String(localized: "Album Download Failed", table: "Fork"),
          from: host
        )
      } else {
        DS.haptic(.success)
      }
    }
  }

  @objc
  private func rowTapped(_ recognizer: UITapGestureRecognizer) {
    guard let index = recognizer.view?.tag, gaps.missing.indices.contains(index),
          !isStartingPlayback
    else { return }
    guard appDelegate.storage.settings.user.isOnlineMode else {
      DS.haptic(.error)
      return
    }
    isStartingPlayback = true
    let tapped = gaps.missing[index]
    Task { @MainActor in
      defer { isStartingPlayback = false }
      let playables = await backendApi.forkYouTubeAlbumPlayables(
        gaps.missing,
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
      appDelegate.player.play(context: PlayContext(
        name: gaps.album.name,
        index: start,
        playables: playables
      ))
    }
  }

  private var parentViewController: UIViewController? {
    var responder: UIResponder? = self
    while let next = responder?.next {
      if let controller = next as? UIViewController { return controller }
      responder = next
    }
    return nil
  }
}
