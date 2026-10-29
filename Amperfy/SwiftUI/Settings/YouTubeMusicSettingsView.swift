//
//  YouTubeMusicSettingsView.swift
//  Amperfy
//
//  Fork: settings of the YouTube Music integration (design phase 5, roadmap 3).
//  YouTube Music on/off, a connection test against the proxy and an optional own proxy URL. Stored in UserSettings
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
  private var isCustomProxy = false
  @State
  private var proxyURLInput = ""
  @State
  private var proxyURLError: String?
  @State
  private var connection = ConnectionState.idle

  var body: some View {
    SettingsList {
      SettingsSection(
        content: {
          SettingsCheckBoxRow(title: "YouTube Music", isOn: $isEnabled)
        },
        footer: String(localized: "Shows YouTube Music results in Search and the download overview in Library.", table: "Fork")
      )

      SettingsSection(
        content: {
          SettingsButtonRow(title: String(localized: "Test Connection", table: "Fork"), action: testConnection)
            .disabled(connection == .testing)
        },
        footer: connectionFooter,
        header: String(localized: "Server", table: "Fork")
      )

      SettingsSection(
        content: {
          SettingsCheckBoxRow(title: String(localized: "Custom Proxy URL", table: "Fork"), isOn: $isCustomProxy)
          if isCustomProxy {
            SettingsRow(title: String(localized: "Proxy URL", table: "Fork"), orientation: .vertical) {
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
        header: String(localized: "Playback Proxy", table: "Fork")
      )
    }
    .navigationTitle("YouTube Music")
    .onAppear(perform: load)
    .onDisappear(perform: saveProxyURL)
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

  private var connectionFooter: String {
    switch connection {
    case .idle:
      return String(localized: "Search, playback and downloads go through the server of your account. It needs the YouTube Music proxy in front of Navidrome.", table: "Fork")
    case .testing:
      return String(localized: "Connecting…", table: "Fork")
    case let .ok(jobCount):
      return jobCount == 1
        ? String(localized: "Connected. The proxy lists 1 download of this account.", table: "Fork")
        : String(localized: "Connected. The proxy lists \(jobCount) downloads of this account.", table: "Fork")
    case let .failed(message):
      return String(localized: "Not available: \(message)", table: "Fork")
    }
  }

  private var proxyFooter: String {
    if let proxyURLError { return proxyURLError }
    return isCustomProxy
      ? String(localized: "Songs from YouTube Music play through this address, followed by /rest/stream.view.", table: "Fork")
      : String(localized: "Songs from YouTube Music play through the server of your account. If it points to Navidrome directly (port \(SongpickerConfig.navidromePort)), port \(SongpickerConfig.proxyPort) of the same host is used.", table: "Fork")
  }

  private func load() {
    let user = appDelegate.storage.settings.user
    isEnabled = user.isYouTubeMusicEnabled
    isCustomProxy = user.songpickerProxyURL != nil
    proxyURLInput = user.songpickerProxyURL?.absoluteString ?? ""
  }

  private func update(_ change: (inout UserSettings) -> ()) {
    var user = appDelegate.storage.settings.user
    change(&user)
    appDelegate.storage.settings.user = user
    SongpickerConfig.apply(user)
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
      proxyURLError = String(localized: "Please enter an address like https://music.example.com.", table: "Fork")
      return
    }
    proxyURLError = nil
    proxyURLInput = url.absoluteString
    update { $0.songpickerProxyURL = url }
  }

  private func testConnection() {
    saveProxyURL()
    connection = .testing
    if let accountInfo = appDelegate.storage.settings.accounts.active {
      YouTubeMusicJobMonitor.shared.configure(backendApi: appDelegate.getMeta(accountInfo).backendApi)
    }
    Task { @MainActor in
      do {
        let jobCount = try await YouTubeMusicJobMonitor.shared.testConnection()
        connection = .ok(jobCount: jobCount)
      } catch {
        connection = .failed(error.localizedDescription)
      }
    }
  }
}
