//
//  TileCollectionCell.swift
//  Amperfy
//
//  Fork: compact tile for the Recently Played grid on Home. Cover on the left, name on the right,
//  on a muted surface. Works with library entities, plain images (YouTube) and generated covers.
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

final class TileCollectionCell: UICollectionViewCell {
  static let reuseID = "TileCollectionCell"

  private let artwork = ShelfArtworkView()
  private let titleLabel = UILabel()
  private let titleBar = ShelfTextBar(widthFraction: 0.7)

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = DS.Color.tileSurface
    contentView.layer.cornerRadius = DS.Radius.small
    contentView.clipsToBounds = true
    artwork.cornerRadius = 0

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = DS.Font.tileTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label
    titleLabel.numberOfLines = 2

    contentView.addSubview(artwork)
    contentView.addSubview(titleLabel)
    contentView.addSubview(titleBar)
    NSLayoutConstraint.activate([
      artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
      artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      artwork.widthAnchor.constraint(equalTo: artwork.heightAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: DS.Space.xs),
      titleLabel.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -DS.Space.xs
      ),
      titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      titleBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      titleBar.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      titleBar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      titleBar.heightAnchor.constraint(equalToConstant: 12),
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
    setTitle(container.name)
  }

  /// For items outside the library, e.g. YouTube Music results.
  func display(title: String, image: UIImage?) {
    artwork.show(image: image)
    setTitle(title)
  }

  func display(title: String, generatedArtwork: UIView) {
    artwork.show(generated: generatedArtwork)
    setTitle(title)
  }

  func displaySkeleton() {
    artwork.showSkeleton()
    titleLabel.isHidden = true
    titleBar.isHidden = false
    // skeletons are hidden from VoiceOver until the real item arrives (UI-10)
    accessibilityLabel = nil
    isAccessibilityElement = false
    accessibilityElementsHidden = true
  }

  private func setTitle(_ title: String) {
    titleLabel.text = title
    titleLabel.isHidden = false
    titleBar.isHidden = true
    isAccessibilityElement = true
    accessibilityElementsHidden = false
    accessibilityLabel = title
  }
}
