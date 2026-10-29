//
//  TabBarVC+ForkMiniPlayer.swift
//  Amperfy
//
//  Fork (UI-19): on the iPhone the mini player is a floating card above the tab bar
//  (`FloatingMiniPlayerView`) instead of the glass `bottomAccessory`. iPad keeps the accessory.
//  The tab bar stays put while scrolling, the card hovers above it.
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

extension TabBarVC {
  var forkFloatingMiniPlayer: FloatingMiniPlayerView? {
    view.subviews.first { $0 is FloatingMiniPlayerView } as? FloatingMiniPlayerView
  }

  /// The accessory layout (`configureTraitChangesForMiniPlayer`) is skipped once the card is in place.
  var forkUsesFloatingMiniPlayer: Bool { forkFloatingMiniPlayer != nil }

  /// Takes the mini player out of the accessory glass and puts it into the card.
  func forkInstallFloatingMiniPlayer() {
    guard DS.isPhone, let miniPlayer else { return }
    bottomAccessory = nil
    tabBarMinimizeBehavior = .never
    miniPlayer.removeFromSuperview()

    let card = FloatingMiniPlayerView(miniPlayer: miniPlayer, player: appDelegate.player)
    card.alpha = card.hasSong ? 1 : 0
    card.visibilityChanged = { [weak self] in self?.forkLayoutFloatingMiniPlayer(animated: true) }
    view.insertSubview(card, belowSubview: tabBar)
    miniPlayer.forkConfigureAsFloatingCard()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    forkLayoutFloatingMiniPlayer(animated: false)
  }

  /// The inset on the tab's navigation controller does not reach every pushed page (the album
  /// page kept its last rows under the card), so a page also ends above the card on its own:
  /// its safe area is topped up to the card's top edge plus the gap. Returns false without card.
  func forkApplyMiniPlayerInset(to viewController: UIViewController) -> Bool {
    guard let card = forkFloatingMiniPlayer, viewController.isViewLoaded else { return false }
    let page = viewController.view!
    var extra: CGFloat = 0
    if card.hasSong, page.window != nil {
      let cardTop = page.convert(card.frame, from: view).minY
      let needed = page.bounds.maxY - cardTop + FloatingMiniPlayerView.bottomGap
      let base = page.safeAreaInsets.bottom - viewController.additionalSafeAreaInsets.bottom
      extra = max(0, needed - base)
    }
    if viewController.additionalSafeAreaInsets.bottom != extra {
      viewController.additionalSafeAreaInsets.bottom = extra
    }
    return true
  }

  /// Card 8 pt above the tab bar. Without a song the card hides.
  func forkLayoutFloatingMiniPlayer(animated: Bool) {
    guard let card = forkFloatingMiniPlayer else { return }
    // after the card has its new frame (UIView.animate sets it right away)
    defer {
      for child in viewControllers ?? [] {
        if let top = (child as? UINavigationController)?.topViewController {
          _ = forkApplyMiniPlayerInset(to: top)
        }
      }
    }
    let height = FloatingMiniPlayerView.height
    let margin = FloatingMiniPlayerView.sideMargin
    let tabBarVisible = !tabBar.isHidden && tabBar.alpha > 0.01 && tabBar.frame.minY < view.bounds.maxY
    let bottom = tabBarVisible ?
      tabBar.frame.minY - FloatingMiniPlayerView.bottomGap :
      view.bounds.maxY - view.safeAreaInsets.bottom - FloatingMiniPlayerView.bottomGap
    let frame = CGRect(
      x: view.safeAreaInsets.left + margin,
      y: bottom - height,
      width: view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 2 * margin,
      height: height
    )
    let hasSong = card.hasSong

    // the content of every tab ends above the card
    let inset = hasSong ? height + FloatingMiniPlayerView.bottomGap : 0
    for child in viewControllers ?? [] where child.additionalSafeAreaInsets.bottom != inset {
      child.additionalSafeAreaInsets.bottom = inset
    }

    let apply = {
      card.frame = frame
      card.alpha = hasSong ? 1 : 0
    }
    card.isUserInteractionEnabled = hasSong
    guard animated, card.frame != frame || card.alpha != (hasSong ? 1 : 0) else {
      if !animated { apply() }
      return
    }
    UIView.animate(
      withDuration: 0.3,
      delay: 0,
      usingSpringWithDamping: 0.9,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction],
      animations: apply
    )
  }
}
