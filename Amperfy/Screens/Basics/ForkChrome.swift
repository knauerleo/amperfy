//
//  ForkChrome.swift
//  Amperfy
//
//  Fork (UI-18): navigation and tab bar in the Drift identity, iPhone only. Transparent bars
//  without a hairline (iOS 26 softens the content below them), large titles in SF Pro Rounded,
//  selected tab in the accent. iPad and Mac keep the system bars (UI-16).
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

@MainActor
enum ForkChrome {
  /// Called once at start, before the first navigation controller exists.
  static func applyPhoneAppearance() {
    guard DS.isPhone else { return }

    let navigation = UINavigationBarAppearance()
    navigation.configureWithTransparentBackground()
    navigation.shadowColor = .clear
    navigation.largeTitleTextAttributes = [
      .font: DS.Font.display,
      .foregroundColor: DS.Color.text,
    ]
    navigation.titleTextAttributes = [
      .font: DS.Font.navTitle,
      .foregroundColor: DS.Color.text,
    ]
    let navigationBar = UINavigationBar.appearance()
    navigationBar.standardAppearance = navigation
    navigationBar.scrollEdgeAppearance = navigation
    navigationBar.compactAppearance = navigation
    navigationBar.compactScrollEdgeAppearance = navigation

    // The iOS 26 tab bar is Liquid Glass and carries the mini player as its accessory.
    // A painted background would replace the glass, so only the item colors change.
    let tabBar = UITabBar.appearance()
    tabBar.tintColor = DS.Color.accent
    tabBar.unselectedItemTintColor = DS.Color.text3
  }
}
