//
//  ForkLaunchScreenCache.swift
//  Amperfy
//
//  Fork: iOS keeps the old launch screen snapshot after an update from
//  LaunchScreen.storyboard to UILaunchScreen. Remove it once so iOS renders the new one.
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

enum ForkLaunchScreenCache {
  /// Raise when the launch screen changes again.
  private static let version = 2
  private static let key = "forkLaunchScreenCacheVersion"

  static func resetIfNeeded() {
    #if !targetEnvironment(macCatalyst)
      let defaults = UserDefaults.standard
      guard defaults.integer(forKey: key) < version else { return }
      let splashBoard = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/SplashBoard")
      try? FileManager.default.removeItem(at: splashBoard)
      defaults.set(version, forKey: key)
    #endif
  }
}
