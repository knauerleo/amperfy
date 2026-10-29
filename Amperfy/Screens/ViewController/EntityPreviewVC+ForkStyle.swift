//
//  EntityPreviewVC+ForkStyle.swift
//  Amperfy
//
//  Fork: fonts of the context menu preview on DS.Font (UI-9). The info line (year, duration,
//  bitrate) was 16 pt and cut off the bitrate on the iPhone, now it uses the 13-pt cell
//  subtitle. The fixed label heights of the XIB follow the line height of the new fonts.
//  The Mac keeps the XIB fonts.
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

extension EntityPreviewVC {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    let fonts: [(UILabel?, UIFont)] = [
      (titleLabel, DS.Font.previewTitle),
      (artistLabel, DS.Font.previewSubtitle),
      (infoLabel, DS.Font.cellSubtitle),
    ]
    for (label, font) in fonts {
      guard let label else { continue }
      label.font = font
      for constraint in label.constraints
        where constraint.firstAttribute == .height && constraint.secondItem == nil {
        constraint.constant = ceil(font.lineHeight)
      }
    }
  }
}
