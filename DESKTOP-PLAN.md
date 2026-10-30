# Drift Desktop: Plan für Windows, macOS und Linux in Rust

Stand 2026-10-30. Entwurf, noch nichts gebaut.

Ziel: Ein eigener Desktop-Client „Drift“ für Windows, macOS und Linux, der dasselbe Setup spricht wie die iPhone-App
(Login-Host `https://musik.leokna.de`, Subsonic über den Proxy, YouTube Music über `ytm-`-IDs) und sich wie ein
Streaming-Client anfühlt. Kein Port von Amperfy: neuer Code, neue Architektur, gleiche Server-Verträge.
Grundlage sind FORK.md („Server-Setup“, Abschnitt 9, „Server-Vertrag vom 2026-10-29“) und die Design-Tokens aus
`Amperfy/Screens/Basics/DesignTokens.swift`.

---

## 1. Entscheidungen vorab

| Frage | Vorschlag | Begründung |
|---|---|---|
| Repo | Neues Repo `knauerleo/drift-desktop`, nicht in diesem | Kein Code aus Amperfy wird übernommen, der Xcode-Fork bleibt unberührt |
| Lizenz | GPL-3.0 | Gleiche Lizenz wie der Fork, „Based on Amperfy“ nur als Hinweis in „Über“, falls Ideen/Texte übernommen werden |
| UI-Technik | **Tauri 2** (entschieden 2026-10-30): Rust-Kern + Webview-Oberfläche mit Svelte 5 und TypeScript, gebaut mit Vite | Drift lebt vom Look (Cover-Verläufe, Unschärfe, Karten, Lyrics-Ansicht, lange virtualisierte Listen). Im Webview geht das am schnellsten und sieht auf allen drei Systemen gleich aus. Alles mit Logik (API, Datenbank, Audio, Downloads, Systemintegration) ist Rust. Typen für Befehle und Ereignisse erzeugt `tauri-specta` aus dem Rust-Code, damit Oberfläche und Kern nicht auseinanderlaufen |
| Verworfen | Slint 1.x | Verläufe, Unschärfe und Animationen von Hand, Listen mit tausenden Zeilen und Covern mehr Aufwand |
| Audio | Eigene Engine: `symphonia` (Decoder) + `opus` (libopus, für die `.opus`-Dateien aus YouTube) + `cpal` (Ausgabe) | Volle Kontrolle für Gapless, ReplayGain, EQ, Visualizer, Spulen in laufenden Streams (F-22) und später Crossfade (F-17, zwei Kanäle sind hier von Anfang an eingeplant). Fallback: `libmpv` über `libmpv2`, falls der Spike in Phase 0 scheitert |
| macOS | Desktop-App ersetzt auf Dauer die Catalyst-Variante | Catalyst bleibt im Upstream-Stil (UI-16), die Desktop-App bekommt das Drift-Design |

---

## 2. Architektur

Cargo-Workspace, die Oberfläche spricht nur über eine schmale Befehls-/Ereignis-Schnittstelle mit dem Kern.

```
drift-desktop/
├─ crates/
│  ├─ drift-subsonic/   Subsonic/OpenSubsonic-Client (reqwest + rustls, serde, f=json, Token-Auth md5(pw+salt))
│  ├─ drift-proxy/      Drift-Erweiterungen des Proxys: getYtJobs, getYtAlbum, getYtArtist, downloadYtAlbum,
│  │                    downloadAlbumMissing, getAlbum&drift=full, searchLyrics, ytm-/ndv-ID-Typen
│  ├─ drift-library/    SQLite (rusqlite + refinery-Migrationen), Sync, Volltextsuche (FTS5), Cover-Cache
│  ├─ drift-audio/      Engine: 2 Kanäle, Decoder, Resampler (rubato), EQ (biquad), ReplayGain, Gapless, Analyzer
│  ├─ drift-player/     Warteschlange, Shuffle/Repeat, Scrobbling, Play-Queue-Sync, Sleep Timer, Statistik
│  ├─ drift-downloads/  Offline-Dateien, Vorwärmen (HEAD wie F-22), Auto-Cache
│  ├─ drift-system/     Mediensteuerung (souvlaki: MPRIS / SMTC / MPNowPlayingInfoCenter), Tray, Hotkeys,
│  │                    Mitteilungen, Keyring (Zugangsdaten), Deep Links drift://
│  └─ drift-core/       Verdrahtung: AppState, Befehle, Ereignis-Bus (tokio broadcast), Einstellungen
├─ app/                 Tauri-Shell (src-tauri) + Oberfläche (ui/)
└─ xtask/               Build, Signieren, Paketieren
```

Leitlinien:

- **Async überall** (tokio). Kein Netzwerk- oder Datei-Zugriff im UI-Thread; die Audio-Callback-Schleife ist
  allokationsfrei und spricht nur über einen lock-freien Ring-Puffer (`rtrb`) mit dem Rest.
- **IDs als Typen:** `SongId::{Navidrome(String), YouTube(VideoId), Elsewhere{song, album}}` für `ytm-`/`ndv-`.
  Damit gilt die Regel „`ytm-`-Songs nicht in die Bibliothek“ (F-1a) schon beim Parsen, nicht erst später.
- **`drift=full`-Antworten nie in die Datenbank** (Server-Vertrag), nur im Speicher für die Albumseite.
- **Client-Name** bei Subsonic: `Drift Desktop` statt `Amperfy`. Damit kann Play-Queue-Sync `changedBy` auswerten
  (behebt die Grenze aus F-10 für dieses Gerät).
- **Kern ohne Tauri testbar:** `drift-core` hat eine CLI (`drift-cli login/sync/play`) für Tests und Fehlersuche.

---

## 3. Funktionsumfang nach Phasen

Schätzungen in Arbeitstagen für einen Entwickler mit Claude, ohne Wartezeiten (Zertifikate, Store).

### Phase 0: Spikes (3–4 Tage)

Klärt die Risiken, bevor die Struktur steht. Jeder Spike ist ein Wegwerf-Binary.

- **D-0a Audio:** 320-kbit-MP3 aus `stream.view?id=ytm-…&format=mp3` (chunked, ohne Content-Length) abspielen,
  erster Ton messen; FLAC und `.opus` aus Navidrome; Gapless zwischen zwei Album-Tracks; Spulen in einem laufenden
  Stream per `timeOffset`. Auf allen drei Systemen (cpal: WASAPI, CoreAudio, PipeWire/ALSA).
  Ergebnis: Engine selbst bauen oder libmpv.
- **D-0b UI:** Albumseite mit 5 000 Songs virtualisiert + Cover-Verlauf in Tauri/Svelte, flüssig auch unter
  WebKitGTK (Linux). Cover kommen über ein eigenes Protokoll `drift-cover://` aus dem Rust-Cache, nicht per Base64.
- **D-0c Systemintegration:** `souvlaki` zeigt Titel/Cover und reagiert auf Medientasten auf allen drei Systemen.

### Phase 1: Fundament und Abspielen (MVP, ~3 Wochen)

- **D-1 Login:** Server-URL, Benutzer, Passwort; Erkennung OpenSubsonic (`getOpenSubsonicExtensions`);
  Passwort im System-Schlüsselbund (`keyring`), mehrere Accounts.
- **D-2 Bibliotheks-Sync:** Künstler, Alben, Songs, Playlists, Genres in SQLite. Erster Sync mit Fortschritt,
  danach inkrementell (`getIndexes`/`ifModifiedSince`, `getAlbumList2?type=newest`). Cover-Cache auf Platte (LRU, Größe einstellbar).
- **D-3 Engine:** Abspielen, Pause, Spulen, Lautstärke, Gapless, ReplayGain (Track/Album), Puffer-Anzeige.
- **D-4 Warteschlange:** Als Nächstes, Hinzufügen, Umordnen per Drag & Drop, Shuffle, Repeat; Zustand übersteht Neustart.
- **D-5 Grundansichten:** Seitenleiste (Home, Suche, Bibliothek, Playlists, Downloads), Albumseite, Künstlerseite,
  Playlist, Player-Leiste unten mit Cover, Fortschritt, Lautstärke.
- **D-6 Mediensteuerung:** Medientasten, Now Playing / MPRIS / SMTC mit Cover.
- **D-7 Scrobbling:** `scrobble.view` (jetzt spielt + gehört), offline gepuffert.

Abnahme: Ein Album aus Navidrome und ein YouTube-Song laufen auf allen drei Systemen, Medientasten gehen.

### Phase 2: Drift-Funktionen (~3 Wochen)

Das, was Drift von einem normalen Subsonic-Client unterscheidet (iPhone-Gegenstück in Klammern).

- **D-8 Suche mit YouTube Music:** `search3` am Login-Host, `ytm-`-Treffer als eigene Sektion mit ☁︎, Top-Treffer-Ranking
  mit Bonus aus `playCount`/Favorit/zuletzt gehört (Abschnitt 5, `forkScore`). Scope „Songtext“ über `searchLyrics` (F-21).
- **D-9 YouTube abspielen und laden:** Abspielen über `stream.view?id=ytm-…`; „In Sammlung laden“ (erstes Byte lesen,
  dann trennen, F-1); Download-Liste aus `getYtJobs` mit Polling, Mitteilung bei `fertig` (F-1b, F-7);
  Platzhalter durch den echten Song ersetzen, sobald Navidrome ihn kennt (F-6).
- **D-10 YouTube-Album und -Künstler:** `getYtAlbum`, `getYtArtist`, `downloadYtAlbum` (F-8).
- **D-11 „Fehlt in deiner Sammlung“:** Albumseite mit `getAlbum&drift=full`, „Fehlende laden“ per
  `downloadAlbumMissing`, Job-Zustände live (F-19c).
- **D-12 Links einfügen:** Statt Teilen-Erweiterung (F-9/F-9b): YouTube-/YTM-Link per Strg/⌘+V ins Fenster, per Drag &
  Drop oder als `drift://add?url=…`; gleiche Erkennung (`watch?v=`, `youtu.be`, `shorts`, `browse/MPREb_…`).
- **D-13 Künstlerseite:** `getArtistInfo2` (Bild, Bio, ähnliche Künstler), „Popular“ aus `getTopSongs` (F-3, F-4).
- **D-14 Home:** Zuletzt gehört, neu hinzugefügt, meistgehört, Top Rated, Jahrzehnte aus `getAlbumList2` (F-11);
  Mixe aus lokalen Daten (F-12); „Ähnliche Songs von YouTube“ (F-5).
- **D-15 Lyrics:** OpenSubsonic `getLyricsBySongId` (synchron), mitlaufende Zeile im Player, Vollbild-Ansicht (UI-6, UI-27a).
- **D-16 Weiterhören:** `savePlayQueue`/`getPlayQueue` beim Pausieren, Songwechsel, Beenden; Angebot „Weiterhören?“
  beim Start (F-10).
- **D-17 Favoriten und Bewertung:** `star`/`unstar`/`setRating`, auch für `ndv-`-IDs.

### Phase 3: Desktop-Komfort und Feinschliff (~2 Wochen)

- **D-18 Offline:** Alben/Playlists auf Platte laden (Original oder transkodiert, einstellbar), Offline-Modus mit
  automatischer Erkennung, Speicherverwaltung.
- **D-19 Vorwärmen und Spulen (F-22):** HEAD-Vorwärmen aus Suche und Albumseite, Auto-Cache des laufenden Songs,
  Spulen per `timeOffset` bzw. Wechsel auf die Cache-Datei. Zahlen gegen die iPhone-Messung legen.
- **D-20 Tray und Mini-Player:** Tray-Menü (Play/Pause, Weiter, Titel), schwebender Mini-Player, „Beim Schließen in
  den Tray“ (Windows/Linux) bzw. Dock-Menü (macOS).
- **D-21 Tastatur:** Leertaste, Pfeile, ⌘/Strg+F, ⌘/Strg+L (Lyrics), globale Hotkeys optional; Befehlspalette (⌘/Strg+K).
- **D-22 EQ, Sleep Timer, Visualizer:** 10-Band-EQ mit Presets, Sleep Timer mit Ausblenden (UI-12), Spektrum aus dem Analyzer.
- **D-23 Statistik / Jahresrückblick** aus der lokalen Datenbank (F-13).
- **D-24 Sprache:** Englisch und Deutsch mit Fluent (`fluent-bundle`), Ansprache „du“, Sprache folgt dem System oder Einstellung.
- **D-25 Barrierefreiheit:** Tastaturbedienung überall, Screenreader-Beschriftungen, „Bewegung reduzieren“ respektieren.

### Phase 4: Verteilung (~1 Woche + Wartezeit auf Zertifikate)

- **D-26 CI:** GitHub Actions, Matrix `windows-latest`, `macos-14` (arm64 + x86_64 als Universal), `ubuntu-22.04`;
  `cargo clippy`, `cargo test`, UI-Tests, Bundles als Artefakte.
- **D-27 macOS:** `.dmg`, Developer-ID-Signatur mit dem vorhandenen Team (`45L48D96FZ`), Notarisierung
  (`notarytool`), Hardened Runtime. Optional später Mac App Store (Sandbox, eigene Bundle-ID `de.knauerleo.drift-desktop`).
- **D-28 Windows:** MSI (WiX) oder NSIS-Installer, Signatur über Azure Trusted Signing (sonst SmartScreen-Warnung),
  WebView2 per Bootstrapper.
- **D-29 Linux:** AppImage und `.deb`, Flatpak über Flathub später; Abhängigkeiten WebKitGTK 4.1, PipeWire/ALSA, D-Bus.
- **D-30 Updates:** Tauri-Updater mit signierten Releases auf GitHub, Kanal „stabil“/„beta“.

### Danach (Backlog)

- **D-31 Crossfade (F-17):** Zweiter Kanal ist in `drift-audio` schon da, Rampe mit gleicher Leistung (cos/sin).
- **D-32 Podcasts und Radios**, falls genutzt.
- **D-33 Discord Rich Presence**, Last.fm direkt.
- **D-34 Cast/DLNA** auf andere Geräte.

Gesamt bis zur ersten signierten Version auf allen drei Systemen: **etwa 9–10 Wochen**.

---

## 4. Design

- Tokens aus `DesignTokens.swift` als gemeinsame Quelle übernehmen (Abstände 4/8/12/16/24/32, Radien 4/8/12/14,
  Schriftgrößen, Farben `background`, `surfaceRaised`, Theme-Farbe) und als CSS-Variablen (bzw. Slint-Globals)
  ablegen. Dark-first, helles Thema als zweite Stufe.
- Layout für große Fenster neu denken statt iPhone kopieren: Seitenleiste links, Inhalt mitte, optional rechte Spalte
  (Warteschlange oder Lyrics), Player-Leiste unten. Ab ~900 px schmaler Modus ohne rechte Spalte.
- Player-Vollansicht mit bewegtem Cover-Verlauf (UI-13) und Lyrics-Karte (UI-11).
- Mockups zuerst für Home, Albumseite, Suche und Player; danach bauen.

---

## 5. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Chunked MP3 ohne Content-Length: Dauer unbekannt, Spulen schwierig | Dauer aus `getSong`/Suchtreffer (wie F-18), Spulen per `timeOffset`, Spike D-0a |
| Opus-Wiedergabe braucht libopus (C) | `opus`-Crate mit statischem Build; Alternative: bei Navidrome `format=mp3`/`flac` anfordern |
| Webview-Unterschiede (WebKitGTK unter Linux langsamer) | Virtualisierte Listen, keine schweren CSS-Filter auf Listen, früh auf Linux testen |
| Erster YouTube-Ton nach 9–15 s | Klare Ladeanzeige, Vorwärmen (D-19); Server-Seite gehört zu F-22 |
| Zertifikate kosten Zeit und Geld (Windows) | Früh beantragen, bis dahin unsigniert für den Eigengebrauch |
| Aufwand doppelt zur iPhone-App | Server-Logik bleibt auf dem Pi; der Client macht nur Darstellung, Cache, Wiedergabe |

---

## 6. Erste Schritte

1. ~~Entscheidung Tauri oder Slint~~ → Tauri 2 mit Svelte 5 (2026-10-30).
2. Repo `drift-desktop` anlegen, Workspace-Gerüst, CI mit leerem Fenster auf allen drei Systemen.
3. Spikes D-0a bis D-0c, Ergebnisse hier eintragen.
4. Phase 1 starten mit `drift-subsonic` (Login + `ping` + `getAlbumList2`) und `drift-cli`.
