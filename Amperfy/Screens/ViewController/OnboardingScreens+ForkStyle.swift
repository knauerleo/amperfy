//
//  OnboardingScreens+ForkStyle.swift
//  Amperfy
//
//  Fork: login, initial sync, library update and the welcome popups in the Drift look (UI-7).
//  Surface `DS.Color.background`, the wave glyph of the splash above the title, fonts from `DS.Font`,
//  progress bar and buttons in the label color instead of system blue. Only the look changes:
//  server URL, authentication, API detection and the sync steps stay as they are.
//  The Mac keeps the original look.
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

// MARK: - ForkOnboardingStyle

@MainActor
enum ForkOnboardingStyle {
  /// The three waves of the app icon and the splash (`LaunchGlyph`, theme blue).
  static func makeWaveGlyph(size: CGFloat) -> UIImageView {
    let imageView = UIImageView(image: UIImage(named: "LaunchGlyph"))
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.isAccessibilityElement = false
    NSLayoutConstraint.activate([
      imageView.widthAnchor.constraint(equalToConstant: size),
      imageView.heightAnchor.constraint(equalToConstant: size),
    ])
    return imageView
  }

  /// Slow breathing while something runs. Off with "Reduce Motion".
  static func breathe(_ view: UIView) {
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    view.alpha = 1
    UIView.animate(
      withDuration: 1.6,
      delay: 0,
      options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction],
      animations: { view.alpha = 0.45 }
    )
  }

  /// Fixed label heights from the storyboard follow the line height of the new font.
  static func setFont(_ font: UIFont, on label: UILabel) {
    label.font = font
    for constraint in label.constraints
      where constraint.firstAttribute == .height && constraint.secondItem == nil {
      constraint.constant = max(constraint.constant, ceil(font.lineHeight))
    }
  }

  static func styleProgress(
    bar: UIProgressView,
    percent: UILabel,
    info: UILabel,
    spinner: UIActivityIndicatorView
  ) {
    bar.progressTintColor = .label
    bar.trackTintColor = UIColor.label.withAlphaComponent(0.15)
    bar.layer.cornerRadius = 2
    bar.clipsToBounds = true
    info.font = DS.Font.cellSubtitle
    info.textColor = .secondaryLabel
    percent.font = DS.Font.cellDuration
    percent.textColor = .secondaryLabel
    spinner.color = .secondaryLabel
  }

  /// Title of the sync/update screen: the one label without an outlet. The glyph sits above it.
  static func styleTitle(in view: UIView, excluding outlets: [UILabel]) {
    guard let title = view.subviews.compactMap({ $0 as? UILabel })
      .first(where: { label in !outlets.contains { $0 === label } }) else { return }
    setFont(DS.Font.onboardingTitle, on: title)
    title.textColor = .label
    let glyph = makeWaveGlyph(size: 72)
    view.addSubview(glyph)
    NSLayoutConstraint.activate([
      glyph.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      glyph.bottomAnchor.constraint(equalTo: title.topAnchor, constant: -DS.Space.m),
    ])
    breathe(glyph)
  }

  /// Pill button in the label color, e.g. "Skip" or "Close".
  static func stylePill(_ button: UIButton, prominent: Bool, title: String? = nil) {
    let text = title ?? button.attributedTitle(for: .normal)?.string ?? button.title(for: .normal)
    button.setAttributedTitle(nil, for: .normal)
    var config: UIButton.Configuration = prominent ? .filled() : .gray()
    config.title = text
    config.cornerStyle = .capsule
    config.baseForegroundColor = prominent ? DS.Color.background : .label
    if prominent { config.baseBackgroundColor = .label }
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = DS.Font.cellTitle.withWeight(.semibold)
      return attributes
    }
    button.configuration = config
    button.backgroundColor = .clear
    button.tintColor = .label
  }
}

extension UIFont {
  fileprivate func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}

// MARK: - LoginVC

extension LoginVC {
  func applyForkStyle(
    _ brand: UILabel,
    _ watermark: UIImageView,
    _ fields: [UITextField],
    _ apiLabel: UILabel
  ) {
    guard ForkSurface.isEnabled else { return }
    view.backgroundColor = DS.Color.background

    brand.font = DS.Font.loginBrand
    brand.adjustsFontForContentSizeCategory = true
    brand.textColor = .label

    // the large app icon behind the form gives way to the wave glyph above the name
    watermark.isHidden = true
    let glyph = ForkOnboardingStyle.makeWaveGlyph(size: 64)
    view.addSubview(glyph)
    NSLayoutConstraint.activate([
      glyph.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      glyph.bottomAnchor.constraint(equalTo: brand.topAnchor, constant: -DS.Space.xs),
    ])

    for field in fields {
      field.font = DS.Font.cellTitle
      field.adjustsFontForContentSizeCategory = true
      field.borderStyle = .none
      field.layer.borderWidth = 0
      field.layer.cornerRadius = DS.Radius.medium
      field.backgroundColor = DS.Color.surfaceRaised
      field.tintColor = .label
      field.leftView?.subviews.forEach { $0.tintColor = .secondaryLabel }
      field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: DS.Space.s, height: 1))
      field.rightViewMode = .always
    }

    apiLabel.font = DS.Font.cellTitle
    apiLabel.adjustsFontForContentSizeCategory = true
    apiLabel.textColor = .secondaryLabel
  }
}

// MARK: - SyncVC

extension SyncVC {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    view.backgroundColor = DS.Color.background
    ForkOnboardingStyle.styleTitle(in: view, excluding: [progressLabel, progressInfo])
    ForkOnboardingStyle.styleProgress(
      bar: progressBar,
      percent: progressLabel,
      info: progressInfo,
      spinner: activitySpinner
    )
    ForkOnboardingStyle.stylePill(skipButton, prominent: false, title: "Skip")
  }
}

// MARK: - UpdateVC

extension UpdateVC {
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    view.backgroundColor = DS.Color.background
    ForkOnboardingStyle.styleTitle(in: view, excluding: [progressLabel, progressInfo])
    ForkOnboardingStyle.styleProgress(
      bar: progressBar,
      percent: progressLabel,
      info: progressInfo,
      spinner: activitySpinner
    )
  }
}

// MARK: - LibrarySyncPopupVC

extension LibrarySyncPopupVC {
  /// Card on `DS.Color.surfaceRaised` instead of system blue, icon on the theme color.
  func applyForkStyle() {
    guard ForkSurface.isEnabled else { return }
    contentView.backgroundColor = DS.Color.surfaceRaised
    contentView.layer.cornerRadius = 20
    iconBackgroundLabel.backgroundColor = appDelegate.storage.settings.accounts.getSetting(nil).read
      .themePreference.asColor

    ForkOnboardingStyle.setFont(DS.Font.onboardingTitle, on: titelLabel)
    titelLabel.textColor = .label
    infoLabel.font = DS.Font.cellTitle
    infoLabel.textColor = .secondaryLabel

    // "Close" has no outlet: the other button of the card
    let buttons = contentView.subviews.compactMap { $0 as? UIButton }
    for button in buttons {
      let isClose = button !== optionalButton
      ForkOnboardingStyle.stylePill(button, prominent: isClose)
      for constraint in button.constraints
        where constraint.firstAttribute == .height && constraint.secondItem == nil {
        constraint.constant = 34
      }
    }
  }
}
