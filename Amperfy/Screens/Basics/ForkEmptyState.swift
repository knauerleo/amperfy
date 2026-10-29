//
//  ForkEmptyState.swift
//  Amperfy
//
//  Fork: empty states with an action for the remaining library lists (UI-17), like the empty
//  state of Home: favorites ("Sync Favorites"), playlists ("New Playlist"), downloads
//  ("Download Favorite Songs") and podcasts ("Refresh"). The texts stay English like the rest
//  of the app. Buttons that need the server only show up in online mode.
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

@MainActor
enum ForkEmptyState {
  private static var appDelegate: AppDelegate { UIApplication.shared.delegate as! AppDelegate }
  private static var isOnline: Bool { appDelegate.storage.settings.user.isOnlineMode }

  // MARK: - Favorites

  enum FavoriteKind {
    case songs, albums, artists

    var title: String {
      switch self {
      case .songs: "No Favorite Songs"
      case .albums: "No Favorite Albums"
      case .artists: "No Favorite Artists"
      }
    }

    var hint: String {
      switch self {
      case .songs: "Tap ♥ on a song and it shows up here."
      case .albums: "Tap ♥ on an album and it shows up here."
      case .artists: "Tap ♥ on an artist and it shows up here."
      }
    }
  }

  /// "Sync Favorites" fetches the favorites from the server, e.g. ones set in another app.
  static func favorites(
    _ kind: FavoriteKind,
    account: Account,
    in viewController: UIViewController,
    onFinished: @escaping () -> ()
  )
    -> UIContentUnavailableConfiguration {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .heartEmpty
    config.text = kind.title
    config.secondaryText = kind.hint
    guard isOnline else { return config }
    config.button = .filled()
    config.button.title = "Sync Favorites"
    config.buttonProperties.primaryAction = UIAction { [weak viewController] _ in
      guard let viewController else { return }
      runWithSpinner(in: viewController, onFinished: onFinished) {
        do {
          try await appDelegate.getMeta(account.info).librarySyncer.syncFavoriteLibraryElements()
        } catch {
          appDelegate.eventLogger.report(topic: "Favorites Sync", error: error)
        }
      }
    }
    return config
  }

  // MARK: - Playlists

  /// "New Playlist" asks for a name, creates the playlist on the server and opens it.
  static func playlists(account: Account, in viewController: UIViewController)
    -> UIContentUnavailableConfiguration {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .playlist
    config.text = "No Playlists"
    guard isOnline else {
      config.secondaryText = "Playlists from your server show up here. New playlists need online mode."
      return config
    }
    config.secondaryText = "Create a playlist, then add songs from any list or from the player."
    config.button = .filled()
    config.button.title = "New Playlist"
    config.buttonProperties.primaryAction = UIAction { [weak viewController] _ in
      guard let viewController else { return }
      presentNewPlaylistAlert(account: account, in: viewController)
    }
    return config
  }

  private static func presentNewPlaylistAlert(account: Account, in viewController: UIViewController) {
    let alert = UIAlertController(title: "New Playlist", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "Name"
      textField.autocapitalizationType = .sentences
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak viewController, weak alert] _ in
      let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty, let viewController else { return }
      createPlaylist(name: name, account: account, in: viewController)
    })
    viewController.present(alert, animated: true)
  }

  /// Same steps as `NewPlaylistTableHeader`, plus the upload so the playlist exists on the server.
  private static func createPlaylist(name: String, account: Account, in viewController: UIViewController) {
    let library = appDelegate.storage.main.library
    let playlist = library.createPlaylist(account: account)
    playlist.name = name
    appDelegate.storage.main.saveContext()
    DS.haptic(.success)
    Task { @MainActor in
      do {
        try await appDelegate.getMeta(account.info).librarySyncer
          .syncUpload(playlistToUpdateName: playlist)
      } catch {
        appDelegate.eventLogger.report(topic: "Playlist Upload", error: error)
      }
    }
    viewController.navigationController?.pushViewController(
      AppStoryboard.Main.segueToPlaylistDetail(account: account, playlist: playlist),
      animated: true
    )
  }

  // MARK: - Downloads

  /// "Download Favorite Songs" when there are favorites that are not on the device yet.
  static func downloads(account: Account, in viewController: UIViewController)
    -> UIContentUnavailableConfiguration {
    var config = UIContentUnavailableConfiguration.empty()
    config.image = .download
    config.text = "No Downloads"
    config.secondaryText = "Download albums, playlists or songs to listen without a connection."
    guard isOnline else { return config }
    let favorites = appDelegate.storage.main.library.getFavoriteSongs(for: account)
      .filter { !$0.isCached }
    guard !favorites.isEmpty else { return config }
    config.button = .filled()
    config.button.title = "Download Favorite Songs"
    config.buttonProperties.primaryAction = UIAction { [weak viewController] _ in
      guard let viewController else { return }
      downloadFavorites(account: account, in: viewController)
    }
    return config
  }

  private static func downloadFavorites(account: Account, in viewController: UIViewController) {
    let songs = appDelegate.storage.main.library.getFavoriteSongs(for: account)
      .filter { !$0.isCached }
    guard !songs.isEmpty else { return }
    let download = {
      DS.haptic(.success)
      appDelegate.getMeta(account.info).playableDownloadManager.download(objects: songs)
    }
    guard songs.count > AppDelegate.maxPlayablesDownloadsToAddAtOnceWithoutWarning else {
      download()
      return
    }
    let alert = UIAlertController(
      title: "Many Songs",
      message: "Are you sure to add \(songs.count) favorite songs to the download queue?",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in download() })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    viewController.present(alert, animated: true)
  }

  // MARK: - Podcasts

  /// Adds "Refresh" to the podcast empty states: podcasts and newest episodes from the server.
  static func podcasts(
    _ base: UIContentUnavailableConfiguration,
    account: Account,
    in viewController: UIViewController,
    onFinished: @escaping () -> ()
  )
    -> UIContentUnavailableConfiguration {
    var config = base
    config.secondaryText = "Podcasts you subscribe to on your server show up here."
    guard isOnline else { return config }
    config.button = .filled()
    config.button.title = "Refresh"
    config.buttonProperties.primaryAction = UIAction { [weak viewController] _ in
      guard let viewController else { return }
      runWithSpinner(in: viewController, onFinished: onFinished) {
        let meta = appDelegate.getMeta(account.info)
        do {
          try await meta.librarySyncer.syncDownPodcastsWithoutEpisodes()
          _ = try await AutoDownloadLibrarySyncer(
            storage: appDelegate.storage,
            account: account,
            librarySyncer: meta.librarySyncer,
            playableDownloadManager: meta.playableDownloadManager
          )
          .syncNewestPodcastEpisodes()
        } catch {
          appDelegate.eventLogger.report(topic: "Podcasts Sync", error: error)
        }
      }
    }
    return config
  }

  // MARK: - Helper

  /// Shows a spinner in the button while `work` runs, `onFinished` rebuilds the empty state.
  private static func runWithSpinner(
    in viewController: UIViewController,
    onFinished: @escaping () -> (),
    work: @escaping @MainActor () async -> ()
  ) {
    if var config = viewController.contentUnavailableConfiguration as? UIContentUnavailableConfiguration {
      config.button.showsActivityIndicator = true
      config.buttonProperties.isEnabled = false
      viewController.contentUnavailableConfiguration = config
    }
    DS.haptic(.light)
    Task { @MainActor in
      await work()
      onFinished()
    }
  }
}

// MARK: - Hooks in the list screens

extension SongsVC {
  func forkEmptyContentConfig() -> UIContentUnavailableConfiguration? {
    guard displayFilter == .favorites else { return nil }
    return ForkEmptyState.favorites(.songs, account: account, in: self) { [weak self] in
      guard let self else { return }
      updateSearchResults(for: searchController)
    }
  }
}

extension ArtistsVC {
  func forkEmptyContentConfig() -> UIContentUnavailableConfiguration? {
    guard displayFilter == .favorites else { return nil }
    return ForkEmptyState.favorites(.artists, account: account, in: self) { [weak self] in
      guard let self else { return }
      updateSearchResults(for: searchController)
    }
  }
}

extension AlbumsCommonVCInteractions {
  func forkEmptyContentConfig() -> UIContentUnavailableConfiguration? {
    guard displayFilter == .favorites, let rootVC else { return nil }
    return ForkEmptyState.favorites(.albums, account: account, in: rootVC) { [weak self] in
      self?.updateSearchResultsCB?()
      self?.updateContentUnavailable()
    }
  }
}

extension PlaylistsVC {
  func forkEmptyContentConfig() -> UIContentUnavailableConfiguration {
    ForkEmptyState.playlists(account: account, in: self)
  }
}

extension PodcastsVC {
  func forkEmptyContentConfig(_ base: UIContentUnavailableConfiguration)
    -> UIContentUnavailableConfiguration {
    ForkEmptyState.podcasts(base, account: account, in: self) { [weak self] in
      self?.updateContentUnavailable()
    }
  }
}

extension DownloadsVC {
  /// DownloadsVC had no empty state: "No Downloads" plus the list updates while downloads change.
  func forkInstallEmptyState() {
    resultUpdateHandler?.changesDidEnd = { [weak self] in
      self?.forkUpdateEmptyState()
    }
  }

  func forkUpdateEmptyState() {
    let isEmpty = singleFetchedResultsController?.fetchedObjects?.isEmpty ?? true
    contentUnavailableConfiguration = isEmpty ? ForkEmptyState.downloads(account: account, in: self) : nil
  }
}
