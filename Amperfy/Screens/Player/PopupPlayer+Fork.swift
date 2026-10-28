//
//  PopupPlayer+Fork.swift
//  Amperfy
//
//  Fork: player polish (design phase 5, measure 13).
//  - Matched transition: the player zooms out of the mini player cover and back into it (iPhone).
//  - Lyrics card under the cover, tap opens the full lyrics.
//  - Queue by swiping up on the player instead of the style switch, pull down to get back.
//  The XIBs stay untouched, PopupPlayerVC only calls the hooks below.
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
import CoreMedia
import UIKit

// MARK: - ForkPlayerTransition

@MainActor
enum ForkPlayerTransition {
  static var isActive: Bool { UIDevice.current.userInterfaceIdiom == .phone }

  /// Zoom transition from the mini player cover. Returns false where the sheet stays (iPad, Mac).
  static func prepare(_ player: PopupPlayerVC, sourceView: UIView) -> Bool {
    guard isActive else { return false }
    // the player always opens on the cover, the queue is one swipe away
    player.appDelegate.storage.settings.user.playerDisplayStyle = .large

    let options = UIViewController.Transition.ZoomOptions()
    options.alignmentRectProvider = { context in
      guard let player = context.zoomedViewController as? PopupPlayerVC,
            let target = player.forkZoomTargetView,
            target.window != nil
      else { return nil }
      return target.convert(target.bounds, to: player.view)
    }
    options.interactiveDismissShouldBegin = { [weak player] _ in
      player?.forkAllowsInteractiveDismiss ?? true
    }
    player.preferredTransition = .zoom(options: options) { [weak sourceView] _ in
      sourceView?.window == nil ? nil : sourceView
    }
    player.modalPresentationStyle = .fullScreen
    return true
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  private static let queuePullDistance: CGFloat = 80

  /// Hook at the end of `viewDidLoad`.
  func forkConfigurePlayer() {
    guard ForkPlayerTransition.isActive else { return }
    addCloseGrabber()

    let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(forkSwipedUp))
    swipeUp.direction = .up
    largeCurrentlyPlayingView?.addGestureRecognizer(swipeUp)

    if let stack = largeCurrentlyPlayingView?.upperContainerView.superview as? UIStackView {
      let card = LyricsCardView()
      card.isHidden = true
      card.addTarget(self, action: #selector(forkLyricsCardTapped), for: .touchUpInside)
      stack.addArrangedSubview(card)
    }
    forkReloadLyricsCard()
  }

  var forkLyricsCard: LyricsCardView? {
    (largeCurrentlyPlayingView?.upperContainerView.superview as? UIStackView)?
      .arrangedSubviews.lazy.compactMap { $0 as? LyricsCardView }.first
  }

  private var isQueueShown: Bool {
    appDelegate.storage.settings.user.playerDisplayStyle == .compact
  }

  /// The cover the zoom transition starts from and ends in.
  var forkZoomTargetView: UIView? {
    if isQueueShown {
      return currentlyPlayingTableCell?.artworkImage
    }
    guard let artwork = largeCurrentlyPlayingView?.artworkImage, artwork.alpha > 0.5 else {
      return largeCurrentlyPlayingView
    }
    return artwork
  }

  /// Swiping down closes the player only on the cover, the queue and the lyrics scroll.
  var forkAllowsInteractiveDismiss: Bool {
    !isQueueShown && !appDelegate.storage.settings.user.isPlayerLyricsDisplayed
  }

  // MARK: Queue

  @objc
  private func forkSwipedUp() {
    guard !isQueueShown, !appDelegate.storage.settings.user.isPlayerLyricsDisplayed else { return }
    DS.haptic(.light)
    switchDisplayStyleOptionPersistent()
    controlView?.refreshView()
  }

  /// Pulling the queue down past its top returns to the cover.
  @objc
  func scrollViewWillEndDragging(
    _ scrollView: UIScrollView,
    withVelocity velocity: CGPoint,
    targetContentOffset: UnsafeMutablePointer<CGPoint>
  ) {
    guard ForkPlayerTransition.isActive, scrollView === tableView, isQueueShown else { return }
    let overscroll = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    guard overscroll > Self.queuePullDistance else { return }
    DS.haptic(.light)
    switchDisplayStyleOptionPersistent()
    controlView?.refreshView()
  }

  // MARK: Close grabber

  /// Replaces the grabber of the former sheet: shows that the player closes downwards.
  private func addCloseGrabber() {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "Close Player"
    button.addAction(UIAction { [weak self] _ in self?.closePopupPlayer() }, for: .touchUpInside)
    let capsule = UIView()
    capsule.translatesAutoresizingMaskIntoConstraints = false
    capsule.isUserInteractionEnabled = false
    capsule.backgroundColor = UIColor.label.withAlphaComponent(0.35)
    capsule.layer.cornerRadius = 2.5
    button.addSubview(capsule)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -DS.Space.xs),
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.widthAnchor.constraint(equalToConstant: 64),
      button.heightAnchor.constraint(equalToConstant: 24),
      capsule.centerXAnchor.constraint(equalTo: button.centerXAnchor),
      capsule.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      capsule.widthAnchor.constraint(equalToConstant: 36),
      capsule.heightAnchor.constraint(equalToConstant: 5),
    ])
  }

  // MARK: Lyrics card

  /// Hook: a song starts from the beginning. Loads the lyrics of the current song.
  func forkReloadLyricsCard() {
    guard let card = forkLyricsCard else { return }
    guard isLyricsCardAllowed,
          let song = player.currentlyPlaying?.asSong,
          let account = song.account,
          let lyricsRelFilePath = song.lyricsRelFilePath
    else {
      card.songID = nil
      card.display(lyrics: nil)
      forkRefreshLyricsCard()
      return
    }
    guard card.songID != song.id else {
      forkRefreshLyricsCard()
      return
    }
    card.songID = song.id
    card.display(lyrics: nil)
    forkRefreshLyricsCard()
    Task { @MainActor [weak self] in
      let lyrics = try? await self?.appDelegate.getMeta(account.info).librarySyncer
        .parseLyrics(relFilePath: lyricsRelFilePath)
        .getFirstSyncedLyricsOrUnsyncedAsDefault()
      guard let self, let card = forkLyricsCard, card.songID == song.id else { return }
      card.display(lyrics: lyrics)
      forkRefreshLyricsCard()
    }
  }

  /// Hook: after the large view switched between cover, lyrics and visualizer.
  func forkRefreshLyricsCard() {
    guard let card = forkLyricsCard else { return }
    let isShown = isLyricsCardAllowed && card.hasLyrics &&
      !appDelegate.storage.settings.user.isPlayerLyricsDisplayed
    card.tint(with: artworkGradientColors)
    guard card.isHidden == isShown else { return }
    card.isHidden = !isShown
  }

  /// Hook: playback time for synced lyrics.
  func forkUpdateLyricsCard(time: CMTime) {
    guard let card = forkLyricsCard, !card.isHidden else { return }
    card.update(time: time)
  }

  private var isLyricsCardAllowed: Bool {
    largeCurrentlyPlayingView?.isLyricsButtonAllowedToDisplay ?? false
  }

  @objc
  private func forkLyricsCardTapped() {
    DS.haptic(.light)
    appDelegate.storage.settings.user.isPlayerVisualizerDisplayed = false
    appDelegate.storage.settings.user.isPlayerLyricsDisplayed = true
    largeCurrentlyPlayingView?.display(element: .lyrics)
    controlView?.refreshView()
  }
}
