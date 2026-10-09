import XCTest
@testable import KlimaCore

/// The live-recorded VAO exchange with via stops (owner request 2026-10-09), `FX/vao/vao_tripsearch_tariff_via_voels_ibk-hall`.
final class VaoViaRecordedTests: XCTestCase {
    typealias F = PricingFixtures

    /// [LIVE 2026-10-09, one request] VAO honours `viaLocL`: Innsbruck → Völs → Hall in Tirol is priced over the via
    /// route (VVT 6 Zonen 9,40) instead of the direct relation (3 Zonen 4,70). Fixture + `FX/vao/golden_extra.json`.
    func testRecordedVaoViaExchange() async throws {
        let extra = try XCTUnwrap(try Fixture.json("vao/golden_extra") as? [String: Any])
        let golden = try XCTUnwrap(extra["vao/vao_tripsearch_tariff_via_voels_ibk-hall"] as? [String: Any])
        let name = "vao_tripsearch_tariff_via_voels_ibk-hall"
        let fixture = try XCTUnwrap(try Fixture.json("vao/\(name)") as? [String: Any])
        let recorded = try XCTUnwrap(((fixture["request"] as? [String: Any])?["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual(recorded["viaLocL"] as? NSArray, [["loc": ["lid": golden["viaLid"] as! String, "type": "S"]]] as NSArray)

        // Our encoder sends exactly the recorded request (minus outDate/outTime).
        let voels = PriceEndpoint(stationID: "at:47:1191", name: "Völs", coordinate: GeoPoint(latitude: 47.25558, longitude: 11.32129))
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao(name))])
        let q = try await r.service.livePrice(PriceRequest(from: F.epInnsbruck, to: F.epHall, departure: F.vienna("2026-10-09T22:18:04"), via: [voels]))
        var sent = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        var expected = recorded
        for k in ["outDate", "outTime"] {
            sent[k] = nil
            expected[k] = nil
        }
        XCTAssertEqual(sent as NSDictionary, expected as NSDictionary)

        let rows = try XCTUnwrap(golden["connections"] as? [[String: Any]])
        XCTAssertEqual(q.amountEUR, Double(try XCTUnwrap(rows.first?["totalCents"] as? Int)) / 100)
        XCTAssertGreaterThan(q.amountEUR, Double(try XCTUnwrap(golden["directCents"] as? Int)) / 100, "the detour costs more zones")
        XCTAssertEqual(q.explanation, "VVT Einzelticket · VVT 6 Zonen · Verkehrsauskunft Österreich · über Völs")
        // Every priced connection really passes Völs.
        let res = try XCTUnwrap(((fixture["response"] as? [String: Any])?["svcResL"] as? [[String: Any]])?.first?["res"] as? [String: Any])
        let locs = try XCTUnwrap((res["common"] as? [String: Any])?["locL"] as? [[String: Any]])
        for con in try XCTUnwrap(res["outConL"] as? [[String: Any]]) {
            let stops = (con["secL"] as? [[String: Any]] ?? []).compactMap { ($0["dep"] as? [String: Any])?["locX"] as? Int }.map { locs[$0]["name"] as? String ?? "" }
            XCTAssertTrue(stops.contains { $0.hasPrefix("Völs") }, "\(stops)")
        }
    }
}
