//
//  PlayQueueSyncCoordinator.swift
//  Amperfy
//
//  Fork (F-10): continue listening on another device. The queue, the current song and its
//  position go to the server (`savePlayQueue`) when playback pauses, when a new song starts and
//  when the app goes to the background. When the app becomes active and nothing plays, the queue
//  of the server (`getPlayQueue`) is offered as "Continue Listening?" if another device or
//  another client saved it after this device.
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

// MARK: - PlayQueueSyncCoordinator

@MainActor
final class PlayQueueSyncCoordinator: NSObject {
  static let shared = PlayQueueSyncCoordinator()

  /// Songs before the current one that are saved too.
  private static let maxPreviousSongs = 20
  /// All saved songs. Every ID is a query item of a GET request, this keeps the URL below 8 KB.
  private static let maxSongs = 150
  /// Server and device clocks may differ a little.
  private static let clockTolerance: TimeInterval = 10
  /// Same song and less apart than this: nothing to continue.
  private static let positionTolerance: Double = 15
  private static let minCheckInterval: TimeInterval = 20

  private let log = OSLog(subsystem: "Amperfy", category: "PlayQueueSync")
  private var isStarted = false
  private var lastSavedSignature: String?
  private var lastCheck: Date?
  private var isChecking = false

  private var player: PlayerFacade { appDelegate.player }

  /// Called once at start.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    player.addNotifier(notifier: self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  // MARK: Account

  private var activeAccountInfo: AccountInfo? {
    guard appDelegate.isNormalInteraction,
          !appDelegate.storage.settings.user.isOfflineMode
    else { return nil }
    return appDelegate.storage.settings.accounts.active
  }

  private func defaultsKey(_ name: String, _ accountInfo: AccountInfo) -> String {
    "fork.playQueue.\(name).\(accountInfo.ident)"
  }

  /// When this device saved the queue the last time.
  private func lastSaveDate(_ accountInfo: AccountInfo) -> Date? {
    UserDefaults.standard.object(forKey: defaultsKey("lastSave", accountInfo)) as? Date
  }

  /// `changed` of the server queue that was offered and answered (continued or declined).
  private func answeredDate(_ accountInfo: AccountInfo) -> Date? {
    UserDefaults.standard.object(forKey: defaultsKey("answered", accountInfo)) as? Date
  }

  // MARK: Save

  @objc
  private func appDidEnterBackground() {
    save()
  }

  private func save() {
    guard let accountInfo = activeAccountInfo,
          let snapshot = queueSnapshot(accountInfo: accountInfo)
    else { return }
    let signature = "\(snapshot.ids.joined(separator: ","))|\(snapshot.currentId)|" +
      "\(Int(snapshot.position / 5))"
    guard signature != lastSavedSignature else { return }
    lastSavedSignature = signature

    let backendApi = appDelegate.getMeta(accountInfo).backendApi
    let app = UIApplication.shared
    // pausing on the lock screen or leaving the app: finish the request before suspension
    let taskId = app.beginBackgroundTask(withName: "Fork.SavePlayQueue", expirationHandler: nil)
    let defaultsKey = defaultsKey("lastSave", accountInfo)
    let log = log
    Task { @MainActor in
      do {
        try await backendApi.forkSavePlayQueue(
          songIds: snapshot.ids,
          currentId: snapshot.currentId,
          position: snapshot.position
        )
        UserDefaults.standard.set(Date(), forKey: defaultsKey)
      } catch {
        self.lastSavedSignature = nil
        os_log("savePlayQueue failed: %s", log: log, type: .info, error.localizedDescription)
      }
      if taskId != .invalid { app.endBackgroundTask(taskId) }
    }
  }

  /// Songs of the queue in play order (previous, current, user queue, next), without podcasts,
  /// radios, YouTube placeholders (the server does not know them) and songs of other accounts.
  private func queueSnapshot(
    accountInfo: AccountInfo
  ) -> (ids: [String], currentId: String, position: Double)? {
    guard player.playerMode == .music, let current = player.currentlyPlaying else { return nil }
    let isSaveable: (AbstractPlayable) -> Bool = { playable in
      playable.isSong && !playable.isYouTubeMusicPlaceholder &&
        playable.account?.ident == accountInfo.ident
    }
    let previous = player.getAllPrevQueueItems().filter(isSaveable)
      .suffix(Self.maxPreviousSongs)
    var following = (player.getAllUserQueueItems() + player.getAllNextQueueItems())
      .filter(isSaveable)
    var currentId: String
    var position = 0.0
    if isSaveable(current) {
      currentId = current.id
      position = player.elapsedTime.isFinite ? player.elapsedTime : 0
    } else if let next = following.first {
      // a YouTube placeholder plays: continue with the next song
      currentId = next.id
      following.removeFirst()
    } else {
      return nil
    }
    let ids = previous.map { $0.id } + [currentId] +
      following.prefix(Self.maxSongs - previous.count - 1).map { $0.id }
    return (ids, currentId, position)
  }

  // MARK: Offer

  @objc
  private func appDidBecomeActive() {
    // let the main window settle after launch or a return from the background
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      await self.checkServerQueue()
    }
  }

  private func checkServerQueue() async {
    guard !isChecking, !player.isPlaying, let accountInfo = activeAccountInfo else { return }
    if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.minCheckInterval { return }
    lastCheck = Date()
    isChecking = true
    defer { isChecking = false }

    let account = appDelegate.storage.main.library.getAccount(info: accountInfo)
    let queue: SubsonicPlayQueue?
    do {
      queue = try await appDelegate.getMeta(accountInfo).backendApi.forkGetPlayQueue(
        account: account,
        storage: appDelegate.storage
      )
    } catch {
      os_log("getPlayQueue failed: %s", log: log, type: .info, error.localizedDescription)
      return
    }
    guard let queue, let currentSong = queue.currentSong, let changed = queue.changed else { return }
    // saved by this device, or already offered
    if let lastSave = lastSaveDate(accountInfo),
       changed <= lastSave.addingTimeInterval(Self.clockTolerance) { return }
    if let answered = answeredDate(accountInfo), abs(changed.timeIntervalSince(answered)) < 1 {
      return
    }
    // the same song at about the same position is already here
    if player.currentlyPlaying?.id == currentSong.id,
       abs(player.elapsedTime - queue.position) < Self.positionTolerance { return }
    // something started playing meanwhile
    guard !player.isPlaying else { return }
    offer(queue: queue, currentSong: currentSong, changed: changed, accountInfo: accountInfo)
  }

  private func offer(
    queue: SubsonicPlayQueue,
    currentSong: Song,
    changed: Date,
    accountInfo: AccountInfo
  ) {
    guard let topView = AppDelegate.topViewController(),
          topView.presentedViewController == nil
    else { return }

    var lines = ["“\(currentSong.title)” · \(currentSong.creatorName)"]
    var detail = "at \(Self.timeString(queue.position))"
    if queue.songs.count > 1 { detail += " · \(queue.songs.count) songs" }
    lines.append(detail)
    let ago = RelativeDateTimeFormatter().localizedString(for: min(changed, Date()), relativeTo: Date())
    if let client = queue.changedBy, !client.isEmpty, client != "Amperfy" {
      lines.append("Saved \(ago) in \(client)")
    } else {
      lines.append("Saved \(ago) on another device")
    }

    let alert = UIAlertController(
      title: "Continue Listening?",
      message: lines.joined(separator: "\n"),
      preferredStyle: .alert
    )
    let answeredKey = defaultsKey("answered", accountInfo)
    alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
      UserDefaults.standard.set(changed, forKey: answeredKey)
    })
    let continueAction = UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
      UserDefaults.standard.set(changed, forKey: answeredKey)
      self?.continuePlaying(queue: queue)
    }
    alert.addAction(continueAction)
    alert.preferredAction = continueAction
    topView.present(alert, animated: true)
  }

  private func continuePlaying(queue: SubsonicPlayQueue) {
    var songs: [AbstractPlayable] = queue.songs
    var index = queue.currentIndex
    if appDelegate.storage.settings.user.isOfflineMode {
      // went offline meanwhile: only cached songs
      let current = queue.currentSong
      songs = songs.filter { $0.isCached }
      index = current.flatMap { song in songs.firstIndex { $0.id == song.id } } ?? 0
    }
    guard !songs.isEmpty else { return }
    player.play(context: PlayContext(name: "Continue Listening", index: index, playables: songs))
    if queue.position > 1, songs[index].id == queue.currentSong?.id {
      // applied once the song is loaded
      player.seek(toSecond: queue.position)
    }
  }

  private static func timeString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

// MARK: MusicPlayable

extension PlayQueueSyncCoordinator: MusicPlayable {
  func didStartPlayingFromBeginning() {
    save()
  }

  func didStartPlaying() {}

  func didPause() {
    save()
  }

  func didStopPlaying() {}
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
