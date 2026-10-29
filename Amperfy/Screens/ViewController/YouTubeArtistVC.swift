//
//  YouTubeArtistVC.swift
//  Amperfy
//
//  Fork (TASKS F-8): an artist on YouTube Music (`getYtArtist`). Image, name, then the albums
//  in two sections, "Albums" and "Singles & EPs", newest first as the proxy sends them. A tap
//  opens the YouTube album. Uncached the proxy needs 3–5 s, skeleton rows show until then.
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

// MARK: - YouTubeArtistVC

final class YouTubeArtistVC: UITableViewController {
  private static let skeletonRows = 6
  private static let imageSize: CGFloat = 160

  private let account: Account
  /// `ytm-artist-…` or `ytm-<videoId>` (the artist of that song).
  private let artistId: String
  private var artist: YouTubeArtist?
  private var sections = [(title: String, albums: [YouTubeArtistAlbum])]()
  private var isLoading = false
  private var loadError: String?

  private let headerView = UIView()
  private let imageView = YouTubeArtworkView(cornerRadius: YouTubeArtistVC.imageSize / 2, symbol: "music.mic")
  private let imageSkeleton = SkeletonView(cornerRadius: YouTubeArtistVC.imageSize / 2)
  private let nameLabel = UILabel()
  private let nameSkeleton = SkeletonView()
  private let sourceLabel = UILabel()

  private var backendApi: BackendProxy { appDelegate.getMeta(account.info).backendApi }

  init(account: Account, artistId: String) {
    self.account = account
    self.artistId = artistId
    super.init(style: .plain)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// True if this screen shows the artist (by the ID it was opened with or the loaded one).
  func shows(artistId id: String) -> Bool {
    id == artistId || id == artist?.id
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.largeTitleDisplayMode = .never
    tableView.backgroundColor = ForkSurface.background
    tableView.separatorStyle = .none
    tableView.rowHeight = ForkRowMetrics.containerRowHeight
    tableView.sectionHeaderTopPadding = 0
    tableView.register(YouTubeArtistAlbumCell.self, forCellReuseIdentifier: YouTubeArtistAlbumCell.reuseID)
    tableView.register(
      YouTubeSectionHeaderView.self,
      forHeaderFooterViewReuseIdentifier: YouTubeSectionHeaderView.reuseID
    )
    setupHeader()
    load()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutHeader()
  }

  // MARK: Header

  private func setupHeader() {
    nameLabel.font = DS.Font.detailTitle
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.textColor = DS.Color.text
    nameLabel.textAlignment = .center
    nameLabel.numberOfLines = 2
    nameLabel.accessibilityTraits = .header

    sourceLabel.text = "YouTube Music"
    sourceLabel.font = DS.Font.caption
    sourceLabel.adjustsFontForContentSizeCategory = true
    sourceLabel.textColor = DS.Color.text3
    sourceLabel.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [imageView, sourceLabel, nameLabel])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = DS.Space.xxs
    stack.setCustomSpacing(DS.Space.m, after: imageView)
    stack.translatesAutoresizingMaskIntoConstraints = false
    headerView.addSubview(stack)
    headerView.addSubview(imageSkeleton)
    headerView.addSubview(nameSkeleton)
    NSLayoutConstraint.activate([
      imageView.widthAnchor.constraint(equalToConstant: Self.imageSize),
      imageView.heightAnchor.constraint(equalToConstant: Self.imageSize),
      nameLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
      nameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
      stack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: DS.Space.s),
      stack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: DS.Space.m),
      stack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -DS.Space.m),
      stack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -DS.Space.xs),
      imageSkeleton.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
      imageSkeleton.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
      imageSkeleton.widthAnchor.constraint(equalToConstant: Self.imageSize),
      imageSkeleton.heightAnchor.constraint(equalToConstant: Self.imageSize),
      nameSkeleton.centerXAnchor.constraint(equalTo: nameLabel.centerXAnchor),
      nameSkeleton.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
      nameSkeleton.widthAnchor.constraint(equalToConstant: 180),
      nameSkeleton.heightAnchor.constraint(equalToConstant: 24),
    ])
    tableView.tableHeaderView = headerView
    updateHeader()
  }

  private func updateHeader() {
    let isSkeleton = artist == nil && isLoading
    imageSkeleton.isHidden = !isSkeleton
    nameSkeleton.isHidden = !isSkeleton
    imageView.isHidden = isSkeleton
    nameLabel.text = artist?.name
    imageView.accessibilityLabel = artist?.name
    layoutHeader()
  }

  private func layoutHeader() {
    guard tableView.tableHeaderView === headerView else { return }
    let width = tableView.bounds.width
    guard width > 0 else { return }
    let size = headerView.systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    guard headerView.frame.size != CGSize(width: width, height: size.height) else { return }
    headerView.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
    tableView.tableHeaderView = headerView
  }

  // MARK: Loading

  private func load() {
    guard !isLoading else { return }
    guard appDelegate.storage.settings.user.isOnlineMode else {
      showUnavailable(text: String(localized: "YouTube Music is only available online.", table: "Fork"))
      return
    }
    isLoading = true
    loadError = nil
    contentUnavailableConfiguration = nil
    tableView.tableHeaderView = headerView
    updateHeader()
    tableView.reloadData()
    UIAccessibility.post(notification: .announcement, argument: String(localized: "Loading artist…", table: "Fork"))
    Task { @MainActor in
      do {
        let artist = try await backendApi.forkYouTubeArtist(id: artistId)
        self.artist = artist
        let albums = artist.albums.filter { !$0.kind.isSingleOrEP }
        let singles = artist.albums.filter(\.kind.isSingleOrEP)
        sections = []
        if !albums.isEmpty { sections.append((String(localized: "Albums", table: "Fork"), albums)) }
        if !singles.isEmpty { sections.append((String(localized: "Singles & EPs", table: "Fork"), singles)) }
        isLoading = false
        updateHeader()
        tableView.reloadData()
        loadImage(of: artist)
        if sections.isEmpty {
          var config = UIContentUnavailableConfiguration.empty()
          config.text = String(localized: "No Albums", table: "Fork")
          contentUnavailableConfiguration = config
        }
      } catch {
        isLoading = false
        loadError = error.localizedDescription
        tableView.reloadData()
        showUnavailable(text: error.localizedDescription)
      }
    }
  }

  private func loadImage(of artist: YouTubeArtist) {
    Task { @MainActor in
      let image = await YouTubeCoverCache.shared.image(
        id: artist.coverArt ?? artist.id,
        fallbackURL: artist.artistImageUrl,
        account: account
      )
      imageView.setImage(image, animated: true)
    }
  }

  private func showUnavailable(text: String) {
    tableView.tableHeaderView = nil
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: "exclamationmark.icloud")
    config.text = String(localized: "Artist Not Available", table: "Fork")
    config.secondaryText = text
    if appDelegate.storage.settings.user.isOnlineMode {
      var button = UIButton.Configuration.filled()
      button.title = String(localized: "Try Again", table: "Fork")
      button.baseBackgroundColor = DS.Color.surfaceRaised
      button.baseForegroundColor = DS.Color.text
      button.cornerStyle = .capsule
      config.button = button
      config.buttonProperties.primaryAction = UIAction { [weak self] _ in
        self?.load()
      }
    }
    contentUnavailableConfiguration = config
  }

  // MARK: UITableViewDataSource

  override func numberOfSections(in tableView: UITableView) -> Int {
    isLoading ? 1 : sections.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if isLoading { return Self.skeletonRows }
    return sections.indices.contains(section) ? sections[section].albums.count : 0
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(
      withIdentifier: YouTubeArtistAlbumCell.reuseID,
      for: indexPath
    ) as! YouTubeArtistAlbumCell
    guard !isLoading, let album = album(at: indexPath) else {
      cell.displaySkeleton()
      return cell
    }
    cell.display(album: album)
    if let coverId = cell.coverId, YouTubeCoverCache.shared.cachedImage(id: coverId) == nil {
      Task { @MainActor [weak cell, account] in
        let image = await YouTubeCoverCache.shared.image(id: coverId, account: account)
        cell?.setCover(image, for: coverId)
      }
    }
    return cell
  }

  private func album(at indexPath: IndexPath) -> YouTubeArtistAlbum? {
    guard sections.indices.contains(indexPath.section),
          sections[indexPath.section].albums.indices.contains(indexPath.row)
    else { return nil }
    return sections[indexPath.section].albums[indexPath.row]
  }

  // MARK: UITableViewDelegate

  override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    guard !isLoading, sections.indices.contains(section) else { return nil }
    let header = tableView.dequeueReusableHeaderFooterView(
      withIdentifier: YouTubeSectionHeaderView.reuseID
    ) as? YouTubeSectionHeaderView
    header?.display(title: sections[section].title)
    return header
  }

  override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    isLoading ? DS.Space.m : UITableView.automaticDimension
  }

  override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
    !isLoading
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !isLoading, let album = album(at: indexPath) else { return }
    navigationController?.pushViewController(
      YouTubeAlbumVC(account: account, albumId: album.id),
      animated: true
    )
  }
}
