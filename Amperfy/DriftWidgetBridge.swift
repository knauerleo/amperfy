//
//  DriftWidgetBridge.swift
//  Amperfy
//
//  Fork (F-14): connects the app with the widget extension. Writes the snapshot the widgets
//  show (Recently Played like Home, number of favorite songs, current song and playback state)
//  plus small covers into the App Group, and performs the widget and Control Center buttons.
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
import WidgetKit

// MARK: - DriftWidgetBridge

@MainActor
final class DriftWidgetBridge: NSObject {
  static let shared = DriftWidgetBridge()

  private static let recentCount = 8
  private static let artworkSize: CGFloat = 240

  private let log = OSLog(subsystem: "Amperfy", category: "Widgets")
  private var isStarted = false
  private var pendingUpdate: Task<(), Never>?
  /// Snapshot of the last reload without its date, to skip reloads that change nothing.
  private var lastContent: Data?

  private var player: PlayerFacade { appDelegate.player }

  /// Called once at start, also when the system launches the app in the background for a
  /// widget button.
  func start() {
    guard !isStarted else { return }
    isStarted = true
    DriftWidgetActions.handler = { [weak self] action in
      await self?.perform(action)
    }
    player.addNotifier(notifier: self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scheduleUpdate),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateNow),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    scheduleUpdate()
  }

  // MARK: Actions

  private func perform(_ action: DriftWidgetAction) async {
    guard let account = appDelegate.intentManager.getAccount(fromIntent: nil) else { return }
    switch action {
    case let .playRecent(id, kind):
      await playRecent(id: id, kind: kind, account: account)
    case .shuffleFavorites:
      shuffleFavorites(account: account)
    case let .setPlaying(isPlaying):
      if isPlaying {
        player.play()
      } else {
        player.pause()
      }
    }
    scheduleUpdate()
  }

  private func playRecent(id: String, kind: String, account: Account) async {
    let type: PlayableContainerTypeAppEnum
    switch kind {
    case "artist": type = .artist
    case "playlist": type = .playlist
    default: type = .album
    }
    guard let container = appDelegate.intentManager.getPlayableContainer(
      account: account,
      id: id,
      libraryElementType: type
    ) else { return }
    let storage = appDelegate.storage
    if storage.settings.user.isOnlineMode {
      // albums and artists from Recently Played may not have their songs locally yet
      let meta = appDelegate.getMeta(account.info)
      try? await container.fetch(
        storage: storage,
        librarySyncer: meta.librarySyncer,
        playableDownloadManager: meta.playableDownloadManager
      )
      _ = appDelegate.intentManager.play(
        context: PlayContext(containable: container),
        shuffleOption: false,
        repeatOption: .off
      )
    } else {
      let cached = container.playables.filter(\.isCached)
      guard !cached.isEmpty else { return }
      _ = appDelegate.intentManager.play(
        context: PlayContext(containable: container, playables: cached),
        shuffleOption: false,
        repeatOption: .off
      )
    }
  }

  private func shuffleFavorites(account: Account) {
    let storage = appDelegate.storage
    var songs: [AbstractPlayable] = storage.main.library.getFavoriteSongs(for: account)
    if storage.settings.user.isOfflineMode {
      songs = songs.filter(\.isCached)
    }
    guard !songs.isEmpty else { return }
    let playables = Array(songs.shuffled().prefix(player.maxSongsToAddOnce))
    _ = appDelegate.intentManager.play(
      context: PlayContext(name: String(localized: "Favorite Songs", table: "Fork"), playables: playables),
      shuffleOption: true,
      repeatOption: .off
    )
  }

  // MARK: Snapshot

  @objc
  private func scheduleUpdate() {
    pendingUpdate?.cancel()
    pendingUpdate = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard !Task.isCancelled else { return }
      self.update()
    }
  }

  @objc
  private func updateNow() {
    pendingUpdate?.cancel()
    update()
  }

  private func update() {
    guard DriftAppGroup.containerURL != nil else {
      os_log("App Group not available", log: log, type: .error)
      return
    }
    let snapshot = makeSnapshot()
    var content = snapshot
    content.updated = .distantPast
    let data = try? JSONEncoder().encode(content)
    guard data != lastContent else { return }
    let old = lastContent.flatMap { try? JSONDecoder().decode(DriftWidgetSnapshot.self, from: $0) }
    lastContent = data
    snapshot.write()

    if old == nil || old?.recent != snapshot.recent || old?.accent != snapshot.accent ||
      old?.favoriteSongCount != snapshot.favoriteSongCount {
      WidgetCenter.shared.reloadAllTimelines()
    }
    if old == nil || old?.isPlaying != snapshot.isPlaying ||
      old?.nowPlayingTitle != snapshot.nowPlayingTitle {
      #if !targetEnvironment(macCatalyst)
        ControlCenter.shared.reloadControls(ofKind: DriftWidgetKind.controlPlayPause)
      #endif
    }
  }

  private func makeSnapshot() -> DriftWidgetSnapshot {
    let storage = appDelegate.storage
    guard appDelegate.isNormalInteraction,
          let accountInfo = storage.settings.accounts.active,
          let account = appDelegate.intentManager.getAccount(fromIntent: nil)
    else { return .empty }
    let setting = storage.settings.accounts.getSetting(accountInfo).read
    let isOffline = storage.settings.user.isOfflineMode
    let library = storage.main.library

    var usedFiles = Set<String>()
    let recent = library.getRecentlyPlayedContainers(
      for: account,
      count: Self.recentCount,
      onlyCached: isOffline
    ).compactMap { container -> DriftWidgetSnapshot.Item? in
      let kind: String
      let subtitle: String
      switch container {
      case is Album:
        kind = "album"
        subtitle = container.subtitle ?? String(localized: "Album", table: "Fork")
      case is Artist:
        kind = "artist"
        subtitle = String(localized: "Artist", table: "Fork")
      case is Playlist:
        kind = "playlist"
        subtitle = String(localized: "Playlist", table: "Fork")
      default:
        return nil
      }
      let file = writeArtwork(
        for: container,
        kind: kind,
        theme: setting.themePreference,
        preference: setting.artworkDisplayPreference
      )
      if let file { usedFiles.insert(file) }
      return DriftWidgetSnapshot.Item(
        id: container.id,
        kind: kind,
        title: container.name,
        subtitle: subtitle,
        artworkFile: file
      )
    }
    removeArtwork(except: usedFiles)

    var favorites: [AbstractPlayable] = library.getFavoriteSongs(for: account)
    if isOffline { favorites = favorites.filter(\.isCached) }

    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    setting.themePreference.asColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    let current = player.currentlyPlaying
    return DriftWidgetSnapshot(
      accountIdent: accountInfo.ident,
      recent: recent,
      favoriteSongCount: favorites.count,
      nowPlayingTitle: current?.title,
      nowPlayingArtist: current?.creatorName,
      isPlaying: player.isPlaying,
      accent: [Double(red), Double(green), Double(blue)],
      updated: Date()
    )
  }

  /// Writes a small JPEG of the container's cover once, named after the cover's file so a new
  /// cover gets a new file. Returns the file name.
  private func writeArtwork(
    for container: PlayableContainable,
    kind: String,
    theme: ThemePreference,
    preference: ArtworkDisplayPreference
  ) -> String? {
    guard let directory = DriftAppGroup.widgetArtworkDirectory,
          let entity = container.getArtworkCollection(theme: theme).singleImageEntity,
          let path = entity.imagePath(setting: preference)
    else { return nil }
    let source = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let name = "\(kind)-\(container.id)-\(source)"
      .map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
    let file = String(name.prefix(120)) + ".jpg"
    let url = directory.appendingPathComponent(file)
    if FileManager.default.fileExists(atPath: url.path) { return file }

    guard let image = UIImage(contentsOfFile: path) else { return nil }
    let side = Self.artworkSize
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
      .image { _ in
        // aspect fill
        let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
          x: (side - size.width) / 2,
          y: (side - size.height) / 2,
          width: size.width,
          height: size.height
        ))
      }
    guard let data = thumbnail.jpegData(compressionQuality: 0.8) else { return nil }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
      try data.write(to: url, options: .atomic)
      return file
    } catch {
      os_log("Artwork not written: %s", log: log, type: .error, error.localizedDescription)
      return nil
    }
  }

  private func removeArtwork(except files: Set<String>) {
    guard let directory = DriftAppGroup.widgetArtworkDirectory,
          let existing = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
    else { return }
    for file in existing where !files.contains(file) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }
  }
}

// MARK: MusicPlayable

extension DriftWidgetBridge: MusicPlayable {
  func didStartPlayingFromBeginning() {
    scheduleUpdate()
  }

  func didStartPlaying() {
    scheduleUpdate()
  }

  func didPause() {
    scheduleUpdate()
  }

  func didStopPlaying() {
    scheduleUpdate()
  }

  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
