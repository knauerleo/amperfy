//
//  LyricsCardView.swift
//  Amperfy
//
//  Fork: lyrics card under the cover in the player (design phase 5, measure 13).
//  Shows the current line and the next one, on a surface in the cover color.
//  A tap opens the full lyrics view of the player.
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
import CoreMedia
import UIKit

final class LyricsCardView: UIControl {
  static let height: CGFloat = 92

  private let headerLabel = UILabel()
  private let currentLabel = UILabel()
  private let nextLabel = UILabel()
  private var lyrics: StructuredLyrics?
  private var shownIndex: Int?

  /// Song the lyrics belong to, so a late answer for the previous song is ignored.
  var songID: String?

  var hasLyrics: Bool { lyrics?.line.contains { !$0.value.isEmpty } ?? false }

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = DS.Radius.large
    layer.cornerCurve = .continuous
    clipsToBounds = true
    backgroundColor = UIColor(white: 0.2, alpha: 1)

    headerLabel.text = "Lyrics"
    headerLabel.font = DS.Font.caption
    headerLabel.textColor = UIColor.white.withAlphaComponent(0.7)
    currentLabel.font = DS.Font.rowTitle.withBoldWeight()
    currentLabel.textColor = .white
    currentLabel.numberOfLines = 2
    nextLabel.font = DS.Font.cellSubtitle
    nextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
    nextLabel.numberOfLines = 1
    for label in [headerLabel, currentLabel, nextLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.adjustsFontSizeToFitWidth = true
      label.minimumScaleFactor = 0.8
    }

    let stack = UIStackView(arrangedSubviews: [headerLabel, currentLabel, nextLabel])
    stack.axis = .vertical
    stack.spacing = 2
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: DS.Space.xs),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityHint = "Shows all lyrics"
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isHighlighted: Bool {
    didSet {
      UIView.animate(withDuration: 0.15) {
        self.alpha = self.isHighlighted ? 0.7 : 1
      }
    }
  }

  func display(lyrics: StructuredLyrics?) {
    self.lyrics = lyrics
    shownIndex = nil
    if let lyrics, !lyrics.synced {
      let lines = lyrics.line.map(\.value).filter { !$0.isEmpty }
      setLines(current: lines.first ?? "", next: lines.dropFirst().first)
    } else {
      update(time: CMTime(seconds: appDelegate.player.elapsedTime, preferredTimescale: 1000))
    }
  }

  /// Follows the playback position, like the full lyrics view.
  func update(time: CMTime) {
    guard let lyrics, lyrics.synced, !lyrics.line.isEmpty else { return }
    let milliseconds = Int(time.seconds * 1000) + lyrics.offset
    let index = lyrics.line.lastIndex { ($0.start ?? 0) <= milliseconds }
    guard index != shownIndex || shownIndex == nil else { return }
    shownIndex = index
    if let index {
      let next = lyrics.line[(index + 1)...].first { !$0.value.isEmpty }?.value
      setLines(current: lyrics.line[index].value.isEmpty ? "♪" : lyrics.line[index].value, next: next)
    } else {
      // before the first line
      setLines(current: "♪", next: lyrics.line.first { !$0.value.isEmpty }?.value)
    }
  }

  /// Darkened cover color, so the white text stays readable in light and dark mode.
  func tint(with colors: [UIColor]) {
    guard let base = colors.first else { return }
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    else { return }
    backgroundColor = UIColor(
      hue: hue,
      saturation: min(1, saturation * 1.1),
      brightness: min(brightness, 0.75) * 0.6,
      alpha: 1
    )
  }

  private func setLines(current: String, next: String?) {
    currentLabel.text = current
    nextLabel.text = next ?? " "
    accessibilityLabel = "Lyrics: \(current)"
  }
}

extension UIFont {
  fileprivate func withBoldWeight() -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
    return UIFont(descriptor: descriptor, size: 0)
  }
}
