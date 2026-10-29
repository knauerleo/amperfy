//
//  HomeManager+ForkMixes.swift
//  Amperfy
//
//  Fork (F-12): the "Made for You" section on Home. Three mixes from local data, see
//  LibraryStorage+ForkMixes.swift: Rediscover (favorites not heard for a long time), On Repeat
//  (most plays in the last 14 days) and the Daily Mix (favorites of the day plus
//  `getSimilarSongs2` for three of them, built when it is played).
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

// MARK: - HomeMix

struct HomeMix: Hashable, @unchecked Sendable {
  enum Kind: Int, CaseIterable {
    case daily
    case onRepeat
    case rediscover
  }

  let kind: Kind
  /// Daily Mix: only the favorites, the similar songs are added when it is played.
  let songs: [Song]

  var title: String {
    switch kind {
    case .daily: return "Daily Mix"
    case .onRepeat: return "On Repeat"
    case .rediscover: return "Rediscover"
    }
  }

  var subtitle: String {
    switch kind {
    case .daily: return "Favorites and similar songs"
    case .onRepeat: return "Your most played, last 14 days"
    case .rediscover: return "Favorites you haven't heard in a while"
    }
  }

  var symbolName: String {
    switch kind {
    case .daily: return "sun.max.fill"
    case .onRepeat: return "repeat"
    case .rediscover: return "clock.arrow.circlepath"
    }
  }

  var hue: CGFloat {
    switch kind {
    case .daily: return 0.08
    case .onRepeat: return 0.92
    case .rediscover: return 0.5
    }
  }

  static func == (lhs: HomeMix, rhs: HomeMix) -> Bool {
    lhs.kind == rhs.kind && lhs.songs.map(\.id) == rhs.songs.map(\.id)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(kind)
    hasher.combine(songs.map(\.id))
  }
}

extension GradientArtworkView {
  static func mix(_ mix: HomeMix) -> GradientArtworkView {
    GradientArtworkView(
      colors: colors(hue: mix.hue),
      symbol: UIImage(systemName: mix.symbolName) ?? .musicalNotes
    )
  }
}

// MARK: - HomeManager

extension HomeManager {
  static let mixSongCount = 50
  /// A mix with fewer songs is not worth a tile.
  static let mixMinimumSongCount = 5
  private static let dailyMixFavoriteCount = 20
  private static let dailyMixSeedCount = 3
  private static let dailyMixSimilarCount = 15

  func updateMixes() {
    guard orderedVisibleSections.contains(.mixes) else { return }
    let library = storage.main.library
    var mixes = [HomeMix]()
    let favorites = library.getDailyMixFavorites(
      for: account,
      count: Self.dailyMixFavoriteCount,
      onlyCached: isOfflineMode
    )
    if favorites.count >= Self.dailyMixSeedCount {
      mixes.append(HomeMix(kind: .daily, songs: favorites))
    }
    let onRepeat = library.getOnRepeatSongs(
      for: account,
      count: Self.mixSongCount,
      onlyCached: isOfflineMode
    )
    if onRepeat.count >= Self.mixMinimumSongCount {
      mixes.append(HomeMix(kind: .onRepeat, songs: onRepeat))
    }
    let rediscover = library.getRediscoverSongs(
      for: account,
      count: Self.mixSongCount,
      onlyCached: isOfflineMode
    )
    if rediscover.count >= Self.mixMinimumSongCount {
      mixes.append(HomeMix(kind: .rediscover, songs: rediscover))
    }
    guard mixes != forkMixes || data[.mixes] == nil else { return }
    forkMixes = mixes
    // the tiles are no entities, an empty list only marks the section as loaded
    data[.mixes] = []
    applySnapshotCB?()
  }

  /// The songs to play. The Daily Mix asks the server for songs similar to three of its
  /// favorites and mixes them in, offline or on errors it is the favorites alone.
  func songsToPlay(_ mix: HomeMix) async -> [AbstractPlayable] {
    var songs = mix.songs
    if mix.kind == .daily, storage.settings.user.isOnlineMode {
      let syncer = getMeta(account.info).librarySyncer
      var similar = [Song]()
      for seed in mix.songs.prefix(Self.dailyMixSeedCount) {
        do {
          let found = try await syncer.requestSimilarSongs(
            song: seed,
            count: Self.dailyMixSimilarCount
          )
          similar.append(contentsOf: found)
        } catch {
          eventLogger.report(topic: "Daily Mix", error: error, displayPopup: false)
        }
      }
      // favorite, similar, similar, favorite, …
      var seen = Set<String>()
      var combined = [Song]()
      var similarIterator = similar.filter { !$0.isYouTubeMusicPlaceholder }.makeIterator()
      for favorite in songs {
        if seen.insert(favorite.id).inserted { combined.append(favorite) }
        for _ in 0 ..< 2 {
          guard let next = similarIterator.next() else { break }
          if seen.insert(next.id).inserted { combined.append(next) }
        }
      }
      while let next = similarIterator.next() {
        if seen.insert(next.id).inserted { combined.append(next) }
      }
      songs = Array(combined.prefix(Self.mixSongCount))
    }
    return songs.filterCached(dependigOn: isOfflineMode)
  }
}
