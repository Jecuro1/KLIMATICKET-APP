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

`-KBScreenshot planner | plannerResults | plannerVia | connection | departures | plannerConsent | plannerStates | plannerOptions | plannerSearch | plannerAdvanced | plannerDetail | plannerSort | plannerViaEdit | plannerShare`
(`PlannerScreenshotScene`, demo timetable relative to „now“, no network).

## 5. Honest labels

„Live von ÖBB“ / „Live-Preis · VVT“, „Tarif-Tabelle“, „Schätzung“, „Angepasst“, „Offline · Tarif-Tabelle“
(`PriceSourceBadge`). Footer: „Daten: ÖBB-Personenverkehr AG · Preise ohne Gewähr · KlimaBilanz verkauft keine Tickets“.
No ÖBB or Verbund logos, colours or fonts.

## 6. Result list: sorting, walking, paging

- Sort chips above the list (`ConnectionSort`, KlimaCore `Live/Planner/ConnectionSorting.swift`): **Abfahrt** (default, the
  timetable), **Schnellste**, **Wenig Umstiege**, **Günstigste**, **Wenig CO₂**. A sort only re-orders the rows; it never
  sends a request. The choice is kept in `planner.sort`.
- Each sort says what it uses under the list. „Günstigste“ sorts by the regular fare the card shows (live quote or tariff
  table), not by the amount after the KlimaTicket. Connections without a price go to the end.
- „Wenig CO₂“ uses `PlannerEmissions` (Umweltbundesamt factors in `EmissionFactors.fallback`, per ride leg). The card shows
  it as „≈ x kg CO₂“, always as an estimate. A connection whose legs have no coordinates has no CO₂ figure and sorts last.
- Walking: the card shows the metres on foot. „Max. Fußweg“ (300 m, 500 m, 1 km, 2 km) filters after the search, because the
  timetable request has no such option. Walks without a distance count as 0 m. The list says how many connections it hid.
- „Früher“ / „Später“ pages merge through `PlannerResults.merge` (dedupe by id, departure order). The next page is only
  requested near the end of the departure order, not when a different sort is shown.

## 7. Options: price class, Vorteilscard

- „Klasse“ (Wie Einstellungen / 2. / 1. Klasse) and „Mit Vorteilscard“ override the settings for the prices in the search
  (`PriceRequest.travelClass` / `discount`). The same values are used when a connection is logged.
- The sheet sections are: Verkehrsmittel, Fußweg und Preis, Umstiege, Komfort. Changing them searches again when the sheet
  closes, as before.

## 8. Via stops and deep links

- Via stops can be reordered (up/down buttons next to each „über“ row, two or more stops). A new order searches again.
- `klimabilanz://plan?from=…&to=…&via=…&at=<ISO 8601>&arr=0|1` (`PlannerLink`, KlimaCore): stations as `uic:<id>`, other
  places by name, at most two `via`. Round trip and parsing are tested (`PlannerLogicTests`).

## 9. Connection detail: Teilen, Erinnerung, Favorit, Planen

- **Teilen** (toolbar) opens `PlannerShareSheet`: the text (`PlannerExport.shareText`, e.g. „Innsbruck Hbf → Landeck-Zams ·
  Do, 15. Okt., 08:12–09:30 · 1 Umstieg · RJX 19910“), „Text teilen“, „Link teilen“ and „Link kopieren“. The link opens the
  search in KlimaBilanz; it does not send anything.
- **Kalender** (toolbar): the `.ics` file from `PlannerExport.ics` (RFC 5545, CRLF, folded at 75 octets, UTC times) with a
  display alarm 10 min before the departure.
- **Erinnerung** (Planen card): 5, 10, 15 or 30 min before the planned departure. A local notification (`PlannerReminders`,
  `UNTimeIntervalNotificationTrigger`), no background request and no network. A reminder for a departure that is already
  too near is refused; the state shows „Gesetzt für …“ and can be removed.
- **Als Favorit speichern**: every ride leg becomes one leg of a Kombi-Vorlage (`Repository.addFavorite(fromPlan:mode:)`,
  `JourneyLegCodec`, as the trip favourites). A single leg is a plain favourite. Prices and distances come from the log plan.
- **Zwischenhalt hinzufügen** (up to two) leaves the detail and opens the search for the stop; **Früher suchen** (one hour
  earlier) and **Später suchen** (one minute later) search again from the departure of this connection.

## 10. Siri and Shortcuts

`PlanConnectionIntent` („Nächste Verbindung“, `App/Sources/Features/Planner/PlannerIntents.swift`): parameters „Nach“ (a
station of the offline index, `PlannerPlaceEntity`, searchable) and optional „Von“ (default: the start station). It answers
with a dialog and a snippet (route, departure, arrival, changes, lines) for the next connection departing now. Phrases:
„Nächste Verbindung nach … in KlimaBilanz“, „Verbindung nach … in KlimaBilanz“. It needs the live data (consent, switch and
kill switch are checked by `LiveDataService.timetable`); without them it says so and sends nothing.

Limit: App Shortcut phrases take one parameter, so the phrase „Verbindung von X nach Y“ is available as a Shortcuts action with
both parameters, not as a spoken phrase with two stations.

## 11. Not built, and why

- **Widget „Nächste Verbindung“**: a widget needs live data in the background (refresh of the timetable). OEBB_LIVE §2.3
  allows no background requests except an active „Live verfolgen“ journey. A widget that shows only the last connection
  from the device cache is possible; it is the next step if the owner wants it.
- **Wagenreihung**: not in the ÖBB responses that were checked (OEBB_LIVE §R6, „NO DATA“). Nothing is shown without data.
- **Leg-level „Fahrt erfassen“** (choose the legs to log): not built in this round. The price of a partly logged connection
  would need its own distance share of the quote and a coverage rule for the cut; both need a device check first.
- **Push alerts for delays**: no server and no background polling in the spec; only the local reminder above.

