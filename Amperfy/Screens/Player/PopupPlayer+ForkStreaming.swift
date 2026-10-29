//
//  PopupPlayer+ForkStreaming.swift
//  Amperfy
//
//  Fork (UI-20): the iPhone player laid out like a streaming app.
//  - Header instead of the grabber: chevron to close, "Playing from" and the context, tap opens the album.
//  - Title and artist only, the album moves into the header. Favorite and options without the gray circles.
//  - Transport row: shuffle, previous, play as a white circle, next, repeat.
//  The XIBs stay untouched, the views only call the hooks below.
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

// MARK: - PlayerNowPlayingHeaderView

final class PlayerNowPlayingHeaderView: UIView {
  static let height: CGFloat = 48

  private let closeButton = UIButton(type: .system)
  private let contextButton = UIButton(type: .custom)
  private let captionLabel = UILabel()
  private let contextLabel = UILabel()

  init(onClose: @escaping () -> Void, onContext: @escaping () -> Void) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    var closeConfig = UIButton.Configuration.plain()
    closeConfig.image = UIImage(systemName: "chevron.down")
    closeConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 20,
      weight: .semibold
    )
    closeConfig.baseForegroundColor = .label
    closeButton.configuration = closeConfig
    closeButton.accessibilityLabel = String(localized: "Close Player", table: "Fork")
    closeButton.addAction(UIAction { _ in onClose() }, for: .touchUpInside)

    captionLabel.text = String(localized: "Playing from", table: "Fork").uppercased()
    captionLabel.font = DS.Font.caption
    captionLabel.textColor = .secondaryLabel
    contextLabel.font = DS.Font.tileTitle
    contextLabel.textColor = .label
    for label in [captionLabel, contextLabel] {
      label.textAlignment = .center
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
    }
    let labels = UIStackView(arrangedSubviews: [captionLabel, contextLabel])
    labels.axis = .vertical
    labels.alignment = .center
    labels.spacing = 1
    labels.isUserInteractionEnabled = false
    labels.translatesAutoresizingMaskIntoConstraints = false
    contextButton.addSubview(labels)
    contextButton.addAction(UIAction { _ in onContext() }, for: .touchUpInside)
    contextButton.accessibilityHint = String(localized: "Shows the album", table: "Fork")

    // the right spacer keeps the context centered on the screen
    let spacer = UIView()
    for view in [closeButton, contextButton, spacer] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      closeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
      spacer.trailingAnchor.constraint(equalTo: trailingAnchor),
      spacer.widthAnchor.constraint(equalToConstant: 44),
      spacer.topAnchor.constraint(equalTo: topAnchor),
      spacer.bottomAnchor.constraint(equalTo: bottomAnchor),
      contextButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: DS.Space.xs),
      contextButton.trailingAnchor.constraint(equalTo: spacer.leadingAnchor, constant: -DS.Space.xs),
      contextButton.topAnchor.constraint(equalTo: topAnchor),
      contextButton.bottomAnchor.constraint(equalTo: bottomAnchor),
      labels.centerYAnchor.constraint(equalTo: contextButton.centerYAnchor),
      labels.leadingAnchor.constraint(equalTo: contextButton.leadingAnchor),
      labels.trailingAnchor.constraint(equalTo: contextButton.trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(context: String?) {
    let context = context?.trimmingCharacters(in: .whitespaces) ?? ""
    captionLabel.isHidden = context.isEmpty
    contextLabel.text = context.isEmpty ? ForkBrand.name : context
    contextButton.accessibilityLabel = context.isEmpty ? ForkBrand.name :
      String(localized: "Playing from \(context)", table: "Fork")
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  /// Called from `forkConfigurePlayer`: header at the top of the page.
  func forkMakeNowPlayingHeader() -> PlayerNowPlayingHeaderView {
    PlayerNowPlayingHeaderView(
      onClose: { [weak self] in self?.closePopupPlayer() },
      onContext: { [weak self] in self?.displayAlbumDetail() }
    )
  }

  /// Hook from `LargeCurrentlyPlayingPlayerView.refresh`: context of the playing song.
  func forkRefreshNowPlayingHeader() {
    guard let header = forkPlayerPage?.header else { return }
    switch player.playerMode {
    case .music:
      let album = player.currentlyPlaying?.asSong?.album?.name
      header.display(context: album ?? player.contextName)
    case .podcast:
      header.display(context: player.currentlyPlaying?.asPodcastEpisode?.podcast?.title)
    }
  }
}

// MARK: - LargeCurrentlyPlayingPlayerView

extension LargeCurrentlyPlayingPlayerView {
  /// Hook at the end of `refresh`: title and artist only, plain favorite and options buttons.
  func forkApplyStreamingLayout() {
    guard ForkPlayerTransition.isActive else { return }
    // the album is named in the header
    albumContainerView.isHidden = true
    for button in [favoriteButton, optionsButton] {
      guard var config = button?.configuration else { continue }
      config.background.backgroundColor = .clear
      config.baseBackgroundColor = .clear
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 22,
        weight: .medium
      )
      button?.configuration = config
    }
    // UI-21: without the album the title block needs less height, the cover gains the rest
    if let height = detailsContainer.constraints.first(where: {
      $0.firstItem === detailsContainer && $0.firstAttribute == .height && $0.secondItem == nil
    }) {
      height.constant = Self.forkDetailsHeight
    }
    rootView?.forkRefreshNowPlayingHeader()
  }

  /// Title and artist with the XIB's 100 pt it would float in a wide gap below the cover.
  private static let forkDetailsHeight: CGFloat = 72
}

// MARK: - ForkTransportToggleButton

/// Shuffle or repeat in the transport row.
final class ForkTransportToggleButton: UIButton {
  enum Kind { case shuffle, repeatMode }
  let kind: Kind

  init(kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - PlayerControlView

extension PlayerControlView {
  private static let playCircleSize: CGFloat = 64
  private static let playCircleTag = 0x5054
  /// UI-21: slider to transport row (XIB 22) and transport to options (XIB 20). The play circle
  /// is 14 pt higher than the row, with the XIB values it touched the times and the stream info.
  private static let transportTopSpacing: CGFloat = 40
  private static let optionsTopSpacing: CGFloat = 28
  /// Added to the control placeholder so the rows keep their place at the bottom.
  static var forkStreamingExtraHeight: CGFloat {
    ForkPlayerTransition.isActive ? (transportTopSpacing - 22) + (optionsTopSpacing - 20) : 0
  }

  private var forkTransportStack: UIStackView? {
    playButton.superview as? UIStackView
  }

  private var forkToggleButtons: [ForkTransportToggleButton] {
    forkTransportStack?.arrangedSubviews.compactMap { $0 as? ForkTransportToggleButton } ?? []
  }

  /// Called from `applyForkStyle`: shuffle and repeat around the transport, play as a white circle.
  func forkInstallStreamingTransport() {
    guard ForkPlayerTransition.isActive, let stack = forkTransportStack,
          forkToggleButtons.isEmpty
    else { return }

    let shuffle = ForkTransportToggleButton(kind: .shuffle)
    shuffle.addAction(UIAction { [weak self] _ in
      DS.haptic(.light)
      self?.appDelegate.player.toggleShuffle()
      self?.forkRefreshStreamingTransport()
    }, for: .touchUpInside)
    let repeatButton = ForkTransportToggleButton(kind: .repeatMode)
    repeatButton.addAction(UIAction { [weak self] _ in
      DS.haptic(.light)
      guard let player = self?.appDelegate.player else { return }
      player.setRepeatMode(player.repeatMode.nextMode)
      self?.forkRefreshStreamingTransport()
    }, for: .touchUpInside)
    stack.insertArrangedSubview(shuffle, at: 0)
    stack.addArrangedSubview(repeatButton)

    let circle = UIView()
    circle.tag = Self.playCircleTag
    circle.isUserInteractionEnabled = false
    circle.backgroundColor = .label
    circle.layer.cornerRadius = Self.playCircleSize / 2
    circle.translatesAutoresizingMaskIntoConstraints = false
    playButton.insertSubview(circle, at: 0)
    NSLayoutConstraint.activate([
      circle.centerXAnchor.constraint(equalTo: playButton.centerXAnchor),
      circle.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
      circle.widthAnchor.constraint(equalToConstant: Self.playCircleSize),
      circle.heightAnchor.constraint(equalToConstant: Self.playCircleSize),
    ])
    playButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 26, weight: .bold),
      forImageIn: .normal
    )
    playButton.tintColor = .systemBackground
    playButton.imageView?.tintColor = .systemBackground
    forkSpaceOutStreamingRows(transport: stack)
    forkRefreshStreamingTransport()
  }

  /// UI-21: more room around the transport row, the XIB constraints only get new constants.
  private func forkSpaceOutStreamingRows(transport stack: UIStackView) {
    for constraint in constraints where constraint.firstAttribute == .top {
      if constraint.firstItem === stack, constraint.secondItem === timeSlider {
        constraint.constant = Self.transportTopSpacing
      } else if constraint.firstItem === optionsStackView, constraint.secondItem === stack {
        constraint.constant = Self.optionsTopSpacing
      }
    }
  }

  /// Hook at the end of `refreshPlayer` and on shuffle or repeat changes.
  func forkRefreshStreamingTransport() {
    guard ForkPlayerTransition.isActive else { return }
    if let imageView = playButton.imageView {
      imageView.tintColor = .systemBackground
      playButton.bringSubviewToFront(imageView)
    }
    let player = appDelegate.player
    let isMusic = player.playerMode == .music
    for button in forkToggleButtons {
      button.isHidden = !isMusic
      let isActive: Bool
      let image: UIImage?
      switch button.kind {
      case .shuffle:
        isActive = player.isShuffle
        image = UIImage(systemName: "shuffle")
        button.isEnabled = appDelegate.storage.settings.user.isPlayerShuffleButtonEnabled
        button.accessibilityLabel = String(localized: "Shuffle", table: "Fork")
      case .repeatMode:
        isActive = player.repeatMode != .off
        image = UIImage(systemName: player.repeatMode == .single ? "repeat.1" : "repeat")
        button.accessibilityLabel = String(localized: "Repeat", table: "Fork")
      }
      var config = UIButton.Configuration.plain()
      config.image = image
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 20,
        weight: .semibold
      )
      config.baseForegroundColor = isActive ? DS.Color.accent : .label.withAlphaComponent(0.8)
      button.configuration = config
      button.accessibilityTraits = isActive ? [.button, .selected] : .button
    }
  }
}
