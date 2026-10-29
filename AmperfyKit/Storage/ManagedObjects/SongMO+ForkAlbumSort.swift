//
//  SongMO+ForkAlbumSort.swift
//  AmperfyKit
//
//  Fork (F-20): album pages and album playback sort by track number 1 → n. The disc only breaks ties, because the
//  album page shows no discs and a missing disc tag (e.g. songs from the YouTube path) would
//  otherwise move the tagged songs to the end.
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

import CoreData
import Foundation

extension SongMO {
  static var forkAlbumTrackSortDescriptors: [NSSortDescriptor] {
    [
      NSSortDescriptor(key: #keyPath(SongMO.track), ascending: true),
      NSSortDescriptor(
        key: #keyPath(SongMO.disk),
        ascending: true,
        selector: #selector(NSString.localizedStandardCompare)
      ),
      NSSortDescriptor(
        key: Self.identifierKeyString,
        ascending: true,
        selector: #selector(NSString.localizedStandardCompare)
      ),
    ]
  }
}

extension Array where Element: Song {
  /// Same order as `forkAlbumTrackSortDescriptors`, for `Album.songs` (play order of the album).
  func forkSortByAlbumTrack() -> [Element] {
    sorted {
      if $0.track != $1.track {
        return $0.track < $1.track
      } else if $0.disk != $1.disk {
        return ($0.disk ?? "").localizedStandardCompare($1.disk ?? "") == .orderedAscending
      } else {
        return $0.id < $1.id
      }
    }
  }
}
