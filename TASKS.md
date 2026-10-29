# Tasks

Aus der Durchsicht vom 2026-10-29. `UI-…` = Modernisierung der Oberfläche, `F-…` = neue Features.
Regeln aus `DESIGN-AUDIT.md` §7 gelten weiter: neue Dateien statt Umbauten, XIBs nicht anfassen, Hooks mit einer Zeile.

## Active

- [ ] **F-2 Server-URL automatisch umschalten** - mit F-1 meist überflüssig (nur noch die Domain), nur falls LAN-Adresse weiter genutzt wird
  - Bei Netzwechsel (`NetworkMonitor`) die erste erreichbare URL aus `activeBackendServerUrl` + `alternativeServerURLs` per `ping` wählen

## Waiting On

- [ ] **F-16 CarPlay wieder einschalten** - Antrag bei Apple (developer.apple.com/contact/carplay, „CarPlay Audio App“), danach Entitlement in `Amperfy/Amperfy.entitlements` zurück

## Someday

### Oberfläche

- [ ] **UI-15 Deutsche Texte per String Catalog**
  - Zuerst nur Fork-Texte und `ForkMenuText.relabel`, Upstream-Literale bleiben
- [ ] **UI-16 Entscheidung iPad/Mac**
  - Fork-Design gilt nur auf dem iPhone. Entweder in `FORK.md` festhalten oder Home, Suche und Detailseiten auf dem iPad mitnehmen

### Features

- [ ] **F-8 Ganzes Album / Künstler von YouTube laden**
  - Braucht einen Endpunkt im Songpicker (`album_id`, `kind`). In der App: Menüeintrag am YouTube-Treffer „Ganzes Album laden“
- [ ] **F-14 Widgets und Kontrollzentrum**
  - Neues Widget-Target. Interaktive Widgets „Zuletzt gehört“, „Favoriten mischen“, Taste im Kontrollzentrum. App Intents gibt es schon (`AmperfyAppShortcuts`)
  - Blockiert (2026-10-29): Die App Group lässt sich nicht registrieren, solange im Developer-Account die neue Program License Agreement nicht akzeptiert ist („PLA Update available“). Danach erneut bauen
- [ ] **F-17 Crossfade**
  - Engine `AudioStreaming` (AVAudioEngine) lädt den nächsten Song schon vor. Größter Eingriff in AmperfyKit, zuletzt

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
