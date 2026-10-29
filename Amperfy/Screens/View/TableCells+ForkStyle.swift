//
//  TableCells+ForkStyle.swift
//  Amperfy
//
//  Fork: calmer list cells in the streaming style. Values are set in code so the XIBs stay
//  untouched (XIB diffs are hard to merge with upstream).
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

import UIKit

extension PlayableTableCell {
  /// Cover size in song lists and in the queue of the player (measure 10).
  static let forkArtworkSize: CGFloat = 56
  static let forkQueueArtworkSize: CGFloat = 40
  /// Size of the cover in the XIB, its height follows the row height (48 + margins).
  private static let xibArtworkSize: CGFloat = 48

  func applyForkStyle() {
    applyForkFonts()
    // size class variations of the XIB would bring back the fixed point sizes (UI-9)
    registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]) {
      (self: Self, _) in
      self.applyForkFonts()
    }
  }

  private func applyForkFonts() {
    titleLabel.font = DS.Font.songTitle
    artistLabel.font = DS.Font.cellSubtitle
    titleLabel.adjustsFontForContentSizeCategory = true
    artistLabel.adjustsFontForContentSizeCategory = true
    // UI-9: the remaining XIB fonts, the Mac keeps its own sizes
    guard ForkSurface.isEnabled else { return }
    trackNumberLabel.font = DS.Font.trackNumber
    durationLabel.font = DS.Font.cellDuration
    trackNumberLabel.adjustsFontForContentSizeCategory = true
    durationLabel.adjustsFontForContentSizeCategory = true
  }

  /// Cover size and radius, set on every refresh because `configureStyle` and
  /// `EntityImageView.display` reset parts of it. The row height stays the same:
  /// the cover reaches into the top and bottom margins.
  func forkApplyLayout(isQueue: Bool, isTrackNumberStyle: Bool) {
    #if !targetEnvironment(macCatalyst)
      let size = isQueue ? Self.forkQueueArtworkSize : Self.forkArtworkSize
      let overhang = (size - Self.xibArtworkSize) / 2
      for constraint in entityImage.constraints
        where constraint.firstAttribute == .width && constraint.secondItem == nil {
        constraint.constant = size
      }
      for constraint in contentView.constraints {
        if constraint.firstItem === entityImage, constraint.firstAttribute == .top {
          constraint.constant = -overhang
        } else if constraint.secondItem === entityImage, constraint.secondAttribute == .bottom,
                  constraint.firstAttribute == .bottomMargin {
          constraint.constant = -overhang
        }
      }
      if !isTrackNumberStyle {
        titleContainerLeadingConstraint.constant = 10 + size + 8 // heart + artwork + offset
      }
      entityImage.layer.cornerRadius = DS.Radius.small
    #endif
  }
}

extension GenericTableCell {
  /// Called on every `display`, so size class variations of the XIB never stick.
  func applyForkStyle() {
    titleLabel.font = DS.Font.cellTitle
    subtitleLabel.font = DS.Font.cellSubtitle
    infoLabel.font = DS.Font.caption
    [titleLabel, subtitleLabel, infoLabel].forEach { $0?.adjustsFontForContentSizeCategory = true }
    // tapping the row is enough of a hint, the chevron only adds noise
    accessoryType = .none
  }
}

extension PodcastEpisodeTableCell {
  /// Same type scale and cover radius as song rows (UI-1).
  func applyForkStyle() {
    podcastEpisodeLabel.font = DS.Font.songTitle
    infoLabel.font = DS.Font.caption
    descriptionLabel.font = DS.Font.cellSubtitle
    playProgressLabel.font = DS.Font.caption
    [podcastEpisodeLabel, infoLabel, descriptionLabel, playProgressLabel]
      .forEach { $0?.adjustsFontForContentSizeCategory = true }
    infoLabel.textColor = .secondaryLabel
    descriptionLabel.textColor = .secondaryLabel
    entityImage.layer.cornerRadius = DS.Radius.small
    entityImage.clipsToBounds = true
    playEpisodeButton.tintColor = .label
    optionsButton.tintColor = .secondaryLabel
    backgroundColor = ForkSurface.isEnabled ? .clear : .systemBackground
  }
}

extension PlaylistTableCell {
  private static let forkArtworkSize: CGFloat = 56

  /// Playlist rows like song rows: 56 pt collage, radius 4, no chevron (UI-3).
  func applyForkStyle() {
    nameLabel.font = DS.Font.songTitle
    infoLabel.font = DS.Font.cellSubtitle
    nameLabel.adjustsFontForContentSizeCategory = true
    infoLabel.adjustsFontForContentSizeCategory = true
    infoLabel.textColor = .secondaryLabel
    #if !targetEnvironment(macCatalyst)
      // fixed label heights from the XIB would clip larger Dynamic Type sizes
      for label in [nameLabel, infoLabel] {
        label?.constraints
          .filter { $0.firstAttribute == .height && $0.secondItem == nil }
          .forEach { $0.isActive = false }
      }
      for constraint in entityImage.constraints
        where constraint.firstAttribute == .width && constraint.secondItem == nil {
        constraint.constant = Self.forkArtworkSize
      }
      entityImage.layer.cornerRadius = DS.Radius.small
      entityImage.clipsToBounds = true
      accessoryType = .none
      backgroundColor = .clear
    #endif
  }
}

extension DirectoryTableCell {
  /// Folder and directory rows like the other list rows (UI-9).
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    infoLabel.font = DS.Font.cellTitle
    infoLabel.adjustsFontForContentSizeCategory = true
  }
}
