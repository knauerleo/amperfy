//
//  DownloadJobCell.swift
//  Amperfy
//
//  Fork: one Songpicker job in the download overview of the Library (design phase 5).
//  Cover from the YouTube result, title, state and the same SourceBadgeView as in the search.
//  Failed jobs get a "Retry" button.
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

final class DownloadJobCell: UICollectionViewListCell {
  private(set) var videoId: String?
  private let badge = SourceBadgeView()
  private lazy var retryButton: UIButton = {
    var config = UIButton.Configuration.tinted()
    config.title = String(localized: "Retry", table: "Fork")
    config.buttonSize = .small
    config.cornerStyle = .capsule
    config.baseForegroundColor = .label
    config.baseBackgroundColor = .label
    let button = UIButton(configuration: config)
    button.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
    return button
  }()

  var onRetry: (() -> ())?
  private var thumbTask: Task<(), Never>?

  override func prepareForReuse() {
    super.prepareForReuse()
    thumbTask?.cancel()
    thumbTask = nil
    onRetry = nil
  }

  func display(entry: YouTubeMusicJobEntry) {
    videoId = entry.videoId

    var content = UIListContentConfiguration.subtitleCell()
    content.text = entry.title
    content.textProperties.font = DS.Font.cellTitle
    content.textProperties.numberOfLines = 1
    content.secondaryText = Self.detailText(for: entry)
    content.secondaryTextProperties.font = DS.Font.cellSubtitle
    content.secondaryTextProperties.color = entry.status == .failed ? .systemRed : .secondaryLabel
    content.secondaryTextProperties.numberOfLines = 2
    content.imageProperties.maximumSize = CGSize(width: 48, height: 48)
    content.imageProperties.reservedLayoutSize = CGSize(width: 48, height: 48)
    content.imageProperties.cornerRadius = DS.Radius.small
    let cached = entry.thumbURL.flatMap { JobThumbnailCache.shared.image(for: $0) }
    content.image = cached ?? Self.placeholder
    contentConfiguration = content

    badge.status = entry.status
    var accessories: [UICellAccessory] = []
    if entry.isRetryable {
      accessories.append(.customView(configuration: .init(
        customView: retryButton,
        placement: .trailing(),
        reservedLayoutWidth: .actual
      )))
    }
    accessories.append(.customView(configuration: .init(
      customView: badge,
      placement: .trailing(),
      reservedLayoutWidth: .custom(SourceBadgeView.size)
    )))
    self.accessories = accessories
    configureAccessibility(entry: entry)

    if cached == nil, let url = entry.thumbURL {
      thumbTask?.cancel()
      thumbTask = Task { @MainActor [weak self] in
        guard let image = await JobThumbnailCache.shared.load(url),
              !Task.isCancelled, let self, self.videoId == entry.videoId,
              var content = self.contentConfiguration as? UIListContentConfiguration
        else { return }
        content.image = image
        self.contentConfiguration = content
      }
    }
  }

  /// One element per job: title, artist and state; Retry as an action (UI-10).
  private func configureAccessibility(entry: YouTubeMusicJobEntry) {
    isAccessibilityElement = true
    accessibilityLabel = [entry.title, entry.artist].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: ", ")
    accessibilityValue = Self.detailText(for: entry, includeArtist: false)
    accessibilityTraits = entry.status.isLoading ? [.updatesFrequently] : []
    if entry.isRetryable {
      accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Retry", table: "Fork")) { [weak self] _ in
        self?.onRetry?()
        return true
      }]
    } else {
      accessibilityCustomActions = nil
    }
  }

  private static var placeholder: UIImage? {
    UIImage(systemName: "music.note")?.withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
  }

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  private static func detailText(
    for entry: YouTubeMusicJobEntry,
    includeArtist: Bool = true
  )
    -> String {
    let state: String
    switch entry.status {
    case .waiting: state = String(localized: "Waiting…", table: "Fork")
    case .downloading: state = String(localized: "Downloading…", table: "Fork")
    case .saving: state = String(localized: "Saving…", table: "Fork")
    case .inLibrary: state = String(localized: "In Library", table: "Fork")
    case .failed:
      state = entry.error.map { String(localized: "Failed: \($0)", table: "Fork") } ?? String(localized: "Failed", table: "Fork")
    case .online: state = String(localized: "Only on YouTube Music", table: "Fork")
    }
    var parts = [String]()
    if includeArtist, let artist = entry.artist, !artist.isEmpty { parts.append(artist) }
    parts.append(state)
    if !entry.status.isLoading, let started = entry.started {
      parts.append(relativeFormatter.localizedString(for: started, relativeTo: Date()))
    }
    return parts.joined(separator: " · ")
  }
}

// MARK: - JobThumbnailCache

/// Covers of YouTube results that are not in the library, only in memory.
@MainActor
final class JobThumbnailCache {
  static let shared = JobThumbnailCache()

  private let cache = NSCache<NSURL, UIImage>()
  private var running = [URL: Task<UIImage?, Never>]()

  func image(for url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  func load(_ url: URL) async -> UIImage? {
    if let image = image(for: url) { return image }
    if let task = running[url] { return await task.value }
    let task = Task<UIImage?, Never> {
      guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
      return await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: 144, height: 144))
    }
    running[url] = task
    let image = await task.value
    running.removeValue(forKey: url)
    if let image { cache.setObject(image, forKey: url as NSURL) }
    return image
  }
}
