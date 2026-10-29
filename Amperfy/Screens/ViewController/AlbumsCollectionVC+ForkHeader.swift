//
//  AlbumsCollectionVC+ForkHeader.swift
//  Amperfy
//
//  Fork (TASKS UI-24): head of the album grid as in the mockup, iPhone only and only in
//  "All Albums". Filter chips "Recently Added", "Favorites", "Downloaded" and the play row of
//  UI-25 above the grid, the count under the large title, sort and filter at the top right.
//  The chips use the existing filters: `displayFilter` (.newest, .favorites) and the "Cached"
//  search scope. The grid of UI-2 stays.
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

// MARK: - ForkAlbumChip

enum ForkAlbumChip: CaseIterable {
  case newest
  case favorites
  case cached

  var title: String {
    switch self {
    case .newest: String(localized: "Recently Added", table: "Fork")
    case .favorites: String(localized: "Favorites", table: "Fork")
    case .cached: String(localized: "Downloaded", table: "Fork")
    }
  }
}

// MARK: - ForkAlbumChipsView

/// Round chips in one scrolling row. Active chips in the accent, the others raised.
final class ForkAlbumChipsView: UIView {
  static let chipHeight: CGFloat = 34

  var onTap: ((ForkAlbumChip) -> ())?
  private var buttons = [ForkAlbumChip: UIButton]()

  override init(frame: CGRect) {
    super.init(frame: frame)
    let scrollView = UIScrollView()
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.alwaysBounceHorizontal = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)

    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = DS.Space.xs
    row.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(row)

    for chip in ForkAlbumChip.allCases {
      let button = UIButton(type: .system)
      button.addAction(UIAction { [weak self] _ in
        DS.haptic(.light)
        self?.onTap?(chip)
      }, for: .touchUpInside)
      button.heightAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true
      buttons[chip] = button
      row.addArrangedSubview(button)
    }

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      row.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: DS.Space.m),
      row.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -DS.Space.m),
      row.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])
    update(active: [])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(active: Set<ForkAlbumChip>) {
    for (chip, button) in buttons {
      let isActive = active.contains(chip)
      var config = UIButton.Configuration.filled()
      config.title = chip.title
      config.baseBackgroundColor = isActive ? DS.Color.accent : DS.Color.surfaceRaised
      config.baseForegroundColor = isActive ? DS.Color.onAccent : DS.Color.text
      config.cornerStyle = .capsule
      config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var attributes = $0
        attributes.font = DS.Font.shelfTitle
        return attributes
      }
      button.configuration = config
      button.accessibilityTraits = isActive ? [.button, .selected] : .button
    }
  }
}

// MARK: - ForkAlbumsListHeaderView

/// Chips and play row, placed in the first section header of the grid.
final class ForkAlbumsListHeaderView: UIView {
  static let headerTag = 0x4624

  static var height: CGFloat {
    DS.Space.xs + ForkAlbumChipsView.chipHeight + ListPlayHeaderView.frameHeight
  }

  let chipsView = ForkAlbumChipsView()
  private let playRow: ListPlayHeaderView

  init(width: CGFloat, configuration: PlayShuffleInfoConfiguration, titleOwner: UIViewController) {
    playRow = ListPlayHeaderView.makeView(
      configuration: configuration,
      titleOwner: titleOwner,
      width: width
    )
    super.init(frame: CGRect(x: 0, y: 0, width: width, height: Self.height))
    tag = Self.headerTag
    autoresizingMask = [.flexibleWidth]
    chipsView.frame = CGRect(x: 0, y: DS.Space.xs, width: width, height: ForkAlbumChipsView.chipHeight)
    chipsView.autoresizingMask = [.flexibleWidth]
    playRow.frame = CGRect(
      x: 0,
      y: chipsView.frame.maxY,
      width: width,
      height: ListPlayHeaderView.frameHeight
    )
    playRow.autoresizingMask = [.flexibleWidth]
    addSubview(chipsView)
    addSubview(playRow)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func refresh(active: Set<ForkAlbumChip>) {
    chipsView.update(active: active)
    playRow.refresh()
  }
}

// MARK: - ForkAlbumsHeaderState

@MainActor
private enum ForkAlbumsHeaderState {
  /// Decided once per screen: the chips belong to "All Albums" and stay after a chip changes the filter.
  static let usesHeader = NSMapTable<AlbumsCollectionVC, NSNumber>.weakToStrongObjects()
}

// MARK: - AlbumsCollectionVC

extension AlbumsCollectionVC {
  /// iPhone and "All Albums" when the screen was opened.
  var forkUsesListHeader: Bool {
    if let decided = ForkAlbumsHeaderState.usesHeader.object(forKey: self) {
      return decided.boolValue
    }
    let uses = DS.isPhone && displayFilter == .all
    ForkAlbumsHeaderState.usesHeader.setObject(NSNumber(value: uses), forKey: self)
    return uses
  }

  var forkListHeaderHeight: CGFloat? {
    forkUsesListHeader ? ForkAlbumsListHeaderView.height : nil
  }

  private var forkActiveChips: Set<ForkAlbumChip> {
    var active = Set<ForkAlbumChip>()
    if displayFilter == .newest { active.insert(.newest) }
    if displayFilter == .favorites { active.insert(.favorites) }
    if searchController.searchBar.isCachedScopeSelected { active.insert(.cached) }
    return active
  }

  private var forkCountText: String {
    let count = common.fetchedResultsController.fetchedObjects?.count ?? 0
    return count == 1 ?
      String(localized: "1 Album", table: "Fork") :
      String(localized: "\(count) Albums", table: "Fork")
  }

  /// Puts chips and play row into the first section header. False: keep the upstream header.
  func forkInstallListHeader(in sectionHeader: CommonCollectionSectionHeader) -> Bool {
    guard forkUsesListHeader else { return false }
    sectionHeader.forkRemoveListHeader()
    var config = common.createPlayShuffleInfoConfig()
    config.infoCB = { [weak self] in self?.forkCountText ?? "" }
    let header = ForkAlbumsListHeaderView(
      width: collectionView.bounds.width,
      configuration: config,
      titleOwner: self
    )
    header.chipsView.onTap = { [weak self] chip in self?.forkToggle(chip: chip) }
    header.refresh(active: forkActiveChips)
    sectionHeader.addSubview(header)
    // `applyFilter` sets the English filter title, the chips keep "Albums"
    setNavBarTitle(title: String(localized: "Albums", table: "Fork"))
    return true
  }

  /// After the fetched albums changed: count under the title, chips of the visible header.
  func forkRefreshListHeader() {
    guard forkUsesListHeader else { return }
    if #available(iOS 26.0, *) {
      navigationItem.largeSubtitle = forkCountText
    }
    let sectionHeader = collectionView.supplementaryView(
      forElementKind: UICollectionView.elementKindSectionHeader,
      at: IndexPath(item: 0, section: 0)
    )
    (sectionHeader?.viewWithTag(ForkAlbumsListHeaderView.headerTag) as? ForkAlbumsListHeaderView)?
      .refresh(active: forkActiveChips)
  }

  /// Sort and filter instead of the single "…". Nil: keep the upstream button.
  func forkBarButtons(menus: [UIMenu]) -> [UIBarButtonItem]? {
    guard forkUsesListHeader else { return nil }
    let sortMenu = menus.first { $0.title == "Sort" }
    let otherMenus = menus.filter { $0 !== sortMenu }

    let filters: [(String, DisplayCategoryFilter)] = [
      (String(localized: "All", table: "Fork"), .all),
      (ForkAlbumChip.newest.title, .newest),
      (String(localized: "Recently Played", table: "Fork"), .recent),
      (ForkAlbumChip.favorites.title, .favorites),
    ]
    let filterActions = filters.map { title, filter in
      UIAction(title: title, state: displayFilter == filter ? .on : .off) { [weak self] _ in
        self?.forkApply(filter: filter)
      }
    }
    let cachedAction = UIAction(
      title: ForkAlbumChip.cached.title,
      state: searchController.searchBar.isCachedScopeSelected ? .on : .off
    ) { [weak self] _ in
      self?.forkToggle(chip: .cached)
    }
    let filterMenu = UIMenu(children: [
      UIMenu(options: .displayInline, children: filterActions),
      UIMenu(options: .displayInline, children: [cachedAction]),
    ] + otherMenus)

    let filterItem = UIBarButtonItem(
      image: UIImage(systemName: "line.3.horizontal.decrease"),
      menu: filterMenu
    )
    filterItem.accessibilityLabel = String(localized: "Filter", table: "Fork")
    guard let sortMenu else { return [filterItem] }
    let sortItem = UIBarButtonItem(
      image: UIImage(systemName: "arrow.up.arrow.down"),
      menu: UIMenu(children: sortMenu.children)
    )
    sortItem.accessibilityLabel = String(localized: "Sort", table: "Fork")
    return [filterItem, sortItem]
  }

  private func forkToggle(chip: ForkAlbumChip) {
    switch chip {
    case .newest:
      forkApply(filter: displayFilter == .newest ? .all : .newest)
    case .favorites:
      forkApply(filter: displayFilter == .favorites ? .all : .favorites)
    case .cached:
      let searchBar = searchController.searchBar
      searchBar.selectedScopeButtonIndex = searchBar.isCachedScopeSelected ? 0 : 1
      updateSearchResults(for: searchController)
      common.updateRightBarButtonItems()
      forkRefreshListHeader()
    }
  }

  /// Same steps as opening the filtered screen from the library, the title stays "Albums".
  private func forkApply(filter: DisplayCategoryFilter) {
    guard filter != displayFilter else { return }
    displayFilter = filter
    common.applyFilter()
    setNavBarTitle(title: String(localized: "Albums", table: "Fork"))
    collectionView.showsVerticalScrollIndicator = filter == .newest || filter == .recent
    updateSearchResults(for: searchController)
    common.updateFromRemote()
    collectionView.collectionViewLayout.invalidateLayout()
    forkRefreshListHeader()
  }
}

// MARK: - CommonCollectionSectionHeader

extension CommonCollectionSectionHeader {
  func forkRemoveListHeader() {
    viewWithTag(ForkAlbumsListHeaderView.headerTag)?.removeFromSuperview()
  }
}
