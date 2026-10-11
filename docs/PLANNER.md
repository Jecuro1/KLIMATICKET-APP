# Fahrplan (live planner) – app side

The ÖBB live planner inside KlimaBilanz: connections with realtime, departure boards, live regular prices, KlimaTicket
coverage, and „Fahrt erfassen“ in one tap. The pure logic (HAFAS client, prices, coverage, presentation) lives in
KlimaCore (`Live/**`, spec: `docs/OEBB_LIVE.md`); this document is the **app layer**.

## 1. Consent and kill switch (nothing leaves the phone without it)

`LiveDataService` (`App/Sources/Services/Live/`) is the only door to the live layer.

| Layer | What it does |
|---|---|
| `timetable` / `priceProvider` | `nil` unless consent is granted, the feature switch is on, the remote config does not kill it and the device is online. Every planner call goes through them. |
| effective config | The clients only see a config in which every provider is switched off while consent is undecided/declined, a feature is off or `killSwitch` is set – they throw `LiveError.disabled` before any I/O. |
| remote config | Cached in Application Support (`live-config.json`), refreshed at most every 12 h **only while consent is granted**, from `UpdateManifest.liveConfigURL` or the build's `liveConfigURL` (default: `data/live_config.json` on `main`). Higher `version` wins; intervals are clamped, never loosened. |

Kill switch: commit `data/live_config.json` with `"killSwitch": true` and a higher `version` – all live surfaces switch off
on the next refresh and say so („Fahrplan vorübergehend aus“).
`-KBDemo` / screenshot / perf runs use `DemoTimetableService` + `DemoPriceProvider`: the network is never touched.

Settings › Live-Daten (`SetLiveDataSection`): consent toggle, the two feature switches, health per provider, „Verbindung
testen“, „Live-Cache leeren“. First visit: `LiveConsentCard` (also inline in the trip editor's price card).

## 2. Screens (`App/Sources/Features/Planner/`, `DesignSystem/Planner/`)

| File | |
|---|---|
| `PlannerModel` | search form, results, board, „Deine Strecken“, „In der Nähe“; retries (2/4/8 s), paging, price loading, refresh |
| `PlannerRootView` | home: search card (Von/Nach/Über ≤ 2, swap, time row), Deine Strecken, In der Nähe, Abfahrten mode |
| `PlannerSearchView` | suggestions: offline station index first, live Scotty places merged after 250 ms |
| `PlannerResultsView` | connection cards, Früher/Später, „Nur mit KlimaTicket gültig“, states |
| `ConnectionDetailView` + `ConnectionMapView` | timeline, map, value card with price source, „Fahrt erfassen“ |
| `DeparturesView` + `TripSheetView` | board with filters, the full run of a train |
| `PlannerOptionsSheet`, `PlannerTimeSheet` | options (stored in `planner.options`), date/time |

The tab is the iOS 26 search-role tab; `.searchable` sits on the `TabView` (`PlannerTabSearch`). If it misbehaves on a
device set `PlannerModel.navigationStyle = .plainTab` (one line) – the planner then uses its own field.
Line plates are the Wegzeichen plates (`LineBadge(line:)`), identical to the offline stop details.

Refresh cadences (visible screens only, paused in the background and in Low Power Mode): results/detail 60 s, board 30 s,
„Deine Strecken“ 60 s. Cards ask for the live price of the first three connections; the detail asks for its own.

## 3. Logging a connection

`Repository.logJourney(journey, quote:, coverage:, travelClass:, isRoundTrip:, via:)` → `JourneyLogPlanner` (KlimaCore,
tested in `JourneyLogPlanTests`):

- ride legs become „Reise mit Etappen“ (`journeyID`/`legIndex`), one ride leg a plain trip; walks are no trips;
- the quoted regular price is shared over the legs by distance (cents, exact sum);
- `.partial` coverage logs and values **only the covered segment** (cut at `lastCoveredStopName`), the price card asks for
  that segment's price;
- requested via stops land in `viaRaw` of the leg that passes them; an app station gives id, name and states;
- a price from the planner is never marked manual; manual prices are never overwritten.

## 4. Screenshots

`-KBScreenshot planner | plannerResults | plannerVia | connection | departures | plannerConsent | plannerStates | plannerOptions`
(`PlannerScreenshotScene`, demo timetable relative to „now“).

## 5. Honest labels

„Live von ÖBB“ / „Live-Preis · VVT“, „Tarif-Tabelle“, „Schätzung“, „Angepasst“, „Offline · Tarif-Tabelle“
(`PriceSourceBadge`). Footer: „Daten: ÖBB-Personenverkehr AG · Preise ohne Gewähr · KlimaBilanz verkauft keine Tickets“.
No ÖBB or Verbund logos, colours or fonts.
