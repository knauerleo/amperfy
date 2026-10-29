//
//  PlayerCoverScrollView.swift
//  Amperfy
//
//  Fork (UI-11): the lyrics card sits below the cover instead of taking height from it.
//  The large player view keeps the full height of its placeholder, the card follows below
//  and is reached by scrolling up. Without lyrics the view does not scroll at all.
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

final class PlayerCoverScrollView: UIScrollView {
  let card = LyricsCardView()

  init(largeView: UIView) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    alwaysBounceVertical = true
    isScrollEnabled = false

    largeView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(largeView)
    card.isHidden = true
    addSubview(card)

    NSLayoutConstraint.activate([
      largeView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      largeView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
      largeView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
      largeView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
      largeView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),

      card.topAnchor.constraint(equalTo: largeView.bottomAnchor, constant: DS.Space.xs),
      card.leadingAnchor.constraint(
        equalTo: frameLayoutGuide.leadingAnchor,
        constant: UIView.defaultMarginCellX
      ),
      card.trailingAnchor.constraint(
        equalTo: frameLayoutGuide.trailingAnchor,
        constant: -UIView.defaultMarginCellX
      ),
      card.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -DS.Space.m),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Horizontal swipes on the cover skip tracks, they must not start a scroll.
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer {
      let velocity = panGestureRecognizer.velocity(in: self)
      if abs(velocity.x) > abs(velocity.y) { return false }
    }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }

  /// Shows the card and allows scrolling to it, or hides it and returns to the cover.
  func setCardShown(_ isShown: Bool) {
    guard card.isHidden == isShown else { return }
    card.isHidden = !isShown
    isScrollEnabled = isShown
    if !isShown {
      scrollToCover(animated: false)
    }
  }

  func scrollToCover(animated: Bool) {
    guard contentOffset.y != 0 else { return }
    setContentOffset(.zero, animated: animated)
  }

  var isAtCover: Bool { contentOffset.y <= 1 }

  /// How far the content was pulled up past its end.
  var overscrollAtBottom: CGFloat {
    let maxOffset = max(0, contentSize.height - bounds.height)
    return contentOffset.y - maxOffset
  }
}
