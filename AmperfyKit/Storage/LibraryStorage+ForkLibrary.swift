//
//  LibraryStorage+ForkLibrary.swift
//  AmperfyKit
//
//  Fork: data of the Library grid (design phase 5). Recently used first, the rest by name.
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

extension LibraryStorage {
  /// Played ones by `lastPlayedDate` (newest first), never played ones alphabetically after them.
  private static func recentFirstSort(lastPlayedKey: String, nameKey: String) -> [NSSortDescriptor] {
    // SQLite sorts NULL last in descending order, so unplayed entries follow the played ones
    [
      NSSortDescriptor(key: lastPlayedKey, ascending: false),
      NSSortDescriptor(
        key: nameKey,
        ascending: true,
        selector: #selector(NSString.localizedCaseInsensitiveCompare)
      ),
    ]
  }

  public func getLibraryGridAlbums(for account: Account, limit: Int, onlyCached: Bool) -> [Album] {
    let request: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
      getFetchPredicate(onlyCachedAlbums: onlyCached),
    ])
    request.sortDescriptors = Self.recentFirstSort(
      lastPlayedKey: #keyPath(AlbumMO.lastPlayedDate),
      nameKey: #keyPath(AlbumMO.name)
    )
    request.fetchLimit = limit
    return ((try? context.fetch(request)) ?? []).map { Album(managedObject: $0) }
  }

  public func getLibraryGridArtists(for account: Account, limit: Int, onlyCached: Bool) -> [Artist] {
    let request: NSFetchRequest<ArtistMO> = ArtistMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
      getFetchPredicate(onlyCachedArtists: onlyCached),
    ])
    request.sortDescriptors = Self.recentFirstSort(
      lastPlayedKey: #keyPath(ArtistMO.lastPlayedDate),
      nameKey: #keyPath(ArtistMO.name)
    )
    request.fetchLimit = limit
    return ((try? context.fetch(request)) ?? []).map { Artist(managedObject: $0) }
  }

  public func getLibraryGridPlaylists(
    for account: Account,
    limit: Int,
    onlyCached: Bool
  )
    -> [Playlist] {
    let request: NSFetchRequest<PlaylistMO> = PlaylistMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      PlaylistMO.excludeSystemPlaylistsFetchPredicate,
    ])
    request.sortDescriptors = Self.recentFirstSort(
      lastPlayedKey: #keyPath(PlaylistMO.lastPlayedDate),
      nameKey: #keyPath(PlaylistMO.name)
    )
    request.fetchLimit = onlyCached ? 0 : limit
    let playlists = ((try? context.fetch(request)) ?? [])
      .map { Playlist(library: self, managedObject: $0) }
    guard onlyCached else { return playlists }
    return Array(playlists.filter { $0.playables.hasCachedItems }.prefix(limit))
  }
}
