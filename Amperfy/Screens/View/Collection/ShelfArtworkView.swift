//
//  ShelfArtworkView.swift
//  Amperfy
//
//  Fork: cover area shared by the shelf cells. Shows a library entity (with the usual artwork
//  download and playlist collage), a plain image for items outside the library (YouTube),
//  a generated gradient cover or a skeleton placeholder.
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

final class ShelfArtworkView: UIView {
  /// Corner radius of the cover, ignored when `isCircular` is set.
  var cornerRadius: CGFloat = DS.Radius.small {
    didSet { setNeedsLayout() }
  }

  var isCircular = false {
    didSet { setNeedsLayout() }
  }

  private let entityImage = EntityImageView(frame: .zero)
  private let plainImage = UIImageView()
  private let skeleton = SkeletonView(cornerRadius: 0)
  private var generated: UIView?

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    clipsToBounds = true
    backgroundColor = DS.Color.skeleton
    plainImage.contentMode = .scaleAspectFill
    plainImage.clipsToBounds = true
    for view in [entityImage, plainImage, skeleton] as [UIView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
      pin(view)
    }
    showOnly(nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = isCircular ? bounds.width / 2 : cornerRadius
  }

  func show(container: PlayableContainable) {
    let theme = appDelegate.storage.settings.accounts.getSetting(container.account?.info).read
      .themePreference
    entityImage.display(theme: theme, container: container, cornerRadius: .verySmall)
    // this view clips the corners itself
    entityImage.layer.cornerRadius = 0
    showOnly(entityImage)
  }

  func show(image: UIImage?) {
    plainImage.image = image
    showOnly(plainImage)
  }

  func show(generated view: UIView) {
    generated?.removeFromSuperview()
    view.translatesAutoresizingMaskIntoConstraints = false
    insertSubview(view, belowSubview: skeleton)
    pin(view)
    generated = view
    showOnly(view)
  }

  func showSkeleton() {
    showOnly(skeleton)
  }

  private func showOnly(_ visible: UIView?) {
    entityImage.isHidden = visible !== entityImage
    plainImage.isHidden = visible !== plainImage
    skeleton.isHidden = visible !== skeleton
    generated?.isHidden = visible !== generated
    backgroundColor = visible === skeleton ? .clear : DS.Color.skeleton
  }

  private func pin(_ view: UIView) {
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: topAnchor),
      view.bottomAnchor.constraint(equalTo: bottomAnchor),
      view.leadingAnchor.constraint(equalTo: leadingAnchor),
      view.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }
}

// MARK: - ShelfTextBar

/// Rounded bar standing in for a label while a cell shows its skeleton.
final class ShelfTextBar: UIView {
  private let skeleton = SkeletonView(cornerRadius: DS.Radius.small)

  init(widthFraction: CGFloat) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    isUserInteractionEnabled = false
    addSubview(skeleton)
    NSLayoutConstraint.activate([
      skeleton.leadingAnchor.constraint(equalTo: leadingAnchor),
      skeleton.centerYAnchor.constraint(equalTo: centerYAnchor),
      skeleton.heightAnchor.constraint(equalToConstant: 10),
      skeleton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: widthFraction),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
