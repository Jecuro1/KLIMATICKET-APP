import Foundation
import XCTest
@testable import KlimaCore

/// WP-C2: the runtime merge of places.bin (official layer) and stops_osm.bin (OSM layer), docs/ENRICH_SPEC.md §1.6
/// M1–M8 and the §2.3 API, on the shipped App/Resources data (AT-C3, AT-C4, AT-C5, AT-C6, AT-D5, AT-D8).
final class PlaceEnrichmentTests: XCTestCase {
    static let warth = "at:48:344"
    static let stAnton = "at:47:1222"
    static let floridsdorf = "at:49:334"

    var index: PlaceIndex { PlaceFixtures.index }

    // MARK: AT-C4 lines

    func testWarthLinesMerged() throws {
        XCTAssertTrue(index.dataInfo.hasOSMLayer, "the shipped stops_osm.bin must load (BASE matches)")
        let compact = index.compactLines(for: Self.warth)
        XCTAssertEqual(compact.map(\.ref), ["110", "852", "Skibus"])
        XCTAssertEqual(compact.map(\.kind), [.bus, .bus, .skibus])
        let plates = compact.map { LinePlateText.text(for: $0, size: .s) }
        XCTAssertEqual(plates.map(\.text), ["110", "852", ""])
        XCTAssertEqual(plates.map(\.glyph), [nil, nil, .snowflake])
        XCTAssertEqual(SpokenLabels.plateRow(compact), "Linien: Bus 110, Bus 852, Skibus")
        XCTAssertEqual(index.place(id: Self.warth)?.lines, compact, "Place.lines = the M8 compact set")
        XCTAssertEqual(index.place(id: Self.warth)?.linesText, "110,852,Skibus")

        let all = index.stopLines(for: Self.warth)
        XCTAssertEqual(all.map(\.line.ref), ["110", "709", "852", "Skibus"])
        let byRef = Dictionary(uniqueKeysWithValues: all.map { ($0.line.ref, $0) })
        // AT-D4: 110 and 852 timetable-confirmed with operator and termini; 709 and the Skibus from OSM
        let l110 = try XCTUnwrap(byRef["110"]), l852 = try XCTUnwrap(byRef["852"])
        XCTAssertEqual(l110.confidence, .timetable)
        XCTAssertEqual(l852.confidence, .timetable)
        XCTAssertEqual(l110.line.operatorName, "Postbus")
        XCTAssertEqual(l110.line.operatorLegalName, "Österreichische Postbus AG")
        XCTAssertEqual(l110.line.network, .vvt, "E3: the network of a cross-border line is its majority")
        XCTAssertEqual(Set(l110.line.states), ["T", "V"])
        XCTAssertEqual(l110.line.termini?.to, "Reutte Bahnhof")
        XCTAssertEqual(l110.line.termini?.toStopID, "at:47:2251")
        XCTAssertEqual(l852.line.operatorName, "Landbus Bregenzerwald")
        XCTAssertEqual(l852.line.termini?.from, "Schoppernau Gemeindeamt")
        XCTAssertEqual(l852.line.termini?.toStopID, "at:48:2279")
        XCTAssertEqual(l852.line.key, "VVV|bus|852")
        XCTAssertEqual(l852.line.id, index.line(key: "VVV|bus|852")?.id)
        XCTAssertEqual(byRef["709"]?.confidence, .osmOnly)
        XCTAssertEqual(byRef["709"]?.line.operatorName, "Ortsbus Lech")
        XCTAssertTrue(byRef["709"]?.line.sources.contains(.osm) ?? false)
        let ski = try XCTUnwrap(byRef["Skibus"])
        XCTAssertEqual(ski.confidence, .osmOnly)
        XCTAssertTrue(ski.line.flags.isSuperset(of: [.ski, .winter]))
        XCTAssertEqual(ski.line.flags.displayNotes, ["nur im Winter"])
        XCTAssertEqual(ski.line.kind, .skibus)
        XCTAssertFalse(l852.line.flags.displayNotes.contains("Schultage"), "schooldays? never shows (M7)")
        XCTAssertLessThanOrEqual(ski.directions.count, 3)
    }

    func testStopWithoutLines() throws {
        let e = try XCTUnwrap(index.enrichment)
        let empty = try XCTUnwrap((0..<e.stopCount).first { e.stopLines($0).isEmpty && e.railMask($0) == nil })
        let id = e.stopIDs[empty]
        XCTAssertEqual(index.stopLines(for: id), [])
        XCTAssertEqual(index.compactLines(for: id), [])
        let d = try XCTUnwrap(index.details(for: id))
        XCTAssertTrue(d.lines.isEmpty, "the detail then shows „Kein regelmäßiger Linienverkehr bekannt“")
        XCTAssertTrue(d.compactLines.isEmpty)
        XCTAssertEqual(index.stopLines(for: "at:does-not-exist"), [])
        XCTAssertNil(index.details(for: "at:does-not-exist"))
        XCTAssertEqual(index.tags(for: "at:does-not-exist"), .empty)
    }

    // MARK: AT-C5 tags

    func testWarthTagsAndSkiArea() throws {
        let tags = index.tags(for: Self.warth)
        XCTAssertEqual(tags.primarySkiArea?.id, "ski-arlberg")
        XCTAssertEqual(tags.primarySkiArea?.distanceMeters, 77)
        XCTAssertTrue(tags.showsSnowcap)
        let area = try XCTUnwrap(index.skiArea(id: "ski-arlberg"))
        XCTAssertEqual(area.name, "Ski Arlberg")
        XCTAssertEqual(area.shortName, "Arlberg")
        XCTAssertEqual(area.hue, "enzian")
        XCTAssertEqual(area.glyph, .peaks3)
        XCTAssertEqual(area.monogram, "ARL")
        XCTAssertTrue(area.isVerified)
        XCTAssertFalse(area.isOSMOnly)
        XCTAssertGreaterThan(area.liftCount, 50, "OSM statistics (stops_osm.bin META skiAreaStats)")
        XCTAssertTrue(area.bbox.contains(GeoPoint(latitude: 47.2556, longitude: 10.1829)))
        let lift = try XCTUnwrap(tags.lift)
        XCTAssertEqual(lift.name, "Dorfbahn Warth")
        XCTAssertEqual(lift.role, .valley)
        XCTAssertEqual(lift.liftType, "gondola")
        XCTAssertEqual(lift.walkMinutes, 1)
        XCTAssertEqual(tags.klimaTicket.status, .valid)
        XCTAssertEqual(tags.klimaTicket.regionalTicketIDs, ["vbg-maximo"])
        XCTAssertEqual(Set(tags.regions.map(\.id)), ["arlberg", "bregenzerwald"])
        XCTAssertEqual(tags.services, [.skiBus])
        XCTAssertEqual(tags.gkz, 80239)
        XCTAssertEqual(tags.bezirk, 802)
        XCTAssertNil(tags.wienBezirk)

        let d = try XCTUnwrap(index.details(for: Self.warth))
        XCTAssertEqual(d.skiArea?.id, "ski-arlberg")
        XCTAssertEqual(d.regions.map(\.name), ["Arlberg", "Bregenzerwald"])
        XCTAssertEqual(d.bezirkName, "Bregenz")
        XCTAssertEqual(d.klimaTicketProducts.map(\.id), ["oe", "vbg-maximo"])
        XCTAssertEqual(d.klimaTicketProducts.map(\.name), ["KlimaTicket Ö", "KlimaTicket VMOBIL MAXIMO"])
        XCTAssertEqual(d.attribution.count, 2)
        XCTAssertTrue(d.attribution[1].contains("OpenStreetMap"))
        XCTAssertNotNil(d.dataValidUntil)
        XCTAssertFalse(d.neighbours.isEmpty)
        XCTAssertLessThanOrEqual(d.neighbours.count, 8)
        XCTAssertTrue(d.neighbours.allSatisfy { $0.distanceMeters <= 600 && $0.place.id != Self.warth })
        XCTAssertEqual(d.place.id, Self.warth)
        XCTAssertEqual(d.compactLines.map(\.ref), ["110", "852", "Skibus"])
        XCTAssertEqual(PlaceMarkSelection.rowAreaMark(place: d.place, tags: d.tags), .skiArea(id: "ski-arlberg"))
        XCTAssertEqual(PlaceMarkSelection.rowMark(tags: d.tags)?.kind, .talstation)
    }

    func testStAntonTagsAndRailCategories() throws {
        let tags = index.tags(for: Self.stAnton)
        XCTAssertTrue(Set(tags.klimaTicket.regionalTicketIDs).isSuperset(of: ["tirol", "city-klimaticket-st-anton"]))
        XCTAssertEqual(tags.klimaTicket.extendedTicketIDs, ["vbg-maximo"])
        let types = Dictionary(uniqueKeysWithValues: tags.types.map { ($0.type, $0) })
        for t in [PlaceType.trainStation, .longDistance, .nightTrain, .parkAndRide] { XCTAssertNotNil(types[t], "\(t)") }
        XCTAssertEqual(types[.parkAndRide]?.distanceMeters, 28)
        XCTAssertEqual(tags.accessibility, .yes)
        XCTAssertEqual(tags.primarySkiArea?.id, "ski-arlberg")

        // AT-C6 / M6: RPRD categories as plates, deduped with the OSM „RJ“ and „EN 40465“
        let compact = index.compactLines(for: Self.stAnton)
        let fern = compact.filter { $0.kind == .fern }.map { LinePlateText.text(for: $0, size: .l).text }
        let nacht = compact.filter { $0.kind == .nacht }.map { LinePlateText.text(for: $0, size: .l).text }
        XCTAssertEqual(fern, ["RJX", "RJ", "ICE", "EC", "IC", "D"])
        XCTAssertEqual(nacht, ["EN", "NJ"])
        let all = index.stopLines(for: Self.stAnton)
        XCTAssertEqual(all.filter { LinePlateText.text(for: $0.line, size: .l).text == "RJ" }.count, 1)
        XCTAssertEqual(all.first { $0.line.ref == "RJ" }?.confidence, .timetable, "OSM RJ + RPRD RJ = timetable-confirmed")
        XCTAssertTrue(all.first { $0.line.ref == "RJX" }?.line.isSynthetic ?? false)
        XCTAssertEqual(all.first { $0.line.ref == "RJX" }?.line.key, "ÖBB|rail|RJX")
        XCTAssertEqual(Set(compact.filter { $0.kind == .bus }.map(\.ref)), ["270", "760"])
        XCTAssertTrue(compact.contains { $0.kind == .sev && $0.ref == "SV400" })
        XCTAssertFalse(compact.contains { $0.ref == "6" }, "OSM-only bus 6 is detail-only (M8)")
        XCTAssertTrue(all.contains { $0.line.ref == "6" && $0.confidence == .osmOnly })
        XCTAssertEqual(index.details(for: Self.stAnton)?.klimaTicketProducts.map(\.id),
                       ["oe", "tirol", "city-klimaticket-st-anton", "vbg-maximo"])
    }

    func testFloridsdorfLinesAndTags() throws {
        let compact = index.compactLines(for: Self.floridsdorf)
        let (shown, overflow) = LinePlateOrder.diverse(compact, maxCount: 4)
        XCTAssertEqual(shown.map { $0.kind }, [.regio, .sBahn, .uBahn, .tram])
        XCTAssertEqual(shown.first?.ref, "REX1")
        XCTAssertEqual(shown[2].ref, "U6")
        XCTAssertGreaterThan(overflow, 20)
        let all = index.stopLines(for: Self.floridsdorf)
        // E1: R1/R3 of the right component (no Kleinreifling/Linz, Summerau)
        let r1 = try XCTUnwrap(all.first { $0.line.ref == "R1" })
        XCTAssertFalse([r1.line.termini?.from, r1.line.termini?.to].contains { ($0 ?? "").contains("Kleinreifling") })
        let r3 = try XCTUnwrap(all.first { $0.line.ref == "R3" })
        XCTAssertFalse([r3.line.termini?.from, r3.line.termini?.to].contains { ($0 ?? "").contains("Summerau") })
        XCTAssertFalse(all.contains { $0.line.isSynthetic && ["REX", "R", "CJX"].contains($0.line.ref) },
                       "M6 adds a category plate only when no plate of that category exists")
        let tags = index.tags(for: Self.floridsdorf)
        XCTAssertEqual(tags.wienBezirk, 21)
        XCTAssertEqual(tags.bezirk, 900)
        XCTAssertEqual(index.details(for: Self.floridsdorf)?.wienBezirkName, "Floridsdorf")
        XCTAssertTrue(tags.services.contains(.nightBus))
        XCTAssertEqual(tags.accessibility, .limited)
    }

    // MARK: towns, lookups, merger

    func testTownsCarryTheirMainStop() throws {
        let town = try XCTUnwrap(index.place(id: "osm:n73089810"))
        XCTAssertEqual(town.kind, .town)
        XCTAssertEqual(town.mainStopID, Self.warth)
        XCTAssertEqual(town.lines.map(\.ref), ["110", "852", "Skibus"])
        XCTAssertEqual(town.tags.primarySkiArea?.id, "ski-arlberg")
        XCTAssertEqual(Set(town.tags.regions.map(\.id)), ["arlberg", "bregenzerwald"])
        XCTAssertNil(town.tags.lift, "towns carry ski area and regions only")
        XCTAssertEqual(town.tags.klimaTicket.regionalTicketIDs, ["vbg-maximo"])
        XCTAssertEqual(town.tags.gkz, 80239)
    }

    func testLookups() throws {
        XCTAssertGreaterThan(index.skiAreas.count, 150)
        XCTAssertFalse(index.skiAreas.contains { $0.kind == .alliance })
        XCTAssertTrue(index.skiAreas.contains { $0.isOSMOnly })
        let names = index.skiAreas.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedDescending })
        XCTAssertEqual(index.skiArea(id: "ski-amade")?.kind, .alliance)
        XCTAssertEqual(index.skiArea(id: "ski-amade")?.isVerified, false)
        XCTAssertEqual(index.skiArea(id: "sonnenkopf")?.parentID, "ski-arlberg")
        for a in index.skiAreas {
            XCTAssertTrue(["enzian", "gletscher", "daemmerung", "alpengluehen", "zirbe", "morgenrot", "bergsee", "fels"]
                .contains(a.hue), "AT-D9 hue \(a.id)")
        }
        XCTAssertEqual(index.region(id: "bregenzerwald")?.name, "Bregenzerwald")
        XCTAssertEqual(index.region(id: "bregenzerwald")?.kind, .tourism)
        XCTAssertTrue(index.regions.contains { $0.kind == .landscape })
        XCTAssertEqual(index.operatorName("Österreichische Postbus AG"), "Postbus")
        XCTAssertEqual(index.operatorName("OEBB Personenverkehr AG Kundenservice"), "ÖBB")
        XCTAssertNil(index.line(key: "VVV|bus|nope"))

        let arlberg = index.stops(inSkiArea: "ski-arlberg")
        XCTAssertTrue(arlberg.contains { $0.id == Self.warth })
        XCTAssertTrue(arlberg.contains { $0.id == Self.stAnton })
        XCTAssertFalse(arlberg.contains { $0.id == "at:48:187" }, "St. Anton im Montafon is not Arlberg")
        XCTAssertTrue(arlberg.allSatisfy { ($0.tags.skiAreas.first { $0.id == "ski-arlberg" }?.confidence ?? 0) >= 70 })
        XCTAssertEqual(index.stops(inSkiArea: "ski-arlberg", limit: 3).count, 3)
        XCTAssertEqual(index.stops(inSkiArea: "ski-arlberg", minConfidence: 101), [])
        XCTAssertEqual(index.stops(inSkiArea: "no-such-area"), [])
        let bw = index.stops(inRegion: "bregenzerwald")
        XCTAssertTrue(bw.contains { $0.id == Self.warth })
        XCTAssertTrue(bw.allSatisfy { $0.state == "V" })
        let imp = bw.map(\.importance)
        XCTAssertEqual(imp, imp.sorted(by: >), "by importance")
    }

    /// `StationIndex` (search, nearest, station(id:)) only needs `Place.station`: those paths skip lines and tags.
    func testStationPathsSkipEnrichment() throws {
        let p = try XCTUnwrap(index.place(id: Self.warth))
        let plain = index.nearest(to: p.coordinate, limit: 6, maxMeters: 2_000, enrich: false)
        let full = index.nearest(to: p.coordinate, limit: 6)
        XCTAssertEqual(plain.map(\.place.id), full.map(\.place.id))
        XCTAssertTrue(plain.allSatisfy { $0.place.lines.isEmpty && $0.place.tags == .empty })
        XCTAssertTrue(full.contains { !$0.place.lines.isEmpty })
        XCTAssertEqual(plain.map(\.place.station), full.map(\.place.station))
        XCTAssertEqual(index.search("warth", context: .tripLog, limit: 8, enrich: false).map(\.station),
                       index.search("warth", context: .tripLog, limit: 8).map(\.station))
        XCTAssertEqual(index.station(id: Self.warth), p.station)
        let stations = StationIndex(stations: [])
        stations.attach(places: index)
        XCTAssertEqual(stations.nearest(to: p.coordinate, limit: 3).map(\.station.id), full.prefix(3).map(\.place.station.id))
    }

    func testLegacyStationIDsResolve() throws {
        // stations.json ids of the previous app version map to the same place, lines and tags
        let p = try XCTUnwrap(index.place(id: Self.stAnton))
        let legacy = try XCTUnwrap(p.legacyStationIDs.first)
        XCTAssertEqual(index.stopLines(for: legacy), index.stopLines(for: Self.stAnton))
        XCTAssertEqual(index.tags(for: legacy), p.tags)
        XCTAssertEqual(index.details(for: legacy)?.place.id, Self.stAnton)
    }

    func testMergedLiveRowsKeepOfflineLinesAndTags() throws {
        let q = "Lech Postamt"
        let offline = index.search(q, context: .planner, limit: 20)        // the app's flow: offline first, live later
        XCTAssertTrue(offline.contains { !$0.lines.isEmpty }, "search rows carry their lines")
        let merged = index.merged(offline: offline, live: PlaceFixtures.live("lm_all_lech_postamt"), query: q, limit: 8)
        let both = merged.filter { $0.source == .both }
        XCTAssertFalse(both.isEmpty)
        for p in both {
            XCTAssertEqual(p.lines, index.compactLines(for: p.id), p.name)
            XCTAssertEqual(p.tags, index.tags(for: p.id), p.name)
        }
        for p in merged where p.source == .live {
            XCTAssertEqual(p.lines, [])
            XCTAssertEqual(p.tags, .empty)
        }
    }

    // MARK: AT-D8 superseded, AT-D5 spot checks

    func testSupersededLinesNeverShow() throws {
        let e = try XCTUnwrap(index.enrichment)
        let old: Set<String> = ["5144", "5173", "5377", "4002", "4004", "4008"]
        var shown: [String] = []
        for s in 0..<e.stopCount {
            for l in e.stopLines(s) where l.line.flags.contains(.superseded) || old.contains(l.line.ref) {
                shown.append("\(e.stopIDs[s]) \(l.line.ref)")
            }
        }
        XCTAssertEqual(shown, [])
        XCTAssertTrue(index.stopLines(for: "at:42:4622").contains { $0.line.ref == "184" }, "Patergassen Ort shows 184")
    }

    /// The 51 tag spot checks of data/places_spot_checks.json through the Swift reader (same rules as
    /// scripts/check_places_v2.py `run_spot_checks`).
    func testSpotChecksThroughSwiftReader() throws {
        let url = PlaceFixtures.repoRoot.appendingPathComponent("data/places_spot_checks.json")
        let spots = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(spots.count, 51)
        let e = try XCTUnwrap(index.enrichment)
        let byID = Dictionary(e.stopIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var passed = 0
        for spot in spots {
            let id = spot["id"] as! String
            guard let i = byID[id] else { XCTFail("\(id) not found"); continue }
            let tags = e.tags(i)
            var have: [String: [(value: String, conf: Int, role: String?)]] = [:]
            for t in e.rawTags(i) where t.key != "klimaticket" { have[t.key, default: []].append((t.value, t.confidence, t.role)) }
            let kt = tags.klimaTicket
            let ktStatus = ["valid": "yes", "check": "check", "notIncluded": "no", "border": "border"][kt.status.rawValue]!
            have["klimaticket"] = [(ktStatus, e.rawTags(i).first { $0.key == "klimaticket" }?.confidence ?? 90, nil)]
            have["state"] = [(e.stopState(i) ?? "", 100, nil)]
            if let g = tags.gkz {
                have["bezirk"] = [(g / 10000 == 9 ? "900" : String(format: "%03d", g / 100), 99, nil)]
                if let w = tags.wienBezirk { have["wienBezirk"] = [(String(w), 99, nil)] }
            }
            var fails: [String] = []
            for exp in spot["expect"] as! [[Any]] {
                let key = exp[0] as! String, val = exp[1] as! String, minc = (exp[2] as! NSNumber).intValue
                let want = exp.count > 3 ? exp[3] as? [String: Any] ?? [:] : [:]
                let neg = key.hasPrefix("!")
                let k = String(key.drop { $0 == "!" })
                if k == "kt_reg" {
                    if (kt.regionalTicketIDs + kt.extendedTicketIDs).contains(val) == neg { fails.append("\(key)=\(val)") }
                    continue
                }
                var found = have[k] ?? []
                if val != "*" {
                    if val.contains(where: { "^$*[]|(".contains($0) }) {
                        let re = try NSRegularExpression(pattern: val)
                        found = found.filter { re.firstMatch(in: $0.value, range: NSRange($0.value.startIndex..., in: $0.value)) != nil }
                    } else {
                        found = found.filter { $0.value == val }
                    }
                }
                if let role = want["role"] as? String { found = found.filter { $0.role == role } }
                let ok = neg ? found.isEmpty : found.contains { $0.conf >= minc }
                if !ok { fails.append("\(key)=\(val)>=\(minc) (got \(have[k]?.map { "\($0.value) \($0.conf)" } ?? []))") }
            }
            if fails.isEmpty { passed += 1 } else { XCTFail("AT-D5 \(id): \(fails.joined(separator: "; "))") }
        }
        XCTAssertEqual(passed, 51)
    }

    func testUnverifiedAlliancesNeverSurface() throws {
        let e = try XCTUnwrap(index.enrichment)
        let raw = (0..<e.stopCount).filter { s in e.rawTags(s).contains { $0.key == "skiAlliance" } }
        XCTAssertGreaterThan(raw.count, 100, "the OSM layer has alliance tags")
        for s in raw.prefix(300) {
            for a in e.tags(s).skiAlliances { XCTAssertEqual(index.skiArea(id: a)?.isVerified, true, "\(e.stopIDs[s]) \(a)") }
        }
    }

    // MARK: AT-C3 official layer only

    func testOfficialLayerOnly() throws {
        let ds = PlaceFixtures.dataset          // places.bin + localities.bin, no OSM file
        XCTAssertFalse(ds.dataInfo.hasOSMLayer)
        let e = PlaceEnrichment(stops: ds.stops, official: try XCTUnwrap(ds.officialLayer), osm: nil)
        let i = try XCTUnwrap(e.stopIDs.firstIndex(of: Self.warth))
        XCTAssertEqual(e.compactLines(i).map(\.ref), ["110", "852"])
        XCTAssertEqual(e.stopLines(i).map(\.line.ref), ["110", "852"])
        XCTAssertTrue(e.stopLines(i).allSatisfy { $0.confidence == .timetable && !$0.line.sources.contains(.osm) })
        let tags = e.tags(i)
        XCTAssertTrue(tags.skiAreas.isEmpty, "ski tags are OSM-derived")
        XCTAssertNil(tags.lift)
        XCTAssertEqual(Set(tags.regions.map(\.id)), ["arlberg", "bregenzerwald"], "official Gemeinde defaults")
        XCTAssertEqual(tags.klimaTicket.regionalTicketIDs, ["vbg-maximo"])
        XCTAssertNotNil(e.catalog.areas["ski-arlberg"], "curated areas live in places.bin")
        XCTAssertEqual(e.catalog.areas["ski-arlberg"]?.liftCount, 0, "lift counts are OSM statistics")
        XCTAssertTrue(e.catalog.areas.values.allSatisfy { !$0.isOSMOnly })

        // a stops_osm.bin of another build (different BASE) is ignored (M1)
        let foreign = try Data(contentsOf: PlaceFixtures.dir.appendingPathComponent("v2/stops_osm_other_base.bin"))
        let mixed = try PlaceDataset(places: Data(contentsOf: PlaceFixtures.placesURL), localities: nil, osm: foreign)
        XCTAssertNil(mixed.osmLayer)
        XCTAssertFalse(mixed.dataInfo.hasOSMLayer)
        XCTAssertNotNil(mixed.osmLayerIssue)
        let e2 = PlaceEnrichment(stops: mixed.stops, official: try XCTUnwrap(mixed.officialLayer), osm: mixed.osmLayer)
        XCTAssertFalse(e2.hasOSMLayer)
        XCTAssertEqual(e2.compactLines(try XCTUnwrap(e2.stopIDs.firstIndex(of: Self.warth))).map(\.ref), ["110", "852"])
    }

    // MARK: v1 files and the prototype fixtures

    func testV1FilesGiveLegacyLines() throws {
        let dir = PlaceFixtures.dir.appendingPathComponent("v2/v1")
        let idx = try PlaceIndex(placesURL: dir.appendingPathComponent("places.bin"),
                                 localitiesURL: dir.appendingPathComponent("localities.bin"))
        XCTAssertEqual(idx.dataInfo.formatVersion, 1)
        XCTAssertNil(idx.enrichment)
        let lines = idx.compactLines(for: Self.warth)
        XCTAssertEqual(lines.map(\.ref), ["110", "852"])
        XCTAssertEqual(lines.map(\.mode), [.bus, .bus])
        XCTAssertEqual(idx.stopLines(for: Self.warth).map(\.line.ref), ["110", "852"])
        XCTAssertEqual(idx.tags(for: Self.warth), .empty)
        XCTAssertEqual(idx.skiAreas, [])
        XCTAssertEqual(idx.details(for: Self.warth)?.lines.count, 2)
    }

    func testStepZeroFixturesDecode() throws {
        // Prototype-layout v2 subset (ENRICH_SPEC Appendix B deltas): must index without traps.
        let dir = PlaceFixtures.dir.appendingPathComponent("v2")
        let idx = try PlaceIndex(placesURL: dir.appendingPathComponent("places.bin"),
                                 localitiesURL: dir.appendingPathComponent("localities.bin"),
                                 osmURL: dir.appendingPathComponent("stops_osm.bin"))
        XCTAssertTrue(idx.dataInfo.hasOSMLayer)
        let refs = idx.compactLines(for: Self.warth).map(\.ref)
        XCTAssertTrue(refs.starts(with: ["110", "852"]), "\(refs)")
        XCTAssertTrue(idx.stopLines(for: Self.warth).contains { $0.line.ref == "709" && $0.confidence == .osmOnly })
        XCTAssertEqual(idx.tags(for: Self.warth).primarySkiArea?.id, "ski-arlberg")
        for p in idx.search("warth", limit: 20) + idx.search("st anton", limit: 20) {
            _ = idx.details(for: p.id)
        }
    }

    // MARK: robustness

    /// Random bytes in every enrichment section: the parser drops what does not fit and never traps.
    func testCorruptEnrichmentSectionsNeverTrap() throws {
        let ds = PlaceFixtures.dataset
        let official = try XCTUnwrap(ds.officialLayer)
        var rng = SeededRNG(seed: 0xE1C4)
        for round in 0..<40 {
            var sections = official.sections
            for tag in ["LCAT", "LNAM", "LSTP", "RPRD", "GTAG", "TAGS", "META"] where round % 3 != 0 || tag == "LSTP" {
                guard var b = sections[tag], !b.isEmpty else { continue }
                switch rng.next() % 4 {
                case 0: b = Array(b.prefix(Int(rng.next() % UInt64(b.count))))
                case 1: for _ in 0..<64 { b[Int(rng.next() % UInt64(b.count))] = UInt8(truncatingIfNeeded: rng.next()) }
                case 2: b = (0..<min(b.count, 4096)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
                default: b.insert(contentsOf: [0xFF, 0xFF, 0x03], at: Int(rng.next() % UInt64(b.count)))
                }
                sections[tag] = b
            }
            let layer = PlaceLayer(nRecords: official.nRecords, nGemeinden: official.nGemeinden,
                                   nStopRecords: official.nStopRecords, sections: sections)
            let e = PlaceEnrichment(stops: ds.stops, official: layer, osm: round % 2 == 0 ? layer : nil)
            for s in stride(from: 0, to: e.stopCount, by: 97) {
                _ = e.stopLines(s)
                _ = e.compactLines(s)
                _ = e.tags(s)
            }
        }
    }
}

/// AT-C8 (release gate in CI, step "Place search performance"): enrichment parse and `details(for:)` stay cheap.
final class PlaceEnrichmentPerformanceTests: XCTestCase {
    func testEnrichmentBuildAndDetailsBudget() throws {
        let ds = PlaceFixtures.dataset
        let official = try XCTUnwrap(ds.officialLayer)
        let osm = try PlaceDataset(places: Data(contentsOf: PlaceFixtures.placesURL), localities: nil,
                                   osm: Data(contentsOf: PlaceFixtures.osmURL)).osmLayer
        XCTAssertNotNil(osm)
        var build = Double.infinity
        for _ in 0..<3 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = PlaceEnrichment(stops: ds.stops, official: official, osm: osm)
            build = min(build, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        let index = PlaceFixtures.index
        let ids = ["at:48:344", "at:47:1222", "at:49:334", "at:49:1349", "at:47:1187", "at:46:31026", "osm:n73089810"]
        for id in ids { _ = index.details(for: id) }
        var worst = 0.0
        for id in ids {
            var one = Double.infinity
            for _ in 0..<5 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = index.details(for: id)
                one = min(one, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            }
            worst = max(worst, one)
        }
        print(String(format: "[places] enrichment parse %.1f ms, slowest details(for:) %.3f ms", build, worst))
        #if DEBUG
        XCTAssertLessThan(build, 5_000)
        XCTAssertLessThan(worst, 50)
        #else
        XCTAssertLessThan(build, 250, "enrichment parse (~40–80 ms on one core; generous for shared CI runners)")
        XCTAssertLessThan(worst, 1, "details(for:) < 1 ms (AT-C8)")
        #endif
    }
}
