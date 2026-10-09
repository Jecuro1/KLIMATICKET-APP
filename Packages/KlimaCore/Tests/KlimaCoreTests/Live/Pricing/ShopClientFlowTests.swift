import XCTest
@testable import KlimaCore

/// `OebbShopClient` over `FixtureTransport` with a fake clock (SPEC §B3.1–§B3.4, §D2 WP-B 2).
final class ShopClientFlowTests: XCTestCase {
    typealias F = PricingFixtures

    static let from = OebbShopClient.Station(number: 1290401, name: "Wien Hbf (U)", latitude: 48184986, longitude: 16377950)
    static let to = OebbShopClient.Station(number: 8100002, name: "Salzburg Hbf", latitude: 47813057, longitude: 13045856)
    /// 2026-10-10 08:00 Vienna.
    static let departure = F.vienna("2026-10-10T08:00:00")

    func rig(_ extra: [FixtureTransport.Route], config: LiveConfig = .default) throws -> PricingRig {
        PricingRig(routes: try F.sessionRoutes() + extra, config: config)
    }

    func timetableRoute() throws -> FixtureTransport.Route {
        .init(urlSuffix: F.timetableSuffix, response: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable"))
    }

    func offersRoute() throws -> FixtureTransport.Route {
        .init(urlSuffix: F.offersSuffix, response: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult"))
    }

    func testCallOrderHeadersAndBodies() async throws {
        let r = try rig([try timetableRoute(), try offersRoute()])
        let connections = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
        XCTAssertEqual(connections.count, 5)
        let id = try XCTUnwrap(connections.first?.id)
        let offers = try await r.shop.offers(connectionID: id, departure: Self.departure, discount: .none)
        XCTAssertEqual(ShopOfferSelector.standardFare(offers, travelClass: .second)?.amountEUR, 66.40)

        // token → init → timetable → offers
        XCTAssertEqual(r.paths, [F.tokenSuffix, F.initSuffix, F.timetableSuffix, F.offersSuffix])
        XCTAssertEqual(r.transport.recorded.map(\.method), ["GET", "POST", "POST", "POST"])
        XCTAssertEqual(r.transport.recorded.map(\.url.host), Array(repeating: "shop.oebbtickets.at", count: 4))

        // Exactly the headers of §B3.1 – honest UA, Channel inet, AccessToken after the token call, no Cookie.
        let ua = "KlimaBilanz/1.0.0 (iPhone; iOS; private, low-volume)"
        XCTAssertEqual(r.transport.recorded[0].headers, ["User-Agent": ua, "Accept": "application/json", "Channel": "inet"])
        let authed = ["User-Agent": ua, "Accept": "application/json", "Channel": "inet", "AccessToken": F.token, "Content-Type": "application/json"]
        for i in 1...3 { XCTAssertEqual(r.transport.recorded[i].headers, authed) }
        XCTAssertFalse(r.transport.recorded.contains { $0.headers.keys.contains { $0.lowercased() == "cookie" } })
        XCTAssertEqual(r.transport.recorded[2].timeout, 15)
        XCTAssertEqual(String(decoding: r.transport.recorded[1].body ?? Data(), as: UTF8.self), "{}")

        // Bodies equal §B3.2: minimal passenger, Vienna wall clock without offset, offers datetime = timetable datetime.
        let timetable = try r.transport.jsonBody(2)
        let expected: [String: Any] = [
            "datetimeDeparture": "2026-10-10T08:00:00.000",
            "filter": ["regionaltrains": false, "direct": false, "wheelchair": false, "bikes": false, "trains": false, "motorail": false,
                       "connections": [String]()],
            "passengers": [["type": "ADULT", "id": 1, "cards": [Any]()]],
            "count": 3, "sortType": "DEPARTURE",
            "from": ["number": 1290401, "name": "Wien Hbf (U)", "latitude": 48184986, "longitude": 16377950],
            "to": ["number": 8100002, "name": "Salzburg Hbf", "latitude": 47813057, "longitude": 13045856],
        ]
        XCTAssertEqual(timetable as NSDictionary, expected as NSDictionary)
        let offersBody = try r.transport.jsonBody(3)
        let expectedOffers: [String: Any] = [
            "selection": ["connectionId": id, "offerSections": [String]()],
            "passengers": [["type": "ADULT", "id": 1, "cards": [Any]()]],
            "datetime": "2026-10-10T08:00:00.000",
        ]
        XCTAssertEqual(offersBody as NSDictionary, expectedOffers as NSDictionary)
        XCTAssertTrue(id.hasPrefix("40b209785651"))
        XCTAssertFalse(String(decoding: r.transport.recorded[2].body!, as: UTF8.self).contains("null"))
    }

    func testVorteilscardCard() async throws {
        let r = try rig([.init(urlSuffix: F.offersSuffix, response: try F.shop("shop_wien-salzburg_2026-10-10_08_offers_v6_vorteilscard"))])
        let offers = try await r.shop.offers(connectionID: "x", departure: Self.departure, discount: .vorteilscard)
        XCTAssertEqual(ShopOfferSelector.standardFare(offers, travelClass: .second)?.amountEUR, 33.20)
        let passengers = try XCTUnwrap(try r.transport.jsonBody(2)["passengers"] as? [[String: Any]])
        XCTAssertEqual(passengers[0]["cards"] as? NSArray, [["name": "Vorteilscard Classic", "cardId": 108]] as NSArray)
    }

    func testTokenRenewalAfter240Seconds() async throws {
        let r = try rig([try timetableRoute()])
        _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
        r.clock.advance(200)
        _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
        XCTAssertEqual(r.paths, [F.tokenSuffix, F.initSuffix, F.timetableSuffix, F.timetableSuffix], "token still fresh")
        r.clock.advance(41) // obtained 241+ s ago (throttle sleeps add a little)
        let fresh = await r.shop.hasFreshSession
        XCTAssertFalse(fresh)
        _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
        XCTAssertEqual(Array(r.paths.suffix(3)), [F.tokenSuffix, F.initSuffix, F.timetableSuffix], "renewed: token + init again")
    }

    func testSessionCodesRenewAndRetryOnce() async throws {
        for expired in ["shop_token_expiry_after_330s_timetable", "shop_error_440_session_not_initialised_timetable"] {
            let r = try rig([.init(urlSuffix: F.timetableSuffix, response: try F.shop(expired),
                                   sequence: [try F.shop(expired), try F.shop("shop_wien-salzburg_2026-10-10_05_timetable")])])
            let list = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTAssertEqual(list.count, 5, expired)
            XCTAssertEqual(r.paths, [F.tokenSuffix, F.initSuffix, F.timetableSuffix, F.tokenSuffix, F.initSuffix, F.timetableSuffix], expired)
            let status = await r.health.status()[.oebbShop]
            XCTAssertNil(status?.openUntil, expired)
        }
    }

    func testSecondSessionFailureIsSessionExpired() async throws {
        let r = try rig([.init(urlSuffix: F.timetableSuffix, response: try F.shop("shop_token_expiry_after_330s_timetable"))])
        do {
            _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTFail("expected .sessionExpired")
        } catch let e as LiveError {
            XCTAssertEqual(e, .sessionExpired)
        }
        XCTAssertEqual(r.count(F.timetableSuffix), 2, "exactly one retry")
    }

    func testCloudflareBlockOpensCircuitFor30Minutes() async throws {
        let r = PricingRig(routes: [.init(method: "GET", urlSuffix: F.tokenSuffix, response: try F.shop("shop_error_403_cloudflare_block_page"))])
        do {
            _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTFail("expected .blocked")
        } catch let e as LiveError {
            XCTAssertEqual(e, .blocked(.oebbShop))
        }
        XCTAssertEqual(r.transport.recorded.count, 1, "no retry, no evasion")
        let status = await r.health.status()[.oebbShop]
        XCTAssertEqual(status?.openUntil?.timeIntervalSince(r.clock.now) ?? 0, 30 * 60, accuracy: 2)
        do {
            _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTFail("expected .circuitOpen")
        } catch let e as LiveError {
            guard case .circuitOpen(.oebbShop, _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(r.transport.recorded.count, 1, "open circuit: no I/O")
    }

    func testRateLimitedWithRetryAfter() async throws {
        let limited = HTTPResponse(status: 429, headers: ["Retry-After": "90", "Content-Type": "text/plain"], body: Data("slow down".utf8))
        let r = PricingRig(routes: [.init(method: "GET", urlSuffix: F.tokenSuffix, response: limited)])
        do {
            _ = try await r.shop.stations(named: "Wien Hbf")
            XCTFail("expected .rateLimited")
        } catch let e as LiveError {
            XCTAssertEqual(e, .rateLimited(.oebbShop, retryAfter: 90))
        }
        let status = await r.health.status()[.oebbShop]
        XCTAssertEqual(status?.openUntil?.timeIntervalSince(r.clock.now) ?? 0, 90, accuracy: 2)
    }

    func testRetriesOnceOn503ThenHTTPError() async throws {
        let unavailable = HTTPResponse(status: 503, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
        let r = try rig([.init(urlSuffix: F.timetableSuffix, response: unavailable)])
        do {
            _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTFail("expected .http")
        } catch let e as LiveError {
            guard case .http(503, _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(r.count(F.timetableSuffix), 2)
        XCTAssertTrue(r.clock.sleeps.contains(1.5), "retry after 1.5 s")
    }

    func testEmptyTimetableAndOfferErrorAreNoPrice() async throws {
        let empty = try F.json(["connections": [Any](), "infos": [["header": "Fahrplan 2026/2027"]]])
        let r = try rig([.init(urlSuffix: F.timetableSuffix, response: empty),
                         .init(urlSuffix: F.offersSuffix, response: try F.shop("shop_offers_v6_past_yesterday_wien-salzburg_2026-10-08T0800"))])
        do {
            _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
            XCTFail("expected .noPrice")
        } catch let e as LiveError {
            XCTAssertEqual(e, .noPrice("Fahrplan 2026/2027"))
        }
        do {
            _ = try await r.shop.offers(connectionID: "5f7d", departure: Self.departure, discount: .none)
            XCTFail("expected .noPrice")
        } catch let e as LiveError {
            XCTAssertEqual(e, .noPrice("offerError"))
        }
    }

    func testStationsLookup() async throws {
        let r = try rig([.init(method: "GET", urlSuffix: "count=5", response: try F.shop("shop_wien-salzburg_2026-10-10_03_stations_0"))])
        let list = try await r.shop.stations(named: "Wien Hbf")
        XCTAssertEqual(list.first, OebbShopClient.Station(number: 1290401, name: "Wien Hbf (U)", latitude: 48184986, longitude: 16377950))
        XCTAssertEqual(list.filter { $0.name.isEmpty }.count, 2, "meta entries have an empty name")
        let url = try XCTUnwrap(r.transport.recorded.last?.url.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://shop.oebbtickets.at/api/hafas/v1/stations?name=Wien"), url)
        XCTAssertTrue(url.hasSuffix("&count=5"), url)
    }

    func testKillSwitchAndDisabledShopMakeNoRequests() async throws {
        var off = LiveConfig.default
        off.killSwitch = true
        var shopOff = LiveConfig.default
        shopOff.shop.enabled = false
        for config in [off, shopOff] {
            let r = PricingRig(routes: [], config: config)
            do {
                _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
                XCTFail("expected .disabled")
            } catch let e as LiveError {
                XCTAssertEqual(e, .disabled(.oebbShop))
            }
            XCTAssertTrue(r.transport.recorded.isEmpty)
        }
    }

    func testThrottleSpacesShopRequestsOneSecond() async throws {
        let r = try rig([try timetableRoute()])
        _ = try await r.shop.timetable(from: Self.from, to: Self.to, departure: Self.departure, discount: .none)
        XCTAssertEqual(r.clock.sleeps.filter { $0 > 0 }.count, 2, "init and timetable wait for the 1 s spacing")
        XCTAssertTrue(r.clock.sleeps.allSatisfy { $0 <= 1.0 + 1e-9 })
        let n = await r.throttle.recentCount(.oebbShop)
        XCTAssertEqual(n, 3)
    }
}
