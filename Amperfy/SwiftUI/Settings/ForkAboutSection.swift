//
//  ForkAboutSection.swift
//  Amperfy
//
//  Fork: GPL attribution to the original app, shown on the main settings page.
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

struct ForkAboutSection: View {
  var body: some View {
    SettingsSection(
      content: {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            String(localized: "Based on \(ForkBrand.upstreamName) by \(ForkBrand.upstreamAuthor), licensed under GPLv3", table: "Fork")
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          Link("github.com/BLeeEZ/amperfy", destination: ForkBrand.upstreamURL)
            .font(.footnote)
        }
        .padding(.vertical, 2)
      },
      header: String(localized: "About \(ForkBrand.name)", table: "Fork")
    )
  }
}
