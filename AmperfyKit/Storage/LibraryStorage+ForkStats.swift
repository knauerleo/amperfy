//
//  LibraryStorage+ForkStats.swift
//  AmperfyKit
//
//  Fork (F-13): listening statistics from local data. All time: `playCount` of each song (plays
//  in this app, Subsonic sends no play counts). A year: the local scrobble entries of that year
//  (one per finished play); songs without entries but with `lastPlayedDate` in the year count
//  with their `playCount`. `UserStatistics` adds the plays and the start of the history.
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

// MARK: - ListeningStats

public struct ListeningStats {
  public enum Period: Equatable {
    case allTime
    case year(Int)
  }

  public struct Entry<Item> {
    public let item: Item
    public let plays: Int
  }

  public let period: Period
  public let plays: Int
  public let listeningSeconds: Int
  public let songCount: Int
  public let artistCount: Int
  public let albumCount: Int
  public let topSongs: [Entry<Song>]
  public let topArtists: [Entry<Artist>]
  public let topAlbums: [Entry<Album>]
  /// Year view: some songs had no scrobble entry and counted with their total play count.
  public let isApproximate: Bool
  /// Plays counted by the app's own statistics (all versions) and its first day.
  public let appPlayedSongsCount: Int
  public let historyStartDate: Date?

  public var isEmpty: Bool { plays == 0 }
}

extension LibraryStorage {
  public func getListeningStats(
    for account: Account,
    period: ListeningStats.Period,
    topCount: Int = 10
  )
    -> ListeningStats {
    var playsBySong = [NSManagedObjectID: (song: SongMO, plays: Int)]()
    var isApproximate = false

    let songRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    var predicates = [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K > 0", #keyPath(SongMO.playCount)),
      NSPredicate(format: "NOT (%K BEGINSWITH %@)", #keyPath(SongMO.id), YouTubeMusic.idPrefix),
    ]

    switch period {
    case .allTime:
      songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
      for songMO in (try? context.fetch(songRequest)) ?? [] {
        playsBySong[songMO.objectID] = (songMO, Int(songMO.playCount))
      }
    case let .year(year):
      let calendar = Calendar.current
      guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))
      else { break }
      let scrobbleRequest: NSFetchRequest<ScrobbleEntryMO> = ScrobbleEntryMO.fetchRequest()
      scrobbleRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(
          format: "%K == %@",
          #keyPath(ScrobbleEntryMO.account),
          account.managedObject.objectID
        ),
        NSPredicate(
          format: "%K >= %@ AND %K < %@",
          #keyPath(ScrobbleEntryMO.date), start as NSDate,
          #keyPath(ScrobbleEntryMO.date), end as NSDate
        ),
      ])
      for entry in (try? context.fetch(scrobbleRequest)) ?? [] {
        guard let songMO = entry.playable as? SongMO,
              !songMO.id.hasPrefix(YouTubeMusic.idPrefix) else { continue }
        playsBySong[songMO.objectID, default: (songMO, 0)].plays += 1
      }
      predicates.append(NSPredicate(
        format: "%K >= %@ AND %K < %@",
        #keyPath(SongMO.lastPlayedDate), start as NSDate,
        #keyPath(SongMO.lastPlayedDate), end as NSDate
      ))
      songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
      for songMO in (try? context.fetch(songRequest)) ?? []
        where playsBySong[songMO.objectID] == nil {
        playsBySong[songMO.objectID] = (songMO, Int(songMO.playCount))
        isApproximate = true
      }
    }

    var plays = 0
    var seconds = 0
    var playsByArtist = [NSManagedObjectID: (artist: ArtistMO, plays: Int)]()
    var playsByAlbum = [NSManagedObjectID: (album: AlbumMO, plays: Int)]()
    for (songMO, songPlays) in playsBySong.values {
      plays += songPlays
      seconds += songPlays * Int(songMO.combinedDuration)
      if let artistMO = songMO.artist {
        playsByArtist[artistMO.objectID, default: (artistMO, 0)].plays += songPlays
      }
      if let albumMO = songMO.album {
        playsByAlbum[albumMO.objectID, default: (albumMO, 0)].plays += songPlays
      }
    }

    let statistics = getAllUserStatistics()
    return ListeningStats(
      period: period,
      plays: plays,
      listeningSeconds: seconds,
      songCount: playsBySong.count,
      artistCount: playsByArtist.count,
      albumCount: playsByAlbum.count,
      topSongs: playsBySong.values
        .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : ($0.song.title ?? "") < ($1.song.title ?? "") }
        .prefix(topCount)
        .map { ListeningStats.Entry(item: Song(managedObject: $0.song), plays: $0.plays) },
      topArtists: playsByArtist.values
        .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : ($0.artist.name ?? "") < ($1.artist.name ?? "") }
        .prefix(topCount)
        .map { ListeningStats.Entry(item: Artist(managedObject: $0.artist), plays: $0.plays) },
      topAlbums: playsByAlbum.values
        .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : ($0.album.name ?? "") < ($1.album.name ?? "") }
        .prefix(topCount / 2)
        .map { ListeningStats.Entry(item: Album(managedObject: $0.album), plays: $0.plays) },
      isApproximate: isApproximate,
      appPlayedSongsCount: statistics.reduce(0) { $0 + Int($1.managedObject.playedSongsCount) },
      historyStartDate: statistics.map(\.creationDate).min()
    )
  }

  /// Years with a play in the local history (scrobble entries or `lastPlayedDate`), newest first.
  public func getListeningYears(for account: Account) -> [Int] {
    let calendar = Calendar.current
    var years = Set<Int>()
    let scrobbleRequest: NSFetchRequest<ScrobbleEntryMO> = ScrobbleEntryMO.fetchRequest()
    scrobbleRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      NSPredicate(format: "%K == %@", #keyPath(ScrobbleEntryMO.account), account.managedObject.objectID),
      NSPredicate(format: "%K != nil", #keyPath(ScrobbleEntryMO.date)),
    ])
    scrobbleRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(ScrobbleEntryMO.date), ascending: true)]
    scrobbleRequest.fetchLimit = 1
    let firstScrobble = (try? context.fetch(scrobbleRequest))?.first?.date
    let songRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    songRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "%K != nil", #keyPath(SongMO.lastPlayedDate)),
    ])
    songRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.lastPlayedDate), ascending: true)]
    songRequest.fetchLimit = 1
    let firstPlayed = (try? context.fetch(songRequest))?.first?.lastPlayedDate
    let currentYear = calendar.component(.year, from: Date())
    let firstYear = [firstScrobble, firstPlayed].compactMap { $0 }
      .map { calendar.component(.year, from: $0) }.min() ?? currentYear
    for year in firstYear ... max(firstYear, currentYear) {
      years.insert(year)
    }
    return years.sorted(by: >)
  }
}
