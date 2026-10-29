//
//  LibraryStorage+ForkSpotlight.swift
//  AmperfyKit
//
//  Fork (F-15): albums, artists and playlists of an account as plain values for the Spotlight
//  index. Built in a background context, the app turns them into `CSSearchableItem`s.
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

// MARK: - ForkSpotlightEntry

public struct ForkSpotlightEntry: Sendable {
  public enum Kind: String, Sendable, CaseIterable {
    case album
    case artist
    case playlist
  }

  public let kind: Kind
  public let id: String
  public let title: String
  /// Artist of an album, nil otherwise.
  public let artistName: String?
  /// "Album · 2019 · 12 Songs", "Artist · 4 Albums", "Playlist · 31 Songs"
  public let detail: String
  /// Absolute path of the cached artwork, if any.
  public let artworkPath: String?
}

extension LibraryStorage {
  /// Albums, artists and playlists (without system playlists) of the account. Remote deleted
  /// entries and YouTube Music placeholders are left out.
  public func getForkSpotlightEntries(for account: Account) -> [ForkSpotlightEntry] {
    var entries = [ForkSpotlightEntry]()

    let albumRequest: NSFetchRequest<AlbumMO> = AlbumMO.fetchRequest()
    albumRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
    ])
    for albumMO in (try? context.fetch(albumRequest)) ?? [] {
      let album = Album(managedObject: albumMO)
      guard !YouTubeMusic.isPlaceholderId(album.id), !album.name.isEmpty else { continue }
      var detail = ["Album"]
      if album.year > 0 { detail.append(String(album.year)) }
      if album.songCount > 0 { detail.append(Self.countText(album.songCount, "Song")) }
      entries.append(ForkSpotlightEntry(
        kind: .album,
        id: album.id,
        title: album.name,
        artistName: album.artist?.name,
        detail: detail.joined(separator: " · "),
        artworkPath: album.artwork?.imagePath
      ))
    }

    let artistRequest: NSFetchRequest<ArtistMO> = ArtistMO.fetchRequest()
    artistRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
      getFetchPredicate(forAccount: account),
      AbstractLibraryEntityMO.excludeRemoteDeleteFetchPredicate,
    ])
    for artistMO in (try? context.fetch(artistRequest)) ?? [] {
      let artist = Artist(managedObject: artistMO)
      guard !YouTubeMusic.isPlaceholderId(artist.id), !artist.id.isEmpty, !artist.name.isEmpty
      else { continue }
      var detail = ["Artist"]
      if artist.albumCount > 0 { detail.append(Self.countText(artist.albumCount, "Album")) }
      entries.append(ForkSpotlightEntry(
        kind: .artist,
        id: artist.id,
        title: artist.name,
        artistName: nil,
        detail: detail.joined(separator: " · "),
        artworkPath: artist.artwork?.imagePath
      ))
    }

    for playlist in getPlaylists(for: account) {
      guard !playlist.id.isEmpty, !playlist.name.isEmpty else { continue }
      var detail = ["Playlist"]
      if playlist.songCount > 0 { detail.append(Self.countText(playlist.songCount, "Song")) }
      entries.append(ForkSpotlightEntry(
        kind: .playlist,
        id: playlist.id,
        title: playlist.name,
        artistName: nil,
        detail: detail.joined(separator: " · "),
        artworkPath: nil
      ))
    }
    return entries
  }

  private static func countText(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }
}
