//
//  HomeManager+ForkShelves.swift
//  Amperfy
//
//  Fork (F-11): Home shelves from `getAlbumList2`: "Most Played" (`frequent`), "Top Rated"
//  (`highest`) and "Decades" (tiles, the albums come from `byYear`, see DecadeAlbumsVC).
//  The local lists (play counts, ratings, years) show right away and stay offline, online the
//  server's order replaces them.
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
import Foundation

extension HomeManager {
  /// Home appears often, the server lists are asked at most every 5 minutes per section.
  private static let remoteRefreshInterval: TimeInterval = 5 * 60
  @MainActor
  private static var lastRemoteRefresh = [String: Date]()

  private static let albumListSections: [(HomeSection, SubsonicAlbumListType)] = [
    (.mostPlayedAlbums, .frequent),
    (.topRatedAlbums, .highest),
  ]

  func createForkShelves() {
    for (section, _) in Self.albumListSections where orderedVisibleSections.contains(section) {
      updateLocalAlbumList(section)
    }
    if orderedVisibleSections.contains(.decades) {
      updateDecades()
    }
    updateMixes() // F-12
  }

  func forkShelvesUpdateFromRemote() {
    // Home appears: plays since the last visit change On Repeat and Rediscover (F-12)
    updateMixes()
    guard storage.settings.user.isOnlineMode else { return }
    for (section, type) in Self.albumListSections where orderedVisibleSections.contains(section) {
      let key = remoteKey(section)
      if let last = Self.lastRemoteRefresh[key], data[section]?.isEmpty == false,
         Date().timeIntervalSince(last) < Self.remoteRefreshInterval {
        continue
      }
      beginLoading(section)
      Task { @MainActor in
        defer { self.endLoading(section) }
        do {
          let ids = try await self.getMeta(self.account.info).backendApi
            .forkAlbumListIds(type: type, size: Self.sectionMaxItemCount)
          Self.lastRemoteRefresh[key] = Date()
          let albums = self.storage.main.library.getAlbums(
            for: self.account,
            orderedIds: ids,
            onlyCached: false
          )
          // an empty server list (nothing rated yet) keeps the local one
          guard !albums.isEmpty else { return }
          self.setAlbums(albums, for: section)
        } catch BackendError.notSupported {
          // Ampache: the local list stays
        } catch {
          self.eventLogger.report(topic: "Home \(section.title)", error: error, displayPopup: false)
        }
      }
    }
  }

  private func remoteKey(_ section: HomeSection) -> String {
    "\(account.info.serverHash)|\(account.info.userHash)|\(section)"
  }

  private func updateLocalAlbumList(_ section: HomeSection) {
    let library = storage.main.library
    let albums: [Album]
    switch section {
    case .mostPlayedAlbums:
      albums = library.getMostPlayedAlbums(
        for: account,
        count: Self.sectionMaxItemCount,
        onlyCached: isOfflineMode
      )
    case .topRatedAlbums:
      albums = library.getTopRatedAlbums(
        for: account,
        count: Self.sectionMaxItemCount,
        onlyCached: isOfflineMode
      )
    default:
      return
    }
    // online the server list replaces this one, keep it once it is there
    if isOfflineMode {
      Self.lastRemoteRefresh[remoteKey(section)] = nil
    } else if data[section]?.isEmpty == false {
      return
    }
    setAlbums(albums, for: section)
  }

  private func setAlbums(_ albums: [Album], for section: HomeSection) {
    data[section] = albums.map { HomeItem(section: section, playableContainable: $0) }
    applySnapshotCB?()
  }

  func updateDecades() {
    forkDecades = storage.main.library.getAlbumDecades(for: account, onlyCached: isOfflineMode)
    // the tiles are no entities, an empty list only marks the section as loaded
    data[.decades] = []
    applySnapshotCB?()
  }
}
