# KlimaBilanz · ÖBB Live: Fahrplan, Echtzeit und Live-Ticketpreise

**Implementation spec v1 · 2026-10-09 · lead architect**

**User request (verbatim):** „Es soll auch live per ÖBB API den richtigen Ticket Preis direkt holen. Das Mann den nicht händisch eingeben muss. Inkl Live Routenplaner muss soll auch dabei sein das ich dir ÖBB App nicht mehr brauche.“

In short, the app should:
1. fetch the correct regular ticket price live, so it never has to be typed in;
2. include a live journey planner with realtime data that replaces the ÖBB app for planning and following trips.

The app does **not** sell tickets. Buying hands off to the ÖBB shop (§2).

---

## 0. How to read this document

| Tag | Meaning |
|---|---|
| **[LIVE]** | Verified against the real service on 2026-10-09. A fixture is cited. |
| **[SRC]** | Taken from documentation or source code. The source is cited. |
| **[ASSUMED]** | Not verified. The implementation must tolerate it being wrong. |
| **[DECISION]** | Architect decision. Binding for the work packages. |

### 0.1 Paths

| Abbreviation | Path |
|---|---|
| `$OEBB` | `/tmp/claude-0/-home-user-KLIMATICKET-APP/0dc47024-4f5c-5528-81fe-c86cb79aed3b/scratchpad/oebb`. This is a session scratchpad. Everything needed long term (contracts, fixtures, goldens) is copied into the repo by Step 0 (§D0). |
| `FX/` | `Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/OEBB/`. Staged in `$OEBB/repo-fixtures/` and copied into the repo by Step 0 (§D0). |
| `CORE/` | `Packages/KlimaCore/Sources/KlimaCore/` |

### 0.2 Inputs

**Research reports.** These are reproduced in the task text that commissioned this spec. Their artefacts are in:
- `$OEBB/prices/`: shop and VAO prices
- `$OEBB/journey-planner/`: HAFAS
- `$OEBB/official/`: legal and coverage rules
- `$OEBB/ux/`: UX spec and 13 mockups in `ux/mockups/*.png`

**My own verification** (10 live requests):
- Scripts: `$OEBB/arch/verify_assumptions.py`, `verify_assumptions2.py`
- Fixtures: `$OEBB/arch/fixtures/arch_*.json`, also staged into `FX/shop|vao/`

**Compile-checked interface contracts:** `$OEBB/contracts/`.
- They build together with the current KlimaCore under Swift 6.3.3 on Linux.
- The existing 24 tests and 4 contract tests pass.

**Golden expected values:** `$OEBB/repo-fixtures/golden.json`.
- Computed by the researchers' Python reference parsers.
- Generator: `$OEBB/arch/stage_fixtures.py`.

---

## 1. Summary and binding decisions

### 1.1 What we build

1. **Live journey planner, „Fahrplan“.** It covers:
   - station, address and POI search, and stops nearby;
   - connections with realtime, platforms, platform changes and disruptions;
   - paging, arrive-by, via, filters, and refresh of a chosen connection;
   - the full run of a train with stops and a map polyline;
   - live departure and arrival boards;
   - „Live verfolgen“ (in-app accessory, Live Activity hook, local notifications);
   - „Fahrt erfassen“ from any connection, with price, line, times and distance filled in automatically.

   Data source: the ÖBB Scotty HAFAS JSON API at `fahrplan.oebb.at/gate`.
2. **Live regular price, „Normalpreis“**, for every trip, without manual entry. Price chain:
   - ÖBB ticket shop live (Standard-Ticket, or a Verbund single ticket sold by ÖBB);
   - then the VAO live Verbund tariff;
   - then the offline ÖBB Relationspreise table;
   - then the city ticket or the distance model.

   The source is always shown. A price the user entered is never overwritten.
3. **KlimaTicket coverage** per connection. A rule engine over the official AGB-derived `coverage_rules.json` decides whether each leg is covered, partly covered or not covered. Only covered parts count toward the payoff.

### 1.2 Decisions

| # | Decision |
|---|---|
| D1 | **Planner back end:** ÖBB HAFAS `POST https://fahrplan.oebb.at/gate`, `ver 1.88`, `ext OEBB.14`, the current Scotty web-app profile [LIVE]. The legacy `bin/mgate.exe` 1.41 is the automatic fallback profile. Both are configurable remotely (§A3.8). |
| D2 | **Price back ends:** the ÖBB shop JSON API (anonymous) and the VAO HAFAS at `anachb.vor.at/hamm/gate`. VAO is used only for trips inside one Verkehrsverbund, 2nd class. Offline table and models are the fallback. |
| D3 | **Valuation basis = the regular single fare on the day of travel.** This is consistent with the existing table (ST VP 000) and README. Consequences: (a) advance-purchase shop prices for ÖBB-tariff tickets are replaced by the table price when the table has the relation (§B4.4); (b) **inside one Verbund the Verbund tariff is the regular price** (Handbuch B.3.1.1.2), which changes valuation for many commuter trips [LIVE: 6/6 shop = VAO ≠ table]. |
| D4 | **Navigation:** the iOS 26 search-role tab becomes „Fahrplan“. The quick-add „+“ moves to toolbars. This is UX option A, adopted. |
| D5 | **Legal posture:** unofficial interfaces are used only after **explicit one-time consent** („Live-Daten aktivieren“), at low volume, only on user action or while a screen is visible. There is a remote kill switch, no evasion of blocks, no in-app purchase and no ÖBB branding. Offline data always works. |
| D6 | **All parsing, pricing policy, coverage and view-model logic lives in KlimaCore,** pure Swift, Linux-testable with fixtures. The app target only binds and renders. |
| D7 | **Existing trips are never repriced silently.** New provenance fields are stored for new trips only. |
| D8 | **No VAO REST „Start“ key** is bundled; it is personal (contract §5.1/5.4). A user-supplied key is a follow-up (§F). |
| D9 | **Fixture-first testing.** Linux CI runs offline fixture tests only. Live tests run only with `KB_LIVE_TESTS=1`. |
| D10 | **Live Activity:** integrate by intent. We define the `LiveJourneySnapshot` value and a `RideActivityControlling` protocol. The separately built module maps them onto its own `RideActivityAttributes`. |

---

## 2. Legal and compliance guardrails (non-negotiable)

1. **Terms of use.** The ÖBB terms of use §3 forbid „verwerten“ without written permission [SRC https://www.oebb.at/de/rechtliches/nutzungsbedingungen]. The shop's `robots.txt` disallows `/api` [LIVE `$OEBB/prices/fixtures/shop_robots.txt`]. Scotty `robots.txt` disallows `/bin/` [SRC official report §2.1].
   - We therefore only make single, user-initiated queries from the user's own device.
   - We never harvest systematically. We never call these services from a server.
   - The README already states that the app is independent.
   - Before any **public** distribution (public repo or AltStore source), the owner should ask ÖBB and VAO for permission. Listed in Risks.
2. **Consent first.** Nothing is sent to ÖBB or VAO before the user taps „Live-Daten aktivieren“ (§E7). Declining keeps the app fully offline, as today.
3. **Volume budget per device.** All limits are enforced in KlimaCore (§A2.3).
   - HAFAS: at most 40 requests per minute, at least 0.3 s apart.
   - Shop: at most 12 requests per minute, at least 1 s apart.
   - VAO: at most 20 requests per minute, at least 1 s apart.
   - Nothing runs in the background except an active „Live verfolgen“ journey.
4. **Never evade blocks.**
   - On Cloudflare HTML 403 or HAFAS `AUTH`: open the circuit, show the offline fallback and wait for the remote config. No user-agent rotation, no TLS tricks, no retries.
   - The user agent is honest: `KlimaBilanz/<version> (iPhone; iOS; private, low-volume)`.
5. **Never purchase.**
   - „Im ÖBB-Ticketshop öffnen“ opens the shop link in `SFSafariViewController`. This is the HAFAS `trfRes` link, or a built link per §B3.7.
   - For WESTbahn, open `https://westbahn.at`.
6. **No ÖBB or Verbund logos, fonts or colours.** Do not use the shop's `barColor #AB0020`. Text attribution only (§E7).
7. **Privacy.**
   - Requests go straight from the iPhone to ÖBB or VAO. No account is needed. The shop creates an anonymous session.
   - Coordinates are rounded to 3 decimals before LocGeoPos (≈ 110 m).
   - Logged trips stay local unless the user syncs, as today.
   - The when-in-use location purpose string and the privacy copy are updated (§E8).

---

## 3. Architecture

```
                    ┌──────────────── App target (SwiftUI, iOS 26) ─────────────────────────────┐
 Fahrplan tab ──────┤ PlannerModel (WP-E) ─┐                    LiveJourneyTracker (WP-F)       │
 Trip editor ───────┤ TripEditorModel (WP-F)┼──> LiveDataService (WP-D, @MainActor @Observable)  │
 Settings ──────────┤ SetLiveDataSection    ┘     ├ consent, toggles, kill switch, connectivity   │
 Live Activity ◄────┤ RideActivityControlling     ├ timetable: any TimetableService ──────────┐   │
 (separate module)  └─────────────────────────────┼ prices:    LivePriceService ───────────┐ │   │
                                                   ├ coverage:  CoverageEvaluator         │ │   │
                                                   └ linker:    StationLinker             │ │   │
 ┌──────────────────────── KlimaCore (pure Swift, Linux-testable) ────────────────────────┼─┼───┘
 │ Live/Transport   HTTPTransport · URLSessionTransport · RequestThrottle · LiveHealth       │ │
 │ Live/HAFAS       HafasClient (TimetableService) · HafasCodec (raw mirrors → domain) ◄────┘ │
 │                  StationLinker (app Station ⇄ HAFAS/VAO Location)                           │
 │ Live/Pricing     LivePriceService (policy, cache) · OebbShopClient · VerbundTariffClient ◄─┘
 │                  FareEstimator.estimateLive (additive)                                     
 │ Live/Coverage    CoverageEvaluator (coverage_rules.json)                                    
 │ Live/Presentation RealtimeLabel · TransferInfo · JourneyBar · Notices · LiveJourneySnapshot
 └──────────────────────────────────────────────────────────────────────────────────────────
        │ HTTPS (device → service, never via a KlimaBilanz server)
        ├── fahrplan.oebb.at/gate (HAFAS 1.88)   [fallback bin/mgate.exe 1.41]
        ├── shop.oebbtickets.at/api/…           (anonymous token → offers)
        └── anachb.vor.at/hamm/gate (VAO 1.59)   (Verbund tariff)
```

### 3.1 Concurrency model

KlimaCore stays in Swift 5 language mode. Package tools are 6.0. Do not change the settings in `docs/SWIFTUI_IOS26_NOTES.md` §8.

| Kind | Types |
|---|---|
| `actor` | Clients with state: `HafasClient`, `OebbShopClient`, `VerbundTariffClient`, `LivePriceService`, `StationLinker`, `RequestThrottle`, `LiveHealth` |
| `Sendable` structs | Domain values |
| `@MainActor @Observable` (app) | `LiveDataService`, `PlannerModel`, `LiveJourneyTracker`, `TripEditorModel` |

- The app never passes SwiftData `@Model` objects into KlimaCore. It passes value snapshots only.

### 3.2 Linux compatibility [LIVE]

- `import FoundationNetworking` under `#if canImport(FoundationNetworking)`.
- `URLSession.shared.data(for:)` async works on Linux (Swift 6.3.3).
- `NSRegularExpression` with inline `(?i)` works on Linux.
- Probe: `$OEBB/arch-probe/`.
- SwiftPM test resources via `.copy("Fixtures")` with `Bundle.module.url(forResource: "Fixtures/OEBB/<path>", withExtension: "json")` work on Linux (dry run in `$OEBB/arch/repo-dryrun`).

---

# PART A: KlimaCore live layer (transport, HAFAS, config)

## A1. File layout (all new, under `CORE/Live/`)

```
Live/Transport/LiveTransport.swift        CONTRACT (Step 0): LiveProvider, LiveError, HTTPRequest/Response, HTTPTransport
Live/Transport/URLSessionTransport.swift  WP-A
Live/Transport/RequestThrottle.swift      WP-A  (actor; per-provider min interval + token bucket)
Live/Transport/LiveHealth.swift           WP-A  (actor; circuit breaker + status for Settings)
Live/Transport/JSONValue.swift            WP-A  (tiny Codable enum for tolerant decoding/debug; optional)
Live/Config/LiveConfig.swift              CONTRACT (Step 0)
Live/Config/LiveConfigLoader.swift        WP-A  (decode/validate remote JSON, version compare)
Live/Domain/LiveModels.swift              CONTRACT (Step 0): Location, StopEvent, Leg, Journey, Board, TimetableService …
Live/HAFAS/HafasEnvelope.swift            WP-A  (request envelope + svcReq encoders; shared with VAO)
Live/HAFAS/HafasRaw.swift                 WP-A  (Decodable raw mirrors, all fields optional)
Live/HAFAS/HafasCodec.swift               WP-A  (raw → domain: index resolution, times, platforms, polyline, remarks)
Live/HAFAS/HafasTime.swift                WP-A
Live/HAFAS/Polyline.swift                 WP-A
Live/HAFAS/HTMLText.swift                 WP-A  (HIM HTML → plain text)
Live/HAFAS/HafasClient.swift              WP-A  (actor, TimetableService)
Live/HAFAS/StationLinker.swift            WP-A  (actor; app Station ⇄ HAFAS Location, VAO lid; disk cache)
Live/Pricing/…                            WP-B (Part B)
Live/Coverage/…, Live/Presentation/…      WP-C (Part C)
```

## A2. Transport

### A2.1 `URLSessionTransport` (WP-A)

```swift
public struct URLSessionTransport: HTTPTransport {
    public init(session: URLSession = URLSessionTransport.makeSession())
    public static func makeSession() -> URLSession   // ephemeral config, no cookie storage, no URLCache, waitsForConnectivity=false
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
```

- **Ephemeral session [DECISION].** It sends no cookies. The shop `__cf_bm` cookie is not needed [LIVE `FX/shop/shop_minimal-headers_*`].
- **Error mapping:**

  | URLError | LiveError |
  |---|---|
  | `.timedOut` | `.timeout` |
  | `.notConnectedToInternet`, `.networkConnectionLost`, `.dataNotAllowed`, `.internationalRoamingOff` | `.offline` |
  | everything else | `.network(error.localizedDescription)` |
  | `CancellationError` | rethrown unchanged |

- Always set `Accept-Encoding: gzip`.
  - Darwin URLSession decompresses transparently.
  - `/gate` sends no compression at all: 95–410 KB per TripSearch with passlist [LIVE `_meta.responseHeaders` in `FX/hafas/*.request.json`].

### A2.2 `FixtureTransport` (test helper, WP-A, in `Tests/KlimaCoreTests/Live/Support/`)

```swift
final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    struct Route { let method: String; let urlSuffix: String; let bodyContains: String?; let response: HTTPResponse }
    init(routes: [Route])
    private(set) var recorded: [HTTPRequest]     // lock-protected
    func send(_ r: HTTPRequest) async throws -> HTTPResponse   // first matching route; fatal test failure if none
}
enum Fixture {
    static func data(_ path: String) throws -> Data   // "hafas/tripsearch_st_anton_innsbruck.response"
    static func json(_ path: String) throws -> Any
    static func golden(_ key: String) throws -> [String: Any]   // FX/golden.json[key]
    static func shopResponse(_ path: String) throws -> HTTPResponse  // unwraps {_meta,request,response}; status from _meta.status
}
```

- Shop and VAO fixtures are wrapped as `{_meta, request, response}`. `Fixture.shopResponse` re-encodes `response` as the body.
- `FX/shop/shop_error_403_cloudflare_block_page.json` holds `response_headers` and `response_body_html_ip_redacted` (HTML, trimmed). Serve it as `text/html`, status 403.

### A2.3 `RequestThrottle` and `LiveHealth` (WP-A)

```swift
public actor RequestThrottle {
    public init(clock: @escaping @Sendable () -> Date = { Date() }, sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) })
    /// Waits until the provider may send (min interval + bucket). Throws .rateLimited(provider, nil) if the wait would exceed maxWait.
    public func acquire(_ provider: LiveProvider, minInterval: TimeInterval, perMinute: Int, maxWait: TimeInterval = 5) async throws
}

public actor LiveHealth {
    public struct Status: Sendable, Hashable { public var lastSuccess: Date?; public var lastError: LiveError?; public var openUntil: Date?; public var consecutiveFailures: Int }
    public init(clock: @escaping @Sendable () -> Date = { Date() })
    public func check(_ p: LiveProvider) throws            // throws .circuitOpen(p, until:) while open
    public func recordSuccess(_ p: LiveProvider)
    public func recordFailure(_ p: LiveProvider, _ e: LiveError)
    public func status() -> [LiveProvider: Status]
    public func reset(_ p: LiveProvider? = nil)             // on config change / user "Erneut versuchen"
}
```

**Per-provider budgets [DECISION]:**

| Provider | minInterval | perMinute |
|---|---|---|
| `.oebbHafas` | `config.hafas.minInterval` (0.3 s) | 40 |
| `.oebbShop` | 1.0 s | 12 |
| `.vaoTariff` | 1.0 s | 20 |

**Circuit-breaker rules [DECISION]:**

| Event | Circuit open for |
|---|---|
| `.blocked` | 30 min (shop) / 6 h (HAFAS `AUTH`) |
| `.rateLimited` | `retryAfter ?? 60 s` |
| 3 consecutive failures of type `.http(5xx)` / `.timeout` / `.network` / `.decoding` | 2 min |

- `.offline`, `.noConnection`, `.noPrice` and `.hafas(code)` are **not** failures for the breaker.
- Success resets `consecutiveFailures`.

**Retries [DECISION]:**
- At most one automatic retry, only for `.timeout`, HTTP 502/503/504 and `.network`, after 1.5 s.
- Never retry 4xx except the shop session codes (§B3.4).
- UI paths never wait for a second retry.

**Timeouts [DECISION]** (per request; `HTTPRequest.timeout`):

| Request | Timeout |
|---|---|
| HAFAS | 20 s |
| Shop | 15 s per call |
| VAO | 12 s |

- The whole price flow has a 12 s budget in `LivePriceService` (§B4).
- TripSearch with polylines took up to 13 s [LIVE `INDEX.json` seconds], so list views never request polylines.

## A3. HAFAS client (ÖBB Scotty) (WP-A)

### A3.1 Envelope [LIVE every `FX/hafas/*.request.json`]

```json
{"lang":"deu","ver":"1.88","ext":"OEBB.14",
 "client":{"id":"OEBB","type":"WEB","name":"webapp","l":"vs_webapp"},
 "auth":{"type":"AID","aid":"5vHavmuWPWIfetEe"},
 "svcReqL":[ {"meth":"…","cfg":{"polyEnc":"GPA"}?,"req":{…}} , … ]}
```

**Headers:**
- `Content-Type: application/json`
- `Accept: application/json`
- `Accept-Encoding: gzip`
- `User-Agent: <config.userAgent>`

No cookies and no token. The AID is a public web-app identifier [SRC `https://fahrplan.oebb.at/webapp/js/hafas_webapp_config.js`].

**`/gate` quirks [LIVE]:**
- `client.v` must be an **Int** or absent; a string gives top-level `err:"HAMM"`. Encode `HafasClientVersion` faithfully.
- The parser is **strict.** An unknown field or enum value rejects the **whole envelope** with `err:"PARSE"` [LIVE `FX/hafas/error_parse_unknown_field`, `error_parse_invalid_enum_rtmode`].
  - The encoder emits only the keys listed in §A3.3.
  - Optionals are omitted, never `null`. Synthesized `Encodable` with optionals already omits nil.
  - Never send `cfg.rtMode`.

**Legacy fallback profile** (`LiveConfig.default.hafasFallback`): `POST https://fahrplan.oebb.at/bin/mgate.exe`, `{"lang":"de","ver":"1.41","client":{"id":"OEBB","v":"6120300","type":"IPH","name":"oebbIPH"},"auth":{"type":"AID","aid":"OWDL4fE4ixNiPBBm"}}`.
- It returns the same response shape and is gzip-compressed [LIVE `FX/hafas/legacy_mgate141_tripsearch_st_anton_innsbruck`].
- **Switch rule [DECISION]:** when the primary profile answers top-level `AUTH`, `HAMM` or `PARSE`, `HafasClient` retries **that call once** with the fallback profile.
  - If the fallback succeeds, the client uses the fallback for 6 h and reports `status[.oebbHafas].lastError`.
  - If both fail, it throws `.blocked(.oebbHafas)` (AUTH) or `.decoding(errTxt)` (PARSE/HAMM).
- `Reconstruction` must use `outReconL` on 1.88. `ctxRecon` gives PARSE [LIVE `error_parse_reconstruction_ctxRecon_v188`]. Use `outReconL` on both profiles; [ASSUMED] that 1.41 accepts it too, live-test it. If 1.41 rejects it, send `ctxRecon` on the legacy profile only.

### A3.2 Response envelope and error mapping [LIVE]

```json
{"ver":"1.88","ext":"OEBB.14","lang":"deu","id":"…","err":"OK","svcResL":[{"meth":"TripSearch","err":"OK","res":{"common":{…},…}}]}
```

- HAFAS errors come back with **HTTP 200**. Check the top-level `err` first, then `svcResL[i].err`.
- `svcResL[i]` answers `svcReqL[i]`. Errors are isolated per element [LIVE `FX/hafas/batch_edge_cases_errors`: `["LOCATION","H890","PARAMETER","H9381"]`].
- HTTP status ≠ 200 or a non-JSON body → `.http(status, excerpt)`.

**Mapping:**

| Condition | LiveError |
|---|---|
| top `AUTH` | fallback, then `.blocked(.oebbHafas)` |
| top `PARSE` / `HAMM` | fallback, then `.decoding(errTxt ?? hammError)` |
| top other ≠ OK | `.hafas(code: err, message: errTxt)` |
| svc `H890` | `.noConnection` |
| svc `LOCATION` | `.hafas(code:"LOCATION", message: errTxtOut)`. The caller invalidates the StationLinker entry. |
| svc `H9381` (origin = destination), `H9380` (too near) | `.hafas(code:, message: errTxtOut)`. The UI shows „Start und Ziel sind zu nah beieinander.“ |
| svc other ≠ OK | `.hafas(code:, message: errTxtOut ?? errTxt)` |

- `errTxtOut` is German and user-facing, e.g. „Es wurde keine Verbindung gefunden“.

### A3.3 Requests (exact key sets) [LIVE: fixture requests]

All dates and times are **Europe/Vienna wall clock**: `yyyyMMdd` and `HHmmss`. Use `Calendar.vienna`.

**LocMatch (search box)**
```json
{"meth":"LocMatch","req":{"input":{"loc":{"type":"ALL","name":"<query>?"},"maxLoc":8,"field":"S"}}}
```
- `type` is one of `ALL`, `S`, `A`, `P`, `SP`.
- The trailing `?` means fuzzy matching; it is always appended.
- **LocMatch never fails on nonsense** [LIVE `locmatch_batch_2_nonfuzzy_nomatch`[3]]. It returns OK plus popular stations. The client drops results that do not plausibly match.
  - A result is **kept** when, for at least one normalized query token with ≥ 3 characters, some token of `StationIndex.normalize(result.name)` either starts with it, or has a same-length prefix within `StationIndex.levenshtein(…, limit: 2)`. The `limit: 2` keeps typos such as „Insbruck“.
  - This filter runs in `HafasCodec.locations(from:serviceIndex:query:)`, which `HafasClient.locations` uses.
  - Golden: `xqzvvhjkq` → empty.

**LocGeoPos (nearby)**
```json
{"meth":"LocGeoPos","req":{"ring":{"cCrd":{"x":11401000,"y":47263000},"maxDist":400,"minDist":0},"getStops":true,"getPOIs":false,"maxLoc":10,"locFltrL":[{"type":"PROD","mode":"INC","value":"8191"}]}}
```
- `x` is lon × 1e6 and `y` is lat × 1e6, both **after rounding lat and lon to 3 decimals** [DECISION, privacy].
- The response is `res.locL[]` with `dist` in metres [LIVE `locgeopos_nearby_innsbruck_hbf`].

**TripSearch**
```json
{"meth":"TripSearch","cfg":{"polyEnc":"GPA"},"req":{
 "depLocL":[{"lid":"A=1@L=8100108@","type":"S"}],"arrLocL":[{"lid":"A=1@L=1290401@","type":"S"}],
 "viaLocL":[{"loc":{"lid":"A=1@L=8100013@","type":"S"}}],
 "outDate":"20261009","outTime":"113000","outFrwd":true,
 "maxChg":-1,"minChgTime":-1,"numF":5,
 "getPasslist":true,"getPolyline":false,"getPT":true,"getIV":false,"getTariff":true,"ushrp":true,
 "jnyFltrL":[{"type":"PROD","mode":"INC","value":"8191"}]}}
```

Encoding rules:
- **`viaLocL`** only when `via` is non-empty (never an empty list, never `null`); see the via note below.
- **Paging:** send `ctxScr: <context>` and **omit** `outDate`, `outTime` and `outFrwd` [LIVE `tripsearch_paging_later_graz_klagenfurt`, `…_earlier_…`]. Everything else stays identical.
- **`outFrwd:false`** means `outTime` is the latest arrival [LIVE `tripsearch_arrive_by_innsbruck_wien`].
- **`maxChg`:** `maxChanges ?? -1`. **`minChgTime`:** `minTransferMinutes ?? -1`.
- **Extra `jnyFltrL` entries:**
  - Bike: `{"type":"BC","mode":"INC"}` [LIVE accepted, `tripsearch_bike_filter_BC`].
  - Accessibility: `{"type":"META","mode":"INC","meta":"completeBarrierfree"|"limitedBarrierfree"}` [LIVE accepted, `tripsearch_accessibility_meta_filter`]. Effect unverified [ASSUMED].
- **`getTariff:true`** [DECISION]. It adds the shop deep link `trfRes` per connection at negligible cost [LIVE `tripsearch_getTariff_true_innsbruck_wien`]. It never contains prices [LIVE].
- **`getPolyline`** = `includePolyline`. It is false in list views; shapes come from JourneyDetails.
- **`getPasslist`** = `includeStopovers`: true for results lists (stopover counts, coverage), false for „Deine Strecken“.
- The `PROD` value is a **String**.

**Additive note: via (owner request 2026-10-09)** („man sollte auch VIA Halte rein machen“)
- `JourneyQuery.via: [ViaStop]` replaces the earlier `via: Location?` (decoding still accepts a single `Location` and a
  missing key). `ViaStop = { location: Location, minimumDwellMinutes: Int? }`; at most `JourneyQuery.maxViaStops` (2)
  are sent, in travel order.
- Encoding: `"viaLocL":[{"loc":<loc>,"min":<minutes>}, …]`. `min` only when `minimumDwellMinutes` is set (> 0);
  no `viaLocL` key at all when `via` is empty. Paging requests repeat `viaLocL` unchanged.
- [LIVE 2026-10-09, one request] `/gate` 1.88 accepts `min` inside `viaLocL` and honours it: Innsbruck Hbf → Bregenz
  via Feldkirch with `min: 10` returns 3 journeys that all break at Feldkirch (RJ/RJX → S 1, 18 min stay), whereas
  without the stay the RJX run through to Bregenz [`FX/hafas/tripsearch_via_feldkirch_dwell_ibk_bregenz`, trimmed;
  `HafasViaTests`: request shape, every journey passes the via station, stay ≥ `min`].
- `Journey.passes(_ location:)` (extId, else lid, else ≤ 300 m) checks that a journey stops at a via station.

**Reconstruction (refresh a saved connection)**
```json
{"meth":"Reconstruction","cfg":{"polyEnc":"GPA"},"req":{"outReconL":[{"ctx":"<Journey.refreshToken>"}],"getIST":true,"getPasslist":true,"getPolyline":false}}
```
- The response is `res.outConL[0]` in the TripSearch shape [LIVE `reconstruction_innsbruck_lech_outReconL`].
- Batch refresh: N Reconstruction svcReqs in one envelope.

**JourneyDetails**
```json
{"meth":"JourneyDetails","cfg":{"polyEnc":"GPA"},"req":{"jid":"<Leg.tripID>","getPolyline":true}}
```
- The response is `res.journey`: the whole run (12 stops Wien→Venezia, 3,589 polyline points) [LIVE `journeydetails_rjx133_koralm_polyline`].
- Cut it to the user's leg with `stopL[].idx` between the leg's `dep.idx` and `arr.idx`. These are exposed as `Stopover.index`.

**StationBoard**
```json
{"meth":"StationBoard","req":{"type":"DEP","stbLoc":{"lid":"A=1@L=8100108@","type":"S"},"date":"20261009","time":"112402","dur":60,"maxJny":40,"jnyFltrL":[{"type":"PROD","mode":"INC","value":"8191"}]}}
```

**HimSearch**
```json
{"meth":"HimSearch","req":{"maxNum":30,"dateB":"20261009","timeB":"112702","dateE":"20261010","timeE":"112702","himFltrL":[{"type":"PROD","mode":"INC","value":"4157"}]}}
```
- `himFltrL` is omitted when `products == nil`.

**ServerInfo (health check)**
```json
{"meth":"ServerInfo","req":{"getVersionInfo":true,"getClientFilter":true,"getServerDateTime":true}}
```
- Exposed as `HafasClient.serverInfo()`. Used only by the Settings „Verbindung testen“ action (§E7).

### A3.4 Decoding rules (raw mirrors → domain) [LIVE unless tagged]

- **Raw mirrors.** Every raw struct field is optional, and unknown keys are ignored (default Decodable).
- **Common lists.** `res.common` holds `locL`, `prodL`, `opL`, `remL`, `himL`, `icoL`, `polyL`, `dirL`. These lists are **per `svcResL[i]`**. Objects reference them by index: `…X` is one index, `…XL` a list, `…RefL` a list of references. An out-of-range index yields `nil`; never crash.

**Field types (observed):**

| Field(s) | Type |
|---|---|
| `extId`, `planrtTS`, `dur`, `chgTime`, all times | **String** |
| `crd.x`, `crd.y`, `cls`, `pCls`, `chg`, `idx`, `prio`, `*TZOffset*`, `dist` | Int |
| `isRchbl` | Bool |
| `dPltfS` / `aPltfS` / `dPltfR` / `aPltfR` | object `{"type":"PL","txt":"3"}`; `type` is `PL` or `ST` |

- Also accept the legacy **string** forms `dPlatfS`, `dPlatfR`, `aPlatfS`, `aPlatfR` [SRC hafas-client `parse/journey-leg.js`]. Kind `PL` → `.track`, `ST` → `.stand`, else `.unknown`.

**Times.** `HafasTime.date(base: "yyyyMMdd", time: "[dd]HHMMSS", tzOffsetMinutes: Int?) -> Date?`
- An 8-digit time carries a day offset: `"01004100"` is base + 1 day at 00:41:00.
- If an offset is given, the date is local time minus the offset. Otherwise interpret the time in Europe/Vienna.
- Realtime uses `dTZOffsetR ?? dTZOffset`.
- Base date by method:
  - TripSearch / Reconstruction section times use `outConL[i].date`.
  - `jny.stopL[]` uses `jny.date ?? outConL[i].date`.
  - JourneyDetails uses `journey.date`.
  - StationBoard uses `jnyL[i].date`.
- **Golden:** NJ 19946 departs `224400` with `dTZOffset 120` and arrives `01050500` with `aTZOffset 60`. That is 2026-10-24T22:44+02:00 → 2026-10-25T05:05+01:00 = 26,460 s, equal to HAFAS `dur "072100"` [LIVE `FX/hafas/tripsearch_overnight_dst_change_wien_innsbruck`; golden `journeys[0]`].

**Durations.** `dur`, `durS`, `gis.durS` and `chg.durS` are `[dd]HHMMSS`, converted to seconds.

**Realtime.** `StopEvent.realtime` is set only when `dTimeR` or `aTimeR` exists.
- `prognosis`: `dProgType` / `aProgType` `PROGNOSED` → `.prognosed`, `REPORTED` → `.reported`, else `.other`.
- `isCancelled = dCncl / aCncl == true`. Not observed live; the Swift tests need synthetic cases [SRC hafas-client].
- `platformChangeFlag = dPlatfCh / aPlatfCh == true`.

**Locations** (`locL[i]` → `Location`):

| Domain field | Source |
|---|---|
| `lid` | `lid` |
| `kind` | `type` `S` / `A` / `P` |
| `extId` | `extId` |
| `name` | `name` |
| `coordinate` | `crd.y / 1e6`, `crd.x / 1e6` |
| `products` | `pCls` |
| `isMeta` | `meta == true` |
| `distanceMeters` | `dist` |
| `countryCode` | `countryCodeL[0]` |
| `uicCode` | `globalIdL.first { $0.type == "U" }?.id` |
| `minTransferSeconds` | `chgTime` |

- Meta stations such as `1290401` „Wien Hbf (U)“ and `1291501` „Wien Westbahnhof (U)“ are valid TripSearch and StationBoard origins [LIVE].

**Products → `Line`** (`prodL[prodX]`):

| Domain field | Source |
|---|---|
| `fullName` | `name` |
| `category` | `prodCtx.catOut` trimmed. It is space-padded live: `"RJX     "`. |
| `categoryShort` | `prodCtx.catOutS` |
| `categoryLong` | `prodCtx.catOutL` |
| `lineNumber` | `prodCtx.line` |
| `trainNumber` | `prodCtx.num` |
| `lineId` | `prodCtx.lineId` |
| `admin` | `prodCtx.admin` |
| `operatorName` | `opL[oprX].name` |
| `productClass` | `cls ?? 0` |

- **`name`** (display):
  - If `cls ∈ {1,4,8,4096}`, or `line == nil` and `catOutS != nil`: `"\(catOutS) \(num ?? number)"`, e.g. `"RJX 19960"`. HAFAS sends `"RJX19960"` without a space for 5-digit numbers [LIVE].
  - Otherwise `nameS ?? name`, e.g. `"Bus 750"`, `"CJX 5"`, `"U6"`.
  - If empty: `catOutL ?? "Verbindung"`.
- **`mode`**:

  | `cls` | `TransportMode` |
  |---|---|
  | 1, 4, 8, 16, 4096 | `.train` |
  | 2 (SEV, rail replacement bus) | `.bus` |
  | 32 | `.sBahn` |
  | 64 | `.bus` |
  | 128 | `.ferry` |
  | 256 | `.metro` |
  | 512 | `.tram` |
  | 1024 (long-distance coach) | `.bus` |
  | 2048 | `.cableCar` [ASSUMED] |
  | other | `.other` |

  The bit table is [LIVE] except 128 and 2048 [SRC webapp config]. hafas-client wrongly names bit 2 "IC/EC"; it is SEV [LIVE icon `prod_sev`].
- **Operator quirk:** every ÖBB-run train, including foreign ICE, has the operator `"Nahreisezug"` with `admin 81____` [LIVE]. Do not show the operator for those.

**Legs** (`outConL[i].secL[j]`):

| HAFAS | Domain |
|---|---|
| `type JNY` | `.ride` |
| `type WALK` with `gis.dist > 0` | `.walk` |
| `WALK` without `gis.dist` (`chg` block present, same station on both sides) | `.transfer` |
| `TRSF` | `.transfer` |
| `GIS`, `KISS`, `DEVI` | `.walk` |
| `CHKI`, `CHKO` and other types | `.walk` |
| `hide == true` and not JNY | dropped [ASSUMED; not observed] |

- `id = secL.id ?? "\(cid)-\(j)"`.
- Ride legs:
  - `tripID = jny.jid`;
  - `direction = jny.dirTxt ?? dirL[jny.dirL[0].dirX].txt`;
  - `stopovers` from `jny.stopL`;
  - `isReachable = jny.isRchbl`;
  - `isCancelled = jny.isCncl == true || dep.dCncl || arr.aCncl`;
  - `isPartiallyCancelled = jny.isPartCncl == true`;
  - `currentPosition = jny.pos`.
- Walk legs: `walkDistanceMeters = gis.dist`, `walkDurationSeconds = gis.durS`.
  - The golden walk is 35 m, `durS 000100`, plus a `chg` block of 38 min [LIVE `tripsearch_innsbruck_lech_bus` C-0 sec 1].

**Polyline** (`cfg.polyEnc:"GPA"`):
- Google encoded polyline, precision 1e5, lat/lon order, in `polyL[k].crdEncYX`.
- **A leg's shape is the concatenation of all `polyG.polyXL` indices in order.** ÖBB sends a DOT stub at the origin, the SOLID main line and a DOT stub at the destination. Drop the first point of a segment when it equals the previous segment's last point.
- JourneyDetails may also inline `journey.poly.crdEncYX`.
- **Goldens:**
  - RJX St. Anton→Innsbruck: 889 points (golden `tripsearch_st_anton_innsbruck.journeys[0].polylinePointCounts == [889]`).
  - JourneyDetails RJX 133: 3,589 points, first (48.18505, 16.37701), last (45.44138, 12.32044).
- Ignore `crdEncS` and `crdEncF`.

**Remarks** (`msgL[]` on connection, jny, stop or loc):

| `msgL` entry | Source | Domain |
|---|---|---|
| `type REM` | `remL[remX]` | `Remark(kind: A→.attribute, I→.info, H→.hint, R→.realtime, else .other; code, text: txtN, priority: prio)` |
| `type HIM` | `himL[himX]` | `Remark(kind: .disruption, id: hid, title: head, text: text, priority: prio, validFrom: sDate+sTime, validUntil: eDate+eTime, modifiedAt: lModDate+lModTime)` |

- `txtN` may contain `<b>` and `<s>`. Strip tags; struck text means "not available today".
- **HTML → text** (`HTMLText.plain`):
  - `<br>` and `<br/>` → `\n`;
  - remove all other tags;
  - decode named entities (`&amp; &lt; &gt; &quot; &nbsp; &Ouml; &ouml; &Auml; &auml; &Uuml; &uuml; &szlig;`) and numeric `&#NN;` / `&#xHH;`;
  - collapse more than 2 newlines; trim.
  - Golden source: `himsearch_disruptions_rail`.
- Deduplicate remarks by `(kind, id ?? text)` per object.

**Connection → `Journey`:**

| Domain field | Source |
|---|---|
| `durationSeconds` | `dur` |
| `changes` | `chg` |
| `refreshToken` | `recon.ctx`. It starts with `¶HKI¶` [LIVE golden `refreshTokenPrefix`]. |
| `checksum` | `cksum` |
| `serviceDays` | `sDays.sDaysR` |
| `serviceDaysDetail` | `sDays.sDaysI` |
| `isAlternative` | `isAlt == true` |
| `remarks` | `msgL` |
| `realtimeUpdatedAt` | `planrtTS` (epoch seconds, String) |

- `shopURL`: Base64-decode `trfRes.extContActionBar.content.content` when `content.type == "URL_EXT"`. Else use `trfRes.clickout` (legacy profile).
  - Golden: `https://shop.oebbtickets.at/de/ticket?cref=scotty&connectionDatetimeDeparture=2026-10-09T13:58&…&connectionOrigEva=8100108&connectionDestEva=8103000…` [LIVE `tripsearch_getTariff_true_innsbruck_wien`].
  - WESTbahn connections have none [LIVE].
- `JourneyPage.earlierContext = outCtxScrB`, `laterContext = outCtxScrF`.

**Board** (`jnyL[]` → `BoardEntry`):
- `event` from `stbStop` with the `d` prefix for DEP and the `a` prefix for ARR.
- `stop = locL[stbStop.locX]`.
- `terminusOrOrigin = locL[prodL[0].tLocX]` for DEP and `locL[prodL[0].fLocX]` for ARR, where `prodL` is the entry's own `jnyL[i].prodL`, not common.
- `isRedirected = isRedir == true`.
- **Sort client-side by effective time.** The HAFAS order is not realtime-sorted. +354 min delays exist [LIVE `stationboard_arr_wien_hbf`].
- `dirTxt` is the run's final destination even on ARR boards [LIVE].

### A3.5 `HafasClient` API (WP-A; conforms to `TimetableService`)

```swift
public actor HafasClient: TimetableService {
    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth,
                appVersion: String, clock: @escaping @Sendable () -> Date = { Date() })
    public func update(config: LiveConfig)                      // new endpoints/aid from remote config; resets fallback state
    public func serverInfo() async throws -> HafasServerInfo    // {hciVersion, serverVersion, serverDate, timetableFrom, timetableTo}
    // TimetableService – see contract
}
public struct HafasServerInfo: Sendable, Hashable { public var hciVersion: String?; public var serverVersion: String?; public var serverTime: Date?; public var timetableFrom: String?; public var timetableTo: String? }
```

- **`config.isEnabled(.oebbHafas) == false`** → throw `.disabled(.oebbHafas)` before any I/O.
- **Ordering:** `health.check` → `throttle.acquire` → transport → `health.record…`.
- **In-memory caches [DECISION]:**

  | Request | Cache |
  |---|---|
  | LocMatch | keyed `(normalized query, types)`, TTL 24 h, LRU 200 |
  | identical TripSearch query (excluding `pageContext`) | 30 s, de-duplicates double taps |
  | StationBoard | 20 s |
  | JourneyDetails | 60 s |
  | Reconstruction | never cached |

- **Batch API:** `journeys(batch:)` and `refresh(batch:)` send **one** envelope with N svcReqs and map each `svcResL[i]` independently. This is for „Deine Strecken“ (3 queries) and the visible-cards refresh.

### A3.6 Products filter values

`ProductMask.all = 8191`, `.rail = 4157`, `.klimaTicket = 4991` (all minus ship, coach, on-demand). These are in the contract and covered by contract tests.
- The „Nur mit KlimaTicket gültig“ planner option sends `.klimaTicket`. It **additionally** relies on coverage evaluation (§C2), because cls alone never decides coverage.

### A3.7 `StationLinker` (WP-A): app stations ⇄ live locations

**Why it exists:**
- The app's 1,487 stations use ids like `at:47:1187` (Austrian IFOPT), `uic:8100227`, `wl:60201349`, `osm:hub:…`, `de:…` and similar.
- HAFAS uses extIds; VAO uses its own lids.

```swift
public actor StationLinker {
    public init(stations: StationIndex, timetable: (any TimetableService)?, vao: VaoLocationSearching?, cacheURL: URL?, clock: @escaping @Sendable () -> Date = { Date() })
    /// App station → ÖBB HAFAS location (for TripSearch/StationBoard/shop). Disk-cached 30 days.
    public func hafasLocation(for station: Station) async throws -> Location
    /// App station → VAO lid "A=1@L=<n>@" (for VerbundTariffClient). Disk-cached 30 days.
    public func vaoLid(for station: Station) async throws -> String
    /// HAFAS location → best app station (nil if none within 300 m with a compatible name). Pure; no I/O.
    public nonisolated static func appStation(for location: Location, in index: StationIndex) -> Station?
    public func invalidate(stationID: String)
}
public protocol VaoLocationSearching: Sendable { func vaoLocations(_ query: String) async throws -> [Location] }   // implemented by VerbundTariffClient (WP-B)
```

**HAFAS mapping rules:**
1. `uic:<eva>` → `Location.station(extId: eva, name: station.name)`. No I/O.
2. Otherwise: LocMatch `"<station.name>?"`, type `S`, maxLoc 8. Candidates with `kind == .station` and a coordinate are scored:
   - distance ≤ 300 m, or ≤ 800 m for `isMeta`, is required;
   - prefer non-meta rail stops (`products ∩ .rail ≠ ∅`) for `Station.kind == .rail`;
   - prefer meta for `.metro` and `.tramHub`;
   - ties go to the higher normalized-name similarity.
   
   No candidate → `.hafas(code:"LOCATION", message: nil)`.
   - [LIVE] „Wien Hbf“ returns only the meta `1290401`, which the shop also accepts.
   - [LIVE] `globalIdL U` equals the IFOPT digits only for Tirol and Kärnten. Use it as a hint for a +10 score, never as a key.

**VAO mapping rules:**
1. `at:A:S[:x:P]` → `A=1@L=<A><S zero-padded 5><P zero-padded 2>@`. Example: `at:47:1187` → `A=1@L=470118700@` [LIVE 22/22 + `FX/vao/*` `depLid`].
2. `wl:6020NNNN` → treat as `at:49:NNNN` → `A=1@L=4900NNNN00@` with NNNN zero-padded to 5 digits. [ASSUMED from Wien Hbf `wl:60201349` ↔ `at:49:1349` and Karlsplatz `wl:60200657` ↔ `at:49:657`.] A live test must confirm it.
3. Otherwise: VAO LocMatch by name, pick the nearest within 400 m. **VAO rejects ÖBB EVA lids** (`A=1@L=8100227@` → svc `LOCATION`) [LIVE `FX/vao/arch_vao_tripsearch_tariff_eva-lid_eferding-linz`]. VAO LocMatch works and embeds the IFOPT id: `…@L=444250500@…@i=A×at:44:42505@` for „Eferding Bahnhof“ [LIVE `FX/vao/arch_vao_locmatch_eferding`].

**Reverse mapping** (`appStation(for:in:)`):
- Nearest `StationIndex` station within 300 m whose normalized name shares its first token with the location's display name. Use `DisplayName` stripping; see §C3.3.
- Example: „Innsbruck Hbf“ ↔ „Innsbruck Hauptbahnhof“ via the `hbf` normalization.
- If no station qualifies → nil. The trip is then saved with the free-text name, and its coordinates feed the estimator.

**Disk cache:** JSON `{version:1, entries:{stationID:{hafas:{lid,extId,name,lat,lon}, vaoLid, fetchedAt}}}` at `cacheURL`. Atomic writes, at most 2,000 entries.

### A3.8 Live config and remote kill switch (WP-A model, WP-D loading)

- **Model:** `LiveConfig` (contract). The defaults are compiled in.
- **`LiveConfigLoader.decode(_ data: Data, current: LiveConfig) -> LiveConfig?`** (WP-A) returns nil when invalid, or when `version <= current.version`.
- **Remote file:** `data/live_config.json` in the repo is the template (WP-D). It is published like `tariffs.json`.
- **URL resolution:** `AppConfig.liveConfigURL`, CI variable `LIVE_CONFIG_URL`, or `UpdateManifest.liveConfigURL` (new optional field, WP-D). The manifest wins.
- **Refresh:** at most every 12 h; cached in Application Support (§E4).
- **Kill switch:** `killSwitch:true` or `*.enabled:false` turns off the matching provider at once on the next config load. The UI shows `notice` in Settings.

---

# PART B: Live prices (WP-B)

## B1. File layout

```
Live/Pricing/PriceModels.swift          CONTRACT (Step 0): PriceSource, LeadTimeTier, PriceEndpoint, PriceRequest, PriceQuote, LivePriceProvider
Live/Pricing/FareEstimator+Live.swift   CONTRACT (Step 0): estimateLive(...)   (+ FareEstimator.swift patch: Method.liveOebb/.liveVerbund, FareEstimate.quote)
Live/Pricing/OebbShopClient.swift       WP-B
Live/Pricing/ShopModels.swift           WP-B  (raw Decodable mirrors of timetable/offers/stations/token)
Live/Pricing/ShopOfferSelector.swift    WP-B  (pure: offers → Standard fare)
Live/Pricing/VerbundTariffClient.swift  WP-B  (VAO TripSearch getTariff + LocMatch; uses HafasEnvelope from WP-A)
Live/Pricing/VerbundArea.swift          WP-B  (pure: station id → Verbund hint)
Live/Pricing/LivePriceService.swift     WP-B  (actor; policy §B4, cache §B6)
Live/Pricing/PriceCache.swift           WP-B
Live/Pricing/TariffPeriods.swift        WP-B  (pure: same-tariff-period check)
Live/Pricing/ShopDeepLink.swift         WP-B  (pure: build prefilled shop URL, §B3.7)
```

## B2. Price facts the policy relies on

| Fact | Evidence |
|---|---|
| Regular single ticket = offer in `travelClasses[].class == "2"` (or `"1"`) with `flexibility.de == "FLEX"` whose products are all `trafficType == "ONEWAY"`, lowest `price` | [LIVE] golden: `shop_wien-salzburg_2026-10-10_07` 66,40 Standard-Ticket ÖBB; same day `…sameday…_07` 67,70 |
| Inside a Verbund the shop sells the Verbund ticket (VVT/VOR/OÖVV). FLEX `MULTIPLE` day tickets must be excluded. | [LIVE] `shop_ibk-hall_2026-10-10_07`: VVT Einzelticket 4,70 (ONEWAY) vs. Tagesticket Tirol 2Plus 42,60 (MULTIPLE) |
| Verbund tickets have no 1st class. 1st class is sold as an ÖBB Standard-Ticket at the table's 1st-class price. | [LIVE] `arch_shop_offers_v6_minimal-passenger_ibk-landeck`: 2nd VVT 22,00 · 1st Standard-Ticket 34,40 |
| Vorteilscard Classic = cardId 108; exactly 50 % rounded up to 0,10 | [LIVE] `…_08_offers_v6_vorteilscard` 33,20; `arch_shop_offers_v6_minimal-vorteilscard_graz-wien` 22,20 (= 44,30/2) |
| Minimal passenger `{"type":"ADULT","id":1,"cards":[]}` is accepted; HAFAS-derived station objects are accepted | [LIVE] `arch_shop_timetable_hafas-station_minimal-passenger_ibk-landeck` (3 connections) + offers |
| Price depends on lead time: same day = table ST VP 000; 1–14 days ≈ −1.9 %; ≥ 15 days ≈ −5.9 % | [LIVE] prices report §1.8 |
| Past departures: timetable still lists them, offers return `{"offerError":true}` | [LIVE] `shop_offers_v6_past_yesterday_*` |
| After the timetable change (13.12.2026) only Nightjets are bookable today | [LIVE] `shop_timetable_wien-salzburg_2026-12-15T1400` (sections NJ only) |
| Shop never lists WESTbahn | [LIVE] |
| VAO `trfRes.totalPrice.amount` (cents) = Verbund single ticket; `statusCode:"NA"` across Verbund borders; works for past and future dates; same price for all connections of a relation | [LIVE] `FX/vao/*` golden (St. Anton–Ibk 2200 „VVT 14 Zonen“; Wien–Salzburg NA; Ibk–Hall 470 past, 2026-12-15, 2027-01-15) |
| VAO fare names carry trailing spaces („Einzelticket “) | [LIVE] → trim |
| Detour route variants cost more (RJ 658 via Enns valley 91,50 vs 67,70) | [LIVE] prices report §1.8 |
| Cloudflare blocks some client fingerprints (curl 403 HTML), urllib passes; iOS URLSession unknown | [LIVE] / [ASSUMED] → device test (Risk R1) |

## B3. `OebbShopClient` (actor)

### B3.1 Endpoints and headers [LIVE]

**Base:** `https://shop.oebbtickets.at`.

**Headers on every call:**
- `User-Agent: <config.userAgent>`
- `Accept: application/json`
- `Channel: inet`
- `AccessToken: <jwt>` after the token call
- `Content-Type: application/json` on POST

Nothing else is needed [LIVE `shop_minimal-headers_*`].

| # | Call | Notes |
|---|---|---|
| 1 | `GET /api/domain/v1/anonymousToken` | → `{access_token, expires_in:300, refresh_token, refresh_expires_in:2340, session_state, scope}`. Store `access_token` and `obtainedAt`. |
| 2 | `POST /api/domain/v1/initUserData`, body `{}` | **Required.** Without it, `timetable` returns HTTP 440 `{"error":{"code":3011,…}}` [LIVE `shop_error_440_session_not_initialised_timetable`]. |
| 3 | `GET /api/hafas/v1/stations?name=<q>&count=5` | Fallback station lookup only (§B3.5). Response `[{number, name, meta, latitude, longitude}]` (µdeg ints). Meta entries have `name:""`. |
| 4 | `POST /api/hafas/v4/timetable` | Body below. Response `{connections[], infos[]}`. |
| 5 | `POST /api/offer/v6/offers` | Body below. Response `{connection, offerSections[], offerError, infos, notes, isReturnJourneyAvailable, …}`. |

`/api/offer/v2/travelActions` and `/api/offer/v1/prices` are **not used**: they are optional, and `prices` returns the cheapest Sparschiene price.

### B3.2 Bodies [LIVE]

```json
// timetable
{"datetimeDeparture":"2026-10-09T16:00:00.000",
 "filter":{"regionaltrains":false,"direct":false,"wheelchair":false,"bikes":false,"trains":false,"motorail":false,"connections":[]},
 "passengers":[{"type":"ADULT","id":1,"cards":[]}],
 "count":3,"sortType":"DEPARTURE",
 "from":{"number":8100108,"name":"Innsbruck Hbf","latitude":47263040,"longitude":11401020},
 "to":{"number":8100063,"name":"Landeck-Zams Bahnhof","latitude":47140260,"longitude":10566610}}
// offers
{"selection":{"connectionId":"<connections[i].id>","offerSections":[]},
 "passengers":[{"type":"ADULT","id":1,"cards":[]}],
 "datetime":"2026-10-09T16:00:00.000"}
```

- **Times** are Vienna wall clock **without** an offset, formatted `yyyy-MM-dd'T'HH:mm:ss.SSS`. Using UTC by mistake gives `offerError` everywhere [LIVE, prices report].
- **The offers `datetime`** equals the timetable `datetimeDeparture`.
- **Vorteilscard:** `"cards":[{"name":"Vorteilscard Classic","cardId":108}]` [LIVE]. `cardId` comes from `config.shop.vorteilscardCardID`.
- **Station objects:** `number` = HAFAS extId as Int, `name` = HAFAS name, coordinates in µdeg ints [LIVE]. Meta stations work: `1290401` „Wien Hbf (U)“ [LIVE].

### B3.3 Response decoding (raw mirrors, all optional)

- **`ShopConnection`**:
  - `id` (64-hex, opaque)
  - `from {name, esn, departure, departurePlatform}`
  - `to {name, esn, arrival, arrivalPlatform}`
  - `sections[] {from, to, duration(ms), category{name, number, displayName, longName.de, parallelName?, parallelNumber?, train}, type}`
  - `switches`, `duration` (ms), `infos[] {header, text, textPlain}`
- **`ShopOffers`**:
  - `offerError: Bool?`
  - `offerSections[].travelClasses[] {class: "2"|"1"|"B", offers[]}`
  - each offer: `{flexibility.de: "NON-FLEX"|"SEMI-FLEX"|"FLEX", price: Double, products[] {name.de, price, class, trafficType: "ONEWAY"|"MULTIPLE", owners[] {nameShort, description}, relevantReductions[].de}, reservation?.price, validityInfo?}`
- **Prices** are EUR doubles. Convert with `(price * 100).rounded() / 100`.

### B3.4 Session and error handling [LIVE]

**Session:**
- `ensureSession()`: if there is no token, or `now - obtainedAt > config.shop.tokenRenewAfter` (240 s; the token lives 300 s), call #1 then #2.
- Tokens are kept **in memory only**. They are never persisted or logged.

**Response classification** (in this order):

| Response | Handling |
|---|---|
| 403 and not JSON (Cloudflare page, `server: cloudflare`, `cf-ray`) | `.blocked(.oebbShop)`. The circuit opens for 30 min. [LIVE `shop_error_403_cloudflare_block_page`] |
| 429 | `.rateLimited(.oebbShop, retryAfter)` |
| 401 with `error.code == 13008` („Access token is expired.“) or 440 with `error.code == 3011` | drop the session, `ensureSession()`, **retry once**; second failure → `.sessionExpired` [LIVE `shop_token_expiry_after_330s_timetable`, `shop_error_440_…`] |
| any other ≥ 400, or not JSON | `.http(status, excerpt)` |
| `offerError == true` | `.noPrice("offerError")` |
| empty `connections` | `.noPrice(infos.first?.header ?? "keine buchbare Verbindung")` |

### B3.5 Station resolution for the shop

In priority order:
1. `PriceEndpoint.hafasExtId` with name and coordinates from the planner `Location`.
2. `StationLinker.hafasLocation(for: appStation)`.
3. Shop `stations?name=`: the candidate with a non-empty `name` nearest to the endpoint coordinate, within 1 km.

Positive and negative results are cached by `StationLinker` and the price cache.

### B3.6 Public API

```swift
public actor OebbShopClient {
    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth,
                clock: @escaping @Sendable () -> Date = { Date() })
    public func update(config: LiveConfig)
    public struct Station: Codable, Sendable, Hashable { public var number: Int; public var name: String; public var latitude: Int; public var longitude: Int }
    public func stations(named: String) async throws -> [Station]
    public func timetable(from: Station, to: Station, departure: Date, discount: FareDiscount, count: Int = 3) async throws -> [ShopConnection]
    public func offers(connectionID: String, departure: Date, discount: FareDiscount) async throws -> ShopOffers
}
extension PriceRequest {
    /// From/to = first/last ride leg origin/destination (stationID via StationLinker.appStation(for:in:), hafasExtId, coordinate);
    /// departure = planned departure of the first ride leg; mode = mode of the longest ride leg; journey = journey.
    public init(journey: Journey, travelClass: TravelClass, discount: FareDiscount, stations: StationIndex)
}
public enum ShopOfferSelector {
    /// Standard regular single fare for `travelClass` (2nd → "2", 1st → "1"); nil if none. Pure. Golden-tested.
    public static func standardFare(_ offers: ShopOffers, travelClass: TravelClass) -> ShopFare?
}
public struct ShopFare: Sendable, Hashable { public var amountEUR: Double; public var productName: String; public var owner: String; public var reductions: [String] }
```

- `productName` is the product names joined with „ + “.
- `owner` is `products[0].owners[0].nameShort`, e.g. „ÖBB“, „VVT“, „VOR“, „OÖVV“.

### B3.7 Shop deep link (purchase hand-off) [SRC `oebb_shop_deeplink_params_from_spa_bundle.json`, LIVE format from Scotty]

```
https://shop.oebbtickets.at/de/ticket?cref=klimabilanz&stationOrigEva=<9-digit zero-padded>&stationDestEva=<…>&outwardDateTime=<yyyy-MM-ddTHH:mm Vienna, no offset>
```

- Add `&outwardArrival=true` for arrive-by.
- Prefer `Journey.shopURL` from HAFAS when present.
- `ShopDeepLink.url(from:to:date:arrival:)` is pure (WP-B).
- Whether the prefill takes effect is [ASSUMED]; the SPA was not executed.

## B4. `LivePriceService`: policy (the heart of "richtiger Preis")

```swift
public actor LivePriceService: LivePriceProvider {
    public init(config: LiveConfig, shop: OebbShopClient?, verbund: VerbundTariffClient?, linker: StationLinker?,
                estimator: FareEstimator, stations: StationIndex, cacheURL: URL?,
                clock: @escaping @Sendable () -> Date = { Date() })
    public func update(config: LiveConfig)
    public func update(estimator: FareEstimator)          // after tariff catalog reloads
    /// Live only (throws LiveError) – conforms to LivePriceProvider.
    public func livePrice(_ request: PriceRequest) async throws -> PriceQuote
    /// Live → offline. Never throws. `allowLive:false` = offline chain only (used when Live-Daten is off).
    public func quote(_ request: PriceRequest, allowLive: Bool = true) async -> PriceQuote
    public func offlineQuote(_ request: PriceRequest) -> PriceQuote
    public func clearCache()
}
```

### B4.1 Inputs normalised

- **`day`** = Vienna calendar day of `request.departure`. **`today`** = Vienna day of `clock()`.
- **`verbundA`, `verbundB`** = `VerbundArea.hint(stationID:)`:

  | Station id | Verbund |
  |---|---|
  | `at:41` Burgenland | VOR |
  | `at:42` Kärnten | VKG |
  | `at:43` Niederösterreich | VOR |
  | `at:44` Oberösterreich | OÖVV |
  | `at:45` Salzburg | SVV |
  | `at:46` Steiermark | STV |
  | `at:47` Tirol | VVT |
  | `at:48` Vorarlberg | VVV |
  | `at:49` Wien | VOR |
  | `wl:` | VOR |
  | `uic:`, `osm:` and others | nil, unless the StationLinker VAO lid embeds `i=A×at:NN:` |

- **`sameVerbund`** = both hints non-nil and equal. It is a *hint*; VAO is the authority (NA → not same).

### B4.2 Order of sources [DECISION]

1. **Manual** never reaches this service; the app keeps manual prices.
2. **Cache hit** (§B6) → return it.
3. **VAO first** when `travelClass == .second && sameVerbund && config.isEnabled(.vaoTariff)`.
   - Works for any date, including the past. Fast, and no Cloudflare in front of it.
   - `statusCode == "OK"` → `.liveVerbund` quote (§B5.2). Done.
   - `NA` → negative-cache for 24 h and continue.
4. **Shop** when `config.isEnabled(.oebbShop)`. Plan per §B4.3, policy per §B4.4.
5. **Throw** the most informative error: `.blocked` > `.rateLimited` > `.noPrice` > `.offline` > others.

   `quote()` then falls back to `offlineQuote()`:
   - `FareEstimator.estimate(from: Station, …)` when both endpoints are app stations;
   - else `estimate(from: GeoPoint, to: GeoPoint, …)` with the endpoint coordinates;
   - else a 0-amount `.distanceModel` quote with explanation „Kein Preis verfügbar – bitte eintragen“.

**Discount:** the Verbund path ignores `discount` [ASSUMED: Vorteilscard does not reduce Verbund single tickets]. The explanation then says „Verbundtarif · ohne Vorteilscard-Ermäßigung“. The shop path sends the card.

### B4.3 Shop plan [DECISION]

```
if let journey = request.journey, let dep = first ride leg planned departure, dep > now + 2 min:
    plan = .connection(journey, at: dep, tier: LeadTimeTier.tier(departure: dep, now: now))
else if day > today:
    plan = .relation(at: request.departure, tier: LeadTimeTier.tier(...))          // advance tier
else if day == today || TariffPeriods.same(day, today):                           // proxy = today's price
    let at = max(request.departure, now + 10 min)
    plan = (Vienna day of at == today) ? .relation(at: at, tier: .travelDay) : .skip("Heute keine Abfahrt mehr")
else:
    plan = .skip("Anderer Tarifzeitraum")
```

**`TariffPeriods`** boundaries are `catalog.fareIndex[].validFrom` plus `relations.validFrom` (2025-12-14) [DECISION]. Two days are in the same period when no boundary lies in `(min, max]`.
- The proxy is valid because the shop price for a relation on the day of travel only changes at tariff changes [ASSUMED, consistent with the table matching the same-day shop price: Wien–Salzburg 67,70 and Graz–Wien 44,30 LIVE].

**Executing `.connection`:**
- Timetable at `dep` with `from`/`to` = shop stations of the journey's first and last **ride** leg (addresses and POIs are skipped).
- **Match** the shop connection with `from.departure == dep (minute)` and `to.arrival == planned arrival of the last ride leg (minute)`.
  - Tie-break: a section `category.number ∈ {Line.trainNumber}`.
  - If nothing matches the departure minute, the connection is not sold by ÖBB, e.g. WESTbahn [LIVE]. Fall back to `.relation(at: dep, tier)` with explanation suffix „WESTbahn-Tarif nicht verfügbar – ÖBB-Standardticket als Vergleich“ when any ride leg has `category == "WB"`.

**Executing `.relation`:**
- Timetable at `at` with `count: 3`, **pick the fastest** connection (minimum `duration`) to avoid detour variants, then offers.

Then `ShopOfferSelector.standardFare(offers, travelClass)`.

### B4.4 Policy on the shop result [DECISION]

Let `T` = the offline table price for the same request (`relations.price × fareFactor(day)`, class and discount applied, as in `FareEstimator`), or nil.

| Shop owner | Tier | Condition | Result |
|---|---|---|---|
| Verbund (≠ „ÖBB“) | any | – | `.liveOebb`, provider = owner. Verbund prices do not depend on lead time [LIVE VAO past/future equal]. |
| ÖBB | travelDay | plan `.relation`, `T != nil`, `shop > T × 1.15` | `.table` with T; alternative „ÖBB-Ticketshop € X (andere Route)“. This is the detour guard. |
| ÖBB | travelDay | otherwise | `.liveOebb` |
| ÖBB | advance | `T != nil` | `.table` with T (day-of-travel basis D3); alternative „Vorverkauf heute € X“ |
| ÖBB | advance | `T == nil` | `.liveOebb` with `leadTime` set; explanation „Vorverkaufspreis (heute gekauft)“ |

- Every quote carries `fetchedAt` (except pure table), `leadTime`, `connectionID`, `shopURL` (§B3.7) and `alternatives`. When T exists and differs by ≥ € 0,05, add T as a „Tarif-Tabelle“ alternative.

### B4.5 Explanation strings (German, exact)

| Case | Explanation |
|---|---|
| liveOebb, ÖBB | „Standard-Ticket {1./2.} Kl. · ÖBB-Ticketshop · abgefragt {HH:mm}“ (+ „ · mit Vorteilscard“) |
| liveOebb, Verbund | „{productName} · über ÖBB-Ticketshop · abgefragt {HH:mm}“ |
| liveVerbund | „{productName} · {fareSet} · Verkehrsauskunft Österreich“, e.g. „VVT Einzelticket · VVT 14 Zonen · Verkehrsauskunft Österreich“ |
| table (detour / advance) | „ÖBB-Standardticket {n}. Kl. · Tarif ab {dd.MM.yyyy}“, i.e. the existing `FareEstimator` text |
| proxy (past day, same tariff) | append „ · Preis von heute (gleicher Tarif)“ |

## B5. VAO Verbund tariff (`VerbundTariffClient`, actor)

### B5.1 Request [LIVE `FX/vao/*`]

**Endpoint:** `POST https://anachb.vor.at/hamm/gate`. Envelope from `config.vao`:

```json
{"lang":"deu","ver":"1.59","ext":"VAO.22","auth":{"type":"AID","aid":"wf7mcf9bv3nv8g5f"},
 "client":{"id":"VAO","type":"WEB","name":"webapp","l":"vs_anachb","v":10022},
 "svcReqL":[{"meth":"TripSearch","req":{
   "depLocL":[{"type":"S","lid":"A=1@L=470122200@"}],"arrLocL":[{"type":"S","lid":"A=1@L=470118700@"}],
   "outDate":"20261012","outTime":"080000","outFrwd":true,"numF":2,
   "getPasslist":false,"getPolyline":false,"getTariff":true,
   "trfReq":{"jnyCl":2,"tvlrProf":[{"type":"E"}],"cType":"PK"}}}]}
```

- `/bin/mgate.exe` answers 307 → `/hamm/gate`. Call `/hamm/gate` directly.
- The regional instances `smartride.vvt.at`, `verkehrsauskunft.ooevv.at` and others give identical prices [LIVE]; they are not used.
- **LocMatch** uses the same envelope with `{"meth":"LocMatch","req":{"input":{"loc":{"type":"S","name":"<q>"},"maxLoc":5,"field":"S"}}}` [LIVE `arch_vao_locmatch_eferding`].
- Reuse WP-A's envelope encoder and raw mirrors (`HafasEnvelope`, `HafasRaw`). **Do not use** ÖBB `ProductMask` or `cls` → mode mapping on VAO responses; the bitmasks differ.

### B5.2 Response → quote

- For each `outConL[i].trfRes`:

  | `statusCode` | Meaning |
  |---|---|
  | `"OK"` | `totalPrice{amount (cents), currency}`. The fare is the `fareSetL[].fareL[]` entry whose `price.amount == totalPrice.amount`, first match. |
  | `"NA"` | `statusText` explains. Not priced. |

- **Golden products:**

  | Relation | Product | Fare set | Price |
  |---|---|---|---|
  | St. Anton–Innsbruck | „Einzelticket“ | „VVT 14 Zonen“ | 2200 |
  | Wien Hbf–Wr. Neustadt | „Einzelfahrt VOR + Wien Kernzone“ | „VOR“ | 1480 |
  | Linz–Wels | „Einzelfahrt“ | „OÖVV 5 Zonen“ | 760 |
  | Klagenfurt–Villach | „Einzelkarte Erwachsene“ | „VKG 7 Zonen“ | 1050 |
  | Bregenz–Feldkirch | „Vollpreis - 60/120 Minuten“ | „VVV MAXIMO“ | 960 |

- **`provider`** = first whitespace-separated token of the fare set name: VVT, VOR, OÖVV, VKG, VVV, SVV, STV.
- **`productName`** = the trimmed fare name. Prefix it with the provider unless the name already contains it, e.g. „VVT Einzelticket“, „Einzelfahrt VOR + Wien Kernzone“.
- **Same price on all connections:** take the first OK connection [LIVE].
- **No OK connection** → `.noPrice("NA")`.
- **svc `LOCATION`** → `StationLinker.invalidate` and `.hafas(code:"LOCATION")`.

**Open item:** VAO returns „1 Fahrt WIEN“ = € 3,00, while the catalog `cityFares[wien] = 3,20` [LIVE `vao_tripsearch_tariff_wien-kernzone_wienhbf-wienwest`]. [DECISION] `estimateLive` skips live pricing for `.cityTicket` estimates (contract code). The catalog stays authoritative for city hops until the tariff owner resolves this (§G Q2).

```swift
public actor VerbundTariffClient: VaoLocationSearching {
    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth)
    public func update(config: LiveConfig)
    public struct Fare: Sendable, Hashable { public var amountEUR: Double; public var provider: String; public var productName: String; public var fareSet: String }
    public func singleFare(fromLid: String, toLid: String, departure: Date) async throws -> Fare
    public func vaoLocations(_ query: String) async throws -> [Location]
}
```

## B6. Caching (`PriceCache`) [DECISION]

| Kind | Key | TTL |
|---|---|---|
| Relation quote | `rel` · fromKey · toKey · yyyy-MM-dd · class · discount, joined with `\|` | 24 h |
| Connection quote | `con` · `Journey.id` · class · discount, joined with `\|` | 24 h |
| Negative (VAO NA, shop noPrice) | `neg` · provider · fromKey · toKey · day, joined with `\|` | 24 h (NA) / 1 h (noPrice) |

- `fromKey = stationID ?? "eva:\(hafasExtId)" ?? "name:\(normalize(name))"`. `toKey` is built the same way.
- **Storage:** in memory, plus a JSON file at `cacheURL` (app: `Caches/Live/prices.json`). At most 500 entries with LRU eviction. Write-behind with ≤ 1 write per 5 s.
- **Never cache errors** other than the negative cases above.
- **Invalidation:**
  - `update(config:)` keeps the cache.
  - `update(estimator:)` clears entries whose source is `.table`.
  - `clearCache()` is wired to Settings „Live-Cache leeren“.

**Price-flow budget:** total 12 s (`withTimeout`). Exceeding it throws `.timeout`, and the app shows the offline value with the „Offline · Tarif-Tabelle“ badge.

**Request count per quote:**

| Situation | Requests |
|---|---|
| Cold, shop path | token + init + timetable + offers = 4, plus 0–1 LocMatch |
| Warm session | 2 |
| VAO path | 1 |

## B7. `FareEstimator` integration (contract + patch, WP-B owns afterwards)

- **`FareEstimate.Method`** gains `.liveOebb` and `.liveVerbund`. **`FareEstimate.quote: PriceQuote?`** is added with default nil.
  - Both are source-compatible. The app only compares with `==`; no exhaustive switches exist (grep verified).
- **`FareEstimator.estimateLive(from:to:mode:travelClass:discount:date:journey:live:) async -> FareEstimate`** (contract):
  - Returns the offline estimate when `live == nil`, for `.cityTicket`, or on any live error.
  - It never throws.
  - All existing synchronous `estimate(...)` APIs and the 24 existing tests stay unchanged [verified in `$OEBB/contracts`].
- **`TripEditorModel`** (WP-F) uses `estimateLive` through `LiveDataService.priceProvider` (§E5).

---

# PART C: Coverage and presentation logic (WP-C)

## C1. File layout

```
Live/Coverage/CoverageModels.swift        CONTRACT (Step 0)
Live/Coverage/CoverageRuleSet.swift       WP-C  Decodable model of coverage_rules.json (schemaVersion 1)
Live/Coverage/CoverageEvaluator.swift     WP-C  rule engine
Live/Coverage/CoverageInputMapper.swift   WP-C  Leg/Journey → CoverageLegInput (StationIndex for state/country)
Live/Presentation/PresentationModels.swift CONTRACT (Step 0)
Live/Presentation/RealtimePresentation.swift   WP-C
Live/Presentation/LinePresentation.swift       WP-C  plate/title texts
Live/Presentation/DisplayNames.swift           WP-C
Live/Presentation/JourneyPresentation.swift    WP-C  bar segments, transfers, notices, meta line, VoiceOver text
Live/Presentation/JourneyMetrics.swift         WP-C  dominant mode, distance, covered segment
Live/Presentation/LiveJourneySnapshotBuilder.swift WP-C
App/Resources/coverage_rules.json         WP-C  (copy of FX/coverage/coverage_rules.json; the app loads it like stations.json)
```

## C2. Coverage engine (port of `$OEBB/official/client.py` `Coverage`)

### C2.1 Rule file

- **File:** `coverage_rules.json` (62 KB, schemaVersion 1).
- **Top-level keys:** `rules[27]`, `acceptedOperatorsRail[15]`, `gemeinschaftsbahnhoefe[9]`, `transitSections[6]`, `regionalScopes{tirol, vbg, sbg, ooe, vor-metropolregion, vor-region, wien, stmk, ktn}`, `lineIdPrefixToVerbund`, `clsTables`, `extras`, `ui`.
- **Decode the match nodes as a recursive enum.** Unknown **documentation** keys are ignored: `verification`, `note`, `plus`, `_*` and `sources`.
  - The Python reference crashes on `regionalScopes.wien.include.plus` („unknown match key plus“); found while staging goldens. The Swift port must ignore it.
- **Unknown operator keys** make the containing node evaluate to `false`, logged once. Never crash.

### C2.2 Input mapping (`CoverageLegInput(leg:stations:)`)

| Input field | Source |
|---|---|
| `legType` | `.ride` → `"JNY"`, `.walk` → `"WALK"`, `.transfer` → `"TRSF"` |
| `operator` | `line.operatorName` |
| `productName` | `line.fullName ?? line.name` |
| `category` | `line.category` (catOut trimmed) |
| `categoryLong` | `line.categoryLong` |
| `cls` | `line.productClass` |
| `clsScheme` | `"oebb-mgate"` |
| `admin` | `line.admin` |
| `lineId` | `line.lineId` |
| `line` | `line.lineNumber` |
| `remarks` | texts of `leg.remarks` (all kinds) |
| `from`, `to` | `leg.origin`, `leg.destination` |
| `passList` | `leg.intermediateStops` |

Each stop is built as:
- `country = location.countryCode?.uppercased()`;
- `state` = the `Station.state` of the nearest `StationIndex` station within 2 km (as in the reference `nearest_state`);
- if `country == nil` and the state is an AT state → `"AT"`; if the state is `"X"` → `"XX"`.

### C2.3 Operators (exact semantics of the reference `m1`)

| Operator | Semantics |
|---|---|
| `anyOf` / `allOf` / `not` | Boolean combinators. Sibling keys in one node are AND-combined. |
| `always` | true |
| `legTypeIn` | `legType ∈ v` |
| `operatorRegex`, `productNameRegex`, `categoryLongRegex` | `NSRegularExpression` (pattern verbatim, inline `(?i)`) on the field; nil field → false |
| `remarkRegex` | any remark matches |
| `stopNameRegex` | any of from, to and passList matches |
| `categoryIn`, `lineIn` | trimmed value ∈ v |
| `lineIdPrefix` | any prefix |
| `adminPrefix` | single string prefix |
| `clsAny` | `{scheme: [bits]}` → `(cls & bit) != 0` for `leg.clsScheme` only |
| `stopStateIn` = `anyStopStateIn` | any stop's state ∈ v |
| `allStopsStateIn` | all stops' states ∈ v |
| `anyStopStateNotIn` | any stop with a **non-nil** state ∉ v. An unknown state is not evidence. |
| `anyStopOutsideAustria` | `v == any(endpoint !atOrGbf)` |
| `allStopsInAustriaOrGemeinschaftsbahnhof` | `v == all(stops atOrGbf)` |
| `boardAndAlightInAustria` | `v == (from atOrGbf && to atOrGbf)` |
| `onTransitSection` | `from atOrGbf && to atOrGbf && any passList stop !atOrGbf` |
| `operatorRegexFrom` | any `acceptedOperatorsRail[].regex` matches the operator |
| `ruleRef` | evaluate the referenced rule's `match` |

- **`atOrGbf(stop)`**: country starts with `AT`, or a Gemeinschaftsbahnhof lies within 400 m or matches its `nameRegex`.

### C2.4 Evaluation

**KlimaTicket Ö (`.oe`):**
- Take the rules in ascending `priority`, the first one that `applies` and matches wins.
- `applies`: `appliesTo` contains `"*"`, or `"oe"` for scope `.oe`, or `"regional:*"` / `"regional:<key>"` for regional scopes.
- `resultTirol` overrides when from or to has state `T`.
- `partial` → compute `lastCoveredStop`: walk from, then passList, then to, and stop at the first stop that is not `atOrGbf`. If there is none → `notCovered` with badge „Nicht im KlimaTicket (Auslandsabschnitt)“.
- **`toll-surcharge` scope check:** if the remark quotes stop names in `"…"` and none of their first words occurs in this leg's stop names → `covered`, badge „Inklusive“. [LIVE quirk: the Bus 260 toll remark is attached to Landeck–Ischgl legs too.]
- No rule matches → `unknown`.

**Regional scopes:** port `classify_regional` verbatim. Order:
1. Hard exclusions: priority < 20 with result `notCovered` or `discount`. Skip rule ids starting with `cross-border`, `transit-`, `freilassing` or `night-train`.
2. `scope.include`.
3. `scope.exclude`. An `onTransitSection` exclude uses the transit heuristic.
4. Not included → `unknown` if a from/to state is nil, else `notCovered` with badge „Außerhalb des Geltungsbereichs“.
5. Remaining `*` rules below priority 60.
6. Otherwise `covered`, badge „Inklusive“.

**Ticket scope (`CoverageEvaluator.scope(forProductID:)`):**
- `oe-` → `.oe`.
- Else the first `regionalScopes[key].productIdPrefixes` entry that prefixes the id → `.regional(key)`.
- Else `.unsupported`, which makes every ride leg `.unknown`. Examples: `tirol-innsbruck`, `tirol-regionen`, `vbg-lokal-*`.

### C2.5 Aggregation (`ui.tripAggregation`)

Over ride legs only:
- none → `notApplicable`;
- all results ⊆ {covered, surcharge} → `covered`;
- all `notCovered` → `notCovered`;
- `unknown` present and none of {notCovered, partial, discount} → `unknown`;
- else `partial`.

`JourneyCoverage.lastCoveredLegIndex` / `lastCoveredStopName`: the longest **prefix** of ride legs that are covered or surcharge. A `partial` leg contributes its `lastCoveredStop`.

### C2.6 API

```swift
public final class CoverageEvaluator: Sendable {
    public init(rulesJSON: Data, stations: StationIndex) throws
    public func scope(forProductID id: String) -> TicketScope
    public func evaluate(_ input: CoverageLegInput, scope: TicketScope) -> LegCoverage
    public func evaluate(_ journey: Journey, scope: TicketScope) -> JourneyCoverage
}
```

- Regexes are precompiled at init. Construction must not crash on a rule file of a newer schema: throw instead.

## C3. Presentation logic (all pure; expected values from `FX/ux/vm_*.json` and the UX spec)

### C3.1 Realtime label (`RealtimePresentation.label(_ event: StopEvent) -> RealtimeLabel`)

- `isCancelled` → `.cancelled`, „Fällt aus“.
- No realtime → `.scheduled`, text nil.
- `Δ = round((realtime − planned) / 60)`:
  - Δ ≤ 0 → `.onTime`; „pünktlich“ when Δ == 0, else „HH:mm (Δ)“.
  - 1 ≤ Δ ≤ 4 → `.late`, „HH:mm +Δ“.
  - Δ ≥ 5 → `.veryLate`, „HH:mm +Δ“.
- **Golden:** `FX/ux/vm_trips_landeck_ischgl_delays.json` (+3 / +4) and `vm_trips_innsbruck_lech.json` (`dep.state onTime`, `arr.state scheduled`).

### C3.2 Lines (`LinePresentation`)

Port of the reference `ux/client.py product()`, **with fixes**.

**`plate(line)`:**

| Line | Plate |
|---|---|
| long-distance category ∈ {RJX, RJ, ICE, IC, EC, EN, NJ, IR, WB, D} | category |
| bus | `lineNumber` ?? `name` without „Bus“ ?? „Bus“ |
| tram | „T \(lineNumber)“ |
| S-Bahn | „S \(lineNumber)“ |
| metro | `lineNumber` when it already starts with „U“, else „U\(lineNumber)“ |
| regional rail | „\(category) \(lineNumber)“ or category |

- The metro rule fixes a bug in the reference, which would print „UU6“.

**`title(line)`:**
- Long-distance: „RJX 19910“.
- Bus: „Bus 760“.
- Regional with a different train number: „REX 51 (Zug-Nr. 1628)“.

### C3.3 Display names (`DisplayNames.make(_ raw: String) -> DisplayName`)

- A trailing `(…)` becomes `sub`.
- `St.X` becomes `St. X`.
- A trailing „ Bahnhof“ is dropped.
- „Hauptbahnhof“ becomes „Hbf“.
- **Golden:** „Langen am Arlberg Bahnhof (Vorplatz)“ → name „Langen am Arlberg“, sub „Vorplatz“ (`vm_trips_innsbruck_lech.json`).

### C3.4 Journey presentation (`JourneyPresentation`)

```swift
public struct ConnectionSummary: Sendable, Hashable, Identifiable {
    public var id: String                       // Journey.id
    public var departure: RealtimeLabel; public var arrival: RealtimeLabel
    public var plannedDeparture: Date?; public var plannedArrival: Date?
    public var durationMinutes: Int; public var durationText: String      // "2 h 16 min", "41 min"
    public var changes: Int; public var changesText: String               // "direkt" / "1 Umstieg" / "2 Umstiege"
    public var departurePlatform: PlatformLabel?                           // {label "Gl."|"Steig", planned, realtime, changed, display}
    public var bar: [JourneyBarSegment]
    public var transfers: [TransferInfo]
    public var metaLine: String                                            // "ab Gl. 3 · 1 Umstieg · Langen am Arlberg"
    public var topNotice: Notice?; public var notices: [Notice]
    public var isPast: Bool; public var isCancelled: Bool
    public var tags: Set<Tag>                                              // .fastest, .fewestChanges
}
public struct PlatformLabel: Sendable, Hashable { public var label: String; public var planned: String?; public var realtime: String?; public var changed: Bool; public var display: String }
public enum JourneyPresentation {
    public static func summaries(_ journeys: [Journey], now: Date) -> [ConnectionSummary]   // also assigns tags
    public static func transfers(_ journey: Journey) -> [TransferInfo]
    public static func notices(_ remarks: [Remark]) -> [Notice]
    public static func accessibilityLabel(_ s: ConnectionSummary, priceText: String?) -> String
}
```

**Bar segments:**
- ride → `minutes` of the leg;
- walk → walk minutes;
- wait → the gap between legs.
- `fraction = minutes / total`, where the fractions sum to 1.
- **Golden** `vm_trips_innsbruck_lech.json[0].bar`: ride 76, walk 1, wait 37, ride 22; fractions 0.5588, 0.0074, 0.2721, 0.1618 (±0.0005).

**Transfers:**
- `buffer = nextRide.departure.effective − prevRide.arrival.effective − walkMinutes`.
- Risk: ≥ 5 min `.ok`, 2…4 min `.tight`, < 2 min `.atRisk`.
- Texts: „{buffer+walk} min Umstiegszeit“ / „Knapp: {buffer} min zum Umsteigen“ / „Anschluss gefährdet“.
- **Golden:** at Langen am Arlberg, walk 1, buffer 37, ok, „38 min Umstiegszeit“.

**Notice severity:**
- `crowd` if title or text contains „Auslastung“, „Starker Reisetag“ or „Sitzplatzreservierung“.
- else `critical` if priority ≤ 50 [ASSUMED threshold], or the text contains „Schienenersatzverkehr“ or „fällt aus“.
- else `warning` for disruptions.
- `.attribute` and `.info` remarks → `info`, shown in the detail only.
- `topNotice` = the highest severity, then the lowest priority.
- **Golden:** `vm_trips_innsbruck_lech.json[0].notices[0].severity == "crowd"`.

**Tags:**
- `fastest`: the first non-past, non-cancelled journey with the minimum duration.
- `fewestChanges`: the first with the minimum changes, only when it is a different journey.

**Attributes** (detail chips) from remark codes:

| Codes | Chip |
|---|---|
| WV | wifi |
| BR | fork.knife |
| HD | moon |
| KN | figure.2.and.child.holdinghands |
| RO, EF, OC | figure.roll |
| FK, FR | bicycle |
| UA | briefcase |

At most 6. Order as in `vm_trips_innsbruck_lech.json[0].legs[0].attributes`.

### C3.5 Journey metrics (`JourneyMetrics`)

- **`dominantMode(journey) -> TransportMode`:** the mode of the ride leg with the longest duration. Train beats bus on ties.
- **`distanceKm(journey) -> Double?`:**
  1. Sum of the polyline lengths when every ride leg has a polyline;
  2. else the sum of haversines between consecutive stopovers of ride legs, plus walk distances;
  3. else the haversine origin→destination × `FareModel.railDistance` factor.

  Rounded to 0.1.
- **`lineSummary(journey) -> String`:** „RJX 19910 · Bus 760“, using titles.
- **`coveredSegment(journey, coverage) -> (from: Location, to: Location)?`:** for `.partial`, the journey origin → the last covered stop, as a station `Location`. Used to price only the Austrian or covered part (§E6).

### C3.6 Live journey snapshot (`LiveJourneySnapshotBuilder.make(journey:quote:now:) -> LiveJourneySnapshot`)

| Phase | Condition | Next event |
|---|---|---|
| `beforeDeparture` | now < first departure | the departure |
| `riding` | inside a ride leg | the arrival of that leg; if a transfer follows, the transfer departure |
| `transferring` | between ride legs | the next departure |
| `arrived` | now ≥ final arrival − 1 min | – |
| `cancelled` | any ride leg cancelled | – |

- **`progress`** = elapsed / total, realtime-aware, clamped to 0…1.
- **`staleAfter`** = next event + 2 min.
- **Titles:**
  - „Abfahrt in {n} min · Gl. 3“
  - „Umsteigen in St. Anton“
  - „Ankunft Lech 14:09“
  - „Angekommen in Lech“

## C4. Coverage and presentation tests

See §D2 (WP-C list).

---

# PART D: Step 0, fixtures, test plan

## D0. Step 0 (orchestrator, about 5 min, before any work package starts)

1. Create branch `wip/oebb-live` from the integrated head.
   - **Recommendation:** first merge the open Phase-2 branches `wip/p2-*` and `wip/polish-*` (Risk R6). Otherwise expect conflicts in `RootView.swift`, `TripEditorModel.swift`, `DashboardView.swift`, `SettingsView.swift` and `SyncService.swift`.
2. Run `bash $OEBB/contracts/apply_contracts.sh /home/user/KLIMATICKET-APP`. It is idempotent, dry-run verified on a scratch copy, and does four things:
   - copies `CORE/Live/{Transport,Domain,Config,Pricing,Coverage,Presentation}/*` (the contracts);
   - applies `FareEstimator.patch`;
   - copies `$OEBB/repo-fixtures/` → `FX/` (118 files, 2.3 MB minified, redaction-checked);
   - adds `resources: [.copy("Fixtures")]` to the test target in `Packages/KlimaCore/Package.swift`;
   - copies `Tests/KlimaCoreTests/Live/Support/LiveContractTests.swift` (4 contract tests).
3. Run `swift test --package-path Packages/KlimaCore`. All 28 tests (24 existing + 4 contract) must pass; verified in the dry run.
4. Make sure `docs/OEBB_LIVE.md` (this spec) is present. The architect placed it uncommitted; commit it with the contracts.
5. Commit „ÖBB Live: contracts, fixtures, spec“. **Every work package branches from this commit.**

## D1. Fixtures: layout, formats, ownership

| Folder | Owner (may add files) | Format |
|---|---|---|
| `FX/hafas/` | WP-A | `<scenario>.request.json` = `{_meta{scenario, fetchedAt, httpStatus, seconds, url, method, headers, responseHeaders}, body}`; `<scenario>.response.json` = raw HCI response |
| `FX/shop/` | WP-B | `{_meta{captured_at, method, url, status, latency_s, response_headers, jwt_claims?}, request{headers, body}, response}`. Cloudflare page: `{_meta, response_headers, response_title, response_body_html_ip_redacted}` |
| `FX/vao/` | WP-B | as shop; `request` = the full HAFAS envelope |
| `FX/coverage/` | WP-C | `coverage_rules.json` (schemaVersion 1); `synthetic_cases.json` = `{cases:[{label, family, expected, leg: CoverageLegInput, engineResult, rule}]}` (14 cases) |
| `FX/ux/` | WP-C | view-model expectations from `$OEBB/ux/client.py` |
| `FX/golden.json`, `FX/MANIFEST.json` | nobody (read-only) | keys `hafas/<scenario>`, `shop/<name>`, `vao/<name>`, `coverage/journeys`. To add goldens, create `FX/<folder>/golden_extra.json`. |

Secrets: tokens, session ids, egress IPs and `__cf_bm` cookies are redacted (verified by scan). The `aid` values in the HAFAS and VAO bodies are public web-app identifiers.

**Index (118 files):**
- **`FX/hafas/`** (34 scenarios × request+response, 1,561 KB):
  - LocMatch, LocGeoPos, ServerInfo: `locmatch_innsbruck`, `locmatch_st_anton`, `locmatch_wien_westbahnhof`, `locmatch_batch_mixed`, `locmatch_batch_2_nonfuzzy_nomatch`, `locgeopos_nearby_innsbruck_hbf`, `serverinfo`
  - TripSearch: `tripsearch_st_anton_innsbruck`, `tripsearch_innsbruck_lech_bus`, `tripsearch_innsbruck_wien_hbf`, `tripsearch_wien_westbf_salzburg`, `tripsearch_graz_klagenfurt_koralm`, `tripsearch_overnight_dst_change_wien_innsbruck`, `tripsearch_paging_later_graz_klagenfurt`, `tripsearch_paging_earlier_graz_klagenfurt`, `tripsearch_getTariff_true_innsbruck_wien`, `tripsearch_vienna_urban_address_to_poi`, `tripsearch_tyrol_bus_landeck_ischgl`, `tripsearch_arrive_by_innsbruck_wien`, `tripsearch_via_linz_maxchg0_rail`, `tripsearch_bike_filter_BC`, `tripsearch_accessibility_meta_filter`, `legacy_mgate141_tripsearch_st_anton_innsbruck`
  - Refresh, details, boards, disruptions: `reconstruction_innsbruck_lech_outReconL`, `journeydetails_rjx133_koralm_polyline`, `stationboard_dep_innsbruck_hbf`, `stationboard_arr_wien_hbf`, `stationboard_dep_wien_hbf_rail_90min`, `himsearch_disruptions_rail`
  - Errors: `batch_edge_cases_errors`, `error_parse_invalid_enum_rtmode`, `error_parse_unknown_field`, `error_parse_reconstruction_ctxRecon_v188`, `error_auth_invalid_aid`
- **`FX/shop/`** (29 files, 253 KB):
  - Wien–Salzburg 2026-10-10: `shop_wien-salzburg_2026-10-10_{01_anonymousToken, 02_initUserData, 03_stations_0, 03_stations_1, 05_timetable, 06_prices, 07_offers_v6_adult, 08_offers_v6_vorteilscard, 09_offers_v6_child8}`
  - Wien–Salzburg same day: `shop_wien-salzburg_sameday_2026-10-09_{05_timetable, 07_offers_v6_adult}`
  - Inside a Verbund: `shop_ibk-hall_2026-10-10_{05_timetable, 07_offers_v6_adult}`
  - Sparschiene: `shop_graz-wien_sparschiene_2026-10-12_{05_timetable, 06_prices, 07_offers_v6_adult}`
  - Minimal headers: `shop_minimal-headers_no-travelAction_timetable_wien-salzburg_2026-10-09T1600`, `shop_minimal-headers_offers_v6_wien-salzburg_2026-10-09T1600`
  - Other dates: `shop_offers_v6_wien-salzburg_2026-11-20T1400_RJX`, `shop_timetable_wien-salzburg_2026-12-15T1400`
  - Past departure: `shop_{timetable, prices, offers_v6}_past_yesterday_wien-salzburg_2026-10-08T0800`
  - Errors: `shop_error_403_cloudflare_block_page`, `shop_error_440_session_not_initialised_timetable`, `shop_token_expiry_after_330s_timetable`
  - Architect verifications: `arch_shop_timetable_hafas-station_minimal-passenger_ibk-landeck`, `arch_shop_offers_v6_minimal-passenger_ibk-landeck`, `arch_shop_offers_v6_minimal-vorteilscard_graz-wien`
- **`FX/vao/`** (15 files, 395 KB):
  - `vao_tripsearch_tariff_{stanton-ibk, ibk-hall, ibk-hall_past_2026-10-08, ibk-hall_after-fare-change_2026-12-15, ibk-landeck, wien-salzburg, graz-wien, wien-kernzone_wienhbf-wienwest, wien-wrneustadt, wienwest-stpoelten, linz-wels, klagenfurt-villach, bregenz-feldkirch}`
  - Architect verifications: `arch_vao_locmatch_eferding`, `arch_vao_tripsearch_tariff_eva-lid_eferding-linz`
- **`FX/coverage/`**: `coverage_rules`, `synthetic_cases`
- **`FX/ux/`**: `vm_trips_innsbruck_lech`, `vm_trips_st_anton_innsbruck`, `vm_trips_landeck_ischgl_delays`, `vm_board_innsbruck_hbf`

### D1.1 Key golden values (excerpt of `FX/golden.json`)

| Key | Value |
|---|---|
| `hafas/tripsearch_st_anton_innsbruck` | 4 journeys. Journey 0: 12:33+02:00 → 13:43+02:00, 4,200 s, 0 changes, RJX (cls 1, train, operator „Nahreisezug“), platform 3 (no change), refresh token `¶HKI¶…`, 4 stopovers, **889** polyline points |
| `hafas/tripsearch_innsbruck_lech_bus` | journey 0: legs ride, walk, ride: „RJX19960“ + „Bus 750“ (Österreichische Postbus AG), 8,160 s, 1 change, stopovers [4, 10] |
| `hafas/tripsearch_overnight_dst_change_wien_innsbruck` | NJ 19946: 2026-10-24T22:44+02:00 → 2026-10-25T05:05+01:00 = 26,460 s |
| `hafas/tripsearch_wien_westbf_salzburg` | 8 journeys; `prodL` contains WB with cls 4096 |
| `hafas/tripsearch_graz_klagenfurt_koralm` | journey 0: 41 min (2,460 s), realtime departure +3 min |
| `hafas/journeydetails_rjx133_koralm_polyline` | „RJX 133“ → „Venezia Santa Lucia“, 12 stopovers, 3,589 points, (48.18505, 16.37701) … (45.44138, 12.32044) |
| `hafas/stationboard_dep_innsbruck_hbf` | 30 entries; first „Bus F“ → „Rum Bahnhst“, planned 11:22, realtime 11:24 (+120 s), Steig F |
| `hafas/batch_edge_cases_errors` | svc errors `[LOCATION, H890, PARAMETER, H9381]` |
| `hafas/error_auth_invalid_aid` | top `AUTH` „HCI Core: Authorization fail“ |
| `hafas/tripsearch_getTariff_true_innsbruck_wien` | `shopLink` = `https://shop.oebbtickets.at/de/ticket?cref=scotty&connectionDatetimeDeparture=2026-10-09T13:58&connectionDatetimeArrival=2026-10-09T18:32&connectionOrigEva=8100108&connectionDestEva=8103000&stationOrigName=Innsbruck%20Hbf&stationDestName=Wien%20Hbf%20(Bahnsteige%203-12)` |
| `shop/…2026-10-10_07_offers_v6_adult` | 2nd class 66,40 Standard-Ticket ÖBB; 1st 129,50 |
| `shop/…sameday…_07` | 67,70 / 132,10 |
| `shop/…_08_vorteilscard` | 33,20 / 64,80 |
| `shop/shop_ibk-hall…_07` | 4,70 VVT Einzelticket (MULTIPLE 42,60 excluded); no 1st class |
| `shop/…graz-wien_sparschiene…_07` | FLEX 43,50 (cheaper NON-FLEX ignored); 1st 84,70 |
| `shop/…past_yesterday…offers` | `offerError: true` |
| `shop/arch_…ibk-landeck` | 2nd 22,00 VVT · 1st 34,40 ÖBB |
| `shop/arch_…vorteilscard_graz-wien` | 22,20 reduction „1× Vorteilscard Classic“ · 1st 43,20 |
| `vao/*` | stanton-ibk 2200 „Einzelticket“ / „VVT 14 Zonen“ · ibk-hall 470 (also past and 2026-12-15) · wien-salzburg NA · graz-wien NA · wien-kernzone 300 „1 Fahrt WIEN“ · wien-wrneustadt 1480 · wienwest-stpoelten 1750 · linz-wels 760 „OÖVV 5 Zonen“ · klagenfurt-villach 1050 „VKG 7 Zonen“ · bregenz-feldkirch 960 „VVV MAXIMO“ |
| `coverage/journeys` | per fixture × family (oe, tirol): `overall` + per-leg `result`/`rule` from the reference engine |

## D2. Linux fixture test plan (CI job „KlimaCore Tests (Linux)“, `swift test --no-parallel`)

Tests go under `Packages/KlimaCore/Tests/KlimaCoreTests/Live/<Area>/`. XCTest (as the existing tests), one file per bullet group. Test helpers live in `Live/Support/` (owned by WP-A; others may add helper files there with their own WP prefix, e.g. `PricingTestSupport.swift`).

**Line-name comparison rule** (used in the golden checks below): compare `Line.name` to golden `rideLines` **with spaces removed** on both sides. Golden uses HAFAS `nameS`, which is „RJX19915“; ours is „RJX 19915“.

**WP-A: `Live/HAFAS/`**
1. **HafasTimeTests**
   - `("20261009","111600",120)` → 2026-10-09T09:16:00Z.
   - `"01004100"` day offset.
   - DST golden 26,460 s.
   - Missing offset → Europe/Vienna.
   - `[dd]HHMMSS` durations.
2. **PolylineTests**
   - The Google reference string `_p~iF~ps|U_ulLnnqC_mqNvxq`@` → (38.5, −120.2), (40.7, −120.95), (43.252, −126.453).
   - Segment concatenation with de-duplication.
   - Goldens 889 and 3,589 points, with first and last points.
3. **HafasEncoderTests**: for each request kind, the encoded `svcReqL[0]` has **exactly** the key set of the fixture request. Values are equal except volatile ones (date, time, ctx, jid).
   - Paging omits `outDate`, `outTime` and `outFrwd`.
   - Arrive-by gives `outFrwd:false`.
   - `viaLocL` shape; `BC` and `META` filters; PROD value is a String.
   - `client.v` is omitted for `/gate`, a String for mgate and an Int for VAO.
   - No `null` anywhere: a regex over the JSON finds no `:null`.
4. **HafasDecodeTripSearchTests**: every TripSearch and Reconstruction fixture decodes.
   - `journeyCount`, and for the first 3 journeys: planned and realtime ISO times, `durationSec`, `changes`, leg kinds, ride categories, `cls`, modes, operators, first platform (planned and realtime), delay, refresh-token prefix, stopover counts and polyline counts all equal golden.
   - Invariants: ride legs are chronological; the polyline's first point is within 0.02° of the origin.
   - The legacy mgate fixture decodes to the same shape.
5. **HafasBoardTests**
   - Count, the first 5 entries and the `platformChanges` list equal golden.
   - `maxDelaySec` of `stationboard_arr_wien_hbf` equals golden.
   - `Board.entries` is sorted by effective time.
6. **HafasJourneyDetailsTests**: the trip golden, `Stopover.isBorder` on Tarvisio, and `index` values ascending.
7. **HafasLocationTests**
   - LocMatch goldens: types, ids, names, `isMeta`.
   - The 11-element batch.
   - Nonsense filter: query `xqzvvhjkq` in `locmatch_batch_2_nonfuzzy_nomatch`[3] → empty after filtering.
   - LocGeoPos sorted by distance.
8. **HafasRemarksTests**: HimSearch has 15 messages; the first 3 equal golden (`id`, `head`, `prio`, validity ISO). No `<` remains in `text`, and entities are decoded.
9. **HafasErrorTests** (with `FixtureTransport`)
   - The batch maps to `[.hafas(LOCATION), .noConnection, .hafas(PARAMETER), .hafas(H9381)]`.
   - AUTH on primary, then fallback serving the legacy fixture → success, and the next call goes to the fallback URL.
   - AUTH on both → `.blocked(.oebbHafas)`.
   - PARSE → `.decoding`.
   - 503 twice → one retry, then `.http`.
   - An HTML body → `.http`.
   - `killSwitch` → `.disabled`, and `recorded` is empty.
10. **ShopLinkDecodeTests**: `Journey.shopURL` equals the golden `shopLink`.
11. **ThrottleHealthTests** (fake clock and sleeper)
    - The minimum interval holds; the bucket allows 40 per minute.
    - 3 failures → circuit open 2 min; `.blocked` → 30 min.
    - `.noConnection` does not count.
12. **StationLinkerTests**
    - `uic:` direct.
    - VAO lids: `at:47:1187` → `A=1@L=470118700@`, `at:45:50002` → `A=1@L=455000200@`, `at:44:41164` → `A=1@L=444116400@`, `at:48:452` → `A=1@L=480045200@`, `wl:60201349` → `A=1@L=490134900@`.
    - LocMatch mapping with `locmatch_innsbruck` for `at:47:1187` (47.26330, 11.40085) → extId `8100108`.
    - Reverse mapping „Innsbruck Hbf“ → `at:47:1187`.
    - Disk round trip.
13. **LiveConfigTests**: round trip; the loader rejects a lower version; `isEnabled` follows the kill switch.

**WP-B: `Live/Pricing/`**
1. **ShopDecodeTests and ShopOfferSelectorTests**: all `FX/shop` goldens in §D1.1, plus `offerError` → nil fare.
2. **ShopClientFlowTests** (`FixtureTransport`, fake clock)
   - Call order token → init → timetable → offers.
   - Exact headers (`Channel: inet`, `AccessToken`, no `Cookie`).
   - Body equals §B3.2: minimal passenger, `"2026-10-10T08:00:00.000"` for 08:00 Vienna.
   - Token renewal after 240 s.
   - 401/13008 and 440/3011 → one re-init and retry.
   - 403 HTML → `.blocked`, circuit open for 30 min.
   - 429 → `.rateLimited`.
3. **VerbundTests**
   - The request equals the `vao_tripsearch_tariff_stanton-ibk` request (minus volatile date and time).
   - All VAO goldens: cents → EUR, provider, product name.
   - NA → `.noPrice`; svc LOCATION → `.hafas(LOCATION)`; trailing spaces trimmed.
   - LocMatch → lid containing `at:44:42505`.
4. **VerbundAreaTests and TariffPeriodsTests**: the §B4.1 table.
   - 2026-10-08 ≡ 2026-10-09.
   - 2026-12-12 ≢ 2026-12-13.
   - 2025-12-13 ≢ 2026-01-10.
5. **LivePriceServicePolicyTests**: real clients over `FixtureTransport`, clock = 2026-10-09T12:15 Vienna, stations from a small `StationIndex`.
   - Endpoints carry `hafasExtId` (Wien Hbf 1290401, Salzburg 8100002, Innsbruck 8100108, Landeck 8100063, Graz 8100173), so no LocMatch is needed.
   - One extra test covers resolution through the linker with `locmatch_innsbruck`.
   - The Graz→Wien Vorteilscard case reuses `shop_graz-wien_sparschiene_2026-10-12_05_timetable` for the timetable route.

   | Scenario | Expected quote |
   |---|---|
   | Ibk → Hall, same day, 2nd | VAO → 4,70 `.liveVerbund` VVT; exactly 1 VAO request, 0 shop requests |
   | Wien → Salzburg, same day | relation proxy (sameday fixtures) → 67,70 `.liveOebb` ÖBB |
   | Wien → Salzburg, tomorrow | advance: shop 66,40 → `.table` 67,70 (table) + alternative „Vorverkauf heute € 66,40“ |
   | Wien → Salzburg, 2026-10-08 (past, same tariff) | proxy → 67,70 + „Preis von heute (gleicher Tarif)“ |
   | Wien → Salzburg, 2026-12-15 | offers `offerError` → `quote()` → `.table` 67,70 × 1.035 = **70,10** |
   | Synthetic ÖBB offer 91,50 vs table 67,70 | detour guard → `.table` |
   | Ibk → Landeck, 1st class | VAO skipped → shop 34,40 Standard-Ticket |
   | Graz → Wien, Vorteilscard | shop 22,20; explanation contains „mit Vorteilscard“ |
   | Shop 403 | `quote()` → table; health open |
   | Identical second quote | 0 transport requests (cache) |
   | Transport delay 13 s (fake) | `.timeout` → offline |
   | `.connection` matching with a synthetic Journey (Wien Hbf 8103000 dep 2026-10-10T08:28 → Salzburg 10:53, trainNumber „19962“) | the offers request body contains `40b209785651ab5f…` |
   | WB journey | relation fallback; explanation contains „WESTbahn-Tarif nicht verfügbar“ |

6. **FareEstimatorLiveTests**
   - Source → method mapping.
   - `.cityTicket` never calls live (a stub counts calls).
   - A nil provider gives the offline result.
7. **ShopDeepLinkTests**: `stationOrigEva=001290401`, `stationDestEva=008100002`, `outwardDateTime=2026-10-10T08%3A28`, `cref=klimabilanz`.

**WP-C: `Live/Coverage/` and `Live/Presentation/`**
1. **CoverageRuleSetTests**
   - Decodes 27 rules, 15 operators, 9 Gemeinschaftsbahnhöfe, 6 transit sections and 9 scopes.
   - Documentation keys are ignored, including `wien.include.plus`.
   - Malformed JSON throws.
2. **CoverageSyntheticTests**: the 14 cases → `expected`.
3. **CoverageJourneyGoldenTests**: for each `golden["coverage/journeys"]` entry, decode the HAFAS fixture with `HafasCodec`, then `CoverageInputMapper`, then evaluate. Overall and per-leg results must equal golden. Compiles once WP-A's codec exists (see §W merge order).
4. **TicketScopeTests**
   - `oe-klassik` → `.oe`; `tirol-klassik` → `.regional("tirol")`; `vbg-maximo-klassik` → `vbg`; `ooe-regional-linz-klassik` → `ooe`.
   - `tirol-innsbruck` and `custom` → `.unsupported`.
5. **RealtimePresentationTests**, **LinePresentationTests** (plates RJX, 750, S 4, T 5, **U6**, CJX 5; title „REX 51 (Zug-Nr. 1628)“) and **DisplayNamesTests**.
6. **JourneyPresentationTests** against `FX/ux/vm_trips_innsbruck_lech.json[0]`:
   - bar fractions ±0.0005;
   - transfer (ok, 37 / 1, „38 min Umstiegszeit“);
   - notice severity `crowd`;
   - meta line „ab Gl. 3 · 1 Umstieg · Langen am Arlberg“;
   - „2 h 16 min“, „1 Umstieg“;
   - attribute order.

   Also `vm_trips_landeck_ischgl_delays.json` (+3/+4 states) and `vm_board_innsbruck_hbf.json` (row states, platform labels).
7. **JourneyMetricsTests**
   - Dominant mode of Innsbruck→Lech = train.
   - `lineSummary` „RJX 19960 · Bus 750“.
   - Distance by the stopover method = **110.7 km ± 0.2**: RJX 99.1 + Bus 11.6 haversine over stopovers + 35 m walk; there are no polylines in this fixture.
   - `coveredSegment` for a synthetic Wien→München RJ → (Wien, Salzburg Hbf).
8. **LiveJourneySnapshotTests**: the Innsbruck→Lech journey at fake times.

   | Time | Phase |
   |---|---|
   | 11:00 | `beforeDeparture` |
   | 11:40 | `riding`, next event „Umsteigen in Langen am Arlberg“ |
   | 12:40 | `transferring` |
   | 13:32 | `arrived` |

   `progress` is monotonic and within 0…1.

## D3. Live tests (opt-in, `KB_LIVE_TESTS=1`)

**Files:** `Tests/KlimaCoreTests/Live/LiveSmoke/HafasLiveTests.swift` (WP-A) and `PriceLiveTests.swift` (WP-B).

- Each test starts with `try XCTSkipUnless(ProcessInfo.processInfo.environment["KB_LIVE_TESTS"] == "1")`.
- **Run:** `KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --filter LiveSmoke --no-parallel`.
- **Budget:** ≤ 20 requests per run, through the real `RequestThrottle`.
- **Assertions** check structure, not exact values.
- A `.blocked`, `.rateLimited` or `.offline` result → `XCTSkip` with the reason. It never fails CI. CI does not set the variable.

**HAFAS (WP-A):**
1. LocMatch „Innsbruck Hbf“ contains extId `8100108`.
2. TripSearch `8100064`→`8100108` at now + 60 min gives ≥ 1 journey with a ride leg and a refresh token.
3. Reconstruction of that token returns the same `Journey.id`.
4. StationBoard Innsbruck over 30 min has ≥ 1 entry.
5. JourneyDetails of the first ride leg has > 100 polyline points.
6. **Assumption checks:** the legacy profile accepts `outReconL` (§A3.1). The VAO `wl:60200657` → `A=1@L=490065700@` TripSearch to Wien Westbahnhof returns `statusCode OK` (§A3.7).
7. **Via with a minimum stay** (owner request 2026-10-09): Innsbruck Hbf → Bregenz via Feldkirch, `min: 10`; every journey passes Feldkirch. `KB_LIVE_RECORD_DIR=<dir>` writes the exchange in `FX/hafas` format.

**Prices (WP-B):**
1. Shop Innsbruck→Landeck today, 2nd class: price > 0 and owner VVT.
2. The same in 1st class: owner ÖBB.
3. Shop Wien Hbf→Salzburg, 2nd class: owner ÖBB, 40 < price < 120.
4. VAO Ibk→Hall: > 0, provider VVT.

## D4. Device checklist (manual, before the first release with Live)

1. **The shop is reachable from iOS `URLSession`** (Cloudflare fingerprint, R1). Open Settings › Live-Daten › „Verbindung testen“ and price Wien→Salzburg in the editor.
   - If it is blocked, verify graceful degradation: Verbund trips still live via VAO, other trips „Tarif-Tabelle“.
2. Payload and latency of `/gate` on LTE (target: first results < 3 s). If it is too slow, switch the default to the mgate profile via remote config.
3. Search-role tab with `.searchable`: prompt switching, and results stay visible after picking a suggestion (R4).
4. Live verfolgen: notifications at departure, transfer and arrival; „Fahrt erfassen“ from the notification and from the Live Activity (once the module exists).
5. VoiceOver pass over results, detail and board; Dynamic Type AX3.

---

# PART E: App (SwiftUI, iOS 26)

## E1. Navigation [DECISION D4]

**`AppTab`** (in `AppState.swift`): `case overview, trips, stats, ticket, planner`. Remove `.add`.
- `planner.title = "Fahrplan"`, `planner.symbol = "magnifyingglass"`.
- `klimabilanz://tab/planner` works automatically.

**`MainTabView`** (in `RootView.swift`):

```swift
TabView(selection: $app.selectedTab) {                      // plain binding – the ".add never selected" hack goes away
    Tab(AppTab.overview.title, systemImage: AppTab.overview.symbol, value: AppTab.overview) { DashboardView() }
    Tab(AppTab.trips.title, systemImage: AppTab.trips.symbol, value: AppTab.trips) { TripsView() }
    Tab(AppTab.stats.title, systemImage: AppTab.stats.symbol, value: AppTab.stats) { StatisticsView() }
    Tab(AppTab.ticket.title, systemImage: AppTab.ticket.symbol, value: AppTab.ticket) { TicketView() }
    Tab(AppTab.planner.title, systemImage: AppTab.planner.symbol, value: AppTab.planner, role: .search) { PlannerRootView() }
}
.searchable(text: $planner.query, prompt: Text(planner.searchPrompt))   // planner = app.planner (@Bindable)
.tabViewSearchActivation(.searchTabSelection)
.tabBarMinimizeBehavior(.onScrollDown)
.liveJourneyAccessory(isVisible: app.liveJourney.isActive)              // WP-F; 26.1 isEnabled + 26.0 fallback (notes §1.5)
```

- **Fallback (R4):** if the search tab misbehaves on a device, set `PlannerModel.navigationStyle = .plainTab`, a one-line constant. Then the tab drops `role:` and `.searchable`, and `PlannerRootView` shows its own search field.
- **Quick add „+“** moves to the toolbars:
  - **Dashboard:** add a `ToolbarItem(placement: .topBarTrailing)` button with `plus`, a 44 pt glass circle, accessibility label „Fahrt erfassen“, calling `app.presentAddTrip()`. It sits next to the existing avatar item.
  - **Trips:** already has a „+“ in `toolbarContent` (`TripsView.swift:229`); keep it.
  - **Elsewhere:** favourite chips, widgets, Control Center, Siri and `klimabilanz://add` are unchanged.
  - **New entry point:** „Fahrt erfassen“ on every connection.
  - **`docs/DESIGN.md` §5.1:** replace „Kein doppelter „Neue Fahrt“-Knopf (der „+“-Slot der Tab-Leiste reicht)“ with „Kein zweiter Erfassen-Knopf im Inhalt – Toolbar-„+“ und Favoriten reichen.“
- **Deep links** (`RootView.handleDeepLink`):
  - `klimabilanz://plan?from=<stationID|name>&to=<stationID|name>&at=<ISO8601>&arr=0|1` → `selectedTab = .planner`; `planner.handleDeepLink(from:to:at:arrival:)`.
  - `klimabilanz://board?station=<stationID>` → `selectedTab = .planner`; `planner.showBoard(stationID:)`.
- **Screenshot router (CI):** new screens `planner`, `plannerResults`, `connection`, `departures` → `PlannerScreenshotScene(screen:)` (WP-E). `editorLive` → a `TripDraft` with the demo journey and quote (WP-F supplies `TripDraft.demoLive()`).
  - With `-KBDemo YES`, `LiveDataService(demo: true)` uses `DemoTimetableService` and `DemoPriceProvider` (WP-E). The network is never touched.
  - `scripts/capture_screenshots.sh` gets the new screen names. It belongs to the CI owner; this is integration step I4.

## E2. State and data flow

```swift
// AppState (WP-D) – additions
let live: LiveDataService                 // created in init (after stations/relations/catalog)
let planner: PlannerModel                 // WP-E type: PlannerModel(live: live, stations: stations, settings: settings)
let liveJourney: LiveJourneyTracker       // WP-F type: LiveJourneyTracker(live: live)
// TripDraft – additions
var journey: Journey? = nil               // set when logging/editing from the planner
var priceQuote: PriceQuote? = nil
// Toast – addition (custom == ignores the closure)
var action: ToastAction? = nil            // struct ToastAction { let title: String; let perform: @MainActor () -> Void }
```

**`LiveDataService`** (WP-D, `App/Sources/Services/Live/LiveDataService.swift`). This is the frozen API:

```swift
@MainActor @Observable
final class LiveDataService {
    enum Consent: String { case undecided, granted, declined }

    init(appConfig: AppConfig, settings: AppSettings, stations: StationIndex, relations: RelationPriceTable,
         catalog: TariffCatalog, demo: Bool = LaunchMode.useDemoData)

    // Observable state
    private(set) var config: LiveConfig
    private(set) var isOnline: Bool
    private(set) var health: [LiveProvider: LiveHealth.Status]
    var consent: Consent                                   // persisted via AppSettings.liveConsentRaw
    var isTimetableAvailable: Bool { get }                 // consent granted && settings.liveTimetableEnabled && config.isEnabled(.oebbHafas) && isOnline
    var isLivePriceAvailable: Bool { get }                 // consent granted && settings.livePricesEnabled && (shop || vao enabled) && isOnline
    enum Unavailable: Equatable { case consentUndecided, declined, switchedOff, killSwitch(notice: String?), offline }
    var timetableUnavailable: Unavailable? { get }         // nil when available – drives the planner's empty/consent/offline state
    var priceUnavailable: Unavailable? { get }

    // Services
    var timetable: (any TimetableService)? { get }         // nil when !isTimetableAvailable; DemoTimetableService in demo mode
    var priceProvider: (any LivePriceProvider)? { get }    // nil when !isLivePriceAvailable; DemoPriceProvider in demo mode
    let prices: LivePriceService                           // always; quote(_:allowLive:) falls back offline
    let linker: StationLinker
    let coverage: CoverageEvaluator?                       // from App/Resources/coverage_rules.json; nil if missing/invalid
    var rideActivity: any RideActivityControlling          // NoopRideActivityController until the Live Activity module plugs in

    // Actions
    func start() async                                     // cached config → remote refresh if due → NWPathMonitor → health
    func refreshConfigIfDue(manifest: UpdateManifest?) async
    func catalogDidChange(_ catalog: TariffCatalog) async  // → prices.update(estimator:)
    func quote(_ request: PriceRequest) async -> PriceQuote   // demo: DemoPriceProvider (falls back to offline); else prices.quote(request, allowLive: isLivePriceAvailable)
    func ticketScope(productID: String?) -> TicketScope    // coverage?.scope(forProductID:) ?? .unsupported
    func refreshHealth() async
    func resetCaches() async
    func testConnection() async -> Bool                    // HafasClient.serverInfo()
}
```

- **Construction.** A single shared `URLSessionTransport`, `RequestThrottle` and `LiveHealth` feed `HafasClient`, `OebbShopClient`, `VerbundTariffClient`, `StationLinker` and `LivePriceService`. The cache URLs are `URL.cachesDirectory/Live/{prices,stations-link}.json`.
- **App wiring:**
  - `AppState.refreshRemoteContent()` also calls `live.refreshConfigIfDue(manifest: updates.manifest)`.
  - `reloadCatalog()` also calls `Task { await live.catalogDidChange(catalog) }`.
  - `RootView.task` calls `await app.live.start()`.
- **Connectivity:** `App/Sources/Services/Live/Connectivity.swift` wraps `NWPathMonitor`. Offline → `isOnline = false`.
- **Remote config:** `App/Sources/Services/Live/LiveConfigStore.swift`. Order: cache in Application Support `live-config.json` → bundled default `LiveConfig.default` → remote at most every 12 h. The URL comes from `UpdateManifest.liveConfigURL ?? AppConfig.liveConfigURL`.
  - New optional field `liveConfigURL: String?` in `UpdateManifest`, `Packages/KlimaCore/Sources/KlimaCore/Updates.swift`. WP-D owns this one-line additive change.
  - New `liveConfigURL` in `AppConfig`, `App/Resources/AppConfig.json`, `scripts/write_app_config.py` and the `LIVE_CONFIG_URL` env line in `.github/workflows/ios.yml`.

## E3. Fahrplan screens (WP-E)

The screens follow the UX spec. Layout, tokens, motion and accessibility from the UX report §4–§9 are binding; mockups are in `$OEBB/ux/mockups/*.png`. What follows is the data binding for each screen.

| Screen (UX §) | Data calls (KlimaCore) | Refresh |
|---|---|---|
| **Root / search** (§4.1, mocks 10) | suggestions: `stations.search` (local, instant) → `timetable.locations(query, .all, 8)`. The remote search is debounced 250 ms and only runs when there are < 3 local hits or the query has a digit. Results of `kind == .station` matching a local station are merged. | – |
| **Deine Strecken** (§4.1) | the top 3 relations from `TripEntity` (last 90 days, both station ids set, favourites first) → `linker.hafasLocation` → `timetable.journeys(batch: [q × 3])` with `results 1, includeStopovers false` | 60 s while visible; paused in background and Low Power Mode |
| **In der Nähe** (§4.1) | `StationIndex.nearest(to:limit:1)` (local) → `board(maxResults 2, duration 30)`. „Aktueller Standort“ as origin → `timetable.nearby(point, 1000, 5, .all)`, first stop. | 30 s while visible |
| **Results** (§4.2, mocks 11) | `timetable.journeys(q)` with `results 5, includeStopovers true, includePolyline false, products: options`. „Früher“ uses `earlierContext`; prefetch within 2 cards of the end uses `laterContext`. `JourneyPresentation.summaries`, `coverage.evaluate(j, scope)`. | visible cards via `refresh(batch:)` every 60 s; pull to refresh |
| **Card price** | first 3 visible cards: `live.quote(PriceRequest(journey:))`. Others: `prices.offlineQuote` (instant) with badge „Tarif-Tabelle“/„Schätzung“. A shimmer shows while loading. | cache 24 h |
| **Detail** (§4.3, mocks 12) | the journey from results. Polyline per ride leg is lazy: `timetable.trip(tripID, includePolyline: true)`, cut by `Stopover.index` from the leg's first and last stopover. Walk legs are drawn as straight lines. Price via `live.quote` (with journey). | 60 s `refresh` |
| **Abfahrten** (§4.4, mocks 13) | `timetable.board(BoardQuery(station, .departures/.arrivals, date, 60, 40, .all))`. Mode chips filter client-side on `Line.mode`. Row tap → `trip(tripID, includePolyline: false)` sheet. „Fahrt erfassen bis …“: pick the exit stop → a single-leg `Journey` from `TripDetails.stopovers` → logging (§E6). | 30 s while visible; „Später“ loads +60 min |
| **Options sheet** | `PlannerOptions` (UserDefaults `planner.options`, JSON): `klimaTicketOnly` (default true when the active ticket scope is `.oe`), `products: ProductMask`, `maxChanges: Int?` (nil/0/1/2), `extraTransferMinutes` (0/5/10 → `minTransferMinutes` nil/5/10 [ASSUMED semantics]), `accessible: Bool` → `.complete`, `bike: Bool` | – |

**„Nur mit KlimaTicket gültig“** sends `products: .klimaTicket` **and** hides journeys whose coverage is `.notCovered`. Partial journeys stay visible with the footer „Gültig bis {stop} · danach Ticket nötig“.

**Card footer by coverage** (exact copy):

| Coverage | Footer |
|---|---|
| covered | „Mit KlimaTicket € 0 · Normalpreis € {x}“ |
| covered + surcharge | the same + chip with the rule badge |
| partial | „Gültig bis {lastCoveredStopName} · danach Ticket nötig“ |
| notCovered | „Nicht im {ticketName} enthalten · Ticket € {x}“ |
| discount | „{badge}“, e.g. CAT |
| unknown | „Normalpreis € {x} · Gültigkeit prüfen“ |

The amount shown for `partial` is the covered-part quote (§E6.2).

**Places and recents:**
- `PlannerPlace` = `.station(Station)` | `.live(Location)` | `.currentLocation`.
- Recents: UserDefaults `planner.recents`, the last 8 searches as JSON. Local only, never synced, no consent needed.

**Empty, loading, error and offline states.** Copy from UX §5, mapped from `LiveError`:

| LiveError | UI |
|---|---|
| `.offline` | glass pill „Offline · Fahrplan von {HH:mm} · ohne Echtzeit“; cards at 72 % opacity; realtime hidden |
| `.noConnection` | „Keine Verbindung gefunden“ + chips [Morgen früh zeigen] [Alle Verkehrsmittel] (or [Filter aus] when KlimaTicket-only is on) |
| `.rateLimited` / `.circuitOpen` | „Kurz zu viele Anfragen – gleich geht's weiter.“; auto refresh paused 2 min |
| `.blocked`, `.http`, `.decoding`, `.timeout`, `.network` | banner „ÖBB-Fahrplan gerade nicht erreichbar“ · „Das liegt nicht an dir. Wir versuchen es automatisch wieder.“ [Erneut versuchen]; backoff 2/4/8 s, at most 3 tries |
| `.hafas(code: "H9380" / "H9381")` | „Start und Ziel sind zu nah beieinander.“ |
| `.hafas(code: "LOCATION")` | „Haltestelle nicht gefunden – bitte anders suchen.“ (+ `linker.invalidate`) |
| `.disabled` | `LiveConsentCard` (undecided) or „Live-Daten sind aus“ + [Einstellungen] |

**Accessibility, haptics and motion:** UX §7–§8 are binding. Use `JourneyPresentation.accessibilityLabel` for each connection's VoiceOver label.

## E4. Persistence

| Item | Where | Owner |
|---|---|---|
| `liveConsentRaw` ("undecided"/"granted"/"declined"), `liveTimetableEnabled` (true), `livePricesEnabled` (true) | `AppSettings` (UserDefaults) | WP-D |
| Live config cache | Application Support `live-config.json` | WP-D |
| Price cache, station links | `Caches/Live/prices.json`, `Caches/Live/stations-link.json` | WP-B / WP-A (paths passed by WP-D) |
| `PlannerOptions`, recents | UserDefaults `planner.options`, `planner.recents` | WP-E |
| Tracked journey (for intents) | AppGroup defaults `liveJourney.current` (JSON `{journey, quote, travelClass}`) | WP-F |
| Trip provenance | `TripEntity` new fields (below) + D1 migration (Cloudflare backend) | WP-F |

**`TripEntity` additions** (`Shared/Models.swift`, all with defaults so lightweight migration works):

```swift
var priceSourceRaw: String = ""   // PriceSource.rawValue; "" = trip saved before OEBB_LIVE (legacy)
var priceProvider: String = ""    // "ÖBB", "VVT", "VOR", …
var priceProduct: String = ""     // "Standard-Ticket", "VVT Einzelticket"
var priceFetchedAt: Date? = nil
var journeyRef: String = ""       // Journey.refreshToken (HAFAS recon ctx, 300–600 chars) – refresh / "Rückfahrt planen"
var lineSummary: String = ""      // "RJX 19910 · Bus 760"
var arrivalAt: Date? = nil
```

- `isFareManual == true` ⇒ `priceSourceRaw = "manual"`.
- **`Repository.repeatTrip`** („Nochmal fahren“) copies the price but sets `priceSourceRaw` to `"table"`, or keeps `"manual"`. It clears `priceFetchedAt` and `journeyRef`.

**Sync** (WP-F). The cloud backend is the Cloudflare Worker + D1 (`docs/CLOUDFLARE_BACKEND.md`; this section was
adapted from the retired Supabase plan). New D1 migration `backend/migrations/0002_trip_price_provenance.sql`
(SQLite: one column per `ALTER TABLE`; synced timestamps are canonical TEXT):

```sql
ALTER TABLE trips ADD COLUMN price_source     TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN price_provider   TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN price_product    TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN price_fetched_at TEXT;
ALTER TABLE trips ADD COLUMN journey_ref      TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN line_summary     TEXT NOT NULL DEFAULT '';
ALTER TABLE trips ADD COLUMN arrival_at       TEXT;
```

- Per contract §4, a new sync column goes into the Worker's static schema map (`backend/src`), contract §3.5, the shared
  fixture `backend/test/fixtures/contract-rows.json` and the Swift `TripDTO` **together**, always with a default, so
  older apps that do not send it keep working. `backend.yml` applies the migration before it deploys the new Worker.
- `TripDTO` gets the fields as optionals (`decodeIfPresent`).
- **A Worker without the migration must keep syncing** (the user may build the app before re-running *Actions › Backend*).
  The Worker answers `422 unknown_field` for keys it does not know. Add an additive `features` array to
  `GET /v1/config` (e.g. `["trip_price_provenance"]`); `SyncService` encodes the new keys only when the cached config
  lists the feature, and otherwise encodes the DTO **without** them.

## E5. Trip editor live price (WP-F)

**`TripEditorModel` additions:**

```swift
enum PriceState: Equatable { case idle, loading, resolved(PriceQuote), failed(String) }
private(set) var priceState: PriceState = .idle
private(set) var quote: PriceQuote?                 // last resolved (live or offline)
var connection: Journey?                            // from "Verbindung" row or TripDraft.journey
private var priceTask: Task<Void, Never>?
func schedulePriceRefresh(force: Bool = false)      // debounce 600 ms, cancels the previous task
func pickConnection(_ journey: Journey)             // fills mode, date, distance, lineSummary, then quotes
var fare: Double { manualFare ?? quote?.amountEUR ?? estimate?.fareEUR ?? 0 }
var priceBadge: PriceSourceBadge.Source { … }      // .live(provider) | .table | .estimate | .edited | .loading | .offline
var isOfficialPrice: Bool { !isFareManual && (quote?.source == .table || quote?.isLive == true || estimate?.method == .officialTable) }
```

**Behaviour:**
- `recompute()` stays synchronous: the offline estimate appears immediately. It then calls `schedulePriceRefresh()` when:
  - both stations are resolved, or `connection != nil`;
  - the user has not set a manual price;
  - `app.live.isLivePriceAvailable`.
- **Editing an existing trip never auto-fetches** (D7). Fetching starts only when route, date, class or discount changes, or the user taps „Live-Preis abrufen“.
- The result cross-fades (`.numericText`, light haptic):
  - When live equals the table, show „✓ stimmt mit der Tarif-Tabelle überein“.
  - Otherwise show „Tarif-Tabelle: € {x}“ in `textSecondary`.
- Price calls go through `app.live.quote(...)`: `PriceRequest(from: PriceEndpoint(station:), to: …, departure: date, mode, travelClass, discount, journey: connection)`.
  - Free-text endpoints use `PriceEndpoint(name:, coordinate: nil)`.
  - Without coordinates the offline chain yields 0 € → the card keeps „Preis eingeben“.
- **„Verbindung“ row** (new, `TripEdConnectionRow.swift`). It appears when both endpoints are set and `isTimetableAvailable`.
  - Tapping it opens a sheet with 3 journeys around `date` (`results 3, includeStopovers true`).
  - Selecting one calls `pickConnection`, which sets `mode = JourneyMetrics.dominantMode`, `date` = planned departure, `manualDistanceKm = JourneyMetrics.distanceKm`, `lineSummary` and `connection`, and fetches a connection quote.
- **Drafts from the planner** (`TripDraft.journey` + `priceQuote`) prefill everything without another fetch. The banner reads „Aus dem Fahrplan übernommen · alles live ausgefüllt“ (mock 14).
- **`save()`** writes the provenance fields (§E4).
- **`TripEdPriceCard`:**
  - The „Offizieller ÖBB-Preis“ eyebrow is replaced by `PriceSourceBadge` (UX §4.7 badge spec).
  - The ⓘ popover shows the source, „abgefragt {d. MMM, HH:mm}“, `quote.alternatives`, and `Copy.fareExplanation` (new text, §E9).
  - When `consent == .undecided`, show the compact `LiveConsentCard(style: .inline)` above the amount.
- **`TripDetailView`** shows „Normalpreis € 29,70 · {Live-Preis ÖBB | Live-Preis VVT | Tarif-Tabelle | Geschätzt | Eigener Preis} · abgefragt 9. Okt., 11:58“ from the provenance. Legacy trips (`""`) keep today's text.

## E6. „Fahrt erfassen“ from a connection (WP-F)

### E6.1 API (`App/Sources/Data/Repository+Journey.swift`)

```swift
extension Repository {
    @discardableResult
    func logJourney(_ journey: Journey, quote: PriceQuote?, coverage: JourneyCoverage?, travelClass: TravelClass,
                    isRoundTrip: Bool = false) -> TripEntity
    /// Pending logs from LogTrackedJourneyIntent / notifications (AppGroup queue). Returns the number of trips added.
    @discardableResult
    func ingestJourneyLogs() -> Int
}
```

**Field mapping:**

| `TripEntity` field | Value |
|---|---|
| `fromName`, `toName` | `DisplayNames.make(raw).name` of the first ride leg's origin and the last ride leg's destination. Leading and trailing walks to addresses or POIs are skipped. |
| `fromStationID`, `toStationID` | `StationLinker.appStation(for:in:)?.id` (nil → free text) |
| `date` | planned departure of the first ride leg |
| `arrivalAt` | planned arrival of the last ride leg |
| `mode` | `JourneyMetrics.dominantMode` |
| `distanceKm` | `JourneyMetrics.distanceKm ?? estimator distance` |
| `fareEUR` | `quote?.amountEUR ?? offline quote` |
| provenance | from the quote |
| `journeyRef` | `journey.refreshToken ?? ""` |
| `lineSummary` | `JourneyMetrics.lineSummary` |
| `states` | from the linked app stations, as the editor does |

### E6.2 Rules [DECISION]

| Case | Rule |
|---|---|
| Value base | the regular price of the **covered part** only (`coverage_rules.json ui.tripAggregation.savingsRule`) |
| `.covered` / `.surcharge` | quote for the whole journey; save directly |
| `.partial` | `PlannerModel` requests the quote for `JourneyMetrics.coveredSegment` (origin → last covered stop): `PriceRequest(journey:…)` with `to` replaced by the covered-segment endpoint and `journey = nil`, so the shop prices the relation rather than the foreign connection. It saves that quote. Toast „Fahrt erfasst · nur Österreich-Abschnitt bewertet“. |
| `.notCovered` | CTA „Nicht im KlimaTicket“ (disabled) + secondary „Trotzdem erfassen“, which opens the editor with the draft so the user decides (§G Q3) |
| `.unknown` | save, with toast subtitle „Gültigkeit prüfen“ |
| Departure > 2 h in the future | dialog „Diese Fahrt liegt in der Zukunft.“ [Trotzdem erfassen] [Nach der Ankunft erinnern] → `ArrivalReminder.schedule(journey:quote:)` (WP-F): a local notification at arrival + 5 min with action „Erfassen“ |

- **After saving:** the toast „Fahrt erfasst · +{Δ %}“ has action „Rückgängig“ (soft delete through `Repository.deleteTrip`). The CTA morphs to „✓ Erfasst · Rückfahrt planen“, which swaps the stations and sets the time to arrival + 2 h. Haptic `.success`.

## E7. Consent, settings, attribution (WP-D)

**`LiveConsentCard`** (`App/Sources/Features/Settings/LiveConsentCard.swift`, `style: .card | .inline`). It appears on the first Fahrplan visit and inline in the price card while consent is undecided.
- Title: „Live-Daten aktivieren?“
- Body: „KlimaBilanz kann Fahrplan, Echtzeit und Ticketpreise direkt bei der ÖBB-Fahrplanauskunft, im ÖBB-Ticketshop und bei der Verkehrsauskunft Österreich abfragen – von deinem iPhone aus, ohne Konto. Diese Schnittstellen sind nicht offiziell für andere Apps freigegeben und können sich jederzeit ändern. Ohne Live-Daten nutzt KlimaBilanz weiter die offiziellen Tarif-Tabellen.“
- Buttons: „Aktivieren“ (`glassProminent`) and „Nur Offline-Daten“.

**`SetLiveDataSection`** (new `App/Sources/Features/Settings/SetLiveDataSection.swift`). Inserted in `SettingsView` after `SetFareSection()`.
- **Toggles:**
  - „Live-Daten“, subtitle „Fahrplan, Echtzeit & Ticketpreise live abfragen“. On → consent granted; off → declined.
  - „Fahrplan & Echtzeit“ (indented; disabled while the master is off).
  - „Live-Ticketpreise“, subtitle „Normalpreis aus ÖBB-Ticketshop bzw. Verbundtarif“.
- **Status row per provider** (from `live.health`):
  - „ÖBB-Fahrplan · zuletzt OK 11:58“
  - „ÖBB-Ticketshop · pausiert bis 12:30“
  - „Verkehrsauskunft Österreich · noch nicht genutzt“
- **Actions:** „Verbindung testen“ (spinner, then „Verbunden“ or „Nicht erreichbar“) and „Live-Cache leeren“.
- **Footnotes:** `config.notice`, and the privacy text §E8.

**Datenquellen.** Extend `Copy.dataSources`, which `SetSourcesPage` shows:
- („Fahrplan & Echtzeit“, „ÖBB-Personenverkehr AG – Scotty-Fahrplanauskunft (HAFAS)“)
- („Live-Ticketpreise“, „ÖBB-Ticketshop (Standard-Ticket) · Verkehrsauskunft Österreich VAO (Verbundtarife)“)
- („Offline-Normalpreise“, „ÖBB-Personenverkehr AG, Relationspreise, CC BY 4.0 (bearbeitet)“)
- („KlimaTicket-Gültigkeit“, „Eigene Auswertung der KlimaTicket-AGB, ohne Gewähr“)

**Results and detail footer:** „Daten: ÖBB-Personenverkehr AG · Preise ohne Gewähr · KlimaBilanz verkauft keine Tickets“.

**README** (WP-D):
- Add to the feature list: „Live-Fahrplan & Echtzeit“, „Live-Normalpreise“.
- Extend the Datenquellen line with the attributions above.
- Keep the independence statement.

**Brand:** no ÖBB or Verbund logos, colours (`#AB0020`) or fonts. Names appear only as text.

## E8. Privacy (WP-D)

- **Append to `Copy.privacy`:** „Live-Daten: Wenn du sie aktivierst, fragt dein iPhone Fahrplan und Preise direkt bei der ÖBB und der Verkehrsauskunft Österreich ab. Dabei werden die gesuchten Haltestellen und Zeiten übertragen, für „In der Nähe“ auch dein auf rund 100 m gerundeter Standort. KlimaBilanz selbst erhält diese Daten nicht.“
- **`project.yml` `NSLocationWhenInUseUsageDescription`:** „KlimaBilanz schlägt dir die nächstgelegene Haltestelle vor und zeigt Abfahrten in deiner Nähe. Für Live-Abfahrten wird ein auf rund 100 m gerundeter Standort an die ÖBB-Fahrplanauskunft gesendet.“
- The Always text is unchanged: trip detection never sends location.

## E9. Copy updates (WP-D, `Copy.swift`)

```text
fareExplanation:
So bestimmt KlimaBilanz den Normalpreis – in dieser Reihenfolge:
• Live aus dem ÖBB-Ticketshop: das Standard-Ticket für deine Verbindung, innerhalb eines Verkehrsverbunds das Verbund-Einzelticket.
• Live von der Verkehrsauskunft Österreich: das Verbund-Einzelticket – auch für vergangene Fahrten.
• Offline: offizielle ÖBB-Relationspreise (Kauf am Reisetag), sonst Kernzonen-Tarif oder eine Schätzung nach Bahnkilometern.
Ein Preis, den du selbst einträgst, wird nie überschrieben.
```

**Copy deck** (UX §9 plus error copy, Du-Form, de-AT):
- Fahrplan · Verbindungen · Abfahrten · Ankunft · Wohin? · Von wo? · Station suchen · Aktueller Standort · Jetzt · Früher · Später · Optionen
- Nur mit KlimaTicket gültig · Schnellste · Wenigste Umstiege · direkt · 1 Umstieg / {n} Umstiege
- pünktlich · Fällt aus · Gleiswechsel · heute Gleis {x} · Keine Echtzeitdaten · Fahrplan
- {n} min Fußweg · {n} min Umstiegszeit · Knapp: {n} min zum Umsteigen · Anschluss gefährdet · Alternativen · Zwischenhalte
- Mit KlimaTicket € 0 · Normalpreis · gespart · Live-Preis · Tarif-Tabelle · Schätzung · Angepasst · Live-Preis wird abgefragt …
- Live verfolgen · Fahrt erfassen · Erfasst · Rückfahrt planen · Angekommen in … · In den Kalender · Teilen · Im ÖBB-Ticketshop öffnen

**Rules:**
- „Gl.“ for track (PL), „Steig“ for bay (ST).
- „Bus“, never „Kraftfahrlinie“.
- „Fahrt“, never „Reise“.

## E10. Live Activity hook (integrate by intent, D10)

`App/Sources/Services/Live/RideActivityBridge.swift` (WP-D):

```swift
@MainActor protocol RideActivityControlling: AnyObject {
    var isSupported: Bool { get }
    func start(_ snapshot: LiveJourneySnapshot) async -> String?     // activity id
    func update(_ id: String, _ snapshot: LiveJourneySnapshot) async
    func end(_ id: String, final snapshot: LiveJourneySnapshot?, dismissAfter: TimeInterval) async
}
@MainActor final class NoopRideActivityController: RideActivityControlling { var isSupported: Bool { false } /* no-ops */ }
```

**What the separate module does** (it owns `Shared/RideActivityAttributes.swift` and the widget UI; **this project does not touch those files**):
1. Implement `RideActivityBridge: RideActivityControlling`, mapping `LiveJourneySnapshot` onto its `ContentState`:
   - `phase` → status
   - `currentLine` / `currentMode` → header tile
   - `nextEventTitle` / `Time` / `Platform` → main line
   - `nextEventRealtime.state` → colour
   - `progress` → track
   - `transfer` → footer
   - `arrival` + `regularPriceEUR` → end state
   - `staleAfter` → `ActivityContent.staleDate`
2. Set `app.live.rideActivity = RideActivityBridge()` (integration step I5).
3. Use **`LogTrackedJourneyIntent`** (WP-F, `Shared/JourneyIntents.swift`, a `LiveActivityIntent`) for the „Fahrt erfassen“ button in the end state.
   - The intent enqueues the current tracked journey into `Shared/JourneyLogQueue.swift` (AppGroup).
   - The app ingests the queue on foreground: `RootView.handleExternalRequests` calls `Repository.ingestJourneyLogs()`. WP-D adds that one line.
- `NSSupportsLiveActivities` and the widget-extension `ActivityConfiguration` belong to that module.

## E11. `LiveJourneyTracker` (WP-F, `App/Sources/Features/LiveJourney/`)

```swift
@MainActor @Observable final class LiveJourneyTracker {
    init(live: LiveDataService)
    struct Tracked: Equatable { var journey: Journey; var quote: PriceQuote?; var snapshot: LiveJourneySnapshot; var activityID: String? }
    private(set) var tracked: Tracked?
    var isActive: Bool { tracked != nil }
    func start(_ journey: Journey, quote: PriceQuote?) async
    func stop() async
    func refreshNow() async
}
struct LiveJourneyAccessory: View { … }                        // tabViewBottomAccessory content (expanded / inline)
extension View { func liveJourneyAccessory(isVisible: Bool) -> some View }   // 26.1 isEnabled; 26.0 always-on fallback that renders EmptyView when !isVisible
enum ArrivalReminder { static func schedule(journey: Journey, quote: PriceQuote?) async }
```

- **`start`** does the following:
  - persist `liveJourney.current` to the AppGroup;
  - build the snapshot (`LiveJourneySnapshotBuilder`);
  - call `rideActivity.start`;
  - request notification authorisation on the first use;
  - schedule local notifications: departure − 5 min „Abfahrt in 5 min · Gl. {x}“; per transfer „Umstieg in {station}: {line} ab {platform} {HH:mm}“; at arrival „Angekommen in {dest} · Fahrt erfassen? € {x}“ (category `journey.arrival`, actions `journey.log` „Erfassen“ and `journey.later` „Später“).
- **Refresh:** every 30 s in the foreground via `timetable.refresh(token, includeStopovers: true, includePolyline: false)`.
  - Diffs trigger: platform change → notification „Gleiswechsel: {line} jetzt Gl. {x}“; `TransferRisk.atRisk` → „Anschluss gefährdet – Alternativen ansehen“.
  - Notifications are rescheduled when times change.
  - Background refresh is best effort: `BGAppRefreshTask` id `com.knitelarlberg.klimabilanz.liveJourney`. WP-D adds `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes: [fetch]` in `project.yml`.
  - The tracker never shows stale data as live: after `staleAfter` the accessory says „Stand {HH:mm} · tippen für Live-Daten“.
- **Auto-stop** 30 min after arrival.
- **Notification categories:** add `App/Sources/Services/NotificationCategories.swift` (WP-F), `static func register(_ category: UNNotificationCategory)`. It merges via `getNotificationCategories`.
  - Change `TripDetectionService.registerNotificationCategory()` to use it. **Today it calls `setNotificationCategories([category])`, which would wipe the journey category.**
  - Extend `AppDelegate.userNotificationCenter(_:didReceive:)` in `KlimaBilanzApp.swift`: category `journey.arrival` + action `journey.log` → `Repository.logJourney` of the tracked journey + toast; a plain tap → `selectedTab = .planner` and open its detail.

## E12. Offline behaviour summary

| Surface | Live available | Offline / disabled / blocked |
|---|---|---|
| Fahrplan | full | consent card, or „Offline“ state; local station search still works; Deine Strecken shows relations without times |
| Results / board | realtime | last results stay visible at 72 % opacity with „ohne Echtzeit“ |
| Card / detail price | live quote | `offlineQuote` with badge „Tarif-Tabelle“ / „Schätzung“ / „Offline · Tarif-Tabelle“ |
| Trip editor | live price auto | today's behaviour (table / estimate) + badge „Offline · Tarif-Tabelle“ |
| Live verfolgen | 30 s refresh | snapshot frozen; „Stand {HH:mm}“; notifications as scheduled |

---

# PART W: Work packages (parallel, conflict-free)

**General rules for every work package:**
- Branch from the Step-0 commit.
- Touch only owned files plus the explicitly listed „may edit“ lines.
- Edits to shared hot-spot files are small, additive and wrapped in `// MARK: OEBB Live`.
- KlimaCore must not import UIKit, SwiftUI, ActivityKit, Network, CoreLocation or MapKit.
- No third-party dependencies.
- Swift 5 language mode; concurrency settings unchanged.
- German UI copy only from this spec or the UX spec.
- Commit messages per repo convention.
- Each work package ends with `swift test --package-path Packages/KlimaCore --no-parallel` green, and `python3 scripts/check_integration.py` green when app files changed.

## W-A: Core HAFAS, transport, config, station linking (KlimaCore)

**Owns**
- `CORE/Live/Transport/*`, `CORE/Live/Domain/*`, `CORE/Live/Config/*`, `CORE/Live/HAFAS/*`. The contracts are owned from Step 0 on: additive changes only, never rename public API.
- `Tests/KlimaCoreTests/Live/Support/*`, `Tests/KlimaCoreTests/Live/HAFAS/*`, `Tests/KlimaCoreTests/Live/LiveSmoke/HafasLiveTests.swift`, `FX/hafas/*`.

**Provides** (frozen signatures, §A2–§A3.7):
- `URLSessionTransport`, `RequestThrottle`, `LiveHealth`
- `HafasClient: TimetableService`, `HafasServerInfo`
- `StationLinker`, `VaoLocationSearching`
- `LiveConfigLoader`
- `FixtureTransport`, `Fixture`
- the codec static API:

```swift
public enum HafasCodec {
    public static func journeyPage(from data: Data, serviceIndex: Int = 0) throws -> JourneyPage        // TripSearch / Reconstruction
    public static func journeyPages(from data: Data) throws -> [Result<JourneyPage, LiveError>]         // batch
    public static func board(from data: Data, serviceIndex: Int = 0) throws -> Board
    public static func trip(from data: Data, serviceIndex: Int = 0) throws -> TripDetails
    public static func locations(from data: Data, serviceIndex: Int = 0, query: String? = nil) throws -> [Location]  // LocMatch/LocGeoPos; query enables the nonsense filter
    public static func remarks(from data: Data, serviceIndex: Int = 0) throws -> [Remark]                // HimSearch
    public static func envelopeError(_ data: Data) -> LiveError?
}
public struct HafasEnvelope<Request: Encodable>: Encodable { public init(profile: HafasProfile, svcReqL: [Request]) }   // shared with W-B (VAO)
```

**Acceptance criteria**
1. All §D2 WP-A tests pass on Linux. Every golden in `FX/golden.json["hafas/*"]` is asserted at least once.
2. The `$OEBB/journey-planner/client.py selftest` invariants are ported: legs chronological, polyline starts at the origin, DST, Koralm ≤ 45 min, WB = 4096, batch errors.
3. The encoder never emits `null` or keys outside §A3.3; the fixture key-set equality tests are green.
4. No network in default `swift test`. The live tests skip without `KB_LIVE_TESTS=1`.
5. The kill switch and disabled providers make no I/O (asserted with `FixtureTransport.recorded`).

## W-B: Core live prices (KlimaCore)

**Owns**
- `CORE/Live/Pricing/*`, i.e. the contracts `PriceModels.swift` and `FareEstimator+Live.swift`, plus all new pricing files.
- `CORE/FareEstimator.swift` (only the Step-0 patch lines and later additive changes).
- `Tests/KlimaCoreTests/Live/Pricing/*`, `Tests/KlimaCoreTests/Live/LiveSmoke/PriceLiveTests.swift`, `FX/shop/*`, `FX/vao/*`.

**Consumes:** W-A transport, throttle, health, `HafasEnvelope`, `HafasCodec.locations`/`envelopeError`, `StationLinker`. Code against the signatures; if W-A is not merged yet, use temporary test doubles in the test target only.

**Provides** (frozen, §B3.6, §B4, §B5): `OebbShopClient`, `ShopOfferSelector`, `ShopFare`, `VerbundTariffClient` (`: VaoLocationSearching`), `LivePriceService: LivePriceProvider`, `ShopDeepLink`, `TariffPeriods`, `VerbundArea`, and the implementation of `FareEstimator.estimateLive`.

**Acceptance criteria**
1. All §D2 WP-B tests pass, including the 13 policy scenarios with exact amounts (66,40 / 67,70 / 70,10 / 4,70 / 22,00 / 34,40 / 22,20 …).
2. The existing 24 KlimaCore tests stay green and unchanged.
3. Tokens never touch the disk; a test asserts the price cache JSON contains no `AccessToken` or `eyJ`.
4. The price-flow budget of 12 s is enforced. Worst-case request count per quote is ≤ 5 (asserted with `recorded`).
5. Explanation strings match §B4.5 byte for byte.

## W-C: Core coverage and presentation logic (KlimaCore + one resource)

**Owns**
- `CORE/Live/Coverage/*`, `CORE/Live/Presentation/*` (contracts plus new files).
- `App/Resources/coverage_rules.json` (copy of `FX/coverage/coverage_rules.json`).
- `Tests/KlimaCoreTests/Live/Coverage/*`, `Tests/KlimaCoreTests/Live/Presentation/*`, `FX/coverage/*`, `FX/ux/*`.

**Consumes:** W-A domain types (contract) and `HafasCodec` (golden coverage tests only).

**Provides** (frozen, §C2.6, §C3): `CoverageEvaluator`, `CoverageInputMapper`, `RealtimePresentation`, `LinePresentation`, `DisplayNames`, `JourneyPresentation` (`ConnectionSummary`, `PlatformLabel`), `JourneyMetrics`, `LiveJourneySnapshotBuilder`.

**Acceptance criteria**
1. The 14 synthetic coverage cases match.
2. All `coverage/journeys` goldens match (oe and tirol).
3. All `FX/ux` view-model expectations listed in §D2 match.
4. The rule engine ignores documentation keys; unknown operators evaluate to false without crashing.
5. The reference bugs are fixed and tested: `plus` key, „UU6“.
6. Everything is pure: no I/O, no `Date()` calls (`now` is injected).

## W-D: App shell, services, settings, navigation, legal (App target)

**Owns (new)**
- `App/Sources/Services/Live/{LiveDataService,LiveConfigStore,Connectivity,RideActivityBridge}.swift`
- `App/Sources/Features/Settings/{SetLiveDataSection,LiveConsentCard}.swift`
- `data/live_config.json` (template = `LiveConfig.default` encoded, `version: 1`)

**May edit** (small, marked):
- `App/Sources/Core/AppState.swift`: `AppTab`, the new properties, `TripDraft` fields, `Toast.action`, AppSettings keys.
- `App/Sources/Core/RootView.swift`: `MainTabView`, deep links, screenshot cases, `ingestJourneyLogs` call, `live.start()`.
- `App/Sources/Core/AppConfig.swift`, `App/Resources/AppConfig.json`, `scripts/write_app_config.py`, `.github/workflows/ios.yml` (one env line).
- `Packages/KlimaCore/Sources/KlimaCore/Updates.swift` (`UpdateManifest.liveConfigURL`, optional).
- `App/Sources/Core/Copy.swift`, `App/Sources/Features/Settings/SettingsView.swift` (one line), `App/Sources/Features/Settings/SetAboutSection.swift` (sources).
- `App/Sources/DesignSystem/Components.swift` (`ToastOverlay` action button).
- `App/Sources/Features/Dashboard/DashboardView.swift` (toolbar „+“).
- `project.yml`: location text, `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: fetch`.
- `docs/DESIGN.md` §5.1, `README.md`, `scripts/check_integration.py` (add `PlannerRootView` to `CONTRACT`).

**Consumes** (frozen names): `PlannerModel(live:stations:settings:)`, `.query`, `.searchPrompt`, `.navigationStyle`, `.handleDeepLink(from:to:at:arrival:)`, `.showBoard(stationID:)`, `PlannerRootView`, `PlannerScreenshotScene(screen:)`, `DemoTimetableService`, `DemoPriceProvider` (W-E); `LiveJourneyTracker(live:)`, `.isActive`, `View.liveJourneyAccessory(isVisible:)`, `Repository.ingestJourneyLogs()`, `TripDraft.demoLive()` (W-F).

**Provides:** `LiveDataService` (§E2), `RideActivityControlling` / `NoopRideActivityController` (§E10), `LiveConsentCard(style:)`, `AppSettings.liveConsentRaw` / `liveTimetableEnabled` / `livePricesEnabled`, `Toast.action`, `TripDraft.journey` / `priceQuote`.

**Acceptance criteria**
1. With consent undecided or declined, **zero** requests leave the app. Verify by code review: every client call is gated by `timetable` or `priceProvider` returning nil.
2. Kill switch: a remote config with `killSwitch: true` turns off all live surfaces within one config refresh.
3. `check_integration.py` is green. The macOS CI build is green (`[build]`).
4. The Settings section shows health; „Verbindung testen“ works.
5. Deep links `plan` and `board` route correctly.
6. `-KBDemo` makes no network calls.
7. Privacy, consent and attribution copy appear exactly as §E7–§E9.

## W-E: Fahrplan UI (App target)

**Owns (new)**
- `App/Sources/Features/Planner/**`: `PlannerModel.swift`, `PlannerRootView.swift`, `PlannerSearchView.swift`, `PlannerResultsView.swift`, `ConnectionDetailView.swift`, `ConnectionMapView.swift`, `DeparturesView.swift`, `TripSheetView.swift`, `PlannerOptionsSheet.swift`, `PlannerTimeSheet.swift`, `PlannerStateViews.swift`, `YourRoutesModel.swift`, `PlannerRecents.swift`, `PlannerDemo.swift` (`DemoTimetableService`, `DemoPriceProvider`, `PlannerScreenshotScene`).
- `App/Sources/DesignSystem/Planner/**`: `RealtimeTime`, `LiveDot`, `JourneyBar`, `PlatformBox`, `ConnectionCard`, `TimelineViews` (`TimelineStopRow`, `TimelineRideLeg`, `TimelineWalkLeg`), `NoticeRow`, `DepartureRow`, `LinePlate`, `RouteSlotsCard`.

**May edit:** nothing outside the owned folders. `RouteSlotsCard` shares geometry with `TripEdRouteCard` by copying constants, not by editing it.

**Consumes:** `LiveDataService` (W-D); KlimaCore W-A/W-B/W-C APIs; `PriceSourceBadge(source:)`, `Repository.logJourney`, `ArrivalReminder.schedule`, `LiveJourneyTracker.start` (W-F); `LiveConsentCard` (W-D).

**Provides** (frozen):

```swift
@MainActor @Observable final class PlannerModel {
    enum NavigationStyle { case searchTab, plainTab }
    static let navigationStyle: NavigationStyle = .searchTab
    init(live: LiveDataService, stations: StationIndex, settings: AppSettings)
    var query: String
    var searchPrompt: String                 // "Wohin?" | "Von wo?" | "Station suchen"
    func handleDeepLink(from: String?, to: String?, at: Date?, arrival: Bool)
    func showBoard(stationID: String)
}
struct PlannerRootView: View
struct PlannerScreenshotScene: View { init(screen: String) }
struct DemoTimetableService: TimetableService      // deterministic journeys built with KlimaCore memberwise inits (Innsbruck→Lech, St. Anton→Innsbruck; times relative to now)
struct DemoPriceProvider: LivePriceProvider        // e.g. Innsbruck Hbf→Lech € 29,70 liveOebb; other relations → table
```

**Acceptance criteria**
1. All screens and states of UX §4–§5 exist, in light and dark, and match the mockups' structure.
2. Every network call goes through `LiveDataService`; refresh cadences are as in §E3 and paused off screen.
3. VoiceOver labels come from `JourneyPresentation.accessibilityLabel`; Dynamic Type up to AX5 works without truncating amounts.
4. „Nur mit KlimaTicket gültig“ hides not-covered journeys.
5. The demo scenes render without network.
6. No ÖBB colours.
7. `check_integration.py` is green.

## W-F: Trip logging, editor live price, persistence, sync, live follow (App target + Shared + Cloudflare backend)

**Owns (new)**
- `App/Sources/Data/Repository+Journey.swift`
- `App/Sources/Features/Trips/Editor/TripEdConnectionRow.swift`
- `App/Sources/DesignSystem/Pricing/PriceSourceBadge.swift`
- `App/Sources/Features/LiveJourney/{LiveJourneyTracker,LiveJourneyAccessory,ArrivalReminder}.swift`
- `App/Sources/Services/NotificationCategories.swift`
- `Shared/JourneyLogQueue.swift`, `Shared/JourneyIntents.swift` (`LogTrackedJourneyIntent: LiveActivityIntent`; Shared means both targets)
- `backend/migrations/0002_trip_price_provenance.sql` (+ the matching schema-map, contract and fixture entries, §E4)

**May edit** (marked):
- `Shared/Models.swift` (`TripEntity` fields only)
- `App/Sources/Services/SyncService.swift` (`TripDTO` + probe)
- `App/Sources/Features/Trips/TripEditorModel.swift`, `Editor/TripEdPriceCard.swift`, `Editor/TripEditorView.swift` (insert the connection row and banner)
- `App/Sources/Features/Trips/List/TripDetailView.swift` (source line)
- `App/Sources/Data/Repository.swift` (`repeatTrip` provenance)
- `App/Sources/Services/TripDetectionService.swift` (category merge)
- `App/Sources/KlimaBilanzApp.swift` (`AppDelegate` routing)

**Consumes:** `LiveDataService`, `TripDraft.journey` / `priceQuote` (W-D); KlimaCore APIs.

**Provides** (frozen): `Repository.logJourney(...)`, `Repository.ingestJourneyLogs()`, `PriceSourceBadge(source:)` with `enum Source { case live(String), table, estimate, edited, loading, offline }`, `LiveJourneyTracker`, `LiveJourneyAccessory`, `View.liveJourneyAccessory(isVisible:)`, `ArrivalReminder.schedule(journey:quote:)`, `LogTrackedJourneyIntent`, `TripDraft.demoLive()` (extension in `Repository+Journey.swift`).

**Acceptance criteria**
1. A manual price is never overwritten (code path review plus a manual test).
2. Editing a legacy trip makes no fetch until an input changes.
3. The SwiftData migration is lightweight: all new fields have defaults; launching with an old store works.
4. Sync works against a server **without** migration 0003 (probe path) and with it.
5. Logging partial journeys values only the covered segment.
6. Live verfolgen: accessory, refresh and notifications work; the categories no longer overwrite each other.
7. `check_integration.py` is green; the macOS build is green.

## W-Merge: order and integration checklist (lead)

**Order:** Step 0 → **W-A** → **W-B** ∥ **W-C** → **W-D** → **W-E** ∥ **W-F**.
- All six may be developed in parallel from Step 0. This is the merge order.
- W-B and W-C golden tests that need `HafasCodec` compile once W-A is merged.
- The app work packages compile in CI only (macOS), after W-D is merged.

**Integration checklist (lead, after merges):**
- **I1** Linux `swift test --no-parallel` green: existing + live layer, about 150 tests.
- **I2** `python3 scripts/check_integration.py` green.
- **I3** macOS CI `[build]` green.
- **I4** Screenshots `[shots:planner,plannerResults,connection,departures,editorLive]`. The CI owner adds the names to `capture_screenshots.sh`.
- **I5** When the Live Activity module lands: set `app.live.rideActivity = RideActivityBridge()`, put the end-state button on `LogTrackedJourneyIntent`, and add `NSSupportsLiveActivities`.
- **I6** Device checklist §D4. **R1 decides whether shop prices are available on iOS.**
- **I7** One `KB_LIVE_TESTS=1` run from a dev machine; record the result in the PR.
- **I8** Optional: publish `data/live_config.json` and set `LIVE_CONFIG_URL`.
- **I9** Release notes (German): live planner, live prices, the valuation change for Verbund trips (R5), the consent explanation.

---

# PART F: Follow-ups (not in this round)

- **F1** Parse all 37 Relationspreise PDFs (today 10 of 37) and add Wien Westbahnhof `at:49:1468` as a tariff point. It is missing today, so Westbahnhof trips fall back to the distance model [LIVE prices report §4]. This makes the offline fallback exact for every ÖBB station pair (CC BY 4.0).
- **F2** VAO REST „Start“ as an official, bring-your-own-key `TimetableService` (100 requests/day; key in Keychain; never bundled) [SRC official report §1.1].
- **F3** WESTbahn's own tariff (`beta.westbahn.at/api`, unresearched).
- **F4** Wiener Linien open-data realtime monitor for Vienna stops (CC BY 4.0, rate code 316).
- **F5** App Intent and Siri „Wann fährt mein Zug nach …?“; a widget with the next departure of „Deine Strecken“.
- **F6** „Preise prüfen“ tool: re-price legacy trips with explicit per-trip confirmation (D7).
- **F7** Push-driven Live Activity updates if a push-capable build (TestFlight/App Store) exists.
- **F8** `getTariff` deep links for partial journeys: „Ticket für Teilstrecke ↗“ with a shop link for the non-covered part.

# PART G: Risks and open questions

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| **R1** | Cloudflare filters the shop by client fingerprint. curl got 403, Python urllib got 200 [LIVE]. iOS `URLSession` is **untested** [ASSUMED likely OK]. | Shop live prices may be unavailable on iOS | Device test first (D4). Verbund trips stay live via VAO; others use the table, which equals the shop's day-of-travel price in all cross-Verbund cases tested (2/2 in 2nd class, 5/5 in 1st) [LIVE]. Never evade. |
| **R2** | Legal: unofficial interfaces; ToS §3; robots disallow `/api` and `/bin/`. Public IPA or AltStore source = distribution. | Blocking, takedown request | Consent, low volume, on-device only, kill switch, no branding, no purchase. **Ask ÖBB and VAO for permission before public distribution.** |
| **R3** | API drift: strict `/gate` parser, AID rotation, shop `v4`/`v6` paths | Features break silently | Remote config + fallback profile + tolerant raw decoding + health in Settings + live smoke tests |
| **R4** | iOS 26 search-role tab with `.searchable` behaviour is [ASSUMED] | Navigation glitches | `PlannerModel.navigationStyle = .plainTab` fallback |
| **R5** | Valuation change: inside-Verbund trips use the Verbund tariff (−6 % … +28 % vs table) | New trips are valued differently from old ones | Legacy trips unchanged (D7); explanation popover; release note; follow-up F6 |
| **R6** | Unmerged Phase-2 branches touch `RootView`, `TripEditorModel`, `DashboardView`, `SettingsView`, `SyncService` | Merge conflicts | Step 0 after merging them; marked, minimal edits |
| **R7** | New columns missing on the user's Worker/D1 (backend not redeployed) | Sync failure (`422 unknown_field`) | Feature flag in `/v1/config` before encoding new keys (§E4) |
| **R8** | `/gate` sends 95–410 KB uncompressed per search | Slow on cellular | No polylines in lists; remote switch to gzip mgate |
| **R9** | Cancellations, partial cancellations and occupancy were never observed | Untested UI | Synthetic tests; validate on a strike or heavy-traffic day |
| **R10** | No APNs for Live Activities in sideloaded builds | Stale Live Activity | Honest „Stand …“ state; `BGAppRefresh`; F7 |
| **R11** | Verbund hints from station ids are imperfect at borders; `wl:` → `at:49` mapping is [ASSUMED] | Wrong source order | VAO `NA` falls back to the shop; live test D3 |
| **R12** | Same-tariff-period proxy and 15 % detour guard are heuristics | Small mispricing | Alternatives shown; user can edit |
| **R13** | Vorteilscard on Verbund tickets assumed not discounted [ASSUMED] | Over-valuation for Vorteilscard users inside a Verbund | Explanation says so; verify with the VVT/VOR tariff |

**Open questions for the product owner:**
- **Q1** The valuation basis „Kauf am Reisetag“ (D3) vs. purchase-time prices. The difference is up to ≈ 6 % on ÖBB-tariff trips bought ahead.
- **Q2** The Wien Kernzone single fare: catalog € 3,20 vs. VAO „1 Fahrt WIEN“ € 3,00 [LIVE]. Which one is correct for 2026?
- **Q3** Should connections that are not covered be loggable, and at what value (E6.2)?
- **Q4** Is the repository or AltStore source public? If so, request permission (R2) or keep Live off by default.

# Appendix 1: Endpoint reference

| Service | Method / URL | Auth | Required headers | Key request fields | Key response fields | Errors | Limits (ours) | Evidence |
|---|---|---|---|---|---|---|---|---|
| ÖBB HAFAS | POST `https://fahrplan.oebb.at/gate` | AID in body (`5vHavmuWPWIfetEe`) | Content-Type, Accept, Accept-Encoding, User-Agent | envelope §A3.1; svcReqL §A3.3 | `svcResL[i].res{common, outConL / jnyL / journey / match / locL / msgL}` | HTTP 200 + `err` (AUTH, PARSE, HAMM; svc LOCATION, H890, H9381, PARAMETER) | 40/min, ≥ 0.3 s | [LIVE] `FX/hafas/*` |
| ÖBB HAFAS legacy | POST `https://fahrplan.oebb.at/bin/mgate.exe` | AID `OWDL4fE4ixNiPBBm` | same | ver 1.41, client IPH, v String | identical shape, gzip | same | fallback only | [LIVE] `legacy_mgate141_*` |
| Shop token | GET `https://shop.oebbtickets.at/api/domain/v1/anonymousToken` | – | User-Agent, Accept, Channel: inet | – | `access_token` (JWT, 300 s), `refresh_token` (2,340 s) | Cloudflare 403 HTML, 429 | 12/min, ≥ 1 s | [LIVE] `shop_*_01_*` |
| Shop session | POST `…/api/domain/v1/initUserData` | AccessToken | + Content-Type | `{}` | `sessionId`, `sessionTimeout: 2400`, … | 401/13008 | same | [LIVE] `shop_*_02_*` |
| Shop stations | GET `…/api/hafas/v1/stations?name=&count=` | AccessToken | as above | name, count | `[{number, name, meta, latitude, longitude}]` | as above | same | [LIVE] `shop_*_03_*` |
| Shop timetable | POST `…/api/hafas/v4/timetable` | AccessToken | as above | §B3.2 | `connections[{id, from, to, sections, switches, duration}]`, `infos` | 440/3011, 401/13008, empty connections | same | [LIVE] `shop_*_05_*`, `arch_shop_timetable_*` |
| Shop offers | POST `…/api/offer/v6/offers` | AccessToken | as above | `selection.connectionId`, passengers, datetime | `offerSections[].travelClasses[].offers[{flexibility, price, products[{name, trafficType, owners}]}]`, `offerError` | `offerError: true` | same | [LIVE] `shop_*_07_*`, `arch_shop_offers_*` |
| VAO tariff | POST `https://anachb.vor.at/hamm/gate` | AID `wf7mcf9bv3nv8g5f` | Content-Type, Accept, User-Agent | TripSearch + `getTariff` + `trfReq{jnyCl:2, tvlrProf:[{type:"E"}], cType:"PK"}`, lid `A=1@L=<IFOPT-derived>@` | `outConL[].trfRes{statusCode, totalPrice{amount}, fareSetL[{name, fareL[{name, price}]}]}` | NA, svc LOCATION (EVA lids) | 20/min, ≥ 1 s | [LIVE] `FX/vao/*` |
| Shop deep link | GET `https://shop.oebbtickets.at/de/ticket?cref=…&stationOrigEva=…&stationDestEva=…&outwardDateTime=…` | – | – | – | SPA | – | user tap only | [SRC] SPA bundle; [LIVE] format from Scotty |

# Appendix 2: Artefacts produced for this spec

| Artefact | Path |
|---|---|
| Contracts (compile-checked) | `$OEBB/contracts/Sources/KlimaCore/Live/**`, `$OEBB/contracts/FareEstimator.patch`, `$OEBB/contracts/apply_contracts.sh`, `$OEBB/contracts/repo-tests/LiveContractTests.swift` (repo copy of `$OEBB/contracts/Tests/ContractTests/ContractTests.swift`) |
| Staged fixtures + goldens | `$OEBB/repo-fixtures/` (118 files, `MANIFEST.json`, `golden.json`); generator `$OEBB/arch/stage_fixtures.py` |
| Architect live checks | `$OEBB/arch/verify_assumptions.py`, `verify_assumptions2.py`, `$OEBB/arch/fixtures/arch_*.json` (10 requests on 2026-10-09) |
| Linux probes | `$OEBB/arch-probe/` (URLSession async + ICU regex), `$OEBB/arch/repo-dryrun/` (Step-0 dry run, tests green) |
