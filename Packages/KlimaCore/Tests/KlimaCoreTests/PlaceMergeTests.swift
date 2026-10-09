import Foundation
import XCTest
@testable import KlimaCore

/// Live LocMatch decoding, collapses (C1/P1), plausibility, dedupe rules D0–D4 and the offline/live merge.
final class PlaceMergeTests: XCTestCase {
    func testLocMatchRequestShape() throws {
        let body = LocMatchDecoder.locMatchRequest("Wien Hbf ")
        XCTAssertEqual(body["meth"] as? String, "LocMatch")
        let req = try XCTUnwrap(body["req"] as? [String: Any])
        XCTAssertEqual(Set(req.keys), ["input"])
        let input = try XCTUnwrap(req["input"] as? [String: Any])
        XCTAssertEqual(Set(input.keys), ["loc", "maxLoc", "field"])
        XCTAssertEqual(input["field"] as? String, "S")
        XCTAssertEqual(input["maxLoc"] as? Int, 10)
        let loc = try XCTUnwrap(input["loc"] as? [String: Any])
        XCTAssertEqual(Set(loc.keys), ["type", "name"])
        XCTAssertEqual(loc["type"] as? String, "ALL")
        XCTAssertEqual(loc["name"] as? String, "Wien Hbf?")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testDecodeKindsAndFields() throws {
        let rows = PlaceFixtures.live("lm_all_maria_theresien_strasse_1_innsbruck")
        let addr = try XCTUnwrap(rows.first { $0.kind == .address })
        XCTAssertEqual(addr.title, "Maria-Theresien-Straße 1")
        XCTAssertEqual(addr.subtitle, "6020 Innsbruck")
        XCTAssertTrue(addr.lid?.hasPrefix("A=2@") ?? false)
        let poi = try XCTUnwrap(rows.first { $0.kind == .poi })
        XCTAssertNotNil(poi.poiCategory)
        XCTAssertTrue(poi.lid?.hasPrefix("A=4@") ?? false)
        let stop = try XCTUnwrap(rows.first { $0.kind.isStopLike })
        XCTAssertEqual(stop.extId, "791226")
        XCTAssertEqual(stop.state, "T")
        XCTAssertEqual(rows.map(\.liveRank), Array(1...rows.count))
        let towns = PlaceFixtures.live("lm_all_inns").filter { $0.kind == .town }
        XCTAssertEqual(towns.first?.extId, "1170101")
        XCTAssertEqual(LocMatchDecoder.stateFromExtId("891302"), "V")
        XCTAssertEqual(LocMatchDecoder.stateFromExtId("1290401"), "W")
        XCTAssertNil(LocMatchDecoder.stateFromExtId("8100108"))
    }

    func testCollapsesMetaPairsAndPOIDuplicates() throws {
        // C1: locality meta + station meta with identical crd/pCls/wt → one row with the other name as alias
        XCTAssertEqual(PlaceFixtures.live("lm_all_wien").count, 7)
        XCTAssertEqual(PlaceFixtures.live("lm_all_bregenz_bf").count, 8)
        XCTAssertEqual(PlaceFixtures.live("lm_all_seefeld").count, 9)
        let wien = PlaceFixtures.live("lm_all_wien")
        let flor = try XCTUnwrap(wien.first { $0.name == "Wien Floridsdorf Bahnhof (U)" })
        XCTAssertEqual(flor.kind, .station)
        XCTAssertTrue(flor.aliases.contains("Floridsdorf (Wien)"))
        // P1: "Hofburg, Rennweg 1, 6020 Innsbruck (1)/(2)" → one POI without the counter
        let hofburg = PlaceFixtures.live("lm_all_hofburg")
        XCTAssertEqual(hofburg.count, 9)
        XCTAssertEqual(hofburg.first?.name, "Hofburg, Rennweg 1, 6020 Innsbruck")
    }

    func testErrorsAndNonsenseGiveNoLiveRows() {
        XCTAssertTrue(PlaceFixtures.live("lm_param_field_Z_innsbruck").isEmpty)       // top-level HAMM
        XCTAssertTrue(PlaceFixtures.live("lm_schema_unknown_input_key").isEmpty)
        XCTAssertTrue(LocMatchDecoder.places(fromResponse: Data("not json".utf8)).isEmpty)
        // Scotty answers nonsense with its top stations – the plausibility filter drops them all
        let nonsense = PlaceFixtures.live("lm_all_xqzvvhjkq")
        XCTAssertFalse(nonsense.isEmpty)
        XCTAssertTrue(PlaceFixtures.index.rankLive(nonsense, query: "xqzvvhjkq").isEmpty)
        XCTAssertTrue(PlaceFixtures.index.merged(offline: [], live: nonsense, query: "xqzvvhjkq").isEmpty)
    }

    func testWalkingTimeFormulaMatchesHAFAS() {
        var n = 0
        for f in ["gp_nearby_maria_theresien_strasse_1_innsbruck", "gp_nearby_hofburg_wien", "gp_nearby_lech_dorf"] {
            for (dist, dur) in LocMatchDecoder.durations(fromResponse: PlaceFixtures.liveData(f)) {
                XCTAssertEqual(Place.walkSeconds(meters: Double(dist)), Double(dur), accuracy: 1.0, "\(f) \(dist) m")
                n += 1
            }
        }
        XCTAssertGreaterThanOrEqual(n, 25)
    }

    /// SUGGEST_SPEC §6.6 verified pairs (offline record vs live row).
    func testDedupeRules() throws {
        let index = PlaceFixtures.index
        func live(_ scenario: String, _ name: String) throws -> Place {
            try XCTUnwrap(PlaceFixtures.live(scenario).first { $0.name == name || $0.aliases.contains(name) }, "\(scenario): \(name)")
        }
        func offline(_ name: String, _ kind: PlaceKind? = nil) throws -> Place {
            try XCTUnwrap(PlaceFixtures.record(named: name, kind: kind), name)
        }
        let same: [(Place, Place, String)] = [
            (try offline("Innsbruck Hauptbahnhof"), try live("lm_all_inns", "Innsbruck Hbf"), "D1 EVA 8100108"),
            (try offline("Wien Hauptbahnhof"), try live("lm_all_wien_hbf", "Wien Hbf (U)"), "D2 meta 116 m"),
            (try offline("Lech am Arlberg Dorfhus"), try live("lm_all_lech_postamt", "Lech Dorfhus"), "D3′ 10 m"),
            (try offline("Innsbruck Maria-Theresien-Straße"), try live("lm_all_maria_theresien_strasse_1_innsbruck",
                                                                       "Innsbruck Maria-Theresien-Straße"), "D2 7 m"),
            (try offline("Innsbruck", .town), try live("lm_all_inns", "Innsbruck"), "D4 towns"),
        ]
        for (o, l, rule) in same { XCTAssertTrue(index.isSamePlace(o, l), "\(o.name) ≙ \(l.name) (\(rule))") }
        let different: [(Place, Place, String)] = [
            (try offline("Flughafen Wien Bahnhof"), try live("lm_all_flughafen", "Flughafen Wien"), "D0 stop vs town"),
            (try offline("Innsbruck Westbahnhof"), try live("lm_all_inns", "Innsbruck Hbf"), "1 km apart"),
        ]
        for (o, l, rule) in different { XCTAssertFalse(index.isSamePlace(o, l), "\(o.name) ≠ \(l.name) (\(rule))") }
        // addresses/POIs never merge with stops
        let addr = try live("lm_all_maria_theresien_strasse_1_innsbruck", "6020 Innsbruck, Maria-Theresien-Straße 1")
        XCTAssertFalse(index.isSamePlace(try offline("Innsbruck Maria-Theresien-Straße"), addr))
    }

    func testMergeKeepsOfflineIdentityAndGainsLiveIds() throws {
        let index = PlaceFixtures.index
        let offline = index.search("inns", context: .planner, limit: 8)
        let live = PlaceFixtures.live("lm_all_inns")
        let merged = index.merged(offline: offline, live: live, query: "inns", context: .planner, limit: 8)
        let hbf = try XCTUnwrap(merged.first)
        XCTAssertEqual(hbf.id, "at:47:1187")                // stable offline id
        XCTAssertEqual(hbf.source, .both)
        XCTAssertEqual(hbf.extId, "8100108")
        XCTAssertNotNil(hbf.lid)
        XCTAssertEqual(hbf.liveRank, 1)
        XCTAssertGreaterThan(hbf.score, offline.first!.score)  // live rank bonus
        // merge never mutates the index: a later offline search returns the plain record again
        let again = index.search("inns", context: .planner, limit: 8)
        XCTAssertEqual(again.first?.source, .offline)
        XCTAssertNil(again.first?.lid)
        XCTAssertEqual(again.first?.score, offline.first?.score)
        // no duplicate places in the merged list
        let rules = SimilarityRules(municipalities: index.table.municipalities)
        let keys = merged.map(index.dedupeKey)
        for i in keys.indices { for j in keys.indices where j > i { XCTAssertFalse(rules.samePlace(keys[i], keys[j])) } }
    }

    func testTwoArgumentMergeAndCaps() throws {
        let index = PlaceFixtures.index
        let q = "Hofburg"
        let offline = index.search(q, context: .planner, limit: 8)
        let ranked = index.rankLive(PlaceFixtures.live("lm_all_hofburg"), query: q)
        XCTAssertTrue(ranked.allSatisfy { $0.score != 0 && $0.source == .live })
        // POIs keep Scotty's order (scores non-increasing in live order)
        let pois = ranked.filter { $0.kind == .poi }.map(\.score)
        XCTAssertEqual(pois, pois.sorted(by: >))
        let a = index.merged(offline: offline, live: ranked)
        let b = index.merged(offline: offline, live: PlaceFixtures.live("lm_all_hofburg"), query: q, limit: 50)
        XCTAssertEqual(a.prefix(5).map(PlaceFixtures.fmt), b.prefix(5).map(PlaceFixtures.fmt))
        // diversity caps: at most 3 POIs before the first non-POI overflow when the best row is not a POI …
        let stephans = index.merged(offline: index.search("Stephansplatz", limit: 8), live: PlaceFixtures.live("lm_all_stephansplatz"),
                                    query: "Stephansplatz", limit: 20)
        XCTAssertEqual(stephans.first?.name, "Wien Stephansplatz")
        let firstPOIs = stephans.prefix(4).filter { $0.kind == .poi }.count
        XCTAssertLessThanOrEqual(firstPOIs, 3)
        // … and „Fahrt erfassen“ never shows towns, even from live rows
        let trip = index.merged(offline: index.search("wien", context: .tripLog, limit: 8), live: PlaceFixtures.live("lm_all_wien"),
                                query: "wien", context: .tripLog)
        XCTAssertFalse(trip.contains { $0.kind == .town })
    }
}

/// Robustness: odd inputs never crash and never return garbage.
final class PlaceRobustnessTests: XCTestCase {
    func testOddInputs() {
        let index = PlaceFixtures.index
        let inputs = ["", " ", "...", "(", ")", "[[", "-/-", "ß", "ẞẞẞ", "😀", "🇦🇹 Wien", String(repeating: "a", count: 500),
                      String(repeating: "wien ", count: 40), "1", "6020", "a.d.", "i.", "Wr.", "\u{0301}", "İstanbul",
                      "Москва", "北京", "St.", "st. ", "Hall i.T", "\n\t", "%", "'", "\"", "\\", "\u{0}"]
        for q in inputs {
            for ctx in [PlaceSearchContext.planner, .tripLog, PlaceSearchContext(near: GeoPoint(latitude: 47.26, longitude: 11.39))] {
                let rows = index.search(q, context: ctx, limit: 20)
                XCTAssertLessThanOrEqual(rows.count, 20)
                _ = index.merged(offline: rows, live: PlaceFixtures.live("lm_all_inns"), query: q, context: ctx)
            }
        }
        XCTAssertTrue(index.search("wien", limit: 0).isEmpty)
        XCTAssertTrue(index.search("wien", limit: -3).isEmpty)
        XCTAssertTrue(index.popularStations(limit: -1).isEmpty)
        XCTAssertTrue(index.merged(offline: index.search("wien"), live: [], query: "wien", limit: -1).isEmpty)
        XCTAssertTrue(index.nearest(to: GeoPoint(latitude: .nan, longitude: 11), limit: 3).isEmpty)
        XCTAssertTrue(index.nearest(to: GeoPoint(latitude: 47.26, longitude: 11.39), limit: 0).isEmpty)
        XCTAssertFalse(index.nearest(to: GeoPoint(latitude: 47.26, longitude: 11.39), limit: 2, maxMeters: .infinity).isEmpty)
        XCTAssertTrue(index.nearest(to: GeoPoint(latitude: 47.26, longitude: 11.39), limit: 2, maxMeters: -5).isEmpty)
        XCTAssertNil(index.place(id: ""))
        XCTAssertNil(index.station(id: "nope"))
        // each query token needs its own name token: 8 × "innsbruck" matches nothing (and must not hang)
        XCTAssertTrue(index.search(String(repeating: "innsbruck ", count: 20), context: .tripLog, limit: 3).isEmpty)
    }

    func testCorruptedDataDoesNotCrash() throws {
        let good = try Data(contentsOf: PlaceFixtures.placesURL)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            var d = good
            let cut = Int.random(in: 64..<d.count, using: &rng)
            if Bool.random(using: &rng) {
                d = d.prefix(cut)
            } else {
                for _ in 0..<64 { d[Int.random(in: 64..<d.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng) }
            }
            _ = try? PlaceDataset(places: d, localities: nil)
        }
    }
}
