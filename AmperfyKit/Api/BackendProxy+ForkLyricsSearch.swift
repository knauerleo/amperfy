//
//  BackendProxy+ForkLyricsSearch.swift
//  AmperfyKit
//
//  Fork (TASKS F-21): find songs by a line of their lyrics. `searchLyrics.view` at the proxy
//  searches the lyrics of the library first, then Genius, and answers like `search3`: library
//  songs with their real ID, YouTube Music songs as `ytm-` placeholders, each with the line
//  that matched (`lyricSnippet`) and where it was found (`lyricSource`).
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

import Foundation

// MARK: - LyricsSearchHit

@MainActor
public struct LyricsSearchHit {
  public let song: Song
  /// The matching line as in the lyrics, can be empty.
  public let snippet: String
  /// Found in the lyrics of the library (or else on Genius).
  public let isFromLibrary: Bool
}

// MARK: - BackendProxy

extension BackendProxy {
  /// The proxy answers fewer words with `query_too_short`.
  public static let lyricsSearchMinWords = 3
  private static let lyricsSearchCount = 20

  public static func lyricsSearchWordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
  }

  /// `searchLyrics.view?query=…&count=20`, the songs in the order of the proxy.
  @MainActor
  public func forkSearchLyrics(
    query: String,
    account: Account,
    storage: PersistentStorage
  ) async throws -> [LyricsSearchHit] {
    let data = try await forkYouTubeRequest(action: "searchLyrics", id: nil, extraQuery: [
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "count", value: String(Self.lyricsSearchCount)),
    ])
    let entries = YouTubeAlbumJSON.list(
      try YouTubeAlbumJSON.payload(data, key: "searchResult3")["song"]
    )
    let attributes = entries.map { YouTubeAlbumJSON.stringAttributes($0) }

    let library = storage.main.library
    var songs = [String: Song]()
    var missingIds = [String]()
    var placeholders = [YouTubeAlbumSong]()
    for (entry, attributes) in zip(entries, attributes) {
      guard let id = attributes["id"], !id.isEmpty else { continue }
      if YouTubeMusic.isPlaceholderId(id) {
        if let song = YouTubeAlbumSong(dict: entry) { placeholders.append(song) }
      } else if let song = library.getSong(for: account, id: id) {
        songs[id] = song
      } else {
        missingIds.append(id)
      }
    }
    if !missingIds.isEmpty {
      let fetched = await forkFetchLibrarySongs(ids: missingIds, account: account, storage: storage)
      songs.merge(fetched) { lhs, _ in lhs }
    }
    let created = await forkCreateYouTubePlaceholders(placeholders, account: account, storage: storage)
    songs.merge(created) { lhs, _ in lhs }

    var seen = Set<String>()
    return attributes.compactMap { attributes in
      guard let id = attributes["id"], seen.insert(id).inserted, let song = songs[id]
      else { return nil }
      return LyricsSearchHit(
        song: song,
        snippet: (attributes["lyricSnippet"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        isFromLibrary: attributes["lyricSource"] == "library"
      )
    }
  }
}
