//
//  RecentWidget.swift
//  DriftWidgets
//
//  Fork (F-14): "Recently Played" like the Home section. A tap on a cover plays the album,
//  artist or playlist in the app without opening it.
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

// MARK: - RecentWidget

struct RecentWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: DriftWidgetKind.recent, provider: DriftSnapshotProvider()) { entry in
      RecentWidgetView(entry: entry)
        .containerBackground(DriftWidgetStyle.background, for: .widget)
    }
    .configurationDisplayName(String(localized: "Recently Played", table: "Fork"))
    .description(String(localized: "Play what you listened to last.", table: "Fork"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

// MARK: - RecentWidgetView

struct RecentWidgetView: View {
  @Environment(\.widgetFamily)
  private var family
  let entry: DriftWidgetEntry

  private var items: [DriftWidgetSnapshot.Item] { entry.snapshot.recent }

  var body: some View {
    if items.isEmpty {
      VStack(spacing: 6) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.title2)
        Text(String(localized: "Play something in Drift and it shows up here.", table: "Fork"))
          .font(.caption)
          .multilineTextAlignment(.center)
      }
      .foregroundStyle(.white.opacity(0.6))
    } else {
      switch family {
      case .systemSmall:
        small(items[0])
      case .systemLarge:
        VStack(alignment: .leading, spacing: 10) {
          header
          grid(Array(items.prefix(6)), columns: 3)
        }
      default:
        VStack(alignment: .leading, spacing: 8) {
          header
          grid(Array(items.prefix(4)), columns: 4)
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "waveform")
        .foregroundStyle(entry.snapshot.accentColor)
      Text(String(localized: "Recently Played", table: "Fork"))
        .foregroundStyle(.white)
    }
    .font(.subheadline.weight(.bold))
  }

  private func small(_ item: DriftWidgetSnapshot.Item) -> some View {
    Button(intent: DriftPlayRecentIntent(itemId: item.id, kind: item.kind)) {
      VStack(alignment: .leading, spacing: 4) {
        ZStack(alignment: .bottomTrailing) {
          ArtworkView(snapshot: entry.snapshot, item: item, cornerRadius: 8)
          Image(systemName: "play.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, entry.snapshot.accentColor)
            .padding(4)
        }
        Text(item.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
  }

  private func grid(_ items: [DriftWidgetSnapshot.Item], columns: Int) -> some View {
    let rows = stride(from: 0, to: items.count, by: columns).map {
      Array(items[$0 ..< min($0 + columns, items.count)])
    }
    return VStack(alignment: .leading, spacing: 10) {
      ForEach(rows.indices, id: \.self) { index in
        HStack(alignment: .top, spacing: 10) {
          ForEach(rows[index]) { item in
            tile(item, showSubtitle: family == .systemLarge)
          }
          // keep the tile width when the last row is short
          ForEach(0 ..< (columns - rows[index].count), id: \.self) { _ in
            Color.clear.frame(maxWidth: .infinity)
          }
        }
      }
    }
  }

  private func tile(_ item: DriftWidgetSnapshot.Item, showSubtitle: Bool) -> some View {
    Button(intent: DriftPlayRecentIntent(itemId: item.id, kind: item.kind)) {
      VStack(alignment: .leading, spacing: 3) {
        ArtworkView(snapshot: entry.snapshot, item: item)
        Text(item.title)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if showSubtitle {
          Text(item.subtitle)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}
