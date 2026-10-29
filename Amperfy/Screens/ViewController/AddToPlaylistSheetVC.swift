//
//  AddToPlaylistSheetVC.swift
//  Amperfy
//
//  Fork: slim "Add to Playlist" sheet (UI-5). Half-height sheet with a grabber: "New Playlist" on top,
//  then the recently used playlists (latest change first), then the rest alphabetically.
//  One tap adds the songs and closes the sheet. Duplicates get the same question as the original
//  `PlaylistSelectorVC`, which the Mac keeps.
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

// MARK: - AddToPlaylistSheetVC

class AddToPlaylistSheetVC: UITableViewController {
  private enum Section: Int, CaseIterable {
    case newPlaylist
    case recent
    case all
  }

  private static let recentCount = 4

  private let account: Account
  private let itemsToAdd: [Song]
  private var recent = [Playlist]()
  private var others = [Playlist]()
  private var searchText = ""
  private let searchController = UISearchController(searchResultsController: nil)

  init(account: Account, itemsToAdd: [Song]) {
    self.account = account
    self.itemsToAdd = itemsToAdd
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    appDelegate.userStatistics.visited(.playlistSelector)
    title = itemsToAdd.count > 1 ? "Add \(itemsToAdd.count) Songs" : "Add to Playlist"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { [weak self] _ in self?.close() }
    )

    searchController.obscuresBackgroundDuringPresentation = false
    searchController.searchResultsUpdater = self
    searchController.searchBar.placeholder = "Search Playlists"
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = true

    view.backgroundColor = DS.Color.background
    tableView.backgroundColor = DS.Color.background
    tableView.register(nibName: PlaylistTableCell.typeName)
    tableView.register(NewPlaylistRowCell.self, forCellReuseIdentifier: NewPlaylistRowCell.typeName)
    tableView.rowHeight = PlaylistTableCell.rowHeight
    tableView.sectionHeaderTopPadding = 0
    tableView.separatorStyle = .none

    if let sheet = navigationController?.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
      sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }
    reloadPlaylists()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    guard appDelegate.storage.settings.user.isOnlineMode else { return }
    Task { @MainActor in
      do {
        try await self.appDelegate.getMeta(self.account.info).librarySyncer
          .syncDownPlaylistsWithoutSongs()
      } catch {
        self.appDelegate.eventLogger.report(topic: "Playlists Sync", error: error)
      }
      self.reloadPlaylists()
    }
  }

  // MARK: - Data

  private func reloadPlaylists() {
    let all = appDelegate.storage.main.library.getPlaylists(for: account)
      .filter { !$0.isSmartPlaylist }
    let byName: (Playlist, Playlist) -> Bool = {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    if searchText.isEmpty {
      recent = Array(
        all.filter { $0.changeDate != nil }
          .sorted { ($0.changeDate ?? .distantPast) > ($1.changeDate ?? .distantPast) }
          .prefix(Self.recentCount)
      )
      let recentIds = Set(recent.map { $0.managedObject.objectID })
      others = all.filter { !recentIds.contains($0.managedObject.objectID) }.sorted(by: byName)
      // a short list needs no "recent" split
      if all.count <= Self.recentCount + 2 {
        recent = []
        others = all.sorted(by: byName)
      }
    } else {
      recent = []
      others = all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }.sorted(by: byName)
    }
    tableView.reloadData()
  }

  private func playlists(in section: Section) -> [Playlist] {
    switch section {
    case .newPlaylist: []
    case .recent: recent
    case .all: others
    }
  }

  // MARK: - Table

  override func numberOfSections(in tableView: UITableView) -> Int {
    Section.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let section = Section(rawValue: section) else { return 0 }
    switch section {
    case .newPlaylist: return searchText.isEmpty ? 1 : 0
    case .recent, .all: return playlists(in: section).count
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch Section(rawValue: section) {
    case .recent: recent.isEmpty ? nil : "Recent"
    case .all: recent.isEmpty || others.isEmpty ? nil : "All Playlists"
    default: nil
    }
  }

  override func tableView(
    _ tableView: UITableView,
    willDisplayHeaderView view: UIView,
    forSection section: Int
  ) {
    guard let header = view as? UITableViewHeaderFooterView else { return }
    var content = header.defaultContentConfiguration()
    content.text = self.tableView(tableView, titleForHeaderInSection: section)
    content.textProperties.font = DS.Font.rowTitle
    content.textProperties.color = .secondaryLabel
    content.directionalLayoutMargins.top = DS.Space.m
    header.contentConfiguration = content
    var background = UIBackgroundConfiguration.clear()
    background.backgroundColor = DS.Color.background
    header.backgroundConfiguration = background
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
    if section == .newPlaylist {
      return tableView.dequeueReusableCell(
        withIdentifier: NewPlaylistRowCell.typeName,
        for: indexPath
      )
    }
    let cell: PlaylistTableCell = dequeueCell(for: tableView, at: indexPath)
    cell.display(playlist: playlists(in: section)[indexPath.row], rootView: nil)
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard let section = Section(rawValue: indexPath.section) else { return }
    if section == .newPlaylist {
      askForNewPlaylistName()
    } else {
      select(playlist: playlists(in: section)[indexPath.row])
    }
  }

  // MARK: - Actions

  private func select(playlist: Playlist) {
    let itemsNotContained = playlist.notContaines(playables: itemsToAdd)
    guard itemsNotContained.count != itemsToAdd.count else {
      add(songs: itemsToAdd, to: playlist)
      return
    }
    let alert = UIAlertController(
      title: nil,
      message: "Some Songs are already in this Playlist.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Add Duplicates", style: .default) { _ in
      self.add(songs: self.itemsToAdd, to: playlist)
    })
    alert.addAction(UIAlertAction(title: "Skip Duplicates", style: .default) { _ in
      self.add(songs: Array(itemsNotContained).filterSongs(), to: playlist)
    })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
  }

  /// Same order as `PlaylistSelectorVC`: upload first, then the local copy.
  private func add(songs: [Song], to playlist: Playlist) {
    guard !songs.isEmpty else {
      close()
      return
    }
    Task { @MainActor in
      do {
        try await self.appDelegate.getMeta(self.account.info).librarySyncer
          .syncUpload(playlistToAddSongs: playlist, songs: songs)
        playlist.append(playables: songs)
      } catch {
        self.appDelegate.eventLogger.report(topic: "Playlist Add Songs", error: error)
      }
    }
    DS.haptic(.success)
    close()
  }

  private func askForNewPlaylistName() {
    let alert = UIAlertController(title: "New Playlist", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "Name"
      textField.autocapitalizationType = .sentences
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
      let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty, let self else { return }
      // Same steps as `NewPlaylistTableHeader`. The upload of the songs creates it on the server.
      let playlist = self.appDelegate.storage.main.library.createPlaylist(account: self.account)
      playlist.name = name
      self.appDelegate.storage.main.saveContext()
      self.add(songs: self.itemsToAdd, to: playlist)
    })
    present(alert, animated: true)
  }

  private func close() {
    searchController.isActive = false
    dismiss(animated: true)
  }
}

// MARK: UISearchResultsUpdating

extension AddToPlaylistSheetVC: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
    let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespaces) ?? ""
    guard text != searchText else { return }
    searchText = text
    reloadPlaylists()
  }
}

// MARK: - NewPlaylistRowCell

/// "New Playlist" in the size of a playlist row: plus on a rounded tile where the collage would be.
private class NewPlaylistRowCell: UITableViewCell {
  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear

    let tile = UIView()
    tile.backgroundColor = DS.Color.surfaceRaised
    tile.layer.cornerRadius = DS.Radius.small
    let icon = UIImageView(image: .plus)
    icon.tintColor = .label
    icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
    icon.contentMode = .center
    let label = UILabel()
    label.text = "New Playlist"
    label.font = DS.Font.songTitle
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label

    for view in [tile, icon, label] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    contentView.addSubview(tile)
    tile.addSubview(icon)
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      // same position as the collage of `PlaylistTableCell`
      tile.leadingAnchor.constraint(
        equalTo: contentView.layoutMarginsGuide.leadingAnchor,
        constant: DS.Space.m
      ),
      tile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      tile.widthAnchor.constraint(equalToConstant: 56),
      tile.heightAnchor.constraint(equalToConstant: 56),
      icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
      label.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: DS.Space.xs),
      label.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
      label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
    accessibilityLabel = "New Playlist"
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var layoutMargins: UIEdgeInsets { get { BasicTableCell.margin } set {} }
}
