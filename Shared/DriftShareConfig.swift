//
//  DriftShareConfig.swift
//  Drift (app and share extension)
//
//  Fork (F-9): what the share extension needs to start a YouTube Music download through the
//  Subsonic proxy at the login host. The app keeps the stream URL of the active account (with a
//  placeholder video ID, token and salt instead of the password) in a keychain group shared with
//  the extension. Also the parsing of shared YouTube / YouTube Music links.
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

import Foundation
import Security

// MARK: - DriftShareConfig

struct DriftShareConfig: Codable, Equatable, Sendable {
  /// Replaced by the video ID in `streamURLTemplate`.
  static let placeholder = "DRIFTSHAREVIDEOID"
  /// Keychain group in both entitlements, `$(AppIdentifierPrefix)` is the team ID.
  static let keychainGroup = "45L48D96FZ.de.knauerleo.amperfy-music.shared"
  private static let keychainService = "de.knauerleo.amperfy-music.share"
  private static let keychainAccount = "config"

  /// `…/rest/stream.view?id=ytm-DRIFTSHAREVIDEOID&format=mp3&u=…&t=…&s=…`
  var streamURLTemplate: String
  var headers: [String: String]
  /// Host shown in the extension, e.g. "musik.leokna.de".
  var serverName: String

  func streamURL(videoId: String) -> URL? {
    URL(string: streamURLTemplate.replacingOccurrences(of: Self.placeholder, with: videoId))
  }

  // MARK: Keychain

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessGroup as String: keychainGroup,
    ]
  }

  static func load() -> DriftShareConfig? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(DriftShareConfig.self, from: data)
  }

  @discardableResult
  func save() -> Bool {
    guard let data = try? JSONEncoder().encode(self) else { return false }
    let update: [String: Any] = [
      kSecValueData as String: data,
      // the extension runs while the phone is unlocked anyway
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(Self.baseQuery as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      let add = Self.baseQuery.merging(update) { $1 }
      status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess
  }

  static func remove() {
    SecItemDelete(baseQuery as CFDictionary)
  }
}

// MARK: - YouTubeShareLink

enum YouTubeShareLink {
  /// Video ID of a YouTube or YouTube Music link: `music.youtube.com/watch?v=…`,
  /// `youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`.
  static func videoId(from url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let host = components.host?.lowercased()
    else { return nil }
    let path = url.pathComponents.filter { $0 != "/" }
    var candidate: String?
    if host == "youtu.be" || host.hasSuffix(".youtu.be") {
      candidate = path.first
    } else if host == "youtube.com" || host.hasSuffix(".youtube.com") ||
      host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") {
      if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
        candidate = v
      } else if path.count >= 2, ["shorts", "live", "embed", "v"].contains(path[0]) {
        candidate = path[1]
      }
    }
    guard let candidate, isValidVideoId(candidate) else { return nil }
    return candidate
  }

  /// First YouTube link in a shared text, e.g. "Song – Artist https://music.youtube.com/…".
  static func videoId(fromText text: String) -> String? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    for match in detector.matches(in: text, options: [], range: range) {
      if let url = match.url, let id = videoId(from: url) { return id }
    }
    return nil
  }

  static func isValidVideoId(_ id: String) -> Bool {
    id.count == 11 && id.allSatisfy {
      ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_"
    }
  }
}
