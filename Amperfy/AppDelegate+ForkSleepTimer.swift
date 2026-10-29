//
//  AppDelegate+ForkSleepTimer.swift
//  Amperfy
//
//  Fork (UI-12): the sleep timer fades the volume out over the last 10 seconds
//  instead of pausing hard. Afterwards the volume is restored, so the next play starts normally.
//  Turning the timer off during the fade restores the volume right away.
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
import UIKit

extension AppDelegate {
  /// Hook in `activateSleepTimer`: same timer as before, plus the fade-out before it fires.
  func forkActivateSleepTimer(timeInterval: TimeInterval) {
    sleepTimer?.invalidate()
    let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
      Task { @MainActor in
        self.player.pause()
        self.eventLogger.info(topic: "Sleep Timer", message: "Sleep Timer paused playback.")
        self.sleepTimer?.invalidate()
        self.sleepTimer = nil
        SleepTimerFader.shared.finish()
      }
    }
    sleepTimer = timer
    SleepTimerFader.shared.schedule(for: timer, owner: self)
  }
}

// MARK: - SleepTimerFader

@MainActor
final class SleepTimerFader {
  static let shared = SleepTimerFader()
  static let fadeDuration: TimeInterval = 10
  private static let step: TimeInterval = 0.1

  private var startTimer: Timer?
  private var fadeTimer: Timer?
  private weak var sleepTimer: Timer?
  private weak var owner: AppDelegate?
  private var originalVolume: Float?

  private init() {}

  func schedule(for timer: Timer, owner: AppDelegate) {
    finish()
    sleepTimer = timer
    self.owner = owner
    let delay = max(0, timer.fireDate.timeIntervalSinceNow - Self.fadeDuration)
    startTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
      Task { @MainActor in SleepTimerFader.shared.startFade() }
    }
  }

  /// Stops fading and restores the volume (after the pause, or when the timer was turned off).
  func finish() {
    startTimer?.invalidate()
    startTimer = nil
    fadeTimer?.invalidate()
    fadeTimer = nil
    if let originalVolume, var player = owner?.player {
      player.volume = originalVolume
    }
    originalVolume = nil
  }

  private func startFade() {
    guard let player = owner?.player, isSleepTimerActive else { return finish() }
    originalVolume = player.volume
    fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.step, repeats: true) { _ in
      Task { @MainActor in SleepTimerFader.shared.fadeStep() }
    }
  }

  private func fadeStep() {
    guard var player = owner?.player, let originalVolume,
          let fireDate = sleepTimer?.fireDate, isSleepTimerActive
    else { return finish() }
    let remaining = max(0, fireDate.timeIntervalSinceNow)
    player.volume = originalVolume * Float(min(1, remaining / Self.fadeDuration))
  }

  /// The menu turns the timer off by setting `sleepTimer` to nil. Identity only, because the timer
  /// is already invalid in the moment it fires, before the pause.
  private var isSleepTimerActive: Bool {
    guard let sleepTimer else { return false }
    return sleepTimer === owner?.sleepTimer
  }
}
