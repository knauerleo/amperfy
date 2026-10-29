//
//  PopupPlayer+Fork.swift
//  Amperfy
//
//  Fork: player polish (design phase 5, measure 13).
//  - Matched transition: the player zooms out of the mini player cover and back into it (iPhone).
//  - The player scrolls as one page: cover and controls first, the lyrics card right below
//    (it peeks out at the lower edge), tap opens the lyrics in full screen (UI-27). The queue opens only with its button, pull down to get back.
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
    // the player always opens on the cover, the queue is one tap away
    player.appDelegate.storage.settings.user.playerDisplayStyle = .large
    // UI-27: lyrics open in full screen, the old lyrics over the cover would hide the card
    player.appDelegate.storage.settings.user.isPlayerLyricsDisplayed = false
    player.modalPresentationStyle = .fullScreen

    // UI-10: with Reduce Motion the player fades in instead of zooming out of the cover
    if UIAccessibility.isReduceMotionEnabled {
      player.preferredTransition = nil
      player.modalTransitionStyle = .crossDissolve
      return true
    }
    player.modalTransitionStyle = .coverVertical

    let options = UIViewController.Transition.ZoomOptions()
    options.alignmentRectProvider = { context in
      guard let player = context.zoomedViewController as? PopupPlayerVC,
            let target = player.forkZoomTargetView,
            target.window != nil
      else { return nil }
      return target.convert(target.bounds, to: player.view)
    }
    // UI-27: only a swipe down closes, a swipe up scrolls to the lyrics card
    options.interactiveDismissShouldBegin = { [weak player] context in
      context.velocity.dy > 0 && (player?.forkAllowsInteractiveDismiss ?? true)
    }
    player.preferredTransition = .zoom(options: options) { [weak sourceView] _ in
      sourceView?.window == nil ? nil : sourceView
    }
    return true
  }
}

// MARK: - PopupPlayerVC

extension PopupPlayerVC {
  private static let queuePullDistance: CGFloat = 80

  /// Hook at the end of `viewDidLoad`.
  func forkConfigurePlayer() {
    guard ForkPlayerTransition.isActive else { return }

    // Cover and controls move into a page that scrolls down to the lyrics card.
    // The queue table stays outside, its bottom still follows the controls.
    let page = PlayerPageScrollView(
      header: forkMakeNowPlayingHeader(),
      coverView: largePlayerPlaceholderView,
      controlView: controlPlaceholderView,
      rootView: view,
      above: backgroundImage
    )
    page.delegate = self
    page.card.addTarget(self, action: #selector(forkLyricsCardTapped), for: .touchUpInside)
    // UI-21: the transport row got more room (UI-27b: minus the option row)
    controlPlaceholderHeightConstraint.constant += PlayerControlView.forkStreamingExtraHeight
    // UI-27: the queue ends where the controls start on the first page, at a fixed line of the root
    // view. Tied to the controls inside the page it held the page in place and nothing scrolled.
    tableView.bottomAnchor.constraint(
      equalTo: view.layoutMarginsGuide.bottomAnchor,
      constant: -controlPlaceholderHeightConstraint.constant
    ).isActive = true
    // UI-27: the queue starts below the header (the XIB puts it 20 pt below the top margin, where the header is)
    view.constraints.first { $0.firstItem === tableView && $0.firstAttribute == .top }?.constant +=
      PlayerNowPlayingHeaderView.height + PlayerPageScrollView.coverTopMargin

    forkInstallSleepTimerChip()
    forkInstallAnimatedBackground()
    forkReloadLyricsCard()
  }

  var forkPlayerPage: PlayerPageScrollView? {
    view.subviews.lazy.compactMap { $0 as? PlayerPageScrollView }.first
  }

  var forkLyricsCard: LyricsCardView? {
    forkPlayerPage?.card
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

  /// Swiping down closes the player only at the top of the page, the queue and the lyrics scroll.
  var forkAllowsInteractiveDismiss: Bool {
    !isQueueShown && !appDelegate.storage.settings.user.isPlayerLyricsDisplayed &&
      (forkPlayerPage?.isAtTop ?? true)
  }

  // MARK: Queue

  /// Hook at the end of `changeDisplayStyleVisually`: the queue needs the page at its top.
  func forkDisplayStyleChanged() {
    forkRefreshLyricsCard()
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

  /// UI-10: the VoiceOver escape gesture (two-finger Z) closes the full-screen player.
  override func accessibilityPerformEscape() -> Bool {
    guard ForkPlayerTransition.isActive else { return super.accessibilityPerformEscape() }
    closePopupPlayer()
    return true
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
  /// Also runs after the song info was synced (`refresh`), when the lyrics file may just have arrived.
  func forkRefreshLyricsCard() {
    largeCurrentlyPlayingView?.forkRefreshLyricsBackdrop(colors: artworkGradientColors)
    guard let card = forkLyricsCard else { return }
    // UI-27: the first play of a song syncs its lyrics only after the card asked, load them now
    if isLyricsCardAllowed, let song = player.currentlyPlaying?.asSong, song.id != card.songID,
       song.lyricsRelFilePath != nil {
      forkReloadLyricsCard()
      return
    }
    if let fullScreen = presentedViewController as? LyricsFullScreenVC,
       let lyrics = card.shownLyrics, fullScreen.songID != card.songID {
      fullScreen.show(lyrics: lyrics, songID: card.songID)
    }
    let isShown = isLyricsCardAllowed && card.hasLyrics && !isQueueShown &&
      !appDelegate.storage.settings.user.isPlayerLyricsDisplayed
    card.tint(with: artworkGradientColors)
    forkPlayerPage?.setCardShown(isShown)
  }

  /// Hook in `applyGradientBackground`: surfaces that follow the cover color.
  func forkApplyArtworkColors() {
    forkLyricsCard?.tint(with: artworkGradientColors)
    largeCurrentlyPlayingView?.forkLyricsBackdrop?.tint(with: artworkGradientColors)
    forkAnimatedBackground?.setColors(artworkGradientColors)
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
    forkShowFullScreenLyrics()
  }

  /// UI-27: the lyrics of the card in full screen.
  func forkShowFullScreenLyrics() {
    guard let card = forkLyricsCard, let lyrics = card.shownLyrics, presentedViewController == nil
    else { return }
    let fullScreen = LyricsFullScreenVC(lyrics: lyrics, songID: card.songID, colors: artworkGradientColors)
    present(fullScreen, animated: true)
  }

  /// Hook in `createPlayerOptionsMenu`: one entry that opens the full-screen lyrics, instead of
  /// showing and hiding the lyrics over the cover. Nothing when the song has no lyrics.
  func forkAppendFullScreenLyricsAction(to menuActions: inout [UIMenuElement]) {
    guard forkLyricsCard?.shownLyrics != nil else { return }
    menuActions.append(UIAction(title: "Show Lyrics", image: .lyrics) { [weak self] _ in
      self?.forkShowFullScreenLyrics()
    })
  }
}
