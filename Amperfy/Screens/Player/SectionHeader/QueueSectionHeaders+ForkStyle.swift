//
//  QueueSectionHeaders+ForkStyle.swift
//  Amperfy
//
//  Fork: fonts of the queue section headers in the player on DS.Font instead of the fixed
//  sizes of the XIBs (UI-9). The header frames have a fixed height, so the fonts only grow by
//  one point with Dynamic Type. The Mac keeps the XIB fonts.
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

extension ContextQueueNextSectionHeader {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    queueNameLabel.font = DS.Font.queueHeaderTitle
    contextNameLabel.font = DS.Font.queueHeaderSubtitle
  }
}

extension ContextQueuePrevSectionHeader {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    nameLabel.font = DS.Font.queueHeaderTitle
  }
}

extension UserQueueSectionHeader {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    nameLabel.font = DS.Font.queueHeaderTitle
  }
}
