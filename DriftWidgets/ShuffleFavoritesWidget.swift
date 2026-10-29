//
//  ShuffleFavoritesWidget.swift
//  DriftWidgets
//
//  Fork (F-14): one tap plays the favorite songs in random order, on the Home Screen and on
//  the Lock Screen.
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

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - ShuffleFavoritesWidget

struct ShuffleFavoritesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: DriftWidgetKind.shuffleFavorites,
      provider: DriftSnapshotProvider()
    ) { entry in
      ShuffleFavoritesWidgetView(entry: entry)
    }
    .configurationDisplayName(String(localized: "Shuffle Favorites", table: "Fork"))
    .description(String(localized: "Plays your favorite songs in random order.", table: "Fork"))
    .supportedFamilies([.systemSmall, .accessoryCircular])
  }
}

// MARK: - ShuffleFavoritesWidgetView

struct ShuffleFavoritesWidgetView: View {
  @Environment(\.widgetFamily)
  private var family
  let entry: DriftWidgetEntry

  var body: some View {
    if family == .accessoryCircular {
      Button(intent: DriftShuffleFavoritesIntent()) {
        ZStack {
          AccessoryWidgetBackground()
          Image(systemName: "shuffle")
            .font(.title3.weight(.semibold))
        }
      }
      .buttonStyle(.plain)
      .containerBackground(.clear, for: .widget)
    } else {
      Button(intent: DriftShuffleFavoritesIntent()) {
        VStack(alignment: .leading, spacing: 2) {
          Image(systemName: "shuffle")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.18), in: Circle())
          Spacer(minLength: 0)
          Text(String(localized: "Shuffle", table: "Fork"))
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .containerBackground(for: .widget) {
        LinearGradient(
          colors: [entry.snapshot.accentColor, entry.snapshot.accentColor.mix(with: .black, by: 0.6)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    }
  }

  private var subtitle: String {
    let count = entry.snapshot.favoriteSongCount
    switch count {
    case 0: return String(localized: "Favorites", table: "Fork")
    case 1: return String(localized: "Favorites · 1 song", table: "Fork")
    default: return String(localized: "Favorites · \(count) songs", table: "Fork")
    }
  }
}
