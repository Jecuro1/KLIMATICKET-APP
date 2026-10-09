# KlimaBilanz · Orte-Suche wie Scotty — hybrid place-suggestion engine (SUGGEST_SPEC)

> **Repository copy (2026-10-09).** This is the design spec the KlimaCore place layer implements; see
> [PLACES.md](PLACES.md) for the implementation status, the API and the deviations. Paths below refer to the research
> scratchpad; in the repository: `REF` → `scripts/places_reference.py`, `GOLD`/`FX` →
> `Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/` (`golden_places.json`, `fold_golden.json`, `live/*.json`),
> Task A → `scripts/build_places.py` + `App/Resources/places.bin`/`localities.bin`, `BENCH` → the Swift sources in
> `Packages/KlimaCore/Sources/KlimaCore/Places/`, `LIVE` → [OEBB_LIVE.md](OEBB_LIVE.md). Expected lists in §11.3 were
> computed on the research snapshot; the authoritative expectations are the regenerated goldens on the shipped data.


Status: implementation spec, 2026-10-09. Scope: every place Scotty knows becomes selectable in the app
(all Austrian stops of every operator, towns, addresses, POIs), with Scotty-like suggestions while typing,
nearby stops, and full offline operation for stops. This document is binding for the implementer; values
marked **[LIVE]** were measured against `https://fahrplan.oebb.at/gate` on 2026-10-09, **[FIT]** were fitted
to live data, **[DECISION]** are design choices, **[ASSUMED]** are unverified.

## 0. How to read this

### 0.1 Paths

| Alias | Path |
|---|---|
| `$PL` | `/tmp/claude-0/-home-user-KLIMATICKET-APP/0dc47024-4f5c-5528-81fe-c86cb79aed3b/scratchpad/places` |
| `$SC` | `$PL/scotty` |
| `FX` | `$SC/fixtures/` — 63 LocMatch/LocGeoPos scenarios + 4 raw batch envelopes, index in `FX/INDEX.json` |
| `REF` | `$SC/tools/suggest.py` — executable reference of this spec (Python, stdlib) |
| `BENCH` | `$SC/swift/PlaceSearchBench/` — Swift reference of §3–§5 (offline engine) + benchmark |
| `GOLD` | `$SC/golden_cases.json` (93 cases), `$SC/fold_golden.json` (55 normalisation cases), `$SC/golden_*_subset.json`, `$SC/golden_municipalities.json` |
| Task A | `$PL/out/places.json`, `$PL/out/localities.json`, `$PL/out/places.bin` (offline dataset, built by `$PL/build_places.py`); frozen snapshot used here: `$SC/work/taskA_snapshot/` (sha256/16 `7049ea1ff4a5b50c` places, `30341f3be3148927` localities) |
| `LIVE` | `/home/user/KLIMATICKET-APP/docs/OEBB_LIVE.md` (HAFAS client, §A3) |

Regenerate every derived artefact (no network): `sh $SC/tools/regen_all.sh` → Python cases, Swift build,
normaliser golden check, Swift benchmark, Swift-vs-Python cross-check, golden subset, `golden_cases.json`.

### 0.2 What was verified

- 38 polite live HTTP requests (≥ 1.5 s apart; batches split losslessly because `common` lists are per `svcResL[i]`).
- The reference engine (Python) and the Swift port produce **identical top-5 for 89/89 offline cases** on the
  60,773-record Task A dataset, and the 6,210-stop golden subset reproduces **93/93** expected lists (offline and
  merged with live fixtures).
- Swift (release, Linux x86-64, one core) on the full dataset: **p50 0.46 ms, p95 3.1 ms, p99 3.8 ms, max 4.9 ms per
  keystroke** over 392 typed prefixes (§4.9). Budget on iPhone: 16 ms.

### 0.3 Supersedes

- `LIVE` §E3 "Root / search" rule ("remote search only when < 3 local hits or the query has a digit") → replaced by §6.1
  (live runs for every query ≥ 3 characters, because addresses/POIs only exist live).
- `LIVE` §E3 `PlannerPlace` → replaced by `PlaceSuggestion` (§10). `StationIndex` stays for legacy ids only (§10.4).
- `LIVE` §A3.3 plausibility filter is kept and extended (§6.4).

---

## 1. Summary and binding decisions

1. **Two sources, one ranking.** The offline index (Task A: 39,722 stops + 21,051 localities) answers every keystroke
   synchronously. Live `LocMatch` (type `ALL`) augments with addresses, POIs and HAFAS-only stops after 250 ms of
   idle typing. Both are scored by the *same* formula (§5) and merged with deterministic dedupe rules (§6.6).
2. **Normalisation is table-driven and identical in Swift and Python** (§3, golden `fold_golden.json`). Umlauts fold
   both ways (`Pölten = Poelten = Polten`), abbreviations are synonyms (`Hbf/Hauptbahnhof`, `Bf/Bahnhof/Bhf`,
   `St./Sankt`, `Str./Straße`, `Wr./Wiener`, `i.T.` → `in Tirol`, `a.d.` → `an der`, `Ibk` → `Innsbruck`).
3. **Offline index = sorted form dictionary + importance-ordered CSR postings + flat token tables** (§4). Record id =
   rank by importance, so "first N candidates" = "N most important candidates" (bounded work: N_MAX = 1,500).
4. **Ranking = 100 × text score + 40 × importance + context** (§5); importance from weekday departures and modes,
   fitted to HAFAS `wt` (MAE 0.024).
5. **We fix Scotty's weak spots** (§2.4, §2.5): `wien w` (Scotty: no Westbahnhof), `Westbahnhof` (Scotty: German stations),
   `Hall i.T.` (Scotty: a UK station first), `insbruck` (Scotty: "Institut…" POIs), `Stephansplatz` (Scotty: POI
   before the U-Bahn stop), duplicate meta pairs, `(1)/(2)` POI duplicates.
6. **Picked addresses/POIs are valued via their nearest stop** (walk-time rule, §7); in the planner the HAFAS `lid`
   is used directly (HAFAS adds the walk legs).
7. **Recents and favourites first**: empty query shows them; with text they get score boosts but only when they match (§8).

### 1.1 Flow per keystroke

```
text ──► compile (§3.7: fold, lex, abbreviations, compound split, prefix ranges)
     ├─► offline search (§4.5, sync on the service actor, ≤ 5 ms) ──► rank (§5) ──► caps (§6.7) ──► yield #1
     └─► if live allowed & ≥ 3 chars: debounce 250 ms ─► cache? ─► LocMatch ALL/10 (§6.1)
              ─► parse + C1/P1 collapse (§6.2, §6.5) ─► plausibility (§6.4) ─► score (§6.3)
              ─► dedupe/merge with the offline rows of the same text (§6.6) ─► caps ─► yield #2 (stability rule)
pick ──► recents (§8) ──► planner: lid / extId (§7)   trip log: resolve to stop (§7)
```

---

## 2. Scotty LocMatch: observed behaviour [LIVE]

### 2.1 Request (exact key set)

```json
{"meth":"LocMatch","req":{"input":{"loc":{"type":"ALL","name":"<query>?"},"maxLoc":10,"field":"S"}}}
```

Envelope as `LIVE` §A3.1 (`ver 1.88`, `ext OEBB.14`, AID `5vHavmuWPWIfetEe`). Server reports `ver 1.95` in HAMM errors.

| Parameter | Values | Observed |
|---|---|---|
| `loc.type` | `ALL`, `S`, `A`, `P`, `SP` (any combination of S/A/P) | `ALL` interleaves stops, addresses and POIs (`FX/lm_all_hofburg`); `S` stops only; `A` addresses only (`lm_A_hofburg`: "1010 Wien, Hofburg"); `P` POIs only; `SP` = `ALL` minus addresses (`lm_SP_hofburg`). |
| `loc.name` | text + optional trailing `?` | `?` = "fuzzy" in hafas-client/PTE. **No observable difference** in 6 paired tests (`lm_all_<x>` vs `lm_all_nonfuzzy_<x>` for `inns`, `innsbruck h`, `insbruck`, `st anton`, `ibk`, `Wien Hbf`: identical lists and order). **[DECISION]** always append `?` (as the reference clients do). |
| `maxLoc` | int | Respected (`lm_S_max30_wien`, 30 results). Scotty web uses 7 (`Suggest.resultAmount`). **[DECISION]** 10. |
| `field` | enum `HCILocationField` = **`B, S, D, U, V, I`** | `Z` → top-level `err:"HAMM"`, hammError lists the enum (`lm_param_field_Z_innsbruck`). `D` gives the same list as `S` (`lm_param_field_D_innsbruck`). **[DECISION]** always `S`. |
| any other key (`locFltrL`, unknown keys in `req`, `input`, `input.loc`) | — | top-level `err:"HAMM"`, `hammError:"Internal Server Error"`, empty `svcResL` (`lm_param_locFltrL_bus_innsbruck`, `lm_schema_unknown_*`). LocMatch therefore cannot filter by product server-side; filter client-side. Maps to `LIVE` §A3.2 HAMM handling (fallback profile, then `.decoding`). |

Scotty web suggest config (`hafas_webapp_config.js`, `e.Suggest`): `minChar 4, suggestType "ALL", delay 400,
resultAmount 7, useHistoryLocations "PRESELECT", useFavoriteLocations "REQUEST", useTopLocations "EMPTY",
useNearLocation true, dist 1000`; top locations: WIEN (meta 1190100), Klagenfurt Hbf, Innsbruck Hbf, GRAZ, Salzburg Hbf,
Linz/Donau Hbf, St.Pölten Hbf, Villach Hbf, BREGENZ, EISENSTADT. History keeps 5 locations.

### 2.2 Response objects

`res.match.locL[]` (plus `res.match.state:"L"`, `res.match.field` echoing the request), `res.common.icoL/prodL/remL`.

| `type` | lid `A=` | Fields present | Notes |
|---|---|---|---|
| `S` stop | `A=1@O=<name>@X=@Y=@U=<src>@L=<extId>@p=…@` | `extId, name, crd, pCls, wt, icoX, meta?, countryCodeL, chgTime, TZOffset, pRefL, globalIdL?, msgL?, isFavrbl, state:"F"` | `U=81` ÖBB, `80` DB; `wt` always present for S |
| `A` address | `A=2@O=<PLZ Ort, Straße Nr>@H=1@X=@Y=@U=103@L=<id>@…` (house number) or `…@U=103@b=<street id>@…` (street) | `name, crd, icoX, state, isFavrbl`, `extId` only with house number | `state:"F"` exact house number, `state:"M"` street-level match. Name format `"6020 Innsbruck, Maria-Theresien-Straße 1"`; may carry `" (Gebäude)"` suffixes |
| `P` POI | `A=4@O=<name>@X=@Y=@U=105@L=98xxxxxxx@…` | `extId (98…), name, crd, icoX, state` | Name format `"<POI>, <Straße Nr>, <PLZ> <Ort>"`; duplicates get `" (1)"`, `" (2)"` |

POI categories come from `common.icoL[icoX].res` (German label in `txtA`) [LIVE inventory over all fixtures]:
`STA_TOURISM` Sehenswürdigkeit, `STA_TRADE` Handel, `STA_PUBLIC` Öffentliche Einrichtung, `STA_RESTAURANT` Gastronomie,
`loc_health` Gesundheit, `STA_AIRPORT` Flughafen, `STA_HOTEL` Hotel und Unterkunft, `STA_ENTERTAINMENT` Kultur und
Unterhaltung, `STA_SPORTS` Freizeit und Sport, `prod_taxi`. Stop icons: `prod_ice, prod_ic, prod_nachtzug, prod_reg,
prod_comm_t (S-Bahn), prod_sub_t (U-Bahn), prod_tram, prod_bus, prod_gen, loc_meta`. Addresses: `loc_addr`.

### 2.3 Ids, metas and weights

**extId ranges [LIVE, inferred from 651 distinct stops]:**

| Pattern | Meaning | Examples |
|---|---|---|
| `81xxxxx` | ÖBB EVA (rail station) | 8100108 Innsbruck Hbf, 8100003 Wien Westbahnhof |
| `80…`, `85…`, `70…`, `46…` | foreign (DB EVA, SBB, GB, DE local) | 8004132 München Karlsplatz, 7001069 "Hall i' th' Wood" |
| `11` + 5 digits, `meta:true` | locality/municipality meta ("alle Haltestellen im Ort") — code is GKZ-like, **not** a reliable GKZ | 1170101 Innsbruck, 1190100 Wien, 1192101 Floridsdorf (Wien), 1180113 Lech |
| `12…` meta | station meta (station + surrounding stops) | 1290401 Wien Hbf (U), 1270311 Hall in Tirol Bahnhof |
| `13…` meta | stop-area meta (several stop points) | 1390167 Wien Stephansplatz (U), 1370181 Innsbruck Technik |
| `14…` meta | centre meta | 1470491 Kitzbühel Zentrum |
| 6 digits | Verbund stop; **1st digit = Bundesland** (1 B, 2 K, 3 NÖ, 4 OÖ, 5 S, 6 ST, 7 T, 8 V, 9 W) | 791226 Innsbruck Maria-Theresien-Straße, 891302 Lech Dorfhus, 901057 Wien Albertinaplatz |

For `11/12/13/14xxxxx` the **3rd digit** is the Bundesland (same code). Use only as a display hint when the stop is
not in the offline index (`REF state_from_extid`).

**`wt` (weight):** 0–32,767 (clipped; Meidling (Wien) = 32,767), discrete plateaus (24, 130, 241, 407, 489/490, …,
2,968, …, ~4,500, 10–32 k for IC/RJ hubs) and drifts by a few units within hours (489 vs 490, 31,170 vs 31,177 between
the 09:21 `LIVE` fixtures and the 11:46 `FX` ones). It is driven
by long-distance service, not departure counts (Klagenfurt Hbf 668 weekday departures → wt 24,654).

**Meta pairs:** HAFAS publishes the locality meta and the station meta of the same place with **identical `crd`, `pCls`
and `wt`** (13 pairs found: 12 at 0 m, Puntigam at 47 m): "Floridsdorf (Wien)" + "Wien Floridsdorf Bahnhof (U)", "Zell am See" +
"Zell am See Bahnhof", "Bregenz" + "Bregenz Bahnhof", "Seefeld in Tirol" + "… Bahnhof", "Hütteldorf (Wien)",
"Heiligenstadt (Wien)", "Urfahr (Linz)", "Puntigam (Graz)" (47 m), … Scotty shows both → wasted rows (§6.5 C1).

### 2.4 Ranking Scotty returns

- Not sorted by `wt`. Exact full-name matches come first (`wien` → meta "Wien" before "Wien Hbf (U)" with higher wt;
  `Kitzbühel` → meta with wt 490 first), otherwise roughly by `wt`, with locality metas (`11…`) placed *behind* the main
  station for partial input (`inns` → "Innsbruck Hbf" 21,554 before "Innsbruck" 26,650; `linz`, `Woergl` likewise).
- Strong bias to names that **start** with the query: `Westbahnhof` → "Westbahnhof, Aachen/Landau/Mülheim/Tübingen/Bonn"
  (German naming "Haltestelle, Ort"); "Wien Westbahnhof (U)" is missing from the top 10.
- Single-letter tokens are effectively ignored: `wien w` returns the same list as `wien` (no Westbahnhof).
- POIs/addresses are interleaved by text match, not popularity: `Stephansplatz` → POI Stephansdom first, U-Bahn stop 2nd;
  `Hofburg` → 3 POIs then the stop "Innsbruck Congress/Hofburg".
- Nonsense never fails: `xqzvvhjkq` → most important stations (`LIVE` §A3.3 golden).
- HAFAS knows aliases we do not: `Lech Postamt` → "Lech Dorfhus" first (renamed stop), `ibk` → "Innsbruck".

### 2.5 Spelling tolerance

| Input | Scotty result | Fixture |
|---|---|---|
| `Woergl`, `kitzbuehel`, `St Poelten Hbf` | correct (oe/ue ≙ ö/ü) | `lm_all_woergl_oe`, `lm_all_kitzbuehel_ue`, `lm_all_st_poelten_hbf_oe` |
| `Kitzbuhel`, `st polten` (plain vowel) | correct but odd first row (POI "Kitzbuheler Handarbeiten"; "St.Pölten Ing.-Leopold-Figl-Straße" wt 24) | `lm_all_kitzbuhel_plain`, `lm_all_st_polten_plain` |
| `Sankt Pölten Hauptbahnhof` | correct (Sankt ≙ St., Hauptbahnhof ≙ Hbf) then 8 POIs | `lm_all_sankt_poelten_hauptbahnhof` |
| `Bregenz Bf` | correct (Bf ≙ Bahnhof) | `lm_all_bregenz_bf` |
| `innsbruk` (missing letter at end) | correct (prefix) | `lm_all_innsbruk` |
| `insbruck` (missing inner letter) | **fails**: 4 "Institut…" POIs first, Hbf 6th | `lm_all_insbruck` |
| `Hall i.T.` | **fails**: "Hall i' th' Wood" (GB) first | `lm_all_hall_i_t` |
| `St. Johann` | weak: Pongau, then a Swiss stop and POIs; St. Johann in Tirol missing | `lm_all_st_johann` |
| `Schönbrunn` | weak: a NÖ bus stop + 7 POIs; "Wien Schönbrunn (U)" 10th | `lm_all_schonbrunn` |

### 2.6 LocGeoPos (nearby) [LIVE]

`gp_nearby_*` (rounded 3-decimal coordinates per `LIVE` §A3.3). Each `locL[]` has `dist` (m) and `dur` (s).
**Fit over 37 points: `dur = 120 s + 1.2 s/m × dist`, max error 0.5 s** — HAFAS walking time = 2 min fixed + 3 km/h.
Use this formula offline (`walkSeconds(d) = 120 + 1.2·d`). `entry:true` marks stops with entrance data (ignore).

---

## 3. Normalisation (both sides: index and query)

Reference: `REF fold/lex/abbreviate/tokenize`, `BENCH Normalizer.swift`. Golden: `fold_golden.json` (55 strings →
fold, tokens, flags, forms); both implementations pass 55/55.

### 3.1 Fold

1. Unicode lower-case.
2. ASCII stays. Explicit table (exactly): `äàáâãåāăą→a  æ→ae  çćčĉċ→c  ďđ→d  èéêëēėęěĕ→e  ğĝģ→g  ìíîïīįı→i
   ĺľłļ→l  ñńňņ→n  öòóôõøōőŏ→o  œ→oe  ŕřŗ→r  śšşŝș→s  ß→ss  ťţț→t  üùúûūůűųŭ→u  ýÿ→y  źżž→z  ’‘`´→'`.
3. Any other non-ASCII scalar: NFKD, drop combining marks (Mn/Mc/Me).
4. `ae→a`, `oe→o`, `ue→u` (left to right). Applied to names and queries alike, so `Pölten`, `Poelten`, `Polten` all
   become `polten`; harmless over-merging (`Steuerberg → steurberg`) is accepted.

### 3.2 Lexing and abbreviations

- Alphanumeric runs are tokens. `-` and `/` split tokens but keep them in one **chunk** (compound group); every other
  character ends a chunk. `(…)`/`[…]` mark their tokens as **qualifier**. A `.` directly after a token marks it **dotted**.
- Token-level abbreviation rules (in this order; regex-free so Swift and Python agree):

| Dotted token(s) | Becomes | Example |
|---|---|---|
| `i.` + `t` | `in tirol` | Hall i.T. |
| `i.` + `pg` | `im pongau` | St. Johann i.Pg. |
| `i.` + `m` | `im muhlkreis` | |
| `a.` + `d.` | `an der` | Bruck a.d.Mur |
| `wr.` | `wiener` | Wr.Neustadt |
| `b.` (followed by a token) | `bei` | Hof b.Salzburg |
| `i.` (followed by a token) | `in` | |

### 3.3 Token classes

| Class | Members | Effect |
|---|---|---|
| stopword | `an am der die das dem den bei beim in im ob a d i b und zum zur vom von auf` | optional in queries (skip cost 0.05); not counted for coverage |
| generic | canonical ∈ `hbf bf bahnhst hst u s abzw bahn` | matchable; not counted for coverage; *is* required for "exact" |
| qualifier | bracket tokens; river after `/` in the same chunk (`donau mur ybbs rhein enns inn thaya traun drau krems murz lafnitz raab salzach triesting traisen gail leitha erlauf pielach kamp ager`) | match factor ×0.8; coverage weight 0.5; not required for "exact" |
| numeric | first char is a digit | optional in stop queries (skip cost 0.05); signals address intent |
| essential | everything else | coverage weight 1 |

### 3.4 Synonyms (canonical first)

Groups (every member matches every member exactly): `hbf hauptbahnhof hbhf` · `bf bahnhof bhf bhnf` ·
`bahnhst bahnhaltestelle bhst` · `hst haltestelle` · `st sankt` · `str strasse` · `wiener wr` · `abzw abzweigung` ·
`flughafen airport` · `karnten ktn` · `niederosterreich no` · `oberosterreich oo` · `steiermark stmk` ·
`burgenland bgld` · `vorarlberg vbg`.
City abbreviations (index form with factor 0.9 on the city token, so they apply to *every* stop of the city):
`innsbruck←ibk`, `salzburg←sbg,szbg`, `klagenfurt←klgft`, `wiener←wr`.
Weak synonyms (query canonical → name canonical): `bf→hbf 0.9`, `bf→bahnhst 0.85`, `hst→bahnhst 0.85`, `hst→bf 0.8`.
Record aliases curated in the dataset (`aliases.json`, Task A): `Flughafen Wien: VIE, Vienna Airport, Schwechat Flughafen`;
`Flughafen Wien Bahnhof: VIE`; `Innsbruck Hauptbahnhof: Ibk Hbf, INN Hbf`; `Wien Westbahnhof: Wien West`;
`Wien Hauptbahnhof: Wien Hbf, Wien Süd`; `Salzburg Hauptbahnhof: SZG Hbf` (extend with IATA codes GRZ, LNZ, KLU, INN, SZG).

### 3.5 Index forms of a name token (with factor)

In order, first occurrence wins: the token itself (1.0); its synonym-group members (1.0); its city abbreviations (0.9);
for a non-final token of a multi-part chunk the concatenation of the remaining parts (`maria-theresien-strasse` →
`mariatheresienstrasse`, `theresienstrasse`; 0.95); if the token ends with a split suffix (`hauptbahnhof bahnhof bahnhst
strasse gasse platz weg brucke allee kai gurtel ufer zeile steig siedlung kirche zentrum markt`, first match, ≥ 3 chars
remain) the head (0.8) and the suffix with its synonyms (0.8) (`westbahnhof` → `west`, `bahnhof`, `bf`, `bhf`, `bhnf`).
Split forms (factor 0.8) match only query tokens of ≥ 3 characters (so `w` never matches `…weg`).

### 3.6 Name variants and aliases

- Variant `"<Ort> <X>"` for a name `"X (Ort)"` when the bracket holds a known municipality (`"Floridsdorf (Wien)"` →
  `"Wien Floridsdorf"`). Municipality keys = folded Gemeinde names + folded locality names of class
  city/town/village/suburb + first tokens that start ≥ 3 stop names (7,031 keys on Task A; `golden_municipalities.json`).
- Each alias is a variant with factor **0.97**, or **0.85 for a local alias** (stop alias that lacks the name's first
  token, e.g. `"Jakominiplatz"` for "Graz Jakominiplatz", `"St. Johann"` for "Graz St.Johann"); local aliases get only
  half the exact bonus.

### 3.7 Query side

- Same fold/lex/abbreviations; tokens carry no forms. **Last token is partial** unless the text ends in space, `.` or `,`.
- Query keys of a token = the token + its synonym-group members (so `hbf` also probes `hauptbahnhof`).
- **Compound split** (only if the token has no dictionary prefix match, ≥ 6 letters, *and no fuzzy match*): split at the
  longest head (≥ 4 chars, must have dictionary matches) whose tail is a split suffix or synonym (`str` included), or —
  for the partial last token — a ≥ 2-char prefix of `strasse gasse platz bahnhof`.
  `mariahilferstrasse`, `mariahilferstr` → `mariahilfer` + `strasse`/`str`; `innsbruckhbf` → `innsbruck` + `hbf`.
  (The "no fuzzy match" guard is required: without it `insbruck` split into `ins`+`bruck` — caught by golden T35.)
- Limits [DECISION]: query truncated to 64 characters / 8 tokens.

---

## 4. Offline index

### 4.1 Dataset contract (Task A → engine)

Per stop (Task A `places.json` / `places.bin` v1 fields in brackets):

| Field | Required | Use |
|---|---|---|
| stable id (`id`, IFOPT `at:47:1187`) | yes | identity for recents/favourites/trips; must be stable across releases |
| display name (`name`, VAO style "Ort Haltestelle") | yes | matching + title |
| aliases (`aliases`) | no | variants; **add `aliasKind` official/osm/local** (see §12) |
| lat, lon | yes | proximity, nearest, dedupe |
| products (`modes`, HAFAS pCls bits) | yes | icons, mode class, rail detection |
| weekday departures (`weight`) | yes | importance |
| municipality name (`gem`), state (`state`) | yes | subtitle, municipality keys |
| HAFAS extId (`hafas`), EVA (`eva`) | no | D1 dedupe, TripSearch without lookup |
| legacy app ids (`legacy`) | yes | migrate existing trips/favourites (`osm:hub:…`, `wl:…`, `uic:…`) |

Per locality (`localities.json`): `id` (osm), `name`, `lat`, `lon`, `place` (city/town/village/suburb/hamlet/
neighbourhood/quarter), `main` (most-departures stop within 2.5 km whose name starts with the locality name), `gem`,
`state`, `pop`. Plus the municipality key list (§3.6).

### 4.2 Importance I ∈ [0, 1] [FIT]

Stops: `I = min(1, 0.30 + 0.35·D + 0.35·M)` with `D = min(1, ln(1+dep)/ln(3001))` and mode class
`M = 1.0` if pCls ∩ {1,4,8} (RJX/IC/NJ), `0.9` WESTbahn (4096), `0.6` regional/S (16|32), `0.55` U-Bahn (256),
`0.45` tram (512), `0.3` ship/cable (128|2048), `0.25` bus/SEV (64|2), else 0.
Fitted against `ln(1+wt)/ln(32768)` of 40 stops present in both (mean abs error 0.024, max 0.098).
A live row without offline match uses `ln(1+wt)/ln(32768)`; addresses/POIs use 0.6.
Localities: `I = clamp(I(main) + δ)`, δ = +0.01 city/town, −0.02 village/suburb, −0.10 otherwise.

### 4.3 Data structures (`BENCH PlaceIndex.swift`)

```
records[]            sorted by (importance desc, name, id); record id = position
forms[]              all index forms, unique, sorted by Unicode scalar value (UTF-8 bytes for binary search)
formLen[]            length in scalars
postStart[], postings[]   CSR: postings of form f = record ids ascending (= most important first)
recVarStart[] → varFactor[], varTokStart[] → tokFlags[] (u8), tokCanon[] (form id of canonical spelling),
                tokFormStart[] → tokForm[] (form id), tokFormFac[]           (flat, no per-candidate allocation)
trigrams: [trigram → [form id]]  over alphabetic forms ≥ 3 chars ("  x" padding, as in REF)
exact:    [canonical full name → [record id]]   for names and aliases
byId, byLegacyId: [String → record id]
grid:     [(⌊lat/0.009⌋, ⌊lon/0.0135⌋) → [record id]]   ≈ 1 × 1 km cells, stops only
```

Sizes on Task A (60,773 records): 40,819 forms, 203,672 postings, 67,799 variants, 165,296 tokens, 225,166
token-forms → ≈ 8–10 MB resident including names. Factors are stored as `Double` (or a `UInt8` code into
{1.0, 0.97, 0.95, 0.9, 0.85, 0.8}); **never `Float`**: `Float(0.8) > 0.8` in Double broke the split-form rule in the
first port.

### 4.4 Build and caching [DECISION]

Measured (Swift, Linux): JSON parse 0.8 s, record conversion 0.7 s, index build 1.7 s (tokenise 1.0 s, tables
0.7 s). Therefore:
1. Build on a background actor at app launch (priority `.utility`), from `places.bin` (no JSON on device).
2. Serialise the finished flat arrays to `Caches/places-index-v1-<datasetSHA>.bin`; next launches `mmap` it (< 100 ms).
3. Until ready, search falls back to the old `StationIndex` (1,487 stations) and shows no "Ort" rows.
4. Optional v2: Task A emits the index section itself (same normaliser, guarded by `fold_golden.json` in both CIs).

### 4.5 Candidate generation (per keystroke)

1. Compile the query (§3.7). For each query token: key prefix ranges in `forms` (two binary searches per key);
   `est` = Σ posting lengths via `postStart` (O(1) per range).
2. **Fuzzy** only for a token with no prefix range, ≥ 4 letters: trigram-count candidates (need ≥ |grams| − 3·limit
   shared trigrams), verified with bounded Damerau (OSA) *prefix-edit distance* (min over prefixes of length
   |q|−limit … |q|+limit); limit 1 for ≤ 6 chars, 2 above. Matching forms become single-form ranges.
3. **Generator** = the hard token (non-stopword, non-numeric) with the smallest `est` (first on ties).
4. Candidates = first **N_MAX = 1,500** distinct record ids of the union of the generator's posting lists — bitmap over
   records, scan in id order (= importance order). Plus every record in `exact[full canonical query]` and every
   favourite/recent id. All other tokens are verified while scoring.
5. If fewer than 3 records score and there are ≥ 2 hard tokens: **relaxed mode** — candidates = first 1,500 of the
   union of the two most selective tokens; one non-stopword token may stay unmatched (cost 0.40, §5.2).

Truncation only happens for very unselective input (`wien` est 2,602 → 1,500 scored); because postings are
importance-ordered, the dropped records are the least important ones, which would rank last anyway.

### 4.6 Nearest stops

Grid rings 0…2 around the cell of the point; collect stops ≤ `max_m`, sort by haversine distance; stop after ring ≥ 1
when ≥ k found. Optional product filter. Used for "In der Nähe", empty state, resolution (§7).

### 4.7 Personal index

Recents/favourites that are not offline records (addresses, POIs, live-only stops) live in a small personal index
(≤ 100 records, same structure, rebuilt on change) that is searched with the same scorer; rows get source `.personal`.

### 4.8 Complexity

Per keystroke: O(#keys · log #forms) for ranges + O(postings of generator) bitmap + O(min(N_MAX, est) · tokens) scoring
+ sort of the scored set. No allocation in the per-token loop (bitsets for used tokens, preallocated candidate buffer).

### 4.9 Measured latency

`PlaceSearchBench` (release, Swift 6.3.3, Linux x86-64, single core), Task A snapshot, every prefix of the 40 case
inputs + 12 stress inputs (`a, s, w, st, wi, ba, sankt, bahnhofstraße, hauptplatz, kirche, gemeindeamt, schule`),
min of 3 runs: **392 keystrokes: p50 0.46 ms, p95 3.14 ms, p99 3.85 ms, max 4.92 ms**; worst inputs `insbruc`
(fuzzy), `i`, `ba`, `San`, `in`. The Python reference is ~15× slower (median 5 ms) and only documents behaviour.
Device acceptance: Instruments p99 < 16 ms on iPhone 12 (§11.5).

---

## 5. Ranking formula

Reference: `REF text_score/final_score`, `BENCH Scoring.swift`. Weights (v1):

| Symbol | Value | Symbol | Value |
|---|---|---|---|
| W_text | 100 | W_imp | 40 |
| first | 0.15 | order | 0.05 |
| cov_exact / cov_partial | 0.20 / 0.10 | exact | 0.50 |
| skip stopword / numeric / relaxed | 0.05 / 0.05 / 0.40 | relaxed anchor | 0.25 |
| foreign (country ≠ at) | −20 | town not exact | −3 |
| town minor (hamlet, neighbourhood, quarter) | −12 | town in "Fahrt erfassen" | excluded |
| POI, no digit in query | −40 | POI with digit | 0 |
| address, no digit, no street token | −40 | address, street token (`str strasse gasse weg platz allee ring kai gurtel ufer zeile steig promenade lande damm` or token ending in strasse/gasse/str) | +10 |
| address with digit | +40 | live rank bonus | 5 × (1 − (rank−1)/10) |
| favourite | +35 | recent | 25 × 0.5^(ageDays/14) + 3 × min(uses, 5) |
| near (if location) | 8 × max(0, 1 − d/30 km); 16 × … if query ≤ 3 chars | near, generic-only query | 60 × max(0, 1 − d/20 km) |
| town exact factor by place | city 1.0, town 0.8, village/suburb 0.3, others 0 | | |

### 5.1 Token match m(q, t) — best over the forms f of name token t and keys k of query token q

| Case | m |
|---|---|
| f = k | 1.0 × fac(f) |
| k is a proper prefix of f (and fac > 0.8 or ‖k‖ ≥ 3) | (0.70 + 0.30·‖k‖/‖f‖) × fac if q is the partial last token, else (0.60 + 0.30·‖k‖/‖f‖) × fac |
| f is a fuzzy form of q at distance d | (0.50 − 0.10·(d−1)) × fac |
| weak synonym (canonical pair) | value from §3.4 |
| t is a qualifier | m × 0.8 |

### 5.2 Text score of a record (best over its variants, × variant factor)

1. Candidate pairs (i, j, m>0); weight w_i = max(2, ‖q_i‖). Greedy assignment by descending w_i·m (ties: higher i,
   higher j, higher m); each query token and name token used once.
2. Unassigned query tokens: stopword → +0.05 skip; numeric (non-address) → +0.05; otherwise → +0.40 and counts as
   "hard unmatched". More than 0 (strict) / 1 (relaxed) hard unmatched → record rejected.
3. `quality = Σ w_i·m_i / Σ w_i` (sum over assigned tokens and unassigned non-stopwords).
4. `first = 0.15` if query token 0 sits on name token 0 with m ≥ 0.7. `order = 0.05` if ≥ 2 assigned tokens appear in
   increasing name order.
5. `cov = (matched essential + 0.5 · matched qualifier) / (essential + 0.5 · qualifier)`;
   `completeness = 0.20·cov` if the last query token is complete or matched with m ≥ 0.95, else `0.10·cov`.
6. `exact = 0.50` iff every query token matched with m ≥ 0.95, none hard-unmatched, the last token is complete/exact,
   and **every non-stopword, non-qualifier name token (generic included)** is matched. So `wien` is exact for "Wien"
   but not for "Wien Hbf". Halved for POIs/addresses and local aliases; × town place factor.
7. `anchor = 0.25` in relaxed mode when some query token sits on name token 0 (keeps `Lech Postamt` on Lech).
8. Generic-only queries (`bahnhof`, `hbf`, `haltestelle`): first = order = completeness = exact = 0 (rank by place).
9. `text = (quality + first + order + completeness + exact + anchor − skips) × variantFactor`.

### 5.3 Final score and tie-breakers

`score = 100·text + 40·I + kind/intent terms + live rank bonus + proximity + personal boosts` (table above).
Ties: higher importance, shorter name, name (Unicode scalar order), id.

### 5.4 Worked example (Task A + `FX/lm_all_inns`)

`inns` vs "Innsbruck Hauptbahnhof": m = 0.70 + 0.30·4/9 = 0.833; first 0.15; essential = {innsbruck} → cov 1,
partial → 0.10; text 1.083 → 108.3 + 40·0.9659 = **146.97**; live rank 1 → +5 → **152.0**.
vs locality "Innsbruck" (city): same text 108.3 + 40·0.9759 − 3 (not exact) = 144.4; live meta 1170101 (rank 2, wt
26,650 → I 0.980) scored on its own: 108.3 + 39.2 − 3 + 4.5 = **149.0** → Hbf first, like Scotty.
`innsbruck` (Fahrt erfassen, towns excluded): Hbf 1.0 + 0.15 + 0.20 = 1.35 → 135 + 38.64 = **173.64**
(Swift and Python print the same value).

---

## 6. Live layer (LocMatch) and merge

### 6.1 When to call [DECISION]

- Only with live consent and `config.isEnabled(.oebbHafas)` (`LIVE` §E7, §A3.8).
- Query (after fold, without spaces) ≥ 3 characters, or contains a digit. Not for generic-only queries when a location
  is known (use LocGeoPos instead).
- Debounce **250 ms** after the last keystroke (Scotty web: 400 ms). Cancel the in-flight task on every keystroke
  (`Task.cancel` → `URLSessionTask.cancel`); at most one LocMatch in flight. LocMatch shares the `.oebbHafas` budget of
  `LIVE` §A2.3 (min interval 0.3 s, 40/min) and may use at most **20 of the 40 per minute** (a sliding-window counter in
  `PlaceSuggestService`), calling `acquire(maxWait: 0.5)`; if the throttle would wait longer, the live step is skipped
  for this keystroke (suggestions never queue behind TripSearch). On `.rateLimited`/`.circuitOpen` stay offline silently.
- Cache: `LIVE` §A3.5 (LRU 200, TTL 24 h), key = (fold-normalised, space-collapsed query, `ALL`).
  Prefix reuse: while the request for `innsbruck h` runs, the cached result for the longest cached prefix
  (`innsbruck`) is re-filtered with §6.4 and merged immediately.
- Request: §2.1 with `maxLoc 10`, `field "S"`, `type "ALL"`, name + `?`. Results for a query that is no longer
  the current text are dropped.

### 6.2 Parsing (domain `Location` + extras)

Per `LIVE` §A3.4 plus: `wt` (Int), `icoX → common.icoL[icoX].res/txtA` (POI category), `state` (`F`/`M` for addresses),
derived `stateCode` from extId (§2.3). Kind: `S` with `meta` and extId `11…` → **town**; other `S` → stop
(meta `12/13…` → station-like); `A` → address; `P` → POI. Address name `"PLZ Ort, Straße Nr"` → title `Straße Nr`,
subtitle `PLZ Ort`, match variant `"Straße Nr Ort PLZ"`. POI name `"Name, Straße Nr, PLZ Ort"` → title `Name`
(strip trailing `" (n)"`), subtitle the rest; tokens of the rest are secondary (match × 0.6, never "first").

### 6.3 Live row score

Same formula (§5) on the live name, `relaxed = true`, `I` from `wt`, live rank bonus 5 × (1 − (rank−1)/10).
Addresses and POIs keep **Scotty's relative order per kind**: each A (resp. P) row is capped at 0.5 below the previous
A (resp. P) row's score (HAFAS ranks POIs by a popularity we cannot see).

### 6.4 Plausibility filter

Keep a live row if it scores under §6.3 (≤ 1 hard-unmatched token) **or** some query token ≥ 3 letters is a prefix of,
or within prefix-edit distance 2 of, one of its tokens (score fixed at text 0.30). `xqzvvhjkq` → nothing; `wien w` →
Scotty's metas survive but rank below offline Wien Westbahnhof.

### 6.5 Collapses inside the live list

- **C1 meta pair:** two metas with equal `pCls`, equal `wt`, distance ≤ 60 m → one row: keep the station meta
  (extId `12…/13…`), add the other name as alias (still matches `Floridsdorf`, `Zell am See`), rank = min of both.
  Fixtures: `lm_all_wien` 10 → 7 rows, `lm_all_bregenz_bf` 10 → 8, `lm_all_zell_am_see`, `lm_all_seefeld` 10 → 9.
- **P1 POI duplicates:** same name after stripping `" (n)"`, ≤ 150 m → keep the first (`lm_all_hofburg` 10 → 9).

### 6.6 Dedupe offline ↔ live (and offline ↔ offline)

Same place if (first rule that applies):

| Rule | Condition |
|---|---|
| D0 | addresses/POIs never merge with stops; towns merge only with towns |
| D1 | equal HAFAS extId (offline `hafas`/`eva` vs live `extId`) |
| D2 | name similarity = 1.0 and (d ≤ 300 m, or d ≤ 600 m when either is a meta or both serve rail) |
| D3 | similarity ≥ 0.75 and d ≤ 150 m |
| D3′ | d ≤ 80 m and the last essential tokens are equal or one is a ≥ 4-char prefix of the other (VAO vs HAFAS naming) |
| D4 | towns: similarity = 1.0 and d ≤ 5 km |

Similarity = Jaccard over **essential canonical tokens** (generic, stopwords, qualifiers, numbers removed; for
`"X (Ort)"` the bracket municipality counts), maximised over names + aliases of both; a single extra token that is a
municipality key counts as equal (`Riedenburg` ≈ `Bregenz Riedenburg Bahnhst`).

Verified pairs (golden subset vs fixtures):

| Offline | Live | Result |
|---|---|---|
| Innsbruck Hauptbahnhof (eva 8100108) | Innsbruck Hbf 8100108 | same — D1 (78 m) |
| Wien Hauptbahnhof (eva 8103000) | Wien Hbf (U) meta 1290401 | same — D2 (116 m) |
| Lech am Arlberg Dorfhus | Lech Dorfhus 891302 | same — D3′ (sim 0.67, 10 m) |
| Hall-Thaur Bahnhof | Hall in Tirol-Thaur Bahnhst 8102105 | same — D1 |
| Salzburg-Süd S-Bahn | Salzburg Süd Bahnhst | same — D1 |
| Innsbruck Maria-Theresien-Straße | Innsbruck Maria-Theresien-Straße 791226 | same — D2 (7 m) |
| locality Innsbruck | town meta Innsbruck 1170101 | same — D4 (646 m) |
| Flughafen Wien Bahnhof | town meta Flughafen Wien 1193001 | different — D0 (stop vs town) |
| Innsbruck Westbahnhof | Innsbruck Hbf | different (sim 0.5, 1,056 m) |

On merge the **offline record is the identity** (stable id, municipality, state); it gains the live `lid`, `extId`,
`pCls` (union), importance = max(offline, wt-based), and its score becomes
max(offline score + best live rank bonus, best live row score). Merge works on **copies**: the prototype once mutated
shared index records and leaked live importance into later queries.

### 6.7 Final list

Sort by score (ties §5.3), then **diversity caps** on the visible list (overflow rows move to the end, never dropped):
addresses ≤ 2 (≤ 5 with a digit), POIs ≤ 3 (≤ 5 when the best row is a POI), towns ≤ 2 and one per canonical name
(`Seefeld` has 3 localities). Show 8 rows (+ "Mehr anzeigen" up to 20).

**Stability rule (UI) [DECISION]:** when live rows arrive, rows visible for ≥ 300 ms keep positions 1–3 unless the
newcomer scores ≥ 25 points higher than the row it would displace; at most one reorder per 500 ms; insertions animate
with opacity only.

### 6.8 Errors

Any `LiveError` → keep offline rows silently. If the query has address intent (digit or street token) and there are no
rows: footer „Adressen sind gerade nicht erreichbar – Haltestellen funktionieren offline.“ Without consent: last row
„Adressen & Orte über ÖBB suchen“ → consent card (`LIVE` §E7).

---

## 7. Picked place → KlimaTicket valuation

| Picked | Planner (TripSearch) | "Fahrt erfassen" (manual trip) |
|---|---|---|
| stop/station | `StationLinker.hafasLocation` (D1 extId → `A=1@L=<extId>@` without I/O) | the stop itself |
| town ("Ort") | HAFAS town meta if known (D4 merge or cache), else `main` stop | towns are not offered (excluded); typing a town name ranks its main station first (T38–T40) |
| address (`A=2`) / POI (`A=4`) | pass the HAFAS `lid` unchanged; HAFAS adds walk legs (`LIVE` fixture `tripsearch_vienna_urban_address_to_poi`); valuation counts ride legs only, walk legs are 0 € | resolve to a stop (below) |
| current location | `nearby()` first stop (`LIVE` §E3) | resolve |

**Resolution (address/POI/location → stop):**
1. Offline candidates: `nearest(k = 8, max 1,500 m)`; rank by `walkSeconds(d) − 300 · I` with `walkSeconds = 120 + 1.2·d`.
2. If live is allowed: LocGeoPos (coordinates rounded to 3 decimals, `maxDist 1000`, `maxLoc 10`, products
   `.klimaTicket`); add candidates with HAFAS `dist`/`wt`; D1–D3′ dedupe.
3. Pick the best; persist `TripEndpoint { place: PlaceRef (original), stopID, stopName, walkMeters }`; show
   „Ab Haltestelle {name} · {m} m · {min} min zu Fuß“ with [Ändern] (sheet with the next 3 candidates).
4. No stop ≤ 1,500 m → keep the coordinates; FareEstimator uses them; badge „Schätzung“.

Expected (golden, `REF resolve_to_stop` on Task A + `FX/gp_*`): `6020 Innsbruck, Maria-Theresien-Straße 1` →
"Innsbruck Maria-Theresien-Straße" (70 m offline; LocGeoPos reports the same stop at 73 m and dedupes, D2);
POI "Hofburg, 1010 Wien" → "Wien Habsburgergasse" (223 m) with and without LocGeoPos (LocGeoPos' nearest,
"Wien Albertinaplatz (Augustinerstraße)" 162 m, has wt 24 and ranks second); Lech (47.2107, 10.1426) →
"Lech am Arlberg Dorfhus" (10 m; LocGeoPos "Lech Dorfhus" 45 m dedupes, D3′).

---

## 8. Recents, favourites, empty state

- `planner.recents` (UserDefaults JSON, local only): last 20 picks `{PlaceRef, lastUsed, uses}`; show 5.
  `PlaceRef = {kind, id (offline id | lid), name, lat, lon, products, extId?, lid?}`.
- Favourites: explicit star (swipe action „Favorit“); max 20; local (sync later).
- Empty query, in this order, max 8 rows: „Aktueller Standort“ (if permission) · favourites (≤ 5) · recents not in
  favourites (≤ 5, newest first) · nearby stops (3, „{name} · {m} m · {min} min“) · top stations
  (Wien Hbf, Wien Westbahnhof, Salzburg Hbf, Innsbruck Hbf, Graz Hbf, Linz Hbf, St. Pölten Hbf, Klagenfurt Hbf,
  Villach Hbf, Bregenz).
  Golden (near Maria-Theresien-Straße, fav Innsbruck Hbf, recents Wien Westbahnhof + Hall in Tirol): Standort ·
  Innsbruck Hauptbahnhof · Wien Westbahnhof · Hall in Tirol · Innsbruck Maria-Theresien-Straße 71 m 3 min ·
  Innsbruck Museumstraße 119 m 4 min · Innsbruck Anichstraße/Rathausgalerien 202 m 6 min · Wien Hauptbahnhof.
- With text: personal ids are always scored (§4.5) and boosted (§5); they never appear unless they match.

---

## 9. Row presentation (UI fields)

| Kind | Leading SF Symbol | Title | Subtitle |
|---|---|---|---|
| station (rail) | `train.side.front.car` | display name | modes („Zug · S-Bahn · Bus“) · Bundesland |
| stop | by best mode: `tram.fill` (tram), `tram.fill.tunnel` (U), `bus.fill`, `cablecar.fill`, `ferry.fill` | display name | modes · Gemeinde if the name does not start with it |
| town | `mappin.and.ellipse` | locality name | „Ort · alle Haltestellen“ · Bundesland (planner only) |
| address | `mappin.circle.fill` | „Maria-Theresien-Straße 1“ | „6020 Innsbruck“ |
| POI | by category: `building.columns` tourism, `fork.knife`, `bed.double.fill`, `cross.case.fill`, `cart.fill`, `building.2.fill`, `theatermasks.fill`, `figure.run`, `airplane`, `car.fill` | POI name | category label (`txtA`) · „1010 Wien“ |
| favourite / recent / location | `star.fill` / `clock.arrow.circlepath` / `location.fill` | | |

- Display name = `LIVE` §C3.3 `DisplayNames` + strip arrow markers (`/\s*-+>\s*/` → space; 98 Task A names such as
  „Amstetten ---> Fa Avenarius“) + `St.X` → `St. X`.
- Mode chips from pCls in this order: Zug (1|4|8|16|4096), S (32), U (256), Tram (512), Bus (64|2), Seilbahn (2048),
  Schiff (128). Foreign rows: country chip („DE“, „CH“, „IT“).
- Distance (if location known): „1,2 km“. Matched characters bold (from the assignment, §5.2).
- VoiceOver: „{title}, {kind}, {modes}, {Bundesland}{, Favorit}{, {distance}}“.

---

## 10. API and integration

### 10.1 KlimaCore (Linux-testable)

```
Packages/KlimaCore/Sources/KlimaCore/Places/
  PlaceNormalizer.swift   §3   (port of BENCH Normalizer.swift)
  PlaceDataset.swift      §4.1 reader for places.bin v1 (+ municipality keys, aliases)
  PlaceIndex.swift        §4   (port of BENCH PlaceIndex.swift; + grid, byLegacyId, serialise/mmap)
  PlaceRanking.swift      §5   (port of BENCH Scoring.swift)
  LivePlaceMerger.swift   §6.2–6.7 (port of REF live_items/merge)
  PlaceSuggestService.swift  actor: debounce, cancel, cache, personal index, AsyncStream
  PlaceResolver.swift     §7
```

```swift
public struct PlaceSuggestion: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case station, stop, town, address, poi, currentLocation }
    public enum Source: Sendable { case offline, live, both, personal }
    public var id: String              // offline id | "loc:<osm>" | HAFAS lid for A/P
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var products: ProductMask
    public var coordinate: GeoPoint?
    public var placeID: String?        // offline record id
    public var live: Location?         // LIVE §A3.4 domain value when known
    public var poiCategory: String?
    public var score: Double
    public var source: Source
    public var isFavourite: Bool
    public var isRecent: Bool
}
public enum SuggestContext: Sendable { case planner, tripLog }
public actor PlaceSuggestService {
    public init(index: PlaceIndexProvider, timetable: (any TimetableService)?, personal: PersonalPlaces,
                liveAllowed: @escaping @Sendable () -> Bool, clock: any Clock<Duration> = ContinuousClock())
    /// Yields the offline list immediately, then the merged list (at most once per live response).
    public func suggestions(_ query: String, context: SuggestContext, near: GeoPoint?) -> AsyncStream<[PlaceSuggestion]>
    public func emptyState(context: SuggestContext, near: GeoPoint?) -> [PlaceSuggestion]
    public func resolveStop(_ s: PlaceSuggestion) async -> ResolvedStop      // §7
    public func record(pick: PlaceSuggestion)                               // recents
}
```

`TimetableService.locations(query, types: .all, maxResults: 10)` and `.nearby(…)` are reused unchanged
(`HafasClient` already throttles, caches and maps errors). `Location` gains three optional, Codable-compatible fields:
`weight: Int?` (`wt`), `iconResource: String?` (`icoL[icoX].res`, POI category) and `matchState: String?` (`state`, F/M).

### 10.2 App

- Planner search (`LIVE` §E3 root) and both endpoints of the trip editor use `PlaceSuggestService`
  (`.planner` vs `.tripLog`). The trip editor stores `TripEndpoint` (§7).
- Search runs in the service actor; the view model consumes the `AsyncStream`, applies §6.7 stability, and never
  blocks the main thread. Index readiness is published (`@Observable var isPlaceIndexReady`).

### 10.3 Privacy

LocMatch sends the typed text (no location). LocGeoPos coordinates rounded to 3 decimals (`LIVE` §A3.3). Recents stay
on device. No analytics on queries.

### 10.4 Migration

`StationIndex` (1,487 stations) remains for decoding old trips; Task A `legacy` ids map old `Station.id` →
new place id (`byLegacyId`). Existing `stations.json` aliases are already merged into Task A.

---

## 11. Test plan (Linux CI, `swift test --no-parallel`)

### 11.1 Fixtures to copy into `Tests/KlimaCoreTests/Fixtures/places/`

`fold_golden.json`, `golden_cases.json`, `golden_places_subset.json` (6,210 stops), `golden_localities_subset.json`
(1,032), `golden_municipalities.json` (together 2.2 MB, 0.3 MB gzipped), and `FX/lm_*.response.json` +
`FX/gp_*.response.json` (0.67 MB).

### 11.2 Unit tests

1. `PlaceNormalizerTests`: 55/55 golden entries (fold, tokens, flags, forms).
2. `PlaceIndexTests`: for every `golden_cases.json` case: `offline_top5` exact (planner, tripLog, context cases with
   `near`, `favourites`, `recents`, 45 extra queries). Seed municipality keys from the golden file.
3. `LivePlaceMergerTests`: for every case with `fixture`: `merged_top5` exact; C1 (`lm_all_wien` → 7 rows with aliases),
   P1 (`lm_all_hofburg` → 9), plausibility (`xqzvvhjkq` → none; `LIVE` fixture `locmatch_batch_mixed` svcRes[10]), HAMM errors (`lm_param_field_Z_innsbruck`,
   `lm_schema_unknown_*`) → offline rows only.
4. Dedupe table §6.6 (9 pairs) as explicit assertions.
5. Walk time: every `gp_*` row: `|120 + 1.2·dist − dur| ≤ 1`.
6. Request encoding: LocMatch body has exactly `input.loc.type/name`, `input.maxLoc`, `input.field` = `S`; name ends
   with `?`.
7. Service: debounce 250 ms, cancel on keystroke, single flight, stale responses dropped, prefix-cache reuse
   (FixtureTransport + test clock).

### 11.3 Golden cases (excerpt of `golden_cases.json`; Scotty = raw fixture order)

| ID | Input | Scotty live top-5 | Expected top-5 (offline Task A + live, merged) |
|---|---|---|---|
| T01 | `inns` | Innsbruck Hbf · Innsbruck · Innsbruck Westbahnhof · Wilten (Innsbruck) · Innsbruck Technik | **1** Innsbruck Hauptbahnhof · **2** Ort Innsbruck · **3** Innsbruck Westbahnhof · **4** Innsbruck Technik · **5** Innsbruck Bundesbahndirektion |
| T02 | `innsbruck h` | Innsbruck Hbf · Innsbruck · Innsbruck Hochhaus Schützenstraße · Innsbruck Höttinger Auffahrt · Innsbruck Haydnplatz | **1** Innsbruck Hauptbahnhof · **2** Innsbruck Hochhaus Schützenstraße · **3** Innsbruck Haydnplatz · **4** Innsbruck Höttinger Auffahrt · **5** Innsbruck Hegnerstraße |
| T03 | `wien w` | Wien Hbf (U) · Wien · Floridsdorf (Wien) · Wien Floridsdorf Bahnhof (U) · Hütteldorf (Wien) | **1** Wien Westbahnhof · **2** Wien Weißenböckstraße · **3** Wien Wallensteinplatz · **4** Wien Wienerbergbrücke · **5** Wien Wolf in der Au |
| T04 | `st anton` | St.Anton am Arlberg · St.Anton am Arlberg Bahnhof · St.Anton am Arlberg Alt St.Anton · St.Anton im Montafon Bahnhst · St.Anton am Arlberg Terminal West | **1** St. Anton am Arlberg Bahnhof · **2** Ort St.Anton am Arlberg · **3** St. Anton im Montafon Bahnhof · **4** St.Anton am Arlberg Terminal West · **5** St. Anton am Arlberg Posteinfahrt |
| T05 | `hall in` | Hall in Tirol Bahnhof · Hall in Tirol-Thaur Bahnhst · Hall in Tirol · Hall in Tirol Abzw Bahnhof · Hall in Tirol Alter Zoll | **1** Hall in Tirol Bahnhof · **2** Hall-Thaur Bahnhof · **3** Ort Hall in Tirol · **4** Hall in Tirol Burgfrieden · **5** Hall in Tirol Kurhaus |
| T06 | `Hall i.T.` | Hall i' th' Wood · Hall in Tirol Bahnhof · Hall in Tirol-Thaur Bahnhst · Hall in Tirol · Hall in Tirol Abzw Bahnhof | **1** Hall in Tirol Bahnhof · **2** Ort Hall in Tirol · **3** Hall-Thaur Bahnhof · **4** Hall in Tirol Kurhaus · **5** Hall in Tirol Burgfrieden |
| T07 | `ibk` | Innsbruck · POI Heilstättenschule am LKH. Ibk./Kinderklinik, … · Innsbruck Hbf · Imst · Imst-Pitztal Bahnhof | **1** Ort Innsbruck · **2** Innsbruck Hauptbahnhof · **3** Innsbruck Westbahnhof · **4** Innsbruck Fürstenweg · **5** Innsbruck Technik |
| T08 | `flughafen` | Flughafen Wien · Flughafen Wien Bahnhof · Flughafen Wien Busterminal · Flughafen Graz · Innsbruck Flughafen | **1** Flughafen Wien Bahnhof · **2** Ort Flughafen Wien · **3** Flughafen Wien Busterminal · **4** Flughafen Graz-Feldkirchen Bahnhof · **5** Flughafen Linz |
| T09 | `Stephansplatz` | POI Stephansdom, Stephansplatz 3, 1010 Wien · Wien Stephansplatz (U) · POI Souvenir Jelesitz … · POI Souvenir outlet … · POI Alte Feldapotheke … | **1** Wien Stephansplatz · **2** POI Stephansdom, Stephansplatz 3, 1010 Wien · **3** POI Souvenir Jelesitz, Stephansplatz 11, 1010 Wien · **4** POI Souvenir outlet, Stephansplatz 10, 1010 Wien · **5** POI Alte Feldapotheke, Stephansplatz 8a, 1010 Wien |
| T10 | `Maria-Theresien-Straße 1 Innsbruck` | Adr 6020 Innsbruck, Maria-Theresien-Straße 1 · Innsbruck Maria-Theresien-Straße · POI Manna … · POI MPREIS … · POI Müller … | **1** Adr 6020 Innsbruck, Maria-Theresien-Straße 1 · **2** Innsbruck Maria-Theresien-Straße · **3** POI Manna, Maria-Theresien-Strasse 3, 6020 Innsbruck · **4** POI MPREIS, Maria-Theresien-Strasse 31, 6020 Innsbruck · **5** POI Müller, Maria-Theresien-Strasse 18, 6020 Innsbruck |
| T11 | `Hofburg` | POI Hofburg, Rennweg 1, 6020 Innsbruck (1) · POI … (2) · POI Hofburg, 1010 Wien · Innsbruck Congress/Hofburg · POI Hofburgkapelle, 1010 Wien | **1** POI Hofburg, Rennweg 1, 6020 Innsbruck · **2** POI Hofburg, 1010 Wien · **3** Innsbruck Congress/Hofburg · **4** Adr 1010 Wien, Hofburg · **5** POI Hofburgkapelle, 1010 Wien |
| T12 | `Lech Postamt` | Lech Dorfhus · Höchst/Rhein Postamt · Landeck Postamt · Sölden Postamt · Niederndorf in Tirol Postamt | **1** Lech am Arlberg Dorfhus · **2** Ort Lech · **3** Sölden Postamt · **4** Lech am Arlberg Rüfiplatz · **5** Lech am Arlberg Feuerwehrhaus |
| T13 | `wien` | Wien · Wien Hbf (U) · Floridsdorf (Wien) · Wien Floridsdorf Bahnhof (U) · Hütteldorf (Wien) | **1** Ort Wien · **2** Wien Hauptbahnhof · **3** Wien Hütteldorf · **4** Wien Floridsdorf · **5** Wien Westbahnhof |
| T14 | `Wien Hbf` | Wien Hbf (U) · Wr.Neustadt Hbf · POI B&B Hotel Wien-Hbf … · Wien · Floridsdorf (Wien) | **1** Wien Hauptbahnhof · **2** Wien Blechturmgasse · **3** Wiener Neustadt Hauptbahnhof · **4** Wien Hauptbahnhof Ost · **5** Wien Hauptbahnhof Autoreisezug |
| T15 | `Salzburg` | Salzburg · Salzburg Hbf · Salzburg Süd Bahnhst [in Elsbethen] · Salzburg Süd Bahnhst · Itzling (Salzburg) | **1** Ort Salzburg · **2** Salzburg Hauptbahnhof · **3** Salzburg-Süd S-Bahn · **4** Ort Salzburg-Süd · **5** Salzburg Aiglhof S-Bahn |
| T16 | `graz hbf` | Graz Hbf · Puntigam (Graz) · Graz Puntigam Bahnhof · Graz Don Bosco Bahnhst · Graz Hilmteich/Botanischer Garten | **1** Graz Hauptbahnhof · **2** Graz Daungasse/Hauptbahnhof · **3** Graz Hauptbahnhof Autoreisezug · **4** Graz Puntigam Bahnhof · **5** Graz Don Bosco Bahnhst |
| T17 | `linz` | Linz/Donau Hbf · Linz/Donau · Linz/Donau Untergaumberg Bahnhst · Urfahr (Linz) · Linz/Donau Urfahr Bahnhof | **1** Ort Linz · **2** Linz/Donau Hauptbahnhof · **3** Linz/Donau Untergaumberg · **4** Linz/Donau Urfahr Bahnhof · **5** Linz/Donau Ebelsberg Bahnhof |
| T18 | `Karlsplatz` | Wien Karlsplatz (U) · POI Karlskirche … · POI Kunsthalle Wien Karlsplatz … · POI Künstlerhaus Wien … · Karlstetten Schlossplatz | **1** Wien Karlsplatz · **2** Wien Oper/Karlsplatz U · **3** Wien Bösendorferstraße/Karlsplatz U · **4** München Karlsplatz · **5** POI Karlskirche, Karlsplatz 10, 1040 Wien |
| T19 | `Zell am See` | Zell am See · Zell am See Bahnhof · Zell am See Seespitz · Zell am See Badhaus · Zell am See Friedhof | **1** Zell am See Bahnhof · **2** Ort Zell am See · **3** Zell am See Seespitz · **4** Zell am See Badhaus · **5** Zell am See Friedhof |
| T20 | `St. Johann` | St.Johann im Pongau Bahnhof · Alt St. Johann, Dorf · POI St. Johann, Strassburg · POI St. Johann am Walde … · POI St. Johann am Wimberg … | **1** St. Johann im Pongau Bahnhof · **2** St. Johann im Rosental Alter Bahnhof · **3** Ort St. Johann · **4** Graz St.Johann · **5** St. Johann in Tirol Bahnhof |
| T21 | `Mariahilfer Straße` | POI Mariahilferbräu … · Wien Neubaugasse (U) · Wien Kaiserstraße/Mariahilfer Straße · POI Mariahilf … · Adr 1010 Wien, Passage Mariahilfer Straße | **1** Wien Museumsquartier · **2** Adr 1010 Wien, Passage Mariahilfer Straße · **3** Adr 1060 Wien, Mariahilfer Straße · **4** Wien Mariahilfer Straße/Kaiserstraße · **5** Wien Mariahilfer Straße/Geibelgasse |
| T22 | `Schönbrunn` | Schönbrunn b.Böheimkirchen Abzw Wiesen · POI Schönbrunn Brezel … · POI Schönbrunn-Vorpark … · POI Schönbrunner Bad … · POI Schönbrunner Panoramabahn … (1) | **1** Wien Schönbrunn · **2** Schönbrunn/Böheimkirchen Abzw. Wiesen · **3** Wien Schloss Schönbrunn · **4** Wien Schönbrunner Allee · **5** Wien Margaretenplatz/Schönbrunner Straße |
| T23 | `Nordkette` | POI Nordkette Shop … · Innsbruck Nordkette · POI Nordketten Standle, 6020 · POI Tiroler Berglerbund Nordkette, 6020 · POI Haus Nordkettenblick … | **1** Innsbruck Nordkette · **2** POI Nordkette Shop, Herzog-Friedrich-Strasse 22, 6020 Innsbruck · **3** POI Nordketten Standle, 6020 · **4** POI Tiroler Berglerbund Nordkette, 6020 · **5** Adr 6020 Innsbruck, Nordkettenstraße |
| T24 | `Gmunden` | Gmunden · Gmunden Bahnhof · Gmunden Bezirkshauptmannschaft · Engelhof (Gmunden) · Gmunden Franz-Josef-Platz | **1** Ort Gmunden · **2** Gmunden Bahnhof · **3** Gmunden Bezirkshauptmannschaft · **4** Gmunden Klosterplatz · **5** Gmunden Keramik |
| T25 | `Bregenz Bf` | Bregenz Bahnhof · Bregenz · Bregenz Barbenweg · Bregenz Blumenegg · Bregenz Brachsenweg | **1** Bregenz Bahnhof · **2** Bregenz Riedenburg Bahnhof · **3** Bregenz Hafen Bahnhof · **4** Bregenz Wendeplatz Bhf. · **5** Bregenz Hafen Bhf Ersatz |
| T26 | `Seefeld` | Seefeld in Tirol · Seefeld in Tirol Bahnhof · Seefeld in Tirol Birkenlift Talstation · Seefeld in Tirol Leutascher Straße · Seefeld in Tirol Mittelschule | **1** Seefeld in Tirol Bahnhof · **2** Ort Seefeld · **3** Ort Seefeld in Tirol · **4** Seefeld in Tirol Mittelschule · **5** Seefeld in Tirol Birkenlift |
| T27 | `Westbahnhof` | Westbahnhof, Aachen · Westbahnhof, Landau in der Pfalz · Westbahnhof, Mülheim an der Ruhr · Westbahnhof, Tübingen · Westbahnhof, Bonn | **1** Wien Westbahnhof · **2** Villach Westbahnhof · **3** Innsbruck Westbahnhof · **4** Westbahnhof, Aachen · **5** Westbahnhof, Tübingen |
| T28 | `schwaz` | Schwaz · Schwaz Bahnhof · Schwaz Schwimmbad · Schwaz Adlerwerk · Schwaz Arbeitsamt/Tyrolit | **1** Schwaz Bahnhof · **2** Ort Schwaz · **3** Schwaz Schwimmbad · **4** Schwaz Adlerwerk · **5** Schwaz Tyrolit |
| T29 | `St. Pölten` | St.Pölten Hbf · St.Pölten · St.Pölten Alpenbahnhof-Kaiserwald · St.Pölten Leobersdorfer Bahnstraße · St.Pölten Porschestraße Bahnhst | **1** Ort St. Pölten · **2** St. Pölten Hauptbahnhof · **3** St. Pölten Porschestraße · **4** St.Pölten Alpenbahnhof-Kaiserwald · **5** St.Pölten Leobersdorfer Bahnstraße |
| T30 | `st polten` | St.Pölten Ing.-Leopold-Figl-Straße · St.Pölten Hbf · St.Pölten · St.Pölten Alpenbahnhof-Kaiserwald · St.Pölten Leobersdorfer Bahnstraße | **1** Ort St. Pölten · **2** St. Pölten Hauptbahnhof · **3** St. Pölten Porschestraße · **4** St.Pölten Alpenbahnhof-Kaiserwald · **5** St.Pölten Leobersdorfer Bahnstraße |
| T31 | `St Poelten Hbf` | St.Pölten Hbf · St.Pölten · St.Pölten Alpenbahnhof-Kaiserwald · St.Pölten Leobersdorfer Bahnstraße · St.Pölten Porschestraße Bahnhst | **1** St. Pölten Hauptbahnhof · **2** St. Pölten Hbf./Kremser Landstr. · **3** Ort St. Pölten · **4** St. Pölten Alpenbahnhof-Kaiserwald · **5** St. Pölten Porschestraße |
| T32 | `Sankt Pölten Hauptbahnhof` | St.Pölten Hbf · St.Pölten · POI Schülerhilfe … · POI Skoda … · POI Seminarzentrum Schwaighof … | **1** St. Pölten Hauptbahnhof · **2** St. Pölten Hbf./Kremser Landstr. · **3** Stuttgart Hauptbahnhof 1 · **4** Ort St. Pölten · **5** St. Pölten Bildungscampus Bahnhof |
| T33 | `kitzbuehel` | Kitzbühel Bahnhof · Kitzbühel Hahnenkamm Bahnhof · Kitzbühel Zentrum · Kitzbühel Schwarzsee Bahnhst · Kitzbühel | **1** Kitzbühel Bahnhof · **2** Ort Kitzbühel · **3** Kitzbühel Hahnenkamm Bahnhof · **4** Kitzbühel Zentrum · **5** Kitzbühel Schwarzsee Bahnhof |
| T34 | `Kitzbuhel` | POI Kitzbuheler Handarbeiten … · Kitzbühel Bahnhof · Kitzbühel Hahnenkamm Bahnhof · Kitzbühel Zentrum · Kitzbühel Schwarzsee Bahnhst | **1** Kitzbühel Bahnhof · **2** Ort Kitzbühel · **3** Kitzbühel Hahnenkamm Bahnhof · **4** Kitzbühel Zentrum · **5** Kitzbühel Schwarzsee Bahnhof |
| T35 | `insbruck` | POI Institut Doringer … · POI Institut für Botanik … · POI Institut für Psychosoziale Intervention … · POI Institut für Theorie … · Innsbruck Chemieinstitut | **1** Innsbruck Hauptbahnhof · **2** Ort Innsbruck · **3** Innsbruck Fürstenweg · **4** Innsbruck Westbahnhof · **5** Innsbruck Radetzkystraße |
| T36 | `innsbruk` | Innsbruck Hbf · Innsbruck · Innsbruck Westbahnhof · Wilten (Innsbruck) · Innsbruck Technik | **1** Innsbruck Hauptbahnhof · **2** Ort Innsbruck · **3** Innsbruck Westbahnhof · **4** Innsbruck Bundesbahndirektion · **5** Innsbruck Fürstenweg |
| T37 | `Woergl` | Wörgl Hbf · Wörgl · Wörgl Süd-Bruckhäusl Bahnhst · Wörgl Abzw Bodensiedlung · Wörgl Abzw Wildschönau | **1** Ort Wörgl · **2** Wörgl Hauptbahnhof · **3** Wörgl Süd-Bruckhäusl Bahnhof · **4** Wörgl Abzw Bodensiedlung · **5** Wörgl Abzw Wildschönau |
| T38 | `inns` (Fahrt erfassen) | (as T01) | **1** Innsbruck Hauptbahnhof · **2** Innsbruck Westbahnhof · **3** Innsbruck Technik · **4** Innsbruck Bundesbahndirektion · **5** Innsbruck Fürstenweg |
| T39 | `innsbruck` (Fahrt erfassen) | – (offline only) | **1** Innsbruck Hauptbahnhof · **2** Innsbruck Fürstenweg · **3** Innsbruck Westbahnhof · **4** Innsbruck Radetzkystraße · **5** Innsbruck Mitterhoferstraße |
| T40 | `wien` (Fahrt erfassen) | (as T13) | **1** Wien Hauptbahnhof · **2** Wien Hütteldorf · **3** Wien Floridsdorf · **4** Wien Westbahnhof · **5** Wien Meidling |

Why we differ from Scotty (intended): T03, T27 (Austrian stops first, single-letter tokens work), T06 (`i.T.`), T35
(typo), T09/T21/T22 (stops before POIs unless the POI name itself matches, Scotty's POI order kept), T07/T13/T15
(locality rows from Task A instead of meta duplicates), T11 (POI `(2)` duplicate removed), T12 (offline VAO name
"Lech am Arlberg Dorfhus" merged with HAFAS "Lech Dorfhus", D3′). Positions 4–5 inside one town are importance-driven
and may legitimately change with a new dataset release; when the dataset changes, regenerate the goldens with
`regen_all.sh` and review the diff instead of hand-editing.

Context cases (offline only):

| Input | Context | Expected top-5 |
|---|---|---|
| `bahnhof` | near Innsbruck (47.2654, 11.3928) | **1** Innsbruck Hauptbahnhof · **2** Innsbruck Messe Bahnhof · **3** Innsbruck Hötting Bahnhof · **4** Innsbruck Allerheiligenhöfe Bahnhof · **5** Rum (Tirol) Bahnhof |
| `hbf` | near Graz (47.0707, 15.4395) | **1** Graz Hauptbahnhof · **2** Graz Daungasse/Hauptbahnhof · **3** Graz Hauptbahnhof Autoreisezug · **4** Wien Hauptbahnhof · **5** Linz/Donau Hauptbahnhof |
| `wien` | favourite Wien Meidling (`at:49:1015`) | **1** Ort Wien · **2** Wien Meidling · **3** Wien Hauptbahnhof · **4** Wien Westbahnhof · **5** Wien Hütteldorf |
| `inns` | recent Innsbruck Westbahnhof (2 days, 3 uses) | **1** Innsbruck Westbahnhof · **2** Innsbruck Hauptbahnhof · **3** Ort Innsbruck · **4** Innsbruck Fürstenweg · **5** Innsbruck Radetzkystraße |
| `vie` | IATA alias | **1** Flughafen Wien Bahnhof · **2** Viehofen Bahnhof · **3** Ort Viehofen · … |
| `wr neustadt` | abbreviation | **1** Ort Wiener Neustadt · **2** Wiener Neustadt Hauptbahnhof · **3** Wiener Neustadt Nord · … |
| `bruck mur` | river qualifier | **1** Bruck an der Mur Bahnhof · **2** Ort Bruck an der Mur · … |
| `bahnhof` | no location | unordered set of large stations (no assertion beyond "all rows are stations") |

Extra queries (offline, top-3, all in `golden_cases.json` as context `extra`): `mariahilferstrasse` / `mariahilferstr` /
`mariahilferst` → Wien Museumsquartier · Wien Mariahilfer Straße/Geibelgasse · Wien Mariahilfer Straße/Kaiserstraße;
`innsbruckhbf` → Innsbruck Hauptbahnhof …; `hallthaur` → Hall-Thaur Bahnhof; `praterstern` → Wien Praterstern;
`landeck zams` → Landeck-Zams Bahnhof …; `jakominiplatz` → Graz Jakominiplatz; `linz taubenmarkt` → Linz/Donau
Taubenmarkt …; `lienz` → Lienz (Tirol) Bahnhof · Ort Lienz …; `krems` → Krems an der Donau Bahnhof · Ort Krems …;
`baden` → Baden bei Wien Bahnhof …; `6020` → no offline row (postcodes are live-only).
Known limitation: `west bahnhof` (space inside a compound) finds "Westendorf (Tirol) Bahnhof" first — a query token
pair cannot yet match one name token (v2: try the concatenation of the last two tokens as an extra generator).

### 11.4 How the goldens were produced

`REF cases` (Python) on the Task A snapshot + fixtures → `work/cases_taskA.json`; `BENCH` (Swift) → `work/swift_bench.json`;
`tools/golden.py` asserts Swift = Python (89/89 offline lists), rebuilds the subset and asserts it reproduces 93/93 lists.

### 11.5 Performance gates

- CI (opt-in, release build): full Task A dataset, all prefixes of the golden inputs: p99 < 8 ms, max < 15 ms.
- Device (manual, `LIVE` §D4 list): Instruments Time Profiler on iPhone 12, typing „Maria-Theresien-Straße 1 Innsbruck“
  and „wien w“: no frame drop, search p99 < 16 ms; index ready < 3 s after a cold first launch, < 150 ms afterwards.

---

## 12. Findings for Task A (dataset)

1. **Alias kinds:** 2,544 of 6,947 aliases lack the municipality prefix (local names) and some OSM aliases leak
   neighbouring places ("Wien Blechturmgasse" alias „Wien, Hbf. (International Busterminal)“, "Wien Museumsquartier"
   alias „Mariahilfer Straße“ → T14 #2 and T21 #1). Emit `aliasKind` (official/vao, osm, local) so the engine can weight
   them (§3.6); drop OSM aliases that contain another stop's full name.
2. **Name hygiene:** 98 names contain arrow markers (`--->`, `-->`, `->`); provide a cleaned display name.
3. **Locality noise:** 13,620 hamlets; several same-name localities (`Seefeld` ×3, `Sankt Johann` ×7). Keep them (they
   help villages without a same-name stop) but the engine penalises minor places (§5) and caps towns (§6.7).
4. **HAFAS extIds:** only 258 stops carry `hafas`; 6-digit Verbund extIds for bus stops are learnt at runtime (D2/D3′
   merge) — persist learnt `(placeID → extId)` pairs in the `StationLinker` cache so D1 applies next time.
5. **Municipality key list:** ship it (from the Gemeinden section) so tests and app use the same 7,031 keys.

## 13. Risks and open questions

- HAFAS may change `wt` semantics or tighten the HAMM schema (any unknown key fails the whole envelope): keep the
  request byte-identical to §2.1; contract test against `lm_all_inns`.
- Fuzzy `?` has no measurable effect today; if ÖBB changes that, typo handling still comes from the offline index.
- Ranking weights are tuned on 40 inputs; collect anonymous, on-device "picked rank" counters (no query text) in a
  later release before re-tuning.
- `west bahnhof`-style split compounds (§11.3 limitation); addresses only online.

## Appendix A. Artefacts

| Path | Content |
|---|---|
| `$SC/fixtures/*.request.json`, `*.response.json` | 63 scenarios (`lm_all_*` 39, `lm_all_nonfuzzy_*` 6, `lm_{S,A,P,SP}_*` 9, `lm_param_*` 3, `lm_schema_*` 3, `gp_nearby_*` 3) + 4 raw batch envelopes; FX/hafas format of `LIVE` §D1 (`_meta.splitFrom` marks split batches) |
| `$SC/fixtures/INDEX.json` | per scenario: request params, error, result count, top-3 |
| `$SC/tools/probe.py`, `resplit.py`, `schema_probe.py`, `field_probe.py`, `dump.py` | live probe (polite) and fixture tools |
| `$SC/tools/suggest.py` | executable reference of §3–§8 (Python 3, stdlib) |
| `$SC/tools/golden.py`, `regen_all.sh` | cross-checks and golden generation |
| `$SC/swift/PlaceSearchBench/` | Swift reference of §3–§5 + benchmark (`swift build -c release`) |
| `$SC/golden_cases.json`, `fold_golden.json`, `golden_places_subset.json`, `golden_localities_subset.json`, `golden_municipalities.json` | test data (§11) |
| `$SC/test_corpus.json` | earlier stand-in corpus (app stations + fixture stops); superseded by the Task A subset |
| `$SC/work/` | snapshot of Task A, raw outputs (`cases_taskA.*`, `swift_bench.json`, `dump.txt`) |
