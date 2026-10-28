//
//  LibraryStorage+MultiWordSearch.swift
//  AmperfyKit
//
//  Created by Leopold Knauer on 28.10.26.
//  Copyright (c) 2026 Leopold Knauer. All rights reserved.
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

/// Local search that splits the search text into words and requires every word to appear
/// in at least one of the searched fields (e.g. song title, artist name or album name).
/// "valentines day linkin park" therefore matches the song "Valentine's Day" by "Linkin Park".
extension LibraryStorage {
  /// Splits the search text into lowercased words, ignoring punctuation like apostrophes.
  static func searchWords(of searchText: String) -> [String] {
    searchText
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }

  /// Every word must be contained (case and diacritic insensitive) in one of the key paths.
  /// Apostrophes are ignored by the word split, so "valentines" does not match "Valentine's".
  /// To still match those, a word ending in "s" is also tried without it.
  static func wordVariants(_ word: String) -> [String] {
    guard word.count > 3, word.hasSuffix("s") else { return [word] }
    return [word, String(word.dropLast())]
  }

  static func multiWordSearchPredicate(searchText: String, keyPaths: [String]) -> NSPredicate {
    let words = searchWords(of: searchText)
    guard !words.isEmpty else { return NSPredicate(value: true) }
    return NSCompoundPredicate(andPredicateWithSubpredicates: words.map { word in
      let variants = wordVariants(word)
      return NSCompoundPredicate(orPredicateWithSubpredicates: keyPaths.flatMap { keyPath in
        variants.map { NSPredicate(format: "%K contains[cd] %@", keyPath, $0) }
      })
    })
  }

  /// Ranks by how many search words are part of the primary name, then alphabetically.
  static func rankByPrimaryName<T>(
    _ items: [T],
    searchText: String,
    name: (T) -> String?
  )
    -> [T] {
    let words = searchWords(of: searchText).map { $0.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: nil
    ) }
    func score(_ item: T) -> Int {
      let folded = (name(item) ?? "").folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: nil
      )
      return words.filter { wordVariants($0).contains(where: { folded.contains($0) }) }.count
    }
    return items
      .map { (item: $0, score: score($0), name: name($0) ?? "") }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      .map { $0.item }
  }

  public func multiWordSearchSongs(
    for account: Account,
    searchText: String,
    onlyCached: Bool,
    limit: Int
  )
    -> [Song] {
    let fetchRequest = SongMO.identifierSortedFetchRequest
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      // Unlike excludeServerDeleteUncachedSongsFetchPredicate this does not require a known
      // size or an available album: songs only known from a server search are shown too.
      NSCompoundPredicate(orPredicateWithSubpredicates: [
        AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
        NSPredicate(format: "%K != nil", #keyPath(SongMO.relFilePath)),
      ]),
      Self.multiWordSearchPredicate(
        searchText: searchText,
        keyPaths: [
          #keyPath(SongMO.title),
          #keyPath(SongMO.artist.name),
          #keyPath(SongMO.album.name),
        ]
      ),
      getFetchPredicate(onlyCachedSongs: onlyCached),
    ])
    let found = (try? context.fetch(fetchRequest)) ?? []
    return Self.rankByPrimaryName(found, searchText: searchText, name: { $0.title })
      .prefix(limit)
      .map { Song(managedObject: $0) }
  }

  public func multiWordSearchAlbums(
    for account: Account,
    searchText: String,
    onlyCached: Bool,
    limit: Int
  )
    -> [Album] {
    let fetchRequest = AlbumMO.identifierSortedFetchRequest
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSCompoundPredicate(orPredicateWithSubpredicates: [
        AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
        getFetchPredicate(onlyCachedAlbums: true),
      ]),
      Self.multiWordSearchPredicate(
        searchText: searchText,
        keyPaths: [#keyPath(AlbumMO.name), #keyPath(AlbumMO.artist.name)]
      ),
      getFetchPredicate(onlyCachedAlbums: onlyCached),
    ])
    let found = (try? context.fetch(fetchRequest)) ?? []
    return Self.rankByPrimaryName(found, searchText: searchText, name: { $0.name })
      .prefix(limit)
      .map { Album(managedObject: $0) }
  }

  public func multiWordSearchArtists(
    for account: Account,
    searchText: String,
    onlyCached: Bool,
    limit: Int
  )
    -> [Artist] {
    let fetchRequest = ArtistMO.identifierSortedFetchRequest
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      NSCompoundPredicate(orPredicateWithSubpredicates: [
        AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
        getFetchPredicate(onlyCachedArtists: true),
      ]),
      Self.multiWordSearchPredicate(searchText: searchText, keyPaths: [#keyPath(ArtistMO.name)]),
      getFetchPredicate(onlyCachedArtists: onlyCached),
    ])
    let found = (try? context.fetch(fetchRequest)) ?? []
    return Self.rankByPrimaryName(found, searchText: searchText, name: { $0.name })
      .prefix(limit)
      .map { Artist(managedObject: $0) }
  }
}
