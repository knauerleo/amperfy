//
//  NowPlayingBarsView.swift
//  Amperfy
//
//  Fork: small animated equalizer for the song that is playing (measure 10).
//  Bars move while playing, rest at fixed heights while paused or with "Reduce Motion".
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

// MARK: - NowPlayingBarsView

final class NowPlayingBarsView: UIView {
  /// Bar heights (share of the view height) while not moving.
  private static let restingLevels: [CGFloat] = [0.45, 0.8, 0.3, 0.6]
  private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.5]
  private static let animationKey = "fork.nowPlayingBars"

  private let bars: [CALayer] = NowPlayingBarsView.restingLevels.map { _ in CALayer() }

  /// Playing: bars move (unless Reduce Motion is on). Paused: bars rest.
  var isPlaying = false {
    didSet {
      guard isPlaying != oldValue else { return }
      updateAnimation()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    bars.forEach { layer.addSublayer($0) }
    updateBarColor()
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

  override var intrinsicContentSize: CGSize { CGSize(width: 14, height: 12) }

  override func layoutSubviews() {
    super.layoutSubviews()
    let count = CGFloat(bars.count)
    let gap = max(1, (bounds.width / count) * 0.3)
    let barWidth = (bounds.width - gap * (count - 1)) / count
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, bar) in bars.enumerated() {
      // grow from the bottom: anchor at the bottom edge, scale the height
      bar.anchorPoint = CGPoint(x: 0.5, y: 1)
      bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
      bar.position = CGPoint(
        x: CGFloat(index) * (barWidth + gap) + barWidth / 2,
        y: bounds.height
      )
      bar.cornerRadius = min(1, barWidth / 2)
      if bar.animation(forKey: Self.animationKey) == nil {
        bar.transform = CATransform3DMakeScale(1, Self.restingLevels[index], 1)
      }
    }
    CATransaction.commit()
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    updateBarColor()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // Core Animation drops running animations when a layer leaves the window
    updateAnimation()
  }

  private func updateBarColor() {
    let color = tintColor.resolvedColor(with: traitCollection).cgColor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bars.forEach { $0.backgroundColor = color }
    CATransaction.commit()
  }

  @objc
  private func reduceMotionChanged() {
    updateAnimation()
  }

  private func updateAnimation() {
    let shouldMove = isPlaying && window != nil && !UIAccessibility.isReduceMotionEnabled
    for (index, bar) in bars.enumerated() {
      let resting = Self.restingLevels[index]
      if shouldMove {
        guard bar.animation(forKey: Self.animationKey) == nil else { continue }
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = 0.2
        animation.toValue = 1.0
        animation.duration = Self.durations[index]
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // start each bar at a different point of its cycle
        animation.timeOffset = Self.durations[index] * Double(resting)
        bar.add(animation, forKey: Self.animationKey)
      } else {
        bar.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.transform = CATransform3DMakeScale(1, resting, 1)
        CATransaction.commit()
      }
    }
  }
}
