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
    static var miniPlayerTitle: UIFont { scaled(14, .semibold, .subheadline, maximum: 18) }
    static var miniPlayerSubtitle: UIFont { scaled(12, .regular, .footnote, maximum: 16) }
    static var caption: UIFont { scaled(11, .medium, .caption2) }

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
  }

  // MARK: - Haptics

  static func haptic(_ type: Haptics) {
    let appDelegate = (UIApplication.shared.delegate as! AppDelegate)
    type.vibrate(isHapticsEnabled: appDelegate.storage.settings.user.isHapticsEnabled)
  }
}
