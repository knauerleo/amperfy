//
//  PlayerControlView+ForkStyle.swift
//  Amperfy
//
//  Fork: controls on top of the artwork-colored player background use neutral accents,
//  so the cover color stays the only color on screen.
//  Player fonts (controls and the large title/artist/album view) on DS.Font with Dynamic Type.
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

extension PlayerControlView {
  func applyForkStyle() {
    timeSlider.minimumTrackTintColor = DS.Color.onArtwork
    timeSlider.maximumTrackTintColor = DS.Color.onArtworkTrack
    // Technical stream info (format, bitrate) stays available but no longer competes with the title
    audioInfoLabel.font = DS.Font.caption
    audioInfoLabel.alpha = 0.6
    playTypeIcon.alpha = 0.6
    applyForkFonts()
    forkInstallStreamingTransport()
    // size class variations of the XIB would bring back the fixed point sizes
    registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]) {
      (self: Self, _) in
      self.applyForkFonts()
    }
  }

  /// Fonts of the XIB had fixed point sizes, these scale with Dynamic Type (UI-4).
  private func applyForkFonts() {
    elapsedTimeLabel.font = DS.Font.playerTime
    remainingTimeLabel.font = DS.Font.playerTime
    audioInfoLabel.font = DS.Font.caption
    liveLabel.font = DS.Font.playerTime.withWeight(.bold)
  }
}

extension LargeCurrentlyPlayingPlayerView {
  func applyForkStyle() {
    applyForkFonts()
    registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]) {
      (self: Self, _) in
      self.applyForkFonts()
    }
  }

  private func applyForkFonts() {
    titleLabel.font = DS.Font.playerTitle
    artistLabel.font = DS.Font.playerSubtitle
    albumLabel.font = DS.Font.playerAlbum
  }
}

extension UIFont {
  fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([
      .traits: [UIFontDescriptor.TraitKey.weight: weight],
    ])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
