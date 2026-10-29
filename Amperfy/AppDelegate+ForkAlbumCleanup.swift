//
//  AppDelegate+ForkAlbumCleanup.swift
//  Amperfy
//
//  Fork: once per account after the album split on the server (2026-10-29), hide albums whose
//  ID Navidrome no longer knows and move their songs to the current album
//  (`BackendProxy.forkCleanUpStaleAlbums`). Asked again on the next start if it failed.
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

import AmperfyKit
import UIKit

extension AppDelegate {
  private static let staleAlbumCleanupKey = "fork.staleAlbumCleanup.2026-10-29"

  func forkCleanUpStaleAlbumsOnce(accountInfo: AccountInfo) {
    let key = "\(Self.staleAlbumCleanupKey).\(accountInfo.serverHash).\(accountInfo.userHash)"
    guard !UserDefaults.standard.bool(forKey: key), storage.settings.user.isOnlineMode else { return }
    let account = storage.main.library.getAccount(info: accountInfo)
    let backendApi = getMeta(accountInfo).backendApi
    Task { @MainActor in
      do {
        let count = try await backendApi.forkCleanUpStaleAlbums(account: account, storage: self.storage)
        UserDefaults.standard.set(true, forKey: key)
        self.eventLogger.debug(topic: "Album Cleanup", message: "\(count) stale albums hidden")
      } catch {
        self.eventLogger.debug(topic: "Album Cleanup", message: error.localizedDescription)
      }
    }
  }
}
