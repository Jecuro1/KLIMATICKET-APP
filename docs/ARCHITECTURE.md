# KlimaBilanz – Architektur

Native iOS-App (SwiftUI, **iOS 26+**, Liquid Glass), gebaut mit Xcode 26 über XcodeGen (`project.yml`).
Keine Fremd-Bibliotheken – schnelle Builds, kleine App, volle Kontrolle.

```
project.yml                 XcodeGen-Spezifikation (App + Widget-Extension + lokales Paket)
Packages/KlimaCore/         Plattformunabhängige Logik (unter Linux & macOS testbar: swift test)
  Models.swift              TransportMode, TicketProduct, TicketPeriod, TripRecord, Station, FederalState …
  FareModel.swift           Distanz-Tarif (ÖBB-Standardticket-Näherung), CityFare, EmissionFactors, TariffCatalog
  FareEstimator.swift       Preis-Schätzung einer Fahrt → FareEstimate (Preis, km, Erklärung)
  SavingsCalculator.swift   SavingsSummary (Amortisation, Break-even, Prognose), Kurven-Serien
  Statistics.swift          Monats-/Verkehrsmittel-/Wochentags-/Tages-Statistik, Top-Strecken, Rekorde
  Achievements.swift        Erfolge (rein aus Daten abgeleitet)
  TicketComparator.swift    „Was wäre wenn“ – welches Ticket wäre am günstigsten?
  Updates.swift             SemanticVersion, UpdateManifest, UpdateDecision
  CSVExport.swift           CSV-Export (Excel-AT kompatibel)
  StationIndex.swift        Suche über stations.json; Fassade über PlaceIndex nach attach(places:)
  Places/                   Orte-Suche wie Scotty (docs/PLACES.md): PlaceIndex (offline, ~40k Haltestellen + 21k Orte),
                            PlaceNormalizer, Ranking, LocMatch-Decoder + Merge, PlaceIndexLoader (lazy, Hintergrund)
Packages/KlimaCloud/        Cloud-Client ohne UI (nur Foundation, unter Linux & macOS testbar): HTTP-Client,
                            Sitzung/Refresh, DTOs, Merge-Regel, PKCE, Zeitstempel (docs/CLOUDFLARE_BACKEND.md §6)
Shared/                     In App UND Widget kompiliert
  Models.swift              SwiftData-Modelle: TicketEntity, TripEntity, FavoriteRouteEntity + DataSchema
  AppGroup.swift            App-Group-ID (inkl. AltStore/SideStore-Umschreibung)
  WidgetSnapshot.swift      Kompakte Zusammenfassung für Widgets (App-Group-UserDefaults)
  QuickLog.swift            Warteschlange für Schnellerfassung aus Widgets/Siri
  Intents.swift             App Intents (Lieblingsfahrt erfassen, Fahrt erfassen, Bilanz anzeigen)
App/Sources/
  KlimaBilanzApp.swift      @main, ModelContainer, Screenshot-Modus
  Core/                     AppState (Services + Navigation), AppSettings, RootView, MainTabView,
                            ScreenshotRouter, Format (de-AT Formatierung), Shortcuts (Siri)
  Data/                     Analytics (AnalyticsSnapshot), Repository (alle Schreibzugriffe), DemoData
  Services/                 AuthService, SyncService, KeychainStore, UpdateService, TariffService,
                            NotificationService, LocationService
  DesignSystem/             Theme (Tokens), Komponenten, Hintergründe, Haptik
  Features/<Feature>/       Onboarding, Dashboard, Trips, Statistics, Ticket, Achievements, Settings, Updates, Account, Widgets
App/Resources/              Assets, stations.json (legacy ids), places.bin + localities.bin (all stops/places,
                            docs/PLACES.md), tariffs.json, AppConfig.json
Widgets/Sources/            WidgetKit-Extension
backend/                    Cloud-Backend: Cloudflare Worker (TypeScript) + D1-Schema (migrations/), Tests, Deploy-Skripte
scripts/                    CI-Hilfsskripte, Tarif-Katalog-Generator, build_places.py (Haltestellen/Orte,
                            docs/DATA_SOURCES.md), places_reference.py (Python-Referenz + Goldens der Suche)
.github/workflows/          ios.yml (App, Releases), backend.yml (Worker testen + bereitstellen)
```

## Regeln für den App-Code

- **Lesen** über `@Query` (immer `deletedAt == nil` filtern), **schreiben** ausschließlich über
  `Repository(context:app:)` – speichert, aktualisiert Widgets, plant Erinnerungen, stößt Sync an.
- Berechnungen nie in Views duplizieren: `Analytics.make(ticket:trips:catalog:)` liefert alles
  (Summary, Kurven, Statistiken, Erfolge). Aktives Ticket: `Analytics.activeTicket(in:selectedID:)`.
- Globale Navigation über `AppState`: `selectedTab`, `presentAddTrip(_:)`, `showToast(...)`,
  `isShowingSettings`, `isShowingAchievements`, `celebrateBreakEven`.
- Formatierung immer über `Format.*` (de-AT: „€ 1.400“, „4.812 km“, „14. Dez.“).
- Design immer über `Theme.*` Tokens und DesignSystem-Komponenten – keine Ad-hoc-Farben.
- Persistierte Enums als Raw-Strings (SwiftData-Predicates unterstützen keine Enums).
- Deutsch (Österreich), Du-Form. „Jänner“, „Öffis“, „Bim“.

## Screenshot-Modus (CI)

`-KBScreenshot <screen> -KBDemo YES` startet mit In-Memory-Store und Demo-Daten.
Screens: `onboarding dashboard trips addTrip tripDetail stats ticket achievements settings update widgets`.
CI lädt die PNGs (hell/dunkel) als Artefakt `screenshots-<build>` des Laufs hoch (README.md darin nennt Version und Commit); einen Screenshots-Branch gibt es nicht mehr.

## Diagnose & Performance

- **Diagnose auf dem iPhone** (`App/Sources/Services/Diagnostics/`, nur lokal, nichts wird gesendet):
  `DiagnosticsService` abonniert MetricKit (Absturz-, Hänger-, CPU-/Schreib-, Start-Berichte + Tagesmetriken, JSON in
  `Application Support/Diagnostics/payloads`, 30 Tage, max. 6 MB), ein Watchdog pingt alle 0,5 s den Main-Thread und
  protokolliert jeden Hänger > 250 ms mit dem sichtbaren Bildschirm, ein Breadcrumb-Ring (Tabs, globale Sheets,
  Speichern, Lebenszyklus) überlebt Abstürze, eine Sitzung, die im Vordergrund ohne sauberes Ende abbricht, wird beim
  nächsten Start gemeldet. `Diagnostics.measure("Name") { … }` misst Hot Paths (Signpost + Ø/max je Sitzung), z. B.
  `Analytics.make`, `Widgets.refresh`, `Repository.save`.
- **Export:** Einstellungen › Über KlimaBilanz › *Diagnose & Stabilität* › „Diagnosedatei teilen“ (JSON: Ereignisse,
  Sitzungen, Breadcrumbs, MetricKit-Rohdaten, Gerät/iOS, nur Anzahl der Fahrten). Symbolisieren mit dem dSYM-Artefakt
  des Builds (`dSYM-<version>-<build>`): `atos -arch arm64 -o KlimaBilanz.app.dSYM/Contents/Resources/DWARF/KlimaBilanz
  -l 0x100000000 <0x100000000 + offset>` für „KlimaBilanz +0x…“-Frames.
- **Performance-Tests in CI:** `[perf]` in der Commit-Nachricht (oder *Run workflow* mit `perf`) startet den Job
  `perf`: XCUITest-Target `KlimaBilanzPerfTests` (Schema `KlimaBilanzPerf`, Release) im Simulator mit
  `-KBPerf YES -KBDemo YES` (normale Tabs, Demo-Jahr im Speicher, keine „Rentiert!“-Feier, `-KBPerfTrips 1500` für
  viele Daten). Die Tests finden die Scrollbereiche über Accessibility-IDs (`perf.scroll.overview|trips|stats|ticket|
  gipfelbuch`, `// MARK: perf` in den Screens) und wischen auf festen Koordinaten. Weil der Simulator XCTest keine
  Hitch-Metriken liefert, misst die App im Perf-Modus selbst (`PerfFrameMonitor`): Hitch Time Ratio je Bildschirm
  beim Scrollen (KVO auf `contentOffset` + `CADisplayLink`), Bildschirmwechsel (Auswahl → erstes Bild), Start
  (App.init → erstes Bild, dann 4 s Frames), Speicher (phys_footprint) → `Diagnostics/perf-*.json`; dazu
  LaunchTrace-Marken und der Hänger-Watchdog. Danach nimmt `scripts/perf_profile.sh` je Bildschirm eine Time-Profiler-
  Aufnahme der app-eigenen Tour auf (`-KBPerfTour <screen>`: öffnen, mit 2 400 pt/s scrollen, beenden; Phasen als
  Signposts) und `scripts/perf_profile.py` nennt die Hauptthread-Hotspots. Alles → `$GITHUB_STEP_SUMMARY` und Artefakt
  `perf-<run>` (`perf-summary.md/.json` = Baseline, `scripts/perf_summary.py`).

## Updates

1. **App-Updates:** CI veröffentlicht bei jedem Tag `v*` eine Release mit `.ipa`, `update.json`
   und `altstore-source.json`. Die App prüft `update.json` (URL in `AppConfig.json`) automatisch und
   zeigt ein Update-Sheet; über AltStore/SideStore-Quelle aktualisiert sich die App im Hintergrund.
2. **Tarif-Updates:** `tariffs.json` (Preise, Tarifmodell) wird automatisch nachgeladen, wenn eine
   neuere Version online liegt – ohne App-Update.

## Login & Sync

Eigenes Backend im Cloudflare-Konto des Betreibers (Vertrag: [CLOUDFLARE_BACKEND.md](CLOUDFLARE_BACKEND.md),
Einrichtung: [SETUP.md §3](SETUP.md)): ein Worker `klimabilanz-api` (TypeScript, ohne Laufzeit-Abhängigkeiten,
nur WebCrypto) und die D1-Datenbank `klimabilanz` mit **EU-Jurisdiktion**. `backend.yml` testet jeden Push und stellt
von `main` bzw. per *Run workflow* bereit (D1 anlegen, migrieren, Secrets, Deploy);
ohne Cloudflare-Secrets wird nichts bereitgestellt. Der iOS-Build trägt die Worker-Adresse als `apiBaseURL` in
`AppConfig.json` ein – ohne Adresse funktioniert die App vollständig lokal (Apple-Login lokal möglich).

- **Anmeldung:** Die App öffnet `/v1/auth/{google|microsoft|apple}/start` in `ASWebAuthenticationSession`
  (Autorisierungscode + PKCE, Rückkehr über `klimabilanz://auth-callback`); der Worker spricht OIDC mit dem Anbieter
  (state, nonce, JWKS-Prüfung) und gibt der App eigene Tokens: Access-Token (JWT, 15 min, bei jeder Anfrage gegen die
  Sitzung geprüft) und rotierendes Refresh-Token (60 Tage gleitend, Wiederverwendung sperrt die Sitzung). Signierte
  Builds nutzen den nativen Apple-Login (`/v1/auth/apple/native`). Konten hängen an (Anbieter, Anbieter-ID), nie
  automatisch an der E-Mail. `/v1/config` meldet, welche Anbieter eingerichtet sind; die App blendet nur diese ein.
- **Sync** (`SyncService` + `KlimaCloud`, `/v1/sync/push` und `/v1/sync/pull`): Pull-Cursor ist die vom Server
  vergebene `server_rev` (globaler Zähler, pro Tabelle und Konto, Seiten zu 500), nie die Geräteuhr; der Server
  verwirft veraltete Schreibzugriffe (neueste `updated_at` gewinnt), überspringt Echos und kappt Uhren, die mehr als
  10 Minuten vorgehen. Löschen ist immer weich (`deleted_at`). Lokale Daten gehören dem zuletzt synchronisierten
  Konto – bei einem anderen Konto pausiert der Sync (`pendingAccountSwitch`).
- **Abmelden** wirkt nur auf diesem Gerät; **Konto löschen** (`/v1/account/delete`) entfernt alle Zeilen des Kontos
  in einem Schritt, beendet alle Sitzungen sofort und widerruft das Apple-Token.

Die frühere Supabase-Variante (PostgREST, Row Level Security, Edge Function) ist entfernt und nur noch in der
Git-Historie (bis `0cb2acd`).
