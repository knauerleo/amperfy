//
//  PlayableTableCell+NowPlaying.swift
//  Amperfy
//
//  Fork: the song that is playing shows its title in the accent color and a small
//  animated equalizer, over the cover or in place of the track number (measure 10).
//  Replaces the VYPlayIndicator of PlayableTableCell on iPhone and iPad, the Mac keeps it.
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

// MARK: - NowPlayingCellDecorator

/// Lives as a subview of the cell (dimmed overlay on the cover) and follows play, pause and
/// song changes on its own, like the original PlayIndicator.
final class NowPlayingCellDecorator: UIView {
  private let artworkEqualizer = NowPlayingBarsView()
  private let numberEqualizer = NowPlayingBarsView()
  /// UI-18 (iPhone): the row of the current song sits on a rounded surface.
  private let rowHighlight = UIView()

  private weak var cell: PlayableTableCell?
  private weak var titleLabel: UILabel?
  private weak var trackNumberLabel: UILabel?
  private var playable: AbstractPlayable?
  private var isTrackNumberStyle = false
  private var isQueue = false

  init(cell: PlayableTableCell) {
    super.init(frame: .zero)
    self.cell = cell
    titleLabel = cell.titleLabel
    trackNumberLabel = cell.trackNumberLabel
    isUserInteractionEnabled = false
    isHidden = true
    backgroundColor = .imageOverlayBackground

    artworkEqualizer.tintColor = .white
    numberEqualizer.isHidden = true
    [artworkEqualizer, numberEqualizer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    addSubview(artworkEqualizer)

    // dimmed overlay sits on the cover, the second equalizer in the track number slot
    translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.insertSubview(self, belowSubview: cell.playOverArtworkButton)
    cell.contentView.insertSubview(numberEqualizer, belowSubview: cell.playOverNumberButton)
    rowHighlight.isUserInteractionEnabled = false
    rowHighlight.isHidden = true
    rowHighlight.backgroundColor = DS.Color.surface
    rowHighlight.layer.cornerRadius = DS.Radius.nowPlayingRow
    rowHighlight.layer.cornerCurve = .continuous
    rowHighlight.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.insertSubview(rowHighlight, at: 0)
    NSLayoutConstraint.activate([
      leadingAnchor.constraint(equalTo: cell.entityImage.leadingAnchor),
      trailingAnchor.constraint(equalTo: cell.entityImage.trailingAnchor),
      topAnchor.constraint(equalTo: cell.entityImage.topAnchor),
      bottomAnchor.constraint(equalTo: cell.entityImage.bottomAnchor),
      artworkEqualizer.centerXAnchor.constraint(equalTo: centerXAnchor),
      artworkEqualizer.centerYAnchor.constraint(equalTo: centerYAnchor),
      artworkEqualizer.widthAnchor.constraint(equalToConstant: 16),
      artworkEqualizer.heightAnchor.constraint(equalToConstant: 14),
      numberEqualizer.trailingAnchor.constraint(equalTo: cell.trackNumberLabel.trailingAnchor),
      numberEqualizer.centerYAnchor.constraint(equalTo: cell.trackNumberLabel.centerYAnchor),
      numberEqualizer.widthAnchor.constraint(equalToConstant: 13),
      numberEqualizer.heightAnchor.constraint(equalToConstant: 12),
      rowHighlight.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: DS.Space.xs),
      rowHighlight.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -DS.Space.xs),
      rowHighlight.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 2),
      rowHighlight.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -2),
    ])

    for name in [Notification.Name.playerPlay, .playerPause, .playerStop] {
      appDelegate.notificationHandler.register(
        self,
        selector: #selector(playerStateChanged),
        name: name,
        object: nil
      )
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(playable: AbstractPlayable?, isTrackNumberStyle: Bool, isQueue: Bool) {
    self.playable = playable
    self.isTrackNumberStyle = isTrackNumberStyle
    self.isQueue = isQueue
    refresh()
  }

  @objc
  private func playerStateChanged() {
    refresh()
  }

  private func refresh() {
    let player = appDelegate.player
    // the queue in the player shows the current song in its own row
    let isCurrent = !isQueue && playable != nil && playable == player.currentlyPlaying
    let isPlaying = isCurrent && player.isPlaying
    let accent = appDelegate.storage.settings.accounts.getSetting(playable?.account?.info).read
      .themePreference.asColor

    isHidden = !isCurrent || isTrackNumberStyle
    if DS.isPhone {
      // UI-18: title and track number in the accent, the number stays, the row on a surface
      titleLabel?.textColor = isCurrent ? accent : DS.Color.text
      trackNumberLabel?.textColor = isCurrent ? accent : DS.Color.text2
      trackNumberLabel?.alpha = 1
      numberEqualizer.isHidden = true
      rowHighlight.isHidden = !isCurrent
    } else {
      titleLabel?.textColor = isCurrent ? accent : .label
      numberEqualizer.isHidden = !isCurrent || !isTrackNumberStyle
      // alpha instead of isHidden: the hover code of the cell toggles isHidden
      trackNumberLabel?.alpha = (isCurrent && isTrackNumberStyle) ? 0 : 1
      rowHighlight.isHidden = true
    }
    numberEqualizer.tintColor = accent
    artworkEqualizer.isPlaying = isPlaying && !isTrackNumberStyle
    numberEqualizer.isPlaying = isPlaying && isTrackNumberStyle && !DS.isPhone
    // the equalizer is only visual, VoiceOver hears the state on the row (UI-10)
    cell?.accessibilityValue = isCurrent ? (isPlaying ? String(localized: "Now Playing", table: "Fork") : String(localized: "Paused", table: "Fork")) : nil
  }
}

// MARK: - PlayableTableCell

extension PlayableTableCell {
  private var nowPlayingDecorator: NowPlayingCellDecorator {
    if let existing = contentView.subviews
      .first(where: { $0 is NowPlayingCellDecorator }) as? NowPlayingCellDecorator {
      return existing
    }
    return NowPlayingCellDecorator(cell: self)
  }

  /// Called instead of the PlayIndicator. Returns false on the Mac, which keeps the original.
  func forkDisplayNowPlaying(
    playable: AbstractPlayable?,
    isTrackNumberStyle: Bool,
    isQueue: Bool
  )
    -> Bool {
    #if targetEnvironment(macCatalyst)
      return false
    #else
      nowPlayingDecorator.display(
        playable: playable,
        isTrackNumberStyle: isTrackNumberStyle,
        isQueue: isQueue
      )
      return true
    #endif
  }
}
