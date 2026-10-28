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
Gedämpft wird sie in Phase 3 zusammen mit den neuen Home-Zellen.

### Hilfsskript

`Helper/add-swift-file.py <Neu.swift> <Nachbar.swift>` trägt eine neue Datei ins Projekt ein, in dieselbe Gruppe und
dieselben Targets wie die Nachbardatei. Nötig, weil das Projekt keine synchronisierten Ordner nutzt, sondern jede
Datei einzeln in `project.pbxproj` führt.

---

## Roadmap

1. ~~Suche reparieren~~ ✅
2. **YouTube-Music-Bereich in der Suche:** eigene Sektion mit den Songpicker-Treffern, die `library == false` haben.
   - Antippen spielt sofort über den Proxy (`ytm-<id>`) ab, über die normale Warteschlange.
   - Kontextmenü mit den Einträgen „In Sammlung laden“, „Als Nächstes spielen“, „Zur Warteschlange“.
   - Status-Badge pro Treffer (Wolke, Spinner, Haken), aktualisiert per Polling von `/api/jobs`.
   - Ist ein Job `fertig`, wird der Song über Navidrome synchronisiert: per `search3` nach dem Titel suchen und über
     das Ende von `path` abgleichen.
3. **Einstellungen:** Songpicker-URL (Default `http://10.66.66.6:8781`), YouTube-Bereich an/aus.
4. Später: Download-Übersicht, „Ähnliche Songs von YouTube“.
5. Design-Überarbeitung Richtung moderner Streaming-Client, in 5 Phasen laut `DESIGN-AUDIT.md`. Phase 1 ✅

## Arbeitsweise

- Kleine Commits auf `youtube`, jeweils nach GitHub pushen.
- Neue Dateien sind besser als Umbauten großer bestehender Dateien. Den Stil von AmperfyKit beibehalten
  (async/await, CoreData-Wrapper, `storage.async.performAndGet`).
- Vor „fertig“: einmal auf dem iPhone bauen (siehe oben).
- Upstream holen: `git fetch upstream && git merge upstream/master`. Konfliktgefahr besteht vor allem in `SearchVC.swift`
  und `project.pbxproj`.
