//
//  DriftWidgetsBundle.swift
//  DriftWidgets
//
//  Fork (F-14): widgets "Recently Played" and "Shuffle Favorites" and two Control Center
//  controls. Everything shown comes from the snapshot the app writes into the App Group.
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

import SwiftUI
import WidgetKit

// MARK: - DriftWidgetsBundle

@main
struct DriftWidgetsBundle: WidgetBundle {
  var body: some Widget {
    RecentWidget()
    ShuffleFavoritesWidget()
    ShuffleFavoritesControl()
    PlayPauseControl()
  }
}

// MARK: - DriftWidgetEntry

struct DriftWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: DriftWidgetSnapshot
}

// MARK: - DriftSnapshotProvider

/// The app reloads the timelines whenever the snapshot changes, so one entry is enough.
struct DriftSnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> DriftWidgetEntry {
    DriftWidgetEntry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (DriftWidgetEntry) -> ()) {
    let snapshot = DriftWidgetSnapshot.read()
    let useful = !snapshot.recent.isEmpty || snapshot.favoriteSongCount > 0
    completion(DriftWidgetEntry(
      date: Date(),
      snapshot: context.isPreview && !useful ? .placeholder : snapshot
    ))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DriftWidgetEntry>) -> ()) {
    let entry = DriftWidgetEntry(date: Date(), snapshot: DriftWidgetSnapshot.read())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

// MARK: - Placeholder

extension DriftWidgetSnapshot {
  static let placeholder = DriftWidgetSnapshot(
    accountIdent: nil,
    recent: (1 ... 6).map {
      Item(
        id: "\($0)",
        kind: "album",
        title: String(localized: "Album \($0)", table: "Fork"),
        subtitle: String(localized: "Artist", table: "Fork"),
        artworkFile: nil
      )
    },
    favoriteSongCount: 128,
    nowPlayingTitle: nil,
    nowPlayingArtist: nil,
    isPlaying: false,
    accent: nil,
    updated: Date()
  )

  var accentColor: Color {
    guard let accent, accent.count >= 3 else { return DriftWidgetStyle.defaultAccent }
    return Color(red: accent[0], green: accent[1], blue: accent[2])
  }
}

// MARK: - DriftWidgetStyle

enum DriftWidgetStyle {
  /// Drift is dark-first, `#121212` like the app's background.
  static let background = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
  static let surface = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255)
  static let defaultAccent = Color(red: 0.25, green: 0.52, blue: 0.96)
}

// MARK: - ArtworkView

struct ArtworkView: View {
  let snapshot: DriftWidgetSnapshot
  let item: DriftWidgetSnapshot.Item
  var cornerRadius: CGFloat = 6

  var body: some View {
    Group {
      if let url = snapshot.artworkURL(for: item),
         let image = UIImage(contentsOfFile: url.path) {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        ZStack {
          DriftWidgetStyle.surface
          Image(systemName: Self.symbol(for: item.kind))
            .font(.title3)
            .foregroundStyle(.white.opacity(0.5))
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(item.kind == "artist"
      ? AnyShape(Circle())
      : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
  }

  static func symbol(for kind: String) -> String {
    switch kind {
    case "artist": return "music.mic"
    case "playlist": return "music.note.list"
    default: return "square.stack"
    }
  }
}
