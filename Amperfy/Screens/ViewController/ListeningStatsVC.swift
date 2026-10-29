//
//  ListeningStatsVC.swift
//  Amperfy
//
//  Fork (F-13): statistics and year in review from local data, see LibraryStorage+ForkStats.
//  Opened from the Library (chart button). Segments: the years with plays (newest first,
//  at most three) and "All Time". Listening time, plays, songs, artists, albums, then
//  top artists, songs and albums. Tap on an artist or album opens it, on a song plays the
//  top songs from there.
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

final class ListeningStatsVC: UITableViewController {
  private enum Section: Int, CaseIterable {
    case summary
    case topArtists
    case topSongs
    case topAlbums

    var title: String? {
      switch self {
      case .summary: return nil
      case .topArtists: return String(localized: "Top Artists", table: "Fork")
      case .topSongs: return String(localized: "Top Songs", table: "Fork")
      case .topAlbums: return String(localized: "Top Albums", table: "Fork")
      }
    }
  }

  private static let maxYearSegments = 3
  private static let cellID = "ListeningStatsCell"

  private let account: Account
  private var periods = [ListeningStats.Period]()
  private var stats: ListeningStats?
  private let periodControl = UISegmentedControl()

  init(account: Account) {
    self.account = account
    super.init(style: .insetGrouped)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = String(localized: "Your Stats", table: "Fork")
    navigationItem.largeTitleDisplayMode = .never
    tableView.backgroundColor = ForkSurface.background
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellID)

    let years = appDelegate.storage.main.library.getListeningYears(for: account)
      .prefix(Self.maxYearSegments)
    periods = years.map { .year($0) } + [.allTime]
    for (index, period) in periods.enumerated() {
      periodControl.insertSegment(withTitle: Self.title(of: period), at: index, animated: false)
    }
    periodControl.selectedSegmentIndex = 0
    periodControl.addTarget(self, action: #selector(periodChanged), for: .valueChanged)
    let header = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
    periodControl.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(periodControl)
    NSLayoutConstraint.activate([
      periodControl.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
      periodControl.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
      periodControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),
    ])
    tableView.tableHeaderView = header
    reloadStats()
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    navigationController?.navigationBar.prefersLargeTitles = false
  }

  private static func title(of period: ListeningStats.Period) -> String {
    switch period {
    case .allTime: return String(localized: "All Time", table: "Fork")
    case let .year(year): return String(year)
    }
  }

  @objc
  private func periodChanged() {
    DS.haptic(.light)
    reloadStats()
  }

  private func reloadStats() {
    let index = max(0, periodControl.selectedSegmentIndex)
    guard index < periods.count else { return }
    stats = appDelegate.storage.main.library.getListeningStats(for: account, period: periods[index])
    tableView.reloadData()
    updateEmptyState()
  }

  private func updateEmptyState() {
    guard let stats, stats.isEmpty else {
      contentUnavailableConfiguration = nil
      return
    }
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: "chart.bar.xaxis")
    config.text = String(localized: "No Plays Yet", table: "Fork")
    config.secondaryText = String(localized: "Songs you listen to in Drift show up here.", table: "Fork")
    contentUnavailableConfiguration = config
  }

  // MARK: Formatting

  private static func listeningTime(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 24 * 3600 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = .dropAll
    return formatter.string(from: TimeInterval(seconds)) ?? "0 min"
  }

  private static func plays(_ count: Int) -> String {
    count == 1 ? String(localized: "1 play", table: "Fork") : String(localized: "\(count) plays", table: "Fork")
  }

  private func summaryRows(_ stats: ListeningStats) -> [(String, String)] {
    [
      (String(localized: "Listening Time", table: "Fork"), Self.listeningTime(stats.listeningSeconds)),
      (String(localized: "Plays", table: "Fork"), "\(stats.plays)"),
      (String(localized: "Songs", table: "Fork"), "\(stats.songCount)"),
      (String(localized: "Artists", table: "Fork"), "\(stats.artistCount)"),
      (String(localized: "Albums", table: "Fork"), "\(stats.albumCount)"),
    ]
  }

  // MARK: UITableViewDataSource

  override func numberOfSections(in tableView: UITableView) -> Int {
    guard let stats, !stats.isEmpty else { return 0 }
    return Section.allCases.count
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let stats, let section = Section(rawValue: section) else { return 0 }
    switch section {
    case .summary: return summaryRows(stats).count
    case .topArtists: return stats.topArtists.count
    case .topSongs: return stats.topSongs.count
    case .topAlbums: return stats.topAlbums.count
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    guard let stats, let section = Section(rawValue: section) else { return nil }
    switch section {
    case .topArtists where stats.topArtists.isEmpty,
         .topSongs where stats.topSongs.isEmpty,
         .topAlbums where stats.topAlbums.isEmpty:
      return nil
    default:
      return section.title
    }
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    guard let stats, Section(rawValue: section) == .summary else { return nil }
    var notes = [String]()
    if case .year = stats.period {
      notes.append(stats.isApproximate
        ? String(localized: "From the play history on this device. Songs without a history entry count with their total plays.", table: "Fork")
        : String(localized: "From the play history on this device.", table: "Fork"))
    } else {
      notes.append(String(localized: "Plays counted on this device.", table: "Fork"))
    }
    if let start = stats.historyStartDate {
      let date = start.formatted(date: .abbreviated, time: .omitted)
      notes.append(String(localized: "Drift has counted \(stats.appPlayedSongsCount) plays since \(date).", table: "Fork"))
    }
    return notes.joined(separator: " ")
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  )
    -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
    cell.backgroundColor = DS.Color.surface
    cell.accessoryType = .none
    cell.accessoryView = nil
    cell.selectionStyle = .default
    guard let stats, let section = Section(rawValue: indexPath.section) else { return cell }

    var content: UIListContentConfiguration
    switch section {
    case .summary:
      let row = summaryRows(stats)[indexPath.row]
      content = .valueCell()
      content.text = row.0
      content.secondaryText = row.1
      content.secondaryTextProperties.font = DS.Font.songTitle
      content.secondaryTextProperties.color = .label
      cell.selectionStyle = .none
    case .topArtists:
      let entry = stats.topArtists[indexPath.row]
      content = .valueCell()
      content.text = "\(indexPath.row + 1).  \(entry.item.name)"
      content.secondaryText = Self.plays(entry.plays)
      cell.accessoryType = .disclosureIndicator
    case .topSongs:
      let entry = stats.topSongs[indexPath.row]
      content = .subtitleCell()
      content.text = "\(indexPath.row + 1).  \(entry.item.title)"
      content.secondaryText = entry.item.creatorName
      cell.accessoryView = Self.playsLabel(entry.plays)
    case .topAlbums:
      let entry = stats.topAlbums[indexPath.row]
      content = .subtitleCell()
      content.text = "\(indexPath.row + 1).  \(entry.item.name)"
      content.secondaryText = entry.item.subtitle
      cell.accessoryView = Self.playsLabel(entry.plays)
    }
    content.textProperties.font = DS.Font.cellTitle
    content.textProperties.numberOfLines = 1
    if section != .summary {
      content.secondaryTextProperties.font = DS.Font.cellSubtitle
      content.secondaryTextProperties.color = .secondaryLabel
    }
    cell.contentConfiguration = content
    return cell
  }

  private static func playsLabel(_ count: Int) -> UILabel {
    let label = UILabel()
    label.text = plays(count)
    label.font = DS.Font.cellDuration
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.sizeToFit()
    return label
  }

  // MARK: UITableViewDelegate

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard let stats, let section = Section(rawValue: indexPath.section) else { return }
    switch section {
    case .summary:
      return
    case .topArtists:
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToArtistDetail(
          account: account,
          artist: stats.topArtists[indexPath.row].item
        ),
        animated: true
      )
    case .topSongs:
      let isOfflineMode = appDelegate.storage.settings.user.isOfflineMode
      let songs = stats.topSongs.map(\.item)
      let selected = songs[indexPath.row]
      let playables: [AbstractPlayable] = songs.filterCached(dependigOn: isOfflineMode)
      guard let index = playables.firstIndex(where: { $0 == selected }) else {
        DS.haptic(.error)
        return
      }
      DS.haptic(.light)
      appDelegate.player.play(context: PlayContext(
        name: String(localized: "Top Songs · \(Self.title(of: stats.period))", table: "Fork"),
        index: index,
        playables: playables
      ))
    case .topAlbums:
      navigationController?.pushViewController(
        AppStoryboard.Main.segueToAlbumDetail(
          account: account,
          album: stats.topAlbums[indexPath.row].item
        ),
        animated: true
      )
    }
  }
}
