//
//  NeutralAccentSettingsSection.swift
//  Amperfy
//
//  Fork: Settings › Display › "Neutral Accent" (measure 14).
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

import AmperfyKit
import SwiftUI

struct NeutralAccentSettingsSection: View {
  @State
  private var isNeutralAccent = false

  var body: some View {
    SettingsSection(
      content: {
        SettingsCheckBoxRow(
          title: "Neutral Accent",
          isOn: Binding<Bool>(
            get: { isNeutralAccent },
            set: { newValue in
              isNeutralAccent = newValue
              apply(isNeutral: newValue)
            }
          )
        )
      },
      footer:
      "Use white (Dark) or black (Light) for buttons and highlights instead of the theme color. Colors from the artwork stay."
    )
    .onAppear {
      isNeutralAccent = appDelegate.storage.settings.user.isNeutralAccent
    }
  }

  private func apply(isNeutral: Bool) {
    appDelegate.storage.settings.user.isNeutralAccent = isNeutral
    ForkAccent.isNeutral = isNeutral
    let theme = appDelegate.storage.settings.accounts
      .getSetting(appDelegate.storage.settings.accounts.active).read.themePreference
    appDelegate.setAppTheme(color: theme.asColor)
    appDelegate.applyAppThemeToAlreadyLoadedViews()
  }
}
