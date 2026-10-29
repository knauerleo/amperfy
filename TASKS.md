# Tasks

Aus der Durchsicht vom 2026-10-29. `UI-…` = Modernisierung der Oberfläche, `F-…` = neue Features.
Regeln aus `DESIGN-AUDIT.md` §7 gelten weiter: neue Dateien statt Umbauten, XIBs nicht anfassen, Hooks mit einer Zeile.

## Active

- [ ] **F-16 CarPlay wieder einschalten** - Antrag bei Apple (developer.apple.com/contact/carplay, „CarPlay Audio App“), danach Entitlement in `Amperfy/Amperfy.entitlements` zurück

## Someday

### Oberfläche

- [ ] **UI-15c Restliche Upstream-Texte auf Deutsch** - Rest von UI-15b
  - Offen: Alerts in Upstream-VCs (Texte direkt in `UIAlertController`), XIB-Texte (bräuchten `Base.lproj`, XIBs bleiben unangetastet), Texte mit Einsetzungen („Rating: \(rating)“), Titel von Untermenüs („More Queue Options“ ist ein `UIMenu`, dessen Titel nur lesbar ist), `EventLogger`-Themen, Upstream-Texte außerhalb der Engstellen von UI-15b. Neue Texte in `Amperfy/Localizable.xcstrings` eintragen, sie greifen dann über `ForkMenuText.upstream`
- [ ] **UI-27b Optionszeile unter den Controls entfernen** - Warteschlange als kleines Symbol rechts unter den Controls, AirPlay, Sleep-Timer, Modus, Lautstärke und Optionen ins „…“ oben, freier Platz für die Lyrics-Karte
- [ ] **UI-26 Player nach UI-21 abnehmen** - Screenshot nötig, dann Feinschliff. 2026-10-29: Kopfzeile 20 statt 8 pt unter der Safe Area (FORK.md Abschnitt 10)

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
- [x] ~~**UI-19 Mini-Player als schwebende Karte statt Glas**~~ (2026-10-29) - FORK.md Abschnitt 10, per Screenshot abgenommen; Tab-Bar verkleinert sich auf dem iPhone nicht mehr, die Karte schwebt fest darüber (2026-10-29)
- [x] ~~**F-20 Albumseite nach Tracknummer sortiert**~~ (2026-10-29) - FORK.md Abschnitt 10, auf dem iPhone noch nicht geprüft
- [x] ~~**F-6b Crash beim Platzhalter-Tausch**~~ (2026-10-29) - FORK.md Abschnitt 10, Ursache aus dem Crash-Log, Ablauf auf dem iPhone nicht nachgestellt
- [x] ~~**UI-23 Albumseite wie im Mockup**~~ (2026-10-29) - FORK.md Abschnitt 10, Zurück/„…“ bleiben die Glasknöpfe von iOS 26, auf dem iPhone noch nicht angesehen
- [x] ~~**UI-25 Abspielen/Zufall-Zeile wie im Mockup**~~ (2026-10-29) - FORK.md Abschnitt 10, Anzahl unter dem großen Titel statt daneben (entschieden 2026-10-29), auf dem iPhone noch nicht angesehen
- [x] ~~**F-19b Fehlende Songs auch bei Editionen auf YouTube Music**~~ (2026-10-29) - FORK.md Abschnitt 10; Meteora zeigt zu Recht nichts: die übrigen Songs liegen schon im Album „Meteora (Bonus Edition)“ (2026-10-29)
- [x] ~~**UI-19b Mini-Player-Karte verdeckt das Ende der Albumseite**~~ (2026-10-29) - FORK.md Abschnitt 10, auf dem iPhone noch nicht geprüft
- [x] ~~**UI-24 Alben-Liste wie im Mockup**~~ (2026-10-29) - FORK.md Abschnitt 10, Raster bleibt, Anzahl unter dem Titel, auf dem iPhone noch nicht angesehen
- [x] ~~**UI-27a Lyrics-Karte sichtbar, Songtext im Vollbild**~~ (2026-10-29) - FORK.md Abschnitt 10, auf dem iPhone noch nicht angesehen
