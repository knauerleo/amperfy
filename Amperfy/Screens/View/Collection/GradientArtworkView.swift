//
//  GradientArtworkView.swift
//  Amperfy
//
//  Fork: generated cover for entries that are not a single library entity, e.g. Favorite Songs.
//  A diagonal gradient with a centered symbol. Later also usable for "Downloads" or YouTube mixes.
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

final class GradientArtworkView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  private let symbolView = UIImageView()

  init(colors: [UIColor], symbol: UIImage) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true
    isUserInteractionEnabled = false
    let gradient = layer as! CAGradientLayer
    gradient.colors = colors.map(\.cgColor)
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)

    symbolView.image = symbol.withRenderingMode(.alwaysTemplate)
    symbolView.tintColor = .white
    symbolView.contentMode = .scaleAspectFit
    symbolView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(symbolView)
    NSLayoutConstraint.activate([
      symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
      symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbolView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.42),
      symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor),
    ])
  }

  static func favoriteSongs() -> GradientArtworkView {
    GradientArtworkView(colors: DS.Color.favoritesGradient, symbol: .heartFill)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
