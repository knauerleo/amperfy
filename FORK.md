# Amperfy-Fork mit YouTube-Music-Integration

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

- **Developer-Portal:** Von Hand ist nichts anzulegen. Xcode registriert App-ID und Profil automatisch (`-allowProvisioningUpdates`).
  Siri ist als Capability aktiv. Eine App Group oder Extensions gibt es in Amperfy nicht.
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

- Die Karte nimmt dem Cover Höhe weg (Stack-View aus der XIB). Auf kleinen iPhones wird das Cover dadurch kleiner.
- Das Feld `started` von `/api/jobs` ist nur geraten (Unix-Zeit oder ISO 8601). Fehlt es, sortiert die Liste
  fertige Jobs ohne Zeitangabe ans Ende.
- Die Zwischen-Commits `d3c1ec2b` bis `be5d7705` haben die neuen Dateien unvollständig im Projekt eingetragen,
  erst `9165849a` baut. Der Stand `9165849a` baut und startet auf dem iPhone.

### Hilfsskript

`Helper/add-swift-file.py <Neu.swift> <Nachbar.swift>` trägt eine neue Datei ins Projekt ein, in dieselbe Gruppe und
dieselben Targets wie die Nachbardatei. Nötig, weil das Projekt keine synchronisierten Ordner nutzt, sondern jede
Datei einzeln in `project.pbxproj` führt.

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
5. Design-Überarbeitung Richtung moderner Streaming-Client, in 5 Phasen laut `DESIGN-AUDIT.md`. Phase 1 ✅, Phase 2 ✅, Phase 3 ✅, Phase 4 ✅, Phase 5 ✅

## Arbeitsweise

- Kleine Commits auf `youtube`, jeweils nach GitHub pushen.
- Neue Dateien sind besser als Umbauten großer bestehender Dateien. Den Stil von AmperfyKit beibehalten
  (async/await, CoreData-Wrapper, `storage.async.performAndGet`).
- Vor „fertig“: einmal auf dem iPhone bauen (siehe oben).
- Upstream holen: `git fetch upstream && git merge upstream/master`. Konfliktgefahr besteht vor allem in `SearchVC.swift`
  und `project.pbxproj`.
