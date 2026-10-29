//
//  ArtistCircleCell.swift
//  Amperfy
//
//  Fork: round artist image with the name centered below, for artist shelves.
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

final class ArtistCircleCell: UICollectionViewCell {
  static let reuseID = "ArtistCircleCell"

  private let artwork = ShelfArtworkView()
  private let nameLabel = UILabel()
  private let nameBar = ShelfTextBar(widthFraction: 1)

  override init(frame: CGRect) {
    super.init(frame: frame)
    artwork.isCircular = true

    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    nameLabel.font = DS.Font.shelfTitle
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.textColor = .label
    nameLabel.textAlignment = .center
    nameLabel.numberOfLines = 1

    contentView.addSubview(artwork)
    contentView.addSubview(nameLabel)
    contentView.addSubview(nameBar)
    NSLayoutConstraint.activate([
      artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
      artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
      nameLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: DS.Space.xs),
      nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      nameBar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      nameBar.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
      nameBar.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.6),
      nameBar.heightAnchor.constraint(equalToConstant: 12),
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
    setName(container.name)
  }

  /// For artists outside the library, e.g. YouTube Music results.
  func display(name: String, image: UIImage?) {
    artwork.show(image: image)
    setName(name)
  }

  func displaySkeleton() {
    artwork.showSkeleton()
    // keeps the label height so the skeleton is as tall as a real cell
    nameLabel.text = " "
    nameBar.isHidden = false
    // skeletons are hidden from VoiceOver until the real item arrives (UI-10)
    accessibilityLabel = nil
    isAccessibilityElement = false
    accessibilityElementsHidden = true
  }

  private func setName(_ name: String) {
    nameLabel.text = name
    nameBar.isHidden = true
    isAccessibilityElement = true
    accessibilityElementsHidden = false
    accessibilityLabel = name
  }
}
