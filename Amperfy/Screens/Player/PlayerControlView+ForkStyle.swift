//
//  PlayerControlView+ForkStyle.swift
//  Amperfy
//
//  Fork: controls on top of the artwork-colored player background use neutral accents,
//  so the cover color stays the only color on screen.
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
  }
}
