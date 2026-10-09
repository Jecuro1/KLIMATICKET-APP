import XCTest
@testable import KlimaCore

/// LocMatch / LocGeoPos goldens and the nonsense filter (SPEC §A3.3, §D2 WP-A 7).
final class HafasLocationTests: XCTestCase {
    static let single = ["locmatch_innsbruck", "locmatch_st_anton", "locmatch_wien_westbahnhof"]

    func testLocMatchGoldens() throws {
        for scenario in Self.single + ["locmatch_batch_mixed", "locmatch_batch_2_nonfuzzy_nomatch"] {
            let g = try Fixture.golden("hafas/\(scenario)")
            let locs = try HafasCodec.locations(from: Fixture.data("hafas/\(scenario).response"))
            XCTAssertEqual(locs.count, g["locationCount"] as? Int, scenario)
            for (l, gl) in zip(locs, try XCTUnwrap(g["locations"] as? [[String: Any]])) {
                XCTAssertEqual(l.kind.rawValue, gl["type"] as? String, scenario)
                XCTAssertEqual(l.extId, gl["id"] as? String, scenario)
                XCTAssertEqual(l.name, gl["name"] as? String, scenario)
                XCTAssertEqual(l.isMeta, (gl["meta"] as? Bool) ?? false, scenario)
                XCTAssertFalse(l.lid.isEmpty)
            }
        }
    }

    func testInnsbruckDetails() throws {
        let locs = try HafasCodec.locations(from: Fixture.data("hafas/locmatch_innsbruck.response"), query: "Innsbruck")
        let hbf = try XCTUnwrap(locs.first { $0.extId == "8100108" })
        XCTAssertEqual(hbf.name, "Innsbruck Hbf")
        XCTAssertFalse(hbf.isMeta)
        XCTAssertEqual(hbf.countryCode, "at")
        XCTAssertEqual(hbf.uicCode, "8101187")
        XCTAssertEqual(hbf.minTransferSeconds, 300)
        XCTAssertTrue(hbf.products.isSuperset(of: .rail), "pCls 4735 = rail + tram + bus + SEV")
        XCTAssertEqual(try XCTUnwrap(hbf.coordinate?.latitude), 47.263043, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(hbf.coordinate?.longitude), 11.401019, accuracy: 1e-6)
        XCTAssertTrue(locs.first { $0.extId == "1170101" }?.isMeta == true)
        // The filter keeps every golden Innsbruck result.
        let golden = try XCTUnwrap(try Fixture.golden("hafas/locmatch_innsbruck")["locations"] as? [[String: Any]])
        for gl in golden { XCTAssertTrue(locs.contains { $0.extId == gl["id"] as? String }, "\(gl)") }
    }

    func testBatchOfElevenServiceResults() throws {
        let data = try Fixture.data("hafas/locmatch_batch_mixed.response")
        let g = try XCTUnwrap(try Fixture.golden("hafas/locmatch_batch_mixed")["batch"] as? [[[String: Any]]])
        XCTAssertEqual(g.count, 11)
        for (i, expected) in g.enumerated() {
            let locs = try HafasCodec.locations(from: data, serviceIndex: i)
            for (l, gl) in zip(locs, expected) {
                XCTAssertEqual(l.extId, gl["id"] as? String, "batch[\(i)]")
                XCTAssertEqual(l.name, gl["name"] as? String, "batch[\(i)]")
                XCTAssertEqual(l.kind.rawValue, gl["type"] as? String, "batch[\(i)]")
            }
        }
        XCTAssertThrowsError(try HafasCodec.locations(from: data, serviceIndex: 11))
        // Address and POI kinds.
        XCTAssertEqual(try HafasCodec.locations(from: data, serviceIndex: 6).first?.kind, .address)
        XCTAssertEqual(try HafasCodec.locations(from: data, serviceIndex: 7).first?.kind, .poi)
    }

    func testNonsenseFilter() throws {
        let data = try Fixture.data("hafas/locmatch_batch_2_nonfuzzy_nomatch.response")
        let raw = try HafasCodec.locations(from: data, serviceIndex: 3)
        XCTAssertFalse(raw.isEmpty, "LocMatch never fails on nonsense: popular stations come back")
        XCTAssertTrue(try HafasCodec.locations(from: data, serviceIndex: 3, query: "xqzvvhjkq").isEmpty)
        // Real queries keep their results.
        XCTAssertEqual(try HafasCodec.locations(from: data, serviceIndex: 0, query: "Ischgl").first?.name, "Ischgl")
        XCTAssertEqual(try HafasCodec.locations(from: data, serviceIndex: 4, query: "Landeck-Zams Bahnhof").first?.name, "Landeck-Zams Bahnhof")
        let mixed = try Fixture.data("hafas/locmatch_batch_mixed.response")
        XCTAssertTrue(try HafasCodec.locations(from: mixed, serviceIndex: 10, query: "xqzvvhjkq?").isEmpty)
        // Typos within Levenshtein 2 survive ("Insbruck" → Innsbruck).
        XCTAssertTrue(HafasCodec.plausibleMatch(name: "Innsbruck Hbf", query: "Insbruck"))
        XCTAssertTrue(HafasCodec.plausibleMatch(name: "St.Pölten Hbf", query: "St. Poelten"))
        XCTAssertFalse(HafasCodec.plausibleMatch(name: "Wien Hbf (U)", query: "xqzvvhjkq"))
        XCTAssertTrue(HafasCodec.plausibleMatch(name: "Wien Hbf (U)", query: "W"), "no token ≥ 3 characters → no filtering")
    }

    func testLocGeoPosSortedByDistance() throws {
        let g = try Fixture.golden("hafas/locgeopos_nearby_innsbruck_hbf")
        let locs = try HafasCodec.locations(from: Fixture.data("hafas/locgeopos_nearby_innsbruck_hbf.response"))
        XCTAssertEqual(locs.count, g["locationCount"] as? Int)
        let d = locs.compactMap(\.distanceMeters)
        XCTAssertEqual(d.count, locs.count)
        XCTAssertEqual(d, d.sorted())
        for (l, gl) in zip(locs, try XCTUnwrap(g["locations"] as? [[String: Any]])) {
            XCTAssertEqual(l.extId, gl["id"] as? String)
            XCTAssertEqual(l.name, gl["name"] as? String)
            XCTAssertEqual(l.distanceMeters, gl["distance"] as? Int)
        }
    }

    func testServerInfo() throws {
        let info = try HafasCodec.serverInfo(from: Fixture.data("hafas/serverinfo.response"))
        let g = try XCTUnwrap(try Fixture.golden("hafas/serverinfo")["serverInfo"] as? [String: Any])
        XCTAssertEqual(info.hciVersion, g["hciVersion"] as? String)
        XCTAssertEqual(info.serverVersion, g["serverVersion"] as? String)
        XCTAssertEqual(info.timetableFrom, g["fpB"] as? String)
        XCTAssertEqual(info.timetableTo, g["fpE"] as? String)
        XCTAssertEqual(info.serverTime, ISO.date("2026-10-09T11:17:40+02:00"))
    }
}

/// HimSearch goldens + HTML → text (SPEC §A3.4 Remarks, §D2 WP-A 8).
final class HafasRemarksTests: XCTestCase {
    func testHimSearchGolden() throws {
        let g = try Fixture.golden("hafas/himsearch_disruptions_rail")
        let remarks = try HafasCodec.remarks(from: Fixture.data("hafas/himsearch_disruptions_rail.response"))
        XCTAssertEqual(remarks.count, g["messageCount"] as? Int)
        XCTAssertEqual(remarks.count, 15)
        for (r, gm) in zip(remarks, try XCTUnwrap(g["messages"] as? [[String: Any]])) {
            XCTAssertEqual(r.kind, .disruption)
            XCTAssertEqual(r.id, gm["id"] as? String)
            XCTAssertEqual(r.title, gm["head"] as? String)
            XCTAssertEqual(r.priority, gm["prio"] as? Int)
            XCTAssertEqual(r.validFrom, ISO.date(gm["validFrom"] as? String))
            XCTAssertEqual(r.validUntil, ISO.date(gm["validUntil"] as? String))
        }
        for r in remarks {
            XCTAssertFalse(r.text.contains("<"), r.text)
            XCTAssertFalse(r.text.contains("&"), r.text)
            XCTAssertNotNil(r.modifiedAt)
        }
        XCTAssertTrue(remarks[0].text.contains("\n\nMobilitätseingeschränkten"), "<br><br> → blank line")
    }

    func testJourneyRemarksResolveRemAndHim() throws {
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_innsbruck_lech_bus.response"))
        let ride = try XCTUnwrap(page.journeys.first?.rideLegs.first)
        XCTAssertFalse(ride.remarks.isEmpty)
        XCTAssertTrue(ride.remarks.allSatisfy { !$0.text.isEmpty && !$0.text.contains("<") })
        let keys = ride.remarks.map { "\($0.kind)|\($0.id ?? $0.text)" }
        XCTAssertEqual(keys.count, Set(keys).count, "deduplicated")
        let trip = try HafasCodec.trip(from: Fixture.data("hafas/journeydetails_rjx133_koralm_polyline.response"))
        XCTAssertTrue(trip.remarks.contains { $0.kind == .attribute })
    }

    func testHTMLText() {
        XCTAssertEqual(HTMLText.plain("a<br>b<br/>c<BR />d"), "a\nb\nc\nd")
        XCTAssertEqual(HTMLText.plain("<b>Fahrradmitnahme</b> <s>reservierungspflichtig</s>"), "Fahrradmitnahme reservierungspflichtig")
        XCTAssertEqual(HTMLText.plain("&Ouml;BB &amp; VVT &lt;3 &gt; &quot;x&quot;&nbsp;&szlig;&auml;&uuml;&Auml;&Uuml;&ouml;"), "ÖBB & VVT <3 > \"x\" ßäüÄÜö")
        XCTAssertEqual(HTMLText.plain("&#62; &#x3E; &#8222;"), "> > „")
        XCTAssertEqual(HTMLText.plain("a<br><br><br><br>b"), "a\n\nb")
        XCTAssertEqual(HTMLText.plain("  \n x \n "), "x")
        XCTAssertEqual(HTMLText.plain("Tom & Jerry; a < b"), "Tom & Jerry; a < b", "unknown entities and stray brackets stay")
        XCTAssertEqual(HTMLText.plain(nil), "")
    }

    func testDedupeKeepsFirst() {
        let a = Remark(kind: .attribute, code: "WV", text: "WLAN"), b = Remark(kind: .attribute, code: "WV", text: "WLAN")
        let h1 = Remark(kind: .disruption, id: "HIM_1", title: "x", text: "1"), h2 = Remark(kind: .disruption, id: "HIM_1", title: "y", text: "2")
        XCTAssertEqual(HafasCodec.dedupe([a, b, h1, h2]), [a, h1])
    }
}
