//
//  LyricsView+Fork.swift
//  Amperfy
//
//  Fork (UI-6): full lyrics in the player in the style of the lyrics card.
//  Large bold lines on a surface in the darkened cover color, the current line bright,
//  the others dimmed. Tapping a line still seeks there (LyricsView.onLyricSelected).
//  Only the player on the iPhone uses this style, the lyrics sidebar (iPad, Mac) stays as is.
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

// MARK: - LyricTableCellModel

extension LyricTableCellModel {
  /// Text inset inside the backdrop, in addition to the cell margin.
  static let forkCardTextInset: CGFloat = DS.Space.m

  /// Hook in `LyricsView.reloadViewModels`: replaces the fixed 20 pt fonts.
  func forkApplyCardStyle() {
    let text = lyric?.value ?? ""
    attributedString = NSAttributedString(
      string: text,
      attributes: Self.forkAttributes(color: UIColor.white.withAlphaComponent(0.45))
    )
    highlightedAttributedString = NSAttributedString(
      string: text,
      attributes: Self.forkAttributes(color: .white)
    )
  }

  private static func forkAttributes(color: UIColor) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .natural
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.firstLineHeadIndent = forkCardTextInset
    paragraph.headIndent = forkCardTextInset
    paragraph.tailIndent = -forkCardTextInset
    return [
      .font: DS.Font.lyricsLine,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ]
  }
}

// MARK: - LyricsBackdropView

/// Surface behind the full lyrics, same color as the lyrics card.
final class LyricsBackdropView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = false
    isHidden = true
    layer.cornerRadius = DS.Radius.large
    layer.cornerCurve = .continuous
    backgroundColor = LyricsCardView.defaultSurfaceColor
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func tint(with colors: [UIColor]) {
    guard let color = LyricsCardView.surfaceColor(for: colors) else { return }
    backgroundColor = color
  }
}

// MARK: - LargeCurrentlyPlayingPlayerView

extension LargeCurrentlyPlayingPlayerView {
  /// Hook in `prepare`, right after the lyrics view was added.
  func forkPrepareLyrics(_ lyricsView: LyricsView) {
    guard ForkPlayerTransition.isActive else { return }
    lyricsView.forkCardStyle = true
    let backdrop = LyricsBackdropView()
    upperContainerView.insertSubview(backdrop, belowSubview: lyricsView)
    NSLayoutConstraint.activate([
      backdrop.topAnchor.constraint(equalTo: upperContainerView.topAnchor),
      backdrop.bottomAnchor.constraint(equalTo: upperContainerView.bottomAnchor),
      backdrop.leadingAnchor.constraint(
        equalTo: upperContainerView.leadingAnchor,
        constant: UIView.defaultMarginCellX
      ),
      backdrop.trailingAnchor.constraint(
        equalTo: upperContainerView.trailingAnchor,
        constant: -UIView.defaultMarginCellX
      ),
    ])
  }

  var forkLyricsBackdrop: LyricsBackdropView? {
    upperContainerView.subviews.lazy.compactMap { $0 as? LyricsBackdropView }.first
  }

  /// Shows the backdrop while the full lyrics are displayed.
  func forkRefreshLyricsBackdrop(colors: [UIColor]) {
    guard let backdrop = forkLyricsBackdrop else { return }
    backdrop.tint(with: colors)
    backdrop.isHidden = !isLyricsViewAllowedToDisplay
  }
}
