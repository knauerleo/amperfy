//
//  HomeSection+ForkMigration.swift
//  AmperfyKit
//
//  Fork: Home sections are stored per account. Sections added by the fork would never show up
//  for an account that already has a stored selection, so they are inserted once.
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

import Foundation

extension HomeSection {
  /// Sections of design phase 3, shown at the top of Home.
  static let forkTopSections: [HomeSection] = [.recentlyPlayed, .recentlyAdded]

  /// Fork order: the new sections first, then the user's sections in their order,
  /// random sections last (keeping their relative order).
  static func forkArranged(_ sections: [HomeSection]) -> [HomeSection] {
    let top = forkTopSections.filter { sections.contains($0) }
    let rest = sections.filter { !forkTopSections.contains($0) }
    return top + rest.filter { !$0.isRandomSection } + rest.filter(\.isRandomSection)
  }
}

extension AccountSetting {
  static let forkHomeSectionsVersion = 1

  public var needsForkHomeSectionsMigration: Bool {
    (_forkHomeSectionsVersion ?? 0) < Self.forkHomeSectionsVersion
  }

  /// Runs once per account: adds the fork sections as visible and moves random sections to
  /// the end. Which of the existing sections are visible stays untouched.
  public mutating func migrateForkHomeSections() {
    guard needsForkHomeSectionsMigration else { return }
    let visible = homeSections
    let order = homeSectionOrder
    homeSections = HomeSection.forkArranged(
      HomeSection.forkTopSections + visible.filter { !HomeSection.forkTopSections.contains($0) }
    )
    homeSectionOrder = HomeSection.forkArranged(order)
    _forkHomeSectionsVersion = Self.forkHomeSectionsVersion
  }
}
