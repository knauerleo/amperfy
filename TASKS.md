# Tasks

Aus der Durchsicht vom 2026-10-29. `UI-…` = Modernisierung der Oberfläche, `F-…` = neue Features.
Regeln aus `DESIGN-AUDIT.md` §7 gelten weiter: neue Dateien statt Umbauten, XIBs nicht anfassen, Hooks mit einer Zeile.

## Active

- [ ] **F-2 Server-URL automatisch umschalten** - mit F-1 meist überflüssig (nur noch die Domain), nur falls LAN-Adresse weiter genutzt wird
  - Bei Netzwechsel (`NetworkMonitor`) die erste erreichbare URL aus `activeBackendServerUrl` + `alternativeServerURLs` per `ping` wählen
- [ ] **UI-2 „All Albums“-Raster mit `LargeAlbumCell`**
  - `AlbumsCollectionVC.swift` nutzt noch `AlbumCollectionCell` (XIB). Hook auf die neue Zelle und `ShelfLayout`
  - Fertig, wenn: Albenraster aus Library › Albums › All Albums zeigt dieselben Zellen wie das Filter-Raster
- [ ] **UI-3 Playlists-Liste modernisieren**
  - `PlaylistTableCell` per `+ForkStyle`-Extension: Collage-Cover 56 pt, Radius 4, `DS.Font.songTitle`/`cellSubtitle`, kein Chevron
- [ ] **UI-4 Player-Schriften auf `DS.Font`**
  - 16 feste `pointSize` in `PlayerControlView.xib`, 5 in `LargeCurrentlyPlayingPlayerView.xib`. Im Code überschreiben (`PlayerControlView+ForkStyle.swift`), Dynamic Type mit Obergrenze
  - Fertig, wenn: größere Systemschrift vergrößert Titel/Zeiten im Player, ohne dass das Layout bricht
- [ ] **F-3 Künstlerseite mit `getArtistInfo2`**
  - Neue Extension am Subsonic-Syncer: Künstlerbild, Bio, ähnliche Künstler. Bild in den Header, Bio aufklappbar, ähnliche Künstler als `ShelfLayout.circle`
- [ ] **F-4 „Popular“ mit `getTopSongs`** - auffüllen, solange eigene `playCount`s zu wenige Treffer liefern
  - `ArtistHighlightsView.swift`, neue Extension am Subsonic-Syncer

## Waiting On

- [ ] **F-16 CarPlay wieder einschalten** - Antrag bei Apple (developer.apple.com/contact/carplay, „CarPlay Audio App“), danach Entitlement in `Amperfy/Amperfy.entitlements` zurück

## Someday

### Oberfläche

- [ ] **UI-5 „Zu Playlist hinzufügen“ als schlankes Sheet**
  - Heute `PlaylistSelectorVC` + 14 VCs unter `PlaylistAdd/` im Originalstil. Neues Sheet: „Neue Playlist“ oben, zuletzt genutzte Playlists mit Cover, Rest alphabetisch
- [ ] **UI-6 Volle Lyrics-Ansicht im Stil der Lyrics-Karte**
  - `LyricTableCell` (feste Schrift): große fette Zeilen auf der Cover-Farbe, aktuelle Zeile hell, Tap auf eine Zeile = Sprung zur Stelle
- [ ] **UI-7 Login, Sync, Update im Drift-Stil**
  - `LoginVC` (3× `systemFont(ofSize:)`), `SyncVC`, `UpdateVC`, `LibrarySyncPopupVC`: Fläche `DS.Color.background`, Wellen-Glyph, Fortschritt in Label-Farbe
- [ ] **UI-8 „Shuffle all“/„Play“-Zeile in Songs, Artists, Genres**
  - Kopfzeile wie auf den Detailseiten, in `SongsVC`, `ArtistsVC`, `GenresVC`
- [ ] **UI-9 Restliche XIB-Schriften auf `DS.Font`**
  - `PlayableTableCell.xib` (13), `GenericTableCell.xib` (8), Queue-Header (`ContextQueue…`, `UserQueueSectionHeader`), `EntityPreviewVC.xib` (Bitrate wird abgeschnitten), `DirectoryTableCell.xib`
- [ ] **UI-10 Barrierefreiheit der Fork-Views**
  - Mini-Player: `accessibilityCustomActions` für Skip vor/zurück und Player öffnen
  - Labels für `DownloadJobCell`, `SearchStatusCell`, `NowPlayingBarsView`, Home/Search-Fork-Zellen. Skeletons für VoiceOver ausblenden
  - Zoom-Übergang zum Player bei „Bewegung reduzieren“ prüfen
  - Fertig, wenn: Home → Album → Abspielen → Skip ist komplett mit VoiceOver bedienbar
- [ ] **UI-11 Lyrics-Karte unter das Cover statt neben ihm**
  - Bekannte Grenze aus Phase 5: Karte nimmt dem Cover auf kleinen iPhones Höhe weg. Karte per Scrollen unter dem Cover erreichbar machen
- [ ] **UI-12 Sleep Timer sichtbar im Player**
  - Chip „Pausiert um 23:40“ unter den Controls, Tap = Menü. Lautstärke in den letzten 10 s ausblenden statt harter Pause
- [ ] **UI-13 Bewegter Cover-Verlauf im Player**
  - `AnimatedGradientLayer` existiert. Langsamer Verlauf aus `ArtworkColorCache`-Farben, aus bei „Bewegung reduzieren“
- [ ] **UI-14 Kompakter Mini-Player im Inline-Modus**
  - Bei minimierter Tab-Bar (`tabAccessoryEnvironment == .inline`) nur Cover, Titel, Play
- [ ] **UI-15 Deutsche Texte per String Catalog**
  - Zuerst nur Fork-Texte und `ForkMenuText.relabel`, Upstream-Literale bleiben
- [ ] **UI-16 Entscheidung iPad/Mac**
  - Fork-Design gilt nur auf dem iPhone. Entweder in `FORK.md` festhalten oder Home, Suche und Detailseiten auf dem iPad mitnehmen
- [ ] **UI-17 Leerzustände mit Aktion in den übrigen Listen**
  - Favoriten („Tippe auf ♥“), Playlists („Neue Playlist“), Downloads, Podcasts

### Features

- [ ] **F-5 „Ähnliche Songs von YouTube“** - Roadmap 4
  - Shelf auf Künstler- und Albumseite (`ShelfLayout.section(.large)`, `display(title:…, image:)`). Song-Radio läuft mit YouTube-Treffern weiter, wenn die Sammlung leer läuft
- [ ] **F-6 YouTube-Platzhalter nach dem Sync ersetzen**
  - `ytm-…`-Songs in Queue, Verlauf und Playlists gegen den echten Navidrome-Song tauschen, sobald `YouTubeMusicLibrarySync` ihn gefunden hat
  - Playlists: Der Proxy entfernt Fake-IDs aus `createPlaylist`/`updatePlaylist` und startet nur den Download. Die App muss den Song nach der Zuordnung selbst erneut hinzufügen (an der gemerkten Position)
- [ ] **F-7 Mitteilung bei fertigem Download**
  - Lokale Notification bei `fertig`/`fehler`, Tap öffnet das Album. Optional Live Activity, solange Jobs laufen
- [ ] **F-8 Ganzes Album / Künstler von YouTube laden**
  - Braucht einen Endpunkt im Songpicker (`album_id`, `kind`). In der App: Menüeintrag am YouTube-Treffer „Ganzes Album laden“
- [ ] **F-9 Teilen-Erweiterung „Teilen → Drift“**
  - Erstes Extension-Target: Link aus YouTube Music/Safari annehmen, Video-ID auslesen, `POST /api/get`
- [ ] **F-10 Weiterhören auf anderem Gerät (`savePlayQueue`/`getPlayQueue`)**
  - Queue + Position beim Pausieren/Beenden speichern, beim Start anbieten „Weiter mit …“
- [ ] **F-11 Home-Shelves aus `getAlbumList2`**
  - „Am meisten gehört“ (`frequent`), „Bestbewertet“ (`highest`), „Jahrzehnte“ (`byYear`). Neue `HomeSection`-Fälle **am Ende**
- [ ] **F-12 Mixe aus lokalen Daten**
  - „Lieblinge, lange nicht gehört“ (Favoriten mit altem `lastPlayedDate`), „In Dauerschleife“ (viele Plays in 14 Tagen), Tagesmix (Favoriten + `getSimilarSongs2`)
- [ ] **F-13 Statistik / Jahresrückblick**
  - Aus `playCount`, `lastPlayedDate`, `UserStatistics`: Top-Künstler, Top-Songs, Hörzeit
- [ ] **F-14 Widgets und Kontrollzentrum**
  - Neues Widget-Target. Interaktive Widgets „Zuletzt gehört“, „Favoriten mischen“, Taste im Kontrollzentrum. App Intents gibt es schon (`AmperfyAppShortcuts`)
- [ ] **F-15 Spotlight-Indexierung**
  - Alben, Künstler, Playlists als `CSSearchableItem`, Tap öffnet die Detailseite
- [ ] **F-17 Crossfade**
  - Engine `AudioStreaming` (AVAudioEngine) lädt den nächsten Song schon vor. Größter Eingriff in AmperfyKit, zuletzt

## Done

- [x] ~~**F-1 YouTube Music nur noch über Subsonic am Login-Host**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**F-1a Fake-Songs des Proxys aus der Bibliothek halten**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**F-1b Download-Liste über `/rest/getYtJobs.view`**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**UI-1 Podcast-Detailseite mit `ImmersiveDetailHeaderView`**~~ (2026-10-29) - FORK.md Abschnitt 10
