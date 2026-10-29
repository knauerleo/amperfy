//
//  SubsonicAlbumList.swift
//  AmperfyKit
//
//  Fork (F-11): album lists of `getAlbumList2` for the Home shelves "Most Played" (`frequent`),
//  "Top Rated" (`highest`) and the decade pages (`byYear`). Read as JSON, only the IDs are used,
//  the app resolves them against its own library (all albums are synced at login).
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

// MARK: - SubsonicAlbumListType

public enum SubsonicAlbumListType: Sendable, Equatable {
  case frequent
  case highest
  case byYear(from: Int, to: Int)

  var typeName: String {
    switch self {
    case .frequent: return "frequent"
    case .highest: return "highest"
    case .byYear: return "byYear"
    }
  }
}

// MARK: - SubsonicAlbumList

enum SubsonicAlbumList {
  static func parseAlbumIds(data: Data) throws -> [String] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["subsonic-response"] as? [String: Any]
    else { throw SongpickerError.invalidResponse }
    if response["status"] as? String != "ok" {
      let error = response["error"] as? [String: Any]
      throw SongpickerError.server((error?["message"] as? String) ?? "The server reported an error")
    }
    let list = (response["albumList2"] as? [String: Any]) ?? [:]
    let albums = (list["album"] as? [[String: Any]]) ?? []
    return albums.compactMap { $0["id"] as? String }
  }
}

// MARK: - BackendProxy

extension BackendProxy {
  /// Album IDs in server order. Throws `notSupported` for non-Subsonic accounts.
  public func forkAlbumListIds(type: SubsonicAlbumListType, size: Int) async throws -> [String] {
    guard let serverApi = forkSubsonicServerApi else { throw BackendError.notSupported }
    var fromYear: Int?
    var toYear: Int?
    if case let .byYear(from, to) = type {
      fromYear = from
      toYear = to
    }
    let response = try await serverApi.requestAlbumList2(
      type: type.typeName,
      size: size,
      fromYear: fromYear,
      toYear: toYear
    )
    return try SubsonicAlbumList.parseAlbumIds(data: response.data)
  }
}
