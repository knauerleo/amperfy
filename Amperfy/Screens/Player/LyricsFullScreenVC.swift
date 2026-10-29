//
//  LyricsFullScreenVC.swift
//  Amperfy
//
//  Fork (UI-27): lyrics in full screen like in streaming apps, opened from the lyrics card
//  or the player options. Surface in the cover color, title and artist on top, the lines
//  follow the playback (current line white, the others dimmed), a tap on a line seeks there.
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
import CoreMedia
import UIKit

final class LyricsFullScreenVC: UIViewController {
  private static let buttonSize: CGFloat = 44
  private static let playCircleSize: CGFloat = 64

  private let lyricsView = LyricsView()
  private let titleLabel = UILabel()
  private let artistLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let playButton = UIButton(type: .system)
  private let emptyLabel = UILabel()
  private var lyrics: StructuredLyrics?
  private var colors: [UIColor]
  /// Song the shown lyrics belong to.
  private(set) var songID: String?

  private var player: PlayerFacade { appDelegate.player }

  init(lyrics: StructuredLyrics, songID: String?, colors: [UIColor]) {
    self.lyrics = lyrics
    self.songID = songID
    self.colors = colors
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
    modalTransitionStyle = .coverVertical
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = LyricsCardView.surfaceColor(for: colors) ?? LyricsCardView.defaultSurfaceColor
    overrideUserInterfaceStyle = .dark

    closeButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    closeButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(textStyle: .headline, scale: .large),
      forImageIn: .normal
    )
    closeButton.tintColor = .white
    closeButton.accessibilityLabel = String(localized: "Close lyrics", table: "Fork")
    closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)

    titleLabel.font = DS.Font.playerTitle
    titleLabel.textColor = .white
    titleLabel.adjustsFontForContentSizeCategory = true
    artistLabel.font = DS.Font.playerSubtitle
    artistLabel.textColor = UIColor.white.withAlphaComponent(0.7)
    artistLabel.adjustsFontForContentSizeCategory = true
    let titles = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
    titles.axis = .vertical
    titles.spacing = DS.Space.xxs

    let header = UIStackView(arrangedSubviews: [closeButton, titles])
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = DS.Space.xs
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)

    lyricsView.forkCardStyle = true
    lyricsView.translatesAutoresizingMaskIntoConstraints = false
    lyricsView.onLyricSelected = { [weak self] lyric in
      self?.player.seek(toSecond: lyric.startTime.seconds)
    }
    view.addSubview(lyricsView)

    emptyLabel.text = String(localized: "No lyrics for this song", table: "Fork")
    emptyLabel.font = DS.Font.lyricsCardLine
    emptyLabel.textColor = UIColor.white.withAlphaComponent(0.6)
    emptyLabel.adjustsFontForContentSizeCategory = true
    emptyLabel.numberOfLines = 0
    emptyLabel.textAlignment = .center
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(emptyLabel)

    let circle = UIView()
    circle.isUserInteractionEnabled = false
    circle.backgroundColor = .white
    circle.layer.cornerRadius = Self.playCircleSize / 2
    circle.translatesAutoresizingMaskIntoConstraints = false
    playButton.insertSubview(circle, at: 0)
    playButton.tintColor = .black
    playButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 26, weight: .bold),
      forImageIn: .normal
    )
    playButton.translatesAutoresizingMaskIntoConstraints = false
    playButton.addAction(UIAction { [weak self] _ in
      DS.haptic(.light)
      self?.player.togglePlayPause()
      self?.refreshPlayButton()
    }, for: .touchUpInside)
    view.addSubview(playButton)

    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DS.Space.xs),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Space.xs),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Space.m),
      closeButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
      closeButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),

      lyricsView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DS.Space.m),
      lyricsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Space.xs),
      lyricsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Space.xs),
      lyricsView.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -DS.Space.m),

      emptyLabel.centerYAnchor.constraint(equalTo: lyricsView.centerYAnchor),
      emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DS.Space.l),
      emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DS.Space.l),

      playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DS.Space.m),
      playButton.widthAnchor.constraint(equalToConstant: Self.playCircleSize),
      playButton.heightAnchor.constraint(equalToConstant: Self.playCircleSize),
      circle.centerXAnchor.constraint(equalTo: playButton.centerXAnchor),
      circle.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),
      circle.widthAnchor.constraint(equalToConstant: Self.playCircleSize),
      circle.heightAnchor.constraint(equalToConstant: Self.playCircleSize),
    ])

    player.addNotifier(notifier: self)
    refreshInfo()
    refreshPlayButton()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // the lyrics view centers the current line with insets from its height, show them once it has one
    guard lyricsView.bounds.height > 0, lyrics != nil,
          lyricsView.numberOfRows(inSection: 0) == 0 else { return }
    showLyrics()
  }

  private func showLyrics() {
    guard let lyrics else { return }
    lyricsView.display(lyrics: lyrics, scrollAnimation: true)
    if lyrics.synced {
      lyricsView.scroll(toTime: CMTime(seconds: player.elapsedTime, preferredTimescale: 1000))
    } else {
      lyricsView.highlightAllLyrics()
    }
  }

  private func refreshInfo() {
    let playable = player.currentlyPlaying
    titleLabel.text = playable?.title
    artistLabel.text = playable?.creatorName
  }

  private func refreshPlayButton() {
    let image: UIImage = player.isPlaying ? .pause : .play
    playButton.setImage(image, for: .normal)
    playButton.imageView?.tintColor = .black
    if let imageView = playButton.imageView { playButton.bringSubviewToFront(imageView) }
    playButton.accessibilityLabel = player.isPlaying ?
      String(localized: "Pause", table: "Fork") : String(localized: "Play", table: "Fork")
  }

  private func close() {
    DS.haptic(.light)
    dismiss(animated: true)
  }

  /// Lyrics of the song `songID`, nil while they load or when the song has none.
  /// The player passes them on from its lyrics card.
  func show(lyrics: StructuredLyrics?, songID: String?) {
    self.songID = songID
    refreshInfo()
    guard let lyrics else {
      self.lyrics = nil
      lyricsView.clear()
      emptyLabel.isHidden = false
      return
    }
    self.lyrics = lyrics
    emptyLabel.isHidden = true
    showLyrics()
  }
}

// MARK: MusicPlayable

extension LyricsFullScreenVC: MusicPlayable {
  func didStartPlayingFromBeginning() {
    // the player passes the new lyrics on once its card has them
    if player.currentlyPlaying?.asSong?.id != songID { show(lyrics: nil, songID: nil) }
    refreshPlayButton()
  }

  func didStartPlaying() { refreshPlayButton() }
  func didPause() { refreshPlayButton() }
  func didStopPlaying() { refreshPlayButton() }
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}

  func didLyricsTimeChange(time: CMTime) {
    lyricsView.scroll(toTime: time)
  }
}
