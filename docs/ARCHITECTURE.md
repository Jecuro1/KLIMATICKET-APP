# KlimaBilanz – Architektur

Native iOS-App (SwiftUI, **iOS 26+**, Liquid Glass), gebaut mit Xcode 26 über XcodeGen (`project.yml`).
Keine Fremd-Bibliotheken – schnelle Builds, kleine App, volle Kontrolle. Installiert wird per Sideloading (kein bezahlter
Apple-Developer-Account): kein APNs, kein CloudKit, keine Wallet-Pässe, keine Watch-App, ein Widget-Extension-Target
(zwei App-IDs). Die Zahlen unten stehen nicht von Hand hier: `python3 scripts/doc_numbers.py` liest sie aus den Datendateien.

## Ordnerstruktur

```
project.yml                 XcodeGen-Spezifikation (App + Widget-Extension + lokale Pakete + Perf-Tests)
Packages/KlimaCore/         Plattformunabhängige Logik, unter Linux und macOS testbar (swift test); Sources/KlimaCore/:
  Models, FareModel, FareEstimator(+Via), SavingsCalculator, Statistics, CategoryStats, Achievements, TicketComparator,
  TicketAdvisor, CarComparison, WorkTax, Perks, TripJourney, TripVia, CSVExport/CSVImport, Updates, EuroInput, DayMemo,
  RideTracking, Atlas (Kartenlogik), RelationPrices, StationIndex (Fassade über PlaceIndex)
  Places/                   Orte-Suche wie Scotty (docs/PLACES.md): PlaceIndex (offline), Normalizer, Ranking, Merge der
                            drei Datenebenen, Facilities (Ausstattung), Enrichment, Format, Presentation
  Live/                     Fahrplan, Radar, Zugsuche, Verfolgen (docs/OEBB_LIVE.md): HAFAS (Client, Codec), Transport
                            (RequestThrottle, Gesundheit, URLSessionTransport), Config, Domain, Presentation, Pricing
                            (Live-Preis, Shop, Budget), Coverage (Deckt das KlimaTicket die Fahrt?), Planner, Radar,
                            Map (Kartenebenen), TrainSearch, Follow, Disruptions, Logging
  Alarms/ Routes/ Widgets/  Alarm-Arten und Meldungsverlauf, gespeicherte Strecken, Widget-Cache und Zeitplan
  Tariff/                   Tarifstand: Fahrplanwechsel, Frische, Relationspaket (Download, Prüfung)
  TicketRights/             Fahrgastrechte: Widerspruchs- und Kündigungsbrief, Ratenplan, Fristen
  WhatIf/ YearReview/       „Was wäre wenn?“ und der Jahresrückblick (Seiten, Zeiträume, Referenzstrecken)
  Assistant/ Logos/         Logik der KI auf dem Gerät (Abfrage-Validierung, Erklärung), Logo-Paket-Format
Packages/KlimaCloud/        Cloud-Client ohne UI (nur Foundation, unter Linux und macOS testbar): HTTP-Client,
                            Sitzung/Refresh, DTOs, Merge-Regel, PKCE, Zeitstempel (docs/CLOUDFLARE_BACKEND.md §6)
Shared/                     In App UND Widget-Extension kompiliert – nie ein Netzaufruf (check_integration.py)
  Models.swift              SwiftData-Modelle: TicketEntity, TripEntity, FavoriteRouteEntity + DataSchema
  Theme.swift, Motion/      Design-Tokens und Motion-Tokens (die einzige Quelle für Farben, Abstände, Animation)
  Wegzeichen/               Linien-Schilder, Ortsmarken, Bundesländer-Zeichen (eigene Glyphen, keine Markenlogos)
  WidgetViews/              Alle Widget-Ansichten (auch von der Widget-Galerie der App genutzt)
  AppGroup, WidgetSnapshot, WidgetCache, QuickLog, Intents, WidgetIntents, RideActivity*, FollowActivityAttributes
App/Sources/
  KlimaBilanzApp.swift      @main, ModelContainer, Start-Modi (Screenshot, Perf)
  Core/                     AppState (Dienste + Navigation), AppSettings, AppConfig (LaunchMode), RootView (inkl.
                            ScreenshotRouter, Deep Links, MainTabView), Format (de-AT), Copy, Shortcuts, LaunchTrace
  Data/                     Analytics (AnalyticsSnapshot), Repository (alle Schreibzugriffe), CommitEffects, DemoData,
                            Backup, StoreLoader
  Services/                 Auth, Sync, Keychain, Update, Tarif, Benachrichtigungen, Standort, Fahrterkennung, manueller
                            Update-Download; Unterordner Live/ (LiveDataService: Einwilligung, Drosselung, Verfolgen im
                            Hintergrund), Tariff/ (Relationspaket), Widgets/ (WidgetCacheSync), AI/ (Assistent),
                            Diagnostics/ (Diagnose, Watchdog, Perf-Messung)
  DesignSystem/             Komponenten (Hero, Ticketkarte, Gipfel-Diagramm, Hintergründe), Motion/ (MotionPolicy, Reveal,
                            Zoom-Übergänge, Haptik), Planner/ (Verbindungskarte, Abfahrtszeile, Zeitleiste), Places/,
                            Pricing/, Logos/
  Features/<Feature>/       siehe „Tabs und Bildschirme“
App/Resources/              Assets, stations.json (alte IDs, eingefroren), places.bin + stops_osm.bin + localities.bin
                            (Haltestellen und Orte, docs/PLACES.md), relations.bin + relations-points.json (ÖBB-Preise),
                            tariffs.json, benefits.json, coverage_rules.json, AppConfig.json
Widgets/Sources/            WidgetKit-Extension: Widgets, Bedienelemente, Live Activities (liest nur den Cache)
PerfTests/                  XCUITest-Ziel KlimaBilanzPerfTests (Start, Scroll-Hitches, Tab-Runde, Feature-Bildschirme)
backend/                    Cloudflare Worker (TypeScript) + D1-Schema (migrations/), Tests, Deploy-Skripte
data/                       Rohdaten und Berichte der Daten-Pipelines (Relationspreise, Tarifmodell, live_config.json, …)
scripts/                    CI-Hilfsskripte mit Python-Tests (test_*.py), Daten-Generatoren (build_places.py, build_tariffs.py,
                            build_relations.py), check_integration.py, doc_numbers.py, Perf-Auswertung
tools/                      typecheck/ (Linux-Typprüfung der App), check_no_brand_logos.py
.github/workflows/          ios.yml (App, Screenshots, Perf, Releases), backend.yml (Worker), register-device.yml
```

## Tabs und Bildschirme

Fünf Tabs (`AppTab`, `MainTabView` in `Core/RootView.swift`); der letzte ist der Fahrplan mit der Rolle „Suche“ von iOS 26.

| Tab | Wurzel | Was darin liegt |
|---|---|---|
| Übersicht | `Features/Dashboard/` | Amortisations-Hero, Schnellerfassung, Hinweise, Vorteile-Karte (`Benefits/`), gleitende Einstiege in Gipfelbuch (`Achievements/`) und Einstellungen (Sheet) |
| Fahrten | `Features/Trips/` | Liste, Fahrt erfassen/bearbeiten (Editor mit Via-Halten, Kategorien), Fahrtdetail, Lieblingsfahrten |
| Statistik | `Features/Statistics/` | Verlauf, Monats-/Verkehrsmittel-/Wochentagskarten, Rekorde, Öffis-vs.-Auto-Karte (`Work/`), „Dein Jahr“ (`YearReview/`), Karte (`Map/`), Bericht und PDF (`Reports/`) |
| Ticket | `Features/Ticket/` | Ticketkarte, Gültigkeit, Ticketberater (`Advisor/`) mit „Was wäre wenn?“ (`WhatIf/`), Tarifstand-Hinweis, Fahrgastrechte und Briefe (`TicketRights/`), Vorteile (`Benefits/`) |
| Fahrplan | `Features/Planner/` | Verbindungssuche, Abfahrtstafel, Ergebnisse und Detail, Live verfolgen, Zugsuche (`Planner/TrainSearch/`) |

Vom Fahrplan aus erreichbar: **Zug-Radar** (`Features/Radar/`, Vollbild, MapKit mit eigener Zuglage, Kartenebenen für Stationen,
Störungen und gespeicherte Routen), **Störungen** (`Disruptions/`), **Meine Routen** (`Routes/`), **Haltestellen-Detail**
(`Stops/`, Ausstattung, Linien, Abfahrten), „Live verfolgen“ samt Live Activity (`LiveActivity/`). **Alarme** (`Alarms/`) liegen in
den Einstellungen und sammeln Mitteilungen, Erinnerungen und Verfolgungen mit Verlauf. **Einstellungen** (`Settings/`) hat Konto (Anmelde-Buttons in `Account/`),
Live-Daten (Einwilligung), Tarif, Widgets (`Widgets/` = Galerie), KI (`Assistant/`), Auto/Arbeit (`Work/`), App-Symbol
(`AppIcon/`), Updates (`Updates/`, manuell oder per Sheet), Diagnose. `Onboarding/` richtet beim ersten Start das Ticket ein.

Live-Daten (Fahrplan, Radar, Zugsuche, Verfolgen, Preise, Widget-Cache) gibt es nur mit der Einwilligung aus den Einstellungen,
im Vordergrund und über die `RequestThrottle` (40 Anfragen pro Minute, ehrlicher User-Agent; `docs/OEBB_LIVE.md` §2).
Widgets machen nie einen Netzaufruf: Die App schreibt den Cache in die App Group, die Widgets lesen ihn (`docs/WIDGETS.md`).

## Daten und Zahlen

Aus den Datendateien gelesen (`python3 scripts/doc_numbers.py`, Stand dieses Commits): 39.711 Haltestellen (`places.bin`) und 21.050 Orte (`localities.bin`, OSM, ODbL); 1.487 alte Stationen in `stations.json` (eingefroren, jede ID ist in `places.bin` als `legacy`-ID hinterlegt); 29.883 ÖBB-Relationspreise von 33 Ausgangsorten (Tarif ab 14.12.2025); 80 KlimaTicket-Produkte in `tariffs.json`; 17 Abzeichen im Gipfelbuch.

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

`-KBScreenshot <screen> -KBDemo YES` startet mit In-Memory-Store und Demo-Daten, ohne Netz. Welche Bildschirme es gibt, steht
im `ScreenshotRouter` (`Core/RootView.swift`): ein `case` pro Bildschirm, größere Gruppen als `<Name>ScreenshotHost` mit
`static let screens: Set<String>` im jeweiligen Feature-Ordner. Aufgenommen wird hell und dunkel; `[shots:a,b]` in der
Commit-Nachricht oder der Eingabe `screens` eines manuellen Laufs begrenzt die Liste. CI lädt die PNGs als Artefakt
`screenshots-<build>` des Laufs hoch (README.md darin nennt Version und Commit); einen Screenshots-Branch gibt es nicht mehr.
`LaunchTrace` schreibt zu jedem Start Marken und Hauptthread-Stalls nach `launch-trace.txt`;
`scripts/launch_trace_summary.py` macht daraus die Zusammenfassung des Laufs und warnt vor Starts ohne Lebenszeichen.

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
  LaunchTrace-Marken und der Hänger-Watchdog. Vor den Tests profiliert `scripts/perf_profile.sh` je Bildschirm die
  app-eigene Tour (`-KBPerfTour <screen> -KBPerfTourGate YES`: öffnen, mit 2 400 pt/s scrollen; jede Phase wartet auf
  eine Go-Datei) mit `/usr/bin/sample` (1 ms), `scripts/perf_profile.py` nennt die Hauptthread-Hotspots je Phase
  (xctrace war im CI-Simulator unbrauchbar: `--launch` mehrdeutig, Aufnahmen endeten nicht). Alles →
  `$GITHUB_STEP_SUMMARY` und Artefakt `perf-<run>` (`perf-summary.md/.json` = Baseline, `scripts/perf_summary.py`).
  Die Bildschirme hinter dem Scotty-Ersatz (Fahrplan, Verbindungen, Verbindungsdetail, Zug-Radar, Karte mit Ebenen, Atlas,
  Meine Routen, Haltestelle) öffnet die App selbst (`-KBPerfPresent <name>`, `PerfFeature` in `PerfFeatureScreens.swift`, nur
  Demo-Daten und Demo-Fahrplan, kein ÖBB-Zugriff; `FeaturePerfTests` wischen über das Fenster, Karten-Drags sieht ein
  passiver Pan-Beobachter des Monitors). Zahlen, Messgröße und Bewertungsband: [PERF_BASELINE.md](PERF_BASELINE.md);
  zwei Läufe nebeneinander: `python3 scripts/perf_compare.py <vorher>.json <nachher>.json`.

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
