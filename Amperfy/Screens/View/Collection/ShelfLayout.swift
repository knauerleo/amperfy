//
//  ShelfLayout.swift
//  Amperfy
//
//  Fork: compositional layout sections for the streaming-style shelves. Independent of Home,
//  so any collection view (e.g. a later "Similar from YouTube" shelf) can reuse the same
//  styles together with TileCollectionCell, LargeAlbumCell and ArtistCircleCell.
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

// MARK: - ShelfStyle

enum ShelfStyle: Equatable {
  /// Vertical grid of compact tiles (cover left, name right), no horizontal scrolling.
  case tileGrid(columns: Int)
  /// Horizontal shelf of square covers in the stock size (AlbumCollectionCell).
  case standard
  /// Horizontal shelf of bigger square covers (LargeAlbumCell).
  case large
  /// Horizontal shelf of round artist images (ArtistCircleCell).
  case circle

  /// Placeholder cells shown while the shelf loads.
  var skeletonCount: Int {
    switch self {
    case let .tileGrid(columns): return columns * 3
    case .standard, .large, .circle: return 4
    }
  }
}

// MARK: - ShelfLayout

@MainActor
enum ShelfLayout {
  static let standardWidth: CGFloat = 160
  static let largeWidth: CGFloat = 200
  static let circleWidth: CGFloat = 128
  static let tileHeight: CGFloat = 56

  static let contentInsets = NSDirectionalEdgeInsets(
    top: DS.Space.xs,
    leading: DS.Space.m,
    bottom: DS.Space.l,
    trailing: DS.Space.m
  )

  static func section(_ style: ShelfStyle, withHeader: Bool = true) -> NSCollectionLayoutSection {
    let section: NSCollectionLayoutSection
    switch style {
    case let .tileGrid(columns):
      let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
        heightDimension: .absolute(tileHeight)
      ))
      let group = NSCollectionLayoutGroup.horizontal(
        layoutSize: NSCollectionLayoutSize(
          widthDimension: .fractionalWidth(1.0),
          heightDimension: .absolute(tileHeight)
        ),
        repeatingSubitem: item,
        count: columns
      )
      group.interItemSpacing = .fixed(DS.Space.xs)
      section = NSCollectionLayoutSection(group: group)
      section.interGroupSpacing = DS.Space.xs
    case .standard:
      section = horizontalShelf(width: standardWidth, estimatedHeight: 210)
    case .large:
      section = horizontalShelf(width: largeWidth, estimatedHeight: 250)
    case .circle:
      section = horizontalShelf(width: circleWidth, estimatedHeight: 160)
    }
    section.contentInsets = contentInsets
    if withHeader {
      section.boundarySupplementaryItems = [header()]
    }
    return section
  }

  static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
    let header = NSCollectionLayoutBoundarySupplementaryItem(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .fractionalWidth(1.0),
        heightDimension: .estimated(44)
      ),
      elementKind: UICollectionView.elementKindSectionHeader,
      alignment: .top
    )
    header.pinToVisibleBounds = false
    header.zIndex = 1
    return header
  }

  private static func horizontalShelf(
    width: CGFloat,
    estimatedHeight: CGFloat
  )
    -> NSCollectionLayoutSection {
    // same structure as the stock Home shelf: the cell sizes itself from its width
    let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
      widthDimension: .fractionalWidth(1.0),
      heightDimension: .fractionalHeight(1.0)
    ))
    let group = NSCollectionLayoutGroup.horizontal(
      layoutSize: NSCollectionLayoutSize(
        widthDimension: .absolute(width),
        heightDimension: .estimated(estimatedHeight)
      ),
      subitems: [item]
    )
    let section = NSCollectionLayoutSection(group: group)
    section.orthogonalScrollingBehavior = .continuous
    section.interGroupSpacing = DS.Space.s
    return section
  }
}
