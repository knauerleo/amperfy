# Amperfy-Fork mit YouTube-Music-Integration (App-Name: Drift)

Persönlicher Fork von [Amperfy](https://github.com/BLeeEZ/amperfy) (GPL-3.0, © Maximilian Bauer und Mitwirkende).
Der Fork bleibt unter GPL-3.0. Lizenz- und Quellenhinweise des Originals bleiben unverändert erhalten.

- Repo: https://github.com/knauerleo/amperfy
- Arbeitsbranch: `youtube`
- Upstream-Remote: `upstream` → `BLeeEZ/amperfy`

Ziel: Amperfy so umbauen, dass es mit dem Musik-Setup auf dem Raspberry Pi Treffer von YouTube Music findet, abspielt
und dauerhaft in die Sammlung lädt. Langfristig soll sich die App wie ein vollwertiger Streaming-Client anfühlen.

---

## Server-Setup (Raspberry Pi)

Erreichbar per VPN unter `10.66.66.6`, im LAN unter `192.168.188.23`.

| Dienst | Port | Zweck |
|---|---|---|
| Navidrome (Subsonic-API) | `:4533` | Musikbibliothek. Läuft mit `ND_SUBSONIC_DEFAULTREPORTREALPATH=true`, `path` ist der echte Pfad `/music/<rel>` |
| Songpicker (Flask, ohne Auth) | `:8781` | YouTube-Music-Suche und Download per yt-dlp |
| Subsonic-Proxy (nginx) | `:4534` | Reicht alles an Navidrome durch, versteht zusätzlich die Fake-IDs `ytm-<videoId>` |

### Songpicker-API

- `GET /api/search?q=<text>` → `{library: [...], youtube: [...], error}`.
  Ein YouTube-Treffer sieht so aus: `{source:"youtube", id, title, artist, artists, album, album_id, duration, thumb, kind, library}`.
  `library` ist in der Praxis `null` (nicht in der Sammlung) oder der relative Pfad der vorhandenen Kopie
  (`YouTube/<Künstler>/<Album>/NN - Titel.opus`), kein Boolean.
- `POST /api/get` mit dem kompletten Treffer-JSON als Body → startet den Download nach
  `musik/YouTube/<Künstler>/<Album>/NN - Titel.opus`.
- `GET /api/jobs` → `{<videoId>: {state, label, started, path?, error?}}`.
  Zustände: `wartet` → `lädt` → `speichert` → `fertig` (mit `path`) bzw. `fehler`.
- `GET /api/stream/<videoId>` liefert Opus/WebM, das AVPlayer **nicht** abspielt. Nicht verwenden.
- Seit Abschnitt 9 nutzt die App diese API nicht mehr, alles läuft über Subsonic am Login-Host.

### Sofort abspielen über den Proxy

`:4534/rest/stream.view?id=ytm-<videoId>&format=mp3` mit normaler Subsonic-Auth (u/t/s):

- startet den Download und streamt sofort MP3 mit 320 kbit/s (chunked, ohne Content-Length),
- der erste Ton kommt nach etwa 9 s,
- nach dem Download schreibt der Proxy `ytm-<id>` auf die echte Navidrome-ID um,
- Navidrome findet die neue Datei nach etwa 35 s (der Proxy stößt `startScan` an).

---

## Bauen und Installieren

**Nur auf dem echten iPhone bauen, keine Simulatoren.**

```bash
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy \
  -destination 'platform=iOS,name=leo' \
  -derivedDataPath ../DerivedData -allowProvisioningUpdates build -quiet

xcrun devicectl device install app --device 2145C18E-BC23-508B-BAFD-2F3556A4C825 \
  ../DerivedData/Build/Products/Debug-iphoneos/Amperfy.app
```

- Der erste Build ist ein kompletter Neubau inklusive aller Swift-Pakete und dauert entsprechend lange.
  Danach baut Xcode inkrementell, also nur die geänderten Dateien.
- Das iPhone heißt `leo` (iPhone 16). Die devicectl-ID steht oben im Befehl.
- Alternativ in Xcode: Schema `Amperfy`, Ziel „leo“, ⌘R.

### Signing (Commit `51eff135`)

| Einstellung | Wert |
|---|---|
| Team | `45L48D96FZ` (Leopold Knauer, Individual) |
| App | `de.knauerleo.amperfy-music` |
| AmperfyKit | `de.knauerleo.amperfy-music.AmperfyKit` (manuell signiert, wie im Original) |
| Tests | `de.knauerleo.AmperfyKitTests` |
| Teilen-Erweiterung (F-9) | `de.knauerleo.amperfy-music.Share` (Target `DriftShare`, automatisch, Profil „iOS Team Provisioning Profile: *“) |
| Keychain-Gruppe (F-9) | `45L48D96FZ.de.knauerleo.amperfy-music.shared` (App und `DriftShare`, braucht keine Registrierung) |
| Widgets (F-14) | `de.knauerleo.amperfy-music.Widgets` (Target `DriftWidgets`, automatisch) |
| App Group (F-14) | `group.de.knauerleo.amperfy-music` (App und `DriftWidgets`, von Xcode registriert) |

- **Developer-Portal:** Von Hand ist nichts anzulegen. Xcode registriert App-ID und Profil automatisch (`-allowProvisioningUpdates`).
  Siri ist als Capability aktiv. Extensions sind `DriftShare` (F-9) und `DriftWidgets` (F-14), eingebettet nur für iOS (`platformFilter = ios`).
  Die App führt in `keychain-access-groups` zuerst ihre eigene Gruppe, damit sich die Standardgruppe für Keychain-Einträge nicht ändert.
- **App Group (F-14):** `group.de.knauerleo.amperfy-music` für App und `DriftWidgets`. Registriert `-allowProvisioningUpdates`
  selbst, seit die neue Program License Agreement akzeptiert ist (2026-10-29).
- **CarPlay:** Das Entitlement `com.apple.developer.carplay-audio` ist entfernt, weil Apple es nur auf Antrag vergibt.
  Beantragen unter developer.apple.com/contact/carplay („CarPlay Audio App“). Nach der Freigabe die Zeile in
  `Amperfy/Amperfy.entitlements` wieder einfügen. Der CarPlay-Code selbst ist unverändert.
- **ATS:** `NSAllowsArbitraryLoads` ist im Original schon gesetzt. HTTP zu LAN- und VPN-IPs funktioniert ohne weitere Änderung.
- **TestFlight (später):** In App Store Connect eine App mit der Bundle-ID `de.knauerleo.amperfy-music` anlegen.
  Dort ist ein eindeutiger App-Name nötig, „Amperfy Music“ ist durch das Original belegt.

---

## Änderungen im Fork

### 1. Suche repariert (Commit `839317b6`)

**Probleme im Original:**

- `SearchVC.updateSearchResults` startete die Server-Suche (`search3`) und parallel eine lokale CoreData-Suche.
  Angezeigt wurde nur das lokale Ergebnis. Server-Treffer tauchten erst beim nächsten Tastendruck auf, und auch dann
  nur, falls die lokale Suche sie fand.
- Die lokale Suche filtert mit `title CONTAINS[cd] <ganze Eingabe>`, danach rankt `FuzzySearcher` die ganze Eingabe
  nur gegen den Titel. Eine Suche wie „valentines day linkin park“ fand daher nie etwas.
- `SongMO.excludeServerDeleteUncachedSongsFetchPredicate` blendet Songs ohne `size > 0` oder ohne verfügbares Album aus.

**Lösung:**

| Datei | Änderung |
|---|---|
| `AmperfyKit/Api/BackendApi.swift`, `LibrarySyncerProxy.swift`, `Subsonic/SubsonicLibrarySyncer.swift`, `Ampache/AmpacheLibrarySyncer.swift` | `searchArtists/Albums/Songs` geben die Treffer jetzt als `[NSManagedObjectID]` in Server-Reihenfolge zurück (`@discardableResult`, bestehende Aufrufer bleiben unverändert). Vor der Rückgabe werden permanente IDs geholt, weil neu angelegte Objekte sonst temporäre IDs hätten, die im Main-Kontext ins Leere zeigen. Ampache liefert Künstler nur als Set, dort ist die Reihenfolge also nicht garantiert. |
| `AmperfyKit/Storage/LibraryStorage+MultiWordSearch.swift` (neu) | Lokale Mehrwort-Suche: Jedes Wort muss in Titel, Künstler oder Album vorkommen. Wörter auf „s“ werden auch ohne das „s“ probiert („valentines“ findet „Valentine's“). Ranking: Anzahl der Wörter im Hauptnamen, danach alphabetisch. Die Größen- und Album-Bedingung für Songs fällt hier weg. |
| `AmperfyKit/Storage/LibraryStorage.swift` | `context` von `private` auf `private(set)`, damit die neue Extension lesend darauf zugreifen kann (eine Zeile). |
| `Amperfy/Screens/ViewController/SearchVC.swift` | 300 ms Debounce, die vorherige Suche wird abgebrochen. Zuerst erscheinen die lokalen Treffer. Sobald alle drei Server-Anfragen fertig sind, folgen die Server-Treffer in Server-Reihenfolge, lokale Treffer ohne Server-Treffer werden hinten angehängt. Limits: 25 Songs, je 10 Alben, Künstler und Playlists. Der Scope „Cached“ sucht nur lokal. Die doppelte Logik für die beiden Scopes ist zusammengelegt. |
| `AmperfyKitTests/Cases/Player/MusicPlayerTest.swift` | Mock an die neue Signatur angepasst. |

### 2. Design Phase 1: Fundament und Player-Gefühl (Commits `589b4a88` bis `5597dca5`)

Plan und Begründungen stehen in `DESIGN-AUDIT.md`.

| Datei | Änderung |
|---|---|
| `Amperfy/Screens/Basics/DesignTokens.swift` (neu) | `DS`: Abstände, Radien, Schriften mit Dynamic Type, Farben, `DS.haptic(_:)` |
| `Amperfy/Screens/Basics/ArtworkColorCache.swift` (neu) | Cover-Farben im Hintergrund berechnen und cachen |
| `Amperfy/Screens/Player/PlayerControlView+ForkStyle.swift` (neu) | Slider in Label-Farbe statt Theme-Tint, Format/Bitrate kleiner und gedimmt |
| `PlayerControlView.swift` | 1 Zeile: `applyForkStyle()` in `prepare` |
| `PopupPlayer+Visuals.swift` | `dominantColors` nicht mehr synchron im Main-Thread, kein Theme-Farb-Blitz |
| `PlayerUIHandler.swift`, `PopupPlayerVC.swift` | Haptik bei Play/Pause, Skip (nicht auf dem Mac), Favorit |
| `MiniPlayerView.swift` | iOS: Titel 14 pt semibold über dem Künstler, linksbündig, semantische Farben, Fortschritt in Label-Farbe. Wisch links/rechts = Skip mit Slide-Animation, Wisch hoch = Player öffnen. Neuer Code als Extension am Dateiende |
| `HomeVC.swift` (`SectionHeaderView`) | Titel bündig mit den Covern (doppelter 16-pt-Einzug entfernt), Schrift `DS.Font.sectionTitle` |
| `AmperfyKit/Storage/EntityWrappers/Playlist.swift` | Collage nur aus verschiedenen Covern. Bei weniger als 4 verschiedenen Covern wird das erste allein gezeigt |
| `PlayableTableCell.swift` | Auf der Albumseite entfällt die Künstlerzeile, wenn der Track vom Albumkünstler ist |

Offen aus Phase 1: Die blaue Playlist-Platzhalterkachel ist ein vorgerendertes Asset (`getGeneratedArtwork`).
Erledigt in Phase 3 (`UIImage+MutedArtwork.swift`).

**Design-Tokens (Stand UI-18, nur iPhone, `DS` in `DesignTokens.swift`):**

| Token | Dunkel | Hell | Verwendung |
|---|---|---|---|
| `DS.Color.background` (Grund) | #0B0B0F | `systemBackground` | Listen, Seiten |
| `surface` (Fläche) | #15151B | `secondarySystemBackground` | Karten, Zeile des laufenden Songs |
| `surfaceRaised` (Erhöht) | #1E1E26 | `tertiarySystemBackground` | Pille „Zufall“, erhöhte Flächen |
| `line` (Linie) | #2A2A33 | `separator` | nur wo eine Linie wirklich nötig ist |
| `text` / `text2` / `text3` | #F5F4F8 / #A6A5B4 / #8A899A | `label` / `secondaryLabel` / `tertiaryLabel` | Titel / Unterzeilen, „…“, Tracknummern / inaktive Tabs, Info in Albumzeilen |
| `accent` (Mint, `ForkAccent.fixedColor`) | #7FE7CB | #0E8F73 | Tint, Auswahl, Laufend, „Abspielen“ |
| `onAccent` | #0B0B0F | Weiß | Text und Icons auf Mint |

Schriften: SF Pro Rounded (`.rounded`) für `display` 34 Heavy (große Nav-Titel), `detailTitle` 28 Heavy, `sectionTitle` 22 Bold,
`navTitle` 17 Bold, `pill` 15 Bold. Zeilen: `songTitle` 16 Semibold, `cellSubtitle` 13 Regular in Text 2, Zahlen mit `trackNumber`/`cellDuration`
(feste Ziffern). Radien: `Radius.rowArtwork` 8 (Cover in Zeilen), `card` 14, `nowPlayingRow` 12, Knöpfe und Chips `.capsule`, Künstler rund.
iPad und Mac behalten die Werte von Phase 6 (#121212 / #1E1E1E / #2A2A2A, Theme-Farbe, SF Pro).

### 3. Design Phase 2: Detailseiten (Commits `c7047d01` bis `d45c6c51`)

| Datei | Änderung |
|---|---|
| `Amperfy/Screens/View/ImmersiveDetailHeaderView.swift` (neu) | Header für Album, Playlist, Genre, Künstler. Großes Cover mit Schatten, Verlauf aus der Cover-Farbe, fetter Titel, Künstler antippbar, Aktionszeile (Favorit, Download, Radio, Shuffle, runder Play-Knopf). Stretch beim Überziehen, Titel blendet in die Nav-Bar über. Nutzt die bestehende `DetailHeaderConfiguration` |
| `Amperfy/Screens/View/ArtistHighlightsView.swift` (neu) | Künstlerseite: „Popular“ (Top 5 nach `playCount`), Diskografie-Shelf (neueste zuerst), Künstler-Radio (meistgehörter Song + `getSimilarSongs2`) |
| `Amperfy/Screens/View/TableCells+ForkStyle.swift` (neu) | Schriften für `PlayableTableCell` und `GenericTableCell`, kein Chevron mehr |
| `AlbumDetailVC`, `PlaylistDetailVC`, `GenreDetailVC` | je 2 Zeilen: Typ und Erzeugung des Headers |
| `ArtistDetailVC` | Header + Highlights. Die Albenzeilen der Tabelle werden auf Höhe 0 geklappt, solange die Shelf sichtbar ist (bei Suche wieder sichtbar). Die Datenquelle bleibt gleich, damit FRC-Updates konsistent sind |
| `PlayableTableCell.swift`, `GenericTableCell.swift` | je 1 Zeile: `applyForkStyle()` |
| `DesignTokens.swift` | `detailTitle`, `cellTitle`, `cellSubtitle` |

`GenericDetailTableHeader` bleibt für Podcasts und den Playlist-Editor (`PlaylistEditVC`, Namensbearbeitung) im Einsatz.
Die UI-Texte der neuen Views sind wie der Rest der App englisch („Popular“, „Discography“).

### 4. Design Phase 3: Home (Commits `03e0ed7c` bis `651774d7`)

Maßnahmen 7, 11, 15 aus `DESIGN-AUDIT.md` und der offene Punkt aus Phase 1 (Playlist-Platzhalter).

**Aufbau von Home:** oben ein 2×3-Raster „Recently Played“ (erste Kachel fest „Favorite Songs“, dann die fünf
zuletzt gehörten Alben, Playlists und Künstler), darunter die große Shelf „Recently Added“, dann die bisherigen
Shelves, Random-Sektionen am Ende. „Random Artists“ hat runde Zellen.

| Datei | Änderung |
|---|---|
| `AmperfyKit/Storage/HomeSection.swift` | Neue Fälle `recentlyPlayed`, `recentlyAdded` **am Ende** (Codable/Int). Neue Default-Reihenfolge ohne Random am Anfang |
| `AmperfyKit/Storage/HomeSection+ForkMigration.swift` (neu) | Einmalige Migration pro Account: neue Sektionen sichtbar oben einfügen, Random-Sektionen ans Ende. Welche alten Sektionen sichtbar sind, bleibt gleich |
| `AmperfyKit/Storage/Settings.swift` | 1 Feld `_forkHomeSectionsVersion` (optional, alte Settings decodieren weiter) |
| `AmperfyKit/Storage/LibraryStorage+ForkHome.swift` (neu) | `getRecentlyPlayedContainers`: Alben, Künstler, Playlists nach `lastPlayedDate`, einzeln gespielte Songs zählen für ihr Album. `getRecentlyAddedAlbums`: Alben der neuesten Songs nach `addedDate`, aufgefüllt mit `newestIndex` |
| `AmperfyKit/Assets/UIImage+MutedArtwork.swift` (neu) | Playlist-Platzhalter als dynamisches Bild: hell = hellgraue Fläche + Icon in gedämpfter Theme-Farbe, dunkel = Fläche `white 0.16` + Icon `white 0.55`. Hook: 1 Zeile in `getGeneratedArtwork` |
| `Amperfy/Screens/View/Collection/ShelfLayout.swift` (neu) | `ShelfStyle` (`tileGrid`, `standard`, `large`, `circle`) und Layout-Sektionen dazu. Unabhängig von Home |
| `.../TileCollectionCell.swift`, `LargeAlbumCell.swift`, `ArtistCircleCell.swift` (neu) | Zellen mit `display(container:)` für Bibliotheks-Objekte, `display(title:…, image:)` für Treffer außerhalb der Bibliothek (YouTube) und `displaySkeleton()` |
| `.../ShelfArtworkView.swift`, `SkeletonView.swift`, `GradientArtworkView.swift` (neu) | Gemeinsamer Cover-Bereich (Entity, Bild, Verlauf, Skeleton), Shimmer (aus bei „Bewegung reduzieren“), Verlaufs-Cover mit Symbol (Favorite Songs) |
| `Amperfy/Screens/ViewController/HomeVC+Fork.swift` (neu) | `HomeCellItem` (Entity, Favorite-Songs-Kachel, Skeleton), Zelle und Layout je Sektion, Snapshot mit Skeletons, leere Sektionen ausgeblendet, Leerzustand („Sync Library“, „Edit Home“, Offline-Hinweis), Tap im Raster spielt Album/Playlist sofort |
| `Amperfy/Screens/ViewController/HomeManager+Fork.swift` (neu) | Daten der neuen Sektionen, `HomeForkObserver` (FRC auf Songs nach `lastPlayedDate`/`addedDate`, entprellt), Ladezustand, `syncLibraryForHome()` |
| `HomeVC.swift` | Hooks: Item-Typ, `configureForkLayout()`, Zell-Provider, Snapshot, Header per `sectionIdentifier`, Auswahl. Ein paar `private` auf intern |
| `HomeManager.swift` | Hooks: Migration im `init`, `loadingSections` um die Remote-Syncs, Aufruf der Fork-Controller. Vier Eigenschaften von `private` auf intern |
| `DesignTokens.swift` | `tileTitle`, `shelfTitle`, `shelfSubtitle`, `tileSurface`, `skeleton`, `favoritesGradient` |
| `CarPlayHomeTabExtension.swift` | neue Fälle im `switch` |

**Verhalten:**

- Tap im Raster: Album und Playlist spielen sofort (fehlen die Songs, werden sie vorher geladen), Künstler öffnen
  ihre Seite, „Favorite Songs“ öffnet die Liste. Langes Drücken zeigt wie bisher Vorschau und Menü.
- Skeletons erscheinen, solange eine Sektion noch keine Daten hat oder ihr Remote-Sync läuft. Danach verschwinden
  leere Sektionen ganz.
- „Recently Added“ füllt sich aus `Song.addedDate`. Fertige YouTube-Downloads erscheinen dort, sobald Navidrome sie
  gescannt und Amperfy den Song synchronisiert hat (Roadmap 2: Sync per `search3` nach `fertig`).
- Für „Similar from YouTube“ (später) reichen `ShelfLayout.section(.large)` bzw. `.circle` plus die
  `display(title:…, image:)`-Varianten der Zellen.

**Nicht geändert:** `AlbumCollectionCell` und alle XIBs. Die Standard-Shelves nutzen weiter die alte Zelle.
Die Zwischen-Commits wurden nicht einzeln gebaut, der letzte Stand (`651774d7`) baut und läuft auf dem iPhone.

### 5. Design Phase 4: Suche + YouTube Music (Commits `69eb542d` bis `f8c4a9fe`)

Maßnahmen 8 und 9 aus `DESIGN-AUDIT.md` und Roadmap Punkt 2.

| Datei | Änderung |
|---|---|
| `AmperfyKit/Api/SongpickerClient.swift` (neu) | `SongpickerConfig` (URL-Konstante `http://10.66.66.6:8781`, Proxy-Port `4534`, Schalter `isEnabled`, beides zur Laufzeit setzbar für Phase 5). `SongpickerHit` behält das komplette Treffer-JSON für `POST /api/get`. `SongpickerClient`: `search`, `requestDownload`, `jobs` |
| `AmperfyKit/Api/YouTubeMusicJobMonitor.swift` (neu) | Status je Treffer (`online`, `waiting`, `downloading`, `saving`, `inLibrary`, `failed`). Pollt `/api/jobs` alle 1,5 s, solange ein verfolgter Download läuft. Notification `.youTubeMusicStatusChanged`, Callback `onDownloadFinished` nur für neue `fertig`-Jobs |
| `AmperfyKit/Api/YouTubeMusicLibrarySync.swift` (neu) | Nach `fertig`: `search3` nach dem Titel, Abgleich über die letzten 3 Pfadteile (Künstler/Album/Datei) von `path`, danach `librarySyncer.searchSongs`, damit Song, Album und `addedDate` lokal landen. Versuche nach 5 bis 60 s, etwa 4 min lang (Navidrome braucht ca. 35 s für den Scan) |
| `AmperfyKit/Storage/LibraryStorage+YouTubeMusic.swift` (neu) | Platzhalter-Songs `ytm-<videoId>` ohne Album und ohne Größe, deshalb in keiner Bibliotheksliste. `YouTubeMusicHitStore` (UserDefaults, max. 500) merkt sich Künstlername und Cover-URL. Unbenutzte Platzhalter (nicht in Queue/Playlist/Verlauf/Cache) werden beim Start der Suche gelöscht |
| `BackendProxy.swift` | Stream- und Download-URL für `ytm-…`: `stream.view?…&format=mp3` auf Port 4534 (Host bleibt der des Accounts). Lesezugriff `forkSubsonicServerApi` für das rohe search3 |
| `SubsonicApi.swift`, `SubsonicArtworkDownloadDelegate.swift`, `Song.swift` | Je 1 bis 3 Zeilen: Zugriff auf die Server-API, Cover-URL des Treffers als Artwork, Künstlername aus dem HitStore |
| `LibrarySyncerProxy.swift` | Kein `sync(song:)`, Scrobble, Now Playing, Rating, Favorit, Similar Songs für Platzhalter (Navidrome kennt die IDs nicht) |
| `Amperfy/Screens/ViewController/SearchVC+Fork.swift` (neu) | `SearchItem` (eigener Item-Typ statt `NSManagedObjectID`), `SearchForkState`, Genres, Top-Treffer-Ranking, YouTube-Suche parallel zur Server-Suche, Zellen, Menü, Auswahl, Badge-Updates |
| `.../View/SearchTopHitCell.swift`, `SearchGenreGridCell.swift`, `SearchStatusCell.swift`, `SourceBadgeView.swift` (neu) | Top-Treffer-Karte, Genre-Raster (TileCollectionCell + `ShelfLayout.tileGrid(columns: 2)` in einer Tabellenzeile), Ladezeile, Badge (Wolke, drehender Ring, Haken, Ausrufezeichen) |
| `SearchVC.swift` | Hooks: 3 neue Sektionen, Item-Typ, je eine Zeile pro `switch`, Kontextmenü-Override, Aufrufe in `updateSearchResults`/`display`/`updateContentUnavailable`. Ergebnis-Arrays und `account` von `fileprivate`/`private` auf intern |

**Verhalten:**

- **Leeres Suchfeld:** die letzten 8 Suchen, darunter bis zu 12 Genre-Kacheln (meiste Alben zuerst). Kachel = erstes
  gecachtes Albumcover des Genres, Hintergrund in dessen Farbe (`ArtworkColorCache`), sonst eine feste Farbe aus dem Namen.
  Tap öffnet die Genre-Seite.
- **Reihenfolge der Treffer:** Top Result, Songs, YouTube Music, Artists, Albums, Playlists.
- **Top Result:** bester Kandidat aus erstem Künstler, Song, Album und YouTube-Treffer. Punkte = 2 × Anteil der
  Suchwörter in Name + Künstler, +1 wenn der Name genau der Suche entspricht. Mindestens die Hälfte der Wörter muss
  passen. Ein gezeigter Top-Treffer wird nur durch einen besseren ersetzt (kein Springen). YouTube-Treffer tragen
  das Text-Label „YouTube Music“ und das Badge.
- **Ladezustand:** Solange Server- oder YouTube-Suche laufen und noch nichts da ist, steht „Searching…“ mit Spinner
  statt „No Results“. Gibt es schon lokale Treffer, zeigt die YouTube-Sektion eine Zeile „Searching YouTube Music…“,
  bei Fehler „YouTube Music is not reachable“.
- **YouTube-Sektion:** nur Treffer mit `library == null`, max. 15. Dieselbe `PlayableTableCell` wie lokale Songs
  (Platzhalter-Song mit Cover), rechts das Badge. Tap spielt über die normale Warteschlange, der Proxy startet dabei
  den Download, die App verfolgt den Job. Menü (lange drücken oder „…“): Play, Play Next, Add to Queue, Add to Library.
- **Nach `fertig`:** Sync per search3 (siehe oben), danach erscheint das Album in „Recently Added“ auf Home.

**Maßnahme 9: Menüs und Swipes in Alltagssprache (Commit `c0fd0dc1`)**

| Datei | Änderung |
|---|---|
| `AmperfyKit/Storage/SwipeActionSettings+Fork.swift` (neu) | Neue Swipe-Defaults: links (leading) Play Next / Add to Queue, rechts (trailing) Favorite / Download. Einmalige Migration `migrateForkSwipeDefaults()`, ersetzt nur die unveränderten Original-Defaults. `ForkMenuText.relabel` benennt Menüeinträge um, ohne die Literale im Upstream-Code zu ändern |
| `EntityPreviewVC.swift` | „Play Next“ und „Add to Queue“ direkt im Menü (ein Tap), Context-Queue unter „More Queue Options“ („Play Next in Current List“, „Add to End of Current List“). Podcast-Queue ebenfalls „Play Next“ / „Add to Queue“. „Song Radio“ statt „Instant Mix“ im Wiedergabe-Namen und Hinweis. Aufruf von `relabel` vor dem `return` |
| `PlayerControlView.swift` | 1 Zeile: `relabel` für das Player-Menü |
| `SwipeActionSettings.swift` | Neue Texte für Swipe-Knöpfe und Einstellungen, `defaultSettings` zeigt auf die Fork-Defaults, die alten als `upstreamDefaultSettings` |
| `Settings.swift`, `AppDelegate.swift` | Feld `_forkSwipeDefaultsVersion` (optional), Migration beim Start |

Umbenannt: Song Radio, Go to Album/Artist/Podcast, Add to / Remove from Favorites, Remove Download, Shuffle,
Clear Queue (statt Clear User Queue), Add Current List to Playlist, Scroll to Now Playing.

**Bekannte Grenzen:**

- Läuft der Account nicht über Port 4533/4534 desselben Hosts (z. B. HTTPS-Reverse-Proxy), stimmt die Proxy-URL nicht.
  Erledigt in Phase 5: Settings › YouTube Music › „Custom Proxy URL“.
- Taucht ein per Abspielen gestarteter Download nicht innerhalb von 60 s in `/api/jobs` auf, fällt das Badge auf die Wolke zurück.
- Der Platzhalter bleibt nach dem Sync ein eigener Song (z. B. im Verlauf). Er wird gelöscht, sobald ihn nichts mehr nutzt.
- Ein in einer früheren Sitzung gezeigter Treffer, der aus dem Verlauf gespielt wird, wird nicht verfolgt (das Treffer-JSON fehlt).

### 6. Design Phase 5: Library und Player-Feinschliff (Commits `d3c1ec2b` bis `9165849a`)

Maßnahmen 12 und 13 aus `DESIGN-AUDIT.md`, Roadmap Punkte 3 und 4 (Download-Übersicht).

| Datei | Änderung |
|---|---|
| `AmperfyKit/Storage/UserSettings+Songpicker.swift` (neu) | `songpickerURL` (Default `http://10.66.66.6:8781`), `isYouTubeMusicEnabled` (Default an), `songpickerProxyURL` (optional). `nil` bedeutet jeweils Default |
| `AmperfyKit/Storage/Settings.swift` | 3 optionale Felder `_forkSongpickerURL`, `_forkYouTubeMusicEnabled`, `_forkSongpickerProxyURL` (alte Settings decodieren weiter) |
| `AmperfyKit/Api/SongpickerClient.swift` | `SongpickerConfig.customProxyURL`, `apply(_:)` aus den Settings, `normalizedURL(from:)` (ergänzt `http://`). `proxyURL(rewriting:)` nimmt mit eigener Proxy-URL deren Schema, Host, Port und Pfad, gefolgt vom `rest/…`-Teil. `SongpickerJob.started` (Unix-Zeit oder ISO 8601) |
| `AmperfyKit/Api/YouTubeMusicJobMonitor.swift` | `jobList` (`YouTubeMusicJobEntry`: laufende zuerst, dann neueste), `startObserving`/`stopObserving`, `retry(videoId:)`, `hasLoadedJobs`, `lastError`. Gepollt wird nur, solange ein verfolgter Download läuft oder die Übersicht sichtbar ist (1,5 s, ohne laufenden Job 5 s) |
| `AmperfyKit/Storage/LibraryStorage+YouTubeMusic.swift` | `YouTubeMusicHitStore` merkt sich zusätzlich das Treffer-JSON (optional), `hit(forVideoId:)` für Übersicht und Retry |
| `AmperfyKit/Storage/LibraryStorage+ForkLibrary.swift` (neu) | Alben, Künstler, Playlists für das Raster: nach `lastPlayedDate` absteigend, nie gespielte alphabetisch dahinter, max. 150 |
| `Amperfy/Screens/ViewController/ForkLibraryVC.swift` (neu) | Library-Raster: Chips, angeheftete Kachel „Favorite Songs“ + 7 zuletzt genutzte (TileCollectionCell, `ShelfLayout.tileGrid`), „Browse“ mit den übrigen Kategorien aus den Library-Einstellungen. Filter-Raster mit `LargeAlbumCell` (2 Spalten) bzw. `ArtistCircleCell` (3 Spalten), oben „All Albums/Artists/Playlists“ zur alten, sortierbaren Liste. Kontextmenü wie auf Home. Listen-Knopf oben rechts öffnet die alte Kategorienliste (inkl. Bearbeiten) |
| `.../View/Collection/FilterChipCell.swift`, `.../View/DownloadJobCell.swift` (neu) | Chip (ausgewählt = in Label-Farbe gefüllt), Job-Zeile mit Cover, Status, `SourceBadgeView` und „Retry“ |
| `AppStoryboard.swift` | `segueToLibrary` liefert auf dem iPhone `ForkLibraryVC`, `segueToLibraryList` die alte `LibraryVC` (iPad/Mac unverändert) |
| `Amperfy/SwiftUI/Settings/YouTubeMusicSettingsView.swift` (neu) | Seite „YouTube Music“: Schalter, Songpicker-URL mit „Test Connection“ (`/api/jobs`) und „Reset to Default“, Schalter + Feld „Custom Proxy URL“. Speichert sofort und setzt `SongpickerConfig` |
| `NavigationTarget.swift`, `SettingsView.swift`, `AppDelegate.swift` | Neuer Eintrag `youTubeMusic`, Link in den Settings, `SongpickerConfig.apply` beim Start |
| `Amperfy/Screens/Player/PopupPlayer+Fork.swift` (neu) | `ForkPlayerTransition`: Zoom-Übergang (`preferredTransition = .zoom`) vom Mini-Player-Cover zum Player-Cover, Vollbild statt Sheet, Griff oben zum Schließen. Wisch nach oben auf dem Cover = Queue, in der Queue über den oberen Rand ziehen = zurück. Lyrics-Karte laden, ein- und ausblenden, Zeit nachführen |
| `Amperfy/Screens/Player/LyricsCardView.swift` (neu) | Karte unter Titel und Künstler: aktuelle Zeile fett, nächste gedimmt, Fläche in abgedunkelter Cover-Farbe. Tap öffnet die volle Lyrics-Ansicht |
| `MiniPlayerView.swift`, `PopupPlayerVC.swift`, `PopupPlayer+Visuals.swift`, `LargeCurrentlyPlayingPlayerView.swift` | Nur Hooks (je 1 bis 4 Zeilen): Zoom vorbereiten, `forkConfigurePlayer()`, Lyrics neu laden / Zeit / sichtbar, Karte einfärben |

**Verhalten:**

- **Library (iPhone):** Ohne Chip: „Favorite Songs“ + zuletzt genutzte Alben, Playlists und Künstler, darunter „Browse“
  (Songs, Genres, Podcasts usw., je nach Library-Einstellungen). Chip erneut antippen = zurück zur Übersicht.
  Im Offline-Modus nur gecachte Einträge.
- **Downloads:** alle Jobs, die der Songpicker kennt (auch von anderen Geräten), laufende oben. Tap auf eine
  fehlgeschlagene Zeile oder „Retry“ schickt `POST /api/get` erneut (mit dem gemerkten Treffer-JSON, sonst nur
  `id`, `title`, `source`, `kind`). Darunter „Downloaded on This Device“ (die bisherige `DownloadsVC`).
  Ist YouTube Music aus, steht dort ein Hinweis.
- **Player:** öffnet immer auf dem Cover (die Queue merkt sich der Player nicht mehr über `playerDisplayStyle`).
  Herunterwischen schließt den Player, aber nicht in der Queue und nicht in der vollen Lyrics-Ansicht.
  Die Lyrics-Karte erscheint nur, wenn der Song Lyrics hat (Subsonic, Musikmodus).

**Bekannte Grenzen:**

- Die Karte nimmt dem Cover Höhe weg (Stack-View aus der XIB). Auf kleinen iPhones wird das Cover dadurch kleiner. Behoben mit UI-11 (Abschnitt 10).
- Das Feld `started` von `/api/jobs` ist nur geraten (Unix-Zeit oder ISO 8601). Fehlt es, sortiert die Liste
  fertige Jobs ohne Zeitangabe ans Ende.
- Die Zwischen-Commits `d3c1ec2b` bis `be5d7705` haben die neuen Dateien unvollständig im Projekt eingetragen,
  erst `9165849a` baut. Der Stand `9165849a` baut und startet auf dem iPhone.

### 7. Design Phase 6: Dark-first und Zellen (Commits `353607f9` bis `c5b5f5a6`)

Maßnahme 14 aus `DESIGN-AUDIT.md` und der Rest von Maßnahme 10. Davor Upstream gemergt (`965e7284`, ohne Konflikte).

| Datei | Änderung |
|---|---|
| `AmperfyKit/Storage/UserSettings+Appearance.swift` (neu) | Einmalige Migration `migrateForkDarkFirst()` (Feld `_forkAppearanceVersion`): steht `appearanceMode` noch auf „System“, wird es „Dark“. „Light“ bleibt, eine spätere Wahl bleibt ebenfalls. `isNeutralAccent` (Default aus) und `ForkAccent.isNeutral` als globaler Schalter |
| `AmperfyKit/Storage/Settings.swift` | 2 optionale Felder `_forkAppearanceVersion`, `_forkNeutralAccent` |
| `AmperfyKit/Storage/SettingEnumerations.swift` | je 1 Zeile in `asColor` und `contrastColor`: bei Neutral Accent `label` bzw. `systemBackground` statt Theme-Farbe |
| `AppDelegate.swift` | Migration und `ForkAccent.isNeutral` beim Start, vor `setAppTheme` |
| `Amperfy/SwiftUI/Settings/NeutralAccentSettingsSection.swift` (neu) | Settings › Display › „Neutral Accent“, speichert sofort und färbt die geladenen Views neu (wie der Theme-Wechsel im Original). Hook: 1 Zeile in `DisplaySettingsView` |
| `DesignTokens.swift` | `DS.Color.background` / `surface` / `surfaceRaised` (#121212 / #1E1E1E / #2A2A2A, hell: `systemBackground` / `secondarySystemBackground` / `tertiarySystemBackground`). `tileSurface` (#1E1E1E) und `skeleton` (#2A2A2A) auf den Graustufen, hell weiter `tertiarySystemFill`. `DS.Font.songTitle` (16 semibold) |
| `Amperfy/Screens/Basics/ForkSurface.swift` (neu) | Alle Plain-Listen (`BasicTableViewController`: Library-Listen, Suche, Detailseiten) auf `DS.Color.background`, angeheftete Sektionsköpfe in derselben Farbe, Listenzellen durchsichtig. Auf dem Mac aus |
| `BasicTableViewController`, `BasicTableCell`, `HomeVC`, `ForkLibraryVC`, `ImmersiveDetailHeaderView`, `SearchStatusCell` | Hooks: Flächenfarbe statt `systemBackground`, Verlauf im Header endet in der Flächenfarbe |
| `TableCells+ForkStyle.swift` | `PlayableTableCell`: Cover 56 pt (Queue 40 pt), Radius 4, Titel 16 semibold, Untertitel 13. Das Cover ragt in die Zellränder, die Zeilenhöhe (66 pt) bleibt, `rowHeight` und XIB unverändert |
| `Amperfy/Screens/View/NowPlayingBarsView.swift` (neu) | Kleines animiertes Equalizer-Icon (4 Balken). Bewegt sich nur beim Abspielen, steht still bei Pause und bei „Bewegung reduzieren“ (reagiert auch auf Umschalten zur Laufzeit) |
| `Amperfy/Screens/View/PlayableTableCell+NowPlaying.swift` (neu) | „Läuft gerade“: Titel in Akzentfarbe, Balken über dem abgedunkelten Cover bzw. statt der Tracknummer (Albumseite). Ersetzt auf iPhone/iPad den `VYPlayIndicator`, folgt Play/Pause/Stop selbst |
| `PlayableTableCell.swift` | Nur Hooks: Layout nach `refresh`, Now-Playing statt PlayIndicator, Hintergrund, Download-Icon in der Queue aus |
| `Amperfy/Screens/Player/SectionHeader/CurrentlyPlayingTableCell+Fork.swift` (neu) | Queue im Player: aktueller Song oben auf einer abgerundeten Karte, Cover-Radius 8, Balken-Badge auf dem Cover. Hook: 1 Zeile in `refresh` |

**Verhalten:**

- **Erststart nach dem Update:** Wer die Darstellung nie geändert hat, sieht die App dunkel. „Light“ bleibt hell.
  Eine danach gewählte Einstellung (auch „System“) bleibt erhalten, die Migration läuft nur einmal.
- **Neutral Accent:** Knöpfe, Links, Schalter und der Titel des laufenden Songs in Weiß (Dunkel) bzw. Schwarz (Hell).
  Die Theme-Farbe bleibt gespeichert und gilt wieder, sobald der Schalter aus ist. Farben aus Covern bleiben.
- **Queue im Player:** Zeilen mit 40-pt-Cover ohne Download-Icon, rechts weiter der Griff zum Sortieren.
- **Suche:** Das YouTube-Badge sitzt weiter als `accessoryView` rechts in der Zeile und ist vom größeren Cover links nicht betroffen.

**Bekannte Grenzen:**

- Die Migration kann „nie geändert“ und „bewusst System gewählt“ nicht unterscheiden (beides `.unspecified`).
  Wer vor Phase 6 bewusst „System“ gewählt hatte, landet einmalig auf „Dark“ und muss neu wählen.
- Mit Neutral Accent ist der Titel des laufenden Songs weiß wie die übrigen, nur die Balken zeigen ihn an.
- Der Mac behält Flächen, Zellmaße und den `VYPlayIndicator` des Originals.

### 8. Rebranding: Drift (Commits `50594cb3` bis `c0938f6c`)

Davor Upstream gemergt (`66a11512`, ohne Konflikte). Grundsatz: Nur was der Nutzer sieht, heißt jetzt „Drift“.
Alles, woran Daten, Logins und Downloads hängen, bleibt „Amperfy“.

| Datei | Änderung |
|---|---|
| `AmperfyKit/Common/ForkBrand.swift` (neu) | `ForkBrand.name = "Drift"` und die Angaben zum Original (Name, Autor, Repo-URL). Liegt in AmperfyKit, weil auch dort ein sichtbarer Text steht |
| `Amperfy/Info.plist` | `CFBundleDisplayName` = `Drift` (neu) und `CFBundleName` = `Drift` (statt `$(PRODUCT_NAME)`, daraus baut Mac Catalyst das App-Menü). Siri: alternative Namen „Drift Music“ und „Amperfy“, damit alte Sprachbefehle weiter funktionieren. `UILaunchScreen` statt `UILaunchStoryboardName` |
| `Amperfy/AppIntentVocabulary.plist` | Beispielsätze „… in Drift“ |
| `AppDelegate`, `MiniPlayerSceneDelegate`, `LoginVC`, `WelcomePopupPresenter`, `IntentManager`, `XCallbackURLsSetttingsView`, `SupportSettingsView`, `PlayerSettingsView`, `BackendAudioPlayer` | Je 1 bis 2 Zeilen: „Amperfy“ im sichtbaren Text → `ForkBrand.name` (Neustart-Notification, Mini-Player-Fenstertitel, Login-Titel, Notification-Onboarding, X-Callback-Doku, Mail-Alert und Mail-Betreff, Transcoding-Hinweis, Fehlermeldung „nicht abspielbar“) |
| `Amperfy/SwiftUI/Settings/ForkAboutSection.swift` (neu) | Settings-Hauptseite (auf dem Mac Tab „General“), Sektion „About Drift“: „Based on Amperfy by Maximilian Bauer, licensed under GPLv3“ mit Link auf github.com/BLeeEZ/amperfy. Hook: 1 Zeile in `SettingsView` |
| `AmperfyKit/Assets/ForkAppIcon.icon` (neu) | Icon-Composer-Datei: drei Wellen (Ebenen `Wave1`–`Wave3`, Deckkraft 100/65/35 %) in Theme-Blau `#0A84FF` auf `#121212`, Default und Dark gleich, Tinted in Weiß. Ebenen-Quellen als SVG in `Design/ForkAppIcon/` |
| `project.pbxproj` | `ForkAppIcon.icon` in denselben Resources-Phasen wie `AmperfyAppIcon.icon`, `ASSETCATALOG_COMPILER_APPICON_NAME = ForkAppIcon` (Debug und Release) |
| `Assets.xcassets/LaunchBackground.colorset`, `LaunchGlyph.imageset` (neu) | Splash: Hintergrund in beiden Modi `#121212` (passend zur dunklen App, auch bei hellem System), Wellen-Glyph 96 pt ohne Hintergrund (1x/2x/3x aus `Design/ForkAppIcon/launch-glyph.svg`) |
| `SceneDelegate.swift` | 1 Zeile: Fenster-Hintergrund `DS.Color.background`, damit zwischen Splash und Home nichts aufblitzt |
| `Amperfy/ForkLaunchScreenCache.swift` (neu) | Löscht einmalig `Library/SplashBoard` (Key `forkLaunchScreenCacheVersion`). iOS behält nach dem Wechsel vom Storyboard auf `UILaunchScreen` sonst den alten bzw. einen leeren Splash-Snapshot. Nicht auf dem Mac. Hook: 1 Zeile in `AppDelegate` |

**Bleibt bewusst „Amperfy“:**

- **Bundle-ID** `de.knauerleo.amperfy-music`, `PRODUCT_NAME`, Target-, Scheme- und Modulnamen (`Amperfy`, `AmperfyKit`),
  Typnamen (`AmperfyImage`, `AmperfyAppShortcuts` usw.). Die Bundle-ID bestimmt Container, UserDefaults und Keychain.
  Bei einer Änderung wären Login, Datenbank und Downloads weg. Der Rest würde jeden Upstream-Merge zum Konflikt machen.
- **Core-Data-Modell** „Amperfy“ und die Versionsnamen in `CoreDataMigrationVersion`. Eine Umbenennung würde die
  vorhandene Datenbank nicht mehr finden.
- **Technische IDs:** Background-Task-ID `de.familie-zimba.Amperfy.RefreshTask`, Notification-Namen, Activity-Types,
  URL-Schema `amperfy://` (X-Callback). Steht teils in Shortcuts der Nutzer und in der Info.plist.
- **Subsonic-Client-ID** `c=Amperfy`. Navidrome legt pro Client-Name einen Player an. Ein neuer Name hieße neuer Player,
  und dessen Einstellungen (z. B. Transcoding) gingen verloren.
- **Logs:** OSLog-Subsystem, „Cache Location“, `LogData.appName`, Dateiname `AmperfyLog.json`.
- **Lizenz:** Alle Lizenz-Header, der Copyright-Text in `LicenseSettingsView` und `NSHumanReadableCopyright` von AmperfyKit.
  Die GPL verlangt, dass Copyright- und Lizenzhinweise erhalten bleiben.
- `AmperfyAppIcon.icon` bleibt im Projekt und wird weiter mitkompiliert, ist aber nicht mehr das App-Icon.
  `LaunchScreen.storyboard` bleibt unverändert im Projekt, ist aber nicht mehr eingetragen. `AppDelegate.name` wird nirgends verwendet.

**Mac Catalyst:**

- Das Icon kompiliert `actool` für macOS fehlerfrei zu `ForkAppIcon.icns` und `Assets.car`.
- Einen Splash zeigt macOS bei Catalyst-Apps nicht. Der Wechsel auf `UILaunchScreen` ist dort also folgenlos,
  ein Storyboard muss für den Mac nicht bleiben.
- Menü „About/Hide/Quit Drift“ über `CFBundleName`. Die Datei heißt weiter `Amperfy.app` (Finder zeigt den Dateinamen).

**Bekannte Grenzen:**

- Der Splash ist immer dunkel. Wer die App auf „Light“ stellt, sieht beim Start kurz `#121212`, dann Hell.
- Den Splash gibt es nur bei einem Kaltstart. Holt man die App aus dem Hintergrund zurück, zeigt iOS den letzten Bildschirm.
- Den Splash-Cache löscht die App erst bei ihrem ersten Start nach dem Update. Erst der Kaltstart danach zeigt den neuen Splash.
- Das Icon zeigt immer Blau, unabhängig von der Theme-Farbe in der App.

### 9. YouTube Music über den Subsonic-Proxy (TASKS F-1, F-1a, F-1b)

Login über `https://musik.leokna.de` (Caddy → WireGuard → nginx :4534 → Songpicker `/nd` bzw. Navidrome).
Die App spricht nur noch Subsonic mit dem Login-Host. Die Songpicker-API (`/api/…`, ohne Auth) bleibt intern und wird von der App nicht mehr aufgerufen.

| Datei | Änderung |
|---|---|
| `AmperfyKit/Api/SongpickerClient.swift` | `SongpickerClient` (HTTP an `:8781`) und `baseURL` entfernt. `proxyURL(rewriting:)` schreibt nur noch Port 4533 → 4534 um (Account direkt auf Navidrome), sonst bleibt die URL. `SongpickerHit(videoId:title:artist:album:duration:)`, `thumbnailURL(videoId:)` (i.ytimg.com). `SongpickerJob` mit `title`, `artist`, `album`, `songId`, `path`, Parser für `getYtJobs.view?f=json` |
| `SubsonicServerApi.swift` | `requestYtJobs()` (ein Block) |
| `BackendProxy.swift` | `forkYouTubeJobs()`, `forkStartYouTubeDownload(videoId:)`: `stream.view?id=ytm-…&format=mp3`, liest nur bis zum ersten Audio-Byte (~9 s), der Proxy lädt allein weiter. Ein Job im Zustand `fehler` startet dabei neu |
| `YouTubeMusicJobMonitor.swift` | Jobs aus `getYtJobs`, `configure(backendApi:)`, `testConnection()`. „Add to Library“ und Retry über `forkStartYouTubeDownload` |
| `YouTubeMusicLibrarySync.swift` | Abgleich zuerst über `songId` des Jobs, dann Pfad, `ytm-`-Treffer der search3-Antwort ignoriert |
| `LibraryStorage+YouTubeMusic.swift` | `YouTubeMusic.sanitizedProxyAttributes`: Bei `ytm-`-Songs fallen Album, Künstler, Genre, Datum, Pfad weg, `size` = 0, Marker „ ☁︎“ aus dem Titel, Künstlername in den HitStore. `deleteUnusedYouTubeMusicSongs` räumt zusätzlich alte Fake-Einträge auf (Album/Künstler `ytm-…`, Verknüpfungen der Songs). `getOrCreateYouTubeMusicSong` entfällt |
| `SsSongParserDelegate.swift`, `SsAlbumParserDelegate.swift` | Je ein Hook: Attribute bereinigen bzw. Alben `ytm-…` (Such-Album des Proxys) überspringen |
| `SearchVC+Fork.swift`, `SearchVC.swift` | YouTube-Sektion aus den `ytm-`-Songs der Server-Suche (`forkDidReceiveServerSongs`, 1 Zeile Hook vor `display`). Keine eigene YouTube-Anfrage mehr |
| `UserSettings+Songpicker.swift`, `YouTubeMusicSettingsView.swift` | Songpicker-URL entfällt (`_forkSongpickerURL` bleibt ungenutzt in `Settings` stehen). „Test Connection“ fragt `getYtJobs` ab. Custom Proxy URL bleibt optional |
| `AppDelegate.swift`, `ForkLibraryVC.swift` | Monitor mit dem Backend des aktiven Accounts konfigurieren, Texte |

**Proxy-Routen (Subsonic am Login-Host, normale Auth-Parameter, `f=json`):**

| Route | Zweck |
|---|---|
| `stream.view?id=ytm-<videoId>&format=mp3` | Abspielen, startet dabei den Download (F-1) |
| `getYtJobs.view` | Downloads des Accounts mit Zustand (F-1b) |
| `getYtAlbum.view?id=ytm-<videoId>\|ytm-album-<browseId>` | Album mit Songs, pro Song `downloaded`, `navidromeId`, `ytState` (F-8) |
| `getYtArtist.view?id=ytm-<videoId>\|ytm-artist-<channelId>` | Künstler mit Alben, EPs, Singles (F-8) |
| `downloadYtAlbum.view?id=ytm-album-…\|ytm-<videoId>` | ein Job pro fehlendem Song, Antwort `queued`/`skipped` (F-8) |
| `getCoverArt.view?id=ytm-album-…\|ytm-artist-…` | Cover bzw. Künstlerbild, 404 = keins (F-8) |

Die F-8-Anfragen baut `BackendProxy+ForkYouTubeAlbum.swift` aus der `getCoverArt`-URL des Accounts (dieselben Auth-Parameter, kein Eingriff in `SubsonicServerApi`), umgeschrieben per `proxyURL(rewriting:)`.
Fehler (Code 70 usw.) kommen mit dem Text des Proxys an.

**Bekannte Grenzen:**

- `getYtJobs` kennt nur Jobs, die über den Subsonic-Proxy gestartet wurden, ab der Einführung des Endpunkts (2026-10-29).
- Auf dem iPhone getestet (2026-10-29): Test Connection, YouTube-Treffer ohne ☁︎, Abspielen nach ~9 s, Job in Downloads, Song nach ~35 s in Recently Added, keine Fake-Einträge in Albums/Artists. „In Sammlung laden“ ohne Abspielen kommt auf `fertig`, der Proxy lädt also weiter, wenn die App nach dem ersten Byte trennt.
- Die Download-Liste zeigt das Video-Thumbnail von i.ytimg.com (4:3), die Songs selbst das Cover über `getCoverArt`.
- Nach einem Account-Wechsel konfiguriert sich der Monitor erst neu, wenn Suche oder Library geöffnet werden.

### 10. Tasks aus TASKS.md

| Task | Datei | Änderung |
|---|---|---|
| UI-1 | `PodcastDetailVC.swift` | Header `ImmersiveDetailHeaderView` statt `GenericDetailTableHeader` (2 Zeilen). Play spielt die neueste Episode, Shuffle bleibt aus |
| UI-1 | `TableCells+ForkStyle.swift`, `PodcastEpisodeTableCell.swift` | `PodcastEpisodeTableCell.applyForkStyle()`: `DS.Font.songTitle`/`cellSubtitle`/`caption`, Cover-Radius 4, transparenter Hintergrund. Hook am Ende von `refresh()` statt `backgroundColor = .systemBackground` |
| UI-2 | `AlbumsCollectionVC+Fork.swift` (neu), `AlbumsCollectionVC.swift` | All Albums nutzt `LargeAlbumCell` statt `AlbumCollectionCell`. 3 Hooks: Zelle registrieren, Zelle erzeugen, Zellenhöhe = Breite + `forkCaptionHeight`. Flow-Layout bleibt (Rastergröße aus den Settings, Abschnittsköpfe, Index). Mac Catalyst unverändert |
| UI-3 | `TableCells+ForkStyle.swift`, `PlaylistTableCell.swift` | `PlaylistTableCell.applyForkStyle()`: Collage 56 pt statt 70, Radius 4, `DS.Font.songTitle`/`cellSubtitle`, kein Chevron, feste Label-Höhen aus der XIB aus (Dynamic Type). Hook am Ende von `display`. Gilt überall, wo die Zelle vorkommt (Playlists, Suche, Playlist-Auswahl) |
| UI-4 | `DesignTokens.swift`, `PlayerControlView+ForkStyle.swift`, `LargeCurrentlyPlayingPlayerView.swift` | Neue Tokens `playerTitle` (20 bold, max 26), `playerSubtitle` (17, max 22), `playerAlbum` (15, max 19), `playerTime` (12 monospaced digits, max 16). Zeiten, Live-Label, Titel, Künstler, Album im Code gesetzt und bei Size-Class- oder Textgrößen-Wechsel neu, weil die XIB-Variationen sonst die festen Größen zurückbringen. Hook in `prepare(toWorkOnRootView:)`. Die Buttons der XIB haben keine sichtbare Schrift (nur Symbole) und bleiben |
| F-3 | `SubsonicArtistInfo.swift` (neu, AmperfyKit), `SubsonicServerApi.swift`, `ArtistHighlightsView.swift`, `ArtistDetailVC.swift` | `requestArtistInfo2(id:)` (JSON, 12 ähnliche Künstler), Parser `SubsonicArtistInfo` (Bio ohne HTML und ohne „Read more on Last.fm“), `BackendProxy.forkArtistInfo(artistId:)`. Auf der Künstlerseite unter der Diskografie: „Fans Also Like“ als runde Kacheln (nur Künstler aus der eigenen Bibliothek, Tap öffnet die Seite), darunter „About“ mit 4 Zeilen, Tap klappt auf und zu. Hook `contentDidChange` (1 Zeile), weil die Daten nach dem Header kommen. Das Künstlerbild im Header kommt schon über `getCoverArt` (`ar-…`), `largeImageUrl` wird nur geparst |
| F-4 | `SubsonicArtistInfo.swift`, `SubsonicServerApi.swift`, `ArtistHighlightsView.swift` | `requestTopSongs(artistName:count:)` (JSON), `BackendProxy.forkTopSongIds`. Liefern die eigenen `playCount`s weniger als 5 Songs, füllt „Popular“ mit den Last.fm-Top-Songs aus der Bibliothek auf (ohne Doppelte, offline nur gecachte). Songs ohne eigene Plays zeigen das Album statt „0 plays“ |
| UI-6 | `LyricsView+Fork.swift` (neu), `LyricsView.swift`, `LyricTableCell.swift`, `LargeCurrentlyPlayingPlayerView.swift`, `LyricsCardView.swift`, `PopupPlayer+Fork.swift`, `DesignTokens.swift` | Volle Lyrics im Player (nur iPhone) wie die Karte: Zeilen in `DS.Font.lyricsLine` (24 bold, max 34), linksbündig, aktuelle Zeile weiß, übrige 45 % Weiß, auf einer abgerundeten Fläche (`LyricsBackdropView`) in der abgedunkelten Cover-Farbe (`LyricsCardView.surfaceColor`). Tap auf eine Zeile springt wie bisher dorthin. Hooks: `forkCardStyle` + 1 Zeile in `reloadViewModels`, die beiden Attributed Strings des Zellmodells nicht mehr `private`, 1 Zeile in `prepare`. Die Lyrics-Seitenleiste (iPad/Mac, `LyricsVC`) bleibt im Originalstil |
| UI-11 | `PlayerCoverScrollView.swift` (neu, seit UI-20 `PlayerPageScrollView.swift`), `PopupPlayer+Fork.swift` | Die Lyrics-Karte steckt nicht mehr im Stack der XIB. Die große Player-Ansicht liegt in einer Scroll-View mit der vollen Höhe des Platzhalters, die Karte folgt darunter (16 pt Rand). Hat der Song Lyrics, scrollt man nach oben zur Karte, sonst scrollt nichts. Über das Ende der Karte hinausziehen öffnet die Queue (statt des Wischers nach oben, der bei scrollbarem Cover nicht mehr greift). Waagrechte Wischer auf dem Cover (Skip) starten kein Scrollen. Schließen per Herunterwischen nur, wenn das Cover ganz oben steht |
| UI-12 | `SleepTimerChipView.swift` (neu), `AppDelegate+ForkSleepTimer.swift` (neu), `AppDelegateMainMenuExtension.swift`, `PopupPlayer+Fork.swift` | Läuft ein Sleep Timer, zeigt der Player (nur iPhone, Cover und Queue) unter der Optionszeile einen Chip „Pauses at 23:40“ bzw. „Pauses after this Song“. Tap öffnet das bekannte Sleep-Timer-Menü (ändern, ausschalten). Der Chip prüft jede Sekunde, solange er sichtbar ist, und folgt so auch dem Optionsmenü und dem Mac-Menü. Solange er da ist, wächst der Control-Platzhalter um 38 pt, das Cover wird entsprechend kleiner. Pause: `SleepTimerFader` senkt die Lautstärke in den letzten 10 s linear auf 0, pausiert und stellt die Lautstärke danach wieder her. Ausschalten während des Ausblendens stellt sie sofort wieder her. Hook: Rumpf von `activateSleepTimer` ist 1 Zeile. Texte englisch wie der Rest der App (Deutsch kommt mit UI-15) |
| UI-13 | `PlayerAnimatedBackgroundView.swift` (neu), `PopupPlayer+Fork.swift` | Hinter dem Player (nur iPhone) ein langsam drehender Verlauf aus den Cover-Farben (`artworkGradientColors` aus `ArtworkColorCache`), gebaut auf dem vorhandenen `AnimatedGradientLayer`: Start- und Endpunkt wandern alle 10 s linear eine Ecke weiter (volle Drehung 40 s), Farbwechsel beim Songwechsel in 1,5 s. Liegt über dem statischen Verlauf und unter dem Blur des Hintergrundbilds. Bei „Bewegung reduzieren“ ausgeblendet (auch beim Umschalten zur Laufzeit), dann gilt der statische Verlauf. Der Timer läuft nur, solange der Player im Fenster ist |
| UI-14 | `MiniPlayerView.swift` | Bei minimierter Tab-Bar (`tabAccessoryEnvironment == .inline`) zeigt der Mini-Player nur Cover, Titel und Play: Künstlerzeile und Fortschrittslinie aus, Titel senkrecht mittig neben dem Cover (Kanten-Constraints des Titels werden gemerkt und gegen `centerY` getauscht). Weiter (Next) blendet schon das Original aus. Ausgeklappt wieder wie vorher. Neuer Code in der Fork-Extension am Dateiende, Hooks: 1 Zeile in `refreshForTabAccessoryTraitChange`, 1 gespeicherte Property. Mac unverändert (Guard auf das iOS-Layout) |
| UI-8 | `ListPlayHeaderView.swift` (neu), `ArtistsVC+Fork.swift` (neu), `GenresVC+Fork.swift` (neu), `SongsVC.swift`, `ArtistsVC.swift`, `GenresVC.swift` | Kopfzeile wie die Aktionszeile der Detailseiten: links die Anzahl („1234 Songs“), rechts Shuffle-Symbol und runder Play-Knopf (48 pt). Songs: dieselben Play-/Shuffle-Kontexte wie bisher, Hooks: Typ der Property (Protokoll `ListPlayHeader`) und Klasse im `createTableHeader`-Aufruf. Artists/Genres (bisher ohne Kopfzeile): ein Tap lädt erst bis zu 10 Alben per `fetch` (Spinner im Knopf), Play = Alben der ersten Einträge in Listenreihenfolge, Shuffle = je ein zufälliges Album aus zufälligen Einträgen, gemischt. Offline nur gecachte Songs. Kopfzeile versteckt bei leerer Liste. Hooks: je 1 Zeile in `viewDidLoad` und `updateContentUnavailable`. Mac behält `LibraryElementDetailTableHeaderView` (Songs) bzw. keine Kopfzeile |
| UI-9 | `DesignTokens.swift`, `TableCells+ForkStyle.swift`, `DirectoryTableCell.swift`, `QueueSectionHeaders+ForkStyle.swift` (neu), `ContextQueueNextSectionHeader.swift`, `ContextQueuePrevSectionHeader.swift`, `UserQueueSectionHeader.swift`, `EntityPreviewVC+ForkStyle.swift` (neu), `EntityPreviewVC.swift` | Restliche XIB-Schriften im Code. Neue Tokens `trackNumber` (15 medium, Ziffern gleich breit, max 18), `cellDuration` (13, Ziffern gleich breit, max 15), `queueHeaderTitle` (16 semibold, max 17), `queueHeaderSubtitle` (13, max 14), `previewTitle` (18 semibold, max 21), `previewSubtitle` (15, max 17). `PlayableTableCell`: Tracknummer und Dauer, alle Schriften auch nach Size-Class- oder Textgrößen-Wechsel neu (XIB-Variationen für `widthClass=regular`). `GenericTableCell`: Dynamic Type an (wird bei jedem `display` gesetzt). `DirectoryTableCell`: `cellTitle`. Queue-Header im Player: Titel 16 semibold, Kontextname 13 (feste Rahmenhöhen, deshalb nur +1 pt). Vorschau im Kontextmenü: Titel 18 semibold, Untertitel 15, Info 13 statt 16 (Jahr · Dauer · Bitrate passt jetzt in die Zeile), feste Label-Höhen der XIB folgen der Zeilenhöhe. Hooks: je 1 Zeile in `refresh`/`prepare`/`display`/`viewDidLoad`. Mac behält die XIB-Schriften (außer den schon vorher gesetzten Zellschriften). Die Knöpfe der XIBs zeigen nur Symbole und bleiben |
| UI-17 | `ForkEmptyState.swift` (neu), `SongsVC.swift`, `ArtistsVC.swift`, `AlbumsCommonVCInteractions.swift`, `PlaylistsVC.swift`, `DownloadsVC.swift`, `PodcastsVC.swift` | Leerzustände mit Knopf wie auf Home. Favorite Songs/Albums/Artists: „Tap ♥ on a song and it shows up here.“, Knopf „Sync Favorites“ (`syncFavoriteLibraryElements`, Spinner im Knopf). Playlists: „New Playlist“ fragt nach dem Namen, legt die Playlist an wie `NewPlaylistTableHeader`, lädt sie per `syncUpload(playlistToUpdateName:)` auf den Server und öffnet sie. Downloads (hatte keinen Leerzustand): „No Downloads“, Knopf „Download Favorite Songs“, solange noch nicht geladene Favoriten da sind (ab 200 Songs mit Rückfrage wie im Original). Podcasts und Episoden: Knopf „Refresh“ (`syncDownPodcastsWithoutEpisodes` + neueste Episoden). Knöpfe, die den Server brauchen, nur im Online-Modus. Hooks: je 1 Zeile statt `emptyContentConfig`, Downloads 2 Zeilen (`viewDidLoad`, `viewIsAppearing`), `account` in `AlbumsCommonVCInteractions` von `private` auf intern |
| UI-5 | `AddToPlaylistSheetVC.swift` (neu), `AppStoryboard.swift` | „Add to Playlist“ (Kontextmenü, Player, Mehrfachauswahl) öffnet ein Sheet in halber Höhe mit Griff, aufziehbar auf volle Höhe: oben „New Playlist“ (fragt nach dem Namen, legt die Playlist an, das Hochladen der Songs erzeugt sie auf dem Server), darunter „Recent“ (die 4 zuletzt geänderten Playlists, `changeDate`, das beim Hinzufügen neu gesetzt wird) und „All Playlists“ alphabetisch, jeweils mit Collage (`PlaylistTableCell`). Bei höchstens 6 Playlists keine Aufteilung. Suchfeld filtert nach Namen. Ein Tap fügt hinzu und schließt (Haptik), Duplikate mit derselben Rückfrage wie bisher. Smart-Playlists ausgeblendet, Playlists werden beim Öffnen wie bisher vom Server geholt. Mehrfachauswahl und Sortiermenü entfallen. Hook: 1 Zeile in `segueToPlaylistSelector`. Mac behält `PlaylistSelectorVC`. Die VCs unter `PlaylistAdd/` (Hinzufügen aus der Bibliothek beim Bearbeiten einer Playlist, `PlaylistEditVC`) bleiben im Originalstil |
| UI-7 | `OnboardingScreens+ForkStyle.swift` (neu), `DesignTokens.swift`, `LoginVC.swift`, `SyncVC.swift`, `UpdateVC.swift`, `LibrarySyncPopupVC.swift` | Login, erster Sync, Bibliotheks-Update und die Willkommens-Popups im Drift-Stil, nur das Aussehen (Server-URL, Login, API-Erkennung, Sync-Ablauf unverändert). Neue Tokens `loginBrand` (44 bold, max 50) und `onboardingTitle` (22 bold, max 26). Login: Fläche `DS.Color.background`, Wellen-Glyph (`LaunchGlyph`, 64 pt) über „Drift“ statt des großen App-Icons hinter dem Formular, Name in Label-Farbe, Felder ohne Rahmen auf `surfaceRaised` (Radius 8) in `DS.Font.cellTitle` mit Dynamic Type, Symbole und „API:“ sekundär. Glass-Formular und Login-Knopf bleiben. Sync/Update: Fläche `background`, Glyph 72 pt über dem Titel, atmet langsam (aus bei „Bewegung reduzieren“), Titel `onboardingTitle`, Fortschrittsbalken in Label-Farbe auf 15 % Label, Prozent mit gleich breiten Ziffern, „Skip“ als graue Pille statt blauem Knopf. Popups (Synchronisation, Mitteilungen): Karte auf `surfaceRaised` (Radius 20) statt Blau, Symbolkreis in der Theme-Farbe, Titel/Text aus `DS.Font`, „Close“ als Pille in Label-Farbe, optionaler Knopf grau. Hooks: je 1 Zeile in `viewDidLoad`. Mac unverändert |
| F-6 | `LibraryStorage+YouTubeMusicSwap.swift` (neu, AmperfyKit), `YouTubeMusicLibrarySync.swift` | Hat der Sync den echten Song gefunden, tauscht `replaceYouTubeMusicPlaceholder(videoId:with:account:)` den Platzhalter `ytm-…` in allen Playlist-Einträgen gegen ihn aus, an derselben Stelle: Warteschlangen (User, Kontext, gemischt, auch der laufende Song) und Playlists. Suchverlauf zeigt auf den echten Song (bei zwei Einträgen gilt das neuere Datum), `lastPlayedDate` geht mit (Recently Played). Geänderte Server-Playlists werden per `syncUpload(playlistToUpdateOrder:)` komplett neu hochgeladen, so steht der Song auf dem Server wieder an seiner Position (der Proxy hatte die Fake-ID verworfen). Der Platzhalter bleibt ohne Verwendung zurück und fällt beim nächsten `deleteUnusedYouTubeMusicSongs` weg. Gilt nur für Downloads, die die App in dieser Sitzung verfolgt hat (`onDownloadFinished`) |
| F-7 | `YouTubeMusicDownloadCoordinator.swift` (neu), `YouTubeMusicJobMonitor.swift`, `SearchVC+Fork.swift`, `AppDelegate.swift`, `AppDelegateNotificationExtensions.swift` | Downloads werden app-weit statt nur im Such-Tab behandelt: Der Koordinator setzt `onDownloadFinished` (Sync wie bisher, danach Mitteilung) und das neue `onDownloadFailed` des Monitors, und verfolgt jeden Platzhalter, der abgespielt wird (`.playerPlay`, Treffer aus dem `YouTubeMusicHitStore`), also auch aus Warteschlange, Verlauf und Radio. Mitteilung „Added to Library“ (Titel · Künstler) nach dem Sync, Tap öffnet das Album im Library-Tab. „Download Failed“ mit Titel und Fehlertext bei `fehler`. Lokale Notifications ohne neue Capability. Wurde noch nie gefragt, fragt die App beim ersten laufenden Download nach der Erlaubnis. Hooks: je 1 Zeile beim Start (`start()`) und in `didReceive`. Grenzen: Der Monitor pollt nur, solange die App läuft (im Hintergrund nur bei laufender Wiedergabe), sonst kommt die Mitteilung beim nächsten Öffnen. Keine Live Activity (bräuchte ein Widget-Target mit eigenem Provisioning) |
| F-5 | `YouTubeMusicSuggestions.swift` (neu, AmperfyKit), `AmperKit+ForkAutoplay.swift` (neu, AmperfyKit), `AmperfyKit.swift`, `SubsonicArtistInfo.swift`, `SubsonicServerApi.swift`, `YouTubeMusicShelfView.swift` (neu), `ArtistHighlightsView.swift`, `AlbumDetailVC+Fork.swift` (neu), `AlbumDetailVC.swift` | „Similar on YouTube Music“: `getArtistInfo2` mit `includeNotPresent=true` liefert die Namen ähnlicher Künstler (auch ohne Bibliotheks-ID), für die ersten 3 läuft je ein search3 parallel (der Proxy mischt die `ytm-`-Treffer ein). Nur die Platzhalter, abwechselnd aus den Suchen, ohne Songs, die mit Titel und Künstler schon in der Bibliothek stehen, max. 15. Kennt der Server keine ähnlichen Künstler, wird nach dem Künstler selbst gesucht. Künstlerseite: Shelf zwischen „Fans Also Like“ und „About“. Albumseite: Shelf als Tabellen-Footer unter den Songs (Künstler des Albums). Kacheln wie die Diskografie (140 pt, Titel, Künstler), Tap spielt den Shelf ab diesem Song, langes Drücken: Play, Play Next, Add to Queue, Add to Library. Gelöschte Platzhalter (Such-Tab räumt auf) werden übersprungen. Statt `ShelfLayout`/Collection-View Stack-Shelves wie die übrigen Abschnitte der Künstlerseite. Autoplay: liefert `getSimilarSongs2` nichts oder nur schon gespielte Songs, hängt der Player 10 YouTube-Songs ähnlicher Künstler an (ohne bereits gespielte), ein Radio auf YouTube-Songs bleibt dort (Künstlername aus dem HitStore). Hook: Rumpf von `autoplayCB` ist 1 Zeile, 1 Zeile in `viewDidLoad` des Albums. Grenzen: Jeder abgespielte YouTube-Song wird vom Proxy in die Sammlung geladen (auch im Radio), zwischen zwei YouTube-Songs ca. 9 s Stille bis zum ersten Ton. Jede Detailseite kostet online 1 bis 3 YouTube-Suchen auf dem Pi |
| F-11 | `HomeSection.swift`, `HomeSection+ForkMigration.swift`, `SubsonicAlbumList.swift` (neu, AmperfyKit), `SubsonicServerApi.swift`, `LibraryStorage+ForkAlbumLists.swift` (neu, AmperfyKit), `HomeManager+ForkShelves.swift` (neu), `HomeManager.swift`, `HomeManager+Fork.swift`, `HomeVC+Fork.swift`, `DecadeAlbumsVC.swift` (neu), `GradientArtworkView.swift`, `LargeAlbumCell.swift`, `CarPlayHomeTabExtension.swift` | Neue Home-Sektionen am Ende des Enums: „Most Played“ (`getAlbumList2 type=frequent`), „Top Rated“ (`highest`), „Decades“. `requestAlbumList2` (JSON, nur IDs), `BackendProxy.forkAlbumListIds`, Auflösung gegen die eigene Bibliothek in Server-Reihenfolge. Lokal sofort sichtbar und offline: Alben nach Summe der lokalen `playCount`s ihrer Songs bzw. nach `rating`. Online ersetzt die Server-Liste die lokale (leere Server-Liste lässt die lokale stehen), höchstens alle 5 min pro Sektion. Decades: eine Kachel pro Jahrzehnt mit Alben (Verlauf mit „90s“, Anzahl), Tap öffnet `DecadeAlbumsVC` (Raster `LargeAlbumCell`, lokal nach Jahr, online `byYear` mit bis zu 500 Alben, Tap öffnet das Album, langes Drücken Vorschau + Menü). Settings-Migration Version 2: die drei Sektionen einmal sichtbar vor den Random-Sektionen einfügen (`forkAddedSections`). Hooks: 1 Property in `HomeManager`, CarPlay-`switch`. Ampache: nur die lokalen Listen |
| F-12 | `HomeSection.swift`, `HomeSection+ForkMigration.swift`, `LibraryStorage+ForkMixes.swift` (neu, AmperfyKit), `HomeManager+ForkMixes.swift` (neu), `HomeManager.swift`, `HomeManager+ForkShelves.swift`, `HomeVC+Fork.swift`, `CarPlayHomeTabExtension.swift` | Neue Home-Sektion „Made for You“ (Fall `mixes` am Ende des Enums, Settings-Migration Version 3 setzt sie einmal sichtbar hinter „Recently Added“) mit bis zu drei großen Kacheln (Verlauf + Symbol): „Daily Mix“ (20 Favoriten in einer Tagesreihenfolge, `DailySeededGenerator`; beim Abspielen online je 15 `getSimilarSongs2`-Treffer für die ersten 3 im Wechsel Favorit, ähnlich, ähnlich, ohne YouTube-Platzhalter, max. 50; offline nur die Favoriten), „On Repeat“ (Songs mit `lastPlayedDate` in den letzten 14 Tagen, sortiert nach Anzahl der lokalen Scrobble-Einträge in dieser Zeit, dann `playCount`; mindestens 2 Plays), „Rediscover“ (Favoriten, die 60 Tage oder nie gespielt wurden, Tagesreihenfolge). Eine Kachel erscheint ab 5 Songs (Daily Mix ab 3 Favoriten). Tap spielt den Mix (offline nur geladene Songs), Neuberechnung bei jedem Erscheinen von Home. Hooks: 1 Property in `HomeManager`, CarPlay-`switch`. Grenze: Scrobble-Einträge entstehen nur für geladene Songs oder mit „Scrobble streamed items“, sonst zählt `playCount` (nur Plays in dieser App, der Server liefert keine Zahlen) |
| F-13 | `LibraryStorage+ForkStats.swift` (neu, AmperfyKit), `ListeningStatsVC.swift` (neu), `ForkLibraryVC.swift` | „Your Stats“ über das Diagramm-Symbol oben rechts in der Library. Segmente: bis zu 3 Jahre mit Plays (neuestes zuerst, Standard) und „All Time“. Oben Hörzeit (Plays × Dauer), Plays, Songs, Künstler, Alben, darunter Top 10 Künstler, Top 10 Songs, Top 5 Alben mit Anzahl Plays. Tap: Künstler- bzw. Albumseite, Song spielt die Top-Songs ab dieser Stelle (offline nur geladene). All Time zählt `playCount` (nur Plays in dieser App, Subsonic liefert keine Zahlen). Ein Jahr zählt die lokalen Scrobble-Einträge des Jahres, Songs ohne Eintrag mit `lastPlayedDate` im Jahr zählen mit ihrem `playCount` (Hinweis im Footer). `UserStatistics`: Plays aller App-Versionen und das Startdatum im Footer. YouTube-Platzhalter zählen nicht. Kein Hook in Upstream-Dateien |
| F-10 | `SubsonicPlayQueue.swift` (neu, AmperfyKit), `SubsonicServerApi.swift`, `PlayQueueSyncCoordinator.swift` (neu), `AppDelegate.swift` | Weiterhören auf einem anderen Gerät. `requestSavePlayQueue`/`requestGetPlayQueue`, `BackendProxy.forkSavePlayQueue` und `forkGetPlayQueue` (XML, die `entry`-Songs laufen durch den normalen Song-Parser, unbekannte Songs entstehen in der Bibliothek, die `<playQueue>`-Attribute liest `SsPlayQueueParserDelegate`). Gespeichert wird beim Pausieren, bei jedem neuen Song und beim Wechsel in den Hintergrund (mit Background Task, damit die Anfrage auch nach einer Pause auf dem Sperrbildschirm durchgeht): bis zu 20 vorherige Songs, der aktuelle mit Position, Warteschlange und nächste Songs, zusammen höchstens 150 (jede ID ist ein Query-Parameter einer GET-Anfrage, die URL bleibt unter 8 KB). Ohne Podcasts, Radios, YouTube-Platzhalter und Songs anderer Accounts, unveränderte Queues werden nicht erneut gespeichert. Wird die App aktiv und spielt nichts, holt sie 1,5 s später `getPlayQueue` (höchstens alle 20 s) und bietet „Continue Listening?“ an (Titel · Künstler, Position, Anzahl Songs, „Saved 5 minutes ago in Feishin“ bzw. „on another device“), wenn die Server-Queue nach der letzten eigenen Speicherung entstand (10 s Toleranz), noch nicht beantwortet wurde und nicht derselbe Song an etwa derselben Stelle (15 s) schon im Player steht. „Continue“ spielt die Queue ab dem gespeicherten Song und springt an die Position, „Not Now“ merkt sich die Queue. Merker in `UserDefaults` pro Account. Nur Subsonic, nur online. Hook: 1 Zeile beim Start. Grenze: Alle Drift-Geräte melden sich als Client „Amperfy“, deshalb entscheidet der Zeitpunkt, nicht `changedBy` |
| F-15 | `LibraryStorage+ForkSpotlight.swift` (neu, AmperfyKit), `SpotlightIndexer.swift` (neu), `AppDelegate.swift`, `SceneDelegate.swift` | Alben, Künstler und Playlists des aktiven Accounts als `CSSearchableItem` (CoreSpotlight, keine Capability). `getForkSpotlightEntries(for:)` liest sie im Hintergrund-Kontext (ohne server-seitig gelöschte Einträge, YouTube-Platzhalter und System-Playlists). Titel, Beschreibung „Künstler · Album · 2019 · 12 Songs“ bzw. „Artist · 4 Albums“, „Playlist · 31 Songs“, Vorschaubild aus dem gecachten Cover (Playlists ohne). Der Index wird neu gebaut (alle Einträge der App löschen, in Blöcken von 1000 eintragen), wenn die App aktiv wird und der letzte Aufbau älter als 6 h ist, zu einem anderen Account gehört oder eine ältere Index-Version hat, 5 s nach dem Aktivwerden. Kennung `album/<Account-Ident>/<ID>`. Tap auf einen Treffer schließt den Player und öffnet die Album-, Künstler- bzw. Playlist-Seite im Library-Tab, beim Kaltstart aus Spotlight erst, wenn das Hauptfenster steht. Treffer anderer Accounts werden ignoriert. Hooks: 1 Zeile beim Start, je 1 Zeile in `willConnectTo` und `continue userActivity`. Grenze: Neue Alben erscheinen erst mit dem nächsten Aufbau (höchstens 6 h später) |
| F-9 | `DriftShare/ShareViewController.swift` (neu, Target `DriftShare`), `Shared/DriftShareConfig.swift` (neu, App + Extension), `ShareExtensionBridge.swift` (neu), `BackendProxy+ForkShare.swift` (neu, AmperfyKit), `AppDelegate.swift`, `Amperfy.entitlements` | „Teilen → Drift“ für Links aus YouTube Music, YouTube und Safari (URL oder Text mit Link): `watch?v=`, `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`, Video-ID mit 11 Zeichen. Der Download läuft wie in der App über Subsonic am Login-Host: `stream.view?id=ytm-<videoId>&format=mp3`, gelesen bis zum ersten Audio-Byte (~9 s), danach lädt der Proxy allein weiter. Keine Songpicker-API. Die Extension kennt keine Zugangsdaten: Die App legt bei jedem Aktivwerden die Stream-URL des aktiven Accounts mit Platzhalter-ID (`forkYouTubeStreamTemplate`, mit Token und Salt bzw. bei Legacy-Auth dem Passwort, plus HTTP-Header) in die geteilte Keychain-Gruppe, ohne Subsonic-Account wird sie gelöscht, offline bleibt die alte. Oberfläche: dunkle Karte mit Spinner „Adding to Drift…“ (Server, mitgeteilter Text), danach Haken „Added to Drift“ und Schließen nach 1,5 s, Fehler mit Grund („No YouTube or YouTube Music link found“, „Open Drift once…“, HTTP-Status). Hook: 1 Zeile beim Start. Grenzen: Die Karte muss bis zum ersten Byte offen bleiben („Cancel“ vorher bricht ab). Erst nach einem Start der App mit diesem Build eingerichtet. Playlists und Alben (`list=`) gehen nicht (F-8). Die App erfährt vom Download über `getYtJobs` (Downloads-Liste), eine Mitteilung wie bei F-7 gibt es dafür nicht |
| UI-10 | `MiniPlayerAccessibilityElement.swift` (neu), `MiniPlayerView.swift`, `PopupPlayer+Fork.swift`, `PlayableTableCell+NowPlaying.swift`, `DownloadJobCell.swift`, `SearchStatusCell.swift`, `SkeletonView.swift`, `LargeAlbumCell.swift`, `TileCollectionCell.swift`, `ArtistCircleCell.swift` | VoiceOver in den Fork-Views. Mini-Player (iOS): Cover und Texte sind ein Element „Now Playing, Titel, Künstler“ (Doppeltipp öffnet den Player), Aktionen „Skip Forward“, „Skip Back“, „Open Player“ wie die Wischgesten, danach Play und „Next“. Player: Escape-Geste (Zwei-Finger-Z) schließt ihn. Bei „Bewegung reduzieren“ blendet der Player über (`crossDissolve`) statt aus dem Cover zu zoomen, Schließen dann über den Griff oder Escape (kein Herunterwischen). Song-Zeilen melden den laufenden Song als Wert „Now Playing“/„Paused“ (der Equalizer bleibt stumm). Download-Zeilen: Titel, Künstler, Zustand als Wert, „Retry“ als Aktion. Status-Zeile der Suche als ein Text. Skeletons (Home-Shelves, Kacheln) sind für VoiceOver unsichtbar statt „Loading“. Hooks: 1 Zeile in `configureForkStyleForiOS` (Fork-Bereich von `MiniPlayerView`), sonst nur Fork-Dateien. Die übrigen Fork-Kacheln, Kopfzeilen und Chips hatten schon Labels |
| UI-15 | `Amperfy/Fork.xcstrings` (neu, App), `DriftShare/Fork.xcstrings` (neu, Teilen-Erweiterung), `project.pbxproj`, alle Fork-Dateien mit sichtbaren Texten, Fork-Zeilen in `HomeSection.swift`, `SearchVC.swift`, `MiniPlayerView.swift` | Deutsche Texte für den Fork. Basis bleibt Englisch, Deutsch kommt dazu (`knownRegions` + `de`, Katalog mit `en` und `de`). Alle Fork-Texte laufen über `String(localized: "…", table: "Fork")`, also eine eigene Tabelle: Upstream-Texte (UIKit-Literale, SwiftUI-`Text`, App Intents in der Standardtabelle `Localizable`) finden dort nichts und bleiben unverändert englisch. AmperfyKit-Texte (`ForkMenuText`, Home-Sektionen „Most Played“, „Top Rated“, „Decades“, „Made for You“, Jahrzehnte „90er“, Spotlight-Beschreibungen, Proxy-Fehler) lesen aus dem Katalog der App (`Bundle.main`). Die Teilen-Erweiterung hat einen eigenen Katalog. Zahlen: eigene Schlüssel für 1 und mehrere („1 Album“/„%lld Alben“), Umstellungen mit `%1$@`/`%2$@`. Ansprache „du“. Die Sprache folgt dem iPhone bzw. Einstellungen › Drift › Sprache. Neue Fork-Texte gehören in die Tabelle `Fork` und von Hand in `Amperfy/Fork.xcstrings` (das App-Target extrahiert keine Schlüssel, `SWIFT_EMIT_LOC_STRINGS` ist dort aus). Nebenwirkung: Systemtexte (Abbrechen, Bearbeiten, Datumsangaben) erscheinen auf einem deutschen iPhone jetzt deutsch, auch in Upstream-Ansichten. Offen (TASKS UI-15b): Upstream-Texte, vom Fork nur umbenannte Upstream-Texte, `EventLogger`-Themen |
| UI-16 | – | Entscheidung: Das Fork-Design gilt nur auf dem iPhone. iPad und Mac bleiben im Upstream-Stil (Home, Suche, Detailseiten werden dort nicht nachgezogen). |
| F-14 | `DriftWidgets/` (neu, Target `DriftWidgets`: `DriftWidgetsBundle.swift`, `RecentWidget.swift`, `ShuffleFavoritesWidget.swift`, `DriftControls.swift`, `Fork.xcstrings`), `Shared/DriftAppGroup.swift` (neu, App + Widgets), `Shared/DriftWidgetIntents.swift` (neu, App + Widgets), `DriftWidgetBridge.swift` (neu), `AppDelegate.swift`, `Amperfy.entitlements` | Widgets und Kontrollzentrum. Die App schreibt einen kleinen Snapshot (`widget-snapshot.json` in der App Group: Recently Played wie auf Home, max. 8 Alben/Künstler/Playlists, Anzahl Lieblingssongs, aktueller Song, spielt/pausiert, Theme-Farbe) und Cover als JPEG (240 px, Dateiname nach dem Cover, ungenutzte werden gelöscht). Kein Core Data und kein AmperfyKit in der Extension. Neu geschrieben 1 s nach Songwechsel, Play, Pause und Aktivwerden, sofort beim Wechsel in den Hintergrund. Timelines bzw. Controls werden nur neu geladen, wenn sich ihr Inhalt ändert. Widgets: „Zuletzt gehört“ (klein: 1 Cover, mittel: 4, groß: 6 mit Untertitel), „Favoriten mischen“ (klein mit Verlauf in der Theme-Farbe und Anzahl, rund für den Sperrbildschirm). Kontrollzentrum: Taste „Favoriten mischen“ und Schalter „Drift abspielen/pausieren“ mit dem aktuellen Titel. Alle Tasten sind `AudioPlaybackIntent`s in App und Extension, das System führt sie in der App aus (startet sie bei Bedarf im Hintergrund), die App öffnet sich nicht. Tap auf ein Cover: online erst `fetch`, dann abspielen, offline nur geladene Songs. Mischen: bis zu `maxSongsToAddOnce` zufällige Lieblingssongs (offline nur geladene). Hook: 1 Zeile beim Start. Texte in `DriftWidgets/Fork.xcstrings` (en, de), die Intent-Titel bleiben englisch wie die übrigen App Intents. Grenzen: Ohne Start der App mit diesem Build zeigen die Widgets nichts. Nach einem Account-Wechsel oder neuen Favoriten erst beim nächsten Schreiben aktuell |
| UI-18 | `DesignTokens.swift`, `UserSettings+Appearance.swift` (AmperfyKit), `SettingEnumerations.swift`, `AppDelegate.swift`, `NeutralAccentSettingsSection.swift`, `AccountSettingsView.swift`, `ForkChrome.swift` (neu), `ListRows+ForkStyle.swift` (neu), `TableCells+ForkStyle.swift`, `PlayableTableCell.swift`, `GenericTableCell.swift`, `PlaylistTableCell.swift`, `PlayableTableCell+NowPlaying.swift`, `ForkSurface.swift`, `SearchVC.swift`, `ListPlayHeaderView.swift`, `ImmersiveDetailHeaderView.swift`, `PlaylistBarButtons+Fork.swift` (neu), `PlaylistsVC.swift`, `PlaylistDetailVC.swift`, `MiniPlayerView.swift` | Identität + Listen, nur iPhone (`DS.isPhone`). Palette und Schriften siehe Abschnitt 2 „Design-Tokens“. Feste Akzentfarbe Mint: `ForkAccent.isFixed` (beim Start = iPhone) wirkt über den vorhandenen Hook in `ThemePreference.asColor`/`contrastColor`, also auf Tint, Laufend-Titel, Platzhalter und Widgets; Neutral Accent hat Vorrang. Die Theme-Farbe bleibt gespeichert, die Auswahl in Settings › Account ist auf dem iPhone ausgeblendet. Dunkel zuerst ohne Zwang: alle Farben dynamisch mit Hell-Variante (Hell bleibt wählbar, Migration aus Phase 6 setzt „System“ schon auf Dunkel), kein `overrideUserInterfaceStyle`-Eingriff nötig. Nav-Bar transparent ohne Linie (iOS 26 blendet Inhalte darunter weich aus), große Titel Rounded 34 Heavy, kleine Rounded 17 Bold, gilt global per `UINavigationBar.appearance()` (auch Settings). Tab-Bar: Auswahl Mint, sonst Text 3; das Liquid Glass bleibt. Listen: keine Trennlinien (alle `BasicTableViewController`-Listen und Suche), Songzeile 60 pt mit 48-pt-Cover, Album-, Künstler- und Playlistzeile 72 pt mit 56-pt-Cover (Künstler rund), Radius 8; `rowHeight` der drei Zellen ist auf dem iPhone ein berechneter Wert (je 1 Zeile). „…“-Knopf (44 pt, Text 2, VoiceOver „Mehr“) rechts: Songzeilen nutzen den vorhandenen Optionsknopf (verbreitert), Alben/Künstler/Genres/Podcasts und Playlists bekommen ihn als `accessoryView` mit dem Menü von `EntityPreviewActionBuilder` (nicht in den Hinzufügen-Screens). Swipes bleiben. Laufender Song: Titel Mint, Zeile auf `surface` mit Radius 12, Balken im Cover; Albumseite: Tracknummer Mint statt Balken, keine Künstlerzeile, Dauer (feste Ziffern) als Unterzeile, Gastkünstler davor. Kopfzeile Songs/Künstler/Genres: „Abspielen“ als Mint-Pille, „Zufall“ als erhöhte Pille, Anzahl rechts. Play-Knopf der Detailseiten Mint. Playlists und Playlistseite: „Bearbeiten“ im „…“-Menü statt eigenem Knopf (Liste: danach „Fertig“ in der Leiste). Mini-Player: Fortschritt 2 pt Mint. Hooks: je 1 Zeile. Abweichungen: Tab-Bar ohne eigenen Grund (würde das Glas ersetzen), Mini-Player ohne schwebende Karte (TASKS UI-19), Queue im Player hat jetzt ebenfalls 60-pt-Zeilen |
| F-8 | `BackendProxy+ForkYouTubeAlbum.swift` (neu, AmperfyKit), `YouTubeAlbumActions.swift` (neu), `YouTubeAlbumViews.swift` (neu), `YouTubeAlbumVC.swift` (neu), `YouTubeArtistVC.swift` (neu), `SearchVC+Fork.swift`, `YouTubeMusicShelfView.swift` | Ganzes Album / Künstler von YouTube Music. Am YouTube-Treffer (Suche, Top-Treffer, F-5-Shelf, Kontext- und „…“-Menü, nur online) „Album ansehen“, „Künstler ansehen“, „Ganzes Album laden“ (Hinweis mit „6 werden geladen, 9 schon da“ und Weg zum Album). Album-Screen: Cover 220 pt, „YouTube Music“, Titel Rounded, Künstler in Mint (öffnet den YouTube-Künstler, von dort kommend zurück), Typ · Jahr · Songs, Pille „Album laden“ (danach Zusammenfassung auf erhöhter Fläche, sonst „Lädt…“ bzw. „In der Bibliothek“), Trackliste 60 pt mit Tracknummer, Gastkünstler · Dauer und Zustand (`SourceBadgeView`: ✓, Ring für wartet/lädt/speichert, !, Wolke). Tap spielt das Album ab dem Song: echte Navidrome-Songs (`navidromeId`, fehlende per `getSong` geholt), sonst `ytm-`-Platzhalter, die durch den normalen Song-Parser entstehen. Gestartete Jobs verfolgt `YouTubeMusicJobMonitor` (F-6-Abgleich, F-7-Mitteilung), Zustände kommen per Notification, `getYtAlbum` neu alle 10 s nur bei sichtbarem Screen und solange Songs laden oder noch keine `navidromeId` haben. Künstler-Screen: rundes Bild (Cover über `getCoverArt`, sonst `artistImageUrl`), Abschnitte „Alben“ und „Singles & EPs“ (EPs zu den Singles), 72-pt-Zeilen, Skeleton beim Laden, Tap öffnet das Album. Fehler und offline mit „Erneut versuchen“. Hooks nur in Fork-Dateien |
| UI-20 | `TabBarVC.swift`, `SearchVC.swift`, `Fork.xcstrings` | iPhone: drei gleiche Tabs Home / Suche / Bibliothek wie im Mockup. Suche ist ein normaler `UITab` statt `UISearchTab` (der wäre der getrennte Glas-Knopf rechts), Reihenfolge Home, Suche, Bibliothek, Titel aus der Tabelle `Fork`. Das Suchfeld bleibt unter dem Titel sichtbar (`hidesSearchBarWhenScrolling = false`). Ausgewählter Tab Mint, `tintColor` direkt an der Tab-Bar, weil der Appearance-Proxy die iOS-26-Leiste nicht erreicht. Identifier (`Tabs.Search` …) unverändert. iPad und Mac behalten `UISearchTab` |
| UI-20 | `PlayerPageScrollView.swift` (umbenannt aus `PlayerCoverScrollView.swift`), `LyricsCardView.swift`, `PopupPlayer+Fork.swift`, `PopupPlayer+Animations.swift`, `SleepTimerChipView.swift`, `DesignTokens.swift` | Player wie bei Streaming-Apps (nur iPhone): Die ganze Seite scrollt. Die beiden Platzhalter der XIB (Cover und Steuerung) wandern in eine Scroll-View, die erste Seite ist genau bildschirmhoch (Abstände wie in der XIB aus Safe Area und Margins des Root-Views), darunter folgt die Songtext-Karte. Karte neu: Titel „Songtext“ + Vollbild-Symbol, 7 Zeilen um die aktuelle (aktuelle weiß, übrige 45 %), unten ausgeblendet, feste Höhe 380 pt (mit Dynamic Type skaliert), Fläche in der Cover-Farbe, Tap öffnet die volle Lyrics-Ansicht. Kein Wischen nach oben und kein Überziehen mehr zur Queue, die Queue öffnet nur ihr Knopf. In der Queue, in den vollen Lyrics und ohne Lyrics scrollt die Seite nicht (Hook: 1 Zeile am Anfang von `changeDisplayStyleVisually`). Sleep-Timer-Chip liegt in der Seite und scrollt mit. Schließen per Herunterwischen nur ganz oben |
| UI-20 | `PopupPlayer+ForkStreaming.swift` (neu), `PlayerPageScrollView.swift`, `PopupPlayer+Fork.swift`, `LargeCurrentlyPlayingPlayerView.swift`, `PlayerControlView.swift`, `PlayerControlView+ForkStyle.swift`, `Fork.xcstrings` | Erste Player-Seite wie bei Streaming-Apps (nur iPhone): Kopfzeile statt Grabber (Pfeil nach unten schließt, „Wird gespielt von“ + Album bzw. Kontext, Tap öffnet das Album). Albumzeile unter dem Titel ausgeblendet, Herz und „…“ ohne graue Kreise. Steuerreihe: Zufall, Zurück, Play als weißer Kreis (64 pt, Symbol in Hintergrundfarbe), Weiter, Wiederholen (aktiv in Mint, Wiederholen zeigt `repeat.1` bei einem Song, nur im Musikmodus). Hooks: 1 Zeile am Ende von `LargeCurrentlyPlayingPlayerView.refresh` (`rootView` dafür `private(set)`), je 1 Zeile in `refreshPlayer`, `didShuffleChange`, `didRepeatChange` und `applyForkStyle` |
| UI-20 | `InfoPlist.xcstrings` (neu) | `CFBundleDisplayName`/`CFBundleName` = „Drift“ für de und en. Das Bundle hieß schon „Drift“, Mitteilungen und Kontrollzentrum zeigten aber noch „Amperfy“ (Cache von iOS). Mit lokalisiertem Namen liest iOS ihn beim Update neu. Hilft das nicht: iPhone neu starten || F-18 | `PlayerDurationResolver.swift` (neu, AmperfyKit), `PlayerFacade.swift`, `NowPlayingInfoCenterHandler.swift`, `BackendAudioPlayer.swift`, `AmperfyKit.swift`, `PlayerUIHandler.swift` | Songdauer immer bekannt. Ursache: Player, Mini-Player und Sperrbildschirm nahmen die Dauer nur von AudioStreaming, das sie aus der Content-Length rechnet. Der YouTube-Proxy streamt chunked ohne Länge, also 0:00 / --:-- und kein Fortschritt im Kontrollzentrum. Die Core-Data-Dauer wurde nie benutzt. Jetzt: Dauer des Streams, wenn bekannt (gewinnt immer, `savePlayInformation` speichert sie wie bisher als `playDuration`), sonst die gespeicherte, bei `ytm-`-Platzhaltern die des YouTube-Treffers (`YouTubeMusicHitStore`). Fehlt beides, holt `getSong` (über den Proxy, nur das `duration`-Attribut, kein voller Parser) sie beim Start des Songs, auch ohne offenen Player, einmal pro Song und Sitzung, und speichert sie als `remoteDuration`; danach Now-Playing und UI neu. Spulen nur mit bekannter Stream-Länge (`forkCanSeek`): AudioStreaming schließt sonst die Quelle. Der Zeitregler ist dann gesperrt, der Sperrbildschirm-Regler springt zurück. Gapless-Vorladen, Fortsetzen und Speichern nutzen weiter nur die Stream-Dauer. Hooks: je 1 Zeile in `PlayerFacade` (Protokoll + `duration` + `forkCanSeek`), `NowPlayingInfoCenterHandler`, `BackendAudioPlayer.seek`, `AmperKit` (Installation), `PlayerUIHandler.refreshTimeInfo` |
| F-18 | `PlayerDurationResolver.swift` (neu, AmperfyKit), `PlayerFacade.swift`, `NowPlayingInfoCenterHandler.swift`, `BackendAudioPlayer.swift`, `AmperfyKit.swift`, `PlayerUIHandler.swift` | Songdauer immer bekannt. Ursache: Player, Mini-Player und Sperrbildschirm nahmen die Dauer nur von AudioStreaming, das sie aus der Content-Length rechnet. Der YouTube-Proxy streamt chunked ohne Länge, also 0:00 / --:-- und kein Fortschritt im Kontrollzentrum. Die Core-Data-Dauer wurde nie benutzt. Jetzt: Dauer des Streams, wenn bekannt (gewinnt immer, `savePlayInformation` speichert sie wie bisher als `playDuration`), sonst die gespeicherte, bei `ytm-`-Platzhaltern die des YouTube-Treffers (`YouTubeMusicHitStore`). Fehlt beides, holt `getSong` (über den Proxy, nur das `duration`-Attribut, kein voller Parser) sie beim Start des Songs, auch ohne offenen Player, einmal pro Song und Sitzung, und speichert sie als `remoteDuration`; danach Now-Playing und UI neu. Spulen nur mit bekannter Stream-Länge (`forkCanSeek`): AudioStreaming schließt sonst die Quelle. Der Zeitregler ist dann gesperrt, der Sperrbildschirm-Regler springt zurück. Gapless-Vorladen, Fortsetzen und Speichern nutzen weiter nur die Stream-Dauer. Hooks: je 1 Zeile in `PlayerFacade` (Protokoll, `duration`, `forkCanSeek`), `NowPlayingInfoCenterHandler`, `BackendAudioPlayer.seek`, `AmperKit` (Installation), `PlayerUIHandler.refreshTimeInfo` |

### Hilfsskript

`Helper/add-swift-file.py <Neu.swift> <Nachbar.swift>` trägt eine neue Datei ins Projekt ein, in dieselbe Gruppe und
dieselben Targets wie die Nachbardatei. Nötig, weil das Projekt keine synchronisierten Ordner nutzt, sondern jede
Datei einzeln in `project.pbxproj` führt.

`Helper/add-extension-target.py <spec.json>` legt ein Extension-Target an (Gruppe, Build-Phasen, Build-Einstellungen wie die App:
Team, iOS 26, Version, automatisches Signing) und bettet es in die App ein (nur iOS). Dateien in `Shared/` landen in App und Extension.
Beispiel-Spec im Kopf des Skripts.

---

## Roadmap

1. ~~Suche reparieren~~ ✅
2. ~~**YouTube-Music-Bereich in der Suche**~~ ✅ (Design Phase 4): eigene Sektion mit den Songpicker-Treffern, die `library == false` haben.
   - Antippen spielt sofort über den Proxy (`ytm-<id>`) ab, über die normale Warteschlange.
   - Kontextmenü mit den Einträgen „In Sammlung laden“, „Als Nächstes spielen“, „Zur Warteschlange“.
   - Status-Badge pro Treffer (Wolke, Spinner, Haken), aktualisiert per Polling von `/api/jobs`.
   - Ist ein Job `fertig`, wird der Song über Navidrome synchronisiert: per `search3` nach dem Titel suchen und über
     das Ende von `path` abgleichen.
3. ~~**Einstellungen:** Songpicker-URL (Default `http://10.66.66.6:8781`), YouTube-Bereich an/aus.~~ ✅ (Design Phase 5, plus eigene Proxy-URL)
4. ~~Download-Übersicht~~ ✅ (Design Phase 5, Library-Chip „Downloads“). Später: „Ähnliche Songs von YouTube“.
   - **Personalisierte Treffer:** Der Songpicker sortiert die YouTube-Ergebnisse nach den Hörgewohnheiten
     (Wiedergabezahlen, Favoriten, oft gehörte Künstler über die Subsonic-API von Navidrome), Karaoke- und Cover-Versionen
     nach unten. In der App nur ein kleiner Bonus im Top-Treffer-Ranking (`forkScore` in `SearchVC+Fork.swift`) aus
     `playCount`, `isFavorite` und `lastPlayedDate`, die schon lokal vorliegen.
5. Design-Überarbeitung Richtung moderner Streaming-Client, in 5 Phasen laut `DESIGN-AUDIT.md`. Phase 1 ✅, Phase 2 ✅, Phase 3 ✅, Phase 4 ✅, Phase 5 ✅, Phase 6 ✅ (Maßnahmen 10 und 14 abgeschlossen)

### Crossfade (TASKS F-17): Umsetzungsplan

Stand 2026-10-29: nicht eingebaut. Mit einzeiligen Hooks geht es nicht sauber, deshalb erst dieser Plan.

**Wie die Wiedergabe heute läuft**

- `BackendAudioPlayer` (AmperfyKit) hält genau einen `AudioStreamingPlayer` (Unterklasse von `AudioStreaming.AudioPlayer`,
  eigene `AVAudioEngine`) in der privaten Variable `player`, dazu EQ (`AVAudioUnitEQ`), ReplayGain-Mixer und den
  `AudioAnalyzer` (Visualizer, am EQ installiert).
- Gapless: `checkForPreloadNextPlayerItem()` holt 10 s vor Ende über `nextPlayablePreloadCB` den nächsten Song und hängt ihn
  mit `player.queue(url:)` an **dieselbe** Engine. Das Ende meldet `audioPlayerDidFinishPlaying` (nur wenn
  `currentPlayUrl` passt) → `itemFinishedPlaying()` → `AudioPlayer.didItemFinishedPlaying()` → `playNext()` →
  `requestToPlay` erkennt den vorgeladenen Song in `handleRequest` und übernimmt nur noch Zustand
  (`currentPlayUrl`, `playType`, Bitrate, ReplayGain).
- An diesem Ablauf hängen Warteschlange, `countPlayed`/Statistik, Scrobbling (`ScrobbleSyncer`), Now-Playing-Info,
  CarPlay, Lyrics-Zeit, Play-Queue-Sync (F-10) und der Sleep Timer „nach diesem Song“.
- Lautstärke: `AudioPlayer.volume` ist `mainMixerNode.outputVolume` der Engine. Pro Player einzeln regelbar.

**Warum nicht mit Hooks**

Crossfade braucht zwei gleichzeitig hörbare Songs, also zwei Engines. `player`, die Preload-Variablen,
`handleRequest`, die Delegate-Methoden und das Node-Setup sind `private` in `BackendAudioPlayer`. Eine Fork-Extension in
einer eigenen Datei kommt an nichts davon heran. Der Wechsel des aktiven Players müsste in `handleRequest`,
`audioPlayerDidFinishPlaying`, `didStartPlaying`, `clearPlayer`, `pause`/`continuePlay`/`seek`, `elapsedTime`/`duration`
und `initAudioStreamingPlayerAndNodes` eingreifen, also Funktionsrümpfe in Upstream ersetzen. Ein reines
Aus- und Einblenden in einem Player wäre kein Crossfade (Lücke in der Mitte) und bricht Gapless für Alben.

**Ansatz**

1. Neue Datei `AmperfyKit/Player/CrossfadeCoordinator.swift`: besitzt einen zweiten `AudioStreamingPlayer` mit eigenem
   EQ- und ReplayGain-Node (Setup aus `initAudioStreamingPlayerAndNodes` als gemeinsame Funktion herausziehen) und fährt
   die Rampe: alle 50 ms `outgoing.volume = v·(1−t)`, `incoming.volume = v·t` (gleichmäßige Leistung:
   `cos`/`sin` statt linear), `v` = Nutzerlautstärke. Muster wie `SleepTimerFader` (UI-12).
2. `BackendAudioPlayer` umbauen (größter Teil, Upstream-Datei):
   - `player` wird „aktiver Kanal“ von zwei Kanälen (`channels[2]`, `activeIndex`), alle Zugriffe laufen über ihn.
   - In `checkForPreloadNextPlayerItem()`: bei Crossfade an und `remaining <= fadeDauer` den nächsten Song nicht in die
     Queue hängen, sondern auf dem freien Kanal mit Lautstärke 0 starten (`play(url:)`, Stream-URL über
     `insertStreamPlayable`-Logik, gecachte Datei direkt).
   - Sobald der neue Kanal `didStartPlaying` meldet: Rampe starten, Kanäle tauschen, `responder.didItemFinishedPlaying()`
     **sofort** auslösen, damit Warteschlange, Now-Playing, Scrobbling und `countPlayed` auf den neuen Song wechseln.
     `handleRequest` muss diesen Fall als „schon vorbereitet“ erkennen (wie heute den vorgeladenen Song).
   - Delegate-Aufrufe des auslaufenden Kanals ignorieren (`player === activePlayer` prüfen), nach der Rampe `stop()`.
   - `pause`/`continuePlay`/`stop`/`seek`/Rate/EQ/ReplayGain während der Rampe: auf beide Kanäle wirken bzw. Rampe
     abbrechen und den alten Kanal sofort stoppen (Seek, Skip, Stop).
   - `audioAnalyzer` folgt dem aktiven Kanal (am neuen EQ installieren).
3. Kein Crossfade (normales Gapless bleibt) bei: Radios, Podcasts, YouTube-Platzhaltern, Repeat One,
   „Pause after this Song“, wenn beide Songs aus demselben Album aufeinander folgen (Album-Gapless,
   wie Apple Music), Songs kürzer als 2× Fadedauer, unbekannter Dauer (Streams ohne `duration`).
4. Einstellung in einer neuen Fork-Datei: `UserDefaults`-Schlüssel `forkCrossfadeSeconds` (0 = aus, Standard aus,
   Slider 1–12 s) in Einstellungen › Player, SwiftUI-Zeile „Crossfade“ / „Überblenden“ in `Amperfy/Fork.xcstrings`.
   Kein Core-Data-Feld.
5. Audio-Session: zwei Engines auf derselben `AVAudioSession` gehen, `AudioSessionHandler` braucht keine Änderung.
   Interruption (Anruf) muss beide Engines pausieren.

**Betroffene Dateien**: `BackendAudioPlayer.swift` (Kanalverwaltung, ca. 10 Methoden), `AudioPlayer.swift`
(Prüfung „darf überblenden“: Repeat, Pause-nach-Song), `CrossfadeCoordinator.swift` (neu), Einstellungsseite (neu),
`Fork.xcstrings`. Optional `NowPlayingInfoCenterHandler` nicht nötig, wenn der Songwechsel über
`didItemFinishedPlaying` läuft.

**Risiken**: Doppelte bzw. fehlende Song-Ende-Meldung (Scrobbling doppelt oder nie, Queue springt zwei Songs),
Streams, die beim Start buffern (Rampe muss bis `didStartPlaying` warten, sonst Lücke), doppelter Netz- und
Speicherbedarf während der Überblendung, Visualizer zeigt nur einen Kanal, Konflikte bei jedem Upstream-Merge in
`BackendAudioPlayer.swift` (Upstream ändert die Datei regelmäßig), Mac Catalyst und CarPlay mittesten.

**Aufwand**: etwa 2–3 Tage inklusive Tests auf dem iPhone (Album gapless, Playlist mit Crossfade, Skip während
der Rampe, Pause/Seek während der Rampe, Sperrbildschirm, CarPlay, Scrobbles in Navidrome prüfen).
Alternative mit weniger Eingriff: Upstream-PR, der `BackendAudioPlayer` für zwei Kanäle öffnet, dann bleibt der Fork-Teil
eine neue Datei.

## Arbeitsweise

- Kleine Commits auf `youtube`, jeweils nach GitHub pushen.
- Neue Dateien sind besser als Umbauten großer bestehender Dateien. Den Stil von AmperfyKit beibehalten
  (async/await, CoreData-Wrapper, `storage.async.performAndGet`).
- Vor „fertig“: einmal auf dem iPhone bauen (siehe oben).
- Fork-Design nur auf dem iPhone. iPad und Mac bleiben im Upstream-Stil (TASKS UI-16).
- Upstream holen: `git fetch upstream && git merge upstream/master`. Konfliktgefahr besteht vor allem in `SearchVC.swift`
  und `project.pbxproj`.
