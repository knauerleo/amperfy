//
//  SpotlightIndexer.swift
//  Amperfy
//
//  Fork (F-15): albums, artists and playlists of the active account in Spotlight. The index is
//  rebuilt when the app becomes active and the last build is older than 6 hours or belongs to
//  another account. A tap on a result opens the detail page in the Library tab.
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
import CoreSpotlight
import os.log
import UIKit
import UniformTypeIdentifiers

// MARK: - SpotlightIndexer

@MainActor
final class SpotlightIndexer: NSObject {
  static let shared = SpotlightIndexer()

  /// Raise to force a rebuild after changing the item contents.
  private static let indexVersion = 1
  private static let reindexInterval: TimeInterval = 6 * 60 * 60
  nonisolated private static let batchSize = 1000
  private static let accountKey = "fork.spotlight.account"
  private static let dateKey = "fork.spotlight.date"
  private static let versionKey = "fork.spotlight.version"

  nonisolated private static let log = OSLog(subsystem: "Amperfy", category: "Spotlight")
  private var isStarted = false
  private var isIndexing = false
  /// Result tapped before the main window was ready (launch from Spotlight).
  private var pendingIdentifier: String?

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
  }

  @objc
  private func appDidBecomeActive() {
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      self.openPendingIfPossible()
      // indexing reads the whole library, not during the first seconds after launch
      try? await Task.sleep(nanoseconds: 4_500_000_000)
      self.reindexIfNeeded()
    }
  }

  // MARK: Index

  private func reindexIfNeeded() {
    guard !isIndexing, appDelegate.isNormalInteraction, CSSearchableIndex.isIndexingAvailable(),
          let accountInfo = appDelegate.storage.settings.accounts.active
    else { return }
    let defaults = UserDefaults.standard
    if defaults.string(forKey: Self.accountKey) == accountInfo.ident,
       defaults.integer(forKey: Self.versionKey) == Self.indexVersion,
       let lastDate = defaults.object(forKey: Self.dateKey) as? Date,
       Date().timeIntervalSince(lastDate) < Self.reindexInterval {
      return
    }
    isIndexing = true
    let accountIdent = accountInfo.ident
    let storage = appDelegate.storage
    let accountObjectId = storage.main.library.getAccount(info: accountInfo).managedObject.objectID
    Task { @MainActor in
      let entries = try? await storage.async.performAndGet { asyncCompanion in
        let account = asyncCompanion.library.getAccount(managedObjectId: accountObjectId)
        return asyncCompanion.library.getForkSpotlightEntries(for: account)
      }
      guard let entries else {
        self.isIndexing = false
        return
      }
      Self.rebuildIndex(entries: entries, accountIdent: accountIdent) { success in
        Task { @MainActor in
          self.isIndexing = false
          guard success else { return }
          let defaults = UserDefaults.standard
          defaults.set(accountIdent, forKey: Self.accountKey)
          defaults.set(Date(), forKey: Self.dateKey)
          defaults.set(Self.indexVersion, forKey: Self.versionKey)
          os_log("Indexed %d items", log: Self.log, type: .info, entries.count)
        }
      }
    }
  }

  /// Removes all items of the app (also those of a previous account) and indexes the entries.
  nonisolated private static func rebuildIndex(
    entries: [ForkSpotlightEntry],
    accountIdent: String,
    completion: @escaping @Sendable (Bool) -> ()
  ) {
    CSSearchableIndex.default().deleteAllSearchableItems { error in
      if let error {
        os_log("Delete failed: %s", log: log, type: .error, error.localizedDescription)
        completion(false)
        return
      }
      index(entries: entries[...], accountIdent: accountIdent, completion: completion)
    }
  }

  nonisolated private static func index(
    entries: ArraySlice<ForkSpotlightEntry>,
    accountIdent: String,
    completion: @escaping @Sendable (Bool) -> ()
  ) {
    guard !entries.isEmpty else {
      completion(true)
      return
    }
    let batch = entries.prefix(batchSize)
    let rest = entries.dropFirst(batchSize)
    let items = batch.map { makeItem(entry: $0, accountIdent: accountIdent) }
    CSSearchableIndex.default().indexSearchableItems(items) { error in
      if let error {
        os_log("Index failed: %s", log: log, type: .error, error.localizedDescription)
        completion(false)
        return
      }
      index(entries: rest, accountIdent: accountIdent, completion: completion)
    }
  }

  nonisolated private static func makeItem(
    entry: ForkSpotlightEntry,
    accountIdent: String
  ) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .content)
    attributes.title = entry.title
    attributes.displayName = entry.title
    if let artistName = entry.artistName, !artistName.isEmpty {
      attributes.contentDescription = "\(artistName) · \(entry.detail)"
      attributes.artist = artistName
    } else {
      attributes.contentDescription = entry.detail
    }
    if entry.kind == .album { attributes.album = entry.title }
    if let artworkPath = entry.artworkPath {
      attributes.thumbnailURL = URL(fileURLWithPath: artworkPath)
    }
    attributes.keywords = [entry.title, entry.artistName, entry.kind.rawValue].compactMap { $0 }
    return CSSearchableItem(
      uniqueIdentifier: identifier(kind: entry.kind, accountIdent: accountIdent, id: entry.id),
      domainIdentifier: entry.kind.rawValue,
      attributeSet: attributes
    )
  }

  /// "album/<account ident>/<id>". The account ident is "<server hash>-<user hash>".
  nonisolated private static func identifier(
    kind: ForkSpotlightEntry.Kind,
    accountIdent: String,
    id: String
  ) -> String {
    "\(kind.rawValue)/\(accountIdent)/\(id)"
  }

  // MARK: Open

  /// Opens the detail page of a tapped Spotlight result, later if the app is still starting.
  func open(userActivity: NSUserActivity) {
    guard userActivity.activityType == CSSearchableItemActionType,
          let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    else { return }
    pendingIdentifier = identifier
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 300_000_000)
      self.openPendingIfPossible()
    }
  }

  private func openPendingIfPossible() {
    guard let identifier = pendingIdentifier, appDelegate.isNormalInteraction,
          AppDelegate.mainWindowHostVC != nil
    else { return }
    pendingIdentifier = nil

    let parts = identifier.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3,
          let kind = ForkSpotlightEntry.Kind(rawValue: String(parts[0])),
          let activeInfo = appDelegate.storage.settings.accounts.active,
          activeInfo.ident == String(parts[1])
    else { return }
    let id = String(parts[2])
    let library = appDelegate.storage.main.library
    let account = library.getAccount(info: activeInfo)

    let detailVC: UIViewController?
    switch kind {
    case .album:
      detailVC = library.getAlbum(for: account, id: id, isDetailFaultResolution: true).map {
        AppStoryboard.Main.segueToAlbumDetail(account: account, album: $0)
      }
    case .artist:
      detailVC = library.getArtist(for: account, id: id).map {
        AppStoryboard.Main.segueToArtistDetail(account: account, artist: $0)
      }
    case .playlist:
      detailVC = library.getPlaylist(for: account, id: id).map {
        AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: $0)
      }
    }
    guard let detailVC else { return }
    // close the player first, the page would open behind it
    appDelegate.visualizePopupPlayer(direction: .close, animated: true) {
      self.appDelegate.displayInLibraryTab(vc: detailVC)
    }
  }
}
