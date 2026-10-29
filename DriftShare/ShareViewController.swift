//
//  ShareViewController.swift
//  DriftShare
//
//  Fork (F-9): "Share → Drift" for links from YouTube Music, YouTube and Safari. Reads the video
//  ID and starts the download like the app does: `stream.view?id=ytm-<videoId>&format=mp3` at
//  the Subsonic proxy of the login host, read until the first audio byte (about 9 s), the proxy
//  then keeps loading on its own and puts the song into the library.
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
import UIKit
import UniformTypeIdentifiers

// MARK: - ShareViewController

@objc(ShareViewController)
final class ShareViewController: UIViewController {
  private let model = ShareModel()
  private var task: Task<(), Never>?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
      self?.close()
    })
    host.view.backgroundColor = .clear
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    host.didMove(toParent: self)

    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    task = Task { @MainActor in
      await self.model.run(items: items)
      if case .added = self.model.state {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        self.close()
      }
    }
  }

  private func close() {
    task?.cancel()
    extensionContext?.completeRequest(returningItems: nil)
  }
}

// MARK: - ShareModel

@MainActor
@Observable
final class ShareModel {
  enum State {
    case reading
    case adding(server: String)
    case added
    case failed(String)
  }

  var state = State.reading
  /// Text that came with the link, e.g. the song title from YouTube Music.
  var sharedText: String?

  func run(items: [NSExtensionItem]) async {
    sharedText = items.compactMap { $0.attributedContentText?.string }
      .first { !$0.isEmpty && YouTubeShareLink.videoId(fromText: $0) == nil }
    guard let videoId = await Self.videoId(in: items) else {
      state = .failed(String(localized: "No YouTube or YouTube Music link found.", table: "Fork"))
      return
    }
    guard let config = DriftShareConfig.load(), let url = config.streamURL(videoId: videoId) else {
      state = .failed(String(localized: "Open Drift once with your server account, then try again.", table: "Fork"))
      return
    }
    state = .adding(server: config.serverName)
    do {
      try await Self.startDownload(url: url, headers: config.headers)
      state = .added
    } catch is CancellationError {
      return
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  /// Same as `BackendProxy.forkStartYouTubeDownload`: wait for the first audio byte.
  private static func startDownload(url: URL, headers: [String: String]) async throws {
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw ShareError.invalidResponse }
    guard (200 ..< 300).contains(http.statusCode) else { throw ShareError.status(http.statusCode) }
    // Subsonic errors come as XML/JSON with status 200
    guard http.mimeType?.hasPrefix("audio/") ?? true else { throw ShareError.invalidResponse }
    for try await _ in bytes {
      break
    }
  }

  private static func videoId(in items: [NSExtensionItem]) async -> String? {
    let providers = items.flatMap { $0.attachments ?? [] }
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
         let id = YouTubeShareLink.videoId(from: url) {
        return id
      }
    }
    for provider in providers
      where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        as? String, let id = YouTubeShareLink.videoId(fromText: text) {
        return id
      }
    }
    for item in items {
      if let text = item.attributedContentText?.string,
         let id = YouTubeShareLink.videoId(fromText: text) {
        return id
      }
    }
    return nil
  }
}

// MARK: - ShareError

enum ShareError: LocalizedError {
  case invalidResponse
  case status(Int)

  var errorDescription: String? {
    switch self {
    case .invalidResponse: return String(localized: "The server did not start the download.", table: "Fork")
    case let .status(code): return String(localized: "The server answered with status \(code).", table: "Fork")
    }
  }
}

// MARK: - ShareView

struct ShareView: View {
  let model: ShareModel
  let close: () -> ()

  var body: some View {
    VStack {
      Spacer()
      VStack(spacing: 14) {
        icon
          .frame(height: 44)
        Text(title)
          .font(.title3.weight(.bold))
          .multilineTextAlignment(.center)
        if let detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
        }
        Button(action: close) {
          Text(buttonTitle)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
      }
      .padding(24)
      .frame(maxWidth: 420)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .padding(16)
    }
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder
  private var icon: some View {
    switch model.state {
    case .reading, .adding:
      ProgressView()
        .controlSize(.large)
    case .added:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 40))
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 36))
        .foregroundStyle(.yellow)
    }
  }

  private var title: String {
    switch model.state {
    case .reading: return "Drift"
    case .adding: return String(localized: "Adding to Drift…", table: "Fork")
    case .added: return String(localized: "Added to Drift", table: "Fork")
    case .failed: return String(localized: "Not Added", table: "Fork")
    }
  }

  private var detail: String? {
    switch model.state {
    case .reading:
      return nil
    case let .adding(server):
      let song = model.sharedText.map { "\($0)\n" } ?? ""
      return String(localized: "\(song)Starting the download on \(server), this takes about 10 seconds.", table: "Fork")
    case .added:
      return String(localized: "The song will appear in your library in a minute.", table: "Fork")
    case let .failed(message):
      return message
    }
  }

  private var buttonTitle: String {
    switch model.state {
    case .added, .failed: return String(localized: "Done", table: "Fork")
    default: return String(localized: "Cancel", table: "Fork")
    }
  }
}
