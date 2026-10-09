# Orte-Suche („alle Orte wie bei Scotty“) – KlimaCore Places

Status 2026-10-09: offline layer implemented and tested on Linux (`Packages/KlimaCore/Sources/KlimaCore/Places/`).
The app UI does **not** use it yet – §3 is the integration guide for the station picker and the planner.
Design and ranking rules: [PLACES_SUGGEST_SPEC.md](PLACES_SUGGEST_SPEC.md). Data sources and licences:
[DATA_SOURCES.md](DATA_SOURCES.md).

## 1. What is in the box

| | |
|---|---|
| Data | `App/Resources/places.bin` – 39,711 stops of every Austrian operator (rail, S-Bahn, U-Bahn, tram, bus incl. Postbus and regional buses, ship, cable car/on-demand) + 118 border/foreign stations, with every line and the official tags (KBPL v2, [ENRICH_SPEC.md](ENRICH_SPEC.md) §1); `App/Resources/stops_osm.bin` – the optional ODbL layer (OSM-only lines, ski areas, lifts, POI types); `App/Resources/localities.bin` – 21,050 towns/villages/districts („Ort“) with their main stop. 2,052,688 B together |
| Offline search | prefix + token + typo (1 edit ≤ 6 letters, 2 above) matching, umlauts/ß folded both ways (Pölten = Poelten = Polten), abbreviations (Hbf/Hauptbahnhof, Bf/Bahnhof/Bhf, St./Sankt, Str./Straße, Wr., i.T., a.d., b., Ibk, Sbg, VIE …), region words that Scotty adds (NÖ, Vlbg, Bgld, Tirol, „Ort“) optional, compound split („mariahilferstr“), importance (weekday departures + modes), proximity, favourites/recents |
| Live merge | ÖBB LocMatch rows (stops, town metas, addresses, POIs) are decoded (`LocMatchDecoder`), scored with the same formula, deduplicated against offline rows (rules D0–D4) and merged with diversity caps |
| Nearby | exact k-nearest stops by grid (any radius, optional product filter); address/POI/location → best stop by walking time (`resolveStops`) |
| Legacy | every id of the old `stations.json` (1,487) resolves to its new record; `Place.stationID` keeps the old id so trips, recents, geofences and ÖBB relation prices keep working |
| Façade | `StationIndex.attach(places:)` routes the existing `StationIndex` API (search, `station(id:)`, `nearest`) through all stops |

Measured (Swift 6.3.3, Linux x86-64, one core, full dataset, release): decode + inflate of the three v2 files 0.11 s,
enrichment parse ~45 ms, index build ~0.8 s – **cold build 0.91–0.94 s** (ENRICH_SPEC AT-C8: 1.30 s); **100 typical
queries 21–23 ms in total**; per keystroke over 375 typed prefixes p50 0.14 ms, p99 0.6 ms, max 0.9 ms; nearest 9 µs;
`details(for:)` 0.33 ms. Memory: ~41 MB resident for the built v2 index (the v1 files measured the same way: ~36 MB;
`PlaceIndexBudgetTests`). Debug builds are ~11× slower (100 queries ≈ 230 ms) – the release gates run in CI („Place
search performance“ step).

## 2. API (KlimaCore)

```swift
// Loading – once, off the main thread, shared
PlaceIndexLoader.shared.preload()                         // at launch (after the first frame), .utility priority
PlaceIndexLoader.shared.current                           // PlaceIndex? – never blocks
let index = try await PlaceIndexLoader.shared.load()      // awaits the single build
PlaceIndexLoader.shared.whenReady { stations.attach(places: $0) }   // StationIndex façade

// Search
index.search(_ text: String, context: PlaceSearchContext = .planner, limit: Int = 20) -> [Place]
index.nearest(to: GeoPoint, limit: Int = 5, maxMeters: Double = 2_000, products: PlaceProducts = []) -> [(place: Place, distanceMeters: Double)]
index.popularStations(limit: 10) -> [Place]               // empty state: Wien Hbf, Westbahnhof, Salzburg Hbf, …
index.place(id:) -> Place?                                // place id or old stations.json id
index.station(id:) -> Station?                            // legacy bridge, keeps the requested id
index.resolveStops(near: GeoPoint, live: [(Place, Double)] = [], maxMeters: 1_500) -> [PlaceIndex.ResolvedStop]

// Live merge (LocMatch)
LocMatchDecoder.locMatchRequest(text)                     // svcReq body: {"meth":"LocMatch","req":{"input":{"loc":{"type":"ALL","name":"<text>?"},"maxLoc":10,"field":"S"}}}
LocMatchDecoder.places(fromResponse: Data) -> [Place]     // HAMM/service errors → []
LocMatchDecoder.nearby(fromResponse: Data) -> [(place: Place, distanceMeters: Double)]   // LocGeoPos
index.merged(offline: [Place], live: [Place], query: String, context: PlaceSearchContext = .planner, limit: Int = 20) -> [Place]
index.rankLive(_ live: [Place], query:, context:) -> [Place]          // score + plausibility filter only
index.merged(offline: [Place], live: [Place]) -> [Place]              // both lists already scored (search / rankLive)
index.isSamePlace(_:_:) -> Bool                                        // dedupe rules D0–D4
```

`PlaceSearchContext(mode: .planner | .tripLog, near: GeoPoint?, favourites: Set<String>, recents: [String: PlaceRecentUse])`
– `.tripLog` („Fahrt erfassen“) never returns towns; ids may be place ids or old station ids.

`Place` (value, `Identifiable`, `Hashable`, `Sendable`): `id`, `kind` (`.station`, `.stop`, `.town`, `.address`, `.poi`),
`name` (official), `title`/`subtitle` (row texts, German), `aliases`, `coordinate`, `products: PlaceProducts`
(HAFAS `pCls` bits; `.modes` = chips in display order, `.primaryMode: TransportMode` for icon/default mode),
`importance`, `state`/`federalState`, `municipality`, `extId`, `lid` (live), `isMeta`, `liveRank`, `poiCategory`/
`poiCategoryLabel`, `localityClass`, `mainStopID` (towns), `legacyStationIDs`, `stationID`, `station` (legacy `Station`),
`departures`, `lines: [LineRef]` (offline stops: the compact M8 set, display-sorted; towns: their main stop; live rows
`[]`), `tags: PlaceTags` (ski area, regions, types, services, lift, accessibility, KlimaTicket, Gemeinde/Bezirk),
`linesText` (the former comma string), `score`, `source` (`.offline`/`.live`/`.both`). Lines, tags, ski areas, regions and
the stop detail: `stopLines(for:)`, `compactLines(for:)`, `tags(for:)`, `details(for:)`, `skiArea(id:)`, `region(id:)`,
`line(key:)`, `stops(inSkiArea:)`, `stops(inRegion:)`, `dataInfo` – ENRICH_SPEC §2.3. The `StationIndex` façade
(`search`, `nearest`, `station(id:)`) returns `Station`s and skips lines and tags. `Station` gained `products: Int?` and
`primaryMode` (additive, Codable-compatible).

## 3. Station picker / planner integration (for the UI agents)

1. **Launch:** `PlaceIndexLoader.shared.preload()` and
   `PlaceIndexLoader.shared.whenReady { [stations = app.stations] in stations.attach(places: $0) }`. From then on the
   existing `StationPickerView` (which calls `app.stations.search/nearest/station(id:)`) already lists every stop.
   Publish readiness (`isPlaceIndexReady`) for the new picker; until ready keep using `StationIndex`.
2. **Typing (offline, every keystroke):** run `index.search(text, context: ctx, limit: 20)` off the main actor
   (e.g. in the picker's `.task(id:)` with `Task.detached(priority: .userInitiated)`); it takes < 1 ms, so no debounce
   is needed for the offline part. Show 8 rows (+ „Mehr anzeigen“ up to 20).
3. **Live (planner, and „Fahrt erfassen“ if wanted):** only with live consent and `config.isEnabled(.oebbHafas)`,
   for text ≥ 3 characters (after folding) or containing a digit: wait **250 ms** idle, cancel the previous request
   on every keystroke, one LocMatch in flight, at most **20 of the 40 HAFAS requests per minute**
   (`acquire(maxWait: 0.5)`, else skip). Send `LocMatchDecoder.locMatchRequest(text)` through the HAFAS client
   (OEBB_LIVE §A3), decode with `LocMatchDecoder.places(fromResponse:)` (or map the client's `Location`s to
   `Place(…, source: .live)` with `liveRank` = position), then
   `rows = index.merged(offline: offlineRows, live: liveRows, query: text, context: ctx)`. Drop responses for text
   that is no longer current. Errors → keep the offline rows silently.
4. **Stability rule:** when live rows arrive, rows visible ≥ 300 ms keep positions 1–3 unless the newcomer scores
   ≥ 25 points higher; at most one reorder per 500 ms; animate insertions with opacity only (spec §6.7).
5. **Empty query:** „Aktueller Standort“ (if permitted) · favourites (≤ 5) · recents (≤ 5) · `index.nearest(to:limit: 3,
   maxMeters: 1500)` with „{m} m · {min} min“ (`Place.walkSeconds(meters:)`) · `index.popularStations()`.
6. **Rows:** title `place.title`, subtitle `place.subtitle`, icon by `kind`/`products.primaryMode`
   (station `train.side.front.car`, U-Bahn `tram.fill.tunnel`, tram `tram.fill`, bus `bus.fill`, cable `cablecar.fill`,
   ship `ferry.fill`, town `mappin.and.ellipse`, address `mappin.circle.fill`, POI by `poiCategory`), mode chips
   `products.modes.map(\.displayName)`.
7. **Picking:** stops/stations → store `place.stationID` (trip) and `place.id` (recents/favourites), use `place.station`
   for `FareEstimator`; towns (planner only) → HAFAS meta via `place.lid`/`extId` if merged, else `mainStopID`;
   addresses/POIs → planner: pass `place.lid` to TripSearch unchanged; trip log: `index.resolveStops(near:
   place.coordinate, live: LocMatchDecoder.nearby(…))` and show „Ab Haltestelle {name} · {m} m · {min} min zu Fuß“.
   After a merge, offline rows carry the learnt HAFAS `extId`/`lid` – persist them in the `StationLinker` cache.
8. **Recents/favourites boost:** pass them in `PlaceSearchContext` (`favourites` +35, recents
   `25 × 0.5^(age/14) + 3 × min(uses, 5)`); they only appear when they match the text.

## 4. Decisions and deviations from PLACES_SUGGEST_SPEC

- **Live for every query ≥ 3 characters** (spec §6.1) – supersedes OEBB_LIVE §E3 („only when < 3 local hits“),
  because addresses and POIs exist only live. Needs product sign-off.
- **Optional region tokens:** a non-first query token `NÖ/OÖ/Vlbg/Bgld/Stmk/Ktn/Tirol/Ort/Ortsmitte` may stay
  unmatched at stopword cost, so HAFAS-style names („Kleinmariazell NÖ Abzw Ort“, „Lauterach in Vlbg …“) find the
  offline stop. `vlbg` is a synonym of Vorarlberg.
- **Foreign penalty (−20)** also applies to offline foreign stations (state X), as the spec table says.
- **Exact nearest:** rings grow until no closer stop can exist (the prototype stopped after ring 1).
- **Dataset fixes from spec §12:** OSM aliases are no longer in `places.bin` (fixes „Wien Blechturmgasse“ for
  `Wien Hbf`, „Museumsquartier“ for `Mariahilfer Straße`); 99 arrow markers („--->“) removed from names; curated codes
  (VIE, GRZ, LNZ, KLU, INN, SZG Hbf, Wien West, Wien Süd) added; locality class stored in `localities.bin`; all old
  station ids stored per record.
- Not yet: `PlaceSuggestService` actor (debounce/cancel/cache, spec §10.1) – needs the HAFAS client (OEBB_LIVE WP-A);
  personal index for live-only recents (addresses/POIs); serialised index cache (build is ~1 s, so not needed now).
- Known limitations: `west bahnhof` (compound typed as two words) finds Westendorf first; postcodes (`6020`) only live;
  on-demand pickup points („Sammelpunkte“) only live; 7,617 stops without a departure on the reference weekday rank low.

## 5. Tests and goldens

`swift test --package-path Packages/KlimaCore --no-parallel` (Linux CI) runs 27 place tests on the shipped
`.bin` files: normaliser golden (60 strings), 163 ranking cases (offline + merged with 43 Scotty fixtures; 48 of them
search context words, docs/ENRICH_SPEC.md §2.4), 383 typed prefixes in both modes, nearest, address/POI → stop, dedupe
pairs, C1/P1 collapses, plausibility, HAMM errors,
walking time, legacy ids, `StationIndex` façade, loader, dataset coverage, odd inputs and corrupted files, performance. The expected values come from
`scripts/places_reference.py` (Python, stdlib) – the executable reference that mirrors the Swift code 1:1 – run on
the same files; after a dataset or ranking change regenerate them (DATA_SOURCES §4) and review the diff:

```sh
SCOTTY_FIXTURES=<LocMatch fixtures> OEBB_FIXTURES=Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/OEBB/hafas \
  python3 -I scripts/places_reference.py golden App/Resources/places.bin App/Resources/localities.bin \
  Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places --osm App/Resources/stops_osm.bin
```

`--osm` loads the ODbL layer like the app does (ski-area context words need its tags).
Fixtures: `Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/` (golden JSON + trimmed LocMatch/LocGeoPos
responses, 340 KB).
