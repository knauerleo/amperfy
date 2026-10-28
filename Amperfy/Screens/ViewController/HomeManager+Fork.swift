//
//  HomeManager+Fork.swift
//  Amperfy
//
//  Fork: data for the Home sections of design phase 3 (Recently Played grid, Recently Added),
//  loading state for skeletons and the "Sync Library" action of the empty Home.
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
import CoreData
import UIKit

// MARK: - HomeForkObserver

/// Watches songs by play and add date. Playing anything sets the song's `lastPlayedDate`
/// (and the context's), adding a song sets `addedDate`, so these two cover both new sections.
@MainActor
final class HomeForkObserver: NSObject, @preconcurrency NSFetchedResultsControllerDelegate {
  private var controllers = [NSFetchedResultsController<SongMO>: () -> ()]()
  private var pending = [ObjectIdentifier: Task<(), Never>]()

  func observe(_ request: NSFetchRequest<SongMO>, context: NSManagedObjectContext, onChange: @escaping () -> ()) {
    let controller = NSFetchedResultsController(
      fetchRequest: request,
      managedObjectContext: context,
      sectionNameKeyPath: nil,
      cacheName: nil
    )
    controller.delegate = self
    try? controller.performFetch()
    controllers[controller] = onChange
  }

  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    guard let controller = controller as? NSFetchedResultsController<SongMO>,
          let onChange = controllers[controller] else { return }
    // a playing or downloading song changes often, rebuild at most a few times per second
    let key = ObjectIdentifier(controller)
    pending[key]?.cancel()
    pending[key] = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard !Task.isCancelled else { return }
      onChange()
    }
  }
}

// MARK: - HomeManager

extension HomeManager {
  static let recentlyPlayedCount = 10

  /// Inserts the fork sections once into an existing stored selection (see AccountSetting).
  static func migrateForkSections(storage: PersistentStorage, account: Account) {
    guard storage.settings.accounts.getSetting(account.info).read
      .needsForkHomeSectionsMigration else { return }
    storage.settings.accounts.updateSetting(account.info) { $0.migrateForkHomeSections() }
  }

  /// A section shows skeletons while it has no items and is not loaded yet or still syncing.
  func isLoading(_ section: HomeSection) -> Bool {
    data[section] == nil || loadingSections.contains(section)
  }

  func beginLoading(_ section: HomeSection) {
    loadingSections.insert(section)
  }

  func endLoading(_ section: HomeSection) {
    guard loadingSections.remove(section) != nil else { return }
    applySnapshotCB?()
  }

  func createForkFetchControllers() {
    let observer = HomeForkObserver()
    forkObserver = observer
    if orderedVisibleSections.contains(.recentlyPlayed) {
      let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
      request.predicate = NSPredicate(format: "%K != nil", #keyPath(SongMO.lastPlayedDate))
      request.sortDescriptors = [NSSortDescriptor(
        key: #keyPath(SongMO.lastPlayedDate),
        ascending: false
      )]
      request.fetchLimit = 20
      observer.observe(request, context: storage.main.context) { [weak self] in
        self?.updateRecentlyPlayed()
      }
      updateRecentlyPlayed()
    }
    if orderedVisibleSections.contains(.recentlyAdded) {
      let request: NSFetchRequest<SongMO> = SongMO.fetchRequest()
      request.predicate = NSPredicate(format: "%K != nil", #keyPath(SongMO.addedDate))
      request.sortDescriptors = [NSSortDescriptor(key: #keyPath(SongMO.addedDate), ascending: false)]
      request.fetchLimit = 50
      observer.observe(request, context: storage.main.context) { [weak self] in
        self?.updateRecentlyAdded()
      }
      updateRecentlyAdded()
    }
  }

  func forkUpdateFromRemote() {
    // the newest albums fill up Recently Added, sync them unless the stock section already does
    guard orderedVisibleSections.contains(.recentlyAdded),
          !orderedVisibleSections.contains(.newestAlbums) else { return }
    beginLoading(.recentlyAdded)
    Task { @MainActor in
      defer { self.endLoading(.recentlyAdded) }
      do {
        try await AutoDownloadLibrarySyncer(
          storage: self.storage,
          account: self.account,
          librarySyncer: self.getMeta(self.account.info).librarySyncer,
          playableDownloadManager: self.getMeta(self.account.info).playableDownloadManager
        )
        .syncNewestLibraryElements(offset: 0, count: Self.sectionMaxItemCount)
      } catch {
        self.eventLogger.report(topic: "Newest Albums Sync", error: error)
      }
      self.updateRecentlyAdded()
    }
  }

  func updateRecentlyPlayed() {
    let containers = storage.main.library.getRecentlyPlayedContainers(
      for: account,
      count: Self.recentlyPlayedCount,
      onlyCached: isOfflineMode
    )
    data[.recentlyPlayed] = containers.map {
      HomeItem(section: .recentlyPlayed, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  func updateRecentlyAdded() {
    let albums = storage.main.library.getRecentlyAddedAlbums(
      for: account,
      count: Self.sectionMaxItemCount,
      onlyCached: isOfflineMode
    )
    data[.recentlyAdded] = albums.map {
      HomeItem(section: .recentlyAdded, playableContainable: $0)
    }
    applySnapshotCB?()
  }

  /// Action of the empty Home: pulls everything Home shows from the server,
  /// independent of which sections are visible.
  func syncLibraryForHome() {
    guard storage.settings.user.isOnlineMode else { return }
    let sections = orderedVisibleSections
    sections.forEach { beginLoading($0) }
    applySnapshotCB?()
    Task { @MainActor in
      defer { sections.forEach { self.endLoading($0) } }
      let syncer = self.getMeta(self.account.info).librarySyncer
      do {
        try await AutoDownloadLibrarySyncer(
          storage: self.storage,
          account: self.account,
          librarySyncer: syncer,
          playableDownloadManager: self.getMeta(self.account.info).playableDownloadManager
        )
        .syncNewestLibraryElements(offset: 0, count: Self.sectionMaxItemCount)
        try await syncer.syncRecentAlbums(offset: 0, count: Self.sectionMaxItemCount)
        try await syncer.syncDownPlaylistsWithoutSongs()
        try await syncer.syncFavoriteLibraryElements()
      } catch {
        self.eventLogger.report(topic: "Home Sync", error: error)
      }
      self.createFetchController()
    }
  }
}
