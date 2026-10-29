//
//  DriftAppGroup.swift
//  Drift (app and extensions)
//
//  Fork (F-14): the App Group shared by the app and its extensions. The app writes a small
//  snapshot (recently played, favorites, playback state) and the covers as JPEG files, the
//  widgets only read them. Neither Core Data nor AmperfyKit is shared.
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

// MARK: - DriftAppGroup

enum DriftAppGroup {
  static let identifier = "group.de.knauerleo.amperfy-music"

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  static var widgetSnapshotURL: URL? {
    containerURL?.appendingPathComponent("widget-snapshot.json")
  }

  static var widgetArtworkDirectory: URL? {
    containerURL?.appendingPathComponent("WidgetArtwork", isDirectory: true)
  }
}

// MARK: - DriftWidgetKind

enum DriftWidgetKind {
  static let recent = "de.knauerleo.amperfy-music.widget.recent"
  static let shuffleFavorites = "de.knauerleo.amperfy-music.widget.shuffleFavorites"
  static let controlShuffleFavorites = "de.knauerleo.amperfy-music.control.shuffleFavorites"
  static let controlPlayPause = "de.knauerleo.amperfy-music.control.playPause"
}

// MARK: - DriftWidgetSnapshot

struct DriftWidgetSnapshot: Codable, Sendable {
  struct Item: Codable, Hashable, Identifiable, Sendable {
    /// Library ID of the album, artist or playlist.
    var id: String
    /// "album", "artist" or "playlist"
    var kind: String
    var title: String
    var subtitle: String
    /// File name in `DriftAppGroup.widgetArtworkDirectory`
    var artworkFile: String?
  }

  var accountIdent: String?
  var recent: [Item]
  var favoriteSongCount: Int
  var nowPlayingTitle: String?
  var nowPlayingArtist: String?
  var isPlaying: Bool
  /// Theme color of the account as RGB 0...1
  var accent: [Double]?
  var updated: Date

  static let empty = DriftWidgetSnapshot(
    accountIdent: nil,
    recent: [],
    favoriteSongCount: 0,
    nowPlayingTitle: nil,
    nowPlayingArtist: nil,
    isPlaying: false,
    accent: nil,
    updated: .distantPast
  )

  static func read() -> DriftWidgetSnapshot {
    guard let url = DriftAppGroup.widgetSnapshotURL,
          let data = try? Data(contentsOf: url),
          let snapshot = try? JSONDecoder().decode(DriftWidgetSnapshot.self, from: data)
    else { return .empty }
    return snapshot
  }

  func write() {
    guard let url = DriftAppGroup.widgetSnapshotURL,
          let data = try? JSONEncoder().encode(self) else { return }
    try? data.write(to: url, options: .atomic)
  }

  func artworkURL(for item: Item) -> URL? {
    guard let file = item.artworkFile else { return nil }
    return DriftAppGroup.widgetArtworkDirectory?.appendingPathComponent(file)
  }
}
