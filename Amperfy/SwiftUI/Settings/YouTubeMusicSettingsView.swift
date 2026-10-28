//
//  YouTubeMusicSettingsView.swift
//  Amperfy
//
//  Fork: settings of the YouTube Music integration (design phase 5, roadmap 3).
//  Songpicker URL, YouTube Music on/off and an optional own proxy URL. Stored in UserSettings
//  and taken over by SongpickerConfig right away.
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
import SwiftUI

// MARK: - YouTubeMusicSettingsView

struct YouTubeMusicSettingsView: View {
  private enum ConnectionState: Equatable {
    case idle
    case testing
    case ok(jobCount: Int)
    case failed(String)
  }

  @State
  private var isEnabled = true
  @State
  private var songpickerURLInput = ""
  @State
  private var isCustomProxy = false
  @State
  private var proxyURLInput = ""
  @State
  private var songpickerURLError: String?
  @State
  private var proxyURLError: String?
  @State
  private var connection = ConnectionState.idle

  private var defaultURLText: String { SongpickerConfig.defaultBaseURL.absoluteString }

  var body: some View {
    SettingsList {
      SettingsSection(
        content: {
          SettingsCheckBoxRow(title: "YouTube Music", isOn: $isEnabled)
        },
        footer: "Shows YouTube Music results in Search and the download overview in Library."
      )

      SettingsSection(
        content: {
          SettingsRow(title: "Songpicker URL", orientation: .vertical) {
            TextField(defaultURLText, text: $songpickerURLInput)
              .keyboardType(.URL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .textContentType(.URL)
              .submitLabel(.done)
              .onSubmit(saveSongpickerURL)
              .foregroundColor(.secondary)
          }
          SettingsButtonRow(title: "Test Connection", action: testConnection)
            .disabled(connection == .testing)
          if songpickerURLInput != defaultURLText {
            SettingsButtonRow(title: "Reset to Default") {
              songpickerURLInput = defaultURLText
              saveSongpickerURL()
            }
          }
        },
        footer: songpickerFooter,
        header: "Songpicker"
      )

      SettingsSection(
        content: {
          SettingsCheckBoxRow(title: "Custom Proxy URL", isOn: $isCustomProxy)
          if isCustomProxy {
            SettingsRow(title: "Proxy URL", orientation: .vertical) {
              TextField("https://music.example.com", text: $proxyURLInput)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .submitLabel(.done)
                .onSubmit(saveProxyURL)
                .foregroundColor(.secondary)
            }
          }
        },
        footer: proxyFooter,
        header: "Playback Proxy"
      )
    }
    .navigationTitle("YouTube Music")
    .onAppear(perform: load)
    .onDisappear {
      saveSongpickerURL()
      saveProxyURL()
    }
    .onChange(of: isEnabled) { _, newValue in
      update { $0.isYouTubeMusicEnabled = newValue }
    }
    .onChange(of: isCustomProxy) { _, newValue in
      if newValue {
        saveProxyURL()
      } else {
        proxyURLError = nil
        update { $0.songpickerProxyURL = nil }
      }
    }
  }

  private var songpickerFooter: String {
    if let songpickerURLError { return songpickerURLError }
    switch connection {
    case .idle:
      return "Search and downloads go to this address. Default: \(defaultURLText)"
    case .testing:
      return "Connecting…"
    case let .ok(jobCount):
      return "Connected. The Songpicker knows \(jobCount) download\(jobCount == 1 ? "" : "s")."
    case let .failed(message):
      return "Not reachable: \(message)"
    }
  }

  private var proxyFooter: String {
    if let proxyURLError { return proxyURLError }
    return isCustomProxy
      ? "Songs from YouTube Music play through this address, followed by /rest/stream.view."
      : "Songs from YouTube Music play through port \(SongpickerConfig.proxyPort) on the host of your account."
  }

  private func load() {
    let user = appDelegate.storage.settings.user
    isEnabled = user.isYouTubeMusicEnabled
    songpickerURLInput = user.songpickerURL.absoluteString
    isCustomProxy = user.songpickerProxyURL != nil
    proxyURLInput = user.songpickerProxyURL?.absoluteString ?? ""
  }

  private func update(_ change: (inout UserSettings) -> ()) {
    var user = appDelegate.storage.settings.user
    change(&user)
    appDelegate.storage.settings.user = user
    SongpickerConfig.apply(user)
  }

  private func saveSongpickerURL() {
    let text = songpickerURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = text.isEmpty ? SongpickerConfig.defaultBaseURL : SongpickerConfig.normalizedURL(from: text)
    guard let url else {
      songpickerURLError = "Please enter an address like \(defaultURLText)."
      return
    }
    songpickerURLError = nil
    songpickerURLInput = url.absoluteString
    if url != appDelegate.storage.settings.user.songpickerURL {
      connection = .idle
      update { $0.songpickerURL = url }
    }
  }

  private func saveProxyURL() {
    guard isCustomProxy else { return }
    let text = proxyURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    // an empty field keeps the switch on until an address is typed
    guard !text.isEmpty else {
      proxyURLError = nil
      update { $0.songpickerProxyURL = nil }
      return
    }
    guard let url = SongpickerConfig.normalizedURL(from: text) else {
      proxyURLError = "Please enter an address like https://music.example.com."
      return
    }
    proxyURLError = nil
    proxyURLInput = url.absoluteString
    update { $0.songpickerProxyURL = url }
  }

  private func testConnection() {
    saveSongpickerURL()
    guard songpickerURLError == nil else { return }
    connection = .testing
    Task { @MainActor in
      do {
        let jobs = try await SongpickerClient.shared.jobs()
        connection = .ok(jobCount: jobs.count)
      } catch {
        connection = .failed(error.localizedDescription)
      }
    }
  }
}
