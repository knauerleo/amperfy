//
//  PlaylistBarButtons+Fork.swift
//  Amperfy
//
//  Fork (UI-18): one "…" button in the navigation bar of the playlist screens on the iPhone.
//  "Edit" moves into its menu instead of sitting next to it. iPad and Mac keep both buttons.
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

// MARK: - ForkEditMenu

@MainActor
enum ForkEditMenu {
  private static let groupIdentifier = UIMenu.Identifier("drift.fork.edit")

  /// Puts "Edit" as the first, inline group into the menu of `options`. Calling it again
  /// replaces the group instead of adding a second one.
  static func merge(
    into options: UIBarButtonItem,
    isEnabled: Bool,
    handler: @escaping () -> ()
  ) {
    let edit = UIAction(
      title: String(localized: "Edit", table: "Fork"),
      image: UIImage(systemName: "pencil"),
      attributes: isEnabled ? [] : .disabled
    ) { _ in handler() }
    let group = UIMenu(identifier: groupIdentifier, options: .displayInline, children: [edit])
    let rest = (options.menu?.children ?? []).filter {
      ($0 as? UIMenu)?.identifier != groupIdentifier
    }
    options.menu = UIMenu(children: [group] + rest)
  }

  /// Offline there is no "Edit": takes the group out of a menu that got it earlier.
  static func remove(from options: UIBarButtonItem) {
    guard let children = options.menu?.children,
          children.contains(where: { ($0 as? UIMenu)?.identifier == groupIdentifier })
    else { return }
    options.menu = UIMenu(children: children.filter {
      ($0 as? UIMenu)?.identifier != groupIdentifier
    })
  }
}

// MARK: - PlaylistDetailVC

extension PlaylistDetailVC {
  /// "Edit" opens the edit sheet, like the bar button it replaces.
  func forkMergeEditIntoOptions() {
    guard DS.isPhone, let items = navigationItem.rightBarButtonItems, let options = items.first
    else { return }
    guard items.count == 2 else {
      ForkEditMenu.remove(from: options)
      return
    }
    let edit = items[1]
    ForkEditMenu.merge(into: options, isEnabled: edit.isEnabled) { [weak edit] in
      guard let edit, let action = edit.action else { return }
      UIApplication.shared.sendAction(action, to: edit.target, from: edit, for: nil)
    }
    navigationItem.rightBarButtonItems = [options]
  }
}

// MARK: - PlaylistsVC

extension PlaylistsVC {
  /// "Edit" switches the list into edit mode, "Done" in the bar ends it again.
  func forkMergeEditIntoOptions() {
    guard DS.isPhone, let items = navigationItem.rightBarButtonItems, items.count == 2,
          items[1] === editButtonItem
    else { return }
    if isEditing {
      navigationItem.rightBarButtonItems = [UIBarButtonItem(
        systemItem: .done,
        primaryAction: UIAction { [weak self] _ in
          self?.setEditing(false, animated: true)
          self?.updateRightBarButtonItems()
        }
      )]
      return
    }
    let options = items[0]
    ForkEditMenu.merge(into: options, isEnabled: true) { [weak self] in
      self?.setEditing(true, animated: true)
      self?.updateRightBarButtonItems()
    }
    navigationItem.rightBarButtonItems = [options]
  }
}
