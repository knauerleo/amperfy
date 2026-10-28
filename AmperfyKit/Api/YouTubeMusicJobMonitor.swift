//
//  YouTubeMusicJobMonitor.swift
//  AmperfyKit
//
//  Fork: download status of YouTube Music results, by polling `GET /api/jobs` of the Songpicker
//  while a tracked download runs (wartet → lädt → speichert → fertig/fehler).
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
import os.log

// MARK: - YouTubeMusicStatus

public enum YouTubeMusicStatus: Equatable, Sendable {
  /// Only on YouTube Music, plays through the proxy.
  case online
  /// Download requested or waiting on the Pi.
  case waiting
  case downloading
  case saving
  case inLibrary
  case failed

  public var isLoading: Bool {
    self == .waiting || self == .downloading || self == .saving
  }
}

// MARK: - YouTubeMusicJobEntry

/// One Songpicker job for the download overview.
public struct YouTubeMusicJobEntry: Sendable, Hashable {
  public let videoId: String
  public let title: String
  public let artist: String?
  public let thumbURL: URL?
  public let status: YouTubeMusicStatus
  public let error: String?
  public let started: Date?

  public var isRetryable: Bool { status == .failed }
}

extension Notification.Name {
  /// Posted on the main actor whenever the status of at least one video ID changed.
  public static let youTubeMusicStatusChanged =
    Notification.Name(rawValue: "de.knauerleo.amperfy.youTubeMusic.statusChanged")
}

// MARK: - YouTubeMusicJobMonitor

@MainActor
public final class YouTubeMusicJobMonitor {
  public static let shared = YouTubeMusicJobMonitor()

  /// Called once per download that finished while it was tracked (not for old jobs).
  public var onDownloadFinished: ((_ hit: SongpickerHit, _ job: SongpickerJob) -> ())?

  private static let pollInterval: Duration = .milliseconds(1500)
  /// While the overview is visible and nothing loads.
  private static let idlePollInterval: Duration = .seconds(5)
  /// A requested download that does not show up in `/api/jobs` within this time counts as lost.
  private static let pendingTimeout: TimeInterval = 60

  private let client: SongpickerClient
  private let log = OSLog(subsystem: "Amperfy", category: "YouTubeMusic")
  private var jobs = [String: SongpickerJob]()
  private var hits = [String: SongpickerHit]()
  /// Tracked downloads not yet visible in `/api/jobs`: request time and the job seen before,
  /// so an old finished job of the same video does not count as the new one.
  private var pending = [String: (requested: Date, previous: SongpickerJob?)]()
  /// Tracked downloads whose job was seen unfinished, so `fertig` is new.
  private var running = Set<String>()
  private var pollTask: Task<(), Never>?
  /// Visible screens that show the job list (download overview).
  private var observerCount = 0

  init(client: SongpickerClient = .shared) {
    self.client = client
  }

  public func status(for hit: SongpickerHit) -> YouTubeMusicStatus {
    if pending[hit.videoId] != nil { return .waiting }
    if let job = jobs[hit.videoId] {
      return Self.status(of: job.state)
    }
    return hit.isInLibrary ? .inLibrary : .online
  }

  /// All jobs the Songpicker reported, running ones first, then newest first.
  /// Requested downloads that are not yet visible in `/api/jobs` are included as waiting.
  public var jobList: [YouTubeMusicJobEntry] {
    var videoIds = Set(jobs.keys)
    videoIds.formUnion(pending.keys)
    let entries = videoIds.map { videoId -> YouTubeMusicJobEntry in
      let job = pending[videoId] == nil ? jobs[videoId] : nil
      let hit = hits[videoId] ?? YouTubeMusicHitStore.shared.hit(forVideoId: videoId)
      let status: YouTubeMusicStatus
      if let hit {
        status = self.status(for: hit)
      } else if let job {
        status = Self.status(of: job.state)
      } else {
        status = .waiting
      }
      return YouTubeMusicJobEntry(
        videoId: videoId,
        title: hit?.title ?? job?.label ?? videoId,
        artist: hit?.artist,
        thumbURL: hit?.thumbURL,
        status: status,
        error: job?.error,
        started: job?.started ?? pending[videoId]?.requested
      )
    }
    return entries.sorted { lhs, rhs in
      if lhs.status.isLoading != rhs.status.isLoading { return lhs.status.isLoading }
      return (lhs.started ?? .distantPast) > (rhs.started ?? .distantPast)
    }
  }

  /// True after the first successful `/api/jobs` answer.
  public private(set) var hasLoadedJobs = false
  /// Error of the last `/api/jobs` request, `nil` when it worked.
  public private(set) var lastError: String?

  /// The download overview is visible: keeps the job list current until `stopObserving`.
  public func startObserving() {
    observerCount += 1
    if pollTask == nil {
      startPollingIfNeeded()
    }
  }

  public func stopObserving() {
    observerCount = max(0, observerCount - 1)
  }

  /// `POST /api/get` again for a failed job. Uses the result of the search, if it is known,
  /// otherwise the video ID and label of the job.
  public func retry(videoId: String) async throws {
    let hit = hits[videoId]
      ?? YouTubeMusicHitStore.shared.hit(forVideoId: videoId)
      ?? SongpickerHit(dict: [
        "source": "youtube",
        "id": videoId,
        "title": jobs[videoId]?.label ?? videoId,
        "kind": "song",
      ])
    guard let hit else { throw SongpickerError.invalidResponse }
    try await addToLibrary(hit)
  }

  private static func status(of state: SongpickerJobState) -> YouTubeMusicStatus {
    switch state {
    case .waiting: return .waiting
    case .downloading: return .downloading
    case .saving: return .saving
    case .done: return .inLibrary
    case .failed: return .failed
    }
  }

  /// Loads the job list once, e.g. when new results are shown, and keeps polling if needed.
  public func refresh() {
    guard pollTask == nil else { return }
    pollTask = Task { [weak self] in
      await self?.poll()
      guard let self else { return }
      pollTask = nil
      startPollingIfNeeded()
    }
  }

  /// Follows the download of a result, e.g. after it was played through the proxy.
  public func track(_ hit: SongpickerHit) {
    hits[hit.videoId] = hit
    let current = jobs[hit.videoId]
    if current?.state == .done { return }
    if let current, !current.state.isFinished {
      running.insert(hit.videoId)
    } else if pending[hit.videoId] == nil {
      pending[hit.videoId] = (Date(), current)
      postChange()
    }
    startPollingIfNeeded()
  }

  /// `POST /api/get`: downloads the result into the library.
  public func addToLibrary(_ hit: SongpickerHit) async throws {
    hits[hit.videoId] = hit
    pending[hit.videoId] = (Date(), jobs[hit.videoId])
    postChange()
    do {
      try await client.requestDownload(hit: hit)
    } catch {
      pending.removeValue(forKey: hit.videoId)
      postChange()
      throw error
    }
    startPollingIfNeeded()
  }

  private var needsPolling: Bool {
    !pending.isEmpty || !running.isEmpty || observerCount > 0
  }

  private var isAnyJobLoading: Bool {
    !pending.isEmpty || !running.isEmpty || jobs.values.contains { !$0.state.isFinished }
  }

  private func startPollingIfNeeded() {
    guard needsPolling, pollTask == nil else { return }
    pollTask = Task { [weak self] in
      while let self, self.needsPolling, !Task.isCancelled {
        await self.poll()
        let interval = self.isAnyJobLoading ? Self.pollInterval : Self.idlePollInterval
        try? await Task.sleep(for: interval)
      }
      self?.pollTask = nil
    }
  }

  private func poll() async {
    let newJobs: [String: SongpickerJob]
    do {
      newJobs = try await client.jobs()
    } catch {
      os_log("Jobs request failed: %s", log: log, type: .info, error.localizedDescription)
      let hadError = lastError != nil
      lastError = error.localizedDescription
      if dropExpiredPending() || !hadError {
        postChange()
      }
      return
    }
    let changed = newJobs != jobs || !hasLoadedJobs || lastError != nil
    jobs = newJobs
    hasLoadedJobs = true
    lastError = nil

    for (videoId, job) in newJobs {
      if let request = pending[videoId] {
        guard job != request.previous else { continue }
        pending.removeValue(forKey: videoId)
      } else if !running.contains(videoId) {
        continue
      }
      if job.state.isFinished {
        running.remove(videoId)
        if job.state == .done, let hit = hits[videoId] {
          onDownloadFinished?(hit, job)
        }
      } else {
        running.insert(videoId)
      }
    }
    let droppedPending = dropExpiredPending()
    if changed || droppedPending {
      postChange()
    }
  }

  @discardableResult
  private func dropExpiredPending() -> Bool {
    let expired = pending.filter {
      Date().timeIntervalSince($0.value.requested) > Self.pendingTimeout
    }
    expired.keys.forEach { pending.removeValue(forKey: $0) }
    return !expired.isEmpty
  }

  private func postChange() {
    NotificationCenter.default.post(name: .youTubeMusicStatusChanged, object: self)
  }
}
