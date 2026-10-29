//
//  ArtistHighlightsView.swift
//  Amperfy
//
//  Fork: "Popular" (top songs by play count) and a horizontal discography shelf for the
//  artist page, shown inside the ImmersiveDetailHeaderView. Also starts an artist radio.
//  Biography and similar artists come from `getArtistInfo2` (F-3). "Popular" is filled up
//  with `getTopSongs` (Last.fm) while the own play counts give fewer than five songs (F-4).
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

final class ArtistHighlightsView: UIView {
  private static let popularCount = 5
  private static let rowHeight: CGFloat = 56
  private static let tileWidth: CGFloat = 140
  private static let similarArtistSize: CGFloat = 110
  private static let collapsedBioLines = 4

  private let artist: Artist
  private weak var rootView: UIViewController?
  private let stack = UIStackView()
  private var popularSongs: [AbstractPlayable] = []
  /// Library songs from `getTopSongs`, in Last.fm order.
  private var topSongs: [AbstractPlayable] = []
  private var albums: [Album] = []
  private var biography: String?
  private var similarArtists: [Artist] = []
  private var isBioExpanded = false

  /// Called when server data arrived later, so the header can update its height.
  var contentDidChange: (() -> ())?

  var hasContent: Bool {
    !popularSongs.isEmpty || !albums.isEmpty || biography != nil || !similarArtists.isEmpty
  }
  var hasAlbums: Bool { !albums.isEmpty }

  init(artist: Artist, rootView: UIViewController) {
    self.artist = artist
    self.rootView = rootView
    super.init(frame: .zero)
    stack.axis = .vertical
    stack.spacing = DS.Space.l
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    reload()
    loadArtistInfo()
    loadTopSongs()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Data

  /// Last.fm top songs that are in the library, once per page and only if they are needed.
  private func loadTopSongs() {
    guard popularSongs.count < Self.popularCount,
          appDelegate.storage.settings.user.isOnlineMode, let account = artist.account else { return }
    let artistName = artist.name
    Task { @MainActor in
      do {
        let ids = try await self.appDelegate.getMeta(account.info).backendApi
          .forkTopSongIds(artistName: artistName, count: 20)
        self.topSongs = ids.compactMap {
          self.appDelegate.storage.main.library.getSong(for: account, id: $0)
        }
        guard !self.topSongs.isEmpty else { return }
        self.reload()
        self.contentDidChange?()
      } catch {
        // without Last.fm "Popular" stays with the own play counts
      }
    }
  }

  /// Biography and similar artists of the library, once per page.
  private func loadArtistInfo() {
    guard appDelegate.storage.settings.user.isOnlineMode, let account = artist.account else { return }
    let artistId = artist.id
    Task { @MainActor in
      do {
        let info = try await self.appDelegate.getMeta(account.info).backendApi
          .forkArtistInfo(artistId: artistId)
        self.biography = info.biography
        self.similarArtists = info.similarArtistIds.compactMap {
          self.appDelegate.storage.main.library.getArtist(for: account, id: $0)
        }
        self.rebuild()
        self.contentDidChange?()
      } catch {
        // servers without getArtistInfo2 simply show no biography
      }
    }
  }

  func reload() {
    let isOffline = appDelegate.storage.settings.user.isOfflineMode
    popularSongs = Array(
      artist.songs
        .filter { $0.isSong && $0.playCount > 0 && (!isOffline || $0.isCached) }
        .sorted { $0.playCount > $1.playCount }
        .prefix(Self.popularCount)
    )
    let fillUp = topSongs.filter { top in
      (!isOffline || top.isCached) && !popularSongs.contains { $0.id == top.id }
    }
    popularSongs += fillUp.prefix(Self.popularCount - popularSongs.count)
    albums = artist.albums
      .filter { !isOffline || $0.isCached }
      .sorted { lhs, rhs in
        // newest first, albums without year at the end
        if lhs.year == rhs.year { return lhs.name < rhs.name }
        if lhs.year == 0 { return false }
        if rhs.year == 0 { return true }
        return lhs.year > rhs.year
      }
    rebuild()
  }

  private func rebuild() {
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if !popularSongs.isEmpty {
      let section = UIStackView()
      section.axis = .vertical
      section.addArrangedSubview(sectionTitle("Popular"))
      section.setCustomSpacing(DS.Space.xs, after: section.arrangedSubviews[0])
      for (index, song) in popularSongs.enumerated() {
        section.addArrangedSubview(PopularSongRow(
          index: index,
          song: song,
          theme: theme(for: song.account),
          target: self
        ))
      }
      stack.addArrangedSubview(section)
    }
    if !albums.isEmpty {
      let section = UIStackView()
      section.axis = .vertical
      section.spacing = DS.Space.s
      section.addArrangedSubview(sectionTitle("Discography"))
      section.addArrangedSubview(createDiscographyShelf())
      stack.addArrangedSubview(section)
    }
    if !similarArtists.isEmpty {
      let section = UIStackView()
      section.axis = .vertical
      section.spacing = DS.Space.s
      section.addArrangedSubview(sectionTitle("Fans Also Like"))
      section.addArrangedSubview(createSimilarArtistsShelf())
      stack.addArrangedSubview(section)
    }
    if let biography {
      let section = UIStackView()
      section.axis = .vertical
      section.spacing = DS.Space.xs
      section.addArrangedSubview(sectionTitle("About"))
      section.addArrangedSubview(createBiographyLabel(text: biography))
      stack.addArrangedSubview(section)
    }
  }

  private func createBiographyLabel(text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DS.Font.rowSubtitle
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.numberOfLines = isBioExpanded ? 0 : Self.collapsedBioLines
    label.isUserInteractionEnabled = true
    label.accessibilityTraits = .button
    label.accessibilityHint = isBioExpanded ? "Collapses the biography" : "Shows the whole biography"
    label.addGestureRecognizer(UITapGestureRecognizer(
      target: self,
      action: #selector(biographyTapped)
    ))
    return label
  }

  private func createSimilarArtistsShelf() -> UIView {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.clipsToBounds = false
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = DS.Space.m
    row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(row)
    for (index, similar) in similarArtists.enumerated() {
      let tile = ArtistCircleTile(
        artist: similar,
        theme: theme(for: similar.account),
        size: Self.similarArtistSize
      )
      tile.tag = index
      tile.addGestureRecognizer(UITapGestureRecognizer(
        target: self,
        action: #selector(similarArtistTapped(_:))
      ))
      row.addArrangedSubview(tile)
    }
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      scrollView.heightAnchor.constraint(equalToConstant: Self.similarArtistSize + 28),
    ])
    return scrollView
  }

  private func theme(for account: Account?) -> ThemePreference {
    appDelegate.storage.settings.accounts.getSetting(account?.info).read.themePreference
  }

  private func sectionTitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = DS.Font.sectionTitle
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label
    return label
  }

  private func createDiscographyShelf() -> UIView {
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.clipsToBounds = false
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = DS.Space.s
    row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(row)
    for (index, album) in albums.enumerated() {
      let tile = AlbumTile(album: album, theme: theme(for: album.account), width: Self.tileWidth)
      tile.tag = index
      tile.addGestureRecognizer(UITapGestureRecognizer(
        target: self,
        action: #selector(albumTapped(_:))
      ))
      row.addArrangedSubview(tile)
    }
    NSLayoutConstraint.activate([
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      scrollView.heightAnchor.constraint(equalToConstant: Self.tileWidth + 44),
    ])
    return scrollView
  }

  // MARK: - Actions

  fileprivate func playPopular(at index: Int) {
    DS.haptic(.light)
    appDelegate.player.play(context: PlayContext(
      name: "\(artist.name): Popular",
      index: index,
      playables: popularSongs
    ))
  }

  fileprivate func menu(forPopularAt index: Int) -> UIContextMenuConfiguration? {
    guard let rootView, popularSongs.indices.contains(index) else { return nil }
    let song = popularSongs[index]
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      EntityPreviewActionBuilder(container: song, on: rootView).createMenu()
    }
  }

  @objc
  private func albumTapped(_ recognizer: UITapGestureRecognizer) {
    guard let index = recognizer.view?.tag, albums.indices.contains(index),
          let account = albums[index].account,
          let navigationController = rootView?.navigationController else { return }
    navigationController.pushViewController(
      AppStoryboard.Main.segueToAlbumDetail(account: account, album: albums[index]),
      animated: true
    )
  }

  @objc
  private func biographyTapped() {
    DS.haptic(.light)
    isBioExpanded.toggle()
    rebuild()
    contentDidChange?()
  }

  @objc
  private func similarArtistTapped(_ recognizer: UITapGestureRecognizer) {
    guard let index = recognizer.view?.tag, similarArtists.indices.contains(index),
          let account = similarArtists[index].account,
          let navigationController = rootView?.navigationController else { return }
    navigationController.pushViewController(
      AppStoryboard.Main.segueToArtistDetail(account: account, artist: similarArtists[index]),
      animated: true
    )
  }

  /// Plays the artist's most played song followed by similar songs from the server.
  func playRadio() {
    let seed = popularSongs.first?.asSong ?? artist.songs.compactMap { $0.asSong }.randomElement()
    guard let seed, let account = seed.account else { return }
    Task { @MainActor in
      do {
        let similar = try await self.appDelegate.getMeta(account.info).librarySyncer
          .requestSimilarSongs(song: seed, count: 99)
        guard !similar.isEmpty else {
          self.appDelegate.eventLogger.info(
            topic: "Artist Radio",
            message: "No similar songs found",
            displayPopup: true
          )
          return
        }
        self.appDelegate.player.play(context: PlayContext(
          name: "\(self.artist.name) Radio",
          playables: [seed] + similar
        ))
      } catch {
        self.appDelegate.eventLogger.report(topic: "Artist Radio", error: error)
      }
    }
  }
}

// MARK: - PopularSongRow

private final class PopularSongRow: UIView, UIContextMenuInteractionDelegate {
  private let index: Int
  private weak var target: ArtistHighlightsView?

  init(index: Int, song: AbstractPlayable, theme: ThemePreference, target: ArtistHighlightsView) {
    self.index = index
    self.target = target
    super.init(frame: .zero)

    let numberLabel = UILabel()
    numberLabel.text = "\(index + 1)"
    numberLabel.font = DS.Font.rowSubtitle
    numberLabel.textColor = .secondaryLabel
    numberLabel.textAlignment = .center

    let artwork = EntityImageView(frame: .zero)
    artwork.display(theme: theme, container: song, cornerRadius: .verySmall)

    let titleLabel = UILabel()
    titleLabel.text = song.title
    titleLabel.font = DS.Font.rowTitle
    titleLabel.textColor = .label

    let countLabel = UILabel()
    // songs from Last.fm without own plays show their album instead of "0 plays"
    countLabel.text = song.playCount > 0 ?
      "\(song.playCount.formatted()) play\(song.playCount == 1 ? "" : "s")" :
      (song.asSong?.album?.name ?? "")
    countLabel.font = DS.Font.rowSubtitle
    countLabel.textColor = .secondaryLabel

    let textStack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
    textStack.axis = .vertical
    textStack.spacing = 2

    let row = UIStackView(arrangedSubviews: [numberLabel, artwork, textStack])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = DS.Space.s
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 56),
      numberLabel.widthAnchor.constraint(equalToConstant: 20),
      artwork.widthAnchor.constraint(equalToConstant: 44),
      artwork.heightAnchor.constraint(equalToConstant: 44),
      row.leadingAnchor.constraint(equalTo: leadingAnchor),
      row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])

    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    addInteraction(UIContextMenuInteraction(delegate: self))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func tapped() {
    target?.playPopular(at: index)
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  )
    -> UIContextMenuConfiguration? {
    target?.menu(forPopularAt: index)
  }
}

// MARK: - AlbumTile

private final class AlbumTile: UIView {
  init(album: Album, theme: ThemePreference, width: CGFloat) {
    super.init(frame: .zero)
    let artwork = EntityImageView(frame: .zero)
    artwork.display(theme: theme, container: album, cornerRadius: .small)

    let titleLabel = UILabel()
    titleLabel.text = album.name
    titleLabel.font = DS.Font.rowSubtitle.withSize(14)
    titleLabel.textColor = .label

    let yearLabel = UILabel()
    yearLabel.text = album.year > 0 ? "\(album.year)" : " "
    yearLabel.font = DS.Font.rowSubtitle
    yearLabel.textColor = .secondaryLabel

    let stack = UIStackView(arrangedSubviews: [artwork, titleLabel, yearLabel])
    stack.axis = .vertical
    stack.spacing = 2
    stack.setCustomSpacing(DS.Space.xs, after: artwork)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: width),
      artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
    isUserInteractionEnabled = true
    accessibilityLabel = album.name
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - ArtistCircleTile

private final class ArtistCircleTile: UIView {
  init(artist: Artist, theme: ThemePreference, size: CGFloat) {
    super.init(frame: .zero)
    let artwork = EntityImageView(frame: .zero)
    artwork.display(theme: theme, container: artist, cornerRadius: .small)
    artwork.layer.cornerRadius = size / 2
    artwork.clipsToBounds = true

    let nameLabel = UILabel()
    nameLabel.text = artist.name
    nameLabel.font = DS.Font.tileTitle
    nameLabel.textColor = .label
    nameLabel.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [artwork, nameLabel])
    stack.axis = .vertical
    stack.spacing = DS.Space.xs
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: size),
      artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
    isUserInteractionEnabled = true
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityLabel = artist.name
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
