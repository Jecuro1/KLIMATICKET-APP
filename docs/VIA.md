# Via stops („Über …", Zwischenhalte)

Trips and favourite routes carry up to **two** via stations in travel order (owner request 2026-10-09, same limit as the
live planner's `JourneyQuery.maxViaStops`). Extend this – don't build a second via model.

## 1. Data shape

| Where | Field | Notes |
|---|---|---|
| KlimaCore | `TripVia { name, stationID? }`, `TripVia.maxCount` (= 2) | `TripVia.swift`; `TripRecord.via`, `RideTrip.via` |
| SwiftData | `TripEntity.viaRaw`, `FavoriteRouteEntity.viaRaw` (`String = ""`) | `.via` accessors; additive → lightweight migration, old stores open unchanged |
| Encoding | `TripViaCodec` | one `"<stationID>\t<name>"` line per via, `"\tLech"` without a station, `""` = direct. Decoders read fields 0–1 and ignore more (room for e.g. a dwell time), drop empty names, cap at 2, merge a stop listed twice in a row |
| Editor | `TripEditorModel.vias: [TripEdViaStop]`, `viaRecords`, `viaStations` | `TripEdViaRows.swift`; `TripDraft.via` prefills |

Everything that copies a route copies `viaRaw`: `repeatTrip`, `addFavorite(from:)` / `metaAddFavorite`,
`FavoriteRouteEntity.makeTrip` (quick logs from widgets, Siri, Control Center, Live Activity rides started from a
favourite), rides from the editor (`RideTrip.via`). The editor's swap reverses the vias; a round trip's return leg passes
them in reverse (shown in the detail as „Zurück über …").

## 2. Fare and distance (`FareEstimator+Via.swift`)

`estimate(from:via:to:…)` / `estimate(route:…)`:

1. **Kernzone:** one city zone holds every stop → one single ticket (changes are included).
2. **ÖBB distance tariff is degressive** → the route is priced **once on its summed tariff km**, never as the sum of
   leg tickets. A leg's tariff km come from its official relation price inverted on the fitted price curve
   (`FareModel.railKm(forFullFare:)`; nil on the flat ends: minimum and maximum fare) or, without a relation, from
   straight line × detour factor.
3. **Official table:** the A → B relation price applies only when every via lies on the default path – all legs have
   official tariff km and they add up to the direct relation's (+ 6 % + 3 km tolerance for the table's rounding).
   Explanation „über Feldkirch · am Weg · ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025".
4. Otherwise the estimate (`.distanceTariff`), „über Villach Hbf · geschätzt nach Tarif-km · 2. Kl.", never below the
   direct ticket. Class, Vorteilscard and the fare index apply as for direct trips.
5. **Distance** (CO₂, km statistics): sum of the legs' rail-km estimates, never below the direct estimate.

Examples (tests in `TripViaTests`, real prices): Innsbruck → Feldkirch → Bregenz = € 43,30 official (not 36,00 + 8,90);
Innsbruck → Villach → Graz = € 85,30 (468 tariff km; legs 62,60 + 37,90, direct 81,10).

Verbund/zone data beyond the Kernzonen is not in the tariff catalog; leaving a Kernzone prices the whole route on the
distance tariff (as direct trips do). A manual price is never touched; editing keeps a saved price until the route,
mode, class, Vorteilscard or tariff period changes (adding/removing a via counts as a route change).

## 3. Sync, backup, CSV

- **Sync:** `via` text(1000) on `trips` and `favorite_routes` (D1 migration `0002_via.sql`, schema map column kind
  **K** = absent/null keeps the stored value, so an older app's edit never wipes vias). `/v1/config` lists
  `features: ["trip_via"]`; the app sends `via` and applies pulled values only when the server lists it
  (`CloudConfig.supports(CloudFeature.tripVia)`), else a Worker without the migration would answer `422 unknown_field`.
  Inserts from the server take `via` whenever present. Known gap: rows pushed while the feature was off reach the server
  without vias until they are edited again.
- **Backup:** v2 rows carry `via` (additive; older apps ignore it, files without it keep an entity's vias).
- **CSV:** column „Über" after „Nach" („Landeck-Zams · Feldkirch"); import also reads „/", „>", „→", „|" and the
  headers Via/Zwischenhalt(e)/…; vias equal to start or destination are dropped, at most two. Files without the column
  import as before. The duplicate key includes the vias (unchanged for trips without).

## 4. Editor

`TripEdViaRows` inside `TripEdRouteCard`: „Zwischenhalt hinzufügen" between Von and the route meta (only once a start
or destination is set, gone at two vias); each via a row with a smaller dot on the route line, tap → station picker
„Über" (stations only, no free text), ✕ / left swipe / context menu / VoiceOver action „Entfernen"
(„Über Feldkirch, Zwischenhalt 1 von 2"). Motion: `Motion.smooth` rise transitions, `.decrease` haptic on removal.

## 5. Where it shows

`ViaText` / `ViaCaption` / `ViaGlyph` / `ViaRouteLabel` (`DesignSystem/ViaDisplay.swift`) – one wording: „über
Feldkirch", „über Landeck-Zams und Feldkirch".

- Fahrten list rows and `TripRow` (Übersicht, Karte): caption „über …"; search finds via names.
- Fahrt-Detail: via stops on the route rail, map polyline through the vias (dots), estimate on the via route,
  „Zurück über …" for round trips.
- Favourites (manager rows, editor chips with fallback to the via glyph, Übersicht quick-log chips), Siri/Shortcuts
  favourite subtitles (`WidgetSnapshot.Favorite.via`), VoiceOver labels.
- Live Activity: caption „über Feldkirch · Unterwegs seit 07:42" (unless a live line is shown), spoken summary.
- Jahresbericht PDF trip rows, CSV import preview (unknown vias warn and are not priced).
- Karte (Atlas): a via route is its own route, drawn as gentle arcs through the via places.
- Ratgeber: the 1st-class surcharge is priced on the via route.

Screenshot routes: `addTripVia`, `tripDetailVia` (demo data: Langen → Bregenz über Bludenz, Innsbruck → Wien über
Salzburg und Linz – both on the default path, so the demo totals are unchanged).
