//
//  UserSettings+Songpicker.swift
//  AmperfyKit
//
//  Fork: stored Songpicker settings (design phase 5). The fields are optional, so settings
//  saved before they existed still decode, and `nil` means the default.
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

extension UserSettings {
  /// YouTube Music section in the search and the download overview.
  public var isYouTubeMusicEnabled: Bool {
    get { _forkYouTubeMusicEnabled ?? true }
    set { _forkYouTubeMusicEnabled = newValue }
  }

  /// Own proxy address. `nil`: the account itself (or its host + `SongpickerConfig.proxyPort`
  /// if the account points to Navidrome directly). `_forkSongpickerURL` is no longer used.
  public var songpickerProxyURL: URL? {
    get { _forkSongpickerProxyURL.flatMap { URL(string: $0) } }
    set { _forkSongpickerProxyURL = newValue?.absoluteString }
  }
}
