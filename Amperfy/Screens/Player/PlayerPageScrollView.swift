//
//  PlayerPageScrollView.swift
//  Amperfy
//
//  Fork: the iPhone player scrolls as one page, like a streaming app. The first screen holds
//  cover and controls (the two placeholders of the XIB, moved in here), the lyrics card follows
//  right below the controls and peeks out at the lower edge (UI-27). Without lyrics, in the queue
//  and in the full lyrics the page does not scroll. Replaces the cover-only scroll view of UI-11.
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
  static let coverTopMargin: CGFloat = 12
  /// UI-21, UI-26: the header kept clear of the Dynamic Island (8 pt was still too close).
  static let headerTopMargin: CGFloat = 20
  /// UI-27: distance of the lyrics card from the controls, its top peeks out at the lower edge.
  private static let cardTopMargin = DS.Space.m

  let header: PlayerNowPlayingHeaderView
  let card = LyricsCardView()
  /// UI-27: everything of the page lives in this container. Its frame and the content size are set
  /// in `layoutSubviews`, Auto Layout works only inside it. With the content layout guide the
  /// content followed the offset on iOS 26 and the page did not move.
  let contentView = UIView()

  private weak var insetSource: UIView?
  private var pageHeightConstraint: NSLayoutConstraint?
  private var topConstraint: NSLayoutConstraint?
  private var bottomConstraint: NSLayoutConstraint?
  private var leadingConstraints = [NSLayoutConstraint]()
  private var trailingConstraints = [NSLayoutConstraint]()

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
    alwaysBounceVertical = false
    bounces = false
    isScrollEnabled = false
    decelerationRate = .fast

    // UI-27: the XIB places both placeholders against the root view and its safe area. Moving them
    // does not drop every one of these constraints (the cover kept its 20 pt below the safe area),
    // they would hold the page at a fixed screen position.
    let moved: [UIView] = [coverView, controlView]
    NSLayoutConstraint.deactivate(rootView.constraints.filter { constraint in
      moved.contains { $0 === constraint.firstItem || $0 === constraint.secondItem }
    })

    rootView.insertSubview(self, aboveSubview: belowView)
    addSubview(contentView)
    contentView.addSubview(header)
    for placeholder in [coverView, controlView] {
      placeholder.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(placeholder)
    }
    card.isHidden = true
    contentView.addSubview(card)

    let firstPage = UILayoutGuide()
    contentView.addLayoutGuide(firstPage)
    let firstPageHeight = firstPage.heightAnchor.constraint(equalToConstant: 0)
    pageHeightConstraint = firstPageHeight
    let top = header.topAnchor.constraint(equalTo: firstPage.topAnchor)
    let bottom = controlView.bottomAnchor.constraint(equalTo: firstPage.bottomAnchor)
    topConstraint = top
    bottomConstraint = bottom
    // Horizontal edges follow the root view's margins like in the XIB, as constants (`layoutSubviews`).
    let edges = [coverView, controlView].flatMap { placeholder in
      [
        placeholder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        placeholder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      ]
    }
    leadingConstraints = edges.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
    trailingConstraints = edges.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)

    NSLayoutConstraint.activate(edges + [
      topAnchor.constraint(equalTo: rootView.topAnchor),
      bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

      firstPage.topAnchor.constraint(equalTo: contentView.topAnchor),
      firstPage.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      firstPage.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      firstPageHeight,

      top,
      header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.xs),
      header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.xs),
      coverView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Self.coverTopMargin),
      controlView.topAnchor.constraint(equalTo: coverView.bottomAnchor),
      bottom,

      card.topAnchor.constraint(equalTo: controlView.bottomAnchor, constant: Self.cardTopMargin),
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.m),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    if let insetSource {
      pageHeightConstraint?.constant = bounds.height
      topConstraint?.constant = insetSource.safeAreaInsets.top + Self.headerTopMargin
      bottomConstraint?.constant = -insetSource.layoutMargins.bottom
      leadingConstraints.forEach { $0.constant = insetSource.layoutMargins.left }
      trailingConstraints.forEach { $0.constant = -insetSource.layoutMargins.right }
      // the first page fills the screen, the card follows the controls and ends above the home indicator
      var height = bounds.height
      if !card.isHidden {
        height = bounds.height - insetSource.layoutMargins.bottom + Self.cardTopMargin +
          LyricsCardView.height + insetSource.safeAreaInsets.bottom + DS.Space.m
      }
      let frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
      if contentView.frame != frame { contentView.frame = frame }
      if contentSize != frame.size { contentSize = frame.size }
    }
    super.layoutSubviews()
  }

  /// Horizontal swipes on the cover skip tracks, they must not start a scroll.
  /// UI-27: at the top a swipe down closes the player, the page must not take it.
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    if gestureRecognizer === panGestureRecognizer {
      let velocity = panGestureRecognizer.velocity(in: self)
      if abs(velocity.x) > abs(velocity.y) { return false }
      if isAtTop, velocity.y > 0 { return false }
    }
    return super.gestureRecognizerShouldBegin(gestureRecognizer)
  }

  /// Shows the card and allows scrolling to it, or hides it and returns to the first page.
  func setCardShown(_ isShown: Bool) {
    guard card.isHidden == isShown else { return }
    card.isHidden = !isShown
    isScrollEnabled = isShown
    if !isShown { scrollToTop(animated: false) }
    setNeedsLayout()
  }

  func scrollToTop(animated: Bool) {
    guard contentOffset.y != 0 else { return }
    setContentOffset(.zero, animated: animated)
  }

  var isAtTop: Bool { contentOffset.y <= 1 }
}
