import XCTest
@testable import KlimaCore

/// `VerbundTariffClient` (VAO) against `FX/vao/*` (SPEC §B5, §D2 WP-B 3).
final class VerbundTests: XCTestCase {
    typealias F = PricingFixtures

    func rig(_ fixture: String, config: LiveConfig = .default) throws -> PricingRig {
        PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao(fixture))], config: config)
    }

    /// The encoded request equals the recorded `vao_tripsearch_tariff_stanton-ibk` request (minus outDate / outTime).
    func testRequestEqualsFixture() async throws {
        let r = try rig("vao_tripsearch_tariff_stanton-ibk")
        let fare = try await r.verbund.singleFare(fromLid: "A=1@L=470122200@", toLid: "A=1@L=470118700@",
                                                  departure: F.vienna("2026-10-09T13:00:00"))
        XCTAssertEqual(fare, VerbundTariffClient.Fare(amountEUR: 22.00, provider: "VVT", productName: "VVT Einzelticket", fareSet: "VVT 14 Zonen"))
        let fixture = try XCTUnwrap(try Fixture.json("vao/vao_tripsearch_tariff_stanton-ibk") as? [String: Any])
        let sent = try r.transport.jsonBody(0)
        let recorded = try XCTUnwrap(fixture["request"] as? [String: Any])
        func stripVolatile(_ envelope: [String: Any]) -> [String: Any] {
            var e = envelope
            var svc = (e["svcReqL"] as? [[String: Any]]) ?? []
            var req = svc[0]["req"] as? [String: Any] ?? [:]
            req["outDate"] = nil
            req["outTime"] = nil
            svc[0]["req"] = req
            e["svcReqL"] = svc
            return e
        }
        XCTAssertEqual(stripVolatile(sent) as NSDictionary, stripVolatile(recorded) as NSDictionary)
        let req = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual(req["outDate"] as? String, "20261009")
        XCTAssertEqual(req["outTime"] as? String, "130000")
        XCTAssertNil(req["viaLocL"], "no viaLocL key without via stops")
        XCTAssertEqual(r.transport.recorded[0].url.absoluteString, "https://anachb.vor.at/hamm/gate")
        XCTAssertEqual(r.transport.recorded[0].headers["User-Agent"], "KlimaBilanz/1.0.0 (iPhone; iOS; private, low-volume)")
        XCTAssertEqual(r.transport.recorded[0].timeout, 12)
        XCTAssertFalse(String(decoding: r.transport.recorded[0].body!, as: UTF8.self).contains("null"))
    }

    /// Every VAO golden: cents → EUR, provider, fare set, product name (trimmed, provider-prefixed); NA → `.noPrice`.
    func testAllVaoGoldens() throws {
        let keys = Fixture.goldenKeys(prefix: "vao/").filter { $0.contains("tariff") && !$0.contains("eva-lid") }
        XCTAssertEqual(keys.count, 13)
        for key in keys {
            let golden = try Fixture.golden(key)
            let rows = try XCTUnwrap(golden["connections"] as? [[String: Any]], key)
            let data = try F.vao(String(key.dropFirst(4))).body
            if let ok = rows.first(where: { $0["statusCode"] as? String == "OK" }) {
                let fare = try VerbundTariffClient.fare(from: data)
                let cents = try XCTUnwrap(ok["totalCents"] as? Int, key)
                XCTAssertEqual(fare.amountEUR, Double(cents) / 100, accuracy: 0.0001, key)
                let fareSet = try XCTUnwrap(ok["fareSet"] as? String, key)
                XCTAssertEqual(fare.fareSet, fareSet, key)
                XCTAssertEqual(fare.provider, String(fareSet.split(separator: " ")[0]), key)
                let product = try XCTUnwrap(ok["product"] as? String, key).trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(fare.productName.hasSuffix(product), "\(key): \(fare.productName)")
                XCTAssertTrue(fare.productName.contains(fare.provider), key)
                XCTAssertEqual(fare.productName, fare.productName.trimmingCharacters(in: .whitespaces), key)
            } else {
                XCTAssertThrowsError(try VerbundTariffClient.fare(from: data), key) { e in
                    XCTAssertEqual(e as? LiveError, .noPrice("NA"), key)
                }
            }
        }
    }

    func testGoldenProductsSpelledOut() throws {
        func fare(_ name: String) throws -> VerbundTariffClient.Fare { try VerbundTariffClient.fare(from: try F.vao(name).body) }
        XCTAssertEqual(try fare("vao_tripsearch_tariff_stanton-ibk"),
                       .init(amountEUR: 22.00, provider: "VVT", productName: "VVT Einzelticket", fareSet: "VVT 14 Zonen"),
                       "„Einzelticket “ trimmed; „Einzelticket Family“ (same price) is not the first match")
        XCTAssertEqual(try fare("vao_tripsearch_tariff_ibk-hall").amountEUR, 4.70)
        XCTAssertEqual(try fare("vao_tripsearch_tariff_ibk-hall_past_2026-10-08").amountEUR, 4.70)
        XCTAssertEqual(try fare("vao_tripsearch_tariff_ibk-hall_after-fare-change_2026-12-15").amountEUR, 4.70)
        XCTAssertEqual(try fare("vao_tripsearch_tariff_wien-wrneustadt"),
                       .init(amountEUR: 14.80, provider: "VOR", productName: "Einzelfahrt VOR + Wien Kernzone", fareSet: "VOR"))
        XCTAssertEqual(try fare("vao_tripsearch_tariff_linz-wels"),
                       .init(amountEUR: 7.60, provider: "OÖVV", productName: "OÖVV Einzelfahrt", fareSet: "OÖVV 5 Zonen"))
        XCTAssertEqual(try fare("vao_tripsearch_tariff_klagenfurt-villach"),
                       .init(amountEUR: 10.50, provider: "VKG", productName: "VKG Einzelkarte Erwachsene", fareSet: "VKG 7 Zonen"))
        XCTAssertEqual(try fare("vao_tripsearch_tariff_bregenz-feldkirch"),
                       .init(amountEUR: 9.60, provider: "VVV", productName: "VVV Vollpreis - 60/120 Minuten", fareSet: "VVV MAXIMO"))
        XCTAssertEqual(try fare("vao_tripsearch_tariff_wien-kernzone_wienhbf-wienwest").amountEUR, 3.00, "VOR „1 Fahrt WIEN“ (catalog: 3,20, §G Q2)")
        XCTAssertEqual(try fare("vao_tripsearch_tariff_wienwest-stpoelten").amountEUR, 17.50)
    }

    func testNotAvailableIsNoPrice() async throws {
        let r = try rig("vao_tripsearch_tariff_wien-salzburg")
        do {
            _ = try await r.verbund.singleFare(fromLid: "A=1@L=490134900@", toLid: "A=1@L=455000200@", departure: F.now)
            XCTFail("expected .noPrice")
        } catch let e as LiveError {
            XCTAssertEqual(e, .noPrice("NA"))
        }
        let status = await r.health.status()[.vaoTariff]
        XCTAssertNotNil(status?.lastSuccess, "NA is an answer, not a failure")
        XCTAssertNil(status?.openUntil)
    }

    func testEvaLidIsLocationError() async throws {
        let r = try rig("arch_vao_tripsearch_tariff_eva-lid_eferding-linz")
        do {
            _ = try await r.verbund.singleFare(fromLid: "A=1@L=8100227@", toLid: "A=1@L=444116400@", departure: F.now)
            XCTFail("expected .hafas(LOCATION)")
        } catch let e as LiveError {
            guard case .hafas(code: "LOCATION", _) = e else { return XCTFail("\(e)") }
        }
        let status = await r.health.status()[.vaoTariff]
        XCTAssertEqual(status?.consecutiveFailures ?? 0, 0, "service errors are not breaker failures")
    }

    func testLocMatchEmbedsIFOPT() async throws {
        let r = try rig("arch_vao_locmatch_eferding")
        let list = try await r.verbund.vaoLocations("Eferding")
        XCTAssertTrue(list.contains { $0.lid.contains("at:44:42505") }, "\(list.map(\.lid))")
        let req = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first)
        XCTAssertEqual(req["meth"] as? String, "LocMatch")
        XCTAssertEqual((req["req"] as? NSDictionary), ["input": ["loc": ["type": "S", "name": "Eferding"], "maxLoc": 5, "field": "S"]] as NSDictionary)
        // The linker maps it to the minimal lid within 400 m (rule 3).
        let eferding = Station(id: "osm:node:1", name: "Eferding Bahnhof", lat: 48.3035, lon: 14.016, state: "OÖ")
        let linker = StationLinker(stations: StationIndex(stations: [eferding]), timetable: nil, vao: r.verbund, cacheURL: nil)
        let lid = try await linker.vaoLid(for: eferding)
        XCTAssertEqual(lid, "A=1@L=444250500@")
        XCTAssertEqual(VerbundArea.hint(vaoLid: list.first { $0.lid.contains("at:44:42505") }?.lid), "OÖVV")
    }

    func testViaLidsAreSentAsViaLocL() async throws {
        let r = try rig("vao_tripsearch_tariff_ibk-hall")
        _ = try await r.verbund.singleFare(fromLid: "A=1@L=470118700@", toLid: "A=1@L=470118400@", via: ["A=1@L=470118600@"], departure: F.now)
        let req = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual(req["viaLocL"] as? NSArray, [["loc": ["lid": "A=1@L=470118600@", "type": "S"]]] as NSArray)
    }

    func testDisabledAndAuthBlocked() async throws {
        var off = LiveConfig.default
        off.vao.enabled = false
        let r = PricingRig(routes: [], config: off)
        do {
            _ = try await r.verbund.singleFare(fromLid: "a", toLid: "b", departure: F.now)
            XCTFail("expected .disabled")
        } catch let e as LiveError {
            XCTAssertEqual(e, .disabled(.vaoTariff))
        }
        XCTAssertTrue(r.transport.recorded.isEmpty)

        let auth = try F.json(["err": "AUTH", "errTxt": "HCI Core: Authorization fail", "ver": "1.59"])
        let b = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: auth)])
        do {
            _ = try await b.verbund.singleFare(fromLid: "a", toLid: "b", departure: F.now)
            XCTFail("expected .blocked")
        } catch let e as LiveError {
            XCTAssertEqual(e, .blocked(.vaoTariff))
        }
        XCTAssertEqual(b.transport.recorded.count, 1)
        let status = await b.health.status()[.vaoTariff]
        XCTAssertEqual(status?.openUntil?.timeIntervalSince(b.clock.now) ?? 0, 30 * 60, accuracy: 2)
    }
}
