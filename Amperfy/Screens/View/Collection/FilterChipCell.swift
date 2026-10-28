//
//  FilterChipCell.swift
//  Amperfy
//
//  Fork: filter chip of the Library grid (Playlists, Albums, Artists, Downloads).
//  Selected = filled in the label color, otherwise a muted surface.
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

final class FilterChipCell: UICollectionViewCell {
  static let reuseID = "FilterChipCell"
  static let height: CGFloat = 34

  private let titleLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.layer.cornerRadius = Self.height / 2
    contentView.clipsToBounds = true

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = DS.Font.shelfTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    contentView.addSubview(titleLabel)
    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      titleLabel.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor,
        constant: -DS.Space.m
      ),
      titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      contentView.heightAnchor.constraint(equalToConstant: Self.height),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
    updateColors()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var isChipSelected = false {
    didSet { updateColors() }
  }

  override var isHighlighted: Bool {
    didSet {
      UIView.animate(withDuration: 0.15) {
        self.contentView.alpha = self.isHighlighted ? 0.6 : 1
      }
    }
  }

  func display(title: String, isSelected: Bool) {
    titleLabel.text = title
    accessibilityLabel = title
    isChipSelected = isSelected
  }

  private func updateColors() {
    contentView.backgroundColor = isChipSelected ? .label : DS.Color.tileSurface
    titleLabel.textColor = isChipSelected ? .systemBackground : .label
    accessibilityTraits = isChipSelected ? [.button, .selected] : .button
  }
}
