//
//  YouTubeMusicSuggestions.swift
//  AmperfyKit
//
//  Fork (TASKS F-5): "similar songs from YouTube". The proxy mixes YouTube Music results
//  (`ytm-<videoId>`) into search3, so the songs come from a server search for the names of
//  similar artists (`getArtistInfo2` with `includeNotPresent`), or for the artist itself if the
//  server knows none. Songs that are already in the library are left out.
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

// MARK: - YouTubeMusicSuggestions

@MainActor
public enum YouTubeMusicSuggestions {
  public static let shelfLimit = 15
  /// Searches per request: each one is a YouTube Music search on the Pi.
  private static let maxQueries = 3

  /// Placeholder songs similar to the artist, songs of the different searches interleaved.
  public static func similarSongs(
    artistName: String,
    artistId: String?,
    account: Account,
    storage: PersistentStorage,
    backendApi: BackendProxy,
    librarySyncer: LibrarySyncer,
    excludingIds: Set<String> = [],
    limit: Int = shelfLimit
  ) async
    -> [Song] {
    guard SongpickerConfig.isEnabled, storage.settings.user.isOnlineMode,
          !artistName.isEmpty
    else { return [] }

    var queries = [String]()
    if let artistId, !artistId.isEmpty, !YouTubeMusic.isPlaceholderId(artistId),
       let info = try? await backendApi.forkArtistInfo(artistId: artistId, includeNotPresent: true) {
      queries = Array(info.similarArtistNames.prefix(maxQueries))
    }
    if queries.isEmpty {
      queries = [artistName]
    }

    let resultIds = await withTaskGroup(of: (Int, [NSManagedObjectID]).self) { group in
      for (index, query) in queries.enumerated() {
        group.addTask {
          (index, (try? await librarySyncer.searchSongs(searchText: query)) ?? [])
        }
      }
      var results = [[NSManagedObjectID]](repeating: [], count: queries.count)
      for await (index, ids) in group {
        results[index] = ids
      }
      return results
    }

    let context = storage.main.context
    let library = storage.main.library
    let lists = resultIds.map { ids in
      ids.compactMap { context.object(with: $0) as? SongMO }
        .map { Song(managedObject: $0) }
        .filter { $0.isYouTubeMusicPlaceholder && !excludingIds.contains($0.id) }
    }

    var seen = Set<String>()
    var songs = [Song]()
    var position = 0
    while songs.count < limit {
      let row = lists.compactMap { $0.indices.contains(position) ? $0[position] : nil }
      guard !row.isEmpty else { break }
      for song in row where songs.count < limit && seen.insert(song.id).inserted {
        guard !library.forkContainsLibrarySong(
          title: song.title,
          artistName: song.creatorName,
          account: account
        ) else { continue }
        songs.append(song)
      }
      position += 1
    }
    return songs
  }
}

// MARK: - LibraryStorage

extension LibraryStorage {
  /// A real (non-placeholder) song with this title by an artist of this name.
  func forkContainsLibrarySong(title: String, artistName: String, account: Account) -> Bool {
    guard !title.isEmpty else { return false }
    let fetchRequest: NSFetchRequest<SongMO> = SongMO.fetchRequest()
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSPredicate(format: "NOT (%K BEGINSWITH %@)", #keyPath(SongMO.id), YouTubeMusic.idPrefix),
      NSPredicate(format: "%K ==[cd] %@", #keyPath(SongMO.title), title),
      NSPredicate(format: "%K ==[cd] %@", #keyPath(SongMO.artist.name), artistName),
    ])
    fetchRequest.fetchLimit = 1
    return ((try? context.count(for: fetchRequest)) ?? 0) > 0
  }
}
