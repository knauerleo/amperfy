//
//  SkeletonView.swift
//  Amperfy
//
//  Fork: placeholder block with a soft shimmer, shown in cell size while a shelf is loading.
//  The shimmer is skipped when Reduce Motion is on.
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

final class SkeletonView: UIView {
  private static let animationKey = "shimmer"
  private let shimmer = CAGradientLayer()

  init(cornerRadius: CGFloat = DS.Radius.small) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = DS.Color.skeleton
    layer.cornerRadius = cornerRadius
    clipsToBounds = true
    isUserInteractionEnabled = false
    shimmer.startPoint = CGPoint(x: 0, y: 0.5)
    shimmer.endPoint = CGPoint(x: 1, y: 0.5)
    shimmer.locations = [0, 0, 0]
    layer.addSublayer(shimmer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isHidden: Bool {
    didSet { updateAnimation() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let highlight = UIColor.label.withAlphaComponent(0.07).resolvedColor(with: traitCollection)
    shimmer.colors = [UIColor.clear.cgColor, highlight.cgColor, UIColor.clear.cgColor]
    shimmer.frame = bounds
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateAnimation()
  }

  /// Cells remove running animations on reuse, so the shimmer restarts whenever it becomes visible.
  private func updateAnimation() {
    let shouldAnimate = window != nil && !isHidden && !UIAccessibility.isReduceMotionEnabled
    if shouldAnimate, shimmer.animation(forKey: Self.animationKey) == nil {
      // animating the stops keeps the sweep independent of the view size
      let animation = CABasicAnimation(keyPath: "locations")
      animation.fromValue = [-0.4, -0.2, 0]
      animation.toValue = [1, 1.2, 1.4]
      animation.duration = 1.4
      animation.repeatCount = .infinity
      animation.isRemovedOnCompletion = false
      shimmer.add(animation, forKey: Self.animationKey)
    } else if !shouldAnimate {
      shimmer.removeAnimation(forKey: Self.animationKey)
    }
  }
}
