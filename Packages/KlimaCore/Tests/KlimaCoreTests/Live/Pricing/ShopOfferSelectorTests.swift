import XCTest
@testable import KlimaCore

/// Shop raw mirrors and the Standard-fare selector against every `FX/shop` golden (SPEC §B2, §B3.3, §D1.1, §D2 WP-B 1).
final class ShopOfferSelectorTests: XCTestCase {
    func offers(_ name: String) throws -> ShopOffers {
        try JSONDecoder().decode(ShopOffers.self, from: try PricingFixtures.shop(name).body)
    }

    /// Every golden with `standard2nd` / `standard1st`: amount, products, owner and reductions.
    func testAllOfferGoldens() throws {
        let keys = Fixture.goldenKeys(prefix: "shop/").filter { $0.contains("offers") }
        XCTAssertGreaterThanOrEqual(keys.count, 10)
        var checked = 0
        for key in keys {
            let golden = try Fixture.golden(key)
            let name = String(key.dropFirst("shop/".count))
            let decoded = try offers(name)
            if golden["offerError"] as? Bool == true {
                XCTAssertEqual(decoded.offerError, true, key)
                XCTAssertNil(ShopOfferSelector.standardFare(decoded, travelClass: .second), key)
                XCTAssertNil(ShopOfferSelector.standardFare(decoded, travelClass: .first), key)
                checked += 1
                continue
            }
            guard let second = golden["standard2nd"] as? [String: Any] else { continue }
            let fare = try XCTUnwrap(ShopOfferSelector.standardFare(decoded, travelClass: .second), key)
            XCTAssertEqual(fare.amountEUR, try XCTUnwrap(PricingFixtures.number(second["price"])), accuracy: 0.001, key)
            XCTAssertEqual(fare.productName, (second["products"] as? [String])?.joined(separator: " + "), key)
            XCTAssertEqual(fare.owner, (second["owners"] as? [String])?.first, key)
            if let reductions = second["reductions"] as? [String] { XCTAssertEqual(fare.reductions, reductions, key) }
            if let first = PricingFixtures.number(golden["standard1st"]) {
                XCTAssertEqual(try XCTUnwrap(ShopOfferSelector.standardFare(decoded, travelClass: .first), key).amountEUR, first, accuracy: 0.001, key)
            } else {
                XCTAssertNil(ShopOfferSelector.standardFare(decoded, travelClass: .first), "\(key): Verbund tickets have no 1st class")
            }
            // The raw offer list decodes completely (class, flexibility, price, trafficTypes, owners).
            if let rows = golden["offers"] as? [[String: Any]] {
                let flat = (decoded.offerSections ?? []).flatMap { s in (s.travelClasses ?? []).flatMap { c in (c.offers ?? []).map { (c.travelClass, $0) } } }
                XCTAssertEqual(flat.count, rows.count, key)
                for (row, (cls, offer)) in zip(rows, flat) {
                    XCTAssertEqual(cls, row["class"] as? String, key)
                    XCTAssertEqual(offer.flexibility?.de, row["flexibility"] as? String, key)
                    XCTAssertEqual(offer.price ?? -1, PricingFixtures.number(row["price"]) ?? -2, accuracy: 0.001, key)
                    XCTAssertEqual(Set((offer.products ?? []).compactMap(\.trafficType)), Set(row["trafficTypes"] as? [String] ?? []), key)
                    XCTAssertEqual(Set((offer.products ?? []).flatMap { $0.owners ?? [] }.compactMap(\.nameShort)), Set(row["owners"] as? [String] ?? []), key)
                }
            }
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 11)
    }

    func testKeyGoldenAmounts() throws {
        // §D1.1 excerpt, spelled out.
        func f(_ name: String, _ c: TravelClass = .second) throws -> ShopFare? { ShopOfferSelector.standardFare(try offers(name), travelClass: c) }
        XCTAssertEqual(try f("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")?.amountEUR, 66.40)
        XCTAssertEqual(try f("shop_wien-salzburg_2026-10-10_07_offers_v6_adult", .first)?.amountEUR, 129.50)
        XCTAssertEqual(try f("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult")?.amountEUR, 67.70)
        XCTAssertEqual(try f("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult", .first)?.amountEUR, 132.10)
        XCTAssertEqual(try f("shop_wien-salzburg_2026-10-10_08_offers_v6_vorteilscard")?.amountEUR, 33.20)
        XCTAssertEqual(try f("shop_wien-salzburg_2026-10-10_08_offers_v6_vorteilscard", .first)?.amountEUR, 64.80)

        let hall = try XCTUnwrap(try f("shop_ibk-hall_2026-10-10_07_offers_v6_adult"))
        XCTAssertEqual(hall, ShopFare(amountEUR: 4.70, productName: "VVT Einzelticket", owner: "VVT"), "MULTIPLE day ticket 42,60 excluded")
        XCTAssertTrue(hall.isVerbund)
        XCTAssertNil(try f("shop_ibk-hall_2026-10-10_07_offers_v6_adult", .first))

        XCTAssertEqual(try f("shop_graz-wien_sparschiene_2026-10-12_07_offers_v6_adult")?.amountEUR, 43.50, "cheaper NON-FLEX Sparschiene ignored")
        XCTAssertEqual(try f("shop_graz-wien_sparschiene_2026-10-12_07_offers_v6_adult", .first)?.amountEUR, 84.70)

        let landeck = try XCTUnwrap(try f("arch_shop_offers_v6_minimal-passenger_ibk-landeck"))
        XCTAssertEqual(landeck.amountEUR, 22.00)
        XCTAssertEqual(landeck.owner, "VVT")
        let landeck1 = try XCTUnwrap(try f("arch_shop_offers_v6_minimal-passenger_ibk-landeck", .first))
        XCTAssertEqual(landeck1, ShopFare(amountEUR: 34.40, productName: "Standard-Ticket", owner: "ÖBB"))
        XCTAssertFalse(landeck1.isVerbund)

        let vc = try XCTUnwrap(try f("arch_shop_offers_v6_minimal-vorteilscard_graz-wien"))
        XCTAssertEqual(vc, ShopFare(amountEUR: 22.20, productName: "Standard-Ticket", owner: "ÖBB", reductions: ["1× Vorteilscard Classic"]))
        XCTAssertEqual(try f("arch_shop_offers_v6_minimal-vorteilscard_graz-wien", .first)?.amountEUR, 43.20)

        XCTAssertEqual(try f("shop_offers_v6_wien-salzburg_2026-11-20T1400_RJX")?.amountEUR, 63.70)
        XCTAssertNil(try f("shop_offers_v6_past_yesterday_wien-salzburg_2026-10-08T0800"), "offerError → nil fare")
    }

    func testSelectorRules() throws {
        func offer(_ flex: String, _ price: Double, _ types: [String]) -> ShopOffers.Offer {
            ShopOffers.Offer(flexibility: ShopText(de: flex), price: price,
                             products: types.map { ShopOffers.Product(name: ShopText(de: "P"), price: price, trafficType: $0, owners: [.init(nameShort: "ÖBB")]) })
        }
        let o = ShopOffers(offerError: false, offerSections: [
            .init(travelClasses: [.init(travelClass: "2", offers: [offer("NON-FLEX", 10, ["ONEWAY"]), offer("SEMI-FLEX", 12, ["ONEWAY"]),
                                                                    offer("FLEX", 30, ["ONEWAY", "MULTIPLE"]), offer("FLEX", 25, ["ONEWAY"]),
                                                                    offer("FLEX", 24, ["ONEWAY", "ONEWAY"]), offer("FLEX", 5, [])]),
                                  .init(travelClass: "B", offers: [offer("FLEX", 1, ["ONEWAY"])])]),
        ])
        let fare = try XCTUnwrap(ShopOfferSelector.standardFare(o, travelClass: .second))
        XCTAssertEqual(fare.amountEUR, 24, "lowest FLEX offer whose products are all ONEWAY")
        XCTAssertEqual(fare.productName, "P + P", "product names joined with „ + “")
        XCTAssertNil(ShopOfferSelector.standardFare(o, travelClass: .first), "business class \"B\" is not 1st class")
        XCTAssertNil(ShopOfferSelector.standardFare(ShopOffers(offerError: true, offerSections: o.offerSections), travelClass: .second))
        // Prices are EUR doubles → cents.
        let odd = ShopOffers(offerError: nil, offerSections: [.init(travelClasses: [.init(travelClass: "2", offers: [offer("FLEX", 33.199999, ["ONEWAY"])])])])
        XCTAssertEqual(ShopOfferSelector.standardFare(odd, travelClass: .second)?.amountEUR, 33.20)
    }

    /// Timetable goldens: count, ids, Vienna wall-clock times, esn, switches, duration, sections.
    func testTimetableGoldens() throws {
        let keys = Fixture.goldenKeys(prefix: "shop/").filter { $0.contains("timetable") && !$0.contains("error") && !$0.contains("expiry") }
        var checked = 0
        for key in keys {
            let golden = try Fixture.golden(key)
            guard let rows = golden["connections"] as? [[String: Any]] else {
                if let n = golden["connectionCount"] as? Int {
                    let r = try JSONDecoder().decode(ShopTimetableResponse.self, from: try PricingFixtures.shop(String(key.dropFirst(5))).body)
                    XCTAssertEqual(r.connections?.count, n, key)
                    checked += 1
                }
                continue
            }
            let r = try JSONDecoder().decode(ShopTimetableResponse.self, from: try PricingFixtures.shop(String(key.dropFirst(5))).body)
            let list = try XCTUnwrap(r.connections, key)
            XCTAssertEqual(list.count, golden["connectionCount"] as? Int, key)
            for (row, c) in zip(rows, list) {
                XCTAssertTrue(c.id?.hasPrefix(row["id"] as? String ?? "?") == true, key)
                XCTAssertEqual(c.id?.count, 64, "64-hex opaque id")
                XCTAssertEqual(c.from?.departure, row["departure"] as? String, key)
                XCTAssertEqual(c.to?.arrival, row["arrival"] as? String, key)
                XCTAssertEqual(c.from?.esn, row["fromEsn"] as? Int, key)
                XCTAssertEqual(c.to?.esn, row["toEsn"] as? Int, key)
                XCTAssertEqual(c.switches, row["switches"] as? Int, key)
                XCTAssertEqual(c.duration, (row["durationMs"] as? Int).map(Double.init), key)
                let sections = (row["sections"] as? [[String]]) ?? []
                XCTAssertEqual((c.sections ?? []).compactMap { s in s.category.map { [$0.name ?? "", $0.number ?? ""] } }, sections, key)
                XCTAssertEqual(c.durationSeconds, (row["durationMs"] as? Int).map { Double($0) / 1000 }, key)
                XCTAssertEqual(c.departureDate, ShopTime.date(row["departure"] as? String), key)
            }
            if let infos = golden["infos"] as? [String] {
                XCTAssertEqual((r.infos ?? []).compactMap(\.header), infos, key)
            }
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 7)
        // Vienna wall clock, no offset: 08:28 CEST = 06:28Z.
        XCTAssertEqual(ShopTime.date("2026-10-10T08:28:00.000"), ISO.date("2026-10-10T06:28:00Z"))
        XCTAssertEqual(ShopTime.string(ISO.date("2026-10-10T06:00:00Z")!), "2026-10-10T08:00:00.000")
        XCTAssertEqual(ShopTime.string(ISO.date("2026-12-15T13:00:00Z")!), "2026-12-15T14:00:00.000", "winter time +01:00")
    }

    func testStationAndSessionGoldens() throws {
        for key in ["shop/shop_wien-salzburg_2026-10-10_03_stations_0", "shop/shop_wien-salzburg_2026-10-10_03_stations_1"] {
            let golden = try XCTUnwrap(try Fixture.golden(key)["stations"] as? [[String: Any]])
            let raw = try JSONDecoder().decode([ShopStationRaw].self, from: try PricingFixtures.shop(String(key.dropFirst(5))).body)
            XCTAssertEqual(raw.map(\.number), golden.map { $0["number"] as? Int }, key)
            XCTAssertEqual(raw.map(\.name), golden.map { $0["name"] as? String }, key)
            XCTAssertTrue(raw.allSatisfy { ($0.latitude ?? 0) > 40_000_000 && ($0.longitude ?? 0) > 9_000_000 }, "µdeg ints")
        }
        let token = try JSONDecoder().decode(ShopTokenResponse.self, from: try PricingFixtures.shop("shop_wien-salzburg_2026-10-10_01_anonymousToken").body)
        XCTAssertEqual(token.accessToken, PricingFixtures.token)
        XCTAssertEqual(token.expiresIn, 300)
        let keys = try XCTUnwrap(try Fixture.golden("shop/shop_wien-salzburg_2026-10-10_01_anonymousToken")["keys"] as? [String])
        XCTAssertTrue(keys.contains("access_token"))
        for (key, code) in [("shop_error_440_session_not_initialised_timetable", 3011), ("shop_token_expiry_after_330s_timetable", 13008)] {
            let r = try PricingFixtures.shop(key)
            XCTAssertEqual(try JSONDecoder().decode(ShopErrorResponse.self, from: r.body).error?.code, code)
            XCTAssertEqual(r.status, (try Fixture.golden("shop/\(key)"))["status"] as? Int)
        }
    }

    /// Tolerance: drifted types and malformed list elements never fail the whole response.
    func testTolerantDecoding() throws {
        let json = #"{"offerError":"no","offerSections":[{"travelClasses":[{"class":2,"offers":[{"flexibility":"FLEX","price":"x"},{"flexibility":{"de":"FLEX"},"price":12.5,"products":[{"name":{"de":"Standard-Ticket"},"trafficType":"ONEWAY","owners":[{"nameShort":"ÖBB"}]},7]}]},"junk"]}]}"#
        let o = try JSONDecoder().decode(ShopOffers.self, from: Data(json.utf8))
        XCTAssertNil(o.offerError)
        XCTAssertEqual(ShopOfferSelector.standardFare(o, travelClass: .second)?.amountEUR, 12.5)
        let t = try JSONDecoder().decode(ShopTimetableResponse.self, from: Data(#"{"connections":[{"id":"a","from":{"esn":"8100108"},"sections":[{"category":{"number":19962}}]},12]}"#.utf8))
        XCTAssertEqual(t.connections?.count, 1)
        XCTAssertEqual(t.connections?.first?.from?.esn, 8100108)
        XCTAssertEqual(t.connections?.first?.trainNumbers, ["19962"])
    }
}
