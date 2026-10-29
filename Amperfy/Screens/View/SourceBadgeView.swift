//
//  SourceBadgeView.swift
//  Amperfy
//
//  Fork: status of a YouTube Music result, shown as accessory view.
//  Cloud = only online, ring = downloading, check = in the library (same check as a cached song).
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

final class SourceBadgeView: UIView {
  static let size: CGFloat = 22

  var status: YouTubeMusicStatus = .online {
    didSet {
      guard status != oldValue else { return }
      update()
    }
  }

  private let imageView = UIImageView()
  private let trackLayer = CAShapeLayer()
  private let ringLayer = CAShapeLayer()
  private static let spinKey = "spin"

  init(status: YouTubeMusicStatus = .online) {
    self.status = status
    super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
    imageView.contentMode = .scaleAspectFit
    imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
      pointSize: 15,
      weight: .medium
    )
    imageView.frame = bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(imageView)

    for shape in [trackLayer, ringLayer] {
      shape.fillColor = UIColor.clear.cgColor
      shape.lineWidth = 2.5
      shape.lineCap = .round
      layer.addSublayer(shape)
    }
    isAccessibilityElement = true
    update()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: Self.size, height: Self.size)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let inset = bounds.insetBy(dx: 3, dy: 3)
    let path = UIBezierPath(
      arcCenter: CGPoint(x: inset.midX, y: inset.midY),
      radius: inset.width / 2,
      startAngle: -.pi / 2,
      endAngle: .pi * 1.5,
      clockwise: true
    ).cgPath
    for shape in [trackLayer, ringLayer] {
      shape.frame = bounds
      shape.path = path
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    updateColors()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    // animations are removed while the view is off screen
    updateSpinning()
  }

  private func update() {
    let isRing = status.isLoading
    imageView.isHidden = isRing
    trackLayer.isHidden = !isRing
    ringLayer.isHidden = !isRing

    switch status {
    case .online:
      imageView.image = UIImage(systemName: "icloud")
      accessibilityLabel = String(localized: "Only on YouTube Music", table: "Fork")
    case .inLibrary:
      imageView.image = .check
      accessibilityLabel = String(localized: "In your library", table: "Fork")
    case .failed:
      imageView.image = .exclamation
      accessibilityLabel = String(localized: "Download failed", table: "Fork")
    case .waiting:
      accessibilityLabel = String(localized: "Waiting for download", table: "Fork")
    case .downloading:
      accessibilityLabel = String(localized: "Downloading", table: "Fork")
    case .saving:
      accessibilityLabel = String(localized: "Saving", table: "Fork")
    }
    // the API reports no percentage, so the ring shows the step
    switch status {
    case .waiting: ringLayer.strokeEnd = 0.15
    case .downloading: ringLayer.strokeEnd = 0.6
    case .saving: ringLayer.strokeEnd = 0.9
    default: ringLayer.strokeEnd = 0
    }
    updateColors()
    updateSpinning()
  }

  private func updateColors() {
    imageView.tintColor = status == .online ? .secondaryLabel : .label
    trackLayer.strokeColor = UIColor.label.withAlphaComponent(0.2)
      .resolvedColor(with: traitCollection).cgColor
    ringLayer.strokeColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
  }

  private func updateSpinning() {
    let shouldSpin = window != nil && status.isLoading && !UIAccessibility.isReduceMotionEnabled
    if shouldSpin, ringLayer.animation(forKey: Self.spinKey) == nil {
      let spin = CABasicAnimation(keyPath: "transform.rotation.z")
      spin.fromValue = 0
      spin.toValue = 2 * Double.pi
      spin.duration = 1.2
      spin.repeatCount = .infinity
      ringLayer.add(spin, forKey: Self.spinKey)
    } else if !shouldSpin {
      ringLayer.removeAnimation(forKey: Self.spinKey)
    }
  }
}
