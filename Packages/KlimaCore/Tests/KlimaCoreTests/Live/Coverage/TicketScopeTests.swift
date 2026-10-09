import XCTest
@testable import KlimaCore

/// SPEC §D2 WP-C 4: `TicketProduct.id` → `TicketScope`.
final class TicketScopeTests: XCTestCase {
    func testProductIDsMapToScopes() {
        let ev = CoverageFixtures.evaluator
        XCTAssertEqual(ev.scope(forProductID: "oe-klassik"), .oe)
        XCTAssertEqual(ev.scope(forProductID: "oe-familie-ermaessigt"), .oe)
        XCTAssertEqual(ev.scope(forProductID: "tirol-klassik"), .regional("tirol"))
        XCTAssertEqual(ev.scope(forProductID: "tirol-klassik-pluseins"), .regional("tirol"))
        XCTAssertEqual(ev.scope(forProductID: "vbg-maximo-klassik"), .regional("vbg"))
        XCTAssertEqual(ev.scope(forProductID: "ooe-regional-linz-klassik"), .regional("ooe"))
        XCTAssertEqual(ev.scope(forProductID: "ooe-gesamt-jugend"), .regional("ooe"))
        XCTAssertEqual(ev.scope(forProductID: "sbg-klassik-plus"), .regional("sbg"))
        XCTAssertEqual(ev.scope(forProductID: "vor-metropolregion-klassik"), .regional("vor-metropolregion"))
        XCTAssertEqual(ev.scope(forProductID: "vor-region-senior"), .regional("vor-region"))
        XCTAssertEqual(ev.scope(forProductID: "wien-klassik"), .regional("wien"))
        XCTAssertEqual(ev.scope(forProductID: "stmk-klassik-uebertragbar"), .regional("stmk"))
        XCTAssertEqual(ev.scope(forProductID: "ktn-spezial-familie"), .regional("ktn"))
        for id in ["tirol-innsbruck", "tirol-regionen", "tirol-euregio", "vbg-lokal-klassik", "custom", ""] {
            XCTAssertEqual(ev.scope(forProductID: id), .unsupported, id)
        }
    }

    /// Every product of the shipped tariff catalog maps to a scope without crashing; KlimaTicket Ö variants are `.oe`.
    func testEveryShippedProductHasAScope() throws {
        let url = PlaceFixtures.resources.appendingPathComponent("tariffs.json")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ids = try XCTUnwrap(obj["products"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        XCTAssertGreaterThan(ids.count, 50)
        let ev = CoverageFixtures.evaluator
        for id in ids where id.hasPrefix("oe-") { XCTAssertEqual(ev.scope(forProductID: id), .oe, id) }
        let regional = ids.filter { if case .regional = ev.scope(forProductID: $0) { return true } else { return false } }
        XCTAssertGreaterThan(regional.count, 40)
    }
}
