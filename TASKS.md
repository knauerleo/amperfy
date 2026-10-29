# Tasks

Aus der Durchsicht vom 2026-10-29. `UI-…` = Modernisierung der Oberfläche, `F-…` = neue Features.
Regeln aus `DESIGN-AUDIT.md` §7 gelten weiter: neue Dateien statt Umbauten, XIBs nicht anfassen, Hooks mit einer Zeile.

## Active

- [ ] **F-16 CarPlay wieder einschalten** - Antrag bei Apple (developer.apple.com/contact/carplay, „CarPlay Audio App“), danach Entitlement in `Amperfy/Amperfy.entitlements` zurück

## Someday

### Oberfläche

- [ ] **UI-15c Restliche Upstream-Texte auf Deutsch** - Rest von UI-15b
  - Offen: Alerts in Upstream-VCs (Texte direkt in `UIAlertController`), XIB-Texte (bräuchten `Base.lproj`, XIBs bleiben unangetastet), Texte mit Einsetzungen („Rating: \(rating)“), Titel von Untermenüs („More Queue Options“ ist ein `UIMenu`, dessen Titel nur lesbar ist), `EventLogger`-Themen, Upstream-Texte außerhalb der Engstellen von UI-15b. Neue Texte in `Amperfy/Localizable.xcstrings` eintragen, sie greifen dann über `ForkMenuText.upstream`
- [ ] **UI-23 Albumseite wie im Mockup** - Abgleich mit „Drift Identität + Listen“, Board „Albumseite“ (2026-10-29, aus dem Code, nicht am Gerät)
  - Cover 220 pt (heute bis 260 pt, Breite − 128), Radius 14 statt 8 (`DS.Radius.card` statt `medium`), Schatten kräftiger (Mockup 0,55 Deckkraft, 24 pt Versatz, 48 pt Unschärfe; heute 0,35 / 8 / 18)
  - Play-Knopf 56 statt 52 pt; Trackzeilen auf der Albumseite 56 statt 60 pt
  - Infozeile als „Album · 2000 · 12 Songs · 37 Min“ (heute `info(.long)` des Upstreams, Inhalt prüfen)
  - Zurück und „…“ oben als runde, halbdunkle 44-pt-Knöpfe über dem Farbverlauf (iOS 26 zeichnet Glas-Knöpfe, ggf. so lassen)
- [ ] **UI-24 Alben-Liste wie im Mockup** - Board „Alben-Liste“
  - Großer Titel „Alben“ mit der Anzahl rechts auf derselben Grundlinie, oben rechts Sortieren/Filtern
  - Filter-Chips (34 pt, rund): „Zuletzt hinzugefügt“ (aktiv in Mint), „Favoriten“, „Geladen“
  - Abspielen/Zufall-Zeile auch bei Alben (heute nur Songs, Künstler, Genres)
  - Entschieden 2026-10-29: Das Raster aus UI-2 bleibt, keine Liste wie im Mockup
- [ ] **UI-25 Abspielen/Zufall-Zeile wie im Mockup** - Boards „Alben-Liste“ und „Drift Identität“
  - Zwei gleich breite Pillen über die volle Breite, 44 pt hoch (heute 40 pt, nebeneinander links, Anzahl rechts in der Zeile); die Anzahl wandert neben den großen Titel (siehe UI-24)
- [ ] **UI-26 Player nach UI-21 abnehmen** - Screenshot nötig, dann Feinschliff

## Backlog (ganz hinten)

- [ ] **F-17 Crossfade** - Entscheidung 2026-10-29: ganz nach hinten, erst wenn alles andere erledigt ist
  - Analysiert: nicht mit einzeiligen Hooks machbar, `BackendAudioPlayer` braucht zwei Kanäle. Umsetzungsplan in FORK.md, „Roadmap“ › „Crossfade (TASKS F-17): Umsetzungsplan“. Vor dem Bau den Plan zeigen

## Done

- [x] ~~**F-1 YouTube Music nur noch über Subsonic am Login-Host**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**F-1a Fake-Songs des Proxys aus der Bibliothek halten**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**F-1b Download-Liste über `/rest/getYtJobs.view`**~~ (2026-10-29) - FORK.md Abschnitt 9
- [x] ~~**UI-1 Podcast-Detailseite mit `ImmersiveDetailHeaderView`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-2 „All Albums“-Raster mit `LargeAlbumCell`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-3 Playlists-Liste modernisieren**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-4 Player-Schriften auf `DS.Font`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-3 Künstlerseite mit `getArtistInfo2`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-4 „Popular“ mit `getTopSongs`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-6 Volle Lyrics-Ansicht im Stil der Lyrics-Karte**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-11 Lyrics-Karte unter das Cover statt neben ihm**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-12 Sleep Timer sichtbar im Player**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-13 Bewegter Cover-Verlauf im Player**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-14 Kompakter Mini-Player im Inline-Modus**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-8 „Shuffle all“/„Play“-Zeile in Songs, Artists, Genres**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-9 Restliche XIB-Schriften auf `DS.Font`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-17 Leerzustände mit Aktion in den übrigen Listen**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-5 „Zu Playlist hinzufügen“ als schlankes Sheet**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-7 Login, Sync, Update im Drift-Stil**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-6 YouTube-Platzhalter nach dem Sync ersetzen**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-7 Mitteilung bei fertigem Download**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-5 „Ähnliche Songs von YouTube“**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-11 Home-Shelves aus `getAlbumList2`**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-12 Mixe aus lokalen Daten**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-13 Statistik / Jahresrückblick**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-10 Weiterhören auf anderem Gerät (`savePlayQueue`/`getPlayQueue`)**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-15 Spotlight-Indexierung**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-9 Teilen-Erweiterung „Teilen → Drift“**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-10 Barrierefreiheit der Fork-Views**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-15 Deutsche Texte per String Catalog**~~ (2026-10-29) - FORK.md Abschnitt 10, nur Fork-Texte, Rest in UI-15b
- [x] ~~**F-2 Server-URL automatisch umschalten**~~ (2026-10-29) - überflüssig – seit F-1 nur noch die Domain
- [x] ~~**UI-16 Entscheidung iPad/Mac**~~ (2026-10-29) - Fork-Design nur auf dem iPhone, iPad und Mac bleiben im Upstream-Stil, FORK.md Abschnitt 10 und „Arbeitsweise“
- [x] ~~**F-14 Widgets und Kontrollzentrum**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**UI-18 Identität + Listen**~~ (2026-10-29) - nur iPhone, FORK.md Abschnitt 10 und Abschnitt 2 „Design-Tokens“, Mini-Player-Karte offen in UI-19
- [x] ~~**F-8 Ganzes Album / Künstler von YouTube laden**~~ (2026-10-29) - FORK.md Abschnitt 9 und 10, nur App-Seite, Server-Teil live
- [x] ~~**UI-20 Drei Tabs, Player als scrollende Seite, Name „Drift“ im System**~~ (2026-10-29) - FORK.md Abschnitt 10, Mini-Player-Karte weiter offen in UI-19
- [x] ~~**F-18 Songdauer beim Abspielen immer bekannt**~~ (2026-10-29) - FORK.md Abschnitt 10, YouTube- und lokaler Song auf dem iPhone noch nicht geprüft
- [x] ~~**UI-21 Player luftiger**~~ (2026-10-29) - FORK.md Abschnitt 10, Abnahme per Screenshot offen
- [x] ~~**UI-22 Album auf Home öffnet das Album**~~ (2026-10-29) - FORK.md Abschnitt 10
- [x] ~~**F-19 Fehlende Album-Songs von YouTube**~~ (2026-10-29) - FORK.md Abschnitt 10, auf dem iPhone noch nicht geprüft
- [x] ~~**UI-15b Upstream-Texte auf Deutsch**~~ (2026-10-29) - FORK.md Abschnitt 10, Rest in UI-15c
- [x] ~~**F-9b Album-Links in der Teilen-Erweiterung**~~ (2026-10-29) - FORK.md Abschnitt 10, Teilen auf dem iPhone noch nicht geprüft
- [x] ~~**UI-22b Playlists auf Home öffnen die Playlist**~~ (2026-10-29) - FORK.md Abschnitt 10, Tap auf dem iPhone noch nicht geprüft
- [x] ~~**UI-19 Mini-Player als schwebende Karte statt Glas**~~ (2026-10-29) - FORK.md Abschnitt 10, Abnahme per Screenshot offen, Verhalten beim Verkleinern der Tab-Bar auf dem iPhone noch nicht geprüft
