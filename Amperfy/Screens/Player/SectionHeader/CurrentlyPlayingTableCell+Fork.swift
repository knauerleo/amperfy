//
//  CurrentlyPlayingTableCell+Fork.swift
//  Amperfy
//
//  Fork: the current song at the top of the queue stands out from the rows below it:
//  a rounded card and moving bars on the cover (measure 10).
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

// MARK: - QueueNowPlayingCard

/// Card behind the current song, follows play and pause for its bars.
final class QueueNowPlayingCard: UIView {
  private static let fill = UIColor { traits in
    UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.1)
  }

  private let barsBadge = UIView()
  private let bars = NowPlayingBarsView()

  init(cell: CurrentlyPlayingTableCell) {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = Self.fill
    layer.cornerRadius = DS.Radius.large
    layer.cornerCurve = .continuous
    translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.insertSubview(self, at: 0)

    // small dark badge with the bars in the bottom trailing corner of the cover
    barsBadge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    barsBadge.layer.cornerRadius = DS.Radius.small
    barsBadge.isUserInteractionEnabled = false
    barsBadge.translatesAutoresizingMaskIntoConstraints = false
    bars.tintColor = .white
    bars.translatesAutoresizingMaskIntoConstraints = false
    barsBadge.addSubview(bars)
    cell.contentView.addSubview(barsBadge)

    let artwork = cell.artworkImage!
    NSLayoutConstraint.activate([
      leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: DS.Space.xs),
      trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -DS.Space.xs),
      topAnchor.constraint(equalTo: artwork.topAnchor, constant: -DS.Space.xs),
      bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: DS.Space.xs),
      barsBadge.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: -DS.Space.xxs),
      barsBadge.bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: -DS.Space.xxs),
      barsBadge.widthAnchor.constraint(equalToConstant: 22),
      barsBadge.heightAnchor.constraint(equalToConstant: 20),
      bars.centerXAnchor.constraint(equalTo: barsBadge.centerXAnchor),
      bars.centerYAnchor.constraint(equalTo: barsBadge.centerYAnchor),
      bars.widthAnchor.constraint(equalToConstant: 12),
      bars.heightAnchor.constraint(equalToConstant: 10),
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

  @objc
  func playerStateChanged() {
    let player = appDelegate.player
    barsBadge.isHidden = player.currentlyPlaying == nil
    bars.isPlaying = player.isPlaying
  }
}

// MARK: - CurrentlyPlayingTableCell

extension CurrentlyPlayingTableCell {
  /// Adds the card once (iPhone and iPad) and updates its bars.
  func forkRefreshNowPlayingCard() {
    #if !targetEnvironment(macCatalyst)
      let card = contentView.subviews.first(where: { $0 is QueueNowPlayingCard }) as? QueueNowPlayingCard ??
        QueueNowPlayingCard(cell: self)
      artworkImage.layer.cornerRadius = DS.Radius.medium
      artworkImage.layer.masksToBounds = true
      card.playerStateChanged()
    #endif
  }
}
