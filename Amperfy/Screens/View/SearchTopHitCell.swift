//
//  SearchTopHitCell.swift
//  Amperfy
//
//  Fork: bigger card for the best search result. A YouTube Music result gets a small text label
//  "YouTube Music" and the status badge.
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

final class SearchTopHitCell: UITableViewCell {
  static let reuseID = "SearchTopHitCell"
  static let artworkSize: CGFloat = 88
  static let rowHeight: CGFloat = artworkSize + 2 * DS.Space.s + DS.Space.xs

  private let card = UIView()
  private let artwork = ShelfArtworkView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let sourceLabel = UILabel()
  private let badge = SourceBadgeView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear

    card.translatesAutoresizingMaskIntoConstraints = false
    card.backgroundColor = DS.Color.tileSurface
    card.layer.cornerRadius = DS.Radius.large
    card.layer.cornerCurve = .continuous

    titleLabel.font = DS.Font.sectionTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.75
    subtitleLabel.font = DS.Font.rowSubtitle
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    sourceLabel.font = DS.Font.caption
    sourceLabel.adjustsFontForContentSizeCategory = true
    sourceLabel.textColor = .secondaryLabel
    sourceLabel.text = "YouTube Music"

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, sourceLabel])
    textStack.axis = .vertical
    textStack.spacing = DS.Space.xxs
    textStack.translatesAutoresizingMaskIntoConstraints = false
    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.setContentHuggingPriority(.required, for: .horizontal)

    contentView.addSubview(card)
    card.addSubview(artwork)
    card.addSubview(textStack)
    card.addSubview(badge)
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DS.Space.m),
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DS.Space.xxs),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DS.Space.xxs),
      artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: DS.Space.s),
      artwork.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      artwork.widthAnchor.constraint(equalToConstant: Self.artworkSize),
      artwork.heightAnchor.constraint(equalToConstant: Self.artworkSize),
      textStack.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: DS.Space.m),
      textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      textStack.trailingAnchor.constraint(
        lessThanOrEqualTo: badge.leadingAnchor,
        constant: -DS.Space.xs
      ),
      badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -DS.Space.m),
      badge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      badge.widthAnchor.constraint(equalToConstant: SourceBadgeView.size),
      badge.heightAnchor.constraint(equalToConstant: SourceBadgeView.size),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func setHighlighted(_ highlighted: Bool, animated: Bool) {
    super.setHighlighted(highlighted, animated: animated)
    UIView.animate(withDuration: 0.15) {
      self.card.alpha = highlighted ? 0.6 : 1
    }
  }

  /// Library result: artist (round cover), album, playlist or song.
  func display(container: PlayableContainable, kind: String) {
    artwork.isCircular = container is Artist
    artwork.cornerRadius = DS.Radius.medium
    artwork.show(container: container)
    titleLabel.text = container.name
    let subtitle = (container is Artist) ? nil : container.subtitle
    subtitleLabel.text = [kind, subtitle].compactMap { $0 }.joined(separator: " · ")
    sourceLabel.isHidden = true
    badge.isHidden = true
    updateAccessibility()
  }

  /// YouTube Music result, `song` is its placeholder for the cover.
  func display(hit: SongpickerHit, song: Song?, status: YouTubeMusicStatus) {
    artwork.isCircular = false
    artwork.cornerRadius = DS.Radius.medium
    if let song {
      artwork.show(container: song)
    } else {
      artwork.show(image: nil)
    }
    titleLabel.text = hit.title
    subtitleLabel.text = String(localized: "Song · \(hit.artist)", table: "Fork")
    sourceLabel.isHidden = false
    badge.isHidden = false
    badge.status = status
    updateAccessibility()
  }

  func update(status: YouTubeMusicStatus) {
    badge.status = status
    updateAccessibility()
  }

  private func updateAccessibility() {
    let source = sourceLabel.isHidden ? nil : "YouTube Music"
    let state = badge.isHidden ? nil : badge.accessibilityLabel
    accessibilityLabel = [String(localized: "Top Result", table: "Fork"), titleLabel.text, subtitleLabel.text, source, state]
      .compactMap { $0 }
      .joined(separator: ", ")
  }
}
