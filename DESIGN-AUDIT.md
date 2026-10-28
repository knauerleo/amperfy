# Design-Audit: Amperfy-Fork → Streaming-Client-Gefühl

Stand: 2026-10-28, Branch `youtube` (Basis `7f7ced94`). Nur Analyse, noch kein Code geändert.

Ziel ist das *Gefühl* eines modernen Streaming-Clients: flüssig, bildlastig, wenige Taps bis zur Musik, Dark-first.
Fremde Marken übernehmen wir nicht: kein fremdes Logo, keine Markenfarbe, keine fremden Assets.

> **Screenshots:** In Abschnitt 1b sind die Beobachtungen von 11 iPhone-Screenshots vom 2026-10-28 eingearbeitet.

---

## 0. Kurzfassung

Technisch ist die App moderner als sie wirkt: iOS 26 als Ziel, `UITab`/`UITabGroup`, ein Mini-Player als
`UITabAccessory` mit Liquid Glass, eine Home-Seite mit `UICollectionViewCompositionalLayout` und horizontalen Shelves,
dazu das Paket `DominantColors`. Das *Erscheinungsbild* stammt aber noch aus der Zeit vor 2020: Listen in
UITableView mit festen Schriftgrößen aus XIBs, ein grauer, 400 pt hoher Standard-Header auf allen Detailseiten, eine
Library als Textliste und überall dieselbe Albumzelle. Die meisten Daten, die eine Streaming-App ausmachen
(Playcount, zuletzt gespielt, hinzugefügt am, Favoriten, ähnliche Songs, Cover-Farben), liegen schon vor und tauchen
in der Oberfläche kaum auf.

---

## 1. Bestandsaufnahme

Technik insgesamt: **UIKit, fast alles in Code und XIB**. `Main.storyboard` enthält nur noch `SyncVC`, `UpdateVC` und
`LibrarySyncPopupVC`. **SwiftUI** gibt es nur in den Settings und in der Visualizer-Ansicht des Players.
Basisklassen: `BasicTableViewController`, `SingleSnapshotFetchedResultsTableViewController` (CoreData + Diffable),
`MultiSourceTableViewController`, `BasicCollectionViewController`.

| Screen | Datei(en) | Aufbau | Zellen und Views |
|---|---|---|---|
| **Tab-Struktur** | `Screens/ViewController/TabBarVC.swift:45-140` | `UITabBarController` mit `UITab`: Search (`UISearchTab`), Home, Gruppe „Library“ (`UITabGroup`, die Unter-Tabs sind umsortier- und ausblendbar). `tabBarMinimizeBehavior = .onScrollDown` | Mini-Player als `bottomAccessory` |
| **Home** | `HomeVC.swift`, `HomeManager.swift`, `AmperfyKit/Storage/HomeSection.swift` | `UICollectionViewController` mit Compositional Layout, eine horizontale Shelf pro Sektion (`orthogonalScrollingBehavior = .continuous`, `HomeVC.swift:140`). Sektionen lassen sich per `HomeEditorVC` an- und abschalten | **eine** Zelle für alles: `AlbumCollectionCell` (XIB), feste 160 pt (`HomeVC.swift:35`). Header `SectionHeaderView` (title3 semibold) |
| **Library** | `LibraryVC.swift:47` | `UICollectionView` mit `UICollectionLayoutListConfiguration(.sidebarPlain)`: eine reine Textliste mit Icons (Artists, Albums, Songs, Favorite Songs, Playlists …) | Listenzellen |
| **Listen** (Artists, Albums, Songs, Genres, Playlists, Podcasts, Downloads, Directories) | `ArtistsVC`, `AlbumsVC`/`AlbumsCollectionVC`, `SongsVC`, `GenresVC`, `PlaylistsVC` … | UITableView + FetchedResultsController. Albums wahlweise als Grid (`AlbumsCollectionVC`) | `GenericTableCell` (XIB, 48-pt-Bild, `GenericTableCell.swift:40`), `PlayableTableCell` (XIB, 48 pt, `PlayableTableCell.swift:86`), `PlaylistTableCell` |
| **Search** | `SearchVC.swift` | UITableView mit Sektionen History / Artist / Album / Playlist / Song, Scope „All/Cached“, Debounce, zuerst lokal, dann Server (Fork-Commit `839317b6`) | `GenericTableCell`, `PlayableTableCell`. Leerzustand per `UIContentUnavailableConfiguration` |
| **Album-Detail** | `AlbumDetailVC.swift:118` | Tabelle + `GenericDetailTableHeader` als `tableHeaderView` | Header-XIB: 240-pt-Cover, Titel 22 pt fest, Untertitel in Tint-Farbe, darunter `LibraryElementDetailTableHeaderView` (Play / Shuffle als zwei graue Kästen, `cornerRadius = 10`) |
| **Artist-Detail** | `ArtistDetailVC.swift:233-250` | `MultiSourceTableViewController`: Sektion „Albums“ (Tabellenzeilen), dann „Songs“ (alle) | gleicher Header, quadratisches Bild |
| **Playlist-Detail** | `PlaylistDetailVC.swift` | wie Album, dazu Edit-Modus (Name im Header, Umsortieren) | Collage aus vier Covern (`EntityImageView` Quad-Modus) |
| **Genre-Detail** | `GenreDetailVC.swift` | Multi-Source-Tabelle Artists / Albums / Songs | wie oben |
| **Player (Vollbild)** | `PopupPlayerVC.swift` (+XIB), `PopupPlayer+Visuals/Animations/TableViewExtension.swift`, `LargeCurrentlyPlayingPlayerView` (+XIB), `PlayerControlView` (+XIB) | als `.pageSheet` mit Detent `.large()` und Grabber geöffnet (`MiniPlayerView.swift:716-725`). Zwei Stile: **large** (großes Cover, Lyrics, Visualizer) und **compact** (Queue-Tabelle). Hintergrund: Cover + `UIBlurEffect(.prominent)` + Verlauf aus 2 Dominant Colors | Rating-View, Favorit, Optionsmenü, Wisch links/rechts auf dem Cover = Skip (`LargeCurrentlyPlayingPlayerView.swift:255-292`) |
| **Mini-Player** | `MiniPlayerView.swift:626-710` | Glass-Container im Tab-Accessory: Cover, Titel, Künstler, Play, Next, 3-pt-Fortschrittslinie | **nur ein Tap-Gesture** (`:629`), keine Swipes. Schrift 11 / 13 pt fest (`:704-705`) |
| **Queue** | Player-Stil „compact“ (`PopupPlayer+TableViewExtension.swift`), iPad: `QueueVC` in `SplitVC.swift:128` | Tabelle mit den Sektionen Previous / Next from Queue / Context-Next (eigene XIB-Header) | `PlayableTableCell`, Drag & Drop |
| **Lyrics** | `Screens/View/Lyrics/LyricsView.swift`, `LyricsVC.swift` | im Player statt des Covers, synced scrolling | `LyricTableCell` |
| **Kontextmenü** | `EntityPreviewVC.swift` (+XIB), `EntityPreviewActionBuilder` ab `:33` | Long-Press mit eigener Preview (Cover + Infos) und `UIMenu` | Einträge wie „Insert Context Queue“, „Append User Queue“ (`:515-541`) |
| **Swipe-Actions** | `AmperfyKit/Storage/SwipeActionSettings.swift:183-195`, `BasicTableViewController.swift` | konfigurierbar in den Settings (SwiftUI) | Default: links Context-Queue einfügen/anhängen, rechts User-Queue, Podcast-Queue, Download |
| **Settings** | `SwiftUI/Settings/*`, gehostet in `SettingsHostVC.swift` | SwiftUI-Listen mit eigenen `SettingsRow`/`SettingsCheckBoxRow` | Display, Player (Transcoding, EQ), Artwork, Library, Swipe, Account, Support, Developer |
| **Leere Zustände** | `contentUnavailableConfiguration` in Songs/Artists/Playlists/Genres/Radios/Search … | System-Standard (`.search()` bzw. Text + Icon) | Home hat **keinen** Leerzustand |
| **Ladezustände** | `UIRefreshControl` (Pull-to-Refresh), `SpinnerViewController`, Spinner als `accessoryView` in `PlayableTableCell` | keine Skeletons. Cover-Platzhalter sind generierte Icon-Artworks in der Theme-Farbe (`EntityImageView.swift:117-160`) | |
| **CarPlay** | `CarPlay/*` | CPTemplates, unabhängig vom UIKit-Design | – (Entitlement derzeit entfernt) |

### 1b. Screenshots vom iPhone

Aufgenommen am 2026-10-28 auf dem iPhone 16 im Dark Mode (11 Screens). Was im Code nicht zu sehen war oder dort anders wirkte:

| Screen | Beobachtung | Folgerung |
|---|---|---|
| **Home** | Sektionstitel („Random Albums“ …) sind rund 16 pt weiter eingerückt als die Cover darunter. Ursache: 16 pt Label-Abstand im `SectionHeaderView` (`HomeVC.swift:487`) *plus* 16 pt Section-Inset (`:142-147`). Zwei Cover und ein Anschnitt pro Zeile, alle Shelves gleich. Bei Alben mit Künstler = Albumname steht der Name doppelt („Valentine's Day / Valentine's Day“). Eine Playlist ohne Cover ist eine **vollflächig blaue Kachel** mit Icon | Ausrichtung ist ein Quick Win. Generierte Platzhalter im Dark Mode dämpfen (dunkle Fläche + gedämpftes Icon statt Theme-Blau) |
| **Tab-Leiste** | Nur Home / Library / Suche (iOS-26-Glass), Mini-Player schwebt darüber. Beim Scrollen verkleinert sich die Leiste und der Mini-Player rutscht zwischen die Tabs (Album-Screenshot) | Struktur passt zum Streaming-Muster, so lassen |
| **Mini-Player** | Titel und Künstler **zentriert**, der Titel ist kleiner und dünner als der Künstler. Fortschritt als blaue Linie am unteren Rand. Glass lässt grelle Inhalte durchscheinen (blaue Kachel hinter dem Player im ersten Screenshot) | Hierarchie umdrehen, linksbündig, Fortschritt in Weiß bzw. Cover-Farbe |
| **Library** | Reine Textliste mit 10 blauen Icons und Chevrons, darunter halber Bildschirm leer | bestätigt Problem 8 |
| **Suche** | Suchfeld unten (iOS 26), leer nur „No Search History“ auf Schwarz. Mit Eingabe: Scope-Leiste All/Cached oben, Künstler-Zeile, dann Albenzeilen mit drei Textzeilen (Titel, Künstler, „3 Songs“) und Chevron. Songs liegen unter der Tastatur und sind ohne Scrollen nicht sichtbar | Top-Treffer und Songs müssen nach oben. Die Scope-Leiste belegt den besten Platz |
| **Album** | Cover ca. 210 pt, Titel in normaler Schriftstärke (nicht fett), Künstler als blauer Link, Play/Shuffle als zwei graue Kästen mit blauem Text, Hintergrund reines Schwarz. Der Albumname steht schon in der Nav-Bar, bevor man scrollt (doppelt). Jede Zeile wiederholt den Künstler. Track-Reihenfolge **8, 14, 1, 9** | Header wie in Maßnahme 5. Künstler nur bei Compilations zeigen. Die Reihenfolge prüfen: sortiert wird nach `disk`, dann `track` (`SongMO+CoreDataClass.swift:74-82`), vermutlich unterschiedliche `disk`-Tags (z. B. leer vs. „1“) bei einem Teilalbum. Kein Design-, sondern ein Datenthema, aber sichtbar |
| **Playlist** | Collage aus vier Covern, aber mit **Duplikaten** (Spiritbox zweimal), weil die ersten vier Songs genommen werden. Pro Zeile Download-Icon + „…“-Button, also zwei Bedienelemente rechts. Laufender Song: Balken-Icon über dem Cover (gut) | Collage aus vier *verschiedenen* Alben bilden. Download-Status nur zeigen, wenn er sich vom Normalfall unterscheidet |
| **Player (groß)** | Der Hintergrund aus der Cover-Farbe **funktioniert** (Petrol bei Spiritbox) und ist der stärkste Screen der App. Störend: blauer Fortschrittsbalken (Theme-Tint) auf Petrol, technische Info „MP3 122 kbps“ in der Mitte, Album und Künstler als zwei gleich gewichtete Zeilen, Herz und „…“ in grauen Kreisen. Sheet-Kante oben sichtbar | Problem 7 zurückgestuft: Farbe bleibt, Akzente (Slider, Buttons) in Weiß. Technik-Info nur auf Tap. Künstler als eine Zeile, antippbar |
| **Queue** (Player kompakt) | Kopf „Next from: <Playlist>“ mit ∞ / Shuffle / Repeat, Zeilen mit Download-Icon und Drag-Griff. Funktional gut, wirkt aber wie eine Einstellungsliste | Zeilen ohne Download-Icon, kleinere Cover, aktuellen Song oben deutlicher |
| **Kontextmenü** | Preview-Karte oben (Bitrate abgeschnitten), dann Play, Shuffle, Instant Mix, **„Music Queue >“** (Untermenü), Show Album, Show Artist, Favorite, Rating, Add to Playlist, Delete Cache | „Als Nächstes spielen“ braucht zwei Taps und steckt hinter einem Fachbegriff. Die häufigsten Aktionen (Als Nächstes, Warteschlange, Favorit) gehören in die erste Ebene |
| **Sprache** | Die komplette Oberfläche ist Englisch, das Gerät Deutsch | Kein Muss. Wenn wir Menü-Texte ohnehin ersetzen (Maßnahme 9), dann gleich als `Localizable`-Strings mit Deutsch |

---

## 2. Verschenktes Potenzial

| Was liegt schon vor | Wo | Wie es heute genutzt wird | Möglichkeit |
|---|---|---|---|
| **`playCount`** pro Song/Album/Artist/Playlist | CoreData `AbstractLibraryEntity.playCount` | in der Oberfläche **nirgends** (nur `ArtworkSettingsView`) | „Meistgehört“-Shelf, **„Beliebt“-Liste auf der Künstlerseite** (Top 5 Songs nach Playcount), Sortierung |
| **`lastPlayedDate`** | `AbstractLibraryEntity`, `Playlist` | **gar nicht** in der UI. „Recently Played Albums“ nutzt den Server-Index `recentIndex` | „Zuletzt gehört“-Raster ganz oben auf Home, gemischt aus Alben, Playlists und Künstlern |
| **`addedDate`** (Song), `newestIndex` (Album) | CoreData | Sortierung in `SongsVC`, Shelf „Newest Albums“ | „Neu in deiner Sammlung“, nach dem YouTube-Download direkt sichtbar (passt zur Roadmap) |
| **Favoriten** (`isFavorite`, `getStarred2`) | überall | kleines Herz-Icon in Zellen. „Favorite Songs“ ist ein Library-Unterpunkt. `syncFavoriteLibraryElements()` läuft nur per Pull-to-Refresh in Songs/Artists/Albums | **„Lieblingssongs“ als feste erste Kachel** (Home + Library) mit eigenem Cover-Verlauf, Herz im Mini-Player und auf der Albumseite |
| **Ähnliche Songs / Instant Mix** | `requestSimilarSongs` (`getSimilarSongs2`), Autoplay (`PlayerUIHandler.swift:88`), Menüpunkt „Instant Mix“ (`EntityPreviewVC.swift:458`) | versteckt im Menü bzw. als ∞-Knopf | „Song-Radio“ als großer Knopf auf der Künstlerseite und im Player. Später auch „Ähnliche Songs von YouTube“ (Roadmap 4) |
| **Ratings** | `rating`, `RatingView` | Sterne in Zellen, **standardmäßig aus** (`isShowRating`) | eher leise halten, im Streaming-Muster spielt das Herz die Hauptrolle |
| **Genres** | `Genre`-Entity, `GenresVC`, Shelf „Random Genres“ | Textliste und zufällige Kacheln | **Genre-Kacheln auf der Such-Startseite** mit Farbe aus dem Cover eines Albums im Genre |
| **Lyrics** (synced) | `LyricsView`, `getFirstSyncedLyricsOrUnsyncedAsDefault` | Umschalter im Player statt des Covers | Lyrics-Karte unter dem Cover im Player (Scroll nach unten), farbig aus dem Cover |
| **Cover-Farben (`DominantColors`)** | nur `PopupPlayer+Visuals.swift:138` | Player-Hintergrund, **synchron im Main-Thread** bei jedem Songwechsel | eigener `ArtworkColorCache` (async, im Speicher, nach Artwork-ID). Damit: Detail-Header-Verlauf, Mini-Player-Tönung, Genre-Kacheln, Kartenhintergründe |
| **Haptik** | `Haptics.swift`, Setting `isHapticsEnabled` | nur Play/Shuffle im Header, Swipe-Actions, Rating, Podcast | Play/Pause, Skip, Favorit, Mini-Player-Swipe, Seek-Ende, Long-Press |
| **Visualizer** (ring, waveform, spectrumBars, generativeArt) | `SettingEnumerations.swift:367`, `LargeCurrentlyPlayingPlayerView.setupSwiftUIView` | im Optionsmenü des Players versteckt | bleibt optional, aber auffindbar machen. Kein Kernmuster |
| **Equalizer** | `Settings/Player/EqualizerSettingsView.swift` | tief in den Settings | Verknüpfung im Player-Optionsmenü |
| **Quad-Collage** für Playlists | `EntityImageView.swift:126-140` | Playlists | gut so, als Playlist-Cover beibehalten |
| **Suchverlauf** | `SearchHistoryItem` | Sektion „History“ in der Suche | als „Zuletzt gesucht“ mit Covern auf der Such-Startseite (bleibt) |
| **Tab-Accessory-Umgebung** | `traitCollection.tabAccessoryEnvironment` (`TabBarVC.swift:157`) | nur für die Größe | Inline-Modus (Tab-Bar minimiert) kompakter gestalten |
| **Theme-Farben** (blue … purple) | `ThemePreference` (`SettingEnumerations.swift:265`) | Tint überall | Akzent bleibt wählbar. Dazu ein *neutraler* Akzent (Weiß/Grau) für Dark-first, der Rest der Farbe kommt aus den Covern |

---

## 3. Vergleich mit Streaming-Mustern

Legende: ✅ vorhanden · 🟡 teilweise · ❌ fehlt

| Muster | Stand | Befund |
|---|---|---|
| Startseite mit horizontalen Shelves | 🟡 | Shelves vorhanden, aber alle gleich (160-pt-Quadrat, eine Zelle). Kein „Zuletzt gehört“-Raster oben, Künstler nicht rund, Default beginnt mit **Random Albums** (`HomeSection.swift:38`) |
| Große Cover und Header | 🟡 | Cover-Breite 240 pt im XIB (auf dem iPhone ca. 210 pt sichtbar) in einem starren 400-pt-Header (`GenericDetailTableHeader.swift:63`), kein Stretch/Parallax, Titel kleben nicht an der Navigation |
| Farbiger oder verschwommener Hintergrund aus dem Cover | 🟡 | nur im Player, dort gut gelöst (Screenshot). Detailseiten haben `.systemBackground` |
| Player als Vollbild-Sheet | 🟡 | `.pageSheet` + `.large()` + Grabber, wischbar. Wirkt wie ein Formular-Sheet, kein Übergang vom Mini-Player-Cover. Stilwechsel large/compact ist ein Extra-Schritt zur Queue |
| Mini-Player mit Swipe-Gesten | ❌ | nur Tap (`MiniPlayerView.swift:629`). Kein Links/Rechts = Skip, kein Hochwischen = Öffnen |
| Künstlerseite mit „Beliebt“ | ❌ | Albums-Tabelle + *alle* Songs alphabetisch (`ArtistDetailVC.swift:233-250`). Kein Header-Bild, keine Diskografie-Shelf, kein „Radio“ |
| „Lieblingssongs“ als zentrale Playlist | 🟡 | existiert als Library-Unterpunkt „Favorite Songs“, aber ohne prominente Kachel und ohne Auto-Sync |
| Such-Startseite mit Genre-Kacheln | ❌ | leere Suche zeigt nur den Verlauf bzw. „No Search History“ |
| Suchergebnis „Top-Treffer“ | ❌ | flache Sektionen Artist → Album → Playlist → Song |
| Skeleton-Loading | ❌ | Spinner/Refresh-Control. Bei der Suche erscheint kurz „No Results“, während die Server-Suche noch läuft (`SearchVC.swift:545` zeigt das lokale Ergebnis, `:643` setzt den Leerzustand) |
| Typografie (Hierarchie, Dynamic Type) | ❌ | 98 feste `pointSize` in XIBs, 12× `.systemFont(ofSize:)` in Code, nur 2× `preferredFont`. Im Mini-Player ist der **Titel kleiner als der Künstler** (11 vs. 13 pt, `MiniPlayerView.swift:704`) |
| Abstände und Raster | 🟡 | `CommonScreenOperations`: Ränder 25/16 pt gemischt, 48-pt-Zeilen. Kein gemeinsames Token-Set |
| Dark-first | 🟡 | Appearance System/Hell/Dunkel wählbar (`AppDelegate.swift:376`). Flächen sind `.systemBackground`, nicht für Dark optimiert (kein tiefes Schwarz/Grau-Stufen) |
| Wenige Taps bis zur Musik | 🟡 | Play nur über den Header-Knopf oder einen Song-Tap. Kein Play-Overlay auf Home-Kacheln, kein schwebender Play-Knopf beim Scrollen |
| Kontextmenü in Alltagssprache | 🟡 | vollständig, aber mit Fachsprache („Insert Context Queue“, „Append User Queue“, `EntityPreviewVC.swift:515-541`) statt „Als Nächstes spielen“ / „Zur Warteschlange“ |
| Haptik | 🟡 | vorhanden, aber an den häufigsten Stellen (Play, Skip, Favorit) nicht |
| Leerzustände mit Handlung | 🟡 | System-Standard ohne Aktion. Home ohne Leerzustand |

---

## 4. Die größten Probleme

Sortiert nach Wirkung auf das Gefühl „Streaming-App“.

1. **Detailseiten wirken wie Formulare** (Album, Artist, Playlist, Genre).
   Ursache: `GenericDetailTableHeader.xib` mit fester Höhe `frameHeightCompact = 400` (`GenericDetailTableHeader.swift:63`),
   240-pt-Cover, 22-pt-Titel mit fester Größe, Hintergrund `systemBackground`. Play/Shuffle sind zwei gleich große graue
   Kästen (`LibraryElementDetailTableHeaderView.swift:155-164`). Keine Cover-Farbe, kein Stretch, kein Titel in der Nav-Bar beim Scrollen.
2. **Künstlerseite ohne Struktur.**
   Ursache: `ArtistDetailVC.swift:233-250` zeigt zwei Tabellensektionen (Albums als Zeilen, danach alle Songs).
   `playCount` wäre für „Beliebt“ da, wird aber nicht genutzt. `getTopSongs`/`getArtistInfo2` (Bild, Bio) fragt das Backend nicht ab (`BackendApi.swift:139-211`).
3. **Mini-Player: falsche Hierarchie, keine Gesten.**
   Ursache: `MiniPlayerView.swift:704-705` (Titel 11 pt, Künstler 13 pt), feste Farben `.white/.lightGray` (`:828-833`)
   statt semantischer Farben, nur `UITapGestureRecognizer` (`:629`).
4. **Typografie ohne System.**
   Ursache: Schriftgrößen stehen fest in XIBs (`PlayableTableCell.xib`, `GenericTableCell.xib`, `GenericDetailTableHeader.xib:112`,
   Player-XIBs mit 12/14/15/17/30/45 pt), kein Dynamic Type, keine gemeinsame Skala.
5. **Home ist eintönig und startet mit Zufall.**
   Ursache: eine Zellklasse und eine Größe für Alben, Künstler, Songs, Genres, Podcasts (`HomeVC.swift:120-166, 185-199`).
   Default-Reihenfolge `randomAlbums` zuerst (`HomeSection.swift:37-42`). Kein „Zuletzt gehört“ aus `lastPlayedDate`, kein Lieblingssongs-Einstieg, kein Play-Overlay.
6. **Suche: kein Start-Erlebnis, kurzes „Keine Treffer“.**
   Ursache: `SearchVC.updateContentUnavailable` (`:643-653`) zeigt ohne Eingabe nur den Verlauf. Beim Tippen wird zuerst das
   lokale Ergebnis gezeigt (`:545`); ist es leer, erscheint „No Results“, bis die Server-Antwort da ist. Kein Top-Treffer.
   Für den YouTube-Bereich muss diese Logik ohnehin angefasst werden.
7. **Player: gute Farbe, falsche Akzente.**
   Auf dem iPhone trägt der Cover-Hintergrund gut (siehe 1b). Störend sind der Fortschrittsbalken in Theme-Blau, die
   Technik-Info „MP3 122 kbps“ in der Mitte und drei gleich gewichtete Textzeilen. Technische Ursache für mögliches Ruckeln:
   `artwork.dominantColors(max: 2)` läuft synchron im Main-Thread (`PopupPlayer+Visuals.swift:138`). Der Verlauf liegt unter
   einem `.prominent`-Blur (`PopupPlayerVC.swift:84`) und kann deshalb nicht in andere Screens übernommen werden.
8. **Library ist eine Textliste.**
   Ursache: `LibraryVC.swift:47` (`.sidebarPlain`). Kein Raster, keine zuletzt genutzten Elemente, Favoriten nicht angeheftet.
9. **„Als Nächstes spielen“ braucht zwei Taps, dazu Fachbegriffe in Menüs und Swipes.**
   Ursache: Untermenü „Music Queue“ (`EntityPreviewVC.swift:515-541`) mit „Insert/Append Context/User Queue“,
   Default-Swipes (`SwipeActionSettings.swift:183-195`) mit denselben Begriffen.
10. **Keine Skeletons, kein Leerzustand auf Home.**
    Ursache: `HomeVC.applySnapshot` (`:235-255`) zeigt leere Sektionen einfach nicht an. Beim ersten Start bleibt der Bildschirm leer.
11. **Kleine Unsauberkeiten, die zusammen „unfertig“ wirken** (aus den Screenshots):
    Home-Titel nicht bündig mit den Covern (`HomeVC.swift:487` + `:142-147`), grelle blaue Platzhalter-Kacheln,
    doppelte Cover in der Playlist-Collage, Künstler in jeder Zeile einer Albumseite, Albumtitel doppelt (Nav-Bar + Header),
    Track-Reihenfolge 8/14/1/9 (`SongMO+CoreDataClass.swift:74-82`, Datenthema prüfen).

---

## 5. Priorisierte Maßnahmen

Wirkung: H/M/N · Aufwand: S (< ½ Tag) / M (1–2 Tage) / L (> 2 Tage). Sortiert nach Wirkung ÷ Aufwand.

| # | Maßnahme | Screen | Wirkung | Aufwand | Merge-Risiko |
|---|---|---|---|---|---|
| 1 | **Design-Tokens** als neue Datei `Fork/Design/DS.swift`: Schriftskala mit Dynamic Type (`UIFontMetrics`), Abstände 4/8/12/16/24/32, Radien, Flächenfarben Dark-first | alle | H | S | niedrig (neue Datei) |
| 2 | **Mini-Player**: Titel > Künstler, semantische Farben, Swipe links/rechts = Skip mit Cover-Slide, Swipe hoch = Player öffnen, Haptik | Mini-Player | H | S | mittel (`MiniPlayerView.swift`, 3 Stellen) |
| 3 | **`ArtworkColorCache`** (async, NSCache nach Artwork-ID) + Player nutzt ihn. Blur reduzieren, damit die Farbe trägt | Player | H | S | niedrig |
| 4 | **Haptik** an Play/Pause, Skip, Favorit, Seek | Player, Mini-Player | M | S | niedrig |
| 5 | **Neuer Detail-Header** `ImmersiveDetailHeaderView` (Code, kein XIB): Cover 260–300 pt, Verlauf aus Cover-Farbe bis Schwarz, Stretch beim Overscroll, Titel blendet in die Nav-Bar über, runder Play-Knopf + Shuffle-Icon, Favorit, Download, Menü | Album, Playlist, Genre | H | M | niedrig, wenn als *zweite* Implementierung neben `GenericDetailTableHeader` hinter einem Schalter |
| 6 | **Künstlerseite neu**: Header mit Künstlerbild, „Beliebt“ (Top 5 nach `playCount`, später `getTopSongs`), Diskografie als horizontale Shelf (Alben/Singles nach Jahr), „Song-Radio“-Knopf (Instant Mix) | Artist | H | M | mittel (`ArtistDetailVC` einmal auf neue Sektionen umstellen) |
| 7 | **Home neu sortieren und anreichern**: oben ein 2×3-Raster „Zuletzt gehört“ (`lastPlayedDate`), Lieblingssongs-Kachel, runde Künstlerzellen, größere Alben-Shelf, „Neu hinzugefügt“. Random nach unten | Home | H | M | mittel (`HomeSection` nur **ans Ende** erweitern, da Codable/Int) |
| 8 | **Such-Startseite**: Genre-Kacheln (Farbe aus Cover), „Zuletzt gesucht“ mit Covern. **Top-Treffer**-Karte. Spinner bzw. Skeleton statt „No Results“ während die Server-Suche läuft | Search | H | M | hoch (`SearchVC.swift`, deshalb mit dem YTM-Bereich bündeln) |
| 9 | **Menü-Texte** in Alltagssprache: „Als Nächstes spielen“, „Zur Warteschlange“, „Zu Playlist hinzufügen“, „Zum Album“, „Zum Künstler“, „Song-Radio“. Swipe-Defaults: links = Als Nächstes, rechts = Favorit | Kontextmenü, Listen | M | S | niedrig (Strings, Default-Werte) |
| 10 | **Zellen moderner**: `PlayableTableCell` 56-pt-Cover mit Radius 4, Titel 16 semibold / Untertitel 13, „läuft gerade“ als Akzentfarbe + Equalizer-Icon, kein Disclosure-Pfeil | alle Listen | M | M | mittel (XIB-Änderungen konfliktanfällig, deshalb Werte im Code in `awakeFromNib`-Extension überschreiben) |
| 11 | **Skeleton-Shelves** auf Home und Detailseiten (Shimmer-Platzhalter in Zellgröße) | Home, Detail | M | M | niedrig (neue View) |
| 12 | **Library als Raster**: angeheftete Lieblingssongs, Filter-Chips (Playlists, Alben, Künstler, Downloads), zuletzt genutzt zuerst | Library | M | L | mittel |
| 13 | **Player-Feinschliff**: Matched-Transition vom Mini-Player-Cover, Lyrics-Karte unter dem Cover, Queue per Wisch nach oben statt Stilwechsel | Player | M | L | hoch (`PopupPlayer*`) |
| 14 | **Dark-first**: Default-Appearance Dunkel, Flächen in Grau-Stufen (#121212 / #1E1E1E / #2A2A2A), neutraler Akzent als Option | global | M | S | niedrig |
| 16 | **Quick Wins aus den Screenshots**: Home-Titel bündig, Platzhalter-Artwork gedämpft, Player-Slider und Buttons in Weiß, Technik-Info ausblenden, Künstler in Albumzeilen weglassen, Collage ohne Duplikate | Home, Player, Album, Playlist | M | S | niedrig bis mittel (je 1–3 Zeilen) |
| 15 | **Leerzustände mit Aktion** (Home: „Bibliothek synchronisieren“, Favoriten: „Tippe auf ♥“) | Home, Listen | N | S | niedrig |

---

## 6. Umsetzung in Phasen

Jede Phase ist eigenständig, endet mit einem Build auf dem iPhone („leo“) und lässt sich einzeln abnehmen.
Kleine Commits innerhalb jeder Phase. Neue Optik zunächst hinter **einem** Schalter
`Settings → Display → „Neues Design“` (Default an), damit jederzeit ein Vergleich mit dem alten Stand möglich ist.

### Phase 1: Fundament und Player-Gefühl (Maßnahmen 1, 2, 3, 4, 14, 16)
- `DS.swift` (Tokens), `ArtworkColorCache.swift`, `Haptics`-Aufrufe.
- Mini-Player: Hierarchie, Gesten, Haptik. Player-Hintergrund mit kräftiger Cover-Farbe.
- **Test auf dem iPhone:** Song starten, im Mini-Player wischen (Skip), hochwischen (öffnen), Farbe im Player prüfen, Haptik spüren.

### Phase 2: Detailseiten (Maßnahmen 5, 6, 10)
- `ImmersiveDetailHeaderView` für Album, Playlist, Genre. Künstlerseite mit „Beliebt“, Diskografie-Shelf, Song-Radio.
- Neue Zellwerte für `PlayableTableCell`.
- **Test:** Album öffnen, nach oben/unten ziehen (Stretch, Titel in der Nav-Bar), mit einem Tap abspielen, Künstlerseite durchgehen.

### Phase 3: Home (Maßnahmen 7, 11, 15)
- Neue Zelltypen `TileCollectionCell` (Raster „Zuletzt gehört“), `ArtistCircleCell`, `LargeAlbumCell`. Neue `HomeSection`-Fälle **am Ende** angehängt.
- Lieblingssongs-Kachel, Skeletons, Leerzustand.
- **Test:** App kalt starten, das Skeleton erscheint und wird ersetzt. Oben steht, was zuletzt lief, und es spielt mit einem Tap.

### Phase 4: Suche + YouTube Music (Maßnahmen 8, 9 + Roadmap 2)
- Such-Startseite (Genre-Kacheln, zuletzt gesucht), Top-Treffer, Ladezustand.
- **YouTube-Music-Sektion** direkt im neuen Stil: dieselben Zellen wie lokale Songs, rechts ein Status-Badge (Wolke / Ring-Fortschritt / Haken).
  Kontextmenü mit den neuen Alltagsbegriffen („In Sammlung laden“, „Als Nächstes spielen“, „Zur Warteschlange“).
  Der Top-Treffer darf ein YouTube-Treffer sein, mit kleinem Quell-Label „YouTube Music“ als Text, ohne fremdes Logo.
- **Test:** „valentines day linkin park“ tippen: kein „No Results“-Flackern, YTM-Treffer antippen, nach ca. 9 s Ton, Badge wechselt bis zum Haken.

### Phase 5: Library und Player-Feinschliff (Maßnahmen 12, 13 + Roadmap 3/4)
- Library-Raster mit Chips, angeheftete Lieblingssongs, **Download-Übersicht** (Songpicker-Jobs) als Chip „Downloads“.
- Settings: Songpicker-URL, YouTube an/aus im selben SwiftUI-Stil.
- Player: Cover-Übergang, Lyrics-Karte, Queue per Wisch.
- **Test:** Library-Chips filtern, Download-Liste zeigt laufende YouTube-Jobs, Player öffnen und schließen, Lyrics-Karte prüfen.

### YouTube Music im Design mitdenken
- **Ein Zellentyp** für alle Songs (lokal, Server, YouTube). Die Quelle zeigt nur ein kleines Badge bzw. ein Status-Icon im `accessoryView`.
  So muss `PlayableTableCell` nur um eine optionale `SourceBadge`-Unteransicht erweitert werden.
- **Status-Sprache** einheitlich: Wolke = nur online, Ring-Fortschritt = lädt, Haken = in der Sammlung. Dieselben Icons wie beim normalen Song-Download.
- **Shelf-Komponenten wiederverwendbar** bauen (Phase 3), damit später „Ähnliche Songs von YouTube“ als Shelf auf Künstler- und Albumseite passt.
- „Neu hinzugefügt“ (Home) zeigt automatisch fertige YouTube-Downloads, als Rückmeldung nach „In Sammlung laden“.

---

## 7. Upstream-Merges: Risiken und wie man sie klein hält

**Konflikt-Hotspots** (häufig upstream geändert bzw. groß):
`Amperfy.xcodeproj/project.pbxproj`, `SearchVC.swift`, `HomeVC.swift`/`HomeManager.swift`, `MiniPlayerView.swift`,
`PopupPlayer*.swift`, alle `*.xib` (XML-Diffs mit generierten IDs lassen sich praktisch nicht von Hand mergen),
`EntityPreviewVC.swift`, `ArtistDetailVC.swift`.

**Regeln:**
1. **Neue Dateien statt Umbauten.** Alles Neue kommt in eine eigene Gruppe `Amperfy/Fork/` (Views, Zellen, Tokens, Caches).
   Eintragen mit `Helper/add-swift-file.py`. `project.pbxproj`-Konflikte sind dann nur angehängte Zeilen.
2. **XIBs nicht anfassen.** Wo eine bestehende Zelle anders aussehen soll, Werte in einer Extension im Code setzen
   (z. B. `PlayableTableCell+ForkStyle.swift`, aufgerufen aus `display(...)` mit einer Zeile). Neue Header/Zellen werden in Code gebaut.
3. **Einhängen über eine Zeile.** In bestehenden Dateien nur Hook-Aufrufe ergänzen (`if DS.isNewDesign { … } else { altes Verhalten }`),
   keine Blöcke verschieben, keine Umformatierung (das Projekt nutzt `swiftformat` mit 2 Spaces: Konfiguration beibehalten).
4. **Persistierte Enums nur am Ende erweitern** (`HomeSection`, `LibraryDisplayType`, `SwipeActionType` sind `Codable`/Int).
   Default-Werte nur über neue, fork-eigene Settings ändern, nicht in den Upstream-Defaults.
5. **AmperfyKit möglichst unberührt lassen.** Neue Abfragen (Top-Played, Zuletzt gehört) als `LibraryStorage+Fork….swift`-Extension,
   wie schon bei `LibraryStorage+MultiWordSearch.swift`. Neue Server-Calls (`getTopSongs`) als eigene Extension des Subsonic-Syncers.
6. **Strings:** Menü-Texte über eine kleine Mapping-Funktion ersetzen statt an 30 Stellen im Upstream-Code.
7. **Vor jeder Phase** `git fetch upstream && git merge upstream/master`, damit die Konflikte klein bleiben.
   In `FORK.md` pro Phase die angefassten Upstream-Dateien auflisten.
