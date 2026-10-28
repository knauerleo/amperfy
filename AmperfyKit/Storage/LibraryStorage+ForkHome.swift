//
//  LibraryStorage+ForkHome.swift
//  AmperfyKit
//
//  Fork: queries for the Home sections of design phase 3 (Recently Played grid, Recently Added).
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
  /// Albums, playlists and artists by `lastPlayedDate`, newest first.
  /// A song played on its own counts as a play of its album, so the list is not empty for users
  /// who mostly start single songs.
  public func getRecentlyPlayedContainers(
    for account: Account,
    count: Int,
    onlyCached: Bool
  )
    -> [PlayableContainable] {
    var candidates = [NSManagedObjectID: (date: Date, container: PlayableContainable)]()
    func add(_ container: PlayableContainable, objectID: NSManagedObjectID, date: Date?) {
      guard let date else { return }
      if let existing = candidates[objectID], existing.date >= date { return }
      candidates[objectID] = (date, container)
    }
    let playedPredicate = NSPredicate(
      format: "%K != nil",
      #keyPath(AbstractLibraryEntityMO.lastPlayedDate)
    )
    let byLastPlayed = [NSSortDescriptor(
      key: #keyPath(AbstractLibraryEntityMO.lastPlayedDate),
      ascending: false
    )]

    let albumRequest: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    albumRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      playedPredicate,
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
      getFetchPredicate(onlyCachedAlbums: onlyCached),
    ])
    albumRequest.sortDescriptors = byLastPlayed
    albumRequest.fetchLimit = count
    for albumMO in (try? context.fetch(albumRequest)) ?? [] {
      add(Album(managedObject: albumMO), objectID: albumMO.objectID, date: albumMO.lastPlayedDate)
    }

    let artistRequest: NSFetchRequest<ArtistMO> = ArtistMO.fetchRequest()
    artistRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      playedPredicate,
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
      getFetchPredicate(onlyCachedArtists: onlyCached),
    ])
    artistRequest.sortDescriptors = byLastPlayed
    artistRequest.fetchLimit = count
    for artistMO in (try? context.fetch(artistRequest)) ?? [] {
      add(
        Artist(managedObject: artistMO),
        objectID: artistMO.objectID,
        date: artistMO.lastPlayedDate
      )
    }

    let playlistRequest: NSFetchRequest<PlaylistMO> = PlaylistMO.fetchRequest()
    playlistRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      PlaylistMO.excludeSystemPlaylistsFetchPredicate,
      NSPredicate(format: "%K != nil", #keyPath(PlaylistMO.lastPlayedDate)),
    ])
    playlistRequest.sortDescriptors = [NSSortDescriptor(
      key: #keyPath(PlaylistMO.lastPlayedDate),
      ascending: false
    )]
    playlistRequest.fetchLimit = count
    for playlistMO in (try? context.fetch(playlistRequest)) ?? [] {
      let playlist = Playlist(library: self, managedObject: playlistMO)
      if onlyCached, !playlist.playables.hasCachedItems { continue }
      add(playlist, objectID: playlistMO.objectID, date: playlistMO.lastPlayedDate)
    }

    let songRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      playedPredicate,
      NSPredicate(format: "%K != nil", #keyPath(SongMO.album)),
      SongMO.excludeServerDeleteUncachedSongsFetchPredicate,
      getFetchPredicate(onlyCachedSongs: onlyCached),
    ])
    songRequest.sortDescriptors = byLastPlayed
    songRequest.fetchLimit = count * 5
    for songMO in (try? context.fetch(songRequest)) ?? [] {
      guard let albumMO = songMO.album else { continue }
      add(Album(managedObject: albumMO), objectID: albumMO.objectID, date: songMO.lastPlayedDate)
    }

    return candidates.values
      .sorted { $0.date > $1.date }
      .prefix(count)
      .map(\.container)
  }

  /// Albums of the most recently added songs (`addedDate`, newest first). Completed with the
  /// server's newest albums (`newestIndex`) when the local songs don't fill the shelf.
  /// Finished YouTube downloads land here once Navidrome has picked them up.
  public func getRecentlyAddedAlbums(for account: Account, count: Int, onlyCached: Bool) -> [Album] {
    var albums = [Album]()
    var seen = Set<NSManagedObjectID>()

    let songRequest = SongMO.addedDateSortedFetchRequest
    songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K != nil", #keyPath(SongMO.addedDate)),
      NSPredicate(format: "%K != nil", #keyPath(SongMO.album)),
      SongMO.excludeServerDeleteUncachedSongsFetchPredicate,
      getFetchPredicate(onlyCachedSongs: onlyCached),
    ])
    songRequest.fetchLimit = count * 15
    for songMO in (try? context.fetch(songRequest)) ?? [] {
      guard albums.count < count, let albumMO = songMO.album,
            seen.insert(albumMO.objectID).inserted else { continue }
      albums.append(Album(managedObject: albumMO))
    }

    if albums.count < count {
      let albumRequest = AlbumMO.newestSortedFetchRequest
      albumRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        getFetchPredicate(forAccount: account),
        getFetchPredicate(albumsDisplayFilter: .newest),
        getFetchPredicate(onlyCachedAlbums: onlyCached),
      ])
      albumRequest.fetchLimit = count * 2
      for albumMO in (try? context.fetch(albumRequest)) ?? [] {
        guard albums.count < count, seen.insert(albumMO.objectID).inserted else { continue }
        albums.append(Album(managedObject: albumMO))
      }
    }
    return albums
  }
}
