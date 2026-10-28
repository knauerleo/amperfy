//
//  ForkSurface.swift
//  Amperfy
//
//  Fork: dark-first surfaces (measure 14). Plain lists sit on `DS.Color.background`
//  (#121212 in dark mode) instead of pure black, cells and headers follow it.
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

// MARK: - ForkSurface

@MainActor
enum ForkSurface {
  /// The Mac keeps the system look next to its sidebar.
  static var isEnabled: Bool {
    #if targetEnvironment(macCatalyst)
      return false
    #else
      return true
    #endif
  }

  static var background: UIColor { isEnabled ? DS.Color.background : .systemBackground }

  /// Background of a plain list cell: transparent, the system highlight while pressed.
  static func listCellBackground(for state: UICellConfigurationState) -> UIBackgroundConfiguration {
    var background = UIBackgroundConfiguration.listPlainCell().updated(for: state)
    if isEnabled, !state.isHighlighted, !state.isSelected {
      background.backgroundColor = .clear
    }
    return background
  }

  /// Sticky section headers need an opaque color, otherwise rows show through.
  static func applyHeaderBackground(_ view: UIView) {
    guard isEnabled, let header = view as? UITableViewHeaderFooterView else { return }
    var background = UIBackgroundConfiguration.listPlainHeaderFooter()
    background.backgroundColor = DS.Color.background
    header.backgroundConfiguration = background
  }
}

// MARK: - BasicTableViewController

extension BasicTableViewController {
  /// All list screens (Library lists, Search, detail pages). Grouped tables keep their style.
  func applyForkSurface() {
    guard ForkSurface.isEnabled, tableView.style == .plain else { return }
    tableView.backgroundColor = DS.Color.background
  }

  override func tableView(
    _ tableView: UITableView,
    willDisplayHeaderView view: UIView,
    forSection section: Int
  ) {
    super.tableView(tableView, willDisplayHeaderView: view, forSection: section)
    guard tableView.style == .plain else { return }
    ForkSurface.applyHeaderBackground(view)
  }
}
