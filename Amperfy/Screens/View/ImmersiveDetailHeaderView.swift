//
//  ImmersiveDetailHeaderView.swift
//  Amperfy
//
//  Fork: streaming-style table header for album, playlist, genre and artist pages.
//  Large cover on a gradient from the cover color, bold title, one-tap play button,
//  stretch on overscroll and the title fading into the navigation bar while scrolling.
//  Takes the same DetailHeaderConfiguration as GenericDetailTableHeader.
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

final class ImmersiveDetailHeaderView: UIView {
  private static let playButtonSize: CGFloat = 52
  private static let maxArtworkSize: CGFloat = 260
  // UI-23: album page on the iPhone as in the mockup
  private static let albumPlayButtonSize: CGFloat = 56
  private static let albumArtworkSize: CGFloat = 220

  private let config: DetailHeaderConfiguration
  /// Optional extra action, e.g. an artist radio. Shown left in the action row.
  var radioAction: (() -> ())? {
    didSet { radioButton.isHidden = radioAction == nil }
  }

  private let backdropView = UIView()
  private let backdropGradient = CAGradientLayer()
  private let contentStack = UIStackView()
  private let artworkView = EntityImageView(frame: .zero)
  private let titleLabel = UILabel()
  private let subtitleButton = UIButton(type: .system)
  private let infoLabel = UILabel()
  private let descriptionLabel = UILabel()
  private let favoriteButton = UIButton(type: .system)
  private let downloadButton = UIButton(type: .system)
  private let radioButton = UIButton(type: .system)
  private let shuffleButton = UIButton(type: .system)
  private let playButton = UIButton(type: .system)
  private let accessoryContainer = UIStackView()
  private let navTitleLabel = UILabel()

  private var artworkSizeConstraint: NSLayoutConstraint?
  private var offsetObservation: NSKeyValueObservation?
  private var lastLayoutWidth: CGFloat = 0
  private var backdropColors: [UIColor] = []

  /// UI-23: album page on the iPhone. Playlists, genres and artists keep their header.
  private var isAlbumStyle: Bool {
    DS.isPhone && config.entityContainer is Album
  }

  private var maxArtworkSize: CGFloat {
    isAlbumStyle ? Self.albumArtworkSize : Self.maxArtworkSize
  }

  private var artworkCornerRadius: CGFloat {
    isAlbumStyle ? DS.Radius.card : DS.Radius.medium
  }

  // MARK: - Creation

  /// Creates the header and installs it as `tableHeaderView` of the configured table view.
  static func createTableHeader(configuration: DetailHeaderConfiguration)
    -> ImmersiveDetailHeaderView {
    let header = ImmersiveDetailHeaderView(configuration: configuration)
    header.installInTableView()
    return header
  }

  private init(configuration: DetailHeaderConfiguration) {
    config = configuration
    super.init(frame: CGRect(
      x: 0,
      y: 0,
      width: configuration.rootView.view.bounds.width,
      height: 400
    ))
    setupViews()
    refresh()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func installInTableView() {
    let tableView = config.tableView
    tableView.tableHeaderView = self
    updateHeight()
    offsetObservation = tableView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
      MainActor.assumeIsolated {
        self?.scrollOffsetChanged()
      }
    }
    navTitleLabel.alpha = 0
    config.rootView.navigationItem.titleView = navTitleLabel
  }

  // MARK: - Setup

  private func setupViews() {
    clipsToBounds = false
    backgroundColor = .clear

    backdropGradient.startPoint = CGPoint(x: 0.5, y: 0)
    backdropGradient.endPoint = CGPoint(x: 0.5, y: 1)
    backdropView.layer.addSublayer(backdropGradient)
    backdropView.isUserInteractionEnabled = false
    addSubview(backdropView)

    artworkView.translatesAutoresizingMaskIntoConstraints = false
    artworkView.layer.cornerRadius = artworkCornerRadius
    let artworkShadowContainer = UIView()
    artworkShadowContainer.translatesAutoresizingMaskIntoConstraints = false
    artworkShadowContainer.layer.shadowColor = UIColor.black.cgColor
    // UI-23: mockup shadow 0.55 / 24 pt offset / 48 pt blur (shadowRadius is half the blur)
    artworkShadowContainer.layer.shadowOpacity = isAlbumStyle ? 0.55 : 0.35
    artworkShadowContainer.layer.shadowRadius = isAlbumStyle ? 24 : 18
    artworkShadowContainer.layer.shadowOffset = CGSize(width: 0, height: isAlbumStyle ? 24 : 8)
    artworkShadowContainer.addSubview(artworkView)
    let artworkRow = UIView()
    artworkRow.addSubview(artworkShadowContainer)
    let sizeConstraint = artworkView.widthAnchor.constraint(equalToConstant: maxArtworkSize)
    artworkSizeConstraint = sizeConstraint
    NSLayoutConstraint.activate([
      sizeConstraint,
      artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor),
      artworkView.topAnchor.constraint(equalTo: artworkShadowContainer.topAnchor),
      artworkView.bottomAnchor.constraint(equalTo: artworkShadowContainer.bottomAnchor),
      artworkView.leadingAnchor.constraint(equalTo: artworkShadowContainer.leadingAnchor),
      artworkView.trailingAnchor.constraint(equalTo: artworkShadowContainer.trailingAnchor),
      artworkShadowContainer.topAnchor.constraint(equalTo: artworkRow.topAnchor),
      artworkShadowContainer.bottomAnchor.constraint(equalTo: artworkRow.bottomAnchor),
      artworkShadowContainer.centerXAnchor.constraint(equalTo: artworkRow.centerXAnchor),
    ])

    titleLabel.font = DS.Font.detailTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2

    var subtitleConfig = UIButton.Configuration.plain()
    subtitleConfig.contentInsets = .zero
    subtitleConfig.baseForegroundColor = .label
    subtitleConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = DS.Font.rowTitle
      return attributes
    }
    subtitleButton.configuration = subtitleConfig
    subtitleButton.contentHorizontalAlignment = .leading
    subtitleButton.addTarget(self, action: #selector(subtitlePressed), for: .touchUpInside)

    infoLabel.font = DS.Font.rowSubtitle
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = .secondaryLabel
    infoLabel.numberOfLines = 1

    descriptionLabel.font = DS.Font.rowSubtitle
    descriptionLabel.textColor = .secondaryLabel
    descriptionLabel.numberOfLines = 3

    configureIconButton(favoriteButton, image: .heartEmpty, action: #selector(favoritePressed))
    configureIconButton(downloadButton, image: .download, action: #selector(downloadPressed))
    configureIconButton(radioButton, image: .radio, action: #selector(radioPressed))
    radioButton.isHidden = true
    configureIconButton(shuffleButton, image: .shuffle, action: #selector(shufflePressed))
    shuffleButton.accessibilityLabel = String(localized: "Shuffle", table: "Fork")

    var playConfig = UIButton.Configuration.filled()
    playConfig.image = UIImage.play.withConfiguration(
      UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    )
    // UI-18: the play button carries the accent on the iPhone
    playConfig.baseBackgroundColor = DS.isPhone ? DS.Color.accent : .label
    playConfig.baseForegroundColor = DS.isPhone ? DS.Color.onAccent : .systemBackground
    playConfig.cornerStyle = .capsule
    playButton.configuration = playConfig
    playButton.accessibilityLabel = String(localized: "Play", table: "Fork")
    playButton.addTarget(self, action: #selector(playPressed), for: .touchUpInside)
    playButton.translatesAutoresizingMaskIntoConstraints = false
    let playSize = isAlbumStyle ? Self.albumPlayButtonSize : Self.playButtonSize
    NSLayoutConstraint.activate([
      playButton.widthAnchor.constraint(equalToConstant: playSize),
      playButton.heightAnchor.constraint(equalToConstant: playSize),
    ])

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actionRow = UIStackView(arrangedSubviews: [
      favoriteButton, downloadButton, radioButton, spacer, shuffleButton, playButton,
    ])
    actionRow.axis = .horizontal
    actionRow.alignment = .center
    actionRow.spacing = DS.Space.s

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleButton, infoLabel])
    textStack.axis = .vertical
    textStack.spacing = DS.Space.xxs

    accessoryContainer.axis = .vertical
    accessoryContainer.isHidden = true

    [artworkRow, textStack, descriptionLabel, actionRow, accessoryContainer]
      .forEach { contentStack.addArrangedSubview($0) }
    contentStack.axis = .vertical
    contentStack.spacing = DS.Space.m
    contentStack.setCustomSpacing(DS.Space.l, after: artworkRow)
    contentStack.setCustomSpacing(DS.Space.xs, after: textStack)
    contentStack.setCustomSpacing(DS.Space.l, after: actionRow)
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentStack)
    NSLayoutConstraint.activate([
      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.xs),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.s),
    ])

    navTitleLabel.font = DS.isPhone ? DS.Font.navTitle : .systemFont(ofSize: 17, weight: .semibold)
    navTitleLabel.textColor = .label

    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
      self.applyBackdropColors()
    }
  }

  private func configureIconButton(_ button: UIButton, image: UIImage, action: Selector) {
    var buttonConfig = UIButton.Configuration.plain()
    buttonConfig.image = image.withConfiguration(UIImage.SymbolConfiguration(
      pointSize: 22,
      weight: .regular
    ))
    buttonConfig.baseForegroundColor = .secondaryLabel
    buttonConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
    button.configuration = buttonConfig
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  /// Adds content below the action row (e.g. "Popular" and discography on the artist page).
  func setAccessoryView(_ view: UIView?) {
    accessoryContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if let view {
      accessoryContainer.addArrangedSubview(view)
    }
    accessoryContainer.isHidden = view == nil
    updateHeight()
  }

  // MARK: - Content

  func refresh() {
    let container = config.entityContainer
    let accountSettings = appDelegate.storage.settings.accounts.getSetting(container.account?.info)
      .read
    artworkView.display(
      theme: accountSettings.themePreference,
      container: container,
      cornerRadius: .small
    )
    artworkView.layer.cornerRadius = container is Artist ? artworkSize / 2 : artworkCornerRadius

    titleLabel.text = container.name
    navTitleLabel.text = container.name
    navTitleLabel.sizeToFit()

    if let subtitle = container.subtitle, !subtitle.isEmpty {
      subtitleButton.configuration?.title = subtitle
      subtitleButton.isHidden = false
      subtitleButton.isUserInteractionEnabled = container is Album
    } else {
      subtitleButton.isHidden = true
    }

    let infoText = albumInfoText ?? container.info(
      for: container.account?.apiType.asServerApiType,
      details: DetailInfoType(type: .long, settings: appDelegate.storage.settings)
    )
    infoLabel.text = infoText
    infoLabel.isHidden = infoText.isEmpty

    descriptionLabel.text = config.descriptionText
    descriptionLabel.isHidden = (config.descriptionText ?? "").isEmpty

    let isOnline = appDelegate.storage.settings.user.isOnlineMode
    favoriteButton.isHidden = !container.isFavoritable
    favoriteButton.isEnabled = isOnline
    favoriteButton.configuration?.image = (container.isFavorite ? UIImage.heartFill : UIImage.heartEmpty)
      .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22))
    favoriteButton.configuration?.baseForegroundColor = container.isFavorite ? .redHeart : .secondaryLabel
    downloadButton.isHidden = !container.isDownloadAvailable || !isOnline

    if let playConfig = config.playShuffleInfoConfig {
      playButton.isHidden = false
      shuffleButton.isHidden = playConfig.isShuffleHidden
      shuffleButton.isEnabled = !playConfig.isShuffleOnContextNeccessary || appDelegate.storage
        .settings.user.isPlayerShuffleButtonEnabled
    } else {
      playButton.isHidden = true
      shuffleButton.isHidden = true
    }

    refreshBackdropColors(theme: accountSettings.themePreference, settings: accountSettings)
    updateHeight()
  }

  private var artworkSize: CGFloat {
    artworkSizeConstraint?.constant ?? maxArtworkSize
  }

  /// UI-23: "Album · 2000 · 12 Songs · 37 Min" instead of the upstream long info
  /// ("12 Songs · Cached · Year 2000 · Genre: Rock · 37m"). Missing parts are left out.
  private var albumInfoText: String? {
    guard isAlbumStyle, let album = config.entityContainer as? Album else { return nil }
    var parts = [String(localized: "Album", table: "Fork")]
    if album.year > 0 {
      parts.append(String(album.year))
    }
    if album.songCount == 1 {
      parts.append(String(localized: "1 Song", table: "Fork"))
    } else if album.songCount > 1 {
      parts.append(String(localized: "\(album.songCount) Songs", table: "Fork"))
    }
    let minutes = Int((Double(album.duration) / 60).rounded())
    if minutes > 0 {
      parts.append(String(localized: "\(minutes) Min", table: "Fork"))
    }
    return parts.joined(separator: " · ")
  }

  private func refreshBackdropColors(
    theme: ThemePreference,
    settings: AccountSetting
  ) {
    let collection = config.entityContainer.getArtworkCollection(theme: theme)
    guard let entity = collection.singleImageEntity ?? collection.quadImageEntity?.first,
          entity.imagePath(setting: settings.artworkDisplayPreference) != nil
    else {
      backdropColors = []
      applyBackdropColors()
      return
    }
    let image = LibraryEntityImage.getImageToDisplayImmediately(
      libraryEntity: entity,
      themePreference: theme,
      artworkDisplayPreference: settings.artworkDisplayPreference,
      useCache: true
    )
    if let cached = ArtworkColorCache.shared.cachedColors(for: image) {
      backdropColors = cached
      applyBackdropColors()
      return
    }
    applyBackdropColors()
    Task { @MainActor in
      guard let colors = await ArtworkColorCache.shared.colors(for: image) else { return }
      self.backdropColors = colors
      UIView.transition(with: self.backdropView, duration: 0.25, options: .transitionCrossDissolve) {
        self.applyBackdropColors()
      }
    }
  }

  private func applyBackdropColors() {
    let base = ForkSurface.background.resolvedColor(with: traitCollection)
    let top = (backdropColors.first ?? .secondarySystemBackground).resolvedColor(with: traitCollection)
    // darken the cover color so white text stays readable in dark mode, lighten in light mode
    let tinted = traitCollection.userInterfaceStyle == .dark ?
      top.blended(with: .black, amount: 0.35) :
      top.blended(with: .white, amount: 0.45)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backdropGradient.colors = [tinted.cgColor, tinted.blended(with: base, amount: 0.6).cgColor, base.cgColor]
    backdropGradient.locations = [0, 0.55, 1]
    CATransaction.commit()
  }

  // MARK: - Layout

  override func layoutSubviews() {
    super.layoutSubviews()
    if abs(lastLayoutWidth - bounds.width) > 0.5 {
      lastLayoutWidth = bounds.width
      updateArtworkSize()
      DispatchQueue.main.async { self.updateHeight() }
    }
    layoutBackdrop()
  }

  private func updateArtworkSize() {
    let available = bounds.width - 2 * 64
    artworkSizeConstraint?.constant = max(160, min(maxArtworkSize, available))
    if config.entityContainer is Artist {
      artworkView.layer.cornerRadius = artworkSize / 2
    }
  }

  private func updateHeight() {
    let tableView = config.tableView
    let width = tableView.bounds.width > 0 ? tableView.bounds.width : config.rootView.view.bounds
      .width
    guard width > 0 else { return }
    let fitting = systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    let height = ceil(fitting.height)
    guard abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 else { return }
    frame = CGRect(x: 0, y: 0, width: width, height: height)
    if tableView.tableHeaderView === self {
      // re-assigning makes the table view pick up the new height
      tableView.tableHeaderView = self
    }
  }

  // MARK: - Scrolling

  private func layoutBackdrop() {
    let tableView = config.tableView
    let topInset = tableView.adjustedContentInset.top
    let pull = max(0, -(tableView.contentOffset.y + topInset))
    let extraTop = topInset + pull
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backdropView.frame = CGRect(
      x: 0,
      y: -extraTop,
      width: bounds.width,
      height: bounds.height + extraTop
    )
    backdropGradient.frame = backdropView.bounds
    CATransaction.commit()
  }

  private func scrollOffsetChanged() {
    let tableView = config.tableView
    let scrolled = tableView.contentOffset.y + tableView.adjustedContentInset.top
    layoutBackdrop()

    // stretch the cover a little on overscroll, fade it while scrolling away
    if scrolled < 0 {
      let scale = 1 + min(-scrolled / 600, 0.2)
      artworkView.transform = CGAffineTransform(scaleX: scale, y: scale)
      artworkView.alpha = 1
    } else {
      artworkView.transform = .identity
      artworkView.alpha = 1 - min(scrolled / max(artworkSize, 1), 1) * 0.7
    }

    // show the title in the navigation bar once the header title scrolled underneath it
    let titleBottom = titleLabel.convert(titleLabel.bounds, to: self).maxY
    let fade = (scrolled - titleBottom + DS.Space.l) / DS.Space.l
    navTitleLabel.alpha = min(max(fade, 0), 1)
  }

  // MARK: - Actions

  @objc
  private func playPressed() {
    guard let playConfig = config.playShuffleInfoConfig,
          let context = playConfig.playContextCb?() else { return }
    DS.haptic(.success)
    playConfig.player.play(context: context)
  }

  @objc
  private func shufflePressed() {
    guard let playConfig = config.playShuffleInfoConfig else { return }
    DS.haptic(.success)
    if let shuffleContext = playConfig.shuffleContextCb?() {
      if playConfig.isShuffleOnContextNeccessary {
        playConfig.player.playShuffled(context: shuffleContext)
      } else {
        playConfig.player.play(context: shuffleContext)
      }
    } else if let context = playConfig.playContextCb?() {
      playConfig.player.playShuffled(context: context)
    }
  }

  @objc
  private func radioPressed() {
    DS.haptic(.light)
    radioAction?()
  }

  @objc
  private func favoritePressed() {
    let container = config.entityContainer
    guard appDelegate.storage.settings.user.isOnlineMode,
          let account = container.account else { return }
    DS.haptic(.success)
    Task { @MainActor in
      do {
        try await container.remoteToggleFavorite(
          syncer: self.appDelegate.getMeta(account.info).librarySyncer
        )
      } catch {
        self.appDelegate.eventLogger.report(topic: "Toggle Favorite", error: error)
      }
      self.refresh()
    }
  }

  @objc
  private func downloadPressed() {
    let playables = config.entityContainer.playables
    guard let accountInfo = playables.first?.account?.info else { return }
    DS.haptic(.light)
    appDelegate.getMeta(accountInfo).playableDownloadManager.download(objects: playables)
  }

  @objc
  private func subtitlePressed() {
    guard let album = config.entityContainer as? Album,
          let artist = album.artist,
          let account = album.account,
          let navController = config.rootView.navigationController
    else { return }
    navController.pushViewController(
      AppStoryboard.Main.segueToArtistDetail(account: account, artist: artist),
      animated: true
    )
  }
}

// MARK: - UIColor blending

extension UIColor {
  fileprivate func blended(with other: UIColor, amount: CGFloat) -> UIColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return UIColor(
      red: r1 + (r2 - r1) * amount,
      green: g1 + (g2 - g1) * amount,
      blue: b1 + (b2 - b1) * amount,
      alpha: a1 + (a2 - a1) * amount
    )
  }
}
