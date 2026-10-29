//
//  YouTubeAlbumActions.swift
//  Amperfy
//
//  Fork (TASKS F-8): menu entries at YouTube Music results (search, F-5 shelf) to open the
//  album or the artist of the song on YouTube Music, or to download the whole album. Also
//  the cover cache for `ytm-album-…`/`ytm-artist-…` and the album download itself.
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

// MARK: - YouTubeAlbumActions

@MainActor
enum YouTubeAlbumActions {
  private static var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

  /// Albums and artists need the proxy, so they are only offered online.
  static var isAvailable: Bool {
    SongpickerConfig.isEnabled && appDelegate.storage.settings.user.isOnlineMode
  }

  /// The active account, the YouTube results always belong to it.
  static var activeAccount: Account? {
    guard let info = appDelegate.storage.settings.accounts.active else { return nil }
    return appDelegate.storage.main.library.getAccount(info: info)
  }

  /// "View Album", "View Artist", "Download Whole Album" for the song `ytm-<videoId>`.
  /// `host` is asked for the screen that pushes or presents when an entry is chosen.
  static func menu(
    videoId: String,
    host: @escaping () -> UIViewController?
  )
    -> UIMenu? {
    guard isAvailable, let account = activeAccount else { return nil }
    let songId = YouTubeMusic.playableId(videoId: videoId)
    let viewAlbum = UIAction(
      title: String(localized: "View Album", table: "Fork"),
      image: UIImage(systemName: "square.stack")
    ) { _ in
      push(YouTubeAlbumVC(account: account, albumId: songId), from: host())
    }
    let viewArtist = UIAction(
      title: String(localized: "View Artist", table: "Fork"),
      image: UIImage(systemName: "music.mic")
    ) { _ in
      push(YouTubeArtistVC(account: account, artistId: songId), from: host())
    }
    let download = UIAction(
      title: String(localized: "Download Whole Album", table: "Fork"),
      image: UIImage(systemName: "arrow.down.circle.dotted")
    ) { _ in
      guard let host = host() else { return }
      Task { @MainActor in
        await downloadAlbumWithAlert(account: account, id: songId, from: host)
      }
    }
    return UIMenu(options: .displayInline, children: [viewAlbum, viewArtist, download])
  }

  static func push(_ vc: UIViewController, from host: UIViewController?) {
    guard let host else { return }
    if let navigationController = host.navigationController ?? host as? UINavigationController {
      navigationController.pushViewController(vc, animated: true)
    } else {
      appDelegate.displayInLibraryTab(vc: vc)
    }
  }

  // MARK: Download

  /// Starts one job per missing song and follows them like a played result (F-6 sync, F-7
  /// notification). The proxy skips songs that are already in the library.
  static func downloadAlbum(account: Account, id: String) async throws -> YouTubeAlbumDownload {
    let backendApi = appDelegate.getMeta(account.info).backendApi
    let monitor = YouTubeMusicJobMonitor.shared
    monitor.configure(backendApi: backendApi)
    YouTubeMusicDownloadCoordinator.shared.start()
    let result = try await backendApi.forkDownloadYouTubeAlbum(id: id)
    for song in result.songs where !song.downloaded && song.status.isLoading {
      if let hit = song.hit(album: result.name) {
        monitor.track(hit)
      }
    }
    return result
  }

  /// From a menu: the download and its result as an alert, with a way to the album.
  private static func downloadAlbumWithAlert(
    account: Account,
    id: String,
    from host: UIViewController
  ) async {
    do {
      let result = try await downloadAlbum(account: account, id: id)
      DS.haptic(.success)
      let alert = UIAlertController(
        title: result.name.isEmpty ? String(localized: "Downloading Album", table: "Fork") : result.name,
        message: summary(queued: result.queued, skipped: result.skipped),
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: String(localized: "View Album", table: "Fork"), style: .default) { _ in
        let albumId = result.albumId.isEmpty ? id : result.albumId
        push(YouTubeAlbumVC(account: account, albumId: albumId), from: host)
      })
      alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Fork"), style: .cancel))
      host.present(alert, animated: true)
    } catch {
      DS.haptic(.error)
      showError(error, title: String(localized: "Album Download Failed", table: "Fork"), from: host)
    }
  }

  static func showError(_ error: Error, title: String, from host: UIViewController) {
    let alert = UIAlertController(
      title: title,
      message: error.localizedDescription,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Fork"), style: .cancel))
    host.present(alert, animated: true)
  }

  /// "6 downloading, 9 already there", or that everything is in the library.
  static func summary(queued: Int, skipped: Int) -> String {
    guard queued > 0 else {
      return String(localized: "All songs are already in your library", table: "Fork")
    }
    let loading = queued == 1
      ? String(localized: "1 downloading", table: "Fork")
      : String(localized: "\(queued) downloading", table: "Fork")
    guard skipped > 0 else { return loading }
    return loading + ", " + String(localized: "\(skipped) already there", table: "Fork")
  }

  // MARK: Texts

  static func kindName(_ kind: YouTubeAlbumKind) -> String {
    switch kind {
    case .album: return String(localized: "Album", table: "Fork")
    case .single: return String(localized: "Single", table: "Fork")
    case .ep: return String(localized: "EP", table: "Fork")
    }
  }

  static func songCount(_ count: Int) -> String {
    count == 1 ? String(localized: "1 Song", table: "Fork") : String(localized: "\(count) Songs", table: "Fork")
  }
}

// MARK: - YouTubeCoverCache

/// Covers of YouTube albums and artists from `getCoverArt` at the proxy, kept in memory.
@MainActor
final class YouTubeCoverCache {
  static let shared = YouTubeCoverCache()

  private let cache = NSCache<NSString, UIImage>()
  /// IDs the proxy has no cover for (404).
  private var missing = Set<String>()
  private var running = [String: Task<(image: UIImage?, isMissing: Bool), Never>]()

  private init() {
    cache.countLimit = 200
  }

  func cachedImage(id: String) -> UIImage? {
    cache.object(forKey: id as NSString)
  }

  /// The cover of `id` (`ytm-album-…`/`ytm-artist-…`), or the image at `fallbackURL`.
  func image(id: String?, fallbackURL: URL? = nil, account: Account) async -> UIImage? {
    let key = id ?? fallbackURL?.absoluteString
    guard let key else { return nil }
    if let image = cache.object(forKey: key as NSString) { return image }
    if missing.contains(key) { return nil }
    if let task = running[key] { return await task.value.image }
    let backendApi = (UIApplication.shared.delegate as! AppDelegate).getMeta(account.info).backendApi
    let task = Task<(image: UIImage?, isMissing: Bool), Never> {
      var data: Data?
      var isMissing = false
      if let id {
        do {
          data = try await backendApi.forkYouTubeCoverArt(id: id)
          // 404: the proxy has no cover, asking again would not change that
          isMissing = data == nil && fallbackURL == nil
        } catch {
          data = nil
        }
      }
      if data == nil, let fallbackURL {
        data = try? await URLSession.shared.data(from: fallbackURL).0
      }
      guard let data else { return (nil, isMissing) }
      let image = await Task.detached {
        UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
      }.value
      return (image, image == nil)
    }
    running[key] = task
    let result = await task.value
    running.removeValue(forKey: key)
    if let image = result.image {
      cache.setObject(image, forKey: key as NSString)
    } else if result.isMissing {
      missing.insert(key)
    }
    return result.image
  }
}

// MARK: - UIView

extension UIView {
  /// The view controller that shows this view, e.g. to push from a shelf.
  var forkHostViewController: UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let vc = current as? UIViewController { return vc }
      responder = current.next
    }
    return nil
  }
}
