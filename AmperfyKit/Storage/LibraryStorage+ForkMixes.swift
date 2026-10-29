//
//  LibraryStorage+ForkMixes.swift
//  AmperfyKit
//
//  Fork (F-12): song lists for the mixes on Home, built from local data only.
//  - Rediscover: favorites not played for a long time (`lastPlayedDate`), shuffled per day.
//  - On Repeat: songs played in the last 14 days with the most plays. The local scrobble
//    entries are the play history (one per finished play), `playCount` breaks ties.
//  - Daily Mix seeds: favorites picked per day, the app adds `getSimilarSongs2` to them.
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

// MARK: - DailySeededGenerator

/// Same sequence for the whole day, a new one tomorrow (SplitMix64).
public struct DailySeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  public init(date: Date = Date(), salt: UInt64 = 0) {
    let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
    self.state = UInt64(day) &* 0x9E37_79B9_7F4A_7C15 &+ salt
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

extension LibraryStorage {
  public static let forkRediscoverAge: TimeInterval = 60 * 24 * 60 * 60
  public static let forkOnRepeatPeriod: TimeInterval = 14 * 24 * 60 * 60

  private func forkMixSongPredicates(for account: Account, onlyCached: Bool) -> [NSPredicate] {
    [
      getFetchPredicate(forAccount: account),
      SongMO.excludeServerDeleteUncachedSongsFetchPredicate,
      getFetchPredicate(onlyCachedSongs: onlyCached),
      NSPredicate(format: "NOT (%K BEGINSWITH %@)", #keyPath(SongMO.id), YouTubeMusic.idPrefix),
    ]
  }

  /// Favorites not played for 60 days (or never), in a daily random order.
  public func getRediscoverSongs(for account: Account, count: Int, onlyCached: Bool) -> [Song] {
    let cutoff = Date().addingTimeInterval(-Self.forkRediscoverAge)
    let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: forkMixSongPredicates(
      for: account,
      onlyCached: onlyCached
    ) + [
      NSPredicate(format: "%K == TRUE", #keyPath(SongMO.isFavorite)),
      NSCompoundPredicate(orPredicateWithSubpredicates: [
        NSPredicate(format: "%K == nil", #keyPath(SongMO.lastPlayedDate)),
        NSPredicate(format: "%K < %@", #keyPath(SongMO.lastPlayedDate), cutoff as NSDate),
      ]),
    ])
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.id), ascending: true)]
    var generator = DailySeededGenerator(salt: 1)
    let songMOs = ((try? context.fetch(request)) ?? []).shuffled(using: &generator)
    return songMOs.prefix(count).map { Song(managedObject: $0) }
  }

  /// Songs played in the last 14 days, most plays first. Needs at least two plays in that time
  /// (scrobble entries) or, without a local history, a play count of two.
  public func getOnRepeatSongs(for account: Account, count: Int, onlyCached: Bool) -> [Song] {
    let cutoff = Date().addingTimeInterval(-Self.forkOnRepeatPeriod)
    var recentPlays = [NSManagedObjectID: Int]()
    let scrobbleRequest: NSFetchRequest<ScrobbleEntryMO> = ScrobbleEntryMO.fetchRequest()
    scrobbleRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      NSPredicate(format: "%K == %@", #keyPath(ScrobbleEntryMO.account), account.managedObject.objectID),
      NSPredicate(format: "%K >= %@", #keyPath(ScrobbleEntryMO.date), cutoff as NSDate),
      NSPredicate(format: "%K != nil", #keyPath(ScrobbleEntryMO.playable)),
    ])
    for entry in (try? context.fetch(scrobbleRequest)) ?? [] {
      guard let playable = entry.playable else { continue }
      recentPlays[playable.objectID, default: 0] += 1
    }

    let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: forkMixSongPredicates(
      for: account,
      onlyCached: onlyCached
    ) + [
      NSPredicate(format: "%K >= %@", #keyPath(SongMO.lastPlayedDate), cutoff as NSDate),
    ])
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.playCount), ascending: false)]
    request.fetchLimit = 500
    let songMOs = ((try? context.fetch(request)) ?? []).filter {
      let recent = recentPlays[$0.objectID] ?? 0
      return recent >= 2 || (recent == 0 && $0.playCount >= 2)
    }
    return songMOs
      .sorted {
        let lhs = recentPlays[$0.objectID] ?? 0
        let rhs = recentPlays[$1.objectID] ?? 0
        return lhs != rhs ? lhs > rhs : $0.playCount > $1.playCount
      }
      .prefix(count)
      .map { Song(managedObject: $0) }
  }

  /// Favorites in a daily random order, the start of the Daily Mix.
  public func getDailyMixFavorites(for account: Account, count: Int, onlyCached: Bool) -> [Song] {
    let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: forkMixSongPredicates(
      for: account,
      onlyCached: onlyCached
    ) + [
      NSPredicate(format: "%K == TRUE", #keyPath(SongMO.isFavorite)),
    ])
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.id), ascending: true)]
    var generator = DailySeededGenerator(salt: 2)
    let songMOs = ((try? context.fetch(request)) ?? []).shuffled(using: &generator)
    return songMOs.prefix(count).map { Song(managedObject: $0) }
  }
}
