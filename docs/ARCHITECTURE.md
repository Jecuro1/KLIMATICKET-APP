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
  Services/                 AuthService, SupabaseClient, SyncService, UpdateService, TariffService,
                            NotificationService, LocationService
  DesignSystem/             Theme (Tokens), Komponenten, Hintergründe, Haptik
  Features/<Feature>/       Onboarding, Dashboard, Trips, Statistics, Ticket, Achievements, Settings, Updates, Account, Widgets
App/Resources/              Assets, stations.json, tariffs.json, AppConfig.json
Widgets/Sources/            WidgetKit-Extension
supabase/migrations/        Cloud-Schema mit Row Level Security
scripts/                    CI-Hilfsskripte, Tarif-Katalog-Generator
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
CI legt die PNGs (hell/dunkel) im Branch `screenshots` ab.

## Updates

1. **App-Updates:** CI veröffentlicht bei jedem Tag `v*` eine Release mit `.ipa`, `update.json`
   und `altstore-source.json`. Die App prüft `update.json` (URL in `AppConfig.json`) automatisch und
   zeigt ein Update-Sheet; über AltStore/SideStore-Quelle aktualisiert sich die App im Hintergrund.
2. **Tarif-Updates:** `tariffs.json` (Preise, Tarifmodell) wird automatisch nachgeladen, wenn eine
   neuere Version online liegt – ohne App-Update.

## Login & Sync

Apple (nativ, ID-Token), Google und Microsoft (PKCE-Webflow) über Supabase Auth; Sync über PostgREST mit
Last-Writer-Wins auf `updated_at` und Soft-Deletes. Ohne Supabase-Konfiguration funktioniert die App
vollständig lokal (Apple-Login lokal möglich).

Details (`SyncService`, `supabase/migrations/0002_sync_hardening.sql`): Pull-Cursor ist die vom Server vergebene
`server_rev` (pro Tabelle und Konto, Keyset-Seiten zu 500), nie die Geräteuhr; der Server-Trigger verwirft veraltete
Schreibzugriffe und kappt Uhren, die mehr als 10 Minuten vorgehen. Lokale Daten gehören dem zuletzt synchronisierten
Konto – bei einem anderen Konto pausiert der Sync (`pendingAccountSwitch`). Abmelden wirkt nur auf diesem Gerät,
Kontolöschung läuft über die Edge Function `supabase/functions/delete-account`.
