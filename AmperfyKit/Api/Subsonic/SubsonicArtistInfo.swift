//
//  SubsonicArtistInfo.swift
//  AmperfyKit
//
//  Fork: artist page extras from Subsonic (F-3, F-4). `getArtistInfo2` brings the biography
//  and similar artists, `getTopSongs` the most popular songs on Last.fm. Both are read as
//  JSON and only return IDs, the app resolves them against its own library.
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

// MARK: - SubsonicArtistInfo

public struct SubsonicArtistInfo: Sendable {
  /// Plain text, HTML and the "Read more on Last.fm" link removed.
  public let biography: String?
  public let largeImageUrl: URL?
  public let similarArtistIds: [String]
  /// F-5: names of all similar artists, also the ones without library ID (`includeNotPresent`).
  public let similarArtistNames: [String]

  static func parse(data: Data) throws -> SubsonicArtistInfo {
    let response = try subsonicResponse(data: data)
    let info = (response["artistInfo2"] as? [String: Any]) ?? [:]
    let similar = (info["similarArtist"] as? [[String: Any]]) ?? []
    let imageUrl = (info["largeImageUrl"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    return SubsonicArtistInfo(
      biography: plainText(fromHtml: info["biography"] as? String),
      largeImageUrl: imageUrl,
      similarArtistIds: similar.compactMap { $0["id"] as? String },
      similarArtistNames: similar.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    )
  }

  static func parseTopSongIds(data: Data) throws -> [String] {
    let response = try subsonicResponse(data: data)
    let topSongs = (response["topSongs"] as? [String: Any]) ?? [:]
    let songs = (topSongs["song"] as? [[String: Any]]) ?? []
    return songs.compactMap { $0["id"] as? String }
  }

  private static func subsonicResponse(data: Data) throws -> [String: Any] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["subsonic-response"] as? [String: Any]
    else { throw SongpickerError.invalidResponse }
    if response["status"] as? String != "ok" {
      let error = response["error"] as? [String: Any]
      throw SongpickerError.server((error?["message"] as? String) ?? "The server reported an error")
    }
    return response
  }

  static func plainText(fromHtml html: String?) -> String? {
    guard var text = html else { return nil }
    // Last.fm appends `<a href="…">Read more on Last.fm</a>`
    if let linkStart = text.range(of: "<a ", options: .caseInsensitive) {
      text = String(text[..<linkStart.lowerBound])
    }
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    for (entity, character) in [
      ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
    ] {
      text = text.replacingOccurrences(of: entity, with: character)
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}

// MARK: - BackendProxy

extension BackendProxy {
  public func forkArtistInfo(
    artistId: String,
    includeNotPresent: Bool = false
  ) async throws -> SubsonicArtistInfo {
    guard let serverApi = forkSubsonicServerApi else { throw BackendError.notSupported }
    let response = try await serverApi.requestArtistInfo2(
      id: artistId,
      includeNotPresent: includeNotPresent
    )
    return try SubsonicArtistInfo.parse(data: response.data)
  }

  /// Song IDs in Last.fm order. Navidrome only returns songs that are in the library.
  public func forkTopSongIds(artistName: String, count: Int) async throws -> [String] {
    guard let serverApi = forkSubsonicServerApi else { throw BackendError.notSupported }
    let response = try await serverApi.requestTopSongs(artistName: artistName, count: count)
    return try SubsonicArtistInfo.parseTopSongIds(data: response.data)
  }
}
