import XCTest
@testable import KlimaCore

/// The `/gate` parser rejects unknown keys and enum values with PARSE, so every encoded request must have exactly the
/// key set of the live-verified fixture requests (SPEC §A3.3, §D2 WP-A 3). Values are equal except volatile ones.
final class HafasEncoderTests: XCTestCase {
    static let volatile: Set<String> = ["outDate", "outTime", "date", "time", "dateB", "timeB", "dateE", "timeE", "ctx", "ctxScr", "jid"]

    static func vienna(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        Calendar.vienna.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    static func encode<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    static func fixtureRequest(_ scenario: String, index: Int = 0) throws -> [String: Any] {
        let obj = try XCTUnwrap(try Fixture.json("hafas/\(scenario).request") as? [String: Any])
        let body = try XCTUnwrap(obj["body"] as? [String: Any])
        let list = try XCTUnwrap(body["svcReqL"] as? [[String: Any]])
        return list[index]
    }

    static func fixtureEnvelope(_ scenario: String) throws -> [String: Any] {
        let obj = try XCTUnwrap(try Fixture.json("hafas/\(scenario).request") as? [String: Any])
        var body = try XCTUnwrap(obj["body"] as? [String: Any])
        body["svcReqL"] = nil
        return body
    }

    static func fragment(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: [v])).map { String(decoding: $0, as: UTF8.self) } ?? "\(v)"
    }

    /// Recursive comparison: identical key sets at every level; scalars equal unless the key is volatile or ignored.
    static func assertSameShape(_ ours: Any, _ fixture: Any, path: String = "$", ignoreValues: Set<String> = [],
                         file: StaticString = #filePath, line: UInt = #line) {
        switch (ours, fixture) {
        case let (a as [String: Any], b as [String: Any]):
            XCTAssertEqual(Set(a.keys), Set(b.keys), "key set at \(path)", file: file, line: line)
            for (k, v) in a {
                guard let w = b[k] else { continue }
                if Self.volatile.contains(k) || ignoreValues.contains(k) {
                    // Same JSON type is still required.
                    XCTAssertEqual(v is String, w is String, "type at \(path).\(k)", file: file, line: line)
                    if v is [String: Any] || v is [Any] { Self.assertSameShape(v, w, path: "\(path).\(k)", ignoreValues: ignoreValues, file: file, line: line) }
                    continue
                }
                Self.assertSameShape(v, w, path: "\(path).\(k)", ignoreValues: ignoreValues, file: file, line: line)
            }
        case let (a as [Any], b as [Any]):
            XCTAssertEqual(a.count, b.count, "array length at \(path)", file: file, line: line)
            for (i, (x, y)) in zip(a, b).enumerated() {
                Self.assertSameShape(x, y, path: "\(path)[\(i)]", ignoreValues: ignoreValues, file: file, line: line)
            }
        default:
            XCTAssertEqual(Self.fragment(ours), Self.fragment(fixture), "value at \(path)", file: file, line: line)
        }
    }

    func assertNoNull<T: Encodable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertNil(json.range(of: #":\s*null"#, options: .regularExpression), "null in \(json.prefix(300))", file: file, line: line)
    }

    // MARK: - Envelope

    func testEnvelopeGateOmitsClientVersion() throws {
        let env = HafasEnvelope(profile: LiveConfig.default.hafas, svcReqL: [HafasRequests.serverInfo()])
        var ours = try XCTUnwrap(try Self.encode(env) as? [String: Any])
        let svc = ours.removeValue(forKey: "svcReqL")
        Self.assertSameShape(ours, try Self.fixtureEnvelope("serverinfo"))
        XCTAssertNil((ours["client"] as? [String: Any])?["v"])
        Self.assertSameShape((svc as? [Any])?.first as Any, try Self.fixtureRequest("serverinfo"))
        try assertNoNull(env)
    }

    func testEnvelopeLegacyMgateHasStringVersion() throws {
        let profile = try XCTUnwrap(LiveConfig.default.hafasFallback)
        var ours = try XCTUnwrap(try Self.encode(HafasEnvelope(profile: profile, svcReqL: [HafasRequests.serverInfo()])) as? [String: Any])
        ours["svcReqL"] = nil
        Self.assertSameShape(ours, try Self.fixtureEnvelope("legacy_mgate141_tripsearch_st_anton_innsbruck"))
        XCTAssertTrue((ours["client"] as? [String: Any])?["v"] is String)
        XCTAssertNil(ours["ext"])
    }

    func testEnvelopeVAOHasIntVersion() throws {
        let obj = try XCTUnwrap(try Fixture.json("vao/vao_tripsearch_tariff_stanton-ibk") as? [String: Any])
        var fixture = try XCTUnwrap(obj["request"] as? [String: Any])
        fixture["svcReqL"] = nil
        var ours = try XCTUnwrap(try Self.encode(HafasEnvelope(profile: LiveConfig.default.vao, svcReqL: [HafasRequests.serverInfo()])) as? [String: Any])
        ours["svcReqL"] = nil
        Self.assertSameShape(ours, fixture)
        let v = (ours["client"] as? [String: Any])?["v"]
        XCTAssertEqual(Self.fragment(v as Any), "[10022]")
    }

    // MARK: - Location requests

    func testLocMatch() throws {
        let svc = HafasRequests.locMatch("Innsbruck", types: .all, maxResults: 8)
        Self.assertSameShape(try Self.encode(svc), try Self.fixtureRequest("locmatch_innsbruck"))
        try assertNoNull(svc)
        // The fuzzy "?" is appended exactly once.
        let again = try XCTUnwrap(try Self.encode(HafasRequests.locMatch("Innsbruck?", types: .stations, maxResults: 3)) as? [String: Any])
        let loc = ((again["req"] as? [String: Any])?["input"] as? [String: Any])?["loc"] as? [String: Any]
        XCTAssertEqual(loc?["name"] as? String, "Innsbruck?")
        XCTAssertEqual(loc?["type"] as? String, "S")
    }

    func testLocGeoPosRoundsCoordinates() throws {
        let svc = HafasRequests.locGeoPos(GeoPoint(latitude: 47.26304, longitude: 11.40102), maxDistanceMeters: 400, maxResults: 10, products: .all)
        Self.assertSameShape(try Self.encode(svc), try Self.fixtureRequest("locgeopos_nearby_innsbruck_hbf"), ignoreValues: ["x", "y"])
        let ring = ((try Self.encode(svc) as? [String: Any])?["req"] as? [String: Any])?["ring"] as? [String: Any]
        let c = ring?["cCrd"] as? [String: Any]
        XCTAssertEqual(c?["x"] as? Int, 11_401_000)
        XCTAssertEqual(c?["y"] as? Int, 47_263_000)
        let r2 = HafasRequests.locGeoPos(GeoPoint(latitude: 48.18519, longitude: 16.37641), maxDistanceMeters: 1, maxResults: 1, products: .rail)
        let c2 = ((((try Self.encode(r2) as? [String: Any])?["req"] as? [String: Any])?["ring"] as? [String: Any])?["cCrd"] as? [String: Any])
        XCTAssertEqual(c2?["x"] as? Int, 16_376_000)
        XCTAssertEqual(c2?["y"] as? Int, 48_185_000)
    }

    // MARK: - TripSearch

    static let stAnton = Location(lid: "A=1@L=1170621@", name: "St. Anton am Arlberg")
    static let ibk = Location.station(extId: "8100108", name: "Innsbruck Hbf")
    static let wienHbf = Location.station(extId: "1290401", name: "Wien Hbf (U)")

    func testTripSearchKeySet() throws {
        let q = JourneyQuery(origin: Self.stAnton, destination: Self.ibk, date: Self.vienna(2026, 10, 9, 11, 30), results: 4,
                             includeStopovers: true, includePolyline: true)
        let svc = HafasRequests.tripSearch(q)
        let fixture = try Self.fixtureRequest("tripsearch_st_anton_innsbruck")
        Self.assertSameShape(try Self.encode(svc), fixture, ignoreValues: ["getTariff"])
        let req = try XCTUnwrap((try Self.encode(svc) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertEqual(req["getTariff"] as? Bool, true, "getTariff:true [DECISION]")
        XCTAssertEqual(req["outDate"] as? String, "20261009")
        XCTAssertEqual(req["outTime"] as? String, "113000")
        XCTAssertNil(req["viaLocL"], "no viaLocL key without via")
        XCTAssertTrue(((req["jnyFltrL"] as? [[String: Any]])?.first?["value"]) is String, "PROD value is a String")
        try assertNoNull(svc)
        // Legacy profile: same request shape.
        let legacy = JourneyQuery(origin: Location.station(extId: "8100064", name: "St. Anton"), destination: Self.ibk,
                                  date: Self.vienna(2026, 10, 9, 11, 27, 26), results: 2, includePolyline: true)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(legacy)), try Self.fixtureRequest("legacy_mgate141_tripsearch_st_anton_innsbruck"),
                        ignoreValues: ["getTariff"])
    }

    func testPagingOmitsDateTimeAndDirection() throws {
        let fixture = try Self.fixtureRequest("tripsearch_paging_later_graz_klagenfurt")
        let ctx = try XCTUnwrap((fixture["req"] as? [String: Any])?["ctxScr"] as? String)
        let q = JourneyQuery(origin: .station(extId: "8100173", name: "Graz Hbf"), destination: .station(extId: "8100085", name: "Klagenfurt Hbf"),
                             date: Date(), results: 3, includeStopovers: false, pageContext: ctx)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(q)), fixture, ignoreValues: ["getTariff"])
        let req = try XCTUnwrap((try Self.encode(HafasRequests.tripSearch(q)) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertNil(req["outDate"])
        XCTAssertNil(req["outTime"])
        XCTAssertNil(req["outFrwd"])
        XCTAssertEqual(req["ctxScr"] as? String, ctx)
        let earlier = try Self.fixtureRequest("tripsearch_paging_earlier_graz_klagenfurt")
        let ctxB = try XCTUnwrap((earlier["req"] as? [String: Any])?["ctxScr"] as? String)
        var qb = q
        qb.pageContext = ctxB
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(qb)), earlier, ignoreValues: ["getTariff"])
    }

    func testArriveBy() throws {
        let q = JourneyQuery(origin: Self.ibk, destination: Self.wienHbf, date: Self.vienna(2026, 10, 9, 18, 0), isArrival: true, results: 3)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(q)), try Self.fixtureRequest("tripsearch_arrive_by_innsbruck_wien"), ignoreValues: ["getTariff"])
        let req = try XCTUnwrap((try Self.encode(HafasRequests.tripSearch(q)) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertEqual(req["outFrwd"] as? Bool, false)
        XCTAssertEqual(req["outTime"] as? String, "180000")
    }

    func testBikeAndAccessibilityFilters() throws {
        let bike = JourneyQuery(origin: Self.ibk, destination: Self.wienHbf, date: Self.vienna(2026, 10, 9, 11, 25, 58), maxChanges: 0,
                                bikeCarriage: true, results: 3)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(bike)), try Self.fixtureRequest("tripsearch_bike_filter_BC"), ignoreValues: ["getTariff"])
        let meta = JourneyQuery(origin: .station(extId: "1291501", name: "Wien Westbahnhof (U)"), destination: .station(extId: "8100002", name: "Salzburg Hbf"),
                                date: Self.vienna(2026, 10, 9, 11, 30), accessibility: .complete, results: 4)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(meta)), try Self.fixtureRequest("tripsearch_accessibility_meta_filter"), ignoreValues: ["getTariff"])
        try assertNoNull(HafasRequests.tripSearch(meta))
    }

    func testViaShapeMatchesFixture() throws {
        let linz = Location.station(extId: "8100013", name: "Linz/Donau Hbf")
        let q = JourneyQuery(origin: Self.ibk, destination: Self.wienHbf, via: [ViaStop(location: linz)], date: Self.vienna(2026, 10, 9, 11, 25, 46),
                             maxChanges: 0, products: ProductMask(rawValue: 5181), results: 3)
        Self.assertSameShape(try Self.encode(HafasRequests.tripSearch(q)), try Self.fixtureRequest("tripsearch_via_linz_maxchg0_rail"), ignoreValues: ["getTariff"])
    }

    /// Owner request 2026-10-09: up to two via stops with an optional minimum dwell (`min`).
    func testViaStopsWithDwell() throws {
        let feldkirch = Location.station(extId: "8100094", name: "Feldkirch Bahnhof")
        let bludenz = Location.station(extId: "8100093", name: "Bludenz Bahnhof")
        let dornbirn = Location.station(extId: "8100096", name: "Dornbirn Bahnhof")
        let q = JourneyQuery(origin: Self.ibk, destination: .station(extId: "8100090", name: "Bregenz Bahnhof"),
                             via: [ViaStop(location: bludenz, minimumDwellMinutes: 0), ViaStop(location: feldkirch, minimumDwellMinutes: 10),
                                   ViaStop(location: dornbirn, minimumDwellMinutes: 5)],
                             date: Self.vienna(2026, 10, 9, 12, 0))
        let req = try XCTUnwrap((try Self.encode(HafasRequests.tripSearch(q)) as? [String: Any])?["req"] as? [String: Any])
        let via = try XCTUnwrap(req["viaLocL"] as? [[String: Any]])
        XCTAssertEqual(via.count, 2, "at most JourneyQuery.maxViaStops")
        XCTAssertEqual(Set(via[0].keys), ["loc"], "dwell 0 → no min")
        XCTAssertEqual(Set(via[1].keys), ["loc", "min"])
        XCTAssertEqual(via[1]["min"] as? Int, 10)
        XCTAssertEqual((via[0]["loc"] as? [String: Any])?["lid"] as? String, "A=1@L=8100093@")
        XCTAssertEqual(Set((via[1]["loc"] as? [String: Any] ?? [:]).keys), ["lid", "type"])
        try assertNoNull(HafasRequests.tripSearch(q))
        // Paging keeps the via stops.
        var paged = q
        paged.pageContext = "3|OF|…"
        let preq = try XCTUnwrap((try Self.encode(HafasRequests.tripSearch(paged)) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertEqual((preq["viaLocL"] as? [Any])?.count, 2)
        // Empty via: no key at all.
        var none = q
        none.via = []
        let nreq = try XCTUnwrap((try Self.encode(HafasRequests.tripSearch(none)) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertNil(nreq["viaLocL"])
    }

    // MARK: - Other methods

    func testReconstruction() throws {
        let fixture = try Self.fixtureRequest("reconstruction_innsbruck_lech_outReconL")
        let token = try XCTUnwrap(((fixture["req"] as? [String: Any])?["outReconL"] as? [[String: Any]])?.first?["ctx"] as? String)
        let svc = HafasRequests.reconstruction(token, includeStopovers: true, includePolyline: false)
        Self.assertSameShape(try Self.encode(svc), fixture)
        let req = try XCTUnwrap((try Self.encode(svc) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertNil(req["ctxRecon"], "ctxRecon gives PARSE on 1.88")
        XCTAssertEqual(((req["outReconL"] as? [[String: Any]])?.first?["ctx"] as? String), token)
    }

    func testJourneyDetails() throws {
        let fixture = try Self.fixtureRequest("journeydetails_rjx133_koralm_polyline")
        let jid = try XCTUnwrap((fixture["req"] as? [String: Any])?["jid"] as? String)
        Self.assertSameShape(try Self.encode(HafasRequests.journeyDetails(jid, includePolyline: true)), fixture)
    }

    func testStationBoards() throws {
        let dep = BoardQuery(station: Self.ibk, kind: .departures, date: Self.vienna(2026, 10, 9, 11, 24, 2), durationMinutes: 45, maxResults: 25)
        Self.assertSameShape(try Self.encode(HafasRequests.stationBoard(dep)), try Self.fixtureRequest("stationboard_dep_innsbruck_hbf"))
        let arr = BoardQuery(station: Self.wienHbf, kind: .arrivals, date: Self.vienna(2026, 10, 9, 11, 24, 8), durationMinutes: 30, maxResults: 40)
        Self.assertSameShape(try Self.encode(HafasRequests.stationBoard(arr)), try Self.fixtureRequest("stationboard_arr_wien_hbf"))
    }

    func testHimSearch() throws {
        let q = RemarksQuery(from: Self.vienna(2026, 10, 9, 11, 27, 2), to: Self.vienna(2026, 10, 10, 11, 27, 2),
                             products: ProductMask(rawValue: 5181), maxResults: 15)
        Self.assertSameShape(try Self.encode(HafasRequests.himSearch(q)), try Self.fixtureRequest("himsearch_disruptions_rail"))
        let all = RemarksQuery(from: Date(), to: Date().addingTimeInterval(3600))
        let req = try XCTUnwrap((try Self.encode(HafasRequests.himSearch(all)) as? [String: Any])?["req"] as? [String: Any])
        XCTAssertNil(req["himFltrL"], "himFltrL omitted when products == nil")
    }

    func testNeverSendsRtMode() throws {
        let q = JourneyQuery(origin: Self.ibk, destination: Self.wienHbf, date: Date())
        let json = String(decoding: try JSONEncoder().encode(HafasEnvelope(profile: LiveConfig.default.hafas, svcReqL: [HafasRequests.tripSearch(q)])), as: UTF8.self)
        XCTAssertFalse(json.contains("rtMode"))
        XCTAssertTrue(json.contains(#""cfg":{"polyEnc":"GPA"}"#))
    }
}
