//
//  PlayerDurationResolver.swift
//  AmperfyKit
//
//  Fork (TASKS F-18): the duration of the playing song is always known. AudioStreaming computes
//  it from the content length of the stream, which the YouTube Music proxy (chunked MP3) and
//  some transcoded streams don't send, so the player showed 0:00 / --:-- and the lock screen had
//  no progress. Then the duration from Core Data is shown, for placeholders the one of the
//  YouTube Music result. If neither knows it, `getSong` asks the server (the proxy for `ytm-`
//  songs) when the song starts, also without an open player, and stores it.
//  A duration from the stream always wins. Seeking stays off while only the fallback is known:
//  AudioStreaming can't seek a stream without length and would close it.
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

import CoreMedia
import Foundation

// MARK: - PlayerDurationResolver

@MainActor
final class PlayerDurationResolver {
  /// Strong reference, the player keeps its notifiers weak.
  private static var installed: PlayerDurationResolver?
  /// Durations of YouTube Music results by song ID, the hit store decodes JSON on every read.
  private static var hitDurations = [String: Double]()

  private let musicPlayer: AudioPlayer
  private let storage: PersistentStorage
  private let getBackendApiCB: @MainActor (AccountInfo) -> BackendProxy
  /// Song IDs already asked for in this session, a server without a duration is asked once.
  private var requestedIds = Set<String>()

  private init(
    musicPlayer: AudioPlayer,
    storage: PersistentStorage,
    getBackendApiCB: @escaping @MainActor (AccountInfo) -> BackendProxy
  ) {
    self.musicPlayer = musicPlayer
    self.storage = storage
    self.getBackendApiCB = getBackendApiCB
  }

  static func install(
    musicPlayer: AudioPlayer,
    storage: PersistentStorage,
    getBackendApiCB: @escaping @MainActor (AccountInfo) -> BackendProxy
  ) {
    let resolver = PlayerDurationResolver(
      musicPlayer: musicPlayer,
      storage: storage,
      getBackendApiCB: getBackendApiCB
    )
    installed = resolver
    musicPlayer.addNotifier(notifier: resolver)
  }

  /// Duration to show: the one of the stream, otherwise the stored one of `playable`.
  static func displayDuration(stream: Double, of playable: AbstractPlayable?) -> Double {
    if stream.isFinite, stream > 0 { return stream }
    return knownDuration(of: playable)
  }

  static func knownDuration(of playable: AbstractPlayable?) -> Double {
    guard let playable, !playable.isRadio else { return 0 }
    if playable.duration > 0 { return Double(playable.duration) }
    guard playable.isYouTubeMusicPlaceholder else { return 0 }
    if let cached = hitDurations[playable.id] { return cached }
    let videoId = String(playable.id.dropFirst(YouTubeMusic.idPrefix.count))
    let duration = Double(YouTubeMusicHitStore.shared.hit(forVideoId: videoId)?.duration ?? 0)
    if duration > 0 { hitDurations[playable.id] = duration }
    return duration
  }

  private func resolveCurrentSong() {
    guard let song = musicPlayer.currentlyPlaying?.asSong,
          song.duration == 0,
          let account = song.account
    else { return }
    // a placeholder knows its duration from the YouTube Music result
    let hitDuration = Self.knownDuration(of: song)
    if hitDuration > 0 {
      store(duration: Int(hitDuration), for: song)
      return
    }
    guard storage.settings.user.isOnlineMode,
          !requestedIds.contains(song.id),
          let serverApi = getBackendApiCB(account.info).forkSubsonicServerApi
    else { return }
    requestedIds.insert(song.id)
    let songId = song.id
    Task { @MainActor in
      guard let response = try? await serverApi.requestSongInfo(id: songId),
            let duration = SongDurationParser.duration(in: response.data),
            duration > 0,
            song.id == songId, song.duration == 0
      else { return }
      store(duration: duration, for: song)
    }
  }

  private func store(duration: Int, for song: Song) {
    song.remoteDuration = duration
    storage.main.saveContext()
    if song.id == musicPlayer.currentlyPlaying?.id {
      musicPlayer.notifyNowPlayingInfoChanged()
      musicPlayer.notifyElapsedTimeChanged()
    }
  }
}

// MARK: MusicPlayable

extension PlayerDurationResolver: MusicPlayable {
  func didStartPlayingFromBeginning() {}
  func didStartPlaying() { resolveCurrentSong() }
  func didPause() {}
  func didStopPlaying() {}
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}
}

// MARK: - SongDurationParser

/// Only the `duration` attribute of the first `song` in a `getSong` response, the song itself
/// is already in the library (placeholders must not run through the full parser again).
private final class SongDurationParser: NSObject, XMLParserDelegate {
  private var duration: Int?

  static func duration(in data: Data) -> Int? {
    let delegate = SongDurationParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.parse()
    return delegate.duration
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    guard elementName == "song" else { return }
    duration = attributeDict["duration"].flatMap { Int($0) }
    parser.abortParsing()
  }
}

// MARK: - BackendAudioPlayer

extension BackendAudioPlayer {
  /// Seeking needs a stream with known length (a cached file always has one).
  var forkCanSeek: Bool {
    duration.isFinite && duration > 0
  }
}
