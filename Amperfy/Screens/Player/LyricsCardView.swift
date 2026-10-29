//
//  LyricsCardView.swift
//  Amperfy
//
//  Fork: lyrics card below the player controls, reached by scrolling the player down.
//  Shows a window of lines around the current one (current line white, the others dimmed),
//  on a surface in the cover color. A tap opens the full lyrics view of the player.
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
  /// Lines shown at once: one before the current line, the current one and the following.
  private static let visibleLineCount = 7
  private static let linesBefore = 1
  private static let dimmedAlpha: CGFloat = 0.45

  private let headerLabel = UILabel()
  private let expandIcon = UIImageView()
  private let linesContainer = UIView()
  private let linesStack = UIStackView()
  private let fadeMask = CAGradientLayer()
  private var lineLabels = [UILabel]()
  private var lyrics: StructuredLyrics?
  private var shownIndex: Int?

  /// Song the lyrics belong to, so a late answer for the previous song is ignored.
  var songID: String?

  var hasLyrics: Bool { lyrics?.line.contains { !$0.value.isEmpty } ?? false }

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = DS.Radius.card
    layer.cornerCurve = .continuous
    clipsToBounds = true
    backgroundColor = Self.defaultSurfaceColor

    headerLabel.text = String(localized: "Lyrics", table: "Fork")
    headerLabel.font = DS.Font.lyricsCardHeader
    headerLabel.textColor = .white
    headerLabel.adjustsFontForContentSizeCategory = true
    expandIcon.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right")
    expandIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
    expandIcon.tintColor = UIColor.white.withAlphaComponent(0.8)
    expandIcon.contentMode = .center
    expandIcon.setContentHuggingPriority(.required, for: .horizontal)

    let header = UIStackView(arrangedSubviews: [headerLabel, expandIcon])
    header.axis = .horizontal
    header.alignment = .center
    header.isUserInteractionEnabled = false
    header.translatesAutoresizingMaskIntoConstraints = false
    addSubview(header)

    linesStack.axis = .vertical
    linesStack.spacing = DS.Space.s
    linesStack.isUserInteractionEnabled = false
    linesStack.translatesAutoresizingMaskIntoConstraints = false
    for _ in 0 ..< Self.visibleLineCount {
      let label = UILabel()
      label.font = DS.Font.lyricsCardLine
      label.adjustsFontForContentSizeCategory = true
      label.numberOfLines = 0
      label.textColor = UIColor.white.withAlphaComponent(Self.dimmedAlpha)
      lineLabels.append(label)
      linesStack.addArrangedSubview(label)
    }
    linesContainer.isUserInteractionEnabled = false
    linesContainer.clipsToBounds = true
    linesContainer.translatesAutoresizingMaskIntoConstraints = false
    linesContainer.addSubview(linesStack)
    // the lines fade out at the lower edge instead of being cut off
    fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    fadeMask.locations = [0, 0.75, 1]
    linesContainer.layer.mask = fadeMask
    addSubview(linesContainer)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: Self.height),
      header.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.m),
      header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      linesContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DS.Space.m),
      linesContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.m),
      linesContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.m),
      linesContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.xs),
      linesStack.topAnchor.constraint(equalTo: linesContainer.topAnchor),
      linesStack.leadingAnchor.constraint(equalTo: linesContainer.leadingAnchor),
      linesStack.trailingAnchor.constraint(equalTo: linesContainer.trailingAnchor),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityHint = String(localized: "Shows all lyrics", table: "Fork")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Fixed height, so the page does not jump while the lines change.
  static var height: CGFloat {
    UIFontMetrics(forTextStyle: .title3).scaledValue(for: 380)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fadeMask.frame = linesContainer.bounds
    CATransaction.commit()
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
      // unsynced: the beginning of the text, all lines readable
      let lines = lyrics.line.map(\.value).filter { !$0.isEmpty }
      setLines(Array(lines.prefix(Self.visibleLineCount)), current: nil)
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
    let texts = lyrics.line.map { $0.value.isEmpty ? "♪" : $0.value }
    guard let index else {
      // before the first line
      setLines(Array(texts.prefix(Self.visibleLineCount)), current: nil)
      return
    }
    let start = max(0, index - Self.linesBefore)
    let end = min(texts.count, start + Self.visibleLineCount)
    setLines(Array(texts[start ..< end]), current: index - start)
  }

  /// Darkened cover color, so the white text stays readable in light and dark mode.
  func tint(with colors: [UIColor]) {
    guard let color = Self.surfaceColor(for: colors) else { return }
    backgroundColor = color
  }

  static let defaultSurfaceColor = UIColor(white: 0.2, alpha: 1)

  /// Surface of the card and of the full lyrics view (UI-6).
  static func surfaceColor(for colors: [UIColor]) -> UIColor? {
    guard let base = colors.first else { return nil }
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    else { return nil }
    return UIColor(
      hue: hue,
      saturation: min(1, saturation * 1.1),
      brightness: min(brightness, 0.75) * 0.6,
      alpha: 1
    )
  }

  /// `current` is the index of the playing line in `lines`, nil shows all lines readable.
  private func setLines(_ lines: [String], current: Int?) {
    for (offset, label) in lineLabels.enumerated() {
      label.isHidden = offset >= lines.count
      label.text = offset < lines.count ? lines[offset] : nil
      let isReadable = current == nil || current == offset
      label.textColor = UIColor.white.withAlphaComponent(isReadable ? 1 : Self.dimmedAlpha)
    }
    let spoken = current.map { lines[$0] } ?? lines.first ?? ""
    accessibilityLabel = String(localized: "Lyrics: \(spoken)", table: "Fork")
  }
}
