import XCTest
@testable import KlimaCore

/// `LivePriceService` policy (SPEC §B4) with the real clients over `FixtureTransport`; clock = 2026-10-09T12:15 Vienna.
/// The 13 scenarios of §D2 WP-B 5 with exact amounts and §B4.5 explanations, byte for byte.
final class LivePriceServicePolicyTests: XCTestCase {
    typealias F = PricingFixtures

    static let sameDay = F.vienna("2026-10-09T16:00:00")
    static let tomorrow = F.vienna("2026-10-10T08:00:00")

    func sameDayRoutes() throws -> [FixtureTransport.Route] {
        try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_sameday_2026-10-09_05_timetable"),
                         offers: try F.shop("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult"))
    }

    func request(_ from: PriceEndpoint, _ to: PriceEndpoint, _ departure: Date, _ cls: TravelClass = .second,
                 _ discount: FareDiscount = .none, journey: Journey? = nil, via: [PriceEndpoint] = []) -> PriceRequest {
        PriceRequest(from: from, to: to, departure: departure, mode: .train, travelClass: cls, discount: discount, journey: journey, via: via)
    }

    // 1
    func testInsideVerbundUsesVAOFirst() async throws {
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_ibk-hall"))])
        let q = try await r.service.livePrice(request(F.epInnsbruck, F.epHall, F.vienna("2026-10-09T17:00:00")))
        XCTAssertEqual(q.amountEUR, 4.70)
        XCTAssertEqual(q.source, .liveVerbund)
        XCTAssertEqual(q.provider, "VVT")
        XCTAssertEqual(q.productName, "VVT Einzelticket")
        XCTAssertEqual(q.explanation, "VVT Einzelticket · VVT 3 Zonen · Verkehrsauskunft Österreich")
        XCTAssertEqual(q.fetchedAt, F.now)
        XCTAssertEqual(r.count(F.vaoSuffix), 1, "exactly 1 VAO request")
        XCTAssertEqual(r.count("shop.oebbtickets.at"), 0, "0 shop requests")
        // The VAO lids are the IFOPT-derived ones (no LocMatch).
        let req = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual((req["depLocL"] as? [[String: Any]])?.first?["lid"] as? String, "A=1@L=470118700@")
        XCTAssertEqual((req["arrLocL"] as? [[String: Any]])?.first?["lid"] as? String, "A=1@L=470118400@")
        XCTAssertEqual(req["outDate"] as? String, "20261009")
    }

    // 2
    func testSameDayRelationProxy() async throws {
        let r = PricingRig(routes: try sameDayRoutes())
        let q = try await r.service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.provider, "ÖBB")
        XCTAssertEqual(q.productName, "Standard-Ticket")
        XCTAssertEqual(q.explanation, "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15")
        XCTAssertEqual(q.leadTime, .travelDay)
        XCTAssertTrue(q.alternatives.isEmpty, "table 67,70 = shop → no alternative")
        XCTAssertEqual(q.connectionID?.hasPrefix("e04ec39f5a59"), true, "fastest connection (detour RJ 658 avoided)")
        XCTAssertEqual(r.paths, [F.tokenSuffix, F.initSuffix, F.timetableSuffix, F.offersSuffix], "VOR ≠ SVV: no VAO request")
        let body = try r.transport.jsonBody(2)
        XCTAssertEqual(body["datetimeDeparture"] as? String, "2026-10-09T16:00:00.000")
        XCTAssertEqual((body["from"] as? [String: Any])?["number"] as? Int, 1290401)
        XCTAssertEqual((body["to"] as? [String: Any])?["number"] as? Int, 8100002)
        XCTAssertEqual(try r.transport.jsonBody(3)["datetime"] as? String, "2026-10-09T16:00:00.000")
        XCTAssertEqual(q.shopURL?.absoluteString.contains("stationOrigEva=001290401"), true)
    }

    // 3
    func testTomorrowAdvanceGivesTableWithShopAlternative() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable"),
                                                    offers: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")))
        let q = try await r.service.livePrice(request(F.epWien, F.epSalzburg, Self.tomorrow))
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.explanation, "ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025")
        XCTAssertEqual(q.alternatives, [PriceAlternative(source: .liveOebb, amountEUR: 66.40, label: "Vorverkauf heute")])
        XCTAssertEqual(q.alternatives.first?.text, "Vorverkauf heute € 66,40")
        XCTAssertEqual(q.leadTime, .advanceShort)
        XCTAssertEqual(q.fetchedAt?.timeIntervalSince(F.now) ?? -1, 3, accuracy: 0.001, "after 4 requests ≥ 1 s apart (fake clock)")
        XCTAssertEqual(q.connectionID?.hasPrefix("40b209785651"), true)
        XCTAssertEqual(try r.transport.jsonBody(2)["datetimeDeparture"] as? String, "2026-10-10T08:00:00.000")
    }

    // 4
    func testPastDaySameTariffUsesTodaysPrice() async throws {
        let r = PricingRig(routes: try sameDayRoutes())
        let q = try await r.service.livePrice(request(F.epWien, F.epSalzburg, F.vienna("2026-10-08T08:00:00")))
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.explanation, "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15 · Preis von heute (gleicher Tarif)")
        XCTAssertEqual(q.travelDate, F.vienna("2026-10-08T08:00:00"))
        XCTAssertEqual(try r.transport.jsonBody(2)["datetimeDeparture"] as? String, "2026-10-09T12:25:00.000", "now + 10 min")
    }

    // 5
    func testAfterFareChangeOfferErrorFallsBackToIndexedTable() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_timetable_wien-salzburg_2026-12-15T1400"),
                                                    offers: try F.shop("shop_offers_v6_past_yesterday_wien-salzburg_2026-10-08T0800")))
        let req = request(F.epWien, F.epSalzburg, F.vienna("2026-12-15T14:00:00"))
        do {
            _ = try await r.service.livePrice(req)
            XCTFail("expected .noPrice")
        } catch let e as LiveError {
            XCTAssertEqual(e, .noPrice("offerError"))
        }
        let q = await r.service.quote(req)
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.amountEUR, 70.10, accuracy: 0.0001, "67,70 × 1.035 = 70,10")
        XCTAssertEqual(FareEstimator.euro(q.amountEUR), "€ 70,10")
        XCTAssertEqual(q.explanation, "ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025")
        XCTAssertNil(q.fetchedAt)
        XCTAssertEqual(r.count(F.offersSuffix), 1, "the offerError is negative-cached: quote() sent nothing more")
        XCTAssertEqual(try r.transport.jsonBody(2)["datetimeDeparture"] as? String, "2026-12-15T14:00:00.000")
    }

    // 6
    func testDetourGuard() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_sameday_2026-10-09_05_timetable"),
                                                    offers: try F.offers(sameDayWithSecondClassPrice: 91.50)))
        let q = try await r.service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.explanation, "ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025")
        XCTAssertEqual(q.alternatives, [PriceAlternative(source: .liveOebb, amountEUR: 91.50, label: "ÖBB-Ticketshop (andere Route)")])
        XCTAssertEqual(q.alternatives.first?.text, "ÖBB-Ticketshop € 91,50 (andere Route)")
    }

    // 7
    func testFirstClassSkipsVAOAndUsesStandardTicket() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("arch_shop_timetable_hafas-station_minimal-passenger_ibk-landeck"),
                                                    offers: try F.shop("arch_shop_offers_v6_minimal-passenger_ibk-landeck")))
        let q = try await r.service.livePrice(request(F.epInnsbruck, F.epLandeck, F.vienna("2026-10-09T13:27:00"), .first))
        XCTAssertEqual(q.amountEUR, 34.40)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.provider, "ÖBB")
        XCTAssertEqual(q.productName, "Standard-Ticket")
        XCTAssertEqual(q.travelClass, .first)
        XCTAssertEqual(q.explanation, "Standard-Ticket 1. Kl. · ÖBB-Ticketshop · abgefragt 12:15")
        XCTAssertEqual(r.count(F.vaoSuffix), 0, "VAO only prices 2nd class")
        // Table 17,60 × 1.951 = 34,30 ≠ 34,40 → listed.
        XCTAssertEqual(q.alternatives, [PriceAlternative(source: .table, amountEUR: 34.30, label: "Tarif-Tabelle")])
        let body = try r.transport.jsonBody(2)
        XCTAssertEqual(body["datetimeDeparture"] as? String, "2026-10-09T13:27:00.000")
        XCTAssertEqual((body["from"] as? NSDictionary), ["number": 8100108, "name": "Innsbruck Hauptbahnhof", "latitude": 47263530, "longitude": 11400280] as NSDictionary)
    }

    /// Same relation in 2nd class: VVT is asked first (VAO), the shop is never contacted.
    func testSecondClassInsideTirolGoesToVAO() async throws {
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_ibk-landeck"))])
        let q = try await r.service.livePrice(request(F.epInnsbruck, F.epLandeck, F.vienna("2026-10-09T13:27:00")))
        XCTAssertEqual(q.amountEUR, 22.00)
        XCTAssertEqual(q.source, .liveVerbund)
        XCTAssertEqual(q.explanation, "VVT Einzelticket · VVT 14 Zonen · Verkehrsauskunft Österreich")
        XCTAssertEqual(q.alternatives, [PriceAlternative(source: .table, amountEUR: 17.60, label: "Tarif-Tabelle")], "valuation change R5 is visible")
    }

    /// §B4.5 „{productName} · über ÖBB-Ticketshop · abgefragt {HH:mm}“: a Verbund ticket sold by the shop (VAO switched off).
    func testVerbundTicketFromTheShop() async throws {
        var noVao = LiveConfig.default
        noVao.vao.enabled = false
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_ibk-hall_2026-10-10_05_timetable"),
                                                    offers: try F.shop("shop_ibk-hall_2026-10-10_07_offers_v6_adult")), config: noVao)
        let q = try await r.service.livePrice(request(F.epInnsbruck, F.epHall, F.vienna("2026-10-10T08:00:00")))
        XCTAssertEqual(q.amountEUR, 4.70)
        XCTAssertEqual(q.source, .liveOebb, "Verbund prices do not depend on lead time: no table replacement")
        XCTAssertEqual(q.provider, "VVT")
        XCTAssertEqual(q.productName, "VVT Einzelticket")
        XCTAssertEqual(q.explanation, "VVT Einzelticket · über ÖBB-Ticketshop · abgefragt 12:15")
        XCTAssertEqual(r.count(F.vaoSuffix), 0)
        XCTAssertEqual(q.connectionID?.hasPrefix("0dc520619db6"), true, "fastest: S 4 (10 min)")
    }

    /// The Verbund path ignores the Vorteilscard [ASSUMED] and says so.
    func testVerbundTariffWithVorteilscardSaysNoReduction() async throws {
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_ibk-hall"))])
        let q = try await r.service.livePrice(request(F.epInnsbruck, F.epHall, Self.sameDay, .second, .vorteilscard))
        XCTAssertEqual(q.amountEUR, 4.70)
        XCTAssertEqual(q.discount, .none)
        XCTAssertEqual(q.explanation, "VVT Einzelticket · VVT 3 Zonen · Verkehrsauskunft Österreich · Verbundtarif · ohne Vorteilscard-Ermäßigung")
    }

    // 8
    func testVorteilscard() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_graz-wien_sparschiene_2026-10-12_05_timetable"),
                                                    offers: try F.shop("arch_shop_offers_v6_minimal-vorteilscard_graz-wien")))
        let q = try await r.service.livePrice(request(F.epGraz, F.epWien, F.vienna("2026-10-09T13:28:00"), .second, .vorteilscard))
        XCTAssertEqual(q.amountEUR, 22.20)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.discount, .vorteilscard)
        XCTAssertEqual(q.explanation, "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15 · mit Vorteilscard")
        let cards = try XCTUnwrap((try r.transport.jsonBody(2)["passengers"] as? [[String: Any]])?.first?["cards"] as? [[String: Any]])
        XCTAssertEqual(cards.first?["cardId"] as? Int, 108)
        XCTAssertEqual(try r.transport.jsonBody(3)["passengers"] as? NSArray,
                       [["type": "ADULT", "id": 1, "cards": [["name": "Vorteilscard Classic", "cardId": 108]]]] as NSArray)
        XCTAssertEqual(r.transport.recorded.filter { $0.url.path == F.offersSuffix }.count, 1)
        XCTAssertEqual(q.connectionID?.hasPrefix("79cec422cabc"), true, "fastest Graz–Wien connection")
    }

    // 9
    func testShopBlockedFallsBackToTableAndOpensCircuit() async throws {
        let r = PricingRig(routes: [.init(method: "GET", urlSuffix: F.tokenSuffix, response: try F.shop("shop_error_403_cloudflare_block_page"))])
        let req = request(F.epWien, F.epSalzburg, Self.sameDay)
        let q = await r.service.quote(req)
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.explanation, "ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025")
        let status = await r.health.status()[.oebbShop]
        XCTAssertEqual(status?.lastError, .blocked(.oebbShop))
        XCTAssertEqual(status?.openUntil?.timeIntervalSince(r.clock.now) ?? 0, 30 * 60, accuracy: 2)
        do {
            _ = try await r.service.livePrice(req)
            XCTFail("expected .circuitOpen")
        } catch let e as LiveError {
            guard case .circuitOpen(.oebbShop, _) = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(r.transport.recorded.count, 1, "blocked: never evaded, never retried")
    }

    // 10
    func testIdenticalSecondQuoteIsCached() async throws {
        let r = PricingRig(routes: try sameDayRoutes())
        let req = request(F.epWien, F.epSalzburg, Self.sameDay)
        let first = try await r.service.livePrice(req)
        let sent = r.transport.recorded.count
        XCTAssertEqual(sent, 4)
        let second = try await r.service.livePrice(req)
        let viaQuote = await r.service.quote(req)
        XCTAssertEqual(second, first)
        XCTAssertEqual(viaQuote, first)
        XCTAssertEqual(r.transport.recorded.count, sent, "0 transport requests")
        // Same relation, other time on the same day: same cache entry.
        _ = try await r.service.livePrice(request(F.epWien, F.epSalzburg, F.vienna("2026-10-09T19:00:00")))
        XCTAssertEqual(r.transport.recorded.count, sent)
        // A cleared cache asks again (warm session: timetable + offers).
        await r.service.clearCache()
        r.clock.advance(5)
        _ = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, sent + 2)
    }

    // 11
    func testThirteenSecondTransportDelayTimesOut() async throws {
        let r = PricingRig(routes: try sameDayRoutes(), wrap: { DelayingTransport($0, clock: $1, delay: 13, suffix: F.offersSuffix) })
        let req = request(F.epWien, F.epSalzburg, Self.sameDay)
        do {
            _ = try await r.service.livePrice(req)
            XCTFail("expected .timeout")
        } catch let e as LiveError {
            XCTAssertEqual(e, .timeout, "12 s budget")
        }
        let q = await r.service.quote(req)
        XCTAssertEqual(q.source, .table, "offline value with the „Offline · Tarif-Tabelle“ badge")
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertNil(q.fetchedAt)
        // Nothing was cached from the timed-out flow.
        let cached = await r.service.quote(req, allowLive: false)
        XCTAssertEqual(cached.source, .table)
    }

    /// The real-time race: a flow that never finishes ends with `.timeout` when the budget sleeper fires.
    func testRealTimeBudgetRace() async throws {
        final class Hanging: HTTPTransport, @unchecked Sendable {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw CancellationError()
            }
        }
        let clock = FakeClock(F.now)
        let health = LiveHealth(clock: clock.closure)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let shop = OebbShopClient(config: .default, transport: Hanging(), throttle: throttle, health: health, clock: clock.closure,
                                  appVersion: "1.0.0", sleeper: clock.sleeper)
        let service = LivePriceService(config: .default, shop: shop, verbund: nil, linker: nil, estimator: F.estimator, stations: F.index,
                                       cacheURL: nil, clock: clock.closure, budgetSleeper: { _ in try await Task.sleep(nanoseconds: 50_000_000) })
        let started = Date()
        do {
            _ = try await service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
            XCTFail("expected .timeout")
        } catch let e as LiveError {
            XCTAssertEqual(e, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "the hanging request was cancelled")
    }

    // 12
    func testConnectionMatchingPricesTheExactConnection() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable"),
                                                    offers: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")))
        let req = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index)
        let q = try await r.service.livePrice(req)
        let offersBody = String(decoding: try XCTUnwrap(r.transport.recorded.last?.body), as: UTF8.self)
        XCTAssertTrue(offersBody.contains("40b209785651ab5f"), offersBody)
        let timetable = try r.transport.jsonBody(2)
        XCTAssertEqual(timetable["datetimeDeparture"] as? String, "2026-10-10T08:28:00.000", "timetable at the journey's departure")
        XCTAssertEqual((timetable["from"] as? [String: Any])?["number"] as? Int, 8103000, "shop station = the ride leg's extId")
        XCTAssertEqual(q.connectionID?.hasPrefix("40b209785651ab5f"), true)
        // Advance tier with a table price: valuation basis is the day of travel (D3).
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.alternatives.first?.text, "Vorverkauf heute € 66,40")
        // Cached under the connection key: the same journey again sends nothing.
        let n = r.transport.recorded.count
        _ = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, n)
    }

    /// A tie on departure/arrival minute is broken by the train number.
    func testConnectionTieBreakByTrainNumber() throws {
        let tt = try F.timetable([
            (id: "aaa", from: 8103000, dep: "2026-10-10T08:28:00.000", to: 8100002, arr: "2026-10-10T10:53:00.000", trains: ["999"], ms: 8_700_000),
            (id: "bbb", from: 8103000, dep: "2026-10-10T08:28:00.000", to: 8100002, arr: "2026-10-10T10:53:00.000", trains: ["19962"], ms: 8_700_000),
            (id: "ccc", from: 8103000, dep: "2026-10-10T08:29:00.000", to: 8100002, arr: "2026-10-10T10:53:00.000", trains: ["19962"], ms: 8_640_000),
        ])
        let list = try XCTUnwrap(try JSONDecoder().decode(ShopTimetableResponse.self, from: tt.body).connections)
        XCTAssertEqual(LivePriceService.match(list, journey: F.rjx19962)?.id, "bbb")
        XCTAssertEqual(LivePriceService.fastest(list)?.id, "ccc")
        XCTAssertNil(LivePriceService.match(Array(list.suffix(1)), journey: F.rjx19962), "other departure minute")
    }

    // 13
    func testWestbahnJourneyFallsBackToRelation() async throws {
        let r = PricingRig(routes: try sameDayRoutes())
        let req = PriceRequest(journey: F.westbahn, travelClass: .second, discount: .none, stations: F.index)
        XCTAssertEqual(req.from.stationID, F.wienWest.id)
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.explanation, "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15 · WESTbahn-Tarif nicht verfügbar – ÖBB-Standardticket als Vergleich")
        XCTAssertTrue(q.explanation.contains("WESTbahn-Tarif nicht verfügbar"))
        XCTAssertEqual(r.count(F.timetableSuffix), 1, "the relation fallback reuses the timetable")
        XCTAssertEqual(try r.transport.jsonBody(2)["datetimeDeparture"] as? String, "2026-10-09T14:08:00.000")
        XCTAssertEqual(r.transport.recorded.count, 4)
    }

    // MARK: Station resolution, limits, privacy

    /// One extra case: the endpoint has no extId; the linker resolves it with `locmatch_innsbruck`.
    func testResolutionThroughLinker() async throws {
        let hafasRoute = FixtureTransport.Route(urlSuffix: F.hafasSuffix, response: try Fixture.hafasResponse("locmatch_innsbruck"))
        let shopRoutes = try F.shopRoutes(timetable: try F.shop("arch_shop_timetable_hafas-station_minimal-passenger_ibk-landeck"),
                                          offers: try F.shop("arch_shop_offers_v6_minimal-passenger_ibk-landeck"))
        let clock = FakeClock(F.now)
        let transport = FixtureTransport(routes: [hafasRoute] + shopRoutes)
        let (hafas, _) = HafasClient.testClient(transport, clock: clock)
        let linker = StationLinker(stations: F.index, timetable: hafas, vao: nil, cacheURL: nil, clock: clock.closure)
        let health = LiveHealth(clock: clock.closure)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let shop = OebbShopClient(config: .default, transport: transport, throttle: throttle, health: health, clock: clock.closure,
                                  appVersion: "1.0.0", sleeper: clock.sleeper)
        let service = LivePriceService(config: .default, shop: shop, verbund: nil, linker: linker, estimator: F.estimator,
                                       stations: F.index, cacheURL: nil, clock: clock.closure)
        let ibk = PriceEndpoint(station: F.innsbruck)
        XCTAssertNil(ibk.hafasExtId)
        let q = try await service.livePrice(request(ibk, F.epLandeck, F.vienna("2026-10-09T13:27:00"), .first))
        XCTAssertEqual(q.amountEUR, 34.40)
        XCTAssertEqual(transport.recorded.first?.url.host, "fahrplan.oebb.at", "one HAFAS LocMatch")
        let timetable = try XCTUnwrap(transport.recorded.first { $0.url.path == F.timetableSuffix })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: timetable.body!) as? [String: Any])
        XCTAssertEqual((body["from"] as? [String: Any])?["number"] as? Int, 8100108)
    }

    /// Worst case: VAO says NA (Verbund border) and the shop session is cold → 1 + 4 = 5 requests, never more.
    func testWorstCaseRequestCountIsFive() async throws {
        let routes = [FixtureTransport.Route(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_wien-salzburg"))] + (try sameDayRoutes())
        let r = PricingRig(routes: routes)
        // Wien Hbf → St. Pölten: both VOR by station id, so VAO is asked first.
        let q = try await r.service.livePrice(request(F.epWien, F.epStPoelten, Self.sameDay))
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(r.transport.recorded.count, 5)
        XCTAssertLessThanOrEqual(r.transport.recorded.count, LivePriceService.maxRequestsPerQuote)
        XCTAssertEqual(r.paths.first, "anachb.vor.at/hamm/gate")
        // NA is negative-cached for 24 h: another day-time on the same day skips VAO (and the relation hits the cache).
        let n = r.transport.recorded.count
        _ = try await r.service.livePrice(request(F.epWien, F.epStPoelten, Self.sameDay, .second, .vorteilscard))
        XCTAssertEqual(r.count(F.vaoSuffix), 1, "VAO NA cached")
        XCTAssertGreaterThan(r.transport.recorded.count, n)

        // Endpoints without extIds and without a linker: VAO + session + 2 name lookups = 5; timetable and offers would be
        // 7 → stopped before sending anything more, then offline.
        let lookups = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_wien-salzburg")),
                                          .init(method: "GET", urlSuffix: "count=5", response: try F.shop("shop_wien-salzburg_2026-10-10_03_stations_0"))]
                                 + (try sameDayRoutes()))
        let bare = request(PriceEndpoint(station: F.wienHbf), PriceEndpoint(station: F.wrNeustadt), Self.sameDay)
        do {
            _ = try await lookups.service.livePrice(bare)
            XCTFail("expected a budget stop")
        } catch let e as LiveError {
            guard case .noPrice = e else { return XCTFail("\(e)") }
        }
        XCTAssertEqual(lookups.transport.recorded.count, 5, "\(lookups.paths)")
        XCTAssertEqual(lookups.count(F.timetableSuffix), 0, "stopped before timetable/offers")
        // Next quote: VAO NA, the session and both shop stations are cached → only timetable + offers.
        let next = await lookups.service.quote(bare)
        XCTAssertTrue(next.isLive)
        XCTAssertEqual(lookups.transport.recorded.count, 7)
        XCTAssertEqual(Array(lookups.paths.suffix(2)), [F.timetableSuffix, F.offersSuffix])
    }

    func testKillSwitchAndDisabledProvidersMakeNoRequests() async throws {
        var kill = LiveConfig.default
        kill.killSwitch = true
        var both = LiveConfig.default
        both.shop.enabled = false
        both.vao.enabled = false
        for config in [kill, both] {
            let r = PricingRig(routes: [], config: config)
            do {
                _ = try await r.service.livePrice(request(F.epInnsbruck, F.epHall, Self.sameDay))
                XCTFail("expected .disabled")
            } catch let e as LiveError {
                XCTAssertEqual(e, .disabled(.oebbShop))
            }
            let q = await r.service.quote(request(F.epWien, F.epSalzburg, Self.sameDay))
            XCTAssertEqual(q.source, .table)
            XCTAssertTrue(r.transport.recorded.isEmpty)
        }
        // allowLive: false never touches the network even when everything is enabled.
        let r = PricingRig(routes: [])
        let q = await r.service.quote(request(F.epWien, F.epSalzburg, Self.sameDay), allowLive: false)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertTrue(r.transport.recorded.isEmpty)
        // Shop off, VAO on, not inside one Verbund: disabled, no request.
        var shopOff = LiveConfig.default
        shopOff.shop.enabled = false
        let s = PricingRig(routes: [], config: shopOff)
        do {
            _ = try await s.service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
            XCTFail("expected .disabled")
        } catch let e as LiveError {
            XCTAssertEqual(e, .disabled(.oebbShop))
        }
        XCTAssertTrue(s.transport.recorded.isEmpty)
    }

    /// Tokens never touch the disk (W-B acceptance 3).
    func testPriceCacheFileHoldsNoTokens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-prices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Live/prices.json")
        let r = PricingRig(routes: try sameDayRoutes(), cacheURL: url)
        _ = try await r.service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
        await r.service.flushCache()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("67.7"), text)
        XCTAssertFalse(text.contains("AccessToken"))
        XCTAssertFalse(text.contains("eyJ"))
        XCTAssertFalse(text.contains(F.token))
        XCTAssertFalse(text.lowercased().contains("token"))
        // A new service instance reads the file: no request.
        let again = PricingRig(routes: [], cacheURL: url)
        let q = try await again.service.livePrice(request(F.epWien, F.epSalzburg, Self.sameDay))
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertTrue(again.transport.recorded.isEmpty)
    }

    func testCatalogReloadDropsTableQuotes() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable"),
                                                    offers: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")))
        let req = request(F.epWien, F.epSalzburg, Self.tomorrow)
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.source, .table)
        let n = r.transport.recorded.count
        await r.service.update(estimator: F.estimator)
        r.clock.advance(5)
        _ = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, n + 2, "table quote recomputed after the catalog reload")
    }

    func testOfflineQuoteChain() async {
        let r = PricingRig(routes: [])
        let table = await r.service.offlineQuote(request(F.epWien, F.epSalzburg, Self.sameDay))
        XCTAssertEqual(table.source, .table)
        XCTAssertEqual(table.amountEUR, 67.70)
        XCTAssertNil(table.provider, "nil offline")
        XCTAssertEqual(table.productName, "Standard-Ticket")
        let geo = await r.service.offlineQuote(request(PriceEndpoint(name: "Irgendwo", coordinate: GeoPoint(latitude: 47.5, longitude: 13.0)),
                                                       PriceEndpoint(name: "Anderswo", coordinate: GeoPoint(latitude: 47.8, longitude: 13.04)), Self.sameDay))
        XCTAssertEqual(geo.source, .distanceModel)
        XCTAssertGreaterThan(geo.amountEUR, 0)
        let none = await r.service.offlineQuote(request(PriceEndpoint(name: "A"), PriceEndpoint(name: "B"), Self.sameDay))
        XCTAssertEqual(none.amountEUR, 0)
        XCTAssertEqual(none.source, .distanceModel)
        XCTAssertEqual(none.explanation, "Kein Preis verfügbar – bitte eintragen")
        XCTAssertTrue(r.transport.recorded.isEmpty)
    }

    func testQuoteKeepsCatalogCityFare() async throws {
        let wien = CityFare(id: "wien", name: "Wien", singleTicketEUR: 3.2, latitude: 48.2082, longitude: 16.3738, radiusKm: 11)
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_wien-kernzone_wienhbf-wienwest"))],
                           estimator: FareEstimator(catalog: F.catalog(cityFares: [wien]), relations: F.relations))
        let q = await r.service.quote(PriceRequest(from: PriceEndpoint(station: F.karlsplatz), to: PriceEndpoint(station: F.wienHbf),
                                                   departure: Self.sameDay, mode: .metro))
        XCTAssertEqual(q.source, .cityTicket)
        XCTAssertEqual(q.amountEUR, 3.2)
        XCTAssertTrue(r.transport.recorded.isEmpty, "§B5 open item: the catalog stays authoritative for city hops")
    }

    func testMostInformativeError() {
        XCTAssertEqual(LivePriceService.mostInformative([.offline, .noPrice("NA"), .blocked(.oebbShop), .rateLimited(.vaoTariff, retryAfter: nil)]),
                       .blocked(.oebbShop))
        XCTAssertEqual(LivePriceService.mostInformative([.timeout, .offline, .rateLimited(.vaoTariff, retryAfter: 3)]), .rateLimited(.vaoTariff, retryAfter: 3))
        XCTAssertEqual(LivePriceService.mostInformative([.timeout, .noPrice("x"), .offline]), .noPrice("x"))
        XCTAssertEqual(LivePriceService.mostInformative([.timeout, .offline]), .offline)
        XCTAssertEqual(LivePriceService.mostInformative([.timeout, .http(status: 500, excerpt: "")]), .timeout)
        XCTAssertNil(LivePriceService.mostInformative([]))
    }

    func testShopPlan() async {
        let r = PricingRig(routes: [])
        let s = r.service
        let plan1 = await s.shopPlan(request(F.epWien, F.epSalzburg, F.vienna("2026-10-09T08:00:00")), now: F.now)
        XCTAssertEqual(plan1, .relation(at: F.vienna("2026-10-09T12:25:00"), tier: .travelDay, proxy: false), "earlier today → now + 10 min")
        let plan2 = await s.shopPlan(request(F.epWien, F.epSalzburg, F.vienna("2026-10-09T08:00:00")), now: F.vienna("2026-10-09T23:55:00"))
        XCTAssertEqual(plan2, .skip("Heute keine Abfahrt mehr"))
        let plan3 = await s.shopPlan(request(F.epWien, F.epSalzburg, F.vienna("2025-11-01T08:00:00")), now: F.now)
        XCTAssertEqual(plan3, .skip("Anderer Tarifzeitraum"))
        let plan4 = await s.shopPlan(request(F.epWien, F.epSalzburg, F.vienna("2026-11-20T14:00:00")), now: F.now)
        XCTAssertEqual(plan4, .relation(at: F.vienna("2026-11-20T14:00:00"), tier: .advanceLong, proxy: false))
        // A planner journey leaving within 2 minutes is priced as a relation.
        var soon = F.westbahn
        soon.legs[0].departure = StopEvent(planned: F.now.addingTimeInterval(60))
        let plan5 = await s.shopPlan(request(F.epWien, F.epSalzburg, F.now, journey: soon), now: F.now)
        XCTAssertEqual(plan5, .relation(at: F.now.addingTimeInterval(600), tier: .travelDay, proxy: false))
    }
}
