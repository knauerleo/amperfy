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

  init(client: SongpickerClient = .shared) {
    self.client = client
  }

  public func status(for hit: SongpickerHit) -> YouTubeMusicStatus {
    if pending[hit.videoId] != nil { return .waiting }
    if let job = jobs[hit.videoId] {
      switch job.state {
      case .waiting: return .waiting
      case .downloading: return .downloading
      case .saving: return .saving
      case .done: return .inLibrary
      case .failed: return .failed
      }
    }
    return hit.isInLibrary ? .inLibrary : .online
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
    !pending.isEmpty || !running.isEmpty
  }

  private func startPollingIfNeeded() {
    guard needsPolling, pollTask == nil else { return }
    pollTask = Task { [weak self] in
      while let self, self.needsPolling, !Task.isCancelled {
        await self.poll()
        try? await Task.sleep(for: Self.pollInterval)
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
      dropExpiredPending()
      return
    }
    let changed = newJobs != jobs
    jobs = newJobs

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
