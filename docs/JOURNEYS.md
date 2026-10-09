# Reise mit Etappen (multi-leg journeys, „Kombi-Vorlage")

Bus → Zug → Bim logged as **one journey**, in travel order (owner request 2026-10-09). Every leg stays a trip of its own –
its own stations, mode, price, km, CO₂ and vias – and the legs are tied together. Extend this; don't build a second
journey model. Via stops (one mode, „über Feldkirch") are a different thing: docs/VIA.md.

## 1. Data shape

| Where | Field | Notes |
|---|---|---|
| SwiftData | `TripEntity.journeyID: UUID?`, `TripEntity.legIndex: Int = 0` | additive → lightweight migration, old stores open unchanged; nil = a trip of its own |
| KlimaCore | `TripRecord.journeyID`, `.legIndex`, `.tripKey` (= `journeyID ?? id`), `.isJourneyLeg` | `TripJourney.swift` |
| SwiftData | `FavoriteRouteEntity.legsRaw: String = ""` | „Kombi-Vorlage": `JourneyLegCodec` JSON, "" = one route |
| KlimaCore | `JourneyLeg` (`f`/`fi`/`t`/`ti`/`m`/`km`/`eur`/`v`/`s`), `JourneyLegCodec`, `JourneyLeg.maxCount` (= 6) | decoding ignores unknown keys and broken text, drops nameless legs; one leg alone is no journey |

**Legs share** date and time, „Hin & Retour", class, Mitfahrende, purpose and „Ohne KlimaTicket nicht gefahren"; the
note lives on the first leg. **Each leg keeps** start, destination, station ids, mode, price (estimated or own), km,
vias and federal states. A journey whose other legs were deleted elsewhere is simply a trip again (one leg left).

**A Kombi-Vorlage's own fields describe the whole journey** – first start, last destination, main mode
(`JourneySummary.mainMode`: most km, then highest fare), summed km and fare, union of states, `via` "". That is what
widgets, Siri, Control Center, the Übersicht quick-log chips and older apps show and log; this app logs every leg
(`FavoriteRouteEntity.makeTrips`, `Repository.logFavorite`, `ingestQuickLogs`). `valuePerLog` = what one log adds.

## 2. Statistics – what counts how

| Figure | Rule |
|---|---|
| value, km, CO₂ | sum of the legs – CO₂ per leg at its own mode's factor |
| „Fahrten" (summary, months, weekdays, days, categories, honest balance, achievements, car comparison) | a journey counts **once** (`JourneySummary.tripCount`, `JourneyCounter`) |
| `legCount` | directions of every leg (a round-trip journey of 3 legs = 6) |
| per mode (Verkehrsmittel) | per leg – the bus leg is a bus trip |
| Top-Strecken, „längste / wertvollste Fahrt" | per journey: `JourneySummary.collapsed` (start of the first leg → end of the last, transfers as vias) |
| stations, federal states | every leg |

Tests: `TripJourneyTests` (KlimaCore).

## 3. Sync, backup

- **Sync:** `journey_id` text(36) K ('') + `leg_index` int K (0) on `trips`, `legs` text(4000) K ('') on
  `favorite_routes` (D1 migration `0003_journey.sql`; K = absent/null keeps the stored value, so an older app's edit never
  drops a leg out of its journey). `/v1/config` lists `trip_journey`; the app sends the keys and applies pulled values
  only when the server lists it (`CloudConfig.supports(CloudFeature.tripJourney)`), exactly like `trip_via`. Older apps
  see every leg as a trip of its own and a Kombi-Vorlage as one route with the summed price.
- **Backup:** v2 rows carry the keys (additive; files without them keep an entity's journey).
- **CSV:** one row per leg (unchanged format).

## 4. Writes (all through `Repository`, one commit per action)

`journeyLegs(of:)` / `journeyLegs(_:)` (live legs in travel order), `saveJourney(inserting:updating:removing:)` (the
editor), `deleteTrips` / `restoreTrips` (a journey with „Rückgängig"), `repeatJourney` („Nochmal", „Duplizieren" – new
journey id), `metaAddFavorite(fromJourney:)` (Kombi-Vorlage), `logFavorite` / `undoLogFavorite` (every leg).
