//
//  DriftControls.swift
//  DriftWidgets
//
//  Fork (F-14): Control Center (and Lock Screen / Action button) controls. "Shuffle Favorites"
//  starts the favorites, "Drift" toggles play/pause and shows the current song.
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

// MARK: - ShuffleFavoritesControl

struct ShuffleFavoritesControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: DriftWidgetKind.controlShuffleFavorites) {
      ControlWidgetButton(action: DriftShuffleFavoritesIntent()) {
        Label("Shuffle Favorites", systemImage: "shuffle")
      }
    }
    .displayName("Shuffle Favorites")
    .description("Plays your favorite songs in Drift in random order.")
  }
}

// MARK: - PlayPauseControl

struct PlayPauseControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(
      kind: DriftWidgetKind.controlPlayPause,
      provider: PlaybackStateProvider()
    ) { state in
      ControlWidgetToggle(isOn: state.isPlaying, action: DriftPlayPauseIntent()) {
        Text(state.title)
      } valueLabel: { isOn in
        Label(isOn ? "Playing" : "Paused", systemImage: isOn ? "pause.fill" : "play.fill")
      }
    }
    .displayName("Play/Pause Drift")
    .description("Pauses or continues playback in Drift.")
  }
}

// MARK: - PlaybackStateProvider

struct PlaybackStateProvider: ControlValueProvider {
  struct State: Sendable {
    let isPlaying: Bool
    let title: String
  }

  var previewValue: State { State(isPlaying: false, title: "Drift") }

  func currentValue() async throws -> State {
    let snapshot = DriftWidgetSnapshot.read()
    return State(isPlaying: snapshot.isPlaying, title: snapshot.nowPlayingTitle ?? "Drift")
  }
}
