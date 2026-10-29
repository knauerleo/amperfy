//
//  YouTubeAlbumViews.swift
//  Amperfy
//
//  Fork (TASKS F-8): header and rows of the YouTube album and artist screens in the Drift
//  style (UI-18): rounded titles, mint accent pill, 60 pt song rows and 72 pt album rows.
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

// MARK: - YouTubeArtworkView

/// Cover with a muted placeholder symbol until the image arrives.
final class YouTubeArtworkView: UIView {
  private let imageView = UIImageView()
  private let placeholder = UIImageView()

  init(cornerRadius: CGFloat, symbol: String = "music.note") {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = DS.Color.surfaceRaised
    layer.cornerRadius = cornerRadius
    layer.cornerCurve = .continuous
    clipsToBounds = true
    isAccessibilityElement = false
    placeholder.image = UIImage(systemName: symbol)
    placeholder.tintColor = DS.Color.text3
    placeholder.contentMode = .center
    placeholder.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
    imageView.contentMode = .scaleAspectFill
    for view in [placeholder, imageView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: topAnchor),
        view.bottomAnchor.constraint(equalTo: bottomAnchor),
        view.leadingAnchor.constraint(equalTo: leadingAnchor),
        view.trailingAnchor.constraint(equalTo: trailingAnchor),
      ])
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var image: UIImage? {
    get { imageView.image }
    set {
      imageView.image = newValue
      placeholder.isHidden = newValue != nil
    }
  }

  func setImage(_ image: UIImage?, animated: Bool) {
    guard animated, image != nil, !UIAccessibility.isReduceMotionEnabled else {
      self.image = image
      return
    }
    UIView.transition(with: self, duration: 0.25, options: .transitionCrossDissolve) {
      self.image = image
    }
  }
}

// MARK: - YouTubeAlbumHeaderView

final class YouTubeAlbumHeaderView: UIView {
  enum PillState: Equatable {
    case download
    case running
    /// Summary after the download was started.
    case done(String)
    /// Nothing missing, but songs still load.
    case loading
    case inLibrary
  }

  private static let coverSize: CGFloat = 220
  private static let pillHeight: CGFloat = 44

  var onArtist: (() -> ())?
  var onDownload: (() -> ())?

  private let cover = YouTubeArtworkView(cornerRadius: DS.Radius.card, symbol: "square.stack")
  private let sourceLabel = UILabel()
  private let titleLabel = UILabel()
  private let artistButton = UIButton(type: .system)
  private let infoLabel = UILabel()
  private let pill = UIButton(configuration: .filled())

  init() {
    super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
    backgroundColor = .clear

    sourceLabel.text = "YouTube Music"
    sourceLabel.font = DS.Font.caption
    sourceLabel.adjustsFontForContentSizeCategory = true
    sourceLabel.textColor = DS.Color.text3
    sourceLabel.textAlignment = .center

    titleLabel.font = DS.Font.detailTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = DS.Color.text
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 3
    titleLabel.accessibilityTraits = .header

    var artistConfig = UIButton.Configuration.plain()
    artistConfig.baseForegroundColor = DS.Color.accent
    artistConfig.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    artistConfig.titleLineBreakMode = .byTruncatingTail
    artistConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = DS.Font.songTitle
      return attributes
    }
    artistButton.configuration = artistConfig
    artistButton.accessibilityHint = String(localized: "Opens the artist on YouTube Music", table: "Fork")
    artistButton.addTarget(self, action: #selector(artistTapped), for: .touchUpInside)

    infoLabel.font = DS.Font.rowSubtitle
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = DS.Color.text2
    infoLabel.textAlignment = .center
    infoLabel.numberOfLines = 2

    pill.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
    pill.translatesAutoresizingMaskIntoConstraints = false
    pill.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.pillHeight).isActive = true

    let stack = UIStackView(arrangedSubviews: [
      cover, sourceLabel, titleLabel, artistButton, infoLabel, pill,
    ])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = DS.Space.xxs
    stack.setCustomSpacing(DS.Space.m, after: cover)
    stack.setCustomSpacing(DS.Space.xxs, after: sourceLabel)
    stack.setCustomSpacing(DS.Space.m, after: infoLabel)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      cover.widthAnchor.constraint(equalToConstant: Self.coverSize),
      cover.heightAnchor.constraint(equalToConstant: Self.coverSize),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.s),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.l),
      titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      artistButton.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      infoLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      pill.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
    ])
    apply(pill: .download)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func display(title: String, artist: String, info: String, pill state: PillState) {
    titleLabel.text = title
    artistButton.configuration?.title = artist
    artistButton.isHidden = artist.isEmpty
    artistButton.accessibilityLabel = String(localized: "Artist: \(artist)", table: "Fork")
    infoLabel.text = info
    cover.accessibilityLabel = title
    apply(pill: state)
  }

  func setCover(_ image: UIImage?) {
    cover.setImage(image, animated: true)
  }

  private func apply(pill state: PillState) {
    var config = UIButton.Configuration.filled()
    config.cornerStyle = .capsule
    config.imagePadding = 6
    config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 20)
    config.titleAlignment = .center
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = DS.Font.pill
      return attributes
    }
    let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
    var isEnabled = false
    switch state {
    case .download:
      config.title = String(localized: "Download Album", table: "Fork")
      config.image = UIImage(systemName: "arrow.down", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.accent
      config.baseForegroundColor = DS.Color.onAccent
      pill.accessibilityHint = String(localized: "Downloads the missing songs into your library", table: "Fork")
      isEnabled = true
    case .running:
      config.title = String(localized: "Download Album", table: "Fork")
      config.showsActivityIndicator = true
      config.baseBackgroundColor = DS.Color.accent
      config.baseForegroundColor = DS.Color.onAccent
      pill.accessibilityHint = nil
    case let .done(summary):
      config.title = summary
      config.image = UIImage(systemName: "arrow.down.circle", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.surfaceRaised
      config.baseForegroundColor = DS.Color.text
      pill.accessibilityHint = nil
    case .loading:
      config.title = String(localized: "Downloading…", table: "Fork")
      config.image = UIImage(systemName: "arrow.down.circle", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.surfaceRaised
      config.baseForegroundColor = DS.Color.text
      pill.accessibilityHint = nil
    case .inLibrary:
      config.title = String(localized: "In Library", table: "Fork")
      config.image = UIImage(systemName: "checkmark", withConfiguration: symbol)
      config.baseBackgroundColor = DS.Color.surfaceRaised
      config.baseForegroundColor = DS.Color.text
      pill.accessibilityHint = nil
    }
    pill.configuration = config
    // the disabled look would gray out the summary, so taps are ignored instead
    pill.isUserInteractionEnabled = isEnabled
    pill.accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    pill.accessibilityLabel = config.title
  }

  @objc
  private func artistTapped() {
    DS.haptic(.light)
    onArtist?()
  }

  @objc
  private func pillTapped() {
    onDownload?()
  }
}

// MARK: - YouTubeAlbumTrackCell

/// Track number, title, guest artist · duration, the state of the song on the right.
final class YouTubeAlbumTrackCell: UITableViewCell {
  static let reuseID = "YouTubeAlbumTrackCell"

  private let numberLabel = UILabel()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let badge = SourceBadgeView()
  private var accessibilityBase = ""

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear

    numberLabel.font = DS.Font.trackNumber
    numberLabel.adjustsFontForContentSizeCategory = true
    numberLabel.textColor = DS.Color.text3
    numberLabel.textAlignment = .center

    titleLabel.font = DS.Font.songTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = DS.Color.text

    subtitleLabel.font = DS.Font.cellDuration
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = DS.Color.text2

    badge.isAccessibilityElement = false
    badge.translatesAutoresizingMaskIntoConstraints = false

    let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    texts.axis = .vertical
    texts.spacing = 2
    let row = UIStackView(arrangedSubviews: [numberLabel, texts, badge])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = DS.Space.s
    row.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(row)
    NSLayoutConstraint.activate([
      numberLabel.widthAnchor.constraint(equalToConstant: 28),
      badge.widthAnchor.constraint(equalToConstant: SourceBadgeView.size),
      badge.heightAnchor.constraint(equalToConstant: SourceBadgeView.size),
      row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.xs),
      row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.m),
      row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DS.Space.xxs),
      row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DS.Space.xxs),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateConfiguration(using state: UICellConfigurationState) {
    backgroundConfiguration = ForkSurface.listCellBackground(for: state)
  }

  func display(song: YouTubeAlbumSong, albumArtist: String, status: YouTubeMusicStatus, isPlaying: Bool) {
    numberLabel.text = song.track.map(String.init) ?? "–"
    titleLabel.text = song.title
    let duration = song.duration > 0 ? song.duration.asColonDurationString : ""
    let isGuest = !song.artist.isEmpty && song.artist != albumArtist
    subtitleLabel.text = [isGuest ? song.artist : "", duration].filter { !$0.isEmpty }
      .joined(separator: " · ")
    var parts = [String]()
    if let track = song.track { parts.append(String(localized: "Track \(track)", table: "Fork")) }
    parts.append(song.title)
    if isGuest { parts.append(song.artist) }
    if !duration.isEmpty { parts.append(duration) }
    accessibilityBase = parts.joined(separator: ", ")
    update(status: status, isPlaying: isPlaying)
  }

  func update(status: YouTubeMusicStatus, isPlaying: Bool) {
    badge.status = status
    titleLabel.textColor = isPlaying ? DS.Color.accent : DS.Color.text
    numberLabel.textColor = isPlaying ? DS.Color.accent : DS.Color.text3
    accessibilityLabel = accessibilityBase
    var value = [badge.accessibilityLabel ?? ""]
    if isPlaying { value.insert(String(localized: "Now Playing", table: "Fork"), at: 0) }
    accessibilityValue = value.filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

// MARK: - YouTubeArtistAlbumCell

/// Album row of the artist screen: cover 56 pt, title, "Album · 2019".
final class YouTubeArtistAlbumCell: UITableViewCell {
  static let reuseID = "YouTubeArtistAlbumCell"

  private let cover = YouTubeArtworkView(cornerRadius: DS.Radius.rowArtwork, symbol: "square.stack")
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let titleSkeleton = SkeletonView()
  private let subtitleSkeleton = SkeletonView()
  private let coverSkeleton = SkeletonView(cornerRadius: DS.Radius.rowArtwork)
  private(set) var coverId: String?

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear

    titleLabel.font = DS.Font.songTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = DS.Color.text
    subtitleLabel.font = DS.Font.cellSubtitle
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = DS.Color.text2

    let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    texts.axis = .vertical
    texts.spacing = 2
    let row = UIStackView(arrangedSubviews: [cover, texts])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = DS.Space.s
    row.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(row)
    for skeleton in [coverSkeleton, titleSkeleton, subtitleSkeleton] {
      contentView.addSubview(skeleton)
    }
    let size = ForkRowMetrics.containerArtworkSize
    NSLayoutConstraint.activate([
      cover.widthAnchor.constraint(equalToConstant: size),
      cover.heightAnchor.constraint(equalToConstant: size),
      row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.m),
      row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      coverSkeleton.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
      coverSkeleton.topAnchor.constraint(equalTo: cover.topAnchor),
      coverSkeleton.widthAnchor.constraint(equalToConstant: size),
      coverSkeleton.heightAnchor.constraint(equalToConstant: size),
      titleSkeleton.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: DS.Space.s),
      titleSkeleton.bottomAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -3),
      titleSkeleton.widthAnchor.constraint(equalToConstant: 160),
      titleSkeleton.heightAnchor.constraint(equalToConstant: 14),
      subtitleSkeleton.leadingAnchor.constraint(equalTo: titleSkeleton.leadingAnchor),
      subtitleSkeleton.topAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 3),
      subtitleSkeleton.widthAnchor.constraint(equalToConstant: 90),
      subtitleSkeleton.heightAnchor.constraint(equalToConstant: 12),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateConfiguration(using state: UICellConfigurationState) {
    backgroundConfiguration = ForkSurface.listCellBackground(for: state)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    cover.image = nil
    coverId = nil
  }

  func display(album: YouTubeArtistAlbum) {
    setSkeleton(false)
    titleLabel.text = album.name
    var info = [YouTubeAlbumActions.kindName(album.kind)]
    if let year = album.year { info.append(String(year)) }
    subtitleLabel.text = info.joined(separator: " · ")
    coverId = album.coverArt ?? album.id
    cover.image = YouTubeCoverCache.shared.cachedImage(id: coverId ?? "")
    accessibilityLabel = album.name
    accessibilityValue = subtitleLabel.text
    accessibilityTraits = .button
  }

  func displaySkeleton() {
    setSkeleton(true)
    titleLabel.text = nil
    subtitleLabel.text = nil
    coverId = nil
    cover.image = nil
  }

  func setCover(_ image: UIImage?, for id: String) {
    guard id == coverId else { return }
    cover.setImage(image, animated: true)
  }

  private func setSkeleton(_ isSkeleton: Bool) {
    for skeleton in [coverSkeleton, titleSkeleton, subtitleSkeleton] {
      skeleton.isHidden = !isSkeleton
    }
    cover.isHidden = isSkeleton
    titleLabel.isHidden = isSkeleton
    subtitleLabel.isHidden = isSkeleton
    isAccessibilityElement = !isSkeleton
    accessibilityElementsHidden = isSkeleton
    selectionStyle = isSkeleton ? .none : .default
  }
}

// MARK: - YouTubeSectionHeaderView

/// "Albums", "Singles & EPs" in the rounded section title.
final class YouTubeSectionHeaderView: UITableViewHeaderFooterView {
  static let reuseID = "YouTubeSectionHeaderView"
  private let titleLabel = UILabel()

  override init(reuseIdentifier: String?) {
    super.init(reuseIdentifier: reuseIdentifier)
    titleLabel.font = DS.Font.sectionTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = DS.Color.text
    titleLabel.accessibilityTraits = .header
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(titleLabel)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.m),
      titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DS.Space.m),
      titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DS.Space.xs),
    ])
    var background = UIBackgroundConfiguration.listPlainHeaderFooter()
    background.backgroundColor = ForkSurface.background
    backgroundConfiguration = background
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func display(title: String) {
    titleLabel.text = title
  }
}
