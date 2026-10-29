//
//  SongpickerClient.swift
//  AmperfyKit
//
//  Fork: YouTube Music through the Subsonic proxy in front of Navidrome (see FORK.md).
//  The proxy mixes YouTube results (`ytm-<videoId>`) into search3, streams and downloads them,
//  and lists the downloads of the user in `getYtJobs.view`. The Songpicker itself stays internal.
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

// MARK: - SongpickerConfig

/// Proxy addresses and the YouTube Music switch. Set at start from the settings (see `apply`).
public enum SongpickerConfig {
  /// Port of Navidrome itself. An account on this port talks to Navidrome directly (LAN),
  /// YouTube songs then go to the proxy port of the same host.
  public static let navidromePort = 4533
  /// Port of the Subsonic proxy (nginx) that understands the `ytm-<videoId>` IDs.
  public static let proxyPort = 4534

  private static let _isEnabled = Atomic<Bool>(wrappedValue: true)
  private static let _customProxyURL = Atomic<URL?>(wrappedValue: nil)

  /// Shows the YouTube Music results in the search.
  public static var isEnabled: Bool {
    get { _isEnabled.wrappedValue }
    set { _isEnabled.wrappedValue = newValue }
  }

  /// Own address of the proxy. `nil`: the account itself, or its host + `proxyPort`
  /// if the account points to Navidrome directly.
  public static var customProxyURL: URL? {
    get { _customProxyURL.wrappedValue }
    set { _customProxyURL.wrappedValue = newValue }
  }

  /// Takes over the values stored in the settings.
  public static func apply(_ settings: UserSettings) {
    isEnabled = settings.isYouTubeMusicEnabled
    customProxyURL = settings.songpickerProxyURL
  }

  /// A typed address with scheme, e.g. "music.example.com" → "http://music.example.com".
  public static func normalizedURL(from text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.contains("://") { trimmed = "http://" + trimmed }
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host?.isEmpty == false
    else { return nil }
    return url
  }

  /// Unchanged if the account already talks to the proxy (e.g. `https://musik.leokna.de`).
  /// Navidrome port → proxy port of the same host. With a custom proxy URL: its scheme, host,
  /// port and path, followed by the `rest/…` part.
  public static func proxyURL(rewriting url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    guard let custom = customProxyURL,
          let customComponents = URLComponents(url: custom, resolvingAgainstBaseURL: false)
    else {
      guard components.port == navidromePort else { return url }
      components.port = proxyPort
      return components.url ?? url
    }
    components.scheme = customComponents.scheme
    components.host = customComponents.host
    components.port = customComponents.port
    let restPart = components.path.range(of: "/rest/").map { String(components.path[$0.lowerBound...]) }
      ?? components.path
    var basePath = customComponents.path
    while basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + restPart
    return components.url ?? url
  }
}

// MARK: - SongpickerHit

/// One YouTube Music result, read from a `ytm-<videoId>` song of the proxy.
public struct SongpickerHit: Sendable, Hashable {
  public let videoId: String
  public let title: String
  public let artist: String
  public let album: String?
  public let duration: Int
  public let thumbURL: URL?
  public let kind: String?
  /// Relative path of the copy in the library, if known.
  public let libraryPath: String?
  /// The result as JSON, kept in `YouTubeMusicHitStore`.
  public let json: Data

  public var isInLibrary: Bool { libraryPath != nil }

  /// Public thumbnail of the video, e.g. for the download overview.
  public static func thumbnailURL(videoId: String) -> URL? {
    URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
  }

  public init?(videoId: String, title: String, artist: String, album: String?, duration: Int) {
    var dict: [String: Any] = [
      "source": "youtube",
      "id": videoId,
      "title": title,
      "artist": artist,
      "duration": duration,
      "kind": "song",
    ]
    dict["album"] = album
    self.init(dict: dict)
  }

  init?(dict: [String: Any]) {
    guard let videoId = dict["id"] as? String, !videoId.isEmpty,
          let json = try? JSONSerialization.data(withJSONObject: dict)
    else { return nil }
    self.videoId = videoId
    self.title = (dict["title"] as? String) ?? "Unknown Title"
    let artists = (dict["artists"] as? [String]) ?? []
    self.artist = (dict["artist"] as? String) ?? artists.first ?? "Unknown Artist"
    self.album = dict["album"] as? String
    self.duration = (dict["duration"] as? NSNumber)?.intValue ?? 0
    self.thumbURL = (dict["thumb"] as? String).flatMap { URL(string: $0) }
    self.kind = dict["kind"] as? String
    // `library` is false/null when the song is missing, otherwise true or the relative path
    switch dict["library"] {
    case let path as String where !path.isEmpty:
      self.libraryPath = path
    case let number as NSNumber where number.boolValue:
      self.libraryPath = ""
    default:
      self.libraryPath = nil
    }
    self.json = json
  }

  public static func == (lhs: SongpickerHit, rhs: SongpickerHit) -> Bool {
    lhs.videoId == rhs.videoId
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(videoId)
  }
}

// MARK: - SongpickerJob

public enum SongpickerJobState: Sendable {
  case waiting
  case downloading
  case saving
  case done
  case failed

  init(rawValue: String) {
    switch rawValue.precomposedStringWithCanonicalMapping.lowercased() {
    case "lädt": self = .downloading
    case "speichert": self = .saving
    case "fertig": self = .done
    case "fehler": self = .failed
    default: self = .waiting
    }
  }

  public var isFinished: Bool { self == .done || self == .failed }
}

/// One entry of `getYtJobs.view`.
public struct SongpickerJob: Sendable, Equatable {
  public let state: SongpickerJobState
  public let title: String?
  public let artist: String?
  public let album: String?
  /// Navidrome path (`/music/<rel>`), once the file is saved.
  public let path: String?
  /// Navidrome ID, once the proxy matched the file (about 35 s after `fertig`).
  public let songId: String?
  public let error: String?
  /// Start of the job (Unix time), set again on a retry.
  public let started: Date?

  init(dict: [String: Any]) {
    self.state = SongpickerJobState(rawValue: (dict["state"] as? String) ?? "")
    self.title = (dict["title"] as? String) ?? (dict["label"] as? String)
    self.artist = dict["artist"] as? String
    self.album = dict["album"] as? String
    self.path = dict["path"] as? String
    self.songId = dict["songId"] as? String
    self.error = dict["error"] as? String
    switch dict["started"] {
    case let number as NSNumber:
      let seconds = number.doubleValue
      // milliseconds, if the value is too large for seconds
      self.started = Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
    case let text as String:
      self.started = ISO8601DateFormatter().date(from: text)
        ?? Double(text).map { Date(timeIntervalSince1970: $0) }
    default:
      self.started = nil
    }
  }

  /// Jobs of a `getYtJobs.view?f=json` answer, keyed by video ID.
  static func parseYtJobs(data: Data) throws -> [String: SongpickerJob] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["subsonic-response"] as? [String: Any]
    else { throw SongpickerError.invalidResponse }
    if response["status"] as? String != "ok" {
      let error = response["error"] as? [String: Any]
      throw SongpickerError.server((error?["message"] as? String) ?? "The proxy reported an error")
    }
    // no `ytJobs` at all: the account does not talk to the proxy
    guard let ytJobs = response["ytJobs"] as? [String: Any] else {
      throw SongpickerError.noProxy
    }
    let list = (ytJobs["job"] as? [[String: Any]]) ?? []
    var jobs = [String: SongpickerJob]()
    for dict in list {
      guard let videoId = dict["id"] as? String, !videoId.isEmpty else { continue }
      jobs[videoId] = SongpickerJob(dict: dict)
    }
    return jobs
  }
}

// MARK: - SongpickerError

public enum SongpickerError: LocalizedError {
  case invalidResponse
  case noProxy
  case server(String)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse: return "The proxy sent an invalid response"
    case .noProxy: return "The server of this account does not offer YouTube Music"
    case let .server(message): return message
    }
  }
}
