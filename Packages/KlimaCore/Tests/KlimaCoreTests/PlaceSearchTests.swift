import Foundation
import XCTest
@testable import KlimaCore

/// Normalisation (umlauts, ß, abbreviations, synonyms) – golden from scripts/places_reference.py.
final class PlaceNormalizerTests: XCTestCase {
    func testFoldGolden() throws {
        let cases = try XCTUnwrap(PlaceFixtures.json("fold_golden.json") as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 55)
        for c in cases {
            let input = c["input"] as! String
            XCTAssertEqual(PlaceNormalizer.fold(input), c["fold"] as? String, "fold \(input)")
            XCTAssertEqual(PlaceNormalizer.key(input), c["key"] as? String, "key \(input)")
            let (toks, trailing) = PlaceNormalizer.tokenize(input, isName: true)
            XCTAssertEqual(trailing, c["trailing"] as? Bool, "trailing \(input)")
            let expected = c["tokens"] as! [[String: Any]]
            XCTAssertEqual(toks.map(\.raw), expected.map { $0["raw"] as! String }, "tokens \(input)")
            for (t, e) in zip(toks, expected) {
                XCTAssertEqual(t.isQualifier, e["qualifier"] as? Bool, "\(input)/\(t.raw) qualifier")
                XCTAssertEqual(t.isStop, e["stop"] as? Bool, "\(input)/\(t.raw) stop")
                XCTAssertEqual(t.isGeneric, e["generic"] as? Bool, "\(input)/\(t.raw) generic")
                XCTAssertEqual(t.isNumeric, e["numeric"] as? Bool, "\(input)/\(t.raw) numeric")
                XCTAssertEqual(t.isEssential, e["essential"] as? Bool, "\(input)/\(t.raw) essential")
                let forms = t.forms.map { "\($0.0)=\($0.1)" }.sorted()
                let eforms = (e["forms"] as! [[Any]]).map { "\($0[0] as! String)=\(($0[1] as! NSNumber).doubleValue)" }.sorted()
                XCTAssertEqual(forms, eforms, "\(input)/\(t.raw) forms")
            }
        }
    }

    func testUmlautsAndAbbreviations() {
        XCTAssertEqual(PlaceNormalizer.fold("Sankt Pölten"), "sankt polten")
        XCTAssertEqual(PlaceNormalizer.fold("St. Poelten"), "st. polten")
        XCTAssertEqual(PlaceNormalizer.fold("STRASSE Straße ẞ"), "strasse strasse ss")
        XCTAssertEqual(PlaceNormalizer.fold("Wörgl WÖRGL Woergl Worgl"), "worgl worgl worgl worgl")
        XCTAssertEqual(PlaceNormalizer.key("Innsbruck Hauptbahnhof"), PlaceNormalizer.key("innsbruck hbf"))
        XCTAssertEqual(PlaceNormalizer.key("Bregenz Bahnhof"), PlaceNormalizer.key("Bregenz Bf"))
        XCTAssertEqual(PlaceNormalizer.key("Sankt Anton"), PlaceNormalizer.key("St.Anton"))
        XCTAssertEqual(PlaceNormalizer.key("Hall i.T."), "hall in tirol")
        XCTAssertEqual(PlaceNormalizer.key("Bruck a.d.Mur"), "bruck an der mur")
        XCTAssertEqual(PlaceNormalizer.key("Wr.Neustadt"), "wiener neustadt")
        XCTAssertEqual(PlaceNormalizer.key("Hof b.Salzburg"), "hof bei salzburg")
        XCTAssertEqual(PlaceNormalizer.key("Mariahilfer Str."), PlaceNormalizer.key("Mariahilfer Straße"))
    }

    func testDisplayNames() {
        XCTAssertEqual(PlaceNames.display("St.Anton am Arlberg Bahnhof"), "St. Anton am Arlberg Bahnhof")
        XCTAssertEqual(PlaceNames.display("Graz St.Johann"), "Graz St. Johann")
        XCTAssertEqual(PlaceNames.display("Wien  Westbahnhof"), "Wien Westbahnhof")
        XCTAssertEqual(PlaceNames.display("Wien Westbahnstraße"), "Wien Westbahnstraße")
        XCTAssertEqual(PlaceNames.strippingPOICounter("Hofburg, Rennweg 1, 6020 Innsbruck (2)"), "Hofburg, Rennweg 1, 6020 Innsbruck")
    }
}

/// Ranking against the shipped dataset: every expectation was produced by scripts/places_reference.py on the same
/// places.bin/localities.bin (Swift == reference). Regenerate with the reference after a dataset update.
final class PlaceGoldenTests: XCTestCase {
    func testGoldenDatasetMatchesShippedResources() throws {
        let sha = try XCTUnwrap(PlaceFixtures.golden["dataset_sha256_16"] as? [String: String])
        XCTAssertEqual(Set(sha.keys), ["places.bin", "localities.bin", "stops_osm.bin"],
                       "goldens are generated with the OSM layer, like the app loads the data (--osm)")
        XCTAssertEqual(PlaceFixtures.golden["records"] as? Int, PlaceFixtures.index.count,
                       "goldens were generated for another dataset – rerun scripts/places_reference.py golden")
    }

    func testGoldenCases() throws {
        let index = PlaceFixtures.index
        let cases = try XCTUnwrap(PlaceFixtures.golden["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 100)
        var checked = 0
        for c in cases {
            let input = c["input"] as! String
            let ctx = PlaceFixtures.context(c)
            let label = "\(input) [\(c["mode"] ?? "")/\(c["context"] ?? "")]"
            let raw = index.searchRaw(input, context: index.normalized(ctx), limit: 12)
            if let expected = c["offline_top5"] as? [String] {
                XCTAssertEqual(raw.prefix(5).map(PlaceFixtures.fmt), expected, "offline \(label)")
                checked += 1
            }
            if let expected = c["merged_top5"] as? [String] {
                let live = (c["fixture"] as? String).map(PlaceFixtures.live) ?? []
                if let n = c["live_rows"] as? Int { XCTAssertEqual(live.count, n, "live rows \(label)") }
                if let lt = c["live_top5"] as? [String] { XCTAssertEqual(live.prefix(5).map(PlaceFixtures.fmt), lt, "live \(label)") }
                let merged = index.merged(offline: raw, live: live, query: input, context: ctx, limit: 8)
                XCTAssertEqual(merged.prefix(5).map(PlaceFixtures.fmt), expected, "merged \(label)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 150)
    }

    /// Every prefix while typing the golden inputs (public `search`, both modes).
    func testTypingPrefixes() throws {
        let index = PlaceFixtures.index
        let prefixes = try XCTUnwrap(PlaceFixtures.golden["prefixes"] as? [[String: Any]])
        XCTAssertGreaterThan(prefixes.count, 300)
        var bad = 0
        for p in prefixes {
            let input = p["input"] as! String
            let ctx = PlaceSearchContext(mode: (p["mode"] as? String) == "tripLog" ? .tripLog : .planner)
            let got = index.search(input, context: ctx, limit: 20).prefix(5).map(PlaceFixtures.fmt)
            if got != (p["top5"] as! [String]) {
                bad += 1
                XCTFail("prefix '\(input)' [\(ctx.mode)]: \(got) != \(p["top5"]!)")
            }
            if bad > 10 { break }
        }
    }

    func testNearest() throws {
        let index = PlaceFixtures.index
        for n in try XCTUnwrap(PlaceFixtures.golden["nearest"] as? [[String: Any]]) {
            let p = GeoPoint(latitude: (n["lat"] as! NSNumber).doubleValue, longitude: (n["lon"] as! NSNumber).doubleValue)
            let got = index.nearest(to: p, limit: 5, maxMeters: 1_500)
            XCTAssertEqual(got.map(\.place.name), n["names"] as! [String], "\(n["label"]!)")
            for (g, m) in zip(got, n["meters"] as! [NSNumber]) {
                XCTAssertEqual(g.distanceMeters, m.doubleValue, accuracy: 0.11)
            }
        }
        // nearest is exact: sorted, within the radius, and a product filter only returns matching stops
        let rail = index.nearest(to: GeoPoint(latitude: 47.2669, longitude: 11.3939), limit: 3, maxMeters: 5_000,
                                 products: .longDistance)
        XCTAssertEqual(rail.first?.place.name, "Innsbruck Hauptbahnhof")
        XCTAssertTrue(rail.allSatisfy { !$0.place.products.intersection(.longDistance).isEmpty })
        XCTAssertEqual(rail.map(\.distanceMeters), rail.map(\.distanceMeters).sorted())
        XCTAssertTrue(index.nearest(to: GeoPoint(latitude: 0, longitude: 0), limit: 3).isEmpty)
    }

    func testResolveAddressToStop() throws {
        let index = PlaceFixtures.index
        for r in try XCTUnwrap(PlaceFixtures.golden["resolve"] as? [[String: Any]]) {
            let p = GeoPoint(latitude: (r["lat"] as! NSNumber).doubleValue, longitude: (r["lon"] as! NSNumber).doubleValue)
            XCTAssertEqual(index.resolveStops(near: p).map(\.place.name), r["offline"] as! [String], "\(r["label"]!)")
            let live = LocMatchDecoder.nearby(fromResponse: PlaceFixtures.liveData(r["fixture"] as! String))
            XCTAssertFalse(live.isEmpty)
            XCTAssertEqual(index.resolveStops(near: p, live: live).map(\.place.name), r["with_live"] as! [String], "\(r["label"]!) live")
        }
    }

    /// The dataset researcher's HAFAS-style inputs return the intended stop first.
    func testScottyStyleInputs() {
        let index = PlaceFixtures.index
        let expect: [(String, String)] = [
            ("Wien Hbf", "Wien Hauptbahnhof"), ("Ibk", "Innsbruck Hauptbahnhof"), ("St. Anton", "St. Anton am Arlberg Bahnhof"),
            ("St.Anton a.A.", "St. Anton am Arlberg Bahnhof"), ("Hall i.T.", "Hall in Tirol Bahnhof"),
            ("Wr. Neustadt", "Wiener Neustadt Hauptbahnhof"), ("Lauterach in Vlbg Hasenfeldgasse", "Lauterach (Vorarlberg) Hasenfeldgasse"),
            ("Steinbrunn im Bgld Bethausweg", "Steinbrunn Bethausweg"), ("Nußdorf b.Lienz Volksschule", "Nußdorf (Nußdorf-Debant) Volksschule"),
            ("Schwechat Flughafen", "Flughafen Wien Bahnhof"), ("wien w", "Wien Westbahnhof"), ("insbruck", "Innsbruck Hauptbahnhof"),
            ("Westbahnhof", "Wien Westbahnhof"), ("VIE", "Flughafen Wien Bahnhof"),
        ]
        for (q, name) in expect {
            XCTAssertEqual(index.search(q, context: .tripLog, limit: 5).first?.name, name, q)
        }
        // towns only in the planner, never in „Fahrt erfassen“
        XCTAssertEqual(index.search("wien", context: .planner, limit: 3).first?.kind, .town)
        XCTAssertFalse(index.search("wien", context: .tripLog, limit: 20).contains { $0.kind == .town })
        XCTAssertTrue(index.search("", context: .planner).isEmpty)
        XCTAssertTrue(index.search("xqzvvhjkq").isEmpty)
        XCTAssertEqual(index.popularStations().first?.name, "Wien Hauptbahnhof")
        XCTAssertEqual(index.popularStations().count, 10)
    }

    func testEveryOperatorAndModeIsSearchable() {
        let index = PlaceFixtures.index
        func first(_ q: String, _ products: PlaceProducts) -> Place? {
            index.search(q, context: .tripLog, limit: 10).first { !$0.products.intersection(products).isEmpty }
        }
        XCTAssertNotNil(first("Wien Stephansplatz", .subway))
        XCTAssertNotNil(first("Graz Jakominiplatz", .tram))
        XCTAssertNotNil(first("Innsbruck Maria-Theresien-Straße", .bus))
        XCTAssertNotNil(first("Lech Dorfhus", .bus))
        XCTAssertNotNil(first("Schöckl Seilbahn Bergstation", .onDemandOrCable))
        XCTAssertNotNil(first("St. Wolfgang Markt Schiffstation", .ship))
        XCTAssertNotNil(first("Altmünster Traunsee Schiffstation", .ship))
    }
}
