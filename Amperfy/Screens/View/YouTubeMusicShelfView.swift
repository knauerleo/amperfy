//
//  YouTubeMusicShelfView.swift
//  Amperfy
//
//  Fork (TASKS F-5): shelf "Similar on YouTube Music" for the artist and album pages.
//  Tiles like the discography shelf. Tap plays the shelf from that song through the proxy
//  (which also downloads it), long press offers Play Next, Add to Queue and Add to Library.
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

// MARK: - YouTubeMusicShelfView

final class YouTubeMusicShelfView: UIView {
  static let title = "Similar on YouTube Music"
  private static let tileWidth: CGFloat = 140

  private let songs: [Song]
  private let contextName: String

  init(songs: [Song], contextName: String) {
    self.songs = songs
    self.contextName = contextName
    super.init(frame: .zero)

    let titleLabel = UILabel()
    titleLabel.text = Self.title
    titleLabel.font = DS.Font.sectionTitle
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .label

    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.clipsToBounds = false
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = DS.Space.s
    row.alignment = .top
    row.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(row)
    for (index, song) in songs.enumerated() {
      row.addArrangedSubview(YouTubeSongTile(
        song: song,
        index: index,
        width: Self.tileWidth,
        target: self
      ))
    }

    let stack = UIStackView(arrangedSubviews: [titleLabel, scrollView])
    stack.axis = .vertical
    stack.spacing = DS.Space.s
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      scrollView.heightAnchor.constraint(equalToConstant: Self.tileWidth + 44),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The search tab deletes unused placeholders, a shelf may still show one of them.
  private var usableSongs: [Song] {
    songs.filter(isUsable)
  }

  private func isUsable(_ song: Song) -> Bool {
    song.managedObject.managedObjectContext != nil && !song.managedObject.isDeleted
  }

  // MARK: Actions

  fileprivate func play(at index: Int) {
    guard songs.indices.contains(index), isUsable(songs[index]),
          appDelegate.storage.settings.user.isOnlineMode else { return }
    let playables = usableSongs
    guard let start = playables.firstIndex(where: { $0.id == songs[index].id }) else { return }
    DS.haptic(.light)
    // the download is followed by YouTubeMusicDownloadCoordinator once the song plays
    appDelegate.player.play(context: PlayContext(
      name: contextName,
      index: start,
      playables: playables
    ))
  }

  fileprivate func menu(at index: Int) -> UIContextMenuConfiguration? {
    guard songs.indices.contains(index), isUsable(songs[index]) else { return nil }
    let song = songs[index]
    let videoId = String(song.id.dropFirst(YouTubeMusic.idPrefix.count))
    let hit = YouTubeMusicHitStore.shared.hit(forVideoId: videoId)
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      guard let self else { return nil }
      let play = UIAction(title: "Play", image: .play) { [weak self] _ in
        self?.play(at: index)
      }
      let playNext = UIAction(
        title: "Play Next",
        image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")
      ) { [weak self] _ in
        guard let self, isUsable(song) else { return }
        appDelegate.player.insertUserQueue(playables: [song])
        DS.haptic(.success)
      }
      let addToQueue = UIAction(
        title: "Add to Queue",
        image: UIImage(systemName: "text.line.last.and.arrowtriangle.forward")
      ) { [weak self] _ in
        guard let self, isUsable(song) else { return }
        appDelegate.player.appendUserQueue(playables: [song])
        DS.haptic(.success)
      }
      var children: [UIMenuElement] = [
        UIMenu(options: .displayInline, children: [play, playNext, addToQueue]),
      ]
      if let hit {
        let status = YouTubeMusicJobMonitor.shared.status(for: hit)
        let canAdd = status == .online || status == .failed
        let addToLibrary = UIAction(
          title: status == .inLibrary ? "In Library" : "Add to Library",
          image: UIImage(systemName: status == .inLibrary ? "checkmark.circle" : "arrow.down.circle"),
          attributes: canAdd ? [] : .disabled
        ) { [weak self] _ in
          Task { @MainActor in
            do {
              try await YouTubeMusicJobMonitor.shared.addToLibrary(hit)
              DS.haptic(.success)
            } catch {
              self?.appDelegate.eventLogger.report(topic: "Add to Library", error: error)
            }
          }
        }
        children.append(UIMenu(options: .displayInline, children: [addToLibrary]))
      }
      return UIMenu(children: children)
    }
  }
}

// MARK: - YouTubeSongTile

private final class YouTubeSongTile: UIView, UIContextMenuInteractionDelegate {
  private let index: Int
  private weak var target: YouTubeMusicShelfView?

  init(song: Song, index: Int, width: CGFloat, target: YouTubeMusicShelfView) {
    self.index = index
    self.target = target
    super.init(frame: .zero)

    let artwork = EntityImageView(frame: .zero)
    let theme = appDelegate.storage.settings.accounts.getSetting(song.account?.info).read
      .themePreference
    artwork.display(theme: theme, container: song, cornerRadius: .small)

    let titleLabel = UILabel()
    titleLabel.text = song.title
    titleLabel.font = DS.Font.rowSubtitle.withSize(14)
    titleLabel.textColor = .label

    let artistLabel = UILabel()
    artistLabel.text = song.creatorName
    artistLabel.font = DS.Font.rowSubtitle
    artistLabel.textColor = .secondaryLabel

    let stack = UIStackView(arrangedSubviews: [artwork, titleLabel, artistLabel])
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
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityLabel = "\(song.title), \(song.creatorName), YouTube Music"
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    addInteraction(UIContextMenuInteraction(delegate: self))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc
  private func tapped() {
    target?.play(at: index)
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  )
    -> UIContextMenuConfiguration? {
    target?.menu(at: index)
  }
}
