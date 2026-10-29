//
//  SleepTimerChipView.swift
//  Amperfy
//
//  Fork (UI-12, UI-27b): chip left of the queue symbol under the player controls while a sleep timer runs,
//  e.g. "Pauses at 23:40". A tap opens the sleep timer menu (change or turn off).
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

final class SleepTimerChipView: UIButton {
  static let height: CGFloat = 30

  private var refreshTimer: Timer?
  private var shownText: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    isHidden = true
    showsMenuAsPrimaryAction = true
    menu = UIMenu.lazyMenu { [weak self] in
      guard let self else { return [] }
      return [appDelegate.createSleepTimerMenu(refreshCB: { [weak self] in self?.refresh() })]
    }
    heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    accessibilityHint = String(localized: "Change or turn off the sleep timer", table: "Fork")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    refreshTimer?.invalidate()
    refreshTimer = nil
    guard window != nil else { return }
    refresh()
    // the timer can also be set or turned off in the options menu and the main menu
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    let text = currentText
    if let text, text != shownText {
      var config = UIButton.Configuration.filled()
      config.cornerStyle = .capsule
      config.baseBackgroundColor = UIColor.label.withAlphaComponent(0.12)
      config.baseForegroundColor = .label
      config.image = .sleep
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: DS.Font.caption)
      config.imagePadding = DS.Space.xxs
      config.contentInsets = NSDirectionalEdgeInsets(
        top: DS.Space.xxs,
        leading: DS.Space.s,
        bottom: DS.Space.xxs,
        trailing: DS.Space.s
      )
      var title = AttributedString(text)
      title.font = DS.Font.cellSubtitle
      config.attributedTitle = title
      configuration = config
      accessibilityLabel = String(localized: "Sleep Timer: \(text)", table: "Fork")
    }
    shownText = text
    let isShown = text != nil
    isHidden = !isShown
  }

  private var currentText: String? {
    if let timer = appDelegate.sleepTimer, timer.isValid {
      return String(localized: "Pauses at \(timer.fireDate.asShortHrMinString)", table: "Fork")
    } else if appDelegate.player.isShouldPauseAfterFinishedPlaying {
      return appDelegate.player.playerMode == .music
        ? String(localized: "Pauses after this Song", table: "Fork")
        : String(localized: "Pauses after this Episode", table: "Fork")
    }
    return nil
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  /// Called from `forkConfigurePlayer`. UI-27b: the option row is gone, the chip sits at the left
  /// of the queue symbol's line and needs no extra height.
  func forkInstallSleepTimerChip() {
    guard let controlView, let queue = controlView.forkQueueButton else { return }
    let chip = SleepTimerChipView()
    // inside the scrolling page next to the controls, so it scrolls with them
    let host: UIView = forkPlayerPage ?? view
    host.addSubview(chip)
    NSLayoutConstraint.activate([
      chip.leadingAnchor.constraint(equalTo: controlView.layoutMarginsGuide.leadingAnchor),
      chip.trailingAnchor.constraint(lessThanOrEqualTo: queue.leadingAnchor, constant: -DS.Space.xs),
      chip.centerYAnchor.constraint(equalTo: queue.centerYAnchor),
    ])
  }
}
