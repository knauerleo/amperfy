//
//  DriftWidgetIntents.swift
//  Drift (app and widget extension)
//
//  Fork (F-14): the intents behind the widget and Control Center buttons. They are compiled
//  into the app and the widget extension. As audio playback intents the system performs them
//  in the app's process (started in the background if needed), where `DriftWidgetActions.handler`
//  is set at launch. In the extension process the handler stays nil and nothing happens.
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

import AppIntents
import Foundation

// MARK: - DriftWidgetAction

enum DriftWidgetAction: Sendable {
  case playRecent(id: String, kind: String)
  case shuffleFavorites
  case setPlaying(Bool)
}

// MARK: - DriftWidgetActions

@MainActor
enum DriftWidgetActions {
  /// Set by the app at launch.
  static var handler: ((DriftWidgetAction) async -> ())?

  static func run(_ action: DriftWidgetAction) async {
    await handler?(action)
  }
}

// MARK: - DriftPlayRecentIntent

struct DriftPlayRecentIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play Recently Played Item"
  static let description = IntentDescription("Plays an album, artist or playlist from Recently Played.")
  static let isDiscoverable = false

  @Parameter(title: "ID")
  var itemId: String

  @Parameter(title: "Type")
  var kind: String

  init() {}

  init(itemId: String, kind: String) {
    self.itemId = itemId
    self.kind = kind
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    await DriftWidgetActions.run(.playRecent(id: itemId, kind: kind))
    return .result()
  }
}

// MARK: - DriftShuffleFavoritesIntent

struct DriftShuffleFavoritesIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Shuffle Favorites"
  static let description = IntentDescription("Plays your favorite songs in random order.")

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    await DriftWidgetActions.run(.shuffleFavorites)
    return .result()
  }
}

// MARK: - DriftPlayPauseIntent

struct DriftPlayPauseIntent: SetValueIntent, AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause Drift"
  static let isDiscoverable = false

  @Parameter(title: "Playing")
  var value: Bool

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    await DriftWidgetActions.run(.setPlaying(value))
    return .result()
  }
}
