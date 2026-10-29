//
//  MiniPlayerAccessibilityElement.swift
//  Amperfy
//
//  Fork (UI-10): VoiceOver reads the mini player as one element "Now Playing, title, artist".
//  Double tap opens the player, the actions rotor skips forward and back like the swipes.
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

final class MiniPlayerAccessibilityElement: UIAccessibilityElement {
  struct Actions {
    var open: () -> ()
    var next: () -> ()
    var previous: () -> ()
  }

  private weak var titleLabel: UILabel?
  private weak var subtitleLabel: UILabel?
  /// The area in the container that the element covers (cover and labels, not the buttons).
  private let frameProvider: () -> CGRect
  private let actions: Actions

  init(
    container: UIView,
    titleLabel: UILabel,
    subtitleLabel: UILabel,
    frameProvider: @escaping () -> CGRect,
    actions: Actions
  ) {
    self.titleLabel = titleLabel
    self.subtitleLabel = subtitleLabel
    self.frameProvider = frameProvider
    self.actions = actions
    super.init(accessibilityContainer: container)
    accessibilityTraits = [.button, .updatesFrequently]
    accessibilityHint = String(localized: "Opens the player", table: "Fork")
    accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: String(localized: "Skip Forward", table: "Fork")) { _ in
        actions.next()
        return true
      },
      UIAccessibilityCustomAction(name: String(localized: "Skip Back", table: "Fork")) { _ in
        actions.previous()
        return true
      },
      UIAccessibilityCustomAction(name: String(localized: "Open Player", table: "Fork")) { _ in
        actions.open()
        return true
      },
    ]
  }

  override var accessibilityLabel: String? {
    get { String(localized: "Now Playing", table: "Fork") }
    set {}
  }

  override var accessibilityValue: String? {
    get {
      [titleLabel?.text, subtitleLabel?.text]
        .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
    set {}
  }

  override var accessibilityFrameInContainerSpace: CGRect {
    get { frameProvider() }
    set {}
  }

  override func accessibilityActivate() -> Bool {
    actions.open()
    return true
  }
}
