//
//  PlayerPageScrollView.swift
//  Amperfy
//
//  Fork: the iPhone player scrolls as one page, like a streaming app. The first screen holds
//  cover and controls (the two placeholders of the XIB, moved in here), the lyrics card follows
//  below and is reached by scrolling down. Without lyrics, in the queue and in the full lyrics
//  the page does not scroll. Replaces the cover-only scroll view of UI-11.
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

final class PlayerPageScrollView: UIScrollView {
  /// Distance of the cover from the header.
  private static let coverTopMargin: CGFloat = 12
  /// UI-21, UI-26: the header kept clear of the Dynamic Island (8 pt was still too close).
  private static let headerTopMargin: CGFloat = 20

  let header: PlayerNowPlayingHeaderView
  let card = LyricsCardView()
  /// The first screen: cover and controls, exactly as high as the player.
  let firstPage = UILayoutGuide()

  private weak var insetSource: UIView?
  private var topConstraint: NSLayoutConstraint?
  private var bottomConstraint: NSLayoutConstraint?
  private var cardBottomConstraint: NSLayoutConstraint?
  private var pageEndConstraint: NSLayoutConstraint?

  /// Adds the page to the player's root view right above `belowView` and moves both placeholders
  /// into it. The root view's safe area and margins place the first page like the XIB did.
  init(
    header: PlayerNowPlayingHeaderView,
    coverView: UIView,
    controlView: UIView,
    rootView: UIView,
    above belowView: UIView
  ) {
    self.header = header
    insetSource = rootView
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    alwaysBounceVertical = true
    isScrollEnabled = false
    decelerationRate = .fast

    rootView.insertSubview(self, aboveSubview: belowView)
    addLayoutGuide(firstPage)
    addSubview(header)
    for placeholder in [coverView, controlView] {
      placeholder.translatesAutoresizingMaskIntoConstraints = false
      addSubview(placeholder)
    }
    card.isHidden = true
    addSubview(card)

    let top = header.topAnchor.constraint(equalTo: firstPage.topAnchor)
    let bottom = controlView.bottomAnchor.constraint(equalTo: firstPage.bottomAnchor)
    let cardBottom = card.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
    let pageEnd = firstPage.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
    topConstraint = top
    bottomConstraint = bottom
    cardBottomConstraint = cardBottom
    pageEndConstraint = pageEnd

    // Horizontal edges follow the root view's margins like in the XIB (the page never scrolls sideways).
    NSLayoutConstraint.activate([
      topAnchor.constraint(equalTo: rootView.topAnchor),
      bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

      firstPage.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      firstPage.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
      firstPage.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
      firstPage.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
      firstPage.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),

      top,
      header.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor, constant: DS.Space.xs),
      header.trailingAnchor.constraint(equalTo: frameLayoutGuide.trailingAnchor, constant: -DS.Space.xs),
      coverView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Self.coverTopMargin),
      coverView.leadingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.leadingAnchor),
      coverView.trailingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.trailingAnchor),
      controlView.topAnchor.constraint(equalTo: coverView.bottomAnchor),
      controlView.leadingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.leadingAnchor),
      controlView.trailingAnchor.constraint(equalTo: rootView.layoutMarginsGuide.trailingAnchor),
      bottom,

      card.topAnchor.constraint(equalTo: firstPage.bottomAnchor),
      card.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor, constant: DS.Space.m),
      card.trailingAnchor.constraint(equalTo: frameLayoutGuide.trailingAnchor, constant: -DS.Space.m),
      pageEnd,
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    if let insetSource {
      topConstraint?.constant = insetSource.safeAreaInsets.top + Self.headerTopMargin
      bottomConstraint?.constant = -insetSource.layoutMargins.bottom
      cardBottomConstraint?.constant = -(insetSource.safeAreaInsets.bottom + DS.Space.m)
    }
    super.layoutSubviews()
  }

  /// Horizontal swipes on the cover skip tracks, they must not start a scroll.
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer {
      let velocity = panGestureRecognizer.velocity(in: self)
      if abs(velocity.x) > abs(velocity.y) { return false }
    }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }

  /// Shows the card and allows scrolling to it, or hides it and returns to the first page.
  func setCardShown(_ isShown: Bool) {
    guard card.isHidden == isShown else { return }
    card.isHidden = !isShown
    isScrollEnabled = isShown
    // only one of the two may end the content
    if isShown {
      pageEndConstraint?.isActive = false
      cardBottomConstraint?.isActive = true
    } else {
      cardBottomConstraint?.isActive = false
      pageEndConstraint?.isActive = true
      scrollToTop(animated: false)
    }
  }

  func scrollToTop(animated: Bool) {
    guard contentOffset.y != 0 else { return }
    setContentOffset(.zero, animated: animated)
  }

  var isAtTop: Bool { contentOffset.y <= 1 }
}
