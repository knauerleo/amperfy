//
//  AlbumsCollectionVC+Fork.swift
//  Amperfy
//
//  Fork: Library › Albums › All Albums shows the same LargeAlbumCell as the grid of the
//  library filter (UI-2). The flow layout stays, so the grid size setting, the section
//  headers and the index titles keep working. Mac Catalyst keeps AlbumCollectionCell.
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

extension AlbumsCollectionVC {
  /// Height below the cover: spacing, title and subtitle line of LargeAlbumCell.
  static var forkCaptionHeight: CGFloat {
    guard ForkSurface.isEnabled else { return 45 }
    return ceil(DS.Space.xs + DS.Font.shelfTitle.lineHeight + 2 + DS.Font.shelfSubtitle.lineHeight)
  }

  func forkRegisterAlbumCell() {
    guard ForkSurface.isEnabled else { return }
    collectionView.register(LargeAlbumCell.self, forCellWithReuseIdentifier: LargeAlbumCell.reuseID)
  }

  /// Returns nil on Mac Catalyst, the caller then falls back to AlbumCollectionCell.
  func forkCreateCell(_ collectionView: UICollectionView, at indexPath: IndexPath, album: Album)
    -> UICollectionViewCell? {
    guard ForkSurface.isEnabled,
          let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LargeAlbumCell.reuseID,
            for: indexPath
          ) as? LargeAlbumCell
    else { return nil }
    cell.display(container: album)
    return cell
  }
}
