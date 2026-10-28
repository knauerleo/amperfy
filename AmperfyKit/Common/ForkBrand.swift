//
//  ForkBrand.swift
//  AmperfyKit
//
//  Fork: the app name the user sees. Bundle ID, module, store and key names stay "Amperfy".
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

public enum ForkBrand {
  /// Keep in sync with CFBundleDisplayName and CFBundleName in Amperfy/Info.plist.
  public static let name = "Drift"

  public static let upstreamName = "Amperfy"
  public static let upstreamAuthor = "Maximilian Bauer"
  public static let upstreamURL = URL(string: "https://github.com/BLeeEZ/amperfy")!
}
