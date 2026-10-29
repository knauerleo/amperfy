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

  /// Sections added by later fork tasks, keyed by the settings version that introduced them.
  /// They are shown once, in front of the random sections.
  static let forkAddedSections: [(version: Int, sections: [HomeSection])] = [
    (2, [.mostPlayedAlbums, .topRatedAlbums, .decades]), // F-11
  ]

  static func forkInsertingBeforeRandom(
    _ added: [HomeSection],
    into sections: [HomeSection]
  )
    -> [HomeSection] {
    var result = sections.filter { !added.contains($0) }
    let index = result.firstIndex(where: \.isRandomSection) ?? result.endIndex
    result.insert(contentsOf: added, at: index)
    return result
  }
}

extension AccountSetting {
  static let forkHomeSectionsVersion = 2

  public var needsForkHomeSectionsMigration: Bool {
    (_forkHomeSectionsVersion ?? 0) < Self.forkHomeSectionsVersion
  }

  /// Runs once per account: adds the fork sections as visible and moves random sections to
  /// the end. Which of the existing sections are visible stays untouched.
  public mutating func migrateForkHomeSections() {
    guard needsForkHomeSectionsMigration else { return }
    let storedVersion = _forkHomeSectionsVersion ?? 0
    if storedVersion < 1 {
      let visible = homeSections
      let order = homeSectionOrder
      homeSections = HomeSection.forkArranged(
        HomeSection.forkTopSections + visible.filter { !HomeSection.forkTopSections.contains($0) }
      )
      homeSectionOrder = HomeSection.forkArranged(order)
    }
    for step in HomeSection.forkAddedSections where storedVersion < step.version {
      homeSections = HomeSection.forkInsertingBeforeRandom(step.sections, into: homeSections)
      homeSectionOrder = HomeSection.forkInsertingBeforeRandom(step.sections, into: homeSectionOrder)
    }
    _forkHomeSectionsVersion = Self.forkHomeSectionsVersion
  }
}
