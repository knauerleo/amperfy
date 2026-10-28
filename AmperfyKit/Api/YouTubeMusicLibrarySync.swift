//
//  YouTubeMusicLibrarySync.swift
//  AmperfyKit
//
//  Fork: brings a finished YouTube Music download into the local library. Navidrome needs about
//  35 s to scan the new file, so search3 is retried. The right song is found by the end of its
//  `path` (artist/album/file), because titles are not unique.
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
import os.log

extension Notification.Name {
  /// Posted on the main actor after a downloaded song was synced, `object` is the `Song`.
  public static let youTubeMusicSongSynced =
    Notification.Name(rawValue: "de.knauerleo.amperfy.youTubeMusic.songSynced")
}

// MARK: - YouTubeMusicLibrarySync

@MainActor
public final class YouTubeMusicLibrarySync {
  /// Seconds to wait before each search3 attempt, about four minutes in total.
  private static let attemptDelays: [Int] = [5, 10, 15, 20, 30, 45, 60, 60]
  /// Path components compared from the end: artist folder, album folder, file name.
  private static let comparedPathComponents = 3

  private let account: Account
  private let storage: PersistentStorage
  private let backendApi: BackendProxy
  private let librarySyncer: LibrarySyncer
  private let log = OSLog(subsystem: "Amperfy", category: "YouTubeMusic")

  public init(
    account: Account,
    storage: PersistentStorage,
    backendApi: BackendProxy,
    librarySyncer: LibrarySyncer
  ) {
    self.account = account
    self.storage = storage
    self.backendApi = backendApi
    self.librarySyncer = librarySyncer
  }

  /// Returns the synced song, or nil if Navidrome did not list it in time.
  @discardableResult
  public func syncFinishedDownload(hit: SongpickerHit, job: SongpickerJob) async -> Song? {
    let pathSuffix = Self.pathSuffix(job.path ?? hit.libraryPath)
    for delay in Self.attemptDelays {
      do {
        try await Task.sleep(for: .seconds(delay))
        if let song = try await findAndSync(hit: hit, pathSuffix: pathSuffix) {
          os_log("Synced YouTube download: %s", log: log, type: .info, song.displayString)
          NotificationCenter.default.post(name: .youTubeMusicSongSynced, object: song)
          return song
        }
      } catch is CancellationError {
        return nil
      } catch {
        os_log("search3 failed: %s", log: log, type: .info, error.localizedDescription)
      }
    }
    os_log("YouTube download not found on server: %s", log: log, type: .info, hit.title)
    return nil
  }

  private func findAndSync(hit: SongpickerHit, pathSuffix: String?) async throws -> Song? {
    guard let serverApi = backendApi.forkSubsonicServerApi else { return nil }
    let response = try await serverApi.requestSearchSongs(searchText: hit.title)
    let candidates = SongPathParser.parse(data: response.data)
    let match = candidates.first { candidate in
      guard let pathSuffix, let candidatePath = candidate.path else { return false }
      return Self.pathSuffix(candidatePath) == pathSuffix
    } ?? candidates.first { candidate in
      // without a path only an exact title and a similar duration count
      pathSuffix == nil &&
        candidate.title?.caseInsensitiveCompare(hit.title) == .orderedSame &&
        abs((candidate.duration ?? 0) - hit.duration) <= 3
    }
    guard let match else { return nil }

    // the regular sync creates song, album and artist with `addedDate` (Home: Recently Added)
    try await librarySyncer.searchSongs(searchText: hit.title)
    return storage.main.library.getSong(for: account, id: match.id)
  }

  /// `/music/YouTube/A/B/01 - C.opus` and `YouTube/A/B/01 - C.opus` both become `A/B/01 - C.opus`.
  static func pathSuffix(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    let components = path.precomposedStringWithCanonicalMapping
      .split(separator: "/", omittingEmptySubsequences: true)
    guard !components.isEmpty else { return nil }
    return components.suffix(comparedPathComponents).joined(separator: "/")
  }
}

// MARK: - SongPathParser

/// Reads `id`, `title`, `duration` and `path` of the `<song>` elements of a search3 response.
private final class SongPathParser: NSObject, XMLParserDelegate {
  struct Candidate {
    let id: String
    let title: String?
    let duration: Int?
    let path: String?
  }

  private var candidates = [Candidate]()

  static func parse(data: Data) -> [Candidate] {
    let delegate = SongPathParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.parse()
    return delegate.candidates
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard elementName == "song", let id = attributeDict["id"] else { return }
    candidates.append(Candidate(
      id: id,
      title: attributeDict["title"],
      duration: attributeDict["duration"].flatMap { Int($0) },
      path: attributeDict["path"]
    ))
  }
}
