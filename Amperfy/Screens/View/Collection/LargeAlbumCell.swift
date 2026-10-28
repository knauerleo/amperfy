//
//  LargeAlbumCell.swift
//  Amperfy
//
//  Fork: bigger square cover with title and subtitle, for highlighted album shelves.
//  Sizes itself from the width the layout gives it, so it also serves as skeleton for
//  shelves of the stock size.
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

final class LargeAlbumCell: UICollectionViewCell {
  static let reuseID = "LargeAlbumCell"

  private let artwork = ShelfArtworkView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let titleBar = ShelfTextBar(widthFraction: 0.8)
  private let subtitleBar = ShelfTextBar(widthFraction: 0.5)

  override init(frame: CGRect) {
    super.init(frame: frame)
    artwork.cornerRadius = DS.Radius.medium

    titleLabel.font = DS.Font.shelfTitle
    titleLabel.textColor = .label
    subtitleLabel.font = DS.Font.shelfSubtitle
    subtitleLabel.textColor = .secondaryLabel
    for label in [titleLabel, subtitleLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      label.adjustsFontForContentSizeCategory = true
      label.numberOfLines = 1
    }

    let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    textStack.axis = .vertical
    textStack.spacing = 2
    textStack.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(artwork)
    contentView.addSubview(textStack)
    contentView.addSubview(titleBar)
    contentView.addSubview(subtitleBar)
    NSLayoutConstraint.activate([
      artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
      artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
      textStack.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: DS.Space.xs),
      textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      titleBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      titleBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      titleBar.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
      titleBar.heightAnchor.constraint(equalToConstant: 12),
      subtitleBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      subtitleBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      subtitleBar.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
      subtitleBar.heightAnchor.constraint(equalToConstant: 12),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isHighlighted: Bool {
    didSet {
      UIView.animate(withDuration: 0.15) {
        self.contentView.alpha = self.isHighlighted ? 0.6 : 1
      }
    }
  }

  func display(container: PlayableContainable) {
    artwork.show(container: container)
    setText(title: container.name, subtitle: container.subtitle)
  }

  /// For albums outside the library, e.g. YouTube Music results.
  func display(title: String, subtitle: String?, image: UIImage?) {
    artwork.show(image: image)
    setText(title: title, subtitle: subtitle)
  }

  func displaySkeleton() {
    artwork.showSkeleton()
    // placeholder text keeps the real cell height
    titleLabel.text = " "
    subtitleLabel.text = " "
    subtitleLabel.isHidden = false
    titleBar.isHidden = false
    subtitleBar.isHidden = false
    accessibilityLabel = "Loading"
  }

  private func setText(title: String, subtitle: String?) {
    titleLabel.text = title
    // self-titled releases would repeat the name ("Valentine's Day / Valentine's Day")
    let shownSubtitle = (subtitle == title) ? nil : subtitle
    subtitleLabel.text = shownSubtitle ?? " "
    titleBar.isHidden = true
    subtitleBar.isHidden = true
    accessibilityLabel = [title, shownSubtitle].compactMap { $0 }.joined(separator: ", ")
  }
}
