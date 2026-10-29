//
//  BackendProxy+ForkShare.swift
//  AmperfyKit
//
//  Fork (F-9): the URL the share extension uses to start a YouTube Music download. It is the
//  same `stream.view?id=ytm-<videoId>&format=mp3` request as `forkStartYouTubeDownload`, built
//  for a placeholder video ID that the extension replaces.
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

extension BackendProxy {
  /// Stream URL at the proxy for `ytm-<placeholder>` with the account's credentials (token and
  /// salt), plus the HTTP headers of the account. Only for Subsonic accounts.
  public func forkYouTubeStreamTemplate(
    placeholder: String
  ) async throws -> (url: URL, headers: [String: String]) {
    guard let serverApi = forkSubsonicServerApi else { throw SongpickerError.noProxy }
    let streamUrl = try await serverApi.generateUrl(
      forStreamingPlayableId: YouTubeMusic.playableId(videoId: placeholder),
      maxBitrate: .noLimit,
      formatPreference: .mp3
    )
    return (SongpickerConfig.proxyURL(rewriting: streamUrl), serverApi.httpHeaders)
  }
}
