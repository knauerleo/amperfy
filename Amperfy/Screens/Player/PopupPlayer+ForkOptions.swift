//
//  PopupPlayer+ForkOptions.swift
//  Amperfy
//
//  Fork (UI-27b): no option row under the transport on the iPhone, like in streaming apps.
//  The queue is a small symbol at the right below the controls, the sleep timer chip sits at the
//  left of the same line. AirPlay, volume, player mode and the player options moved into the
//  "…" menu at the top of the player. The row of the XIB is only hidden.
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

// MARK: - ForkQueueButton

/// Small queue symbol below the transport, active in the accent color while the queue is shown.
final class ForkQueueButton: UIButton {
  static let size: CGFloat = 32
  /// Touch area of at least 44 pt around the small symbol.
  private static let minimumTouchSize: CGFloat = 44

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let dx = max(0, (Self.minimumTouchSize - bounds.width) / 2)
    let dy = max(0, (Self.minimumTouchSize - bounds.height) / 2)
    return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
  }
}

// MARK: - PlayerControlView

extension PlayerControlView {
  /// XIB: 28 pt option buttons, 28 pt below the transport (UI-21).
  private static let optionRowHeight: CGFloat = 28
  private static let optionRowTopSpacing: CGFloat = 28

  /// Height the control placeholder gives back to the lyrics card: the option row minus the queue line.
  static var forkCompactSavedHeight: CGFloat {
    ForkPlayerTransition.isActive ?
      (optionRowTopSpacing + optionRowHeight) - (DS.Space.xs + ForkQueueButton.size) : 0
  }

  var forkQueueButton: ForkQueueButton? {
    subviews.lazy.compactMap { $0 as? ForkQueueButton }.first
  }

  /// Called from `forkInstallStreamingTransport`: hides the option row, adds the queue symbol.
  func forkInstallCompactOptions(transport stack: UIStackView) {
    guard ForkPlayerTransition.isActive, forkQueueButton == nil else { return }
    optionsStackView.isHidden = true

    let queue = ForkQueueButton(type: .system)
    queue.translatesAutoresizingMaskIntoConstraints = false
    queue.accessibilityLabel = String(localized: "Queue", table: "Fork")
    queue.addAction(UIAction { [weak self] _ in
      DS.haptic(.light)
      self?.displayPlaylistPressed()
      self?.forkRefreshQueueButton()
    }, for: .touchUpInside)
    addSubview(queue)
    NSLayoutConstraint.activate([
      queue.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: DS.Space.xs),
      queue.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
      queue.widthAnchor.constraint(equalToConstant: ForkQueueButton.size),
      queue.heightAnchor.constraint(equalToConstant: ForkQueueButton.size),
    ])
    forkRefreshQueueButton()
  }

  /// Hook via `forkRefreshStreamingTransport`: accent while the queue is shown.
  func forkRefreshQueueButton() {
    guard let queue = forkQueueButton else { return }
    let isShown = appDelegate.storage.settings.user.playerDisplayStyle == .compact
    var config = UIButton.Configuration.plain()
    config.image = .playlistDisplayStyle
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 18,
      weight: .semibold
    )
    config.contentInsets = .zero
    config.baseForegroundColor = isShown ? DS.Color.accent : .label.withAlphaComponent(0.8)
    queue.configuration = config
    queue.accessibilityTraits = isShown ? [.button, .selected] : .button
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  /// Hook in `refreshOptionButton`: the player part of the "…" menu at the top (iPhone only).
  /// Output first (AirPlay, volume, mode), the song actions follow, the player options at the end.
  func forkPlayerMenu(songActions: [UIMenuElement]) -> [UIMenuElement] {
    guard ForkPlayerTransition.isActive, let controlView else { return songActions }

    var output = [UIMenuElement]()
    output.append(UIAction(
      title: String(localized: "AirPlay", table: "Fork"),
      image: UIImage(systemName: "airplay.audio")
    ) { [weak controlView] _ in
      guard let controlView else { return }
      controlView.airplayButtonPushed(controlView.airplayButton)
    })
    output.append(UIAction(
      title: String(localized: "Volume", table: "Fork"),
      image: UIImage(systemName: "speaker.wave.2")
    ) { [weak self] _ in
      self?.forkShowVolumeSlider()
    })
    // the mode switch only exists with podcasts, like its button in the row
    if player.podcastItemCount > 0 || player.playerMode == .podcast {
      let toPodcasts = player.playerMode == .music
      output.append(UIAction(
        title: toPodcasts ? String(localized: "Switch to Podcasts", table: "Fork") :
          String(localized: "Switch to Music", table: "Fork"),
        image: toPodcasts ? .podcast : .musicalNotes
      ) { [weak controlView] _ in
        controlView?.playerModeChangePressed(self)
      })
    }

    return [
      UIMenu(options: .displayInline, children: output),
      UIMenu(options: .displayInline, children: songActions),
      UIMenu(
        title: String(localized: "Player", table: "Fork"),
        options: .displayInline,
        children: controlView.createPlayerOptionsMenu()
      ),
    ]
  }

  /// Volume slider as a popover at the "…" button, the hidden row button cannot anchor it.
  private func forkShowVolumeSlider() {
    guard let source = largeCurrentlyPlayingView?.optionsButton else { return }
    let popover = SliderMenuPopover()
    let sliderView = popover.sliderMenuView
    sliderView.frame = CGRect(x: 0, y: 0, width: 250, height: 50)
    sliderView.slider.minimumValue = 0
    sliderView.slider.maximumValue = 100
    sliderView.slider.value = player.volume * 100
    sliderView.sliderValueChangedCB = { [weak self] in
      self?.player.volume = Float(sliderView.slider.value) / 100
    }
    popover.modalPresentationStyle = .popover
    popover.preferredContentSize = sliderView.frame.size
    guard let presentation = popover.popoverPresentationController else { return }
    presentation.permittedArrowDirections = [.up, .down]
    presentation.delegate = popover
    presentation.sourceView = source
    present(popover, animated: true)
  }
}

