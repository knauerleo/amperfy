//
//  PlayerAnimatedBackgroundView.swift
//  Amperfy
//
//  Fork (UI-13): slowly moving gradient from the cover colors behind the player.
//  Uses the existing AnimatedGradientLayer, the direction turns by a quarter every 10 seconds.
//  Sits above the static gradient and below the blur of the background image.
//  With "Reduce Motion" it is hidden and the static gradient of the original shows.
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

import UIKit

final class PlayerAnimatedBackgroundView: UIView {
  private static let quarterTurnDuration: TimeInterval = 10
  private static let colorChangeDuration: TimeInterval = 1.5

  private lazy var gradient = AnimatedGradientLayer(view: self)
  private var motionTimer: Timer?
  private var shownColors: [UIColor] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = false
    isHidden = true
    gradient.animationStyle = .linear
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reduceMotionChanged),
      name: UIAccessibility.reduceMotionStatusDidChangeNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradient.adjustTo(size: bounds.size)
    CATransaction.commit()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    refreshMotion()
  }

  /// Cover colors from `ArtworkColorCache` (via the player's `artworkGradientColors`).
  func setColors(_ colors: [UIColor]) {
    guard !colors.isEmpty, colors != shownColors else { return }
    let isFirst = shownColors.isEmpty
    shownColors = colors
    var cgColors = colors.map(\.cgColor)
    if cgColors.count == 1 { cgColors.append(cgColors[0]) }
    gradient.animationDuration = Self.colorChangeDuration
    gradient.setColors(cgColors, isAnimated: !isFirst)
    refreshMotion()
  }

  @objc
  private func reduceMotionChanged() {
    refreshMotion()
  }

  private func refreshMotion() {
    let isActive = window != nil && !shownColors.isEmpty && !UIAccessibility.isReduceMotionEnabled
    isHidden = UIAccessibility.isReduceMotionEnabled || shownColors.isEmpty
    guard isActive else {
      motionTimer?.invalidate()
      motionTimer = nil
      return
    }
    guard motionTimer == nil else { return }
    turn()
    motionTimer = Timer.scheduledTimer(
      withTimeInterval: Self.quarterTurnDuration,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in self?.turn() }
    }
  }

  /// Moves start and end point one corner further, linear, so the turns join without a stop.
  private func turn() {
    let start = gradient.startCorner.rotateClockwise()
    gradient.animationDuration = Self.quarterTurnDuration
    gradient.setCorners(startCorner: start, endCorner: start.opposed(), isAnimated: true)
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  /// Called from `forkConfigurePlayer`.
  func forkInstallAnimatedBackground() {
    let animated = PlayerAnimatedBackgroundView()
    backgroundImage.insertSubview(animated, at: 0)
    NSLayoutConstraint.activate([
      animated.topAnchor.constraint(equalTo: backgroundImage.topAnchor),
      animated.bottomAnchor.constraint(equalTo: backgroundImage.bottomAnchor),
      animated.leadingAnchor.constraint(equalTo: backgroundImage.leadingAnchor),
      animated.trailingAnchor.constraint(equalTo: backgroundImage.trailingAnchor),
    ])
    animated.setColors(artworkGradientColors)
  }

  var forkAnimatedBackground: PlayerAnimatedBackgroundView? {
    backgroundImage.subviews.lazy.compactMap { $0 as? PlayerAnimatedBackgroundView }.first
  }
}
