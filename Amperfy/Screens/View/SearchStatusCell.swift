//
//  SearchStatusCell.swift
//  Amperfy
//
//  Fork: one quiet row inside a search section, e.g. "Searching YouTube Music…" with a spinner.
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

final class SearchStatusCell: UITableViewCell {
  static let reuseID = "SearchStatusCell"
  static let rowHeight: CGFloat = 52

  private let spinner = UIActivityIndicatorView(style: .medium)
  private let label = UILabel()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    label.font = DS.Font.cellSubtitle
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.numberOfLines = 2
    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .horizontal
    stack.spacing = DS.Space.s
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DS.Space.m),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: contentView.trailingAnchor,
        constant: -DS.Space.m
      ),
      stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(text: String, isLoading: Bool) {
    label.text = text
    // read as one line, the spinner itself says nothing (UI-10)
    isAccessibilityElement = true
    accessibilityLabel = text
    accessibilityTraits = isLoading ? [.staticText, .updatesFrequently] : .staticText
    spinner.isHidden = !isLoading
    if isLoading {
      spinner.startAnimating()
    } else {
      spinner.stopAnimating()
    }
  }
}
