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

  /// Fork (F-11/F-12): big text instead of a symbol, e.g. "90s" for a decade.
  init(colors: [UIColor], text: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true
    isUserInteractionEnabled = false
    let gradient = layer as! CAGradientLayer
    gradient.colors = colors.map(\.cgColor)
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)

    let label = UILabel()
    label.text = text
    label.textColor = .white
    label.font = .systemFont(ofSize: 44, weight: .heavy)
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.4
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.8),
    ])
  }

  /// Two colors from a hue, stable for the same seed (decades, mixes).
  static func colors(hue: CGFloat) -> [UIColor] {
    let base = hue.truncatingRemainder(dividingBy: 1)
    return [
      UIColor(hue: base, saturation: 0.65, brightness: 0.85, alpha: 1),
      UIColor(hue: (base + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.45, alpha: 1),
    ]
  }

  static func favoriteSongs() -> GradientArtworkView {
    GradientArtworkView(colors: DS.Color.favoritesGradient, symbol: .heartFill)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
