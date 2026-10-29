//
//  ShareExtensionBridge.swift
//  Amperfy
//
//  Fork (F-9): keeps the configuration of the share extension ("Share → Drift") up to date.
//  Whenever the app becomes active it stores the proxy stream URL of the active account in the
//  shared keychain group (see `DriftShareConfig`). Without a Subsonic account it is removed.
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
import os.log
import UIKit

@MainActor
final class ShareExtensionBridge: NSObject {
  static let shared = ShareExtensionBridge()

  private let log = OSLog(subsystem: "Amperfy", category: "ShareExtension")
  private var isStarted = false
  private var isUpdating = false

  /// Called once at start.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    update()
  }

  @objc
  private func appDidBecomeActive() {
    update()
  }

  private func update() {
    guard !isUpdating else { return }
    guard let accountInfo = appDelegate.storage.settings.accounts.active else {
      DriftShareConfig.remove()
      return
    }
    isUpdating = true
    let backendApi = appDelegate.getMeta(accountInfo).backendApi
    let log = log
    Task { @MainActor in
      defer { self.isUpdating = false }
      do {
        let template = try await backendApi.forkYouTubeStreamTemplate(
          placeholder: DriftShareConfig.placeholder
        )
        let config = DriftShareConfig(
          streamURLTemplate: template.url.absoluteString,
          headers: template.headers,
          serverName: template.url.host ?? template.url.absoluteString
        )
        if !config.save() {
          os_log("Share config not saved", log: log, type: .error)
        }
      } catch SongpickerError.noProxy {
        DriftShareConfig.remove()
      } catch {
        // offline or server not reachable: keep what is stored
        os_log("Share config not updated: %s", log: log, type: .info, error.localizedDescription)
      }
    }
  }
}
