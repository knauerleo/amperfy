//
//  UIImage+MutedArtwork.swift
//  AmperfyKit
//
//  Fork: the stock playlist placeholder is a pre-rendered tile filled with the theme color.
//  Next to real covers it is the loudest thing on screen, so playlists without a cover get a
//  neutral surface with a muted icon instead (dark surface and grey icon in dark mode).
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

extension UIImage {
  // NSCache is thread-safe, getGeneratedArtwork is called from any thread
  nonisolated(unsafe) private static let mutedArtworkCache = NSCache<NSString, UIImage>()

  /// Dynamic image with a light and a dark variant. Image views pick the variant from their
  /// trait collection and switch automatically when the appearance changes.
  /// Dark values match `DS.Color.placeholderSurfaceDark` / `placeholderIconDark` in the app target.
  static func mutedPlaylistArtwork(theme: ThemePreference) -> UIImage {
    let key = "playlist-\(theme.description)" as NSString
    if let cached = mutedArtworkCache.object(forKey: key) { return cached }

    // UIImage.playlist is main actor isolated, this function is not
    let symbol = UIImage(systemName: AmperfyImage.playlist.systemName) ?? UIImage()
    let light = UITraitCollection(userInterfaceStyle: .light)
    let dark = UITraitCollection(userInterfaceStyle: .dark)
    let lightImage = renderMutedArtwork(
      symbol: symbol,
      surface: UIColor(white: 0.90, alpha: 1),
      icon: theme.asColor.resolvedColor(with: light).withAlphaComponent(0.7)
    )
    let darkImage = renderMutedArtwork(
      symbol: symbol,
      surface: UIColor(white: 0.16, alpha: 1),
      icon: UIColor(white: 0.55, alpha: 1)
    )
    let asset = UIImageAsset()
    asset.register(lightImage, with: light)
    asset.register(darkImage, with: dark)
    let image = asset.image(with: UITraitCollection.current)
    mutedArtworkCache.setObject(image, forKey: key)
    return image
  }

  private static func renderMutedArtwork(
    symbol: UIImage,
    surface: UIColor,
    icon: UIColor
  )
    -> UIImage {
    let size = CGSize(width: ArtworkIconSizeType.defaultSize, height: ArtworkIconSizeType.defaultSize)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      surface.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      let glyph = symbol.withTintColor(icon, renderingMode: .alwaysOriginal)
      // same icon share as the original small-icon artwork
      let box = size.width - 2 * ArtworkIconSizeType.small.rawValue
      let aspect = glyph.size.width / max(glyph.size.height, 1)
      let glyphSize = aspect >= 1
        ? CGSize(width: box, height: box / aspect)
        : CGSize(width: box * aspect, height: box)
      glyph.draw(in: CGRect(
        x: (size.width - glyphSize.width) / 2,
        y: (size.height - glyphSize.height) / 2,
        width: glyphSize.width,
        height: glyphSize.height
      ))
    }
  }
}
