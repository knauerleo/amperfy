# Tasks

Aus der Durchsicht vom 2026-10-29. `UI-…` = Modernisierung der Oberfläche, `F-…` = neue Features.
Regeln aus `DESIGN-AUDIT.md` §7 gelten weiter: neue Dateien statt Umbauten, XIBs nicht anfassen, Hooks mit einer Zeile.

## Active

- [ ] **UI-21 Player luftiger** - Screenshot vom 2026-10-29 nach UI-20
  - Kopfzeile „Wird gespielt von“ klebt unter der Dynamic Island, unten drängen sich Zeitleiste, „MP3 124 kbps“, Steuerreihe und Optionszeile, zwischen Cover und Titel ist viel Luft
- [ ] **UI-22 Album auf Home öffnet das Album** - Tap auf eine Albumkachel spielt heute sofort ab
- [ ] **F-19 Fehlende Album-Songs von YouTube** - Albumseite einer Bibliotheks-Album: Songs, die auf YouTube Music zum Album gehören, aber lokal fehlen, mit Wolke anzeigen, „Album laden“ wie in der Suche (F-8)

## Waiting On

- [ ] **F-16 CarPlay wieder einschalten** - Antrag bei Apple (developer.apple.com/contact/carplay, „CarPlay Audio App“), danach Entitlement in `Amperfy/Amperfy.entitlements` zurück

## Someday

### Oberfläche

- [ ] **UI-19 Mini-Player als schwebende Karte** - Rest von UI-18
  - Mockup: Fläche „Erhöht“, Radius 14, Schatten, Fortschritt 2 pt Mint (Fortschritt und Farbe sind erledigt). Der Mini-Player ist das `bottomAccessory` der iOS-26-Tab-Bar, das System zeichnet dort Liquid Glass und Form. Eine eigene Karte hieße, die Accessory-Logik (`TabBarVC`, Inline-Modus UI-14) umzubauen
  - Ebenso offen: Tab-Bar „in Grund mit leichter Transparenz“ – ein eigener Hintergrund würde das Glas ersetzen, darum nur die Farben
- [ ] **UI-15b Upstream-Texte auf Deutsch** - Rest von UI-15
  - Fork-Texte stehen in `Amperfy/Fork.xcstrings` (Tabelle `Fork`). Offen: Upstream-Literale (UIKit-Menüs, Alerts, `SwipeActionType`-Namen, SwiftUI-Einstellungen, XIBs), dafür eine `Localizable.xcstrings` bzw. XIB-Strings
  - Ebenfalls offen: vom Fork nur umbenannte Upstream-Texte (`HomeSection` „Recently Played“/„Recently Added“, Menüeinträge in `EntityPreviewVC`, Swipe-Namen, „Tap to reopen Drift“) und die `EventLogger`-Themen

### Features

- [ ] **F-9b Album-Links in der Teilen-Erweiterung** - Idee aus F-8, nicht gebaut
  - `music.youtube.com/browse/MPREb_…` ginge direkt über `downloadYtAlbum.view?id=ytm-album-MPREb_…` (eine Anfrage, Antwort sofort, kein Warten aufs erste Byte). Die Extension kennt nur die Stream-URL-Vorlage (`forkYouTubeStreamTemplate`), bräuchte also eine zweite Vorlage für `downloadYtAlbum` in der Keychain-Gruppe. `list=`-Links (Playlists, `OLAK5uy_…`) bleiben Fehler, dafür gibt es keinen Endpunkt
- [ ] **F-17 Crossfade**
  - Engine `AudioStreaming` (AVAudioEngine) lädt den nächsten Song schon vor. Größter Eingriff in AmperfyKit, zuletzt
  - Analysiert (2026-10-29): nicht mit einzeiligen Hooks machbar, `BackendAudioPlayer` braucht zwei Kanäle. Umsetzungsplan in FORK.md, „Roadmap“ › „Crossfade (TASKS F-17): Umsetzungsplan“

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
