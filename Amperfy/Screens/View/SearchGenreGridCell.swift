//
//  SearchGenreGridCell.swift
//  Amperfy
//
//  Fork: genre tiles on the search start page, a non-scrolling grid of TileCollectionCells
//  (ShelfLayout.tileGrid) inside one table row. Each tile is tinted with a color of one of its covers.
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

final class SearchGenreGridCell: UITableViewCell {
  static let reuseID = "SearchGenreGridCell"
  static let columns = 2

  var onSelect: ((Genre) -> ())?

  private var genres = [Genre]()
  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewCompositionalLayout(
      section: ShelfLayout.section(.tileGrid(columns: Self.columns), withHeader: false)
    )
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.isScrollEnabled = false
    view.register(TileCollectionCell.self, forCellWithReuseIdentifier: TileCollectionCell.reuseID)
    view.dataSource = self
    view.delegate = self
    return view
  }()

  static func height(itemCount: Int) -> CGFloat {
    guard itemCount > 0 else { return 0 }
    let rows = CGFloat((itemCount + columns - 1) / columns)
    let insets = ShelfLayout.contentInsets
    return insets.top + insets.bottom + rows * ShelfLayout.tileHeight + (rows - 1) * DS.Space.xs
  }

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      collectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(genres: [Genre]) {
    self.genres = genres
    collectionView.reloadData()
  }

  /// First cached album cover of the genre, the genre itself has no image on Subsonic servers.
  private static func coverImage(of genre: Genre) -> UIImage? {
    for album in genre.albums.prefix(12) {
      if let path = album.artwork?.imagePath, let image = UIImage(contentsOfFile: path) {
        return image
      }
    }
    return nil
  }

  /// Stable color per genre name until the cover color is known.
  private static func fallbackTint(for name: String) -> UIColor {
    let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
    return UIColor(hue: CGFloat(hash % 360) / 360, saturation: 0.55, brightness: 0.7, alpha: 1)
  }

  fileprivate static func tileBackground(_ tint: UIColor) -> UIColor {
    tint.withAlphaComponent(0.35)
  }
}

// MARK: UICollectionViewDataSource, UICollectionViewDelegate

extension SearchGenreGridCell: UICollectionViewDataSource, UICollectionViewDelegate {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int {
    genres.count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  )
    -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TileCollectionCell.reuseID,
      for: indexPath
    ) as! TileCollectionCell
    let genre = genres[indexPath.item]
    let name = genre.name
    cell.contentView.backgroundColor = Self.tileBackground(Self.fallbackTint(for: name))
    guard let image = Self.coverImage(of: genre) else {
      cell.display(container: genre)
      return cell
    }
    cell.display(title: name, image: image)
    if let colors = ArtworkColorCache.shared.cachedColors(for: image), let tint = colors.first {
      cell.contentView.backgroundColor = Self.tileBackground(tint)
    } else {
      Task { @MainActor [weak cell] in
        guard let tint = await ArtworkColorCache.shared.colors(for: image)?.first,
              let cell, cell.accessibilityLabel == name else { return }
        UIView.animate(withDuration: 0.2) {
          cell.contentView.backgroundColor = Self.tileBackground(tint)
        }
      }
    }
    return cell
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard indexPath.item < genres.count else { return }
    onSelect?(genres[indexPath.item])
  }
}
