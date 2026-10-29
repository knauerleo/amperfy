//
//  ListRows+ForkStyle.swift
//  Amperfy
//
//  Fork (UI-18): list rows in the Drift identity, iPhone only. Song rows 60 pt with a 48 pt
//  cover, album, artist and playlist rows 72 pt with a 56 pt cover (artists round), no lines
//  between rows, a "…" button on the right that opens the context menu of the row.
//  iPad and Mac keep the earlier fork rows (UI-16).
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

// MARK: - ForkRowMetrics

@MainActor
enum ForkRowMetrics {
  /// Row heights on the iPhone. Spacing separates the rows, not lines.
  static let songRowHeight: CGFloat = 60
  static let containerRowHeight: CGFloat = 72
  static let songArtworkSize: CGFloat = 48
  static let containerArtworkSize: CGFloat = 56
  /// Touch target of the "…" button.
  static let moreButtonSize: CGFloat = 44
}

// MARK: - ForkMoreButton

@MainActor
enum ForkMoreButton {
  /// "…" in Text 2 with a 44 pt touch target. The menu is built when it opens, like the
  /// long-press menu of the row.
  static func make(menuBuilder: @escaping () -> [UIMenuElement]) -> UIButton {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: "ellipsis")?.withConfiguration(
      UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    )
    config.baseForegroundColor = DS.Color.text2
    config.contentInsets = .zero
    let button = UIButton(configuration: config)
    button.frame = CGRect(
      x: 0,
      y: 0,
      width: ForkRowMetrics.moreButtonSize,
      height: ForkRowMetrics.moreButtonSize
    )
    button.showsMenuAsPrimaryAction = true
    button.menu = UIMenu.lazyMenu(builder: menuBuilder)
    button.accessibilityLabel = String(localized: "More", table: "Fork")
    return button
  }
}

// MARK: - GenericTableCell

extension GenericTableCell {
  /// Albums, artists, genres, podcasts. The add-to-playlist screens keep a plain row.
  func applyForkPhoneStyle(container: PlayableContainable?, rootView: UITableViewController?) {
    guard DS.isPhone else { return }
    titleLabel.font = DS.Font.songTitle
    titleLabel.textColor = DS.Color.text
    subtitleLabel.textColor = DS.Color.text2
    infoLabel.textColor = DS.Color.text3
    backgroundColor = .clear

    let isRound = container is Artist
    for constraint in entityImage.constraints
      where constraint.firstAttribute == .width && constraint.secondItem == nil {
      constraint.constant = ForkRowMetrics.containerArtworkSize
    }
    entityImage.layer.cornerRadius = isRound ?
      ForkRowMetrics.containerArtworkSize / 2 : DS.Radius.rowArtwork
    entityImage.clipsToBounds = true

    if let container, let rootView, !(rootView is PlaylistVCAddable) {
      accessoryView = ForkMoreButton.make { [weak rootView] in
        guard let rootView else { return [] }
        return EntityPreviewActionBuilder(container: container, on: rootView).createMenuActions()
      }
    } else {
      accessoryView = nil
    }
  }
}

// MARK: - PlaylistTableCell

extension PlaylistTableCell {
  /// Playlists list and search: collage 56 pt like the album rows, aligned with the other covers.
  func applyForkPhoneStyle(playlist: Playlist?, rootView: UITableViewController?) {
    guard DS.isPhone else { return }
    nameLabel.textColor = DS.Color.text
    infoLabel.textColor = DS.Color.text2
    for constraint in entityImage.constraints
      where constraint.firstAttribute == .width && constraint.secondItem == nil {
      constraint.constant = ForkRowMetrics.containerArtworkSize
    }
    for constraint in contentView.constraints
      where constraint.firstItem === entityImage && constraint.firstAttribute == .leading {
      constraint.constant = 0
    }
    entityImage.layer.cornerRadius = DS.Radius.rowArtwork

    if let playlist, let rootView, rootView is PlaylistsVC || rootView is SearchVC {
      accessoryView = ForkMoreButton.make { [weak rootView] in
        guard let rootView else { return [] }
        return EntityPreviewActionBuilder(container: playlist, on: rootView).createMenuActions()
      }
    } else {
      accessoryView = nil
    }
  }
}

// MARK: - PlayableTableCell

extension PlayableTableCell {
  /// The "…" button of the XIB: 44 pt wide (it reaches into the right margin, the icon moves
  /// 7 pt to the right), Text 2 instead of the label color, a VoiceOver label.
  func forkApplyPhoneOptionsButton() {
    guard DS.isPhone else { return }
    for constraint in optionsButton.constraints
      where constraint.firstAttribute == .width && constraint.secondItem == nil {
      constraint.constant = ForkRowMetrics.moreButtonSize
    }
    for constraint in contentView.constraints
      where constraint.secondItem === optionsButton && constraint.firstAttribute == .trailingMargin {
      constraint.constant = 30 - ForkRowMetrics.moreButtonSize
    }
    optionsButton.imageView?.tintColor = DS.Color.text2
    optionsButton.tintColor = DS.Color.text2
    optionsButton.accessibilityLabel = String(localized: "More", table: "Fork")
  }
}

extension PlayableTableCell {
  /// Last step of `refresh`: `refreshCacheAndDuration` sets the "…" back to the label color.
  func forkFinishRefresh(playable: AbstractPlayable?, isTrackNumberStyle: Bool, isQueue: Bool) {
    guard DS.isPhone, !isQueue else { return }
    optionsButton.imageView?.tintColor = DS.Color.text2
    artistLabel.textColor = DS.Color.text2
    if isTrackNumberStyle, let playable {
      forkApplyAlbumPageRow(playable: playable)
    } else {
      artistLabel.font = DS.Font.cellSubtitle
    }
  }

  /// Album page: track number instead of the cover (upstream), no artist line, the duration
  /// in the subtitle with fixed digits. Guest artists stay in front of the duration.
  private func forkApplyAlbumPageRow(playable: AbstractPlayable) {
    let duration = playable.duration > 0 ? playable.duration.asColonDurationString : ""
    let isGuest = playable.asSong?.album?.artist?.name != playable.creatorName
    let parts = [isGuest ? playable.creatorName : "", duration].filter { !$0.isEmpty }
    artistLabel.text = parts.joined(separator: " · ")
    artistLabel.font = DS.Font.cellDuration
    artistLabel.isHidden = parts.isEmpty

    // the duration column on the right is free now: only "…" and the download icon remain
    let optionsWidth: CGFloat = optionsButton.isHidden ? 0 : 30
    let isCacheIconVisible = !cacheIconImage.isHidden
    durationLabel.isHidden = true
    cacheTrailingCellConstaint.constant = optionsWidth
    labelTrailingCellConstraint.constant = optionsWidth + (isCacheIconVisible ? 4 + 15 + 4 : 0)
  }
}
