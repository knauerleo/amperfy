//
//  BackendProxy+ForkYouTubeAlbum.swift
//  AmperfyKit
//
//  Fork (TASKS F-8): whole albums and artists from YouTube Music. Like `stream.view?id=ytm-…`
//  and `getYtJobs.view`, everything goes through Subsonic at the login host with the normal
//  auth parameters: `getYtAlbum`, `getYtArtist`, `downloadYtAlbum` (JSON) and `getCoverArt`
//  with `ytm-album-…`/`ytm-artist-…`. The Songpicker API stays internal.
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

// MARK: - YouTubeAlbumKind

public enum YouTubeAlbumKind: Sendable, Hashable {
  case album
  case single
  case ep

  init(rawValue: String?) {
    switch rawValue?.lowercased() {
    case "single": self = .single
    case "ep": self = .ep
    default: self = .album
    }
  }

  /// Singles and EPs are listed apart from the albums on the artist page.
  public var isSingleOrEP: Bool { self != .album }
}

// MARK: - YouTubeAlbumSong

/// One song of `getYtAlbum`/`downloadYtAlbum`: a `ytm-<videoId>` song plus its library state.
public struct YouTubeAlbumSong: Sendable, Hashable {
  /// `ytm-<videoId>`
  public let id: String
  public let videoId: String
  public let title: String
  public let artist: String
  /// Only set when the artist exists in Navidrome.
  public let artistId: String?
  /// Gaps are possible.
  public let track: Int?
  public let duration: Int
  public let downloaded: Bool
  /// The real song in Navidrome, preferred for playing.
  public let navidromeId: String?
  /// State of a running job on the proxy, nil without one.
  public let jobState: SongpickerJobState?
  /// The JSON attributes as strings, used to create the placeholder like the song parser does.
  let attributes: [String: String]

  init?(dict: [String: Any]) {
    let attributes = YouTubeAlbumJSON.stringAttributes(dict)
    guard let id = attributes["id"], YouTubeMusic.isPlaceholderId(id) else { return nil }
    self.id = id
    self.videoId = String(id.dropFirst(YouTubeMusic.idPrefix.count))
    self.title = YouTubeMusic.strippedTitle(attributes["title"] ?? "")
    self.artist = attributes["artist"] ?? ""
    self.artistId = attributes["artistId"]
    self.track = attributes["track"].flatMap { Int($0) }
    self.duration = attributes["duration"].flatMap { Int($0) } ?? 0
    self.downloaded = YouTubeAlbumJSON.bool(dict["downloaded"])
    let navidromeId = attributes["navidromeId"]
    self.navidromeId = (navidromeId?.isEmpty ?? true) ? nil : navidromeId
    self.jobState = attributes["ytState"].flatMap { $0.isEmpty ? nil : SongpickerJobState(rawValue: $0) }
    self.attributes = attributes
  }

  /// State for the track list: in the library, a running job, or only on YouTube Music.
  public var status: YouTubeMusicStatus {
    if downloaded { return .inLibrary }
    switch jobState {
    case .waiting: return .waiting
    case .downloading: return .downloading
    case .saving: return .saving
    case .done: return .inLibrary
    case .failed: return .failed
    case .none: return .online
    }
  }

  /// The song as a search result, e.g. to follow its download in `YouTubeMusicJobMonitor`.
  public func hit(album: String?) -> SongpickerHit? {
    SongpickerHit(videoId: videoId, title: title, artist: artist, album: album, duration: duration)
  }

  public static func == (lhs: YouTubeAlbumSong, rhs: YouTubeAlbumSong) -> Bool {
    lhs.attributes == rhs.attributes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - YouTubeAlbum

/// `getYtAlbum.view`: an album on YouTube Music, songs sorted by track number.
public struct YouTubeAlbum: Sendable, Equatable {
  /// `ytm-album-<browseId>`
  public let id: String
  public let name: String
  public let artist: String
  /// `ytm-artist-<channelId>`
  public let artistId: String?
  public let coverArt: String?
  public let songCount: Int
  public let duration: Int
  public let year: Int?
  public let kind: YouTubeAlbumKind
  public private(set) var songs: [YouTubeAlbumSong]

  /// The songs with their state from the answer of `downloadYtAlbum`.
  public func updated(with download: YouTubeAlbumDownload) -> YouTubeAlbum {
    let newSongs = Dictionary(download.songs.map { ($0.id, $0) }) { first, _ in first }
    var album = self
    album.songs = songs.map { newSongs[$0.id] ?? $0 }
    return album
  }

  init?(dict: [String: Any]) {
    let attributes = YouTubeAlbumJSON.stringAttributes(dict)
    guard let id = attributes["id"] else { return nil }
    self.id = id
    self.name = attributes["name"] ?? ""
    self.artist = attributes["artist"] ?? ""
    self.artistId = attributes["artistId"].flatMap { $0.isEmpty ? nil : $0 }
    self.coverArt = attributes["coverArt"].flatMap { $0.isEmpty ? nil : $0 }
    self.duration = attributes["duration"].flatMap { Int($0) } ?? 0
    self.year = attributes["year"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    self.kind = YouTubeAlbumKind(rawValue: attributes["ytType"])
    self.songs = YouTubeAlbumJSON.list(dict["song"]).compactMap { YouTubeAlbumSong(dict: $0) }
    self.songCount = attributes["songCount"].flatMap { Int($0) } ?? songs.count
  }
}

// MARK: - YouTubeArtistAlbum

/// One album of `getYtArtist.view` (without songs).
public struct YouTubeArtistAlbum: Sendable, Hashable {
  /// `ytm-album-<browseId>`
  public let id: String
  public let name: String
  public let artist: String
  public let coverArt: String?
  public let year: Int?
  public let kind: YouTubeAlbumKind

  init?(dict: [String: Any]) {
    let attributes = YouTubeAlbumJSON.stringAttributes(dict)
    guard let id = attributes["id"], !id.isEmpty else { return nil }
    self.id = id
    self.name = attributes["name"] ?? ""
    self.artist = attributes["artist"] ?? ""
    self.coverArt = attributes["coverArt"].flatMap { $0.isEmpty ? nil : $0 }
    self.year = attributes["year"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    self.kind = YouTubeAlbumKind(rawValue: attributes["ytType"])
  }
}

// MARK: - YouTubeArtist

/// `getYtArtist.view`: albums and EPs first, then singles, each newest first.
public struct YouTubeArtist: Sendable, Equatable {
  /// `ytm-artist-<channelId>`
  public let id: String
  public let name: String
  public let coverArt: String?
  public let artistImageUrl: URL?
  public let albums: [YouTubeArtistAlbum]

  init?(dict: [String: Any]) {
    let attributes = YouTubeAlbumJSON.stringAttributes(dict)
    guard let id = attributes["id"] else { return nil }
    self.id = id
    self.name = attributes["name"] ?? ""
    self.coverArt = attributes["coverArt"].flatMap { $0.isEmpty ? nil : $0 }
    self.artistImageUrl = attributes["artistImageUrl"].flatMap { URL(string: $0) }
    self.albums = YouTubeAlbumJSON.list(dict["album"]).compactMap { YouTubeArtistAlbum(dict: $0) }
  }
}

// MARK: - YouTubeAlbumDownload

/// `downloadYtAlbum.view`: one job per missing song, the songs with their new state.
public struct YouTubeAlbumDownload: Sendable, Equatable {
  public let albumId: String
  public let name: String
  public let artist: String
  /// Songs whose download was started.
  public let queued: Int
  /// Songs that were already in the library.
  public let skipped: Int
  public let songs: [YouTubeAlbumSong]

  init(dict: [String: Any]) {
    let attributes = YouTubeAlbumJSON.stringAttributes(dict)
    self.albumId = attributes["albumId"] ?? ""
    self.name = attributes["name"] ?? ""
    self.artist = attributes["artist"] ?? ""
    self.queued = attributes["queued"].flatMap { Int($0) } ?? 0
    self.skipped = attributes["skipped"].flatMap { Int($0) } ?? 0
    self.songs = YouTubeAlbumJSON.list(dict["song"]).compactMap { YouTubeAlbumSong(dict: $0) }
  }
}

// MARK: - YouTubeAlbumError

/// A failed `getYtAlbum`/`getYtArtist`/`downloadYtAlbum`. The proxy names the reason with the
/// stable short code `ytError`; its `message` is German and only shown for unknown codes.
public struct YouTubeAlbumError: LocalizedError, Sendable {
  public let code: String
  public let serverMessage: String

  /// No album or artist exists for the song (e.g. a plain YouTube upload): asking again won't help.
  public var isPermanent: Bool {
    ["missing_id", "invalid_id", "song_not_found", "no_album", "no_artist"].contains(code)
  }

  public var errorDescription: String? {
    switch code {
    case "missing_id":
      return String(localized: "No YouTube Music ID was sent.", table: "Fork")
    case "invalid_id":
      return String(localized: "This is not a valid YouTube Music ID.", table: "Fork")
    case "song_not_found":
      return String(localized: "YouTube Music doesn't know this song.", table: "Fork")
    case "no_album":
      return String(localized: "There is no album for this video on YouTube Music.", table: "Fork")
    case "no_artist":
      return String(localized: "There is no artist for this video on YouTube Music.", table: "Fork")
    case "album_not_found":
      return String(localized: "YouTube Music doesn't know this album, or it isn't reachable right now.", table: "Fork")
    case "artist_not_found":
      return String(localized: "YouTube Music doesn't know this artist, or it isn't reachable right now.", table: "Fork")
    case "yt_unavailable":
      return String(localized: "YouTube Music isn't reachable right now. Try again later.", table: "Fork")
    default:
      return serverMessage
    }
  }
}

// MARK: - YouTubeAlbumJSON

enum YouTubeAlbumJSON {
  /// The payload of a `?f=json` answer. A failed answer throws its message (e.g. code 70
  /// "Album/Künstler bei YouTube Music nicht gefunden …"), a missing payload means no proxy.
  static func payload(_ data: Data, key: String) throws -> [String: Any] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["subsonic-response"] as? [String: Any]
    else { throw SongpickerError.invalidResponse }
    if response["status"] as? String != "ok" {
      let error = response["error"] as? [String: Any]
      let message = (error?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      throw YouTubeAlbumError(
        code: (error?["ytError"] as? String) ?? "",
        serverMessage: message ?? String(localized: "The proxy reported an error", table: "Fork")
      )
    }
    guard let payload = response[key] as? [String: Any] else { throw SongpickerError.noProxy }
    return payload
  }

  /// `song`/`album` are always arrays in the JSON of the proxy, also with 0 or 1 entries.
  static func list(_ value: Any?) -> [[String: Any]] {
    (value as? [[String: Any]]) ?? []
  }

  static func bool(_ value: Any?) -> Bool {
    switch value {
    case let number as NSNumber: return number.boolValue
    case let text as String: return text.lowercased() == "true" || text == "1"
    default: return false
    }
  }

  /// Scalar values as strings, the way the XML song parser expects its attributes.
  static func stringAttributes(_ dict: [String: Any]) -> [String: String] {
    var result = [String: String]()
    for (key, value) in dict {
      switch value {
      case let text as String:
        result[key] = text
      case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
          result[key] = number.boolValue ? "true" : "false"
        } else if number.doubleValue == number.doubleValue.rounded() {
          result[key] = String(number.int64Value)
        } else {
          result[key] = number.stringValue
        }
      default:
        continue
      }
    }
    return result
  }
}

// MARK: - BackendProxy

extension BackendProxy {
  /// Uncached the proxy needs 1–3 s for an album and 3–5 s for an artist.
  private static let youTubeAlbumTimeout: TimeInterval = 30

  /// `getYtAlbum.view?id=ytm-<videoId>|ytm-album-<browseId>`
  public func forkYouTubeAlbum(id: String) async throws -> YouTubeAlbum {
    let data = try await forkYouTubeRequest(action: "getYtAlbum", id: id)
    guard let album = YouTubeAlbum(dict: try YouTubeAlbumJSON.payload(data, key: "album"))
    else { throw SongpickerError.invalidResponse }
    return album
  }

  /// `getYtArtist.view?id=ytm-<videoId>|ytm-artist-<channelId>`
  public func forkYouTubeArtist(id: String) async throws -> YouTubeArtist {
    let data = try await forkYouTubeRequest(action: "getYtArtist", id: id)
    guard let artist = YouTubeArtist(dict: try YouTubeAlbumJSON.payload(data, key: "artist"))
    else { throw SongpickerError.invalidResponse }
    return artist
  }

  /// `downloadYtAlbum.view?id=ytm-album-…|ytm-<videoId>`: one job per missing song (idempotent,
  /// failed jobs start again). The jobs show up in `getYtJobs`.
  public func forkDownloadYouTubeAlbum(id: String) async throws -> YouTubeAlbumDownload {
    let data = try await forkYouTubeRequest(action: "downloadYtAlbum", id: id)
    return YouTubeAlbumDownload(dict: try YouTubeAlbumJSON.payload(data, key: "ytAlbumDownload"))
  }

  /// JPEG of `getCoverArt.view?id=ytm-album-…|ytm-artist-…`, nil if the proxy has none (404).
  public func forkYouTubeCoverArt(id: String) async throws -> Data? {
    guard let serverApi = forkSubsonicServerApi else { throw SongpickerError.noProxy }
    let url = try await serverApi.generateUrl(forArtworkId: id)
    let (data, response) = try await load(SongpickerConfig.proxyURL(rewriting: url), serverApi)
    guard let http = response as? HTTPURLResponse else { throw SongpickerError.invalidResponse }
    if http.statusCode == 404 { return nil }
    guard (200 ..< 300).contains(http.statusCode),
          http.mimeType?.hasPrefix("image/") ?? true, !data.isEmpty
    else { return nil }
    return data
  }

  /// Subsonic request at the proxy with the account's credentials, built from the
  /// `getCoverArt` URL of the account (same auth parameters), action and `f=json` replaced.
  private func forkYouTubeRequest(action: String, id: String) async throws -> Data {
    guard let serverApi = forkSubsonicServerApi else { throw SongpickerError.noProxy }
    let artworkUrl = try await serverApi.generateUrl(forArtworkId: id)
    guard var components = URLComponents(
      url: SongpickerConfig.proxyURL(rewriting: artworkUrl),
      resolvingAgainstBaseURL: false
    ), components.path.hasSuffix("getCoverArt.view")
    else { throw SongpickerError.invalidResponse }
    components.path = String(components.path.dropLast("getCoverArt.view".count)) + "\(action).view"
    var queryItems = components.queryItems ?? []
    queryItems.removeAll { $0.name == "f" }
    queryItems.append(URLQueryItem(name: "f", value: "json"))
    components.queryItems = queryItems
    guard let url = components.url else { throw SongpickerError.invalidResponse }
    let (data, response) = try await load(url, serverApi)
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode)
    else { throw SongpickerError.invalidResponse }
    return data
  }

  private func load(_ url: URL, _ serverApi: SubsonicServerApi) async throws -> (Data, URLResponse) {
    var request = URLRequest(url: url)
    request.timeoutInterval = Self.youTubeAlbumTimeout
    serverApi.httpHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    return try await URLSession.shared.data(for: request)
  }

  // MARK: Songs

  /// Songs to play for the album: the real Navidrome song where there is one (fetched with
  /// `getSong` if it is not in the local library yet), otherwise the `ytm-` placeholder, which
  /// is created through the regular song parser like a search3 result. In album order.
  @MainActor
  public func forkYouTubeAlbumPlayables(
    _ songs: [YouTubeAlbumSong],
    account: Account,
    storage: PersistentStorage
  ) async -> [Song] {
    let library = storage.main.library
    var real = [String: Song]()
    var missingIds = [String]()
    for navidromeId in songs.compactMap(\.navidromeId) {
      if let song = library.getSong(for: account, id: navidromeId) {
        real[navidromeId] = song
      } else {
        missingIds.append(navidromeId)
      }
    }
    if !missingIds.isEmpty {
      let fetched = await forkFetchLibrarySongs(ids: missingIds, account: account, storage: storage)
      real.merge(fetched) { lhs, _ in lhs }
    }
    let placeholderSongs = songs.filter { $0.navidromeId.flatMap { real[$0] } == nil }
    let placeholders = await forkCreateYouTubePlaceholders(
      placeholderSongs,
      account: account,
      storage: storage
    )
    return songs.compactMap { song in
      song.navidromeId.flatMap { real[$0] } ?? placeholders[song.id]
    }
  }

  /// Real songs by Navidrome ID through `getSong` and the regular song parser.
  @MainActor
  private func forkFetchLibrarySongs(
    ids: [String],
    account: Account,
    storage: PersistentStorage
  ) async -> [String: Song] {
    guard let serverApi = forkSubsonicServerApi else { return [:] }
    let accountObjectId = account.managedObject.objectID
    let responses = await withTaskGroup(of: APIDataResponse?.self) { group in
      for id in ids {
        group.addTask { try? await serverApi.requestSongInfo(id: id) }
      }
      var result = [APIDataResponse]()
      for await response in group {
        if let response { result.append(response) }
      }
      return result
    }
    guard !responses.isEmpty else { return [:] }
    let performanceMonitor: ThreadPerformanceMonitor = ThreadPerformanceObserver.shared
    _ = try? await storage.async.performAndGet { asyncCompanion in
      let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
      for response in responses {
        let idParserDelegate = SsIDsParserDelegate(performanceMonitor: performanceMonitor)
        let idParser = XMLParser(data: response.data)
        idParser.delegate = idParserDelegate
        idParser.parse()
        let prefetch = asyncCompanion.library.getElements(
          account: accountAsync,
          prefetchIDs: idParserDelegate.prefetchIDs
        )
        let parserDelegate = SsSongParserDelegate(
          performanceMonitor: performanceMonitor,
          prefetch: prefetch,
          account: accountAsync,
          library: asyncCompanion.library
        )
        let parser = XMLParser(data: response.data)
        parser.delegate = parserDelegate
        parser.parse()
      }
      return true
    }
    var result = [String: Song]()
    for id in ids {
      result[id] = storage.main.library.getSong(for: account, id: id)
    }
    return result
  }

  /// `ytm-` placeholders for the songs, keyed by playable ID. The JSON attributes run through
  /// the song parser, so they are sanitized and their artist goes to the HitStore like search3.
  @MainActor
  private func forkCreateYouTubePlaceholders(
    _ songs: [YouTubeAlbumSong],
    account: Account,
    storage: PersistentStorage
  ) async -> [String: Song] {
    guard !songs.isEmpty else { return [:] }
    let accountObjectId = account.managedObject.objectID
    let performanceMonitor: ThreadPerformanceMonitor = ThreadPerformanceObserver.shared
    let attributeList = songs.map(\.attributes)
    _ = try? await storage.async.performAndGet { asyncCompanion in
      let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
      var prefetchIDs = LibraryStorage.PrefetchIdContainer()
      for attributes in attributeList {
        if let id = attributes["id"] { prefetchIDs.songIDs.insert(id) }
        if let coverArt = attributes["coverArt"], !coverArt.isEmpty {
          prefetchIDs.artworkIDs.insert(ArtworkRemoteInfo(id: coverArt, type: ""))
        }
      }
      let prefetch = asyncCompanion.library.getElements(
        account: accountAsync,
        prefetchIDs: prefetchIDs
      )
      let parserDelegate = SsSongParserDelegate(
        performanceMonitor: performanceMonitor,
        prefetch: prefetch,
        account: accountAsync,
        library: asyncCompanion.library
      )
      // the same calls an XML `<song …/>` element causes
      let parser = XMLParser(data: Data())
      for attributes in attributeList {
        parserDelegate.parser(
          parser,
          didStartElement: "song",
          namespaceURI: nil,
          qualifiedName: nil,
          attributes: attributes
        )
        parserDelegate.parser(parser, didEndElement: "song", namespaceURI: nil, qualifiedName: nil)
      }
      return true
    }
    var result = [String: Song]()
    for song in songs {
      result[song.id] = storage.main.library.getSong(for: account, id: song.id)
    }
    return result
  }
}
