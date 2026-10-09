import XCTest
@testable import KlimaCore

/// The shared test helpers behave as documented in SPEC §A2.2 (other work packages build on them).
final class FixtureSupportTests: XCTestCase {
    func testShopWrapperIsUnwrapped() throws {
        let offers = try Fixture.shopResponse("shop/shop_wien-salzburg_2026-10-10_07_offers_v6_adult")
        XCTAssertEqual(offers.status, 200)
        XCTAssertTrue(offers.isJSON)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: offers.body) as? [String: Any])
        XCTAssertNotNil(obj["offerSections"])
        let stations = try Fixture.shopResponse("shop/shop_wien-salzburg_2026-10-10_03_stations_0")
        XCTAssertTrue(try JSONSerialization.jsonObject(with: stations.body) is [Any])
        let expired = try Fixture.shopResponse("shop/shop_error_440_session_not_initialised_timetable")
        XCTAssertEqual(expired.status, 440)
        let vao = try Fixture.shopResponse("vao/vao_tripsearch_tariff_ibk-hall")
        XCTAssertNil(HafasCodec.envelopeError(vao.body, provider: .vaoTariff))
    }

    func testCloudflareBlockPageIsHTML403() throws {
        let r = try Fixture.shopResponse("shop/shop_error_403_cloudflare_block_page")
        XCTAssertEqual(r.status, 403)
        XCTAssertFalse(r.isJSON)
        XCTAssertTrue(r.contentType.hasPrefix("text/html"))
        XCTAssertNotNil(r.headers["cf-ray"])
        XCTAssertTrue(String(decoding: r.body, as: UTF8.self).lowercased().contains("<html"))
    }

    func testFixtureTransportRoutesAndRecords() async throws {
        let a = HTTPResponse(status: 200, body: Data("a".utf8)), b = HTTPResponse(status: 201, body: Data("b".utf8))
        let t = FixtureTransport(routes: [
            .init(method: "GET", urlSuffix: "/x", response: a),
            .init(urlSuffix: "/y", bodyContains: "two", response: a, sequence: [a, b]),
            .init(urlSuffix: "/y", response: b, error: .timeout),
        ])
        let url = { (s: String) in URL(string: "https://example.invalid\(s)")! }
        let r1 = try await t.send(HTTPRequest(method: "GET", url: url("/x")))
        XCTAssertEqual(r1.status, 200)
        let r2 = try await t.send(HTTPRequest(method: "POST", url: url("/y"), body: Data("two".utf8)))
        let r3 = try await t.send(HTTPRequest(method: "POST", url: url("/y"), body: Data("two".utf8)))
        let r4 = try await t.send(HTTPRequest(method: "POST", url: url("/y"), body: Data("two".utf8)))
        XCTAssertEqual([r2.status, r3.status, r4.status], [200, 201, 201], "sequence, last repeats")
        do { _ = try await t.send(HTTPRequest(method: "POST", url: url("/y"), body: Data("one".utf8))); XCTFail() } catch {
            XCTAssertEqual(error as? LiveError, .timeout)
        }
        XCTAssertEqual(t.recorded.count, 5)
        XCTAssertEqual(t.recorded[0].method, "GET")
    }

    func testGoldenAccess() throws {
        XCTAssertEqual(try Fixture.golden("hafas/serverinfo")["topErr"] as? String, "OK")
        XCTAssertFalse(Fixture.goldenKeys(prefix: "shop/").isEmpty)
        XCTAssertFalse(Fixture.goldenKeys(prefix: "vao/").isEmpty)
        XCTAssertNotNil(try Fixture.json("coverage/coverage_rules"))
        XCTAssertNotNil(Bundle.module.url(forResource: "Fixtures/OEBB/coverage/synthetic_cases", withExtension: "json"))
    }
}
