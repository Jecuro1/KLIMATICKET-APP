# KlimaBilanz · Stop enrichment v2: every line, ski areas, regions, “Wegzeichen” badges, stop detail

**Implementation spec v1 · 2026-10-09 · lead architect**

> **Repo copy (Step 0, 2026-10-09).** This is the implementation spec as handed over by the lead architect, copied into
> the repository so every work package can read it. Changes against the original:
> - **Paths** point into the repository. Artefacts that only existed in the authoring session (prototypes, raw
>   enrichment outputs, mockups, the OEBB contract drafts) are written as `$S/…` and marked *session artefact*; their
>   results reach the repo through the work packages (Step 0 fixtures: `Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/v2/`,
>   written by `scripts/places_v2_fixtures.py`; Python ports: WP-D1).
> - **Trunk-based:** the project now commits straight to `main`. Branch names in §0.2 and §5 (`claude/klimabilanz-ios-app`,
>   `wip/enrich-*`) are historical; the merge order of §5 still holds, every step lands on `main`.
> - **Logos – superseded by [`docs/LOGO_SPEC.md`](LOGO_SPEC.md):** the owner decided that original logos are shown
>   („es müssen schon original logos auch sein … bundesland logos mit wappen“). LOGO_SPEC replaces **D10**, **§1.10.3**,
>   **§1.10.4**, the „Zeichen und Namen“ text of **§1.10.2** and the Wappen/arms part of **AT-U6**:
>   Landeswappen (all states except Niederösterreich) ship in the app bundle; ski-area and region logos come only through
>   the Cloudflare logo pack and are never committed; KlimaCore gets the pure parts (`Logos/LogoPack.swift`: `LogoConfig`,
>   manifest, `StoredZip`, installer, `BrandResolver`/`StopBrands`, `Landeswappen.assetName`). The own „Wegzeichen“
>   badges of this spec remain the built-in rendering and the fallback everywhere (no pack, revoked brand, switch off).
>   The seam for brand marks in rows and the detail hero is `PlaceMarkSelection.rowAreaMark` / `heroAreaCells`
>   (`CORE/Places/Presentation/PlaceMarkSelection.swift`, LOGO_SPEC §4.1).

**User request (verbatim):** „Es müssen alle Linien drinnen sein jede Haltestellen die es nur gibt und die sollen auch gute markiert mit mehreren icons sein wie dem Ski ARLBERG Logo sowie dem Landes Logo alles was dazu halt passt meine App muss sich von anderen stark abheben“

In short:
1. Every stop (all 39,711) shows **every line** that serves it, with mode, operator, termini and seasonal flags.
2. Stops are **marked with several icons**: Bundesland, ski area, region, special places (main station, valley station, airport, P+R, barrier-free …), KlimaTicket validity.
3. The marking is our **own design** („Wegzeichen“, docs: `enrich/design/BADGE_SPEC.md`). The **Ski Arlberg logo and the Landeswappen/Landeslogos are not used** (trademark / state laws, §1.10). The names appear as text, next to our own glyphs and the state colours as stripes. This is the legally safe way to the same effect, and it is what makes the app distinctive.
4. Reference case that must work perfectly: typing **„Warth am Arlberg Dorfplatz“** puts `at:48:344` „Warth (Vorarlberg) Dorfplatz“ first. Its row shows **Vorarlberg · Ski Arlberg · 110 · 852 · Skibus**.

---

## 0. How to read this document

| Tag | Meaning |
|---|---|
| **[MEASURED]** | Produced by the prototypes in `$SPEC/` on the real data on 2026-10-09. The numbers are reproducible. |
| **[DATA]** | Taken from the enrichment outputs (`$LINES`, `$TAGS`) or their reports. |
| **[DESIGN]** | Taken from `$DESIGN/BADGE_SPEC.md`. That document stays the visual source of truth. |
| **[DECISION]** | Architect decision. Binding for the work packages. |

### 0.1 Paths

| Abbreviation | Path |
|---|---|
| `$S` | session scratchpad of the authoring session (**not in the repo**; everything needed long term is copied into the repo by WP-D1 / Step 0) |
| `$PLACES` | base pipeline: `scripts/build_places.py`, `scripts/extract_osm_places.py`, `scripts/fetch_places_sources.sh`; build outputs `build/places/places.json`, `build/places/localities.json`, downloads `build/places-dl/` |
| `$LINES` | line enrichment (session artefact `$S/enrich/lines/`, ported by WP-D1 to `scripts/build_lines.py`, `scripts/extract_osm_routes.py`); outputs `build/lines_full/` (with OSM), `build/lines_official/` (without OSM); Scotty samples `live/` (session artefact) |
| `$TAGS` | tag enrichment (session artefact `$S/enrich/tags/`, ported by WP-D1 to `scripts/build_tags.py`, `scripts/places_curated.py`, `scripts/extract_osm_tags.py`); `spot_checks.json`; outputs `build/tags/tags.json`, `tags_app.json` |
| `$DESIGN` | design hand-off (session artefact `$S/enrich/design/`: `BADGE_SPEC.md`, `swift/Wegzeichen.swift`, `mockups/*.png`, `tokens_check.json`); lands with WP-U1 |
| `$SPEC` | prototypes of this spec (session artefact `$S/enrich/spec/`: `encode_v2.py`, `show_v2.py`, `proto_context_search.py`, `swift/Inflate.swift`, `swift/main.swift`, outputs `out_*`). Swift port: `CORE/Places/Format/` (WP-C1); Python port: `scripts/build_places.py` (WP-D1); small v2 fixtures from `encode_v2.py`: `Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/v2/` |
| `REPO` | the repository root, branch `main` (trunk-based) |
| `CORE` | `Packages/KlimaCore/Sources/KlimaCore/` |

### 0.2 Baseline

- **`wip/places` is merged.** It landed in `claude/klimabilanz-ios-app` as `62351c3` (2026-10-09 14:55). That merge brought `PlaceIndex`, `PlaceDataset` (v1 reader), `App/Resources/places.bin` (3,060,746 B) and `localities.bin` (1,482,788 B), `scripts/build_places.py` and `scripts/places_reference.py`. All work packages here start from `claude/klimabilanz-ios-app` at or after `62351c3`. **Do not** commit to `wip/places`.
- **The ÖBB live layer (OEBB_LIVE WP-A: `HafasClient`, `StationLinker`, `TimetableService`) is on no branch yet.** Its contract types exist in `$S/oebb/contracts/` (session artefact; see `docs/OEBB_LIVE.md`). Live completion (§4) is therefore specified against those contracts, and the app stays **offline only** until WP-A merges.
- **Parallel branches touch files we need** (checked with `git diff --name-only`):
  - `TripEditorView.swift`: `wip/p2-tripmeta`, `wip/p2-live`
  - `TripListComponents.swift`: `wip/p2-tripmeta`
  - `WidComponents.swift`: `wip/polish-widgets`
  - `DashSupport.swift`: `wip/polish-dashboard`
  - `RootView.swift`: nearly every branch

  §5 schedules the edits to these files last and keeps them minimal.

---

## 0.3 Summary of binding decisions

| # | Decision |
|---|---|
| D1 | **Format:** the places data becomes **KBPL v2**, a section container with a directory and per-section raw DEFLATE. It is spread over **three files** so the licences stay separate: `places.bin` (official sources, no OSM), `stops_osm.bin` (new, ODbL) and `localities.bin` (ODbL, rewrapped). Everything the app needs fits in **2,036,472 B on disk [MEASURED]**. Today's v1 files take 4,543,534 B, so the bundle shrinks by 2.5 MB even though every line and tag is added. |
| D2 | **Decoding:** a **pure-Swift `Inflate`** (RFC 1951) in KlimaCore, one code path on iOS and Linux CI. A CRC-32 per section guards it. It decodes all three files in **≈ 43 ms** (Swift 6.3.3 `-O`, one x86 core) **[MEASURED]**. Fuzzing 300 corruptions gave 0 traps, and the CRC caught all 13 silent ones. |
| D3 | **Licence layering:** OSM-derived content goes only into ODbL files. These are OSM-only lines, OSM line attributes, ski areas, lifts, POI types and wheelchair data. The app **merges the layers at runtime**, the same way `places.bin` and `localities.bin` are handled today. If the OSM layer is missing or belongs to another build (`BASE` mismatch), the app runs on the official layer alone. |
| D4 | **Lines model:** `Place.lines: [LineRef]` (the type of the existing internal `lines: String?` changes) plus `PlaceIndex.stopLines(for:) -> [StopLine]` for the detail screen. Compact rows show timetable-confirmed lines and special services. Lines known only from OSM appear in the detail with their source. |
| D5 | **Tags model:** `Place.tags: PlaceTags` (ski area, regions, special types, services, lift, accessibility, KlimaTicket validity, Gemeinde/Bezirk). Lookup tables: `SkiArea`, `Region`, operators, networks, lifts. |
| D6 | **Search:** **context words**. Ski-area, region and Bundesland names in a query (after the first word) count as a match when the place lies there (+10 points) and as a penalty when it does not (−30). „warth am arlberg dorfplatz“ then scores 207.6 against 63.5 for the next result, and „warth vorarlberg“ no longer ranks Warth/NÖ **[MEASURED]**. |
| D7 | **Presentation logic is pure Swift in KlimaCore** and tested on Linux: `LineKind` classification, plate text, display order, title folding, German VoiceOver strings. SwiftUI only adds styling. OEBB_LIVE `LinePresentation.plate` **must delegate** to it, so live and offline lines look identical. |
| D8 | **UI:** badge primitives that the widgets also need go to `Shared/Wegzeichen/`, because the widget target compiles only `Widgets/Sources` + `Shared` (project.yml lines 96–98). App-only composites go to `App/Sources/DesignSystem/Places/`, the new screen to `App/Sources/Features/Stops/`. |
| D9 | **Live:** the stop detail fills missing lines and shows departures from ÖBB HAFAS StationBoard through `StationLinker`. This needs consent, the kill switch and the 40/min budget. Until OEBB WP-A exists, the departures section is hidden and the lines stay offline. |
| D10 | **(Superseded by `docs/LOGO_SPEC.md`, see the note at the top.)** **Logos:** none are shipped. A separate logo pack exists (`$S/logos/package/`, session artefact, 99 brands, permission status „not yet requested“ for all). It is **not** part of these work packages and must not be committed. §1.10.4 defines an optional, permission-gated slot for later. |

---

# PART 1: Places data format v2

## 1.1 Files and licence layering

| File (App/Resources) | Content | Licence of the file | On disk [MEASURED] | gzip |
|---|---|---|---|---|
| `places.bin` (KBPL v2) | v1 records, names and Gemeinden (unchanged semantics) **+** official line catalogue, stop→lines, rail categories, official tags, Gemeinde tag defaults, lookup tables | official sources only: ÖV-GK/MVO, ÖBB GTFS CC BY 4.0, Wiener Linien CC BY 4.0, Land Steiermark CC BY 4.0, Statistik Austria CC BY 4.0, curated own work. **No OSM.** | 1,194,232 B | 1,190,448 |
| `stops_osm.bin` (KBPL v2, **new**) | OSM-only lines (722), OSM attributes for 2,051 official lines (operator, name, termini, flags), 11,843 OSM-only stop–line pairs, OSM tags (ski, lift, wheelchair, P+R, airport …), lifts table, OSM-only ski areas | **ODbL 1.0** (derivative database of OSM) | 204,824 B | 204,862 |
| `localities.bin` (KBPL v2 rewrap, same content) | 21,050 localities with main stop | **ODbL 1.0** | 637,416 B | 636,647 |
| **Total** | | | **2,036,472 B** (budget ≤ 5,000,000 B ✓) | 2,031,957 |

For comparison **[MEASURED]**:
- v1 today: 3,060,746 + 1,482,788 = **4,543,534 B** on disk, 1,835,275 B gzip.
- v2 with every section uncompressed (codec 0): **5,325,364 B**, which is over budget. This is why D1 compresses.
- IPA impact: about +0.2 MB, because the IPA zip already compressed v1. On-device size: −2.5 MB.
- Dropping next-stop ids would save another 61 KB (1,975,320 B). Not worth it: they disambiguate directions.

## 1.2 Container KBPL v2 [DECISION]

Little endian. The 64-byte header keeps the v1 prefix, so the existing `readBin` tooling still recognises the file.

```
header (64 B)
  0  char[4] magic "KBPL"
  4  u16 version = 2              (1 = legacy v1 layout; readers accept 1 and 2, reject > 2)
  6  u16 flags = 0
  8  u32 nRecords                 (RECS count; 0 in stops_osm.bin)
 12  u32 nGemeinden
 16  u8[32] reserved 0            (v1 offsets lived here; v2 readers use the directory)
 48  u32 nStopRecords             (stops come first in RECS, localities after; places.bin: all 39,711 are stops)
 52  u32 dirOffset
 56  u32 dirCount
 60  u32 reserved 0
sections, each 4-byte aligned, in directory order
directory: dirCount × 28 B
  0  char[4] fourcc               ("RECS", "STRS", …)
  4  u32 offset                   (from file start)
  8  u32 storedLength
 12  u32 rawLength                (decoded length; Inflate allocates exactly this)
 16  u8  codec                    (0 = stored, 1 = raw DEFLATE RFC 1951, no zlib/gzip header)
 17  u8  0
 18  u16 countHint                (records/entries; informational, capped 65535)
 20  u32 crc32                    (CRC-32/ISO-HDLC = Python zlib.crc32 of the RAW bytes)
 24  u32 reserved 0
```

Reader rules:
- An **unknown fourcc** is skipped. A **missing optional section** turns that feature off. `RECS`, `STRS` and `GEMS` are mandatory in `places.bin` and `localities.bin`.
- A **CRC mismatch or Inflate error** throws `PlaceDataset.ReadError.corrupt(section:)`.
  - For `places.bin` the loader goes to its existing failure state (`PlaceIndexLoader.State.failed`). The UI falls back to the legacy `StationIndex`, as today.
  - For `stops_osm.bin` the app logs and runs on the official layer alone.
- **Determinism:** two builds from the same inputs produced byte-identical files [MEASURED: same SHA-256 for all three files in two runs]. Python's `zlib.compress(level 9)` is deterministic for a fixed zlib version, and the build records `zlib.ZLIB_VERSION` in `places_report.json`.

## 1.3 Codec, Inflate and CRC

- **Pure Swift.** Reference implementation `$SPEC/swift/Inflate.swift` (~200 lines): canonical-Huffman single-level tables, stored/fixed/dynamic blocks, exact output size, throws on every malformed input, `crc32(_:)`. Its target home is `CORE/Places/Format/Inflate.swift`.
- **Why not Apple's API:** `NSData.decompressed(using: .zlib)` does not exist in swift-corelibs-foundation, so the Linux CI could not test it. **[DECISION] One code path everywhere.** A Darwin fast path may be added later, behind `#if canImport(Compression)`, only if a device profile shows more than 60 ms.
- **Measured** (Swift 6.3.3 release, Linux x86-64, one core; inflate + CRC, best of 5):

  | File | Time |
  |---|---|
  | `places.bin` | 26.4 ms |
  | `stops_osm.bin` | 4.3 ms |
  | `localities.bin` | 12.0 ms |
  | **Total** | **≈ 43 ms** |

  Fuzzing (`$SPEC/swift/fuzz/`, 300 random flips/truncations of the STRS section): 287 threw, 13 decoded to wrong bytes and were caught by the CRC, 0 trapped.
- **Codec per section:** codec 1 for every section larger than 4 KB, except `RPRD` (8,820 B) and `BASE`. Small sections stay codec 0 so they can be inspected in hex dumps.

## 1.4 Sections of `places.bin` (official layer)

Unless noted, the measured raw → stored sizes are from `$SPEC/out_deflate/sizes.json`.

| fourcc | Raw → stored | Layout |
|---|---|---|
| `RECS` | 1,111,908 → 467,679 | **v1 record, unchanged:** `nRecords` × 28 B (`i32 lat_e6, i32 lon_e6, u32 str_off, u32 extra_off, u16 modes(pCls), u16 weight, u16 gemeinde, u8 state, u8 kind, u8 flags, u8 class, u16 0`). Stops first, sorted by weight desc. **Stop record index = position in RECS.** It is the key of every per-stop section. |
| `STRS` | 1,645,572 → 539,371 | v1 string pool (`id \x1f name [\x1f alias]*`, legacy ids, main-stop ids) plus the enrichment strings (line refs, line names). Offset 0 = "". |
| `GEMS` | 16,880 → 7,732 | v1 (`u32 GKZ, u32 str_off`) × nGemeinden |
| `EXTR` | 14,922 → 7,434 | v1 extras **without tag 5** (the old 120-character „lines“ string, 32,085 entries + 253 KB of strings, is replaced by `LSTP`). Tags 1 EVA, 2 HAFAS extId, 3 legacy id, 6 UIC, 7 main stop id: unchanged. |
| `LCAT` | 68,184 → 10,270 | **Line catalogue.** nOfficialLines × 24 B, line index = position (u16): |
| | | `0 u32 ref_off` · `4 u32 name_off (0 none)` · `8 u16 operator (META.operators, 0xFFFF none)` · `10 u8 mode (LineMode)` · `11 u8 network (META.nets index, 0 none)` · `12 u16 flags (LineFlags bits, META.lineFlags order)` · `14 u16 states (bit = state code index 0 X … 9 W)` · `16 u8 sources (bit0 GTFS timetable, bit1 ÖV-GK, bit2 Stmk, bit3 OSM; never set in places.bin)` · `17 u8 terminiKind (0 none, 1 LNAM names, 2 stop record indices)` · `18 u16 successor (line index, 0xFFFF none)` · `20 u16 termFrom` · `22 u16 termTo` |
| `LNAM` | 2,220 → 1,031 | Display-name table (headsigns/termini not resolvable to a stop): `u32 STRS offset` per entry, index u16. |
| `LSTP` | 308,659 → 124,170 | **Stop → lines.** `u8 count[nStopRecords]`, then the entries of all stops in record order. Each entry: `u16 line` · `u8 bits` (0–1 confidence: 1 OSM-only, 2 timetable, 3 reserved live; 2–3 nTo ≤ 3; 4–5 nNext ≤ 3; 6–7 reserved) · `nTo × u16 LNAM` (headsigns at this stop) · `nNext × u16 stop record index` (next stops). Readers compute the per-stop byte offsets once at load (prefix scan). |
| `RPRD` | 8,820 stored | **Rail categories** for the 1,470 rail stations: entries `u16 stop index, u32 mask` (bit = `META.railCats` index: RJX, RJ, ICE, ECE, EC, IC, IR, D, EN, NJ, WB, CJX, REX, R, S, LEX, RB, RE, RX, ER, SP, OS, CAT, ATB, RR, Regionalzug). This is how St. Anton gets RJX/RJ/ICE/EC/IC/EN/NJ/D without OSM. |
| `GTAG` | 12,614 → 2,006 | **Gemeinde tag defaults**, in GEMS order: `u8 count`, then count × 4 B tag entries (region/landscape sets that hold for every stop of the Gemeinde). 1,952 of 2,097 Gemeinden are uniform; 1,242 stops override the default [MEASURED]. |
| `TAGS` | 88,475 → 16,655 | **Stop → official tags.** `u8 count[nStopRecords]` (bit 7 = **override**: GTAG defaults do *not* apply; the stop lists its own region/landscape set), entries `u8 key (bit 7 = aux follows)` · `u8 confidence (60–100)` · `u16 value (META.vals)` · `[u16 aux = distance in m]`. |
| `META` | 27,006 → 8,618 | UTF-8 JSON (§1.4.1) |
| `BASE` | 32 stored | SHA-256 of `"\n".join(stop ids in RECS order)`. It ties `stops_osm.bin` to this file. |

### 1.4.1 `META` JSON of `places.bin`

```json
{ "v": 1,
  "build": {"date": "2026-…", "timetableDays": ["2025-10-22", "2025-10-29"], "gtfsValidity": {"oebb": "…", "wl": "…"},
            "inputs": {"<file>": "<sha256>"}, "zlib": "1.3.1"},
  "keys": ["type","service","region","wheelchair","landscape","klimaticket","railTransfer","lift","ski","skiAlliance",
           "nationalPark","glacierSki","glacier","hut"],
  "vals": ["trainStation", "arlberg", "yes|tirol,city-klimaticket-st-anton,+vbg-maximo", "…"],
  "modes": ["other","rail","sbahn","subway","tram","bus","trolleybus","sev","ship","cable","ondemand"],
  "nets": ["", "VOR","VVSt","VKL","OÖVV","SVV","VVT","VVV","ÖBB","INT"],
  "netNames": {"VVV": "Verkehrsverbund Vorarlberg", "…": "…"},
  "lineFlags": ["ski","winter","summer","night","schooldays","schooldays?","school_or_seasonal","seasonal","ondemand",
                "sev","superseded","ski_candidate","trolley","school"],
  "railCats": ["RJX","RJ","…"],
  "operators": [{"name": "Österreichische Postbus AG", "display": "Postbus"}, "…"],
  "regions": {"arlberg": {"name": "Arlberg", "kind": "tourism"}, "…": "…"},
  "skiAreas": {"ski-arlberg": {"name": "Ski Arlberg", "short": "Arlberg", "kind": "area", "parent": null,
               "resorts": ["St. Anton", "…"], "states": ["T","V"], "bbox": [47.0955,10.0401,47.269,10.2861],
               "glyph": "peaks3", "hue": "enzian", "mono": "ARL", "lifts": 104, "stops": 152,
               "alliances": [], "verified": true}},
  "skiAlliances": {"ski-amade": {"name": "Ski amadé", "verified": false}},
  "bezirke": {"802": "Bregenz"}, "wienBezirke": {"10": "Favoriten"},
  "klimaticket": {"defaultRegional": {"V": ["vbg-maximo"], "T": ["tirol"], "…": []},
                  "products": {"vbg-maximo": "KlimaTicket VMOBIL MAXIMO", "…": "…"}},
  "nOfficialLines": 2841 }
```

- **Readers resolve tag keys by name** (`META.keys`), never by number, so keys can be added without a version bump.
- `skiAreas` holds only the **curated** areas (146 + 7 sectors): names, resorts and styling are own work. The **56 OSM-only areas** are in `stops_osm.bin` META.
- `hue` is the `SummitHue` raw value, mapped at build time following [DESIGN] §2.3:
  - Curated overrides: Arlberg = `enzian`, Schladming-Dachstein = `zirbe`, Ski amadé = `gletscher`, Hochkar = `fels`.
  - Every other area takes the nearest hue angle of `style.color`; saturation below 0.15 → `fels`.
  - The brand-like source colours (`#B1182F` …) are **never** shipped.

### 1.4.2 Tag values

| Key | Value string | aux |
|---|---|---|
| `type` | `trainStation`, `mainStation`, `longDistance`, `nightTrain`, `sBahn`, `uBahn`, `tram`, `privateRail`, `railReplacement`, `busStation`, `ship`, `cableCar`, `onDemand`, `hospital` (by name), and in the OSM layer `airport`, `parkAndRide`, `bikeAndRide`, `university`, `mall` | distance m for P+R/B+R/airport |
| `service` | `nightBus`, `onDemand`, `seasonal`, `airportLink` (official), `skiBus`, `hikingBus` (OSM) | – |
| `region` / `landscape` | region id (`arlberg`, `bregenzerwald`, `v-weinviertel` …) | – |
| `klimaticket` | `yes\|<ids>` (`+id` = Übergangsbereich), `check\|<reason>`, `no\|<reason>`, `border`. **Absent = default**: KlimaTicket Ö + `META.klimaticket.defaultRegional[state]` (Warth → VMOBIL MAXIMO) | – |
| `railTransfer` | target stop id (`at:47:62501`) | distance m |
| `ski` | ski-area id | distance m |
| `skiAlliance` | alliance id | – |
| `lift` | `#lift<k>` → `stops_osm META.lifts[k] = [name, role, liftType]` | distance m |
| `wheelchair` | `yes`, `limited`, `no` | – |
| `nationalPark`, `glacier`, `hut` | name | distance m |
| `glacierSki` | ski-area id | – |
| `state` | **not stored**: it is the record's state | – |

- Confidence below 60 is not shipped. Those tags are evidence only.
- Badges show from confidence 70 ([DATA] `display.minConf`).
- Region chips show from confidence 80 ([DESIGN] §2.4).

## 1.5 Sections of `stops_osm.bin` (ODbL layer)

| fourcc | Raw → stored | Layout |
|---|---|---|
| `STRS` | 128,318 → 45,250 | own string pool |
| `LCAT` | 17,328 → 6,962 | OSM-only lines, same 24-byte layout. **Merged line index = nOfficialLines + position.** |
| `LNAM` | 13,128 → 5,380 | own display-name table |
| `LPAT` | 32,816 → 17,478 | **Patches for official lines**, 16 B each: `u16 officialLine` · `u8 mask` (1 operator, 2 name, 4 termini, 8 flags) · `u8 terminiKind` · `u16 operator` · `u32 name_off` · `u16 termFrom` · `u16 termTo` · `u16 addFlags`. A field is only filled where the official layer lacks it. |
| `LSTP` | 145,856 → 71,058 | Same layout as places.bin `LSTP`. Holds only **pairs the official layer lacks** (skipped when the stop already has an official line with the same mode and ref). Line indices are in the merged space. |
| `TAGS` | 113,275 → 37,025 | Same layout; OSM-derived tags only |
| `META` | 85,829 → 21,338 | `{v, keys, vals, lifts: [[name, role, liftType]], skiAreas: {osm-only areas, same schema, "source":"osm"}, operatorsExtra: [...] (operator index space = official list ++ extra), nOfficialLines, nExtraLines, attribution: "© OpenStreetMap-Mitwirkende, ODbL 1.0"}` |
| `BASE` | 32 | must equal places.bin `BASE` |

## 1.6 Runtime merge rules (KlimaCore, `PlaceEnrichment`) [DECISION]

| Rule | |
|---|---|
| **M1** | Load `places.bin`, then `stops_osm.bin` if it exists, decodes and its `BASE` equals places.bin's; otherwise official only (`PlaceIndex.dataInfo.hasOSMLayer = false`). `localities.bin` is independent (v1 or v2). |
| **M2** | Apply `LPAT` to the official catalogue: fill operator/name/termini when missing, OR the flags. |
| **M3** | **Per stop:** official `LSTP` entries, then OSM entries. Dedupe by **(LineKind family, normalised plate text)** (§2.5). The first one wins (timetable before OSM before live) and directions are united. |
| **M4** | A line flagged `superseded` (113 old ÖV-GK numbers) is **replaced by its successor** at that stop. Deduped by M3 if the successor is already there. Never shown as the old number. |
| **M5** | **Tags:** official per-stop tags + `GTAG[gemeinde]` (unless the override bit is set) + OSM per-stop tags. State, Gemeinde and Bezirk come from the record (`GEMS.gkz`; Bezirk = GKZ / 100; Wiener Gemeindebezirk = GKZ / 100 % 100 when GKZ / 10000 == 9). |
| **M6** | **Rail categories** (`RPRD`) become synthetic `LineRef`s (mode rail, ref = category, `sources = [.timetable]`) for every category not already present as a plate. „RJ“ from OSM and „RJ“ from RPRD dedupe to one plate. |
| **M7** | **Display filtering:** `superseded` never shows; `schooldays?` and `ski_candidate` never show as tags (they are kept in data); `winter` → „nur im Winter“, `summer` → „nur im Sommer“, `schooldays`/`school_or_seasonal` → „Schultage“, `seasonal` → „Saison“. |
| **M8** | **Compact rows** (picker, route card, map callout, widgets) show only: timetable-confirmed lines, special-service lines whatever their source (skibus, wanderbus, nachtbus, rufbus), and OSM-only lines when the stop has no timetable line at all. The **detail** shows everything, with a source line under OSM-only lines („laut OpenStreetMap“). This is why Warth's row reads `110 852 ❄` (as in the mockup) and its detail adds `709`. |

**Warth, decoded from the v2 prototype files [MEASURED, `$SPEC/show_examples.json`]:**

| Line | Mode | Network | Operator | Termini | Flags | Confidence |
|---|---|---|---|---|---|---|
| 110 | bus | VVV | Österreichische Postbus AG | Warth, Steffisalp – Reutte, Bahnhof (A) | – | timetable |
| 852 | bus | VVV | Landbus Bregenzerwald | Schoppernau Gemeindeamt – Lech Schlosskopf | schooldays? | timetable |
| 709 | bus | VVV | Ortsbus Lech | Lech am Arlberg Schlosskopf – Hochkrumbach Saloberlifte | – | osm |
| Skibus | bus | VVV | – | Schröcken Unterboden – Warth Bildegg | ski, winter | osm |

Tags:
- region `arlberg` 90, region `bregenzerwald` 90 (official)
- ski `ski-arlberg` 95, d 77 m (OSM)
- lift [Dorfbahn Warth, valley, gondola] 97, d 77 m (OSM)
- service `skiBus` 85 (OSM)
- state V (record)
- KlimaTicket default: Ö + VMOBIL MAXIMO

## 1.7 Pipeline: `build_places.py` v2 stage

Reference implementation: `$SPEC/encode_v2.py` (writer, stdlib only, ~600 lines incl. reader). `$SPEC/show_v2.py` is the reader plus the M1–M7 merge in Python. **WP-D1 ports both into `$PLACES/build_places.py` as a v2 stage**, then into `scripts/`.

### 1.7.1 Steps (yearly at the December timetable change, or when sources change)

```sh
# 0. sources (≈ 1.4 GB, once per timetable year; ÖBB GTFS needs the terms checkbox → manual)
sh scripts/fetch_places_sources.sh build/places-dl
# 1. OSM extracts (pyosmium; the only non-stdlib step; Geofabrik austria-latest.osm.pbf)
python3 -I scripts/extract_osm_places.py  build/places-dl/osm/austria.osm.pbf build/places-dl/osm/osm_pt_austria.json
python3 -I scripts/extract_osm_routes.py  build/places-dl/osm/austria.osm.pbf build/enrich/osm_routes.json
python3 -I scripts/extract_osm_tags.py    build/places-dl/osm/austria.osm.pbf build/enrich/osm_tags.json      # ≈ 270 s
# 2. base stop list (v1 logic, unchanged) → build/places/places.json + v1 records in memory
python3 -I scripts/build_places.py --dl build/places-dl --stage base --debug-out build/places
# 3. lines twice: official layer (no OSM) and full (with OSM); same places.json
python3 -I scripts/build_lines.py --places build/places/places.json --out build/lines_official  <sources without --osm>
python3 -I scripts/build_lines.py --places build/places/places.json --out build/lines_full --osm build/enrich/osm_routes.json <sources>
# 4. tags (needs shapely + numpy → scripts/requirements-enrich.txt; pinned versions)
python3 -I scripts/build_tags.py --places build/places/places.json --osm build/enrich/osm_tags.json \
        --lines build/lines_full --out build/tags
# 5. v2 stage → App/Resources/{places.bin, stops_osm.bin, localities.bin} + data/places_report.json
python3 -I scripts/build_places.py --dl build/places-dl --stage v2 --lines-official build/lines_official \
        --lines-full build/lines_full --tags build/tags/tags.json --out App/Resources --debug-out build/places
# 6. goldens + tests
python3 -I scripts/places_reference.py golden App/Resources/places.bin App/Resources/localities.bin \
        Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places --osm App/Resources/stops_osm.bin
swift test --package-path Packages/KlimaCore --no-parallel
```

- `scripts/build_places_all.sh` runs steps 2–6.
- `--stage all` (the default once migrated) runs steps 2 and 5 in one process.
- `--stage base` keeps writing the v1 files to `--debug-out` (`v1/places.bin`, `v1/localities.bin`) as a rollback artefact.

### 1.7.2 v2 stage algorithm (port of `encode_v2.py`)

1. Encode v1 records, strings, Gemeinden and extras, minus tag 5.
2. **Official line catalogue** from `lines_official/lines_catalog.json`. Fill `terminiKind = 2` when a terminus name resolves to a stop of the line (normalised name match within the line's stops, else the nearest stop with the same first token ≤ 2 km). Otherwise use `1` (LNAM name).
3. Official `LSTP` from `lines_official/lines_by_stop.json` (confidence 2), headsigns ≤ 3, next stops ≤ 3.
4. `RPRD` from `p[]`.
5. **Tags:** split by **provenance**. WP-D2 makes `build_tags.py` emit `"osm": true|false` per tag. The prototype approximates by key (`OSM_KEYS`, POI types, region `src ∈ {osm, skiArea}`). Then:
   - drop `state` and confidence < 60;
   - drop KlimaTicket defaults;
   - compute the `GTAG` majority sets per Gemeinde and set the override bit on deviating stops.
6. **OSM layer:**
   - **Map each official line to the full-build line** with the same (mode, ref) and the largest stop overlap. Direction official → OSM: in the first prototype run the reverse direction left 110 at Warth without operator/termini [MEASURED].
   - Emit `LPAT` where attributes are missing.
   - Full lines without any overlapping official line → OSM-only `LCAT`.
   - OSM pairs whose (stop, mode, ref) are not in the official layer → `LSTP`.
   - OSM tags, lifts, OSM-only ski areas → `TAGS`/`META`.
7. Rewrap `localities.bin` as v2 (deflate).
8. **Self-test** (fails the build):
   - round-trip read with CRC and BASE;
   - the Warth assertions of AT-D4;
   - the 51 tag spot checks via the v2 reader;
   - budget ≤ 5,000,000 B;
   - no OSM bit in places.bin `LCAT.sources`; no OSM key in places.bin `TAGS`;
   - none of the OSM-only operator names (e.g. „Ortsbus Lech“) present in places.bin `STRS`.
9. Write `data/places_report.json` additions: `v2.sizes` (per section raw/stored/crc), `v2.counts`, `v2.coverage` (per state and mode), input SHA-256s, zlib version.

### 1.7.3 Changes needed in the enrichment builders (WP-D2) — known data issues [MEASURED/DATA]

| # | Issue | Fix | Test |
|---|---|---|---|
| E1 | **Same rail ref in different regions is merged.** Wien Floridsdorf shows R1 „Kleinreifling – Linz/Donau Hbf“ and R3 „Summerau – Linz“, though its headsign is „Gänserndorf“. Cause: GTFS short names R1/R3/REX2 exist in OÖ and in VOR. | Line identity = (agency, route_id) for GTFS, then split each catalogue line into **connected components of its stop graph**. Termini come from the component. | AT-D6 |
| E2 | OSM typos in termini („Lech am Arlberg Schlosswopf“, line 760) | `terminiKind = 2` (stop ids) via §1.7.2 step 2 | AT-D6 |
| E3 | The official build splits cross-Verbund lines (110 VVT/Tirol vs. 110 „VVV“ with 2 stops) | acceptable once patched (M2). The network of the official 110 should be VVT: take the net of the majority of stops of the GTFS/ÖV-GK line, not of the stop. | AT-D4 (operator present) |
| E4 | Operator legal names („OEBB Personenverkehr AG Kundenservice“, „Österreichische Postbus Aktiengesellschaft“) | curated `OPERATOR_DISPLAY` regex table → `{name, display}` (ÖBB, Postbus, Wiener Linien, Graz Linien, Linz AG Linien, IVB, Salzburg AG, Stern & Hafferl, Montafonerbahn, Landbus Bregenzerwald …); text only | AT-C6 |
| E5 | Ski-pass groups (`skiAlliance`, 9 groups) come from the curator's own knowledge | `verified: false` in META until checked against the operators' pages. **UI shows alliances only when `verified`.** | AT-C5 |
| E6 | Mode bit 2048 (cable *or* on-demand) | keep the `onDemand` type below 60 confidence unless an on-demand line serves the stop (as today) | – |
| E7 | ÖV-GK is from 22 Oct 2025 (113 renumbered lines detected) | `superseded` + `successor` (exists); replace ÖV-GK by MVO GTFS when licensed (§1.10) | AT-D8 |
| E8 | Ski-area colours in `tags.json` are close to brand colours | ship only `hue` (§1.4.1) | AT-U6 |
| E9 | 5,861 stops without any line (seasonal/school/Rufbus/depots) | ship as is; detail shows „Kein regelmäßiger Linienverkehr bekannt“; they already rank low (0 departures) | AT-C4 |

## 1.8 Enumerations (stable raw values; add only at the end)

- `LineMode` (u8): 0 other, 1 rail, 2 sBahn, 3 subway, 4 tram, 5 bus, 6 trolleybus, 7 railReplacement, 8 ship, 9 cable, 10 onDemand.
- `LineFlags` (u16 bits) in `META.lineFlags` order:
  - bit 0 ski, 1 winter, 2 summer, 3 night
  - bit 4 schoolDays, 5 schoolDaysUncertain, 6 schoolOrSeasonal, 7 seasonal
  - bit 8 onDemand, 9 railReplacement, 10 superseded, 11 skiCandidate
  - bit 12 trolley, 13 school
- `LineSources` (u8 bits): 1 timetable (GTFS), 2 ÖV-GK, 4 Stmk, 8 OSM, 16 live (runtime only).
- Network index: `META.nets`. State bit index: X B K NÖ OÖ S ST T V W (= `PlaceDataset.stateCodes`).
- **Limits:** u16 stop indices need nStopRecords < 65,535 (today 39,711). The build asserts it; above that, v3 switches LSTP next-stop ids to u32. u16 line indices: 3,563 merged lines today.

## 1.9 Memory and time budget

| Item | Today [MEASURED] | Budget v2 |
|---|---|---|
| Decode `places.bin` + `localities.bin` | 0.24 s | + inflate 43 ms + enrichment parse ≤ 40 ms |
| Index build | 0.85 s | + context sets ≤ 30 ms |
| **Total, Linux CI release** | 1.09 s | **≤ 1.30 s** |
| Resident memory | ~30 MB | **≤ +8 MB** |

- Enrichment is kept as **flat arrays**: `[UInt8]` for LSTP/TAGS, `[Int32]` per-stop offsets, catalogue structs. Inflate buffers are released after the parse.
- **`Place` values are materialised lazily per result row.** Search rows build `lines`/`tags` for at most 20 rows per keystroke, which costs < 0.1 ms.

## 1.10 Licences and attribution

### 1.10.1 Status

| Source | Licence | Layer | Status |
|---|---|---|---|
| ÖV-Güteklassen 2025 (stop list + line refs per stop, 22/29 Oct 2025) | **none stated** („Kein(e) Lizenz und kein Vertrag“) | places.bin | **open, blocking for public release** (DATA_SOURCES §3). Get written permission from AustriaTech/ÖROK **or** switch to MVO (Datenlizenz Mobilitätsverbünde Österreich v1.1). `build_lines.py --gtfs` already accepts the 7 Verbund feeds + Linz AG; the login cannot be scripted. |
| MVO GTFS (if used) | MVO v1.1: attribution + „verändert“; no sub-licensing; **€ 20,000 penalty for outdated timetable data in public journey planners** | places.bin | **rebuild every December** (§1.7.1). The app hides lines when `META.build.gtfsValidity` has expired and shows „Liniendaten veraltet – App aktualisieren“ in the stop detail footer. |
| ÖBB-PV GTFS 2026, Wiener Linien GTFS, Land Steiermark stops + Linienverkehr, Statistik Austria Gemeinden | CC BY 4.0 | places.bin | ok (attribution) |
| OpenStreetMap (routes, ski areas, lifts, pistes, POIs, wheelchair, localities) | ODbL 1.0 | stops_osm.bin, localities.bin | ok. Attribution + offer the database under ODbL: the repo ships the file and the pipeline (DATA_SOURCES §3). Never merged into places.bin (MVO forbids sub-licensing; ODbL share-alike). |
| Curated: ski areas, regions, Landesfarben approximations, KlimaTicket rules, operator display names | own work | places.bin | ok |

### 1.10.2 App texts (German, exact)

`Copy+Places.swift`, a new file, so `Copy.swift` (also edited by OEBB WP-D) stays untouched. Settings › Über › Datenquellen:

- **„Haltestellen“** – existing text from DATA_SOURCES §5.
- **„Linien“** – „ÖBB-Personenverkehr AG Soll-Fahrplan GTFS 2026 (CC BY 4.0) · Stadt Wien – data.wien.gv.at, Wiener Linien Fahrplandaten (CC BY 4.0) · Land Steiermark – data.steiermark.gv.at, Haltestellen und Linienverkehr des Verkehrsverbundes Steiermark (CC BY 4.0) · Linien je Haltestelle: ÖV-Güteklassen 2025 (ÖROK/BMIMI/AustriaTech; Daten der Mobilitätsverbünde Österreich OG), verändert (zusammengeführt).“ When MVO is used, the last clause becomes: „Datenquelle: Mobilitätsverbünde Österreich OG, Datenlizenz Mobilitätsverbünde Österreich v1.1 (data.mobilitaetsverbuende.at); verändert.“
- **„Linienverläufe, Skigebiete, Lifte, Barrierefreiheit, Orte“** – „© OpenStreetMap-Mitwirkende, ODbL 1.0 (openstreetmap.org/copyright)“
- **„Gemeinden und Bezirke“** – „Statistik Austria, Gemeinden 01.01.2026 (CC BY 4.0)“
- **„Zeichen und Namen“** – „Skigebiets-, Regions-, Verbund- und Betreibernamen dienen nur der Ortsangabe; es besteht keine Verbindung zu den Betreibern. KlimaBilanz verwendet keine offiziellen Logos und keine Landeswappen; Farben und Symbole sind eigene Gestaltung.“

**Stop detail footer** (11 pt, `Theme.textTertiary`), built from the layers actually present:
„Linien: ÖBB-GTFS, Wiener Linien, Land Steiermark, ÖV-Güteklassen · Skigebiet, Lifte, weitere Linien: © OpenStreetMap-Mitwirkende (ODbL) · Abfahrten: ÖBB-Fahrplanauskunft (live)“. The last part appears only when live data is shown.

### 1.10.3 What we never use (binding, [DESIGN] §1) – *superseded for logos and Landeswappen by `docs/LOGO_SPEC.md`*

- No Ski Arlberg logo or other ski-area logo, wordmark or brand colour.
- No Landeswappen or Landeslogo: they are protected by the state laws on state symbols. The Landesmarke shows heraldic stripe approximations plus a code and is called „Bundesland“.
- No ÖBB, Postbus, Wiener Linien, Verbund or KlimaTicket logo or brand colour.
- No red cross on white: hospitals use `cross.case.fill` on teal.

Someone should do a short legal review of the state colours and ski-area names as text before release. This is not legal advice.

### 1.10.4 Optional later: permission-gated brand marks (not in these WPs) – *superseded by `docs/LOGO_SPEC.md`*

The user explicitly asked for the Ski Arlberg logo and the state logo. The only compliant path is **written permission per brand**.

A separate workstream has prepared a remote logo pack:
- Location: `$S/logos/package/`.
- Contents: `index.json` with a `revoked` list, `permission_contacts.csv` and a German request template.
- Status: **all 99 brands „not yet requested“.** The pack's own README says not to commit it.

This spec reserves the slot and nothing more:
- `SkiPassBadge` and `StateMark` keep their own design as the **only built-in rendering**.
- A future `BrandMarkProvider` (app target) may overlay an official mark only for brand ids with status `granted`, read from a remote allowlist. It caches by SHA-256, honours `revoked`, and falls back to our badge.
- **Landeswappen stay excluded** even then. Use needs approval by each Landesregierung and is not planned.
- No code for this ships in this round.

---

# PART 2: KlimaCore API additions (on top of `PlaceIndex`)

## 2.1 Step 0 contract file [DECISION]

Before any WP starts, the lead commits `CORE/Places/Enrichment/EnrichmentContracts.swift`. It contains every **public type below**, with stub implementations that compile. The WPs then fill in the behaviour in parallel, as in OEBB_LIVE §D0. The Swift 5 language mode of KlimaCore stays.

```swift
// MARK: Lines
public enum LineMode: UInt8, Sendable, Hashable, Codable, CaseIterable {
    case other = 0, rail, sBahn, subway, tram, bus, trolleybus, railReplacement, ship, cable, onDemand
    public var transportMode: TransportMode       // rail→.train, sBahn→.sBahn, subway→.metro, tram→.tram,
                                                   // bus/trolleybus/railReplacement/onDemand→.bus, ship→.ferry, cable→.cableCar
}
public enum TransitNetwork: String, Sendable, Hashable, Codable, CaseIterable {
    case vor = "VOR", vvst = "VVSt", vkl = "VKL", ooevv = "OÖVV", svv = "SVV", vvt = "VVT", vvv = "VVV", oebb = "ÖBB",
         international = "INT"
    public var displayName: String                 // META.netNames, text only
}
public struct LineFlags: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt16
    public static let ski = LineFlags(rawValue: 1 << 0), winter = LineFlags(rawValue: 1 << 1),
                      summer = LineFlags(rawValue: 1 << 2), night = LineFlags(rawValue: 1 << 3),
                      schoolDays = LineFlags(rawValue: 1 << 4), schoolDaysUncertain = LineFlags(rawValue: 1 << 5),
                      schoolOrSeasonal = LineFlags(rawValue: 1 << 6), seasonal = LineFlags(rawValue: 1 << 7),
                      onDemand = LineFlags(rawValue: 1 << 8), railReplacement = LineFlags(rawValue: 1 << 9),
                      superseded = LineFlags(rawValue: 1 << 10), skiCandidate = LineFlags(rawValue: 1 << 11),
                      trolley = LineFlags(rawValue: 1 << 12), school = LineFlags(rawValue: 1 << 13)
}
public struct LineSources: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public static let timetable = LineSources(rawValue: 1), oevgk = LineSources(rawValue: 2),
                      stmk = LineSources(rawValue: 4), osm = LineSources(rawValue: 8), live = LineSources(rawValue: 16)
}
public enum LineConfidence: UInt8, Sendable, Hashable, Codable, Comparable { case osmOnly = 1, timetable = 2, live = 3 }

public struct LineTermini: Sendable, Hashable, Codable {
    public var from: String?, to: String?
    public var fromStopID: String?, toStopID: String?     // set when terminiKind == 2 (display uses the stop's title)
}

public struct LineRef: Sendable, Hashable, Codable, Identifiable {
    /// "l:<merged index>" for dataset lines (stable within one dataset build), "live:<HAFAS lineId>" for live-only.
    public var id: String
    /// Persistent key across dataset builds: "<net>|<mode>|<ref>" (e.g. "VVV|bus|852"). Store this, never `id`.
    public var key: String
    public var ref: String                    // "852", "REX41", "Skibus", "RJ"
    public var mode: LineMode
    public var network: TransitNetwork?
    public var operatorName: String?          // display name ("Postbus"), legal name in `operatorLegalName`
    public var operatorLegalName: String?
    public var name: String?                  // route name ("Hungerburgbahn", "Bus 852: Schoppernau <=> Lech")
    public var termini: LineTermini?
    public var flags: LineFlags
    public var states: [String]               // FederalState raw codes served by the line
    public var sources: LineSources
    public var successorRef: String?
    public var isSynthetic: Bool              // M6 rail category without a concrete line
    public var kind: LineKind { get }         // §2.5 classification
}

public struct StopLine: Sendable, Hashable, Identifiable {
    public var line: LineRef
    public var directions: [String]           // headsigns at this stop, ≤ 3, display-cleaned
    public var nextStopIDs: [String]          // ≤ 3
    public var confidence: LineConfidence
    public var id: String { line.id }
}

/// Plate family (design LineKind). Raw values = BADGE_SPEC §2.1 names; order = display family order.
public enum LineKind: String, Sendable, Hashable, CaseIterable {
    case fern, nacht, regio, sBahn, uBahn, tram, bus, nachtbus, skibus, wanderbus, rufbus, sev, seilbahn, schiff, sonst
    public var familyRank: Int { get }
    public var spokenNoun: String { get }     // "Bus", "S-Bahn", "Skibus", "Rufbus" …
}

// MARK: Tags
public struct ScoredTag: Sendable, Hashable { public var id: String; public var confidence: Int; public var distanceMeters: Int? }
public enum PlaceType: String, Sendable, Hashable, CaseIterable {
    case trainStation, mainStation, longDistance, nightTrain, sBahn, uBahn, tram, privateRail, railReplacement,
         busStation, ship, cableCar, onDemand, airport, hospital, university, mall, parkAndRide, bikeAndRide
}
public enum PlaceService: String, Sendable, Hashable, CaseIterable { case nightBus, skiBus, hikingBus, onDemand, seasonal, airportLink }
public struct PlaceTypeTag: Sendable, Hashable { public var type: PlaceType; public var confidence: Int; public var distanceMeters: Int? }
public struct LiftStation: Sendable, Hashable {
    public enum Role: String, Sendable { case valley, middle, top, unknown }
    public var name: String; public var role: Role; public var liftType: String?   // "gondola", "chair_lift", …
    public var distanceMeters: Int?; public var confidence: Int
    public var walkMinutes: Int? { get }      // ⌈d / 80 m/min⌉ (BADGE_SPEC §2.3)
}
public enum Accessibility: String, Sendable, Hashable { case yes, limited, no }
public struct KlimaTicketValidity: Sendable, Hashable {
    public enum Status: String, Sendable { case valid, check, notIncluded, border }
    public var status: Status
    public var regionalTicketIDs: [String]    // e.g. ["vbg-maximo"]; default = state list
    public var extendedTicketIDs: [String]    // „Übergangsbereich“ (+id)
    public var reason: String?
}
public struct PlaceTags: Sendable, Hashable {
    public var gkz: Int?; public var bezirk: Int?; public var wienBezirk: Int?
    public var skiAreas: [ScoredTag]          // sorted by confidence desc
    public var skiAlliances: [String]         // only `verified` alliances surface in UI (E5)
    public var glacierSkiArea: String?
    public var regions: [ScoredTag]; public var landscapes: [ScoredTag]
    public var types: [PlaceTypeTag]; public var services: [PlaceService]
    public var lift: LiftStation?
    public var accessibility: Accessibility?
    public var klimaTicket: KlimaTicketValidity
    public var nationalPark: ScoredTag?; public var glacier: ScoredTag?; public var hut: ScoredTag?
    public var railTransfer: ScoredTag?       // id = target stop id
    public var primarySkiArea: ScoredTag? { get }   // first with confidence ≥ 70
    public var showsSnowcap: Bool { get }            // primarySkiArea.confidence ≥ 90 (outline, valley lift, resort ≤ 1.5 km)
    public static let empty: PlaceTags
}

// MARK: Lookups
public struct SkiArea: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case area, sector, alliance }
    public enum Glyph: String, Sendable { case peaks3, peaks2, peaks1, glacier }
    public var id: String; public var name: String; public var shortName: String?; public var kind: Kind
    public var parentID: String?; public var allianceIDs: [String]; public var resorts: [String]; public var states: [String]
    public var bbox: GeoBox; public var glyph: Glyph; public var hue: String   // SummitHue raw value
    public var monogram: String; public var liftCount: Int; public var stopCount: Int
    public var isOSMOnly: Bool; public var isVerified: Bool
}
public struct Region: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case tourism, landscape }
    public var id: String; public var name: String; public var kind: Kind; public var stopCount: Int
}
public struct GeoBox: Sendable, Hashable { public var minLat, minLon, maxLat, maxLon: Double }

public struct StopDetails: Sendable {
    public var place: Place
    public var lines: [StopLine]              // all (M3–M7), display-sorted, superseded replaced
    public var compactLines: [LineRef]        // M8 subset
    public var tags: PlaceTags
    public var skiArea: SkiArea?; public var regions: [Region]
    public var bezirkName: String?; public var wienBezirkName: String?
    public var neighbours: [(place: Place, distanceMeters: Double)]   // ≤ 8 within 600 m (map hero)
    public var klimaTicketProducts: [(id: String, name: String)]       // resolved Ö + regional + extended
    public var attribution: [String]          // §1.10.2 footer parts for the layers present
    public var dataValidUntil: Date?          // META.build.gtfsValidity (MVO rule)
}

public struct PlaceDataInfo: Sendable {
    public var formatVersion: Int; public var buildDate: Date?; public var hasOSMLayer: Bool
    public var timetableReferenceDays: [String]; public var lineCount: Int; public var stopsWithLines: Int
}
```

## 2.2 `Place` changes

- `public var lines: [LineRef]` **replaces** `lines: String?`. Only internal users exist today: `PlaceIndex.place(_:)`, `PlaceMerger` (copies the field), `PlaceDataset` (tag 5).
  - Offline stop rows carry the **M8 compact set**, display-sorted.
  - Towns carry the lines of their main stop.
  - Live-only rows carry `[]`.
  - Kept for compatibility: `public var linesText: String? { lines.isEmpty ? nil : lines.map(\.ref).joined(separator: ",") }`.
- `public var tags: PlaceTags`, `.empty` by default:
  - stops: full tags;
  - towns: ski area and regions of the main stop, plus the town's own state;
  - live rows: `.empty`, unless merged with an offline row (`source == .both`), in which case `PlaceMerger` copies `lines` and `tags` from the offline row.
- `title` is unchanged (the official display name). Folding the state bracket („Warth (Vorarlberg) Dorfplatz“ → „Warth Dorfplatz“) is a **presentation** function (`PlaceTitle.display`, §2.5), because the full name must stay searchable and spoken.
- `subtitle` stays for the legacy picker. The new rows build their meta line from tags (§3).

## 2.3 `PlaceIndex` additions

```swift
extension PlaceIndex {
    public var dataInfo: PlaceDataInfo { get }
    public var skiAreas: [SkiArea] { get }                       // curated + OSM-only, sorted by name
    public func skiArea(id: String) -> SkiArea?
    public var regions: [Region] { get }
    public func region(id: String) -> Region?
    public func operatorName(_ legal: String) -> String           // display mapping (E4)

    public func stopLines(for placeID: String) -> [StopLine]      // full list (detail); place id or legacy id
    public func compactLines(for placeID: String) -> [LineRef]    // M8
    public func tags(for placeID: String) -> PlaceTags
    public func details(for placeID: String) -> StopDetails?
    public func line(key: String) -> LineRef?                     // persistent key → current dataset line (first match)
    public func stops(inSkiArea id: String, minConfidence: Int = 70, limit: Int = 500) -> [Place]
    public func stops(inRegion id: String, limit: Int = 500) -> [Place]
}
```

- Construction: `PlaceIndex(placesURL:localitiesURL:osmURL:)`. `PlaceDataset(places:localities:osm:)` accepts v1 or v2. `PlaceIndexLoader(bundle:)` also resolves `stops_osm.bin`, which is optional.
- `StationIndex.attach(places:)` is unchanged.
- **Thread safety:** all enrichment storage is immutable after the build, so the index stays `@unchecked Sendable` as today.

## 2.4 Search: context words [DECISION, MEASURED]

**Goal:** queries that name *where* a stop is, not only *what* it is called, must find it. Examples: „Warth am Arlberg (Dorfplatz)“, „Sölden Ötztal“, „Mayrhofen Zillertal“, „Warth Vorarlberg“.

**Vocabulary,** built at index time:

| Source | Terms (folded single words, ≥ 3 letters) |
|---|---|
| Ski areas (`kind` area/sector) | words of `name` and `shortName`, minus the generic list below („Ski Arlberg“ → `arlberg`; „Silvretta Arena“ → `silvretta`; „SkiWelt Wilder Kaiser – Brixental“ → `skiwelt`, `wilder`, `kaiser`, `brixental`) |
| Regions (tourism + landscape) | words of `name` (`bregenzerwald`, `zillertal`, `otztal`, `paznaun`, `wachau`, `weinviertel` …) |
| Bundesländer | `vorarlberg vbg vlbg`, `tirol`, `salzburg sbg`, `karnten ktn`, `steiermark stmk`, `oberosterreich oo ooe`, `niederosterreich no noe`, `burgenland bgld`, `wien` |

- **Generic words** (never context terms): ski skigebiet arena region card pass superskipass resort bergbahnen und city plus zentrum am im an der die das see tal land welt gletscher nationalpark naturpark stadt umgebung alpen berg 3000 sportwelt hohe wiener.
- **Membership:**
  - a stop belongs to a term if it has a ski tag (confidence ≥ 70) for an area, or a region/landscape tag (≥ 80) for a region, or lies in the state;
  - a **town** belongs through its main stop's tags plus its own state.
- **Storage:** term → sorted `[Int32]` record ids. Membership is checked with the existing `PlaceTable.sortedContains`.

**Rule** (in `PlaceTable.compile` and `textScore`):

1. A query token at position ≥ 1 that is a context term becomes **optional**. It is excluded from candidate generation, exactly like today's `OPTIONAL_QUERY` region words, so the place word (e.g. „warth“) generates the candidates.
2. After the assignment, for each context token **not matched by a name token** (`aj[i] < 0`):
   - **record ∈ set → +0.10** (`PlaceWeights.contextHit`). This cancels the 0.05 optional skip and adds 0.05.
   - **record ∉ set → −0.30** (`PlaceWeights.contextMiss`), because the place is somewhere else.
3. A context token matched by a name token (e.g. „Lech **am Arlberg** Rüfiplatz“, „Warth (**Vorarlberg**) Dorfplatz“) is scored by the unchanged text score.
4. **Prefixes:** the last, still-typed token may match a context term by prefix of at least 4 letters („warth arlb“). Full tokens must match exactly or as a listed abbreviation.
5. `scripts/places_reference.py` mirrors the rule 1:1. `$SPEC/proto_context_search.py` is the prototype (exact-token variant). The goldens are regenerated and the diff is reviewed.

**Results of the prototype on the shipped data [MEASURED, `$SPEC/proto_context_results.json`]** (score, kind, name, state):

| Query | Today #1 (v1 ranking) | With context words: planner | With context words: tripLog („Fahrt erfassen“) |
|---|---|---|---|
| warth am arlberg dorfplatz | Warth (V) Dorfplatz 104.2 (only hit) | **Warth (V) Dorfplatz 207.6**, then Ort Warth (V) 63.5 | **Warth (V) Dorfplatz 207.6** |
| warth am arlberg | Langen am Arlberg Bahnhof 72.8 (Warth Dorfplatz is 6th) | Ort Warth (V) 142.8 (taps through to its main stop `at:48:344`), **Warth (V) Dorfplatz 140.6** | **Warth (V) Dorfplatz 140.6**, Steffisalp, Wolfegg, Jägeralpe |
| warth arlberg | Ort Warth ×2 (V, NÖ) 69.4/69.3, Warth Dorfplatz 67.2, Warth/Neunkirchen (NÖ) 66.4 | Ort Warth (V) 147.8, **Warth Dorfplatz 145.6** (no NÖ in top 5) | **Warth Dorfplatz 145.6** |
| warth vorarlberg | Ort Warth ×2 (V, NÖ), **Warth/Neunkirchen** and **Warth/Pielach (NÖ)**, Warth (V) Dorfplatz only 5th | Ort Warth (V), then 4 Warth (V) stops; **no NÖ in top 5** | 5 × Warth (V) |
| warth niederösterreich | – | Ort Warth (NÖ), Warth/Neunkirchen, Warth/Pielach … (all NÖ) | all NÖ |
| warth | unchanged | unchanged (Ort Warth V/NÖ, Warth Dorfplatz) | **Warth Dorfplatz 144.6** (unchanged) |
| zürs am arlberg | Zürs Arlberghaus | Ort Zürs, Zürs Flexenpass/Seekopfbahn/Trittkopfbahn | same without Ort |
| sölden ötztal / mayrhofen zillertal / ischgl paznaun | – | the Ort or the main stop first, all in the right valley | main stop first |
| lech am arlberg / st anton am arlberg / wien hbf | – | **unchanged** (name matches) | unchanged |

**Further search details:**
- **Row rendering for duplicates:** two „Warth“ towns are told apart by the Landesmarke (`VB` / `NÖ`) and the Gemeinde, as in [DESIGN] §4.1.
- **Performance:** context checks run only when the query has a context token: at most 8 tokens × 1,500 candidates × one binary search, under 0.05 ms. The CI gate (100 queries < 50 ms release) must still pass.
- **Not in this round:** an area row „Skigebiet Ski Arlberg · 152 Haltestellen“ in the planner. Prepared through `stops(inSkiArea:)`; product decision later.

## 2.5 Presentation helpers (pure, `CORE/Places/Presentation/`, Linux-tested) [DESIGN §2.1, §3, §5]

| Type / function | Behaviour (test cases from BADGE_SPEC) |
|---|---|
| `LineKind.classify(_ line: LineRef, services: [PlaceService]) -> LineKind` | BADGE_SPEC §3.1 verbatim. **rail:** prefix ∈ {RJX, RJ, ICE, ECE, EC, IC, D, TGV, WB, WESTbahn} → fern; {NJ, EN} or night → nacht; {REX, CJX, R, RE, RB} or private rail → regio; `S\d` → sBahn. sbahn → sBahn; subway → uBahn; tram → tram; trolleybus → bus. **bus:** night or `^N\d` → nachtbus; ski or `S[ck]h?i-?bus` → skibus; onDemand or Rufbus/AST/ALT/Anrufsammel → rufbus; Wanderbus/Almbus → wanderbus; else bus. sev → sev; cable → seilbahn; ship → schiff; onDemand → rufbus; else sonst. |
| `LinePlateText.text(for:size:) -> (text: String, glyph: PlateGlyph?)` | Sizes xs/s 5 characters, m 6, l 8; never „…“. `EN 40465`→`EN`, `RJ 255`→`RJ`, `WESTbahn`→`WB`, `REX 41`→`REX41`, `RB 6/S6`→`S6`, `REX 154x`→`REX`, `9773/5`→`9773`, `611/847`→`611`, `Skibus` → glyph `snowflake` at xs/s and `Ski` at m/l, `Shuttlebus`→`Shuttle`, `Hungerburgbahn`→`Hungerburg`, `Achenseeschifffahrt`→`Achensee`, `Twin City Liner`→`Twin City`. |
| `LinePlateOrder.sorted(_:)` / `.diverse(_:maxCount:) -> (shown: [LineRef], overflow: Int)` | Family order, then `localizedStandardCompare` (4 < 13A < 110 < 852). Fixed long-distance order: RJX RJ ICE ECE EC IC D EN NJ WB. Dedupe by (family, text). Round-robin selection across families. Wien Floridsdorf → `REX S U6 25` + overflow. |
| `PlaceTitle.display(name:stateShown:) -> String` | `St.X` → `St. X`. Folds a bracket holding a state name or abbreviation **only when the Landesmarke is visible**: `Warth (Vorarlberg) Dorfplatz` → `Warth Dorfplatz`. `Lechen (Grafendorf) Fink` is unchanged. Detail hero drops a trailing Bahnhof/Hbf/Hauptbahnhof (`St. Anton am Arlberg`, eyebrow „BAHNHOF · …“). |
| `PlaceTitle.highlightRanges(title:query:)` | ranges of folded prefix matches, for the bold hit in rows |
| `OperatorNames.display(_:)` | E4 table, applied at build time; this function only maps live operator names |
| `SpokenLabels` (German) | `plate(_:)` „Bus 852“, „S-Bahn S45“, „U-Bahn-Linie U4“, „Railjet Xpress“, „Nightjet“, „Rufbus 581, nur auf Bestellung“, „Schienenersatzverkehr SV400“; `plateRow` „Linien: Bus 110, Bus 852, Skibus, und 5 weitere“; `stopRow` „Warth (Vorarlberg) Dorfplatz, Bushaltestelle, Vorarlberg, Skigebiet Ski Arlberg, Linien: Bus 110, Bus 852, Skibus“; `lineRow` „Bus 110, von Reutte Bahnhof nach Lech Schlosskopf, Postbus, Tirol und Vorarlberg“; `departure` „Bus 852 nach Lech Schlosskopf, in 6 Minuten, um 14:38, Echtzeit“ |
| `PlaceMarkSelection.rowMark(tags:) -> PlaceType?` and `.detailMarks(tags:)` | one mark in rows, by priority: airport > mainStation > valley station (lift role valley, d ≤ 400) > ship > nightTrain > parkAndRide > barrier-free; every mark in the detail |
| `StopKindLabel.label(place:tags:)` | „Bushaltestelle“, „Bahnhof“, „Hauptbahnhof“, „Straßenbahn“, „U-Bahn“, „Schiffsanlegestelle“, „Seilbahn“, „Ort“ |

**[DECISION] OEBB_LIVE §C3.2 `LinePresentation.plate(line)` returns `LinePlateText.text(for: LiveLineMatcher.lineRef(from: line), size: .s).text`.** The C3.2 table („T 1“, „S 4“) is superseded by BADGE_SPEC: tram plates show `1`/`D`, S-Bahn shows `S4`. OEBB WP-C must apply this; it is noted in its checklist (§5).

---

# PART 3: SwiftUI components, StopDetailView, where badges appear

## 3.1 File layout [DECISION D8]

Every component comes from `$DESIGN/swift/Wegzeichen.swift`, which type-checks with 0 errors. Names are kept **exactly**; the file is split as follows.

**`Shared/Wegzeichen/`** (compiled into app + widgets; `import SwiftUI, KlimaCore`):

| File | Components |
|---|---|
| `WegzeichenTokens.swift` | `extension LineKind` (styling only: `shape`, `fill(for:)`, `textColor`, `ring`, `uBahnFill`), `PlateSize`, `SummitHue` (`init?(rawValue:)` from `SkiArea.hue`) |
| `LinePlate.swift` | `BadgeGlyph`, `BadgeGlyphView`, `LineBadge` (view model: kind, text, glyph, spoken; `init(_ line: LineRef, size:)` via `LinePlateText`), `WedgePlateShape`, `LinePlate`, `LinePlateRow` (`ViewThatFits` with „+k“), `OverflowPlate`. `LineBadge.displayOrder` delegates to `LinePlateOrder`. |
| `StateMark.swift` | `Bundesland` (from `FederalState`; `code2` BG KT NÖ OÖ SB ST TI VB WI; stripes), `LandesBlaze`, `StateMark` (`.compact` / `.full`) |
| `SkiPassBadge.swift` | `SkiPassBadge` (`.compact` / `.full` / `iconOnly`) |
| `WegzeichenGlyphs.swift` | `Peaks3Glyph`, `Peaks2Glyph`, `Peaks1Glyph`, `GlacierGlyph`, `StationClockGlyph`, `GondolaGlyph`, `SnowcapShape`, `SnowcapModifier`, `View.snowcap(_:size:cornerRadius:)` |
| `PlaceMark.swift` | `PlaceMarkKind` (+ `static let allSymbols`), `PlaceMark` |

- `LineKind` itself (cases, rank, spoken noun) moves to KlimaCore (§2.1). The design file's `enum LineKind` becomes the styling extension.
- Widgets **never load the PlaceIndex** (memory). The app writes `[LineBadgeSnapshot]` (kind raw, text, glyph raw, spoken) into `WidgetSnapshot` (§3.4).

**`App/Sources/DesignSystem/Places/`** (app only):

| File | Components |
|---|---|
| `StopTile.swift` | `StopTile` (mode tile 24/38/50 with gradients incl. the new `fern` Gipfelnacht and a `snowcap` flag; [DESIGN] §2.6). New, so `ModeIcon` (`Components.swift`) stays untouched. |
| `StopSuggestionRow.swift` | `StopSuggestionRowModel` (+ `init(place: Place, index: PlaceIndex?, query: String)`), `StopSuggestionRow` (degradation ladder §4.1; Dynamic Type third line), `TownSuggestionRow` („Warth · Ort · 9 Haltestellen“ + chevron) |
| `PlaceChips.swift` | `RegionChip`, `BezirkChip`, `PlaceMarkChip` („P+R · 28 m“), `KlimaTicketChip` (`valid` hidden in rows; `check`/`notIncluded`/`border` always visible), `SeasonTag` („nur im Winter“ …) |
| `LineRows.swift` | `LineFamilyRow` (hero: family symbol + plates, ≤ 2 lines + „+k“), `LineFamilyHeader`, `StopLineRow` (plate m, `MiniRouteGlyph`, termini stacked, operator · network · mini state marks, source note for OSM-only), `MiniRouteGlyph`, `LongDistanceSummaryRow` („→ Innsbruck · Salzburg · Wien“) |
| `DepartureRow.swift` | `DepartureRow` (live / planned / cancelled states), `DeparturesFooter`, `DepartureSkeletonRow` |
| `SkiPassCard.swift` | `SkiPassCard` (punch hole, perforation, contour lines, valley-station line, resorts, „Skigebietsname als Textangabe · kein offizielles Logo“) |
| `StopPins.swift` | `StopPin` (30/34/40, snowcap), `StopDotPin`, `StopClusterPin` (conic ring), `StopCallout` |

**`App/Sources/Features/Stops/`:**

| File | Contents |
|---|---|
| `StopDetailView.swift` | the screen (§3.2) |
| `StopDetailModel.swift` | `@MainActor @Observable`: loads `StopDetails` from `PlaceIndexLoader.shared`; personal stats from the repository; `departures: DeparturesState` |
| `StopDetailSections.swift` | `StopHeroCard`, `StopLinesSection`, `StopSkiSection`, `StopKlimaTicketCard`, `StopFactsSection`, `StopSourcesFooter` |
| `StopMapHero.swift` | MapKit hero with neighbour dots |
| `StopActionBar.swift` | „Fahrt von hier“ / „Fahrt nach hier“ |
| `StopDetailPresentation.swift` | `StopRoute: Hashable { placeID }`, `View.stopDetail(placeID: Binding<String?>)` (sheet, `.large`) and `StopDetailView(placeID:)` for pushes inside an existing NavigationStack. No edit to `RootView.swift`. |
| `StopDeparturesSection.swift` | **owned by WP-L**; WP-U3 ships a placeholder that renders nothing |

**`Shared/Theme.swift` additions:**
- `Theme.live = Color(light: "#0B7A4E", dark: "#5BE0A0")` (light was 3.2:1, now 5.37:1)
- `Theme.snow = Color(light: .white, dark: "#EEF5FF")`
- `Theme.fernTile` gradient tokens

## 3.2 `StopDetailView` [DESIGN §4.4, mockups `02-stop-warth-*`, `03-stop-stanton-*`]

Top to bottom:

1. **`StopMapHero`** (372 pt including the status bar)
   - Map style: `.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)`, about 1,200 m span.
   - Pins: `StopPin` (selected, halo, snowcap when `tags.showsSnowcap`); neighbours ≤ 600 m as named dots.
   - Glass toolbar: back/close, Share | Favorite.
2. **`StopHeroCard`** (`GlassCard`, radius 30, overlaps the map by 72 pt)
   - `StopTile` 50 + snowcap; eyebrow „BUSHALTESTELLE · GEMEINDE WARTH“ / „BAHNHOF · FERNVERKEHR & NACHTZUG“; title 27 bold (`PlaceTitle.display`, `minimumScaleFactor` 0.85).
   - Badge flow (wraps, ≤ 2 lines): `StateMark(.full)` · `SkiPassBadge(.full)` · `RegionChip` (skipped when it equals the ski area's short name) · `PlaceMarkChip`s · `KlimaTicketChip`.
   - `LineFamilyRow` per family: plates `l` when there are ≤ 4 lines in total, else `m`; „+k“ jumps to the lines section.
3. **Departures** (WP-L, §4): 3–4 `DepartureRow`s with a „● Live“ eyebrow. Hidden while live is unavailable.
4. **`StopLinesSection`**: groups by family with a `LineFamilyHeader` (count, season tag). Long distance is one `LongDistanceSummaryRow`. OSM-only lines carry „laut OpenStreetMap“. A stop without lines shows „Kein regelmäßiger Linienverkehr bekannt“.
5. **`StopSkiSection`** (only with a primary ski area): `SkiPassCard` with the valley station (`tags.lift`, „Talstation Dorfbahn Warth · 77 m · 1 min“), resorts (own resort bold) and „Teil von …“ (verified alliances only).
6. **`StopKlimaTicketCard`**:
   - Seal tile 42, „Mit deinem KlimaTicket gratis“ + network name, tickets with check marks (Ö, regional, local, Übergang).
   - **Personal line** „3 Fahrten ab hier · € 20,40 Normalpreis-Wert“ (trips with `fromStationID`/`toStationID` ∈ {place.id, legacy ids}). Tapping it opens the filtered trip list.
   - `check` / `notIncluded` states with reason.
7. **`StopFactsSection`**: Bundesland (full Landesmarke), Bezirk („Bezirk Bregenz“; Vienna: „10. Bezirk · Favoriten“), Gemeinde, regions, facilities (barrier-free / P+R / B+R, or „Keine Angaben zur Barrierefreiheit“), stop id (monospaced) + EVA.
8. **`StopSourcesFooter`**: §1.10.2. With `dataValidUntil` in the past: „Liniendaten veraltet – App aktualisieren“.
9. **`StopActionBar`** (`safeAreaInset(edge: .bottom)`): „Fahrt von hier“ (CTA gradient) / „Fahrt nach hier“ (glass) open „Neue Fahrt“ prefilled with `place.station`.

**Entry points:**
- the route card's from/to name (WP-U2);
- long press on a suggestion row → context menu „Haltestelle ansehen“ (WP-U2);
- trip detail from/to (WP-U4);
- map pin callout (p2-map Atlas, after its merge; WP-U4);
- deep link `klimabilanz://stop/<placeID>` (optional).

**Accessibility:**
- one label per row ([DESIGN] §5); the snowcap has no element of its own;
- Reduce Transparency → opaque chips and bars;
- Reduce Motion → no pulsing.

## 3.3 Where the badges appear

| Screen | Component(s) | Size | Rule | WP |
|---|---|---|---|---|
| Station picker „Von/Nach“ (`StationPickerView`) | `StopSuggestionRow`, `TownSuggestionRow` | tile 38, plates `s`, max 4 + „+k“ | M8 compact lines; ladder: region → ski badge icon only → fewer plates → Gemeinde; Landesmarke + ≥ 1 plate always | U2 |
| Trip editor route card (`TripEdRouteCard`) | meta row: `StateMark`, `SkiPassBadge`, `PlaceMark` + text; right side `LinePlate(xs)` max 3 | xs | replaces „Bahnhof · Tirol“ | U2 |
| Trip editor „Gefahren mit 852 › 760“ | `LinePlate(s)` + chevron | s | optional selection, persisted as `TripEntity.lineKeysRaw` (§5 WP-U4) | U4 |
| Trip list rows | ≤ 2 `LinePlate(xs)` or the category plate | xs | replaces `TripListModeBadge` | U4 |
| Dashboard favourite chips | `LinePlate(xs)` | xs | replaces `DashModeBadge` | U4 |
| Widgets (small „Abfahrten“, medium, lock screen) | `LinePlate` from `LineBadgeSnapshot`; vibrant = outline | s / xs | replaces `WidModeBadge` | U4 |
| Map (p2-map Atlas) | `StopDotPin`, `StopPin`, `StopClusterPin`, `StopCallout` | 8–40 | zoom rules [DESIGN] §4.5 | U4 (after p2-map merge) |
| Stop detail | everything above + `SkiPassCard`, `LineFamilyRow`, `StopLineRow`, `DepartureRow` | l/m | §3.2 | U3, L |

---

# PART 4: Live completion on the stop detail

## 4.1 Preconditions

Live data is shown only when **all** of these hold:
1. `LiveDataService.isConsented` — the user tapped „Live-Daten aktivieren“ (OEBB_LIVE §2.2, §E7).
2. `config.isEnabled(.oebbHafas)` — the kill switch is off (OEBB_LIVE §A3.8).
3. The device is online.
4. A `StopDepartureProviding` is registered.

Otherwise the detail is **offline only**: offline lines, no departures section, no error.

**Until OEBB WP-A merges, no provider exists** and that is the shipped state.

## 4.2 Contract (in Step 0, `CORE/Places/Enrichment/EnrichmentContracts.swift`)

```swift
public protocol StopDepartureProviding: Sendable {
    /// One StationBoard (DEP) for the stop, `minutes` ahead. Throws LiveError (OEBB_LIVE contract) on failure.
    func departures(for place: Place, lines: [StopLine], at date: Date, minutes: Int) async throws -> StopDepartures
}
public struct StopDepartures: Sendable {
    public var entries: [StopDeparture]       // sorted by effective time
    public var observedLines: [StopLine]      // offline lines confirmed (sources ∪ .live) + live-only lines
    public var realtimeUpdatedAt: Date?
}
public struct StopDeparture: Sendable, Hashable, Identifiable {
    public var id: String
    public var line: LineRef                  // matched offline line, or live-only LineRef
    public var direction: String              // display-cleaned dirTxt
    public var via: String?                   // next stop name if known
    public var planned: Date; public var realtime: Date?
    public var platform: String?; public var platformChanged: Bool
    public var isCancelled: Bool
    public var destinationState: String?      // mini Landesmarke when ≠ stop's state
}
```

## 4.3 Implementation (WP-L, after OEBB WP-A): `CORE/Places/Live/HafasStopDepartures.swift`

1. **Location:** `StationLinker.hafasLocation(for: place.station)`.
   - Rule 1: `uic:`/EVA → no I/O.
   - Rule 2: LocMatch by name, distance ≤ 300 m.
   - Disk-cached 30 days.
   - Example: Warth Dorfplatz → extId `892213`, „Warth in Vlbg Dorfplatz (Bezauer Straße)“ [LIVE, `$LINES/live/scotty_lines_raw.json`].
   - Bus-stop extIds are learnt at runtime and never bundled (DATA_SOURCES §3).
2. **Board:** `TimetableService.board(BoardQuery(station: loc, kind: .departures, date: now, durationMinutes: 90, maxResults: 40, products: .all))`. The HafasClient cache (20 s) and the throttle (40/min) apply.
3. **`LiveLineMatcher.match(entry.line, stopLines:) -> LineRef`** (pure, Linux-tested):
   - **Live plate key:** mode from `productClass`:
     - 1 RJX/RJ/ICE, 4 IC/EC, 8 NJ/EN → rail; 16 → rail regional; 4096 → rail WB
     - 32 → sBahn; 64 → bus; 128 → ship; 256 → subway; 512 → tram
     - 1024 coach → `.other`, not KlimaTicket; 2048 → onDemand/cable; 2 → railReplacement
   - **Ref:** `lineNumber`, or `category` for long distance, combined like the offline refs (`category + lineNumber` for REX/CJX/R/S: „REX 51“ → `REX51`, „S 4“ → `S4`). Upper-case, without spaces.
   - **Match** an offline `StopLine` with the same `LineKind` family and the same `LinePlateText`. On a match: return the offline `LineRef` with `sources ∪ .live`.
   - **Superseded:** a live ref equal to an offline line's `successorRef` matches the successor (e.g. live 184 ↔ offline 5144 → 184).
   - **No match** → `LineRef(id: "live:<lineId>", key: "<net>|<mode>|<ref>", sources: .live, operatorName: OperatorNames.display(entry.line.operatorName))`. The network comes from the `lineId` prefix: `vvt`→VVT, `vvv`→VVV, `vor`→VOR, `svv`→SVV, `stv`→VVSt, `ktn`→VKL, `oov`→OÖVV, `esg`→OÖVV (Linz), `at:obb`→ÖBB [LIVE prefixes from 1,000+ sampled board lines].
4. **Entries** → `StopDeparture`:
   - `direction = DisplayNames.make(entry.direction)` (OEBB_LIVE §C3.3);
   - realtime/planned/platform/cancelled from `StopEvent`;
   - `destinationState` from `StationLinker.appStation(for: terminus)?.state`.
5. **`LiveLineCache`** (app, `Application Support/places/live_lines.json`): `{version:1, stops:{placeID:[{key, ref, mode, net, op, lastSeen}]}}`, TTL 30 days, ≤ 500 stops, atomic writes.
   - Live-only lines seen before are shown on the next visit, even offline, as „zuletzt live gesehen am …“.
   - They are never written into the bundled data, and nothing is sent anywhere.
6. **Refresh:**
   - on appear; every 30 s while the view is visible and `scenePhase == .active`; pull to refresh;
   - cancel on disappear;
   - at most one board in flight per stop.

## 4.4 UI states (`DeparturesState`)

| State | Departures section | Lines section |
|---|---|---|
| `.unavailable` (no provider, consent declined, kill switch) | hidden. With consent missing but a provider present: one row „Live-Abfahrten aktivieren“ → consent sheet. | offline (+ cached live-only lines) |
| `.loading` | 3 `DepartureSkeletonRow`s | offline |
| `.live(StopDepartures)` | ≤ 4 rows, footer „Echtzeit · vor 20 s aktualisiert“ + „Alle“ | offline ∪ live-only (plate with a small `dot.radiowaves.left.and.right`, „heute live gesehen“) |
| `.empty` | „In den nächsten 90 Minuten keine Abfahrten“ (+ for winter-only stops: „Saisonbetrieb – im Winter mehr Verbindungen“) | offline |
| `.failed` | footer „Abfahrten gerade nicht verfügbar“ | offline |

## 4.5 Expectations [DATA]

- On served stops, live fills night lines, AST/Rufbus lines and newly numbered lines. From about November, when each Verbund has loaded its winter timetable into Scotty, it also fills the winter ski buses. January 2027 was loaded only for T/ST/OÖ/Linz on 2026-10-09.
- Stops without any line (5,861) are rarely helped: 1 of 24 sampled had live departures.

---

# PART 5: Work packages and file ownership

Branch names follow `wip/enrich-*`. Every WP:
- runs `swift test --package-path Packages/KlimaCore --no-parallel` (Linux);
- runs `tools/typecheck/run.sh --target all` (app + widgets, 0 errors) where app code changes;
- adds the screenshot scenes it owns to `scripts/capture_screenshots.sh` (CI `[shots:…]`).

| WP | Scope | Owns (create/modify) | Depends on | Must not touch |
|---|---|---|---|---|
| **Step 0** (lead, ~30 min) | contracts + fixtures | `CORE/Places/Enrichment/EnrichmentContracts.swift` (all §2.1/§4.2 public types, stubs); `Tests/KlimaCoreTests/Fixtures/places/v2/` (small v2 fixtures written by `encode_v2.py`: Warth/St. Anton/Floridsdorf subset files, an inflate vector set, a corrupt file); this spec copied to `docs/ENRICH_SPEC.md` (paths rewritten) | `62351c3` | – |
| **WP-D1** data pipeline | §1.7: v2 stage in `$PLACES/build_places.py`, then ported to the repo | `scripts/build_places.py` (stage v2, `--stage`), `scripts/build_lines.py`, `scripts/extract_osm_routes.py`, `scripts/build_tags.py`, `scripts/places_curated.py` (from `$TAGS/curated.py`), `scripts/extract_osm_tags.py`, `scripts/requirements-enrich.txt`, `scripts/build_places_all.sh`, `scripts/fetch_places_sources.sh`, `App/Resources/places.bin`, **`App/Resources/stops_osm.bin` (new)**, `App/Resources/localities.bin`, `data/places_report.json`, `docs/DATA_SOURCES.md` | Step 0 | Swift sources |
| **WP-D2** data fixes | §1.7.3 E1–E5: line identity by component, termini as stop ids, net majority, operator display table, alliance `verified`, tag provenance flag | the same scripts (sequential with D1, same branch `wip/enrich-data`) | D1 | – |
| **WP-C1** format reader | KBPL v2 container, Inflate, CRC, v1 compatibility, OSM layer loading, BASE check | `CORE/Places/Format/KBPLContainer.swift`, `CORE/Places/Format/Inflate.swift`, `CORE/Places/PlaceDataset.swift`, `CORE/Places/PlaceIndexLoader.swift`; tests `PlaceFormatTests.swift` | Step 0 | `PlaceIndex.swift`, ranking |
| **WP-C2** enrichment model + API | `PlaceEnrichment` storage + M1–M8, `Place.lines/tags`, `PlaceIndex` additions, `StopDetails`, `PlaceMerger` copy | `CORE/Places/Enrichment/PlaceEnrichment.swift`, `…/LineCatalog.swift`, `…/PlaceTagsDecoder.swift`, `…/SkiAreaCatalog.swift`, `…/StopDetailsBuilder.swift`, `CORE/Places/PlaceModels.swift`, `CORE/Places/PlaceIndex.swift`, `CORE/Places/PlaceMerger.swift`; tests `PlaceEnrichmentTests.swift` | C1 (reader API), C3 (classify/plate text for M3) | `PlaceRanking.swift`, `PlaceTable.swift` |
| **WP-C3** presentation (pure) | §2.5 | `CORE/Places/Presentation/LineKindClassifier.swift`, `LinePlateText.swift`, `LinePlateOrder.swift`, `PlaceTitle.swift`, `OperatorNames.swift`, `SpokenLabels.swift`, `PlaceMarkSelection.swift`, `StopKindLabel.swift`; tests `LinePresentationTests.swift` | Step 0 | – |
| **WP-C4** search context words | §2.4 | `CORE/Places/PlaceRanking.swift`, `CORE/Places/PlaceTable.swift` (context sets passed in by `PlaceIndex`; C2 adds the one-line hook `PlaceTable(records:municipalities:context:)`), `scripts/places_reference.py`, goldens `Fixtures/places/golden_places.json` (+ new cases); tests `PlaceContextSearchTests.swift` | C2 | `PlaceIndex.swift` beyond the hook |
| **WP-U1** Shared Wegzeichen | §3.1 Shared files + Theme tokens | `Shared/Wegzeichen/*.swift`, `Shared/Theme.swift` (additions only); app test `WegzeichenSymbolTests.swift` (every `PlaceMarkKind.allSymbols` exists via `UIImage(systemName:)`) | Step 0, C3 | widget views |
| **WP-U2** picker + route card | new rows in the picker, context menu, route card meta row | `App/Sources/DesignSystem/Places/{StopTile, StopSuggestionRow, PlaceChips}.swift`, `App/Sources/Features/Trips/Editor/StationPickerView.swift`, `App/Sources/Features/Trips/Editor/TripEdRouteCard.swift` | C2, U1 | `TripEditorView.swift`, `TripEdComponents.swift` |
| **WP-U3** stop detail | §3.2 | `App/Sources/Features/Stops/*` (except `StopDeparturesSection.swift` content), `App/Sources/DesignSystem/Places/{LineRows, DepartureRow, SkiPassCard, StopPins}.swift`, `App/Sources/Core/Copy+Places.swift` (§1.10.2 texts), Settings „Datenquellen“ entries through the existing data-source list API | C2, U1 | `RootView.swift`, `Copy.swift` |
| **WP-U4** badge swap + trip lines (**last**, after `wip/p2-tripmeta`, `wip/p2-live`, `wip/polish-widgets`, `wip/polish-dashboard`, `wip/p2-map` are merged) | replace the 4 old badges; widget snapshot; „Gefahren mit“ row; trip-detail and map entry points | `TripListComponents.swift` (badge only), `TripEdComponents.swift` (`TripEdModeBadge` → `LinePlate`), `DashSupport.swift` (badge only), `Shared/WidgetViews/WidComponents.swift` (badge only), `Shared/WidgetSnapshot.swift` (`LineBadgeSnapshot`, additive Codable), `Shared/Models.swift` (`TripEntity.lineKeysRaw: String = ""`, additive; SwiftData lightweight; Cloud DTO field optional → KlimaCloud `SyncDTOs.swift` + Worker column, coordinated with the backend owner), Atlas pins in the p2-map files | U2, U3 and those merges | anything else in those files |
| **WP-L** live completion (after OEBB WP-A + WP-D) | §4 | `CORE/Places/Live/HafasStopDepartures.swift`, `CORE/Places/Live/LiveLineMatcher.swift`, tests `LiveLineMatcherTests.swift` (fixtures: OEBB `stationboard_dep_innsbruck_hbf` + a Warth board trimmed from `$LINES/live/cache`), `App/Sources/Features/Stops/StopDeparturesSection.swift`, `App/Sources/Features/Stops/StopDetailModel+Live.swift`, `App/Sources/Services/LiveLineCache.swift`; registration in the `LiveDataService` (one line, coordinated with OEBB WP-D) | OEBB WP-A, WP-D; U3 | `StopDetailView.swift` (uses the seam) |
| **OEBB WP-C** (other spec) | apply D7 | `LinePresentation.plate` delegates to `LinePlateText` | C3 | – |

**Merge order:**

```
Step 0 → (D1 ∥ C1 ∥ C3 ∥ U1) → D2 → C2 → (C4 ∥ U2) → U3 → [p2/polish merges] → U4 → [OEBB WP-A/D] → L
```

- D1/D2 must land before C2's dataset tests switch from fixtures to the shipped files.
- C2's tests run against the Step 0 fixtures first.

---

# PART 6: Acceptance tests

IDs are referenced by the WPs. „Shipped data“ means `App/Resources/*.bin` after D1/D2.

## 6.1 Data (`scripts/check_places_v2.py`, run by the build self-test and in CI)

| ID | Test |
|---|---|
| AT-D1 | All three files decode. Every section CRC matches. `BASE` of stops_osm.bin == places.bin. Two builds from the same inputs → identical SHA-256. |
| AT-D2 | Size: places.bin + stops_osm.bin + localities.bin ≤ **5,000,000 B** (prototype 2,036,472). Every section > 4 KB uses codec 1. |
| AT-D3 | Coverage (merged layers): stops with ≥ 1 line ≥ **85.0 %**; stops with departures on the reference weekday that have ≥ 1 line ≥ **99.5 %**; official layer alone ≥ **82.0 %** [DATA 85.2 / 99.8 / 82.4]. |
| AT-D4 | **Warth** `at:48:344` (merged): lines ⊇ {110 bus, 852 bus}, both timetable-confirmed, with operator and termini (110: Postbus, Reutte ↔ Warth/Lech). OSM lines ⊇ {709, Skibus [ski, winter]}. Tags: ski `ski-arlberg` ≥ 90 (d ≈ 77 m); lift „Dorfbahn Warth“ role valley; regions ⊇ {arlberg, bregenzerwald}; state V; Bezirk 802; KlimaTicket valid with regional `vbg-maximo`. Ort „Warth“ (`osm:n73089810`) has main stop `at:48:344`. |
| AT-D5 | The 51 spot checks of `$TAGS/spot_checks.json` pass through the v2 reader, including: St. Anton im Montafon `at:48:187` **not** Arlberg; Warth/NÖ `at:43:30742` no ski tag; Obergurgl `at:47:64774` = Obergurgl-Hochgurgl, not Sölden; Innsbruck Hbf `at:47:1187` no ski tag; Schöckl Bergstation `at:46:4898` KlimaTicket `no`; Planai Talstation `at:46:31026` `check`. |
| AT-D6 | **Termini sanity:** for every displayed (stop, line), both termini belong to the same connected component of the line as the stop. Wien Floridsdorf `at:49:334` shows no R1 „Kleinreifling/Linz“ or R3 „Summerau/Linz“. No terminus name differs from its resolved stop's name (fixes „Schlosswopf“). |
| AT-D7 | **Licence layering (negative tests):** places.bin `LCAT.sources` has no OSM bit; places.bin `TAGS` has no key ∈ {ski, skiAlliance, glacierSki, glacier, lift, hut, nationalPark, wheelchair} and no type ∈ {airport, parkAndRide, bikeAndRide, university, mall}; places.bin `STRS` contains none of „Ortsbus Lech“, „Dorfbus Warth“, „Dorfbahn Warth“. |
| AT-D8 | **Superseded:** no stop displays 5144/5173/5377 or Kitzbühel 4002/4004/4008. Patergassen Ort shows 184 (successor of 5144). |
| AT-D9 | **Styling data:** every ski area has `hue` ∈ the 8 SummitHue values and `glyph` ∈ {peaks3, peaks2, peaks1, glacier}. No `#B1182F`-style source colour is present in any shipped file. |

## 6.2 KlimaCore (`swift test`, Linux, Swift 6.3.3 and 6.4)

| ID | Test |
|---|---|
| AT-C1 | `Inflate`: vectors from Python `zlib` (stored, fixed, dynamic, empty, 1 MB repetitive, a 258-byte match at distance 32,768) decode byte-exactly. 300 seeded corruptions → throws or CRC mismatch, **never a trap**. `ReadError.corrupt(section:)` on CRC mismatch. |
| AT-C2 | v1 files (the Step 0 fixture copy of today's format) still decode. v2 version > 2 → `unsupportedVersion(3)`. |
| AT-C3 | Without `stops_osm.bin`, or with a different `BASE`: `dataInfo.hasOSMLayer == false`; Warth lines == [110, 852]; no ski tag; the index still builds. |
| AT-C4 | **Warth merged lines:** `compactLines` display order = [`110`, `852`, Skibus]; kinds [bus, bus, skibus]; plate texts [`110`, `852`, glyph `snowflake`]. `stopLines` additionally contains `709` with confidence `.osmOnly`. `SpokenLabels.plateRow` = „Linien: Bus 110, Bus 852, Skibus“. A stop without lines → `stopLines == []` and `details.lines` empty (UI shows „Kein regelmäßiger Linienverkehr bekannt“). |
| AT-C5 | **Warth tags:** `primarySkiArea.id == "ski-arlberg"`; `skiArea(id:)` → name „Ski Arlberg“, short „Arlberg“, hue `enzian`, glyph `peaks3`, monogram „ARL“; `showsSnowcap == true`; `lift.name == "Dorfbahn Warth"`, role `.valley`, `walkMinutes == 1`; `klimaTicket.status == .valid`, regional `["vbg-maximo"]`. St. Anton Bahnhof `at:47:1222`: regional ⊇ {tirol, city-klimaticket-st-anton}, extended {vbg-maximo}; types ⊇ {trainStation, longDistance, nightTrain, parkAndRide (28 m)}; accessibility `.yes`. Unverified alliances never appear in `skiAlliances`. |
| AT-C6 | **Presentation:** all §2.5 plate-text cases; `PlaceTitle.display("Warth (Vorarlberg) Dorfplatz", stateShown: true) == "Warth Dorfplatz"` (and unchanged with `stateShown: false`); `Lechen (Grafendorf) Fink` unchanged; Floridsdorf diverse(4) → [REX, S, U6, 25] + overflow > 0; St. Anton rail categories (M6) → [RJX, RJ, ICE, EC, IC, D] + [EN, NJ], deduped with the OSM „RJ“ and „EN 40465“; operator display „Österreichische Postbus AG“ → „Postbus“. |
| AT-C7 | **Search goldens** (offline, shipped data): |
| | „Warth am Arlberg Dorfplatz“ → #1 `at:48:344`, planner **and** tripLog, ahead of #2 by ≥ 100 points |
| | „warth am arlberg“ → tripLog #1 `at:48:344`; planner #1 Ort Warth (V) (`osm:n73089810` → main stop `at:48:344`), #2 `at:48:344` |
| | „warth arlberg“, „warth am arlberg dorf“ (partial) → `at:48:344` in the top 2 (planner), #1 (tripLog) |
| | „warth vorarlberg“ → no NÖ record in the top 5; „warth niederösterreich“ → top 5 all NÖ |
| | „warth“ tripLog → #1 `at:48:344` (unchanged) |
| | „lech am arlberg“, „st anton am arlberg“, „wien hbf“, „innsbruck“ → unchanged |
| | The existing 113 ranking goldens are unchanged, except for diffs reviewed and listed in the PR |
| AT-C8 | **Performance (release gate in CI):** decode + inflate + enrichment + index build ≤ **1.30 s**; 100 typical queries incl. 10 with context words < **50 ms**; `details(for:)` < 1 ms; resident memory increase ≤ 8 MB (measured with `mallinfo2` on Linux). |
| AT-C9 | **`LiveLineMatcher`** (fixtures): Warth board 2026-10-14 → 110 and 852 match the offline lines (`sources ⊇ [.live]`) and add **no** live-only line. Innsbruck Hbf board → Bus F matches. A synthetic board with 184 at Patergassen matches the successor of 5144. An unknown line → `LineRef.id` starts with `live:`, network from the lineId prefix, `sources == [.live]`. `LinePresentation.plate` (OEBB) == `LinePlateText` for the same line. |

## 6.3 App (typecheck, unit tests, screenshots, review)

| ID | Test |
|---|---|
| AT-U1 | `tools/typecheck/run.sh --target all` → 0 errors (app + widgets). The widget target compiles `Shared/Wegzeichen` without `PlaceIndex`. |
| AT-U2 | `WegzeichenSymbolTests`: every `PlaceMarkKind.allSymbols` and BADGE_SPEC §6 name returns a non-nil `UIImage(systemName:)`. |
| AT-U3 | **Screenshot scenes (light + dark), checked against the mockups in review:** `pickerWarth` (query „warth“, tripLog: row 1 „**Warth** Dorfplatz“ · VB · Ski Arlberg · 110 852 ❄), `pickerWarthArlberg` (query „Warth am Arlberg Dorfplatz“: same row first), `stopDetailWarth` (hero with snowcap tile, VB, Ski Arlberg, Bregenzerwald, KlimaTicket Ö, lines incl. Skibus „nur im Winter“, ski-pass card „Talstation Dorfbahn Warth · 77 m“), `stopDetailStAnton` (RJX RJ ICE EC IC D · NJ EN · 270 760 6 · SV400), `tripEditorRouteBadges`. |
| AT-U4 | **VoiceOver:** the Warth row label is exactly „Warth (Vorarlberg) Dorfplatz, Bushaltestelle, Vorarlberg, Skigebiet Ski Arlberg, Linien: Bus 110, Bus 852, Skibus“. The state mark reads „Bundesland Vorarlberg“. The ski badge reads „Skigebiet Ski Arlberg“, also when only the glyph is visible. |
| AT-U5 | **Contrast:** `$DESIGN/tokens_check.json` values are reproduced by the token constants. All text ≥ 4.5:1. `Theme.live` light = `#0B7A4E`. |
| AT-U6 | **Legal guard (CI script):** `git ls-files` contains no file from `$S/logos`, no `logo-pack*`, no image asset named `*wappen*`/`*arms*`/`*arlberg*`. The only brand-drawing code is the existing `GoogleLogo`/`MicrosoftLogo` sign-in buttons. `Copy+Places.swift` contains the ODbL and „keine offiziellen Logos“ texts. |
| AT-U7 | **Offline behaviour:** airplane mode → stop detail shows lines, tags and ski card, no departures section, no error banner. With a provider but declined consent → the single „Live-Abfahrten aktivieren“ row. |

## 6.4 Live (opt-in `KB_LIVE_TESTS=1`, OEBB_LIVE §D3 rules: single requests, honest UA)

| ID | Test |
|---|---|
| AT-L1 | Warth Dorfplatz board, 90 min → every live line matches an offline line or is reported. Lines ⊇ {110, 852} on a weekday in autumn. |
| AT-L2 | St. Anton Bahnhof board → long-distance plates come out as categories (RJX/RJ/EC …), never train numbers. |

## 6.5 Device checklist (manual, before release)

- Type „Warth am Arlberg Dorfplatz“ in „Fahrt erfassen › Von“ → first row, badges visible, tap → route card shows VB · Ski Arlberg · `110 852`. Long press → „Haltestelle ansehen“ → the detail matches `02-stop-warth-*`.
- Dynamic Type `accessibility3`: the row gets its third line and plates wrap; the detail title wraps (2 lines).
- Lock-screen widget in vibrant mode: outline plates.
- Cold launch with places v2: the first frame is not delayed (the index builds in the background, as today).

---

# PART 7: Risks and open questions

| # | Risk / question | Mitigation / owner |
|---|---|---|
| R1 | ÖV-GK has no licence → blocks public release (stops **and** line refs) | MVO account + `--gtfs` feeds (also fixes winter/ski/renumbering gaps), or written AustriaTech/ÖROK permission. Owner: product owner. Tracked in DATA_SOURCES §3. |
| R2 | MVO €20,000 penalty for outdated timetable data | December rebuild; `gtfsValidity` guard hides lines after expiry (§1.10.1) |
| R3 | State colours / ski-area names as text | short legal review before release (BADGE_SPEC §1) |
| R4 | The user expects official logos | §1.10.4: permission-gated slot; own design meanwhile. The Landeswappen stay excluded. |
| R5 | Ski-pass alliances unverified | `verified` flag (E5); UI hides them until checked |
| R6 | Winter lines (ski buses) only from OSM until MVO; Scotty has winter data only from about November | M8 shows special services; live completion after WP-A; `skiCandidate` stays hidden |
| R7 | u16 stop indices (65,535) | build assertion; v3 if ever exceeded |
| R8 | Pure-Swift Inflate on older devices | ~43 ms on one x86 core; budget 1.30 s total; Darwin fast path allowed later behind measurement |
| R9 | Elevation („Warth · 1.495 m“) and lift geometries are missing | P2: OSM `ele` of the locality node + `aerialway` polylines into stops_osm.bin (new sections `ELEV`, `LIFT`; no version bump needed) |
| R10 | `TripEntity.lineKeysRaw` needs a Cloud sync field | additive, optional; coordinate with the KlimaCloud/Worker owner in WP-U4 or defer the „Gefahren mit“ row |

---

## Appendix A: Artefacts produced for this spec

| Path | What |
|---|---|
| `$SPEC/encode_v2.py` | v2 writer + reader prototype (the reference for the WP-D1 port); `--deflate`, `--no-next`, `--localities-v2` |
| `$SPEC/show_v2.py` | Python reader + M1–M7 merge; prints the `Place.lines`/`tags` expectations per id |
| `$SPEC/out_deflate/` | **v2 files as specified** (places.bin 1,194,232 B, stops_osm.bin 204,824 B, localities.bin 637,416 B) + `sizes.json` |
| `$SPEC/out_raw/` | the same, uncompressed (5,325,364 B), for comparison |
| `$SPEC/show_examples.json` | decoded Warth / St. Anton / Wien Floridsdorf (shows E1) |
| `$SPEC/swift/Inflate.swift`, `swift/main.swift`, `swift/bench` | pure-Swift Inflate + CRC and the benchmark (26.4 / 4.3 / 12.0 ms) |
| `$SPEC/swift/fuzz/` | Inflate robustness check (300 mutations, 0 traps) |
| `$SPEC/proto_context_search.py`, `proto_context_results.json` | context-word ranking prototype on `scripts/places_reference.py` (repo unchanged) and its results (§2.4) |

Reproduce:

```sh
S=<session scratchpad>   # session artefacts (not in the repo)
REPO=<repository root>
cd $S/enrich/spec
python3 -I encode_v2.py --places-bin $REPO/App/Resources/places.bin \
  --localities-bin $REPO/App/Resources/localities.bin --lines $S/enrich/lines/out \
  --lines-official $S/enrich/lines/out_official --tags $S/enrich/tags/out/tags.json \
  --build-places $S/places/build_places.py --out out_deflate --localities-v2 \
  --deflate RECS,STRS,LSTP,TAGS,META,LPAT,LCAT,LNAM,GTAG,EXTR,GEMS
python3 -I show_v2.py out_deflate at:48:344 at:47:1222
swiftc -O -o swift/bench swift/main.swift swift/Inflate.swift && swift/bench out_deflate/*.bin
python3 -I proto_context_search.py "$REPO" $S/enrich/tags/out/tags_app.json
```

## Appendix B: Prototype deltas the port must close

The prototype measures the format faithfully. These points differ from the final spec:

1. **Termini:** stored as names only (`terminiKind` 1). The spec adds stop indices (kind 2, E2).
2. **Curated ski areas** sit in the OSM META. Spec: curated areas in places.bin META, OSM-only areas in stops_osm.bin META; `hue` mapped, raw colours dropped (§1.4.1, AT-D9).
3. **One shared operator list** in both METAs. Spec: official list ++ `operatorsExtra`, plus display names (E4).
4. **Tag provenance** approximated by key. Spec: per-tag `osm` flag from `build_tags.py` (E-provenance, §1.7.2 step 5).
5. **Rail line identity** not fixed yet (E1). The prototype's Floridsdorf output shows the bug on purpose.
6. **KlimaTicket product names and `build` info** not yet in META.
7. **`RPRD`** falls back to the full build's `p[]` when the official build lacks it. Spec: the official build only (ÖBB GTFS is official).

## Appendix C: Implementation notes (WP-C2, WP-C4)

**WP-C2** (`Places/Enrichment/*`, `PlaceIndex` §2.3 API) follows §1.6 with these decisions:
- **M3 dedupe key** = `LinePlateText.dedupeKey` with the stop's services (the same key `LinePlateOrder` uses), so the
  detail list and the plates agree. Presentation (family, dedupe id, display rank) is precomputed once per catalogue
  line; a stop's lines are merged with integers and materialised at the end.
- **M4:** a superseded line without a successor is hidden; successors are followed ≤ 4 links.
- **M6:** a rail category becomes a plate only when no plate of that category is already shown (`REX1` covers `REX`,
  `S1` covers `S`); an exact plate match (OSM „RJ“ + RPRD „RJ“) makes that line timetable-confirmed. Floridsdorf
  therefore shows `REX1 S U6 5` + overflow, not an extra `REX`/`R`/`CJX`.
- **Search rows** carry the M8 compact lines and the tags, filled after the merge (≤ 20 rows) and memoised per stop
  (bounded cache, 2,048 stops), so a keystroke stays at the v1 cost.
- **Towns:** lines and ski area/regions of their main stop, their own Gemeinde and KlimaTicket default.
- **Bezirk** of Vienna is 900 (`META.bezirke`), the Gemeindebezirk is `wienBezirk`.
- `StopDetails.klimaTicketProducts` is empty for `check` / `notIncluded`; `attribution` lists the official part and,
  with the OSM layer, the ODbL part (the live part is the UI's).
- v1 files keep plates from the legacy line string (`PlaceEnrichment.legacyLines`).
- The presentation helpers got ASCII fast paths with identical results (Foundation's `String.contains` bridges to
  NSString on Linux).

**WP-C4** (`PlaceContext.swift`, `PlaceRanking.swift`, `scripts/places_reference.py`) refines §2.4 after reviewing the
golden diffs; all AT-C7 expectations and the prototype scores (207.6 / 63.5, 142.8 / 140.6, 147.8 / 145.6) hold:
1. **A place outside the area counts the word as unmatched** (relaxed matching only, −0.40) instead of −0.30, so a
   context word never admits places elsewhere: „Maria-Theresien-Straße 1 Innsbruck“ keeps its goldens, „Hall i.T.“
   loses the Styrian Ort Hall, „Steinbrunn im Bgld“ the Upper Austrian Steinbrunn (the only golden changes).
2. **Context words act only when another word names a place selectively** (≤ 500 postings): „bad gastein“ and
   „st johann“ name the place with the area word itself and rank as before (no Bad Hofgastein in „bad gastein“).
3. **A still-typed prefix** of an area word („warth arlb“) is scored by membership but stays an ordinary word for
   candidate generation („warth am arlberg dorf“ must not turn „dorf“ into „Dorfgastein“).
4. Generic words are never context words, also not by prefix („gletscher“ → „gletscherwelt“).
5. The vocabulary words come from the query tokenizer; state abbreviations resolve through the lexicon (Vlbg → vorarlberg).
6. A word that repeats an earlier query word is a name word again („innsbruck innsbruck“ needs two name words).

Context sets are built at index time from the sorted table (`PlaceTable(records:municipalities:options:context:)`);
425 terms on the shipped data. Release (Linux, one core): 100 typical queries 22 ms, 10 context-word queries 1.2 ms,
enrichment parse 51 ms, `details(for:)` 0.33 ms.

**Review (2026-10-09, after C1–C4, D1/D2 and the logo core landed):**
- Robustness: `GeoBox.contains` no longer traps on an inverted/NaN box from META; `SpokenLabels.distance`/`departure`
  clamp non-finite values; a stop abroad (state X) without its own KlimaTicket tag is `notIncluded` („Ausland“, the build
  tags every one of them) instead of the Austrian default. `PresentationFuzzTests` drives random refs, names, queries
  and tags through every presentation helper.
- Speed: record strings are split on bytes (decode of the three files 191 → 113 ms), line classification and spoken
  plates trim without Foundation; the `StationIndex` façade (search, nearest, `station(id:)`) skips lines and tags.
  Cold build of the whole index 0.91–0.94 s (budget 1.30 s); enrichment parse ~45 ms (line item 40 ms).
- Memory: `PlaceRecord` 176 → 160 B, per-stop state codes as bytes; the built v2 index is ~41 MB resident against ~36 MB
  for the v1 files measured the same way (+5 MB, budget +8 MB).
- CI: `scripts/check_places_v2.py check` (AT-D1…D9) runs in the Linux job; the release step adds
  `PlaceFormatPerformanceTests` and `PlaceIndexBudgetTests` (cold build, resident memory).

