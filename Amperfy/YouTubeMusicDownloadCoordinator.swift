//
//  YouTubeMusicDownloadCoordinator.swift
//  Amperfy
//
//  Fork (TASKS F-7): app-wide handling of YouTube Music downloads, independent of the search tab.
//  Follows every placeholder that plays (search, shelves, radio), syncs finished downloads into
//  the library and posts a local notification when a download is done or failed.
//  Tapping the notification of a finished download opens its album.
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
import UserNotifications

// MARK: - YouTubeMusicDownloadCoordinator

@MainActor
final class YouTubeMusicDownloadCoordinator: NSObject {
  static let shared = YouTubeMusicDownloadCoordinator()

  /// `type` in the user info of the download notifications.
  nonisolated static let notificationType = "fork.youTubeMusicDownload"

  private let log = OSLog(subsystem: "Amperfy", category: "YouTubeMusic")
  private var isStarted = false
  private var didCheckAuthorization = false
  private var monitor: YouTubeMusicJobMonitor { .shared }

  /// Called once at start, after the monitor got the backend of the active account.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    monitor.onDownloadFinished = { [weak self] hit, job in
      self?.downloadFinished(hit: hit, job: job)
    }
    monitor.onDownloadFailed = { [weak self] videoId, job in
      self?.downloadFailed(videoId: videoId, job: job)
    }
    appDelegate.notificationHandler.register(
      self,
      selector: #selector(playerDidPlay(notification:)),
      name: .playerPlay,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(statusChanged(notification:)),
      name: .youTubeMusicStatusChanged,
      object: nil
    )
  }

  // MARK: Tracking

  /// A placeholder that plays streams through the proxy, which starts its download.
  @objc
  private func playerDidPlay(notification: Notification) {
    guard let playable = appDelegate.player.currentlyPlaying,
          playable.isYouTubeMusicPlaceholder,
          let hit = YouTubeMusicHitStore.shared.hit(
            forVideoId: String(playable.id.dropFirst(YouTubeMusic.idPrefix.count))
          )
    else { return }
    monitor.track(hit)
  }

  /// Asks for notifications once, when the first download runs and nobody asked before.
  @objc
  private func statusChanged(notification: Notification) {
    guard !didCheckAuthorization, monitor.jobList.contains(where: { $0.status.isLoading })
    else { return }
    didCheckAuthorization = true
    let manager = appDelegate.localNotificationManager
    Task {
      if await manager.hasAuthorizationNotBeenAskedYet() {
        manager.requestAuthorization()
      }
    }
  }

  // MARK: Finished downloads

  private func downloadFinished(hit: SongpickerHit, job: SongpickerJob) {
    guard let accountInfo = appDelegate.storage.settings.accounts.active else { return }
    let account = appDelegate.storage.main.library.getAccount(info: accountInfo)
    let meta = appDelegate.getMeta(accountInfo)
    let sync = YouTubeMusicLibrarySync(
      account: account,
      storage: appDelegate.storage,
      backendApi: meta.backendApi,
      librarySyncer: meta.librarySyncer
    )
    Task { @MainActor in
      // the song is in the library once Navidrome scanned it (about 35 s after `fertig`)
      let song = await sync.syncFinishedDownload(hit: hit, job: job)
      notify(
        identifier: "youtube-\(hit.videoId)",
        title: String(localized: "Added to Library", table: "Fork"),
        body: "\(song?.title ?? job.title ?? hit.title) · \(song?.creatorName ?? job.artist ?? hit.artist)",
        accountIdent: account.ident,
        albumId: song?.album?.id
      )
    }
  }

  private func downloadFailed(videoId: String, job: SongpickerJob) {
    let hit = YouTubeMusicHitStore.shared.hit(forVideoId: videoId)
    let title = job.title ?? hit?.title ?? videoId
    var body = title
    if let artist = job.artist ?? hit?.artist { body += " · \(artist)" }
    if let error = job.error, !error.isEmpty { body += "\n\(error)" }
    notify(
      identifier: "youtube-\(videoId)",
      title: String(localized: "Download Failed", table: "Fork"),
      body: body,
      accountIdent: nil,
      albumId: nil
    )
  }

  private func notify(
    identifier: String,
    title: String,
    body: String,
    accountIdent: String?,
    albumId: String?
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    var userInfo: [String: String] = [NotificationUserInfo.type: Self.notificationType]
    userInfo[NotificationUserInfo.account] = accountIdent
    userInfo[NotificationUserInfo.id] = albumId
    content.userInfo = userInfo
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    let log = log
    Task {
      let center = UNUserNotificationCenter.current()
      let settings = await center.notificationSettings()
      guard settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional
      else { return }
      do {
        try await center.add(request)
      } catch {
        os_log("Notification failed: %s", log: log, type: .error, error.localizedDescription)
      }
    }
  }

  // MARK: Tap

  /// Opens the album of a finished download. True if the notification was one of ours.
  nonisolated static func handleTap(userInfo: [AnyHashable: Any]) -> Bool {
    guard userInfo[NotificationUserInfo.type] as? String == notificationType else { return false }
    let accountIdent = userInfo[NotificationUserInfo.account] as? String
    let albumId = userInfo[NotificationUserInfo.id] as? String
    Task { @MainActor in
      shared.openAlbum(accountIdent: accountIdent, albumId: albumId)
    }
    return true
  }

  private func openAlbum(accountIdent: String?, albumId: String?) {
    guard let accountIdent, let albumId,
          let accountInfo = AccountInfo.create(basedOnIdent: accountIdent)
    else { return }
    let library = appDelegate.storage.main.library
    let account = library.getAccount(info: accountInfo)
    guard let album = library.getAlbum(for: account, id: albumId, isDetailFaultResolution: true)
    else { return }
    appDelegate.displayInLibraryTab(
      vc: AppStoryboard.Main.segueToAlbumDetail(account: account, album: album)
    )
  }
}
