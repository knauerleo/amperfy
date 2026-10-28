//
//  ArtworkColorCache.swift
//  Amperfy
//
//  Fork: extracts dominant artwork colors off the main thread and keeps them in memory,
//  so player, headers and tiles can tint themselves from the cover without stutter.
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

import DominantColors
import UIKit

@MainActor
final class ArtworkColorCache {
  static let shared = ArtworkColorCache()

  private let cache = NSCache<UIImage, NSArray>()

  private init() {
    cache.countLimit = 200
  }

  func cachedColors(for image: UIImage) -> [UIColor]? {
    cache.object(forKey: image) as? [UIColor]
  }

  /// Returns up to `max` dominant colors of the image, computed in the background on first request.
  func colors(for image: UIImage, max: Int = 2) async -> [UIColor]? {
    if let cached = cachedColors(for: image) { return cached }
    guard let cgImage = image.cgImage else { return nil }
    let cgColors = await Task.detached(priority: .userInitiated) {
      try? cgImage.dominantColors(max: max)
    }.value
    guard let cgColors, !cgColors.isEmpty else { return nil }
    let colors = cgColors.map { UIColor(cgColor: $0) }
    cache.setObject(colors as NSArray, forKey: image)
    return colors
  }
}
