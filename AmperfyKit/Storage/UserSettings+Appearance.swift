//
//  UserSettings+Appearance.swift
//  AmperfyKit
//
//  Fork: dark-first appearance and the optional neutral accent (measure 14).
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

extension UserSettings {
  static let forkAppearanceVersion = 1

  /// Runs once: switches the appearance to Dark if it was never changed (still "System").
  /// A choice of Light stays. "System" chosen after this migration stays as well.
  /// Returns true if the settings changed and need to be saved.
  public mutating func migrateForkDarkFirst() -> Bool {
    guard (_forkAppearanceVersion ?? 0) < Self.forkAppearanceVersion else { return false }
    if appearanceMode == .unspecified {
      appearanceMode = .dark
    }
    _forkAppearanceVersion = Self.forkAppearanceVersion
    return true
  }

  /// White (dark mode) or black (light mode) instead of the theme color. Default off.
  public var isNeutralAccent: Bool {
    get { _forkNeutralAccent ?? false }
    set { _forkNeutralAccent = newValue }
  }
}

// MARK: - ForkAccent

/// Global switch read by `ThemePreference.asColor`, set at start and when the setting changes.
public enum ForkAccent {
  private static let _isNeutral = Atomic<Bool>(wrappedValue: false)

  public static var isNeutral: Bool {
    get { _isNeutral.wrappedValue }
    set { _isNeutral.wrappedValue = newValue }
  }

  /// Label color: white in dark mode, black in light mode.
  static let neutralColor = UIColor.label
  /// Text and icons on top of the neutral accent.
  static let neutralContrastColor = UIColor.systemBackground
}
