//
//  SwipeActionSettings+Fork.swift
//  AmperfyKit
//
//  Fork (design phase 4, measure 9): swipe defaults and menu texts in everyday language.
//  Leading edge = Play Next / Add to Queue, trailing edge = Favorite / Download.
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

import UIKit

extension SwipeActionSettings {
  /// Podcast actions only show on episodes, music queue actions only on music.
  static let forkDefaultLeading: [SwipeActionType] = [
    .insertUserQueue,
    .appendUserQueue,
    .insertPodcastQueue,
    .appendPodcastQueue,
  ]
  static let forkDefaultTrailing: [SwipeActionType] = [.favorite, .download]

  static var forkDefaultSettings: SwipeActionSettings {
    SwipeActionSettings(leading: forkDefaultLeading, trailing: forkDefaultTrailing)
  }

  /// The original defaults (`upstreamDefaultSettings`), replaced once if never changed.
  var isUpstreamDefault: Bool {
    let upstream = Self.upstreamDefaultSettings
    return leading == upstream.leading && trailing == upstream.trailing
  }
}

extension UserSettings {
  static let forkSwipeDefaultsVersion = 1

  /// Runs once: switches untouched upstream swipe defaults to the fork defaults.
  /// Returns true if the settings changed and need to be saved.
  public mutating func migrateForkSwipeDefaults() -> Bool {
    guard (_forkSwipeDefaultsVersion ?? 0) < Self.forkSwipeDefaultsVersion else { return false }
    if swipeActionSettings.isUpstreamDefault {
      swipeActionSettings = .forkDefaultSettings
    }
    _forkSwipeDefaultsVersion = Self.forkSwipeDefaultsVersion
    return true
  }
}

// MARK: - ForkMenuText

/// Replaces technical menu titles of the original app, so the upstream code keeps its literals.
public enum ForkMenuText {
  static let titles: [String: String] = [
    "Instant Mix": String(localized: "Song Radio", table: "Fork"),
    "Show Album": String(localized: "Go to Album", table: "Fork"),
    "Show Artist": String(localized: "Go to Artist", table: "Fork"),
    "Show Podcast": String(localized: "Go to Podcast", table: "Fork"),
    "Favorite": String(localized: "Add to Favorites", table: "Fork"),
    "Unmark favorite": String(localized: "Remove from Favorites", table: "Fork"),
    "Delete Cache": String(localized: "Remove Download", table: "Fork"),
    "Clear User Queue": String(localized: "Clear Queue", table: "Fork"),
    "Add Context Queue to Playlist": String(localized: "Add Current List to Playlist", table: "Fork"),
    "Scroll to currently playing": String(localized: "Scroll to Now Playing", table: "Fork"),
  ]

  public static func title(_ title: String) -> String {
    titles[title] ?? upstream(title)
  }

  /// UI-15b: an upstream literal in the app's language, from the table `Localizable` of the app
  /// (`Amperfy/Localizable.xcstrings`). Unknown texts stay as they are.
  public static func upstream(_ text: String) -> String {
    Bundle.main.localizedString(forKey: text, value: text, table: "Localizable")
  }

  /// Renames the actions in place, including those in submenus.
  @MainActor
  @discardableResult
  public static func relabel(_ elements: [UIMenuElement]) -> [UIMenuElement] {
    for element in elements {
      if let action = element as? UIAction {
        action.title = title(action.title)
      } else if let menu = element as? UIMenu {
        relabel(menu.children)
      }
    }
    return elements
  }
}
