//
//  LibraryStorage+ForkAlbumLists.swift
//  AmperfyKit
//
//  Fork (F-11): albums for the Home shelves "Most Played", "Top Rated" and "Decades".
//  Online the order comes from `getAlbumList2` (see SubsonicAlbumList.swift), these functions
//  resolve the IDs and are the offline fallback from local play counts, ratings and years.
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

// MARK: - AlbumDecade

public struct AlbumDecade: Hashable, Sendable {
  /// First year, e.g. 1990.
  public let startYear: Int
  public let albumCount: Int

  public var endYear: Int { startYear + 9 }
  /// "1990s"
  public var title: String { String(localized: "\(startYear)s", table: "Fork") }
  /// "90s" (2000s and later keep four digits)
  public var shortTitle: String {
    startYear < 2000
      ? String(localized: "\(startYear % 100)s", table: "Fork")
      : String(localized: "\(startYear)s", table: "Fork")
  }
}

extension LibraryStorage {
  private func forkAlbumPredicate(for account: Account, onlyCached: Bool) -> NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
      getFetchPredicate(onlyCachedAlbums: onlyCached),
    ])
  }

  /// Albums with the given IDs in the given order, unknown IDs are skipped.
  public func getAlbums(for account: Account, orderedIds ids: [String], onlyCached: Bool) -> [Album] {
    guard !ids.isEmpty else { return [] }
    let request: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      forkAlbumPredicate(for: account, onlyCached: onlyCached),
      NSPredicate(format: "%K IN %@", #keyPath(AlbumMO.id), ids),
    ])
    var byId = [String: AlbumMO]()
    for albumMO in (try? context.fetch(request)) ?? [] {
      byId[albumMO.id] = albumMO
    }
    var seen = Set<String>()
    return ids.compactMap { id in
      guard seen.insert(id).inserted, let albumMO = byId[id] else { return nil }
      return Album(managedObject: albumMO)
    }
  }

  /// Albums by the summed local play counts of their songs (plays in this app).
  public func getMostPlayedAlbums(for account: Account, count: Int, onlyCached: Bool) -> [Album] {
    let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K > 0", #keyPath(SongMO.playCount)),
      NSPredicate(format: "%K != nil", #keyPath(SongMO.album)),
      SongMO.excludeServerDeleteUncachedSongsFetchPredicate,
      getFetchPredicate(onlyCachedSongs: onlyCached),
    ])
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.playCount), ascending: false)]
    request.fetchLimit = 1000
    var plays = [NSManagedObjectID: (album: AlbumMO, plays: Int)]()
    for songMO in (try? context.fetch(request)) ?? [] {
      guard let albumMO = songMO.album else { continue }
      plays[albumMO.objectID, default: (albumMO, 0)].plays += Int(songMO.playCount)
    }
    return plays.values
      .sorted { $0.plays > $1.plays }
      .prefix(count)
      .map { Album(managedObject: $0.album) }
  }

  /// Albums with a rating, best first, favorites before others with the same rating.
  public func getTopRatedAlbums(for account: Account, count: Int, onlyCached: Bool) -> [Album] {
    let request: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      forkAlbumPredicate(for: account, onlyCached: onlyCached),
      NSPredicate(format: "%K > 0", #keyPath(AlbumMO.rating)),
    ])
    request.sortDescriptors = [
      NSSortDescriptor(key: #keyPath(AlbumMO.rating), ascending: false),
      NSSortDescriptor(key: #keyPath(AlbumMO.isFavorite), ascending: false),
      NSSortDescriptor(key: #keyPath(AlbumMO.name), ascending: true),
    ]
    request.fetchLimit = count
    return ((try? context.fetch(request)) ?? []).map { Album(managedObject: $0) }
  }

  /// Decades that have albums, newest first. Albums without a year are left out.
  public func getAlbumDecades(for account: Account, onlyCached: Bool) -> [AlbumDecade] {
    let request = NSFetchRequest<NSDictionary>(entityName: AlbumMO.entity().name ?? "Album")
    request.resultType = .dictionaryResultType
    request.propertiesToFetch = [#keyPath(AlbumMO.year)]
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      forkAlbumPredicate(for: account, onlyCached: onlyCached),
      NSPredicate(format: "%K > 0", #keyPath(AlbumMO.year)),
    ])
    var counts = [Int: Int]()
    for row in (try? context.fetch(request)) ?? [] {
      guard let year = (row[#keyPath(AlbumMO.year)] as? NSNumber)?.intValue, year > 1000 else {
        continue
      }
      counts[year / 10 * 10, default: 0] += 1
    }
    return counts
      .map { AlbumDecade(startYear: $0.key, albumCount: $0.value) }
      .sorted { $0.startYear > $1.startYear }
  }

  /// Albums of a decade, oldest first like `getAlbumList2 byYear`.
  public func getAlbums(for account: Account, decade: AlbumDecade, onlyCached: Bool) -> [Album] {
    let request: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      forkAlbumPredicate(for: account, onlyCached: onlyCached),
      NSPredicate(
        format: "%K >= %i AND %K <= %i",
        #keyPath(AlbumMO.year), decade.startYear,
        #keyPath(AlbumMO.year), decade.endYear
      ),
    ])
    request.sortDescriptors = [
      NSSortDescriptor(key: #keyPath(AlbumMO.year), ascending: true),
      NSSortDescriptor(key: #keyPath(AlbumMO.name), ascending: true),
    ]
    return ((try? context.fetch(request)) ?? []).map { Album(managedObject: $0) }
  }
}
