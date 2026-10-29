//
//  DesignTokens.swift
//  Amperfy
//
//  Fork: shared typography, spacing and color values for the streaming-style redesign.
//  New screens and fork tweaks read from here instead of hard-coding values.
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

// MARK: - DS

@MainActor
enum DS {
  // MARK: - Spacing

  enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
  }

  // MARK: - Corner radius

  enum Radius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
  }

  // MARK: - Typography

  /// Fixed base sizes that scale with Dynamic Type.
  enum Font {
    static var detailTitle: UIFont { scaled(26, .bold, .title1) }
    static var sectionTitle: UIFont { scaled(22, .bold, .title2) }
    static var rowTitle: UIFont { scaled(16, .medium, .body) }
    static var rowSubtitle: UIFont { scaled(13, .regular, .subheadline) }
    /// List cells have a fixed row height, so their fonts only grow a little with Dynamic Type.
    static var cellTitle: UIFont { scaled(16, .regular, .body, maximum: 19) }
    static var cellSubtitle: UIFont { scaled(13, .regular, .subheadline, maximum: 15) }
    /// Song rows (PlayableTableCell): the title carries the row.
    static var songTitle: UIFont { scaled(16, .semibold, .body, maximum: 19) }
    static var miniPlayerTitle: UIFont { scaled(14, .semibold, .subheadline, maximum: 18) }
    static var miniPlayerSubtitle: UIFont { scaled(12, .regular, .footnote, maximum: 16) }
    static var caption: UIFont { scaled(11, .medium, .caption2) }
    /// Full player (UI-4): grows with Dynamic Type up to a cap the layout still fits.
    static var playerTitle: UIFont { scaled(20, .bold, .title3, maximum: 26) }
    static var playerSubtitle: UIFont { scaled(17, .regular, .body, maximum: 22) }
    static var playerAlbum: UIFont { scaled(15, .regular, .subheadline, maximum: 19) }
    static var playerTime: UIFont {
      UIFontMetrics(forTextStyle: .caption1).scaledFont(
        for: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        maximumPointSize: 16
      )
    }
    /// Compact Home tiles (Recently Played grid) and shelf cells.
    static var tileTitle: UIFont { scaled(13, .semibold, .footnote, maximum: 16) }
    static var shelfTitle: UIFont { scaled(14, .semibold, .subheadline, maximum: 18) }
    static var shelfSubtitle: UIFont { scaled(13, .regular, .footnote, maximum: 16) }

    private static func scaled(
      _ size: CGFloat,
      _ weight: UIFont.Weight,
      _ style: UIFont.TextStyle,
      maximum: CGFloat? = nil
    )
      -> UIFont {
      let base = UIFont.systemFont(ofSize: size, weight: weight)
      let metrics = UIFontMetrics(forTextStyle: style)
      if let maximum {
        return metrics.scaledFont(for: base, maximumPointSize: maximum)
      }
      return metrics.scaledFont(for: base)
    }
  }

  // MARK: - Colors

  enum Color {
    /// Accent for controls on top of artwork colors (player slider, mini player progress).
    static let onArtwork = UIColor.label
    static let onArtworkTrack = UIColor.label.withAlphaComponent(0.25)
    /// Muted surface for generated placeholder artwork in dark mode.
    static let placeholderSurfaceDark = UIColor(white: 0.16, alpha: 1)
    static let placeholderIconDark = UIColor(white: 0.55, alpha: 1)
    /// Dark-first surface levels (measure 14): gray steps instead of pure black in dark mode,
    /// the matching semantic system colors in light mode.
    static let background = dynamic(dark: 0x121212, light: .systemBackground)
    static let surface = dynamic(dark: 0x1E1E1E, light: .secondarySystemBackground)
    static let surfaceRaised = dynamic(dark: 0x2A2A2A, light: .tertiarySystemBackground)
    /// Background of compact tiles and the blocks of skeleton placeholders.
    static let tileSurface = dynamic(dark: 0x1E1E1E, light: .tertiarySystemFill)
    static let skeleton = dynamic(dark: 0x2A2A2A, light: .tertiarySystemFill)
    /// Cover gradient of the Favorite Songs tile (top leading to bottom trailing).
    static let favoritesGradient = [
      UIColor(red: 0.91, green: 0.25, blue: 0.42, alpha: 1),
      UIColor(red: 0.45, green: 0.22, blue: 0.75, alpha: 1),
    ]

    private static func dynamic(dark hex: Int, light: UIColor) -> UIColor {
      let dark = UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
      return UIColor { $0.userInterfaceStyle == .dark ? dark : light.resolvedColor(with: $0) }
    }
  }

  // MARK: - Haptics

  static func haptic(_ type: Haptics) {
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    type.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
  }
}
