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

  // MARK: Fixed accent (UI-18)

  private static let _isFixed = Atomic<Bool>(wrappedValue: false)

  /// Set at start on the iPhone: one fixed accent (mint) instead of the theme color of the account.
  /// Neutral Accent still wins, it is an explicit choice.
  public static var isFixed: Bool {
    get { _isFixed.wrappedValue }
    set { _isFixed.wrappedValue = newValue }
  }

  /// Mint #7FE7CB in dark mode, a darker mint in light mode so it stays readable on white.
  public static let fixedColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ?
      UIColor(red: 0x7F / 255, green: 0xE7 / 255, blue: 0xCB / 255, alpha: 1) :
      UIColor(red: 0x0E / 255, green: 0x8F / 255, blue: 0x73 / 255, alpha: 1)
  }

  /// Text and icons on top of the mint: the ground color #0B0B0F, white on the darker light mint.
  public static let fixedContrastColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ?
      UIColor(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0F / 255, alpha: 1) :
      .white
  }

  /// Read by `ThemePreference.asColor`: neutral, fixed or nil for the theme color.
  static var accentOverride: UIColor? {
    if isNeutral { return neutralColor }
    return isFixed ? fixedColor : nil
  }

  static var contrastOverride: UIColor? {
    if isNeutral { return neutralContrastColor }
    return isFixed ? fixedContrastColor : nil
  }
}
