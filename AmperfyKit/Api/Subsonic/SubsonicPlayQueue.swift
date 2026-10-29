//
//  SubsonicPlayQueue.swift
//  AmperfyKit
//
//  Fork (F-10): continue listening on another device. `savePlayQueue` stores the queue, the
//  current song and its position on the server, `getPlayQueue` reads it back. The songs of
//  `getPlayQueue` come as `entry` elements and run through the normal song parser, so songs that
//  are not in the local library yet are created like in every other Subsonic response.
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

// MARK: - SubsonicPlayQueue

/// A play queue saved on the server. `songs` live in the main context.
public struct SubsonicPlayQueue {
  public let songs: [Song]
  /// Index of the current song in `songs` (0 if the server names none or an unknown one).
  public let currentIndex: Int
  /// Position within the current song in seconds.
  public let position: Double
  /// When the queue was saved (server clock), nil if the server does not tell.
  public let changed: Date?
  /// Client name of the saving app, e.g. "Amperfy" or "Feishin".
  public let changedBy: String?

  public var currentSong: Song? {
    songs.indices.contains(currentIndex) ? songs[currentIndex] : nil
  }

  static func parseDate(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
  }
}

// MARK: - SsPlayQueueParserDelegate

/// Song parser that also reads the attributes of `<playQueue>`.
class SsPlayQueueParserDelegate: SsSongParserDelegate {
  private(set) var isPlayQueueFound = false
  private(set) var currentId: String?
  private(set) var positionMs: Int = 0
  private(set) var changed: String?
  private(set) var changedBy: String?

  override func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    if elementName == "playQueue" {
      isPlayQueueFound = true
      currentId = attributeDict["current"]
      positionMs = Int(attributeDict["position"] ?? "") ?? 0
      changed = attributeDict["changed"]
      changedBy = attributeDict["changedBy"]
    }
    super.parser(
      parser,
      didStartElement: elementName,
      namespaceURI: namespaceURI,
      qualifiedName: qName,
      attributes: attributeDict
    )
  }
}

// MARK: - BackendProxy

extension BackendProxy {
  /// Saves the queue on the server. `position` in seconds within the current song.
  public func forkSavePlayQueue(songIds: [String], currentId: String, position: Double) async throws {
    guard let serverApi = forkSubsonicServerApi else { throw BackendError.notSupported }
    let response = try await serverApi.requestSavePlayQueue(
      songIds: songIds,
      currentId: currentId,
      position: max(0, Int(position * 1000))
    )
    let delegate = SsXmlParser(performanceMonitor: ThreadPerformanceObserver.shared)
    let parser = XMLParser(data: response.data)
    parser.delegate = delegate
    parser.parse()
    if let error = delegate.error {
      throw SongpickerError.server(error.message.isEmpty ? "savePlayQueue failed" : error.message)
    }
  }

  /// The queue saved on the server, nil if there is none. Unknown songs are created in the library.
  @MainActor
  public func forkGetPlayQueue(
    account: Account,
    storage: PersistentStorage
  ) async throws -> SubsonicPlayQueue? {
    guard let serverApi = forkSubsonicServerApi else { throw BackendError.notSupported }
    let response = try await serverApi.requestGetPlayQueue()
    let accountObjectId = account.managedObject.objectID
    let performanceMonitor: ThreadPerformanceMonitor = ThreadPerformanceObserver.shared

    let parsed: (
      ids: [NSManagedObjectID],
      currentId: String?,
      positionMs: Int,
      changed: String?,
      changedBy: String?
    )? = try await storage.async.performAndGet { asyncCompanion in
      let accountAsync = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
      let idParserDelegate = SsIDsParserDelegate(performanceMonitor: performanceMonitor)
      let idParser = XMLParser(data: response.data)
      idParser.delegate = idParserDelegate
      idParser.parse()
      let prefetch = asyncCompanion.library.getElements(
        account: accountAsync,
        prefetchIDs: idParserDelegate.prefetchIDs
      )
      let parserDelegate = SsPlayQueueParserDelegate(
        performanceMonitor: performanceMonitor,
        prefetch: prefetch,
        account: accountAsync,
        library: asyncCompanion.library
      )
      let parser = XMLParser(data: response.data)
      parser.delegate = parserDelegate
      parser.parse()
      // no saved queue: Navidrome answers without `playQueue`, others with error 70 (not found)
      guard parserDelegate.error == nil, parserDelegate.isPlayQueueFound else { return nil }
      return (
        parserDelegate.parsedSongs.map { $0.managedObject.objectID },
        parserDelegate.currentId,
        parserDelegate.positionMs,
        parserDelegate.changed,
        parserDelegate.changedBy
      )
    }
    guard let parsed else { return nil }

    let songs = parsed.ids.compactMap { objectId -> Song? in
      guard let songMO = try? storage.main.context.existingObject(with: objectId) as? SongMO
      else { return nil }
      return Song(managedObject: songMO)
    }
    let currentIndex = parsed.currentId.flatMap { id in songs.firstIndex { $0.id == id } }
    return SubsonicPlayQueue(
      songs: songs,
      currentIndex: currentIndex ?? 0,
      position: currentIndex == nil ? 0 : Double(parsed.positionMs) / 1000,
      changed: SubsonicPlayQueue.parseDate(parsed.changed),
      changedBy: parsed.changedBy
    )
  }
}
