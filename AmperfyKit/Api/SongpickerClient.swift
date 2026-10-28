//
//  SongpickerClient.swift
//  AmperfyKit
//
//  Fork: client for the Songpicker service on the Raspberry Pi (YouTube Music search and download).
//  API: GET /api/search, POST /api/get, GET /api/jobs (see FORK.md).
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

/// All Songpicker and proxy addresses in one place, so the settings (phase 5) only need to set `baseURL`.
public enum SongpickerConfig {
  public static let defaultBaseURL = URL(string: "http://10.66.66.6:8781")!
  /// Port of the Subsonic proxy (nginx) that understands the `ytm-<videoId>` IDs.
  public static let proxyPort = 4534

  private static let _baseURL = Atomic<URL>(wrappedValue: defaultBaseURL)
  private static let _isEnabled = Atomic<Bool>(wrappedValue: true)

  public static var baseURL: URL {
    get { _baseURL.wrappedValue }
    set { _baseURL.wrappedValue = newValue }
  }

  /// Shows the YouTube Music section in the search.
  public static var isEnabled: Bool {
    get { _isEnabled.wrappedValue }
    set { _isEnabled.wrappedValue = newValue }
  }

  /// Same host as the Subsonic server of the account, but the proxy port.
  public static func proxyURL(rewriting url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.port = proxyPort
    return components.url ?? url
  }
}

// MARK: - SongpickerHit

/// One YouTube Music result of `GET /api/search`.
public struct SongpickerHit: Sendable, Hashable {
  public let videoId: String
  public let title: String
  public let artist: String
  public let album: String?
  public let duration: Int
  public let thumbURL: URL?
  public let kind: String?
  /// Relative path of the copy in the library, if the Songpicker already knows one.
  public let libraryPath: String?
  /// The complete result as returned by the server, `POST /api/get` expects it unchanged.
  public let json: Data

  public var isInLibrary: Bool { libraryPath != nil }

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

public struct SongpickerJob: Sendable, Equatable {
  public let state: SongpickerJobState
  public let label: String?
  public let path: String?
  public let error: String?

  init(dict: [String: Any]) {
    self.state = SongpickerJobState(rawValue: (dict["state"] as? String) ?? "")
    self.label = dict["label"] as? String
    self.path = dict["path"] as? String
    self.error = dict["error"] as? String
  }
}

// MARK: - SongpickerError

public enum SongpickerError: LocalizedError {
  case badStatus(Int)
  case invalidResponse
  case server(String)

  public var errorDescription: String? {
    switch self {
    case let .badStatus(code): return "Songpicker answered with status \(code)"
    case .invalidResponse: return "Songpicker sent an invalid response"
    case let .server(message): return message
    }
  }
}

// MARK: - SongpickerClient

public final class SongpickerClient: Sendable {
  public static let shared = SongpickerClient()

  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 20
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.session = URLSession(configuration: configuration)
  }

  /// YouTube Music results, in Songpicker order.
  public func search(query: String) async throws -> [SongpickerHit] {
    var components = URLComponents(
      url: SongpickerConfig.baseURL.appendingPathComponent("api/search"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [URLQueryItem(name: "q", value: query)]
    guard let url = components?.url else { throw SongpickerError.invalidResponse }
    let object = try await requestJSON(URLRequest(url: url))
    guard let dict = object as? [String: Any] else { throw SongpickerError.invalidResponse }
    if let message = dict["error"] as? String, !message.isEmpty {
      throw SongpickerError.server(message)
    }
    return ((dict["youtube"] as? [[String: Any]]) ?? []).compactMap { SongpickerHit(dict: $0) }
  }

  /// Starts the download into the library (`musik/YouTube/<artist>/<album>/NN - title.opus`).
  public func requestDownload(hit: SongpickerHit) async throws {
    var request = URLRequest(url: SongpickerConfig.baseURL.appendingPathComponent("api/get"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = hit.json
    _ = try await requestData(request)
  }

  /// All jobs the Songpicker knows, keyed by video ID.
  public func jobs() async throws -> [String: SongpickerJob] {
    var request = URLRequest(url: SongpickerConfig.baseURL.appendingPathComponent("api/jobs"))
    request.timeoutInterval = 8
    guard let dict = try await requestJSON(request) as? [String: Any]
    else { throw SongpickerError.invalidResponse }
    return dict.compactMapValues { ($0 as? [String: Any]).map { SongpickerJob(dict: $0) } }
  }

  private func requestJSON(_ request: URLRequest) async throws -> Any {
    let data = try await requestData(request)
    return try JSONSerialization.jsonObject(with: data)
  }

  private func requestData(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw SongpickerError.invalidResponse }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw SongpickerError.badStatus(http.statusCode)
    }
    return data
  }
}
