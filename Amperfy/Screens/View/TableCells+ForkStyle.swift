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
  func applyForkStyle() {
    titleLabel.font = DS.Font.cellTitle
    artistLabel.font = DS.Font.cellSubtitle
    titleLabel.adjustsFontForContentSizeCategory = true
    artistLabel.adjustsFontForContentSizeCategory = true
  }
}

extension GenericTableCell {
  func applyForkStyle() {
    titleLabel.font = DS.Font.cellTitle
    subtitleLabel.font = DS.Font.cellSubtitle
    infoLabel.font = DS.Font.caption
    // tapping the row is enough of a hint, the chevron only adds noise
    accessoryType = .none
  }
}
