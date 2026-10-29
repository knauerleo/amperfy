//
//  ListPlayHeaderView.swift
//  Amperfy
//
//  Fork: "Shuffle all" / "Play" row on top of the library lists Songs, Artists and Genres (UI-8).
//  Same look as the action row of the detail pages (ImmersiveDetailHeaderView): count on the
//  left, shuffle symbol and the round play button on the right. The Mac keeps the original
//  LibraryElementDetailTableHeaderView with its two text buttons.
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

// MARK: - ListPlayHeader

/// What a list needs from its play header: refresh the count and hide it while the list is empty.
@MainActor
protocol ListPlayHeader: UIView {
  func refresh()
}

// MARK: - LibraryElementDetailTableHeaderView + ListPlayHeader

extension LibraryElementDetailTableHeaderView: ListPlayHeader {}

// MARK: - ListPlayHeaderView

final class ListPlayHeaderView: UIView, ListPlayHeader {
  private static let playButtonSize: CGFloat = 48
  /// UI-18 (iPhone): "Play" and "Shuffle" as pills.
  private static let pillHeight: CGFloat = 40
  static var frameHeight: CGFloat {
    (DS.isPhone ? pillHeight : playButtonSize) + DS.Space.xs + DS.Space.s
  }

  /// Builds the play context asynchronously, e.g. after fetching the songs of a few artists.
  typealias ContextProvider = @MainActor (_ isShuffled: Bool) async -> PlayContext?

  private var config: PlayShuffleInfoConfiguration
  private var contextProvider: ContextProvider?
  private var isLoading = false

  private let infoLabel = UILabel()
  private let shuffleButton = UIButton(type: .system)
  private let playButton = UIButton(type: .system)

  // MARK: - Creation

  /// Same call as `LibraryElementDetailTableHeaderView.createTableHeader`. iPhone and iPad get the
  /// fork row, the Mac keeps the original header.
  static func createTableHeader(
    rootView: BasicTableViewController,
    configuration: PlayShuffleInfoConfiguration
  )
    -> ListPlayHeader? {
    guard ForkSurface.isEnabled else {
      return LibraryElementDetailTableHeaderView.createTableHeader(
        rootView: rootView,
        configuration: configuration
      )
    }
    let header = ListPlayHeaderView(configuration: configuration, width: rootView.view.bounds.width)
    rootView.tableView.tableHeaderView = header
    return header
  }

  /// For lists without a synchronous play context (Artists, Genres). Only on iPhone and iPad.
  @discardableResult
  static func install(
    in rootView: BasicTableViewController,
    player: PlayerFacade,
    infoCB: @escaping GetInfoCallback,
    contextProvider: @escaping ContextProvider
  )
    -> ListPlayHeaderView? {
    guard ForkSurface.isEnabled else { return nil }
    let config = PlayShuffleInfoConfiguration(
      infoCB: infoCB,
      playContextCb: nil,
      player: player,
      isInfoAlwaysHidden: false,
      isShuffleOnContextNeccessary: true
    )
    let header = ListPlayHeaderView(configuration: config, width: rootView.view.bounds.width)
    header.contextProvider = contextProvider
    rootView.tableView.tableHeaderView = header
    return header
  }

  private init(configuration: PlayShuffleInfoConfiguration, width: CGFloat) {
    config = configuration
    super.init(frame: CGRect(x: 0, y: 0, width: width, height: Self.frameHeight))
    autoresizingMask = [.flexibleWidth]
    setupViews()
    refresh()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Setup

  private func setupViews() {
    backgroundColor = .clear
    if DS.isPhone {
      setupPhonePills()
      return
    }

    infoLabel.font = DS.Font.rowSubtitle
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = .secondaryLabel
    infoLabel.numberOfLines = 1
    infoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    var shuffleConfig = UIButton.Configuration.plain()
    shuffleConfig.image = UIImage.shuffle.withConfiguration(UIImage.SymbolConfiguration(
      pointSize: 22,
      weight: .regular
    ))
    shuffleConfig.baseForegroundColor = .secondaryLabel
    shuffleConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
    shuffleButton.configuration = shuffleConfig
    shuffleButton.accessibilityLabel = String(localized: "Shuffle All", table: "Fork")
    shuffleButton.addTarget(self, action: #selector(shufflePressed), for: .touchUpInside)

    var playConfig = UIButton.Configuration.filled()
    playConfig.image = UIImage.play.withConfiguration(
      UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
    )
    playConfig.baseBackgroundColor = .label
    playConfig.baseForegroundColor = .systemBackground
    playConfig.cornerStyle = .capsule
    playButton.configuration = playConfig
    playButton.accessibilityLabel = String(localized: "Play All", table: "Fork")
    playButton.addTarget(self, action: #selector(playPressed), for: .touchUpInside)
    playButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      playButton.widthAnchor.constraint(equalToConstant: Self.playButtonSize),
      playButton.heightAnchor.constraint(equalToConstant: Self.playButtonSize),
    ])

    let row = UIStackView(arrangedSubviews: [infoLabel, shuffleButton, playButton])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = DS.Space.s
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.xs),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.s),
    ])
  }

  /// UI-18: "Play" as an accent pill, "Shuffle" as a raised pill, the count on the right.
  private func setupPhonePills() {
    infoLabel.font = DS.Font.rowSubtitle
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = DS.Color.text2
    infoLabel.textAlignment = .right
    infoLabel.numberOfLines = 1
    infoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    playButton.configuration = Self.pillConfiguration(
      title: String(localized: "Play", table: "Fork"),
      image: .play,
      background: DS.Color.accent,
      foreground: DS.Color.onAccent
    )
    playButton.accessibilityLabel = String(localized: "Play All", table: "Fork")
    playButton.addTarget(self, action: #selector(playPressed), for: .touchUpInside)

    shuffleButton.configuration = Self.pillConfiguration(
      title: String(localized: "Shuffle", table: "Fork"),
      image: .shuffle,
      background: DS.Color.surfaceRaised,
      foreground: DS.Color.text
    )
    shuffleButton.accessibilityLabel = String(localized: "Shuffle All", table: "Fork")
    shuffleButton.addTarget(self, action: #selector(shufflePressed), for: .touchUpInside)

    for button in [playButton, shuffleButton] {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.heightAnchor.constraint(equalToConstant: Self.pillHeight).isActive = true
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    let row = UIStackView(arrangedSubviews: [playButton, shuffleButton, infoLabel])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = DS.Space.xs
    row.setCustomSpacing(DS.Space.s, after: shuffleButton)
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.xs),
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.s),
    ])
  }

  private static func pillConfiguration(
    title: String,
    image: UIImage,
    background: UIColor,
    foreground: UIColor
  )
    -> UIButton.Configuration {
    var config = UIButton.Configuration.filled()
    config.title = title
    config.image = image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
    config.imagePadding = 6
    config.baseBackgroundColor = background
    config.baseForegroundColor = foreground
    config.cornerStyle = .capsule
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = DS.Font.pill
      return attributes
    }
    return config
  }

  // MARK: - Content

  func refresh() {
    infoLabel.text = config.infoCB?() ?? ""
    shuffleButton.isHidden = config.isShuffleHidden
    shuffleButton.isEnabled = !isLoading && (
      !config.isShuffleOnContextNeccessary || appDelegate.storage.settings.user
        .isPlayerShuffleButtonEnabled
    )
    playButton.isEnabled = !isLoading
  }

  private func setLoading(_ loading: Bool, button: UIButton) {
    isLoading = loading
    button.configuration?.showsActivityIndicator = loading
    refresh()
  }

  // MARK: - Actions

  @objc
  private func playPressed() {
    start(isShuffled: false, button: playButton)
  }

  @objc
  private func shufflePressed() {
    start(isShuffled: true, button: shuffleButton)
  }

  private func start(isShuffled: Bool, button: UIButton) {
    guard !isLoading else { return }
    DS.haptic(.success)
    let player = config.player
    if let contextProvider {
      setLoading(true, button: button)
      Task { @MainActor in
        let context = await contextProvider(isShuffled)
        self.setLoading(false, button: button)
        guard let context else { return }
        isShuffled ? player.playShuffled(context: context) : player.play(context: context)
      }
      return
    }
    if isShuffled {
      if let shuffleContext = config.shuffleContextCb?() {
        config.isShuffleOnContextNeccessary ? player.playShuffled(context: shuffleContext) : player
          .play(context: shuffleContext)
      } else if let context = config.playContextCb?() {
        player.playShuffled(context: context)
      }
    } else if let context = config.playContextCb?() {
      player.play(context: context)
    }
  }
}

// MARK: - ListPlayContextBuilder

/// Play contexts for lists of containers whose songs are usually not synced yet (Artists, Genres).
/// Picks a handful of albums, fetches them like the swipe actions do and plays their songs.
@MainActor
enum ListPlayContextBuilder {
  /// Albums fetched for one tap. Each one is a server request, so keep it small.
  static let albumCount = 10

  static func context(
    name: String,
    albums: [Album],
    account: Account
  ) async
    -> PlayContext? {
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    let isOnline = appDelegate.storage.settings.user.isOnlineMode
    var songs = [AbstractPlayable]()
    for album in albums {
      if isOnline {
        do {
          try await album.fetch(
            storage: appDelegate.storage,
            librarySyncer: appDelegate.getMeta(account.info).librarySyncer,
            playableDownloadManager: appDelegate.getMeta(account.info).playableDownloadManager
          )
        } catch {
          appDelegate.eventLogger.report(topic: "Album Sync", error: error)
        }
      }
      let albumSongs = album.playables
      songs.append(contentsOf: isOnline ? albumSongs : albumSongs.filter { $0.isCached })
    }
    guard !songs.isEmpty else { return nil }
    return PlayContext(name: name, playables: Array(songs.prefix(appDelegate.player.maxSongsToAddOnce)))
  }

  /// Albums in list order: all albums of the first containers until `albumCount` is reached.
  static func albumsInOrder(of groups: [[Album]]) -> [Album] {
    var result = [Album]()
    var seen = Set<Album>()
    for albums in groups {
      for album in albums where seen.insert(album).inserted {
        result.append(album)
        if result.count >= albumCount { return result }
      }
    }
    return result
  }

  /// Random albums spread over many containers: one random album from each of up to
  /// `albumCount` random containers, filled up with further random albums if there are few.
  static func randomAlbums(of groups: [[Album]]) -> [Album] {
    let nonEmpty = groups.filter { !$0.isEmpty }
    var result = [Album]()
    var seen = Set<Album>()
    for albums in nonEmpty[randomPick: albumCount] {
      if let album = albums.randomElement(), seen.insert(album).inserted {
        result.append(album)
      }
    }
    if result.count < albumCount {
      var rest = [Album]()
      for album in nonEmpty.joined() where seen.insert(album).inserted {
        rest.append(album)
      }
      result.append(contentsOf: rest[randomPick: albumCount - result.count])
    }
    return result
  }
}
