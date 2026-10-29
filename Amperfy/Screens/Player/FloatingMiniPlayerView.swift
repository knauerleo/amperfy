//
//  FloatingMiniPlayerView.swift
//  Amperfy
//
//  Fork (UI-19): the mini player as a floating card above the tab bar (iPhone), like streaming apps.
//  Raised surface, radius 14, shadow. It hosts the existing `MiniPlayerView`, so player updates,
//  progress, swipes, VoiceOver and the zoom into the player stay as they are.
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

final class FloatingMiniPlayerView: UIView {
  static let height: CGFloat = 60
  static let sideMargin: CGFloat = 8
  /// Gap between the card and the top of the tab bar.
  static let bottomGap: CGFloat = 8

  let miniPlayer: MiniPlayerView
  private let player: PlayerFacade
  /// Called when a song starts or the queue runs empty, the card shows or hides then.
  var visibilityChanged: (() -> ())?

  private let surface = UIView()

  var hasSong: Bool { player.currentlyPlaying != nil }

  init(miniPlayer: MiniPlayerView, player: PlayerFacade) {
    self.miniPlayer = miniPlayer
    self.player = player
    super.init(frame: .zero)

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.5
    layer.shadowOffset = CGSize(width: 0, height: 8)
    layer.shadowRadius = 12

    surface.backgroundColor = DS.Color.surfaceRaised
    surface.layer.cornerRadius = DS.Radius.card
    surface.layer.cornerCurve = .continuous
    surface.clipsToBounds = true
    surface.translatesAutoresizingMaskIntoConstraints = false
    addSubview(surface)

    miniPlayer.translatesAutoresizingMaskIntoConstraints = false
    surface.addSubview(miniPlayer)

    NSLayoutConstraint.activate([
      surface.leadingAnchor.constraint(equalTo: leadingAnchor),
      surface.trailingAnchor.constraint(equalTo: trailingAnchor),
      surface.topAnchor.constraint(equalTo: topAnchor),
      surface.bottomAnchor.constraint(equalTo: bottomAnchor),
      miniPlayer.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      miniPlayer.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      miniPlayer.topAnchor.constraint(equalTo: surface.topAnchor),
      miniPlayer.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
    ])

    player.addNotifier(notifier: self)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: DS.Radius.card).cgPath
  }
}

// MARK: MusicPlayable

extension FloatingMiniPlayerView: MusicPlayable {
  func didStartPlayingFromBeginning() {}
  func didStartPlaying() { visibilityChanged?() }
  func didPause() {}
  func didStopPlaying() { visibilityChanged?() }
  func didElapsedTimeChange() {}
  func didPlaylistChange() { visibilityChanged?() }
  func didArtworkChange() {}
  func didNowPlayingInfoChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}
