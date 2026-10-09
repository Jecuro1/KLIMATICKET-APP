import XCTest
@testable import KlimaCore

/// Via stops in price requests (owner request 2026-10-09: „man sollte auch VIA Halte rein machen“): one ticket where a
/// back end supports the via route, else consecutive segments with an honest explanation.
final class LivePriceServiceViaTests: XCTestCase {
    typealias F = PricingFixtures

    /// Innsbruck Hbf → Bregenz via Feldkirch (min 10) from the live-recorded W-A fixture: RJ 13478 → S 1, 2026-10-10.
    func viaJourney() throws -> Journey {
        let page = try HafasCodec.journeyPage(from: try Fixture.data("hafas/tripsearch_via_feldkirch_dwell_ibk_bregenz.response"))
        return try XCTUnwrap(page.journeys.first)
    }

    static let feldkirchStop = ViaStop(location: Location.station(extId: "8100197", name: "Feldkirch Bahnhof"), minimumDwellMinutes: 10)

    func testJourneyFixtureShape() throws {
        let j = try viaJourney()
        XCTAssertEqual(j.rideLegs.map { $0.line?.trainNumber }, ["13478", "5644"])
        XCTAssertTrue(j.passes(Self.feldkirchStop.location))
        let r = PriceRequest(journey: j, travelClass: .second, discount: .none, stations: F.index, via: [Self.feldkirchStop])
        XCTAssertEqual(r.from.stationID, F.innsbruck.id)
        XCTAssertEqual(r.to.stationID, F.bregenz.id)
        XCTAssertEqual(r.via.first?.hafasExtId, "8100197")
        XCTAssertEqual(r.departure, F.vienna("2026-10-10T09:16:00"))
    }

    /// All points in one Verbund: VAO prices the via route as one Verbund ticket (`viaLocL`), 1 request.
    func testVAOViaRouteInsideOneVerbund() async throws {
        let r = PricingRig(routes: [.init(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_ibk-hall"))])
        let req = PriceRequest(from: F.epInnsbruck, to: F.epHall, departure: F.vienna("2026-10-09T17:00:00"), via: [F.epRum])
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.amountEUR, 4.70)
        XCTAssertEqual(q.source, .liveVerbund)
        XCTAssertEqual(q.explanation, "VVT Einzelticket · VVT 3 Zonen · Verkehrsauskunft Österreich · über Rum")
        XCTAssertEqual(r.transport.recorded.count, 1)
        let body = try XCTUnwrap((try r.transport.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        XCTAssertEqual(body["viaLocL"] as? NSArray, [["loc": ["lid": "A=1@L=470118600@", "type": "S"]]] as NSArray)
        // Cached under the via key; the direct relation is a different entry.
        _ = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, 1)
    }

    /// Planner journey + via: the shop lists the exact connection (same departure and arrival minute) → one ticket.
    func testExactShopConnectionOfViaJourney() async throws {
        let j = try viaJourney()
        let timetable = try F.timetable([
            (id: "exact000", from: 8100108, dep: "2026-10-10T09:16:00.000", to: 8100090, arr: "2026-10-10T12:14:00.000", trains: ["13478", "5644"], ms: 10_680_000),
        ])
        let r = PricingRig(routes: try F.shopRoutes(timetable: timetable, offers: try F.offers(second: 41.30)))
        let req = PriceRequest(journey: j, travelClass: .second, discount: .none, stations: F.index, via: [Self.feldkirchStop])
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.amountEUR, 41.30)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.connectionID, "exact000")
        XCTAssertEqual(q.explanation, "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15 · Vorverkaufspreis (heute gekauft) · über Feldkirch Bahnhof")
        XCTAssertEqual(r.transport.recorded.count, 4)
        XCTAssertEqual(q.shopURL, j.shopURL, "HAFAS trfRes link preferred")
    }

    /// Planner journey + via with a stay: the shop has the same through train (RJ 13478 runs on to Bregenz) → one
    /// through Standard-Ticket, break of journey at Feldkirch allowed.
    func testThroughTrainServingTheViaStop() async throws {
        let j = try viaJourney()
        let timetable = try F.timetable([
            (id: "other000", from: 8100108, dep: "2026-10-10T09:16:00.000", to: 8100090, arr: "2026-10-10T11:50:00.000", trains: ["999"], ms: 9_240_000),
            (id: "through0", from: 8100108, dep: "2026-10-10T09:16:00.000", to: 8100090, arr: "2026-10-10T11:43:00.000", trains: ["13478"], ms: 8_820_000),
        ])
        let r = PricingRig(routes: try F.shopRoutes(timetable: timetable, offers: try F.offers(second: 41.30)))
        let req = PriceRequest(journey: j, travelClass: .second, discount: .none, stations: F.index, via: [Self.feldkirchStop])
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.connectionID, "through0")
        XCTAssertEqual(q.amountEUR, 41.30)
        XCTAssertEqual(q.explanation,
                       "Standard-Ticket 2. Kl. · ÖBB-Ticketshop · abgefragt 12:15 · Vorverkaufspreis (heute gekauft) · über Feldkirch Bahnhof (durchgehendes Ticket)")
        let timetableBody = try r.transport.jsonBody(2)
        XCTAssertEqual(timetableBody["datetimeDeparture"] as? String, "2026-10-10T09:16:00.000")
        XCTAssertEqual((timetableBody["to"] as? [String: Any])?["number"] as? Int, 8100090)
        XCTAssertTrue(String(decoding: r.transport.recorded[3].body!, as: UTF8.self).contains("through0"))
        XCTAssertNil(LivePriceService.throughMatch(try JSONDecoder().decode(ShopTimetableResponse.self, from: timetable.body).connections ?? [],
                                                   journey: j, via: [F.epBregenz.with(extId: "8100999")]),
                     "a via stop no train of the connection serves → no through ticket")
    }

    /// No journey: the via route is priced as consecutive segments, each through the normal chain (shop, VAO), ≤ 5 requests.
    func testSegmentsWhenNoSingleTicketIsPossible() async throws {
        let routes = [FixtureTransport.Route(urlSuffix: F.vaoSuffix, response: try F.vao("vao_tripsearch_tariff_bregenz-feldkirch"))]
            + (try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_sameday_2026-10-09_05_timetable"),
                                offers: try F.shop("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult")))
        let r = PricingRig(routes: routes)
        let req = PriceRequest(from: F.epInnsbruck, to: F.epBregenz, departure: F.vienna("2026-10-09T16:00:00"), via: [F.epFeldkirch])
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(q.amountEUR, 77.30, accuracy: 0.0001)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.provider, "ÖBB + VVV")
        XCTAssertEqual(q.productName, "Standard-Ticket + VVV Vollpreis - 60/120 Minuten")
        XCTAssertEqual(q.explanation,
                       "Summe von 2 Teilstrecken über Feldkirch: Innsbruck Hauptbahnhof – Feldkirch € 67,70 (ÖBB) + Feldkirch – Bregenz € 9,60 (VVV)")
        XCTAssertEqual(r.paths, [F.tokenSuffix, F.initSuffix, F.timetableSuffix, F.offersSuffix, "anachb.vor.at/hamm/gate"])
        XCTAssertLessThanOrEqual(r.transport.recorded.count, LivePriceService.maxRequestsPerQuote)
        XCTAssertNotNil(q.fetchedAt)
        // Cached as a whole and per segment.
        _ = try await r.service.livePrice(req)
        let seg = try await r.service.livePrice(PriceRequest(from: F.epFeldkirch, to: F.epBregenz, departure: F.vienna("2026-10-09T18:00:00")))
        XCTAssertEqual(seg.amountEUR, 9.60)
        XCTAssertEqual(r.transport.recorded.count, 5)
    }

    /// A segment the budget cannot cover keeps its offline price; the result is honest about it and not cached.
    func testSegmentOverBudgetStaysOffline() async throws {
        // Both segments need the shop (Graz STV → Wien VOR → Salzburg SVV): 4 + 2 > 5 → the second segment stays offline.
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_graz-wien_sparschiene_2026-10-12_05_timetable"),
                                                    offers: try F.offers(second: 45.00)))
        let req = PriceRequest(from: F.epGraz, to: F.epSalzburg, departure: F.vienna("2026-10-09T16:00:00"), via: [F.epWien])
        let q = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, 4, "the second segment would need 2 more → not sent")
        XCTAssertEqual(q.source, .table, "not every part is live")
        XCTAssertEqual(q.amountEUR, 112.70, accuracy: 0.0001)
        XCTAssertEqual(q.explanation,
                       "Summe von 2 Teilstrecken über Wien Hauptbahnhof: Graz Hauptbahnhof – Wien Hauptbahnhof € 45,00 (ÖBB) + Wien Hauptbahnhof – Salzburg Hauptbahnhof € 67,70 (Tarif-Tabelle)")
        let n = r.transport.recorded.count
        r.clock.advance(70)
        let again = try await r.service.livePrice(req)
        XCTAssertEqual(r.transport.recorded.count, n + 2, "not cached; segment 1 is, segment 2 now fits (warm session)")
        XCTAssertEqual(again.source, .liveOebb)
        XCTAssertEqual(again.amountEUR, 90.00, accuracy: 0.0001)
    }

    func testOfflineViaQuoteSumsSegments() async {
        let r = PricingRig(routes: [])
        let q = await r.service.offlineQuote(PriceRequest(from: F.epGraz, to: F.epSalzburg, departure: F.now, via: [F.epWien]))
        XCTAssertEqual(q.amountEUR, 112.00, accuracy: 0.0001)
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.explanation,
                       "Summe von 2 Teilstrecken über Wien Hauptbahnhof: Graz Hauptbahnhof – Wien Hauptbahnhof € 44,30 (Tarif-Tabelle) + Wien Hauptbahnhof – Salzburg Hauptbahnhof € 67,70 (Tarif-Tabelle)")
        XCTAssertNil(q.fetchedAt)
        // No direct table price for Graz → Salzburg in the excerpt: no alternative.
        XCTAssertTrue(q.alternatives.isEmpty)
        // Wien → Salzburg via Graz: a segment without table price makes the sum an estimate; the direct table price is offered.
        let detour = await r.service.offlineQuote(PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.now, via: [F.epGraz]))
        XCTAssertEqual(detour.source, .distanceModel)
        XCTAssertTrue(detour.explanation.contains("€ 44,30 (Tarif-Tabelle) + Graz Hauptbahnhof – Salzburg Hauptbahnhof"), detour.explanation)
        XCTAssertTrue(detour.explanation.hasSuffix("(Schätzung)"), detour.explanation)
        XCTAssertEqual(detour.alternatives, [PriceAlternative(source: .table, amountEUR: 67.70, label: "Direkt ohne Zwischenhalt (Tarif-Tabelle)")])
        XCTAssertEqual(detour.alternatives.first?.text, "Direkt ohne Zwischenhalt € 67,70 (Tarif-Tabelle)")
        // Via stops equal to an end are ignored; a free-text via without coordinates falls back to the direct relation.
        let same = await r.service.offlineQuote(PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.now, via: [F.epWien]))
        XCTAssertEqual(same.amountEUR, 67.70)
        let blind = await r.service.offlineQuote(PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.now, via: [PriceEndpoint(name: "Irgendwo")]))
        XCTAssertEqual(blind.amountEUR, 67.70)
        XCTAssertTrue(r.transport.recorded.isEmpty)
    }

    func testAtMostTwoViaStops() {
        let r = PriceRequest(from: F.epGraz, to: F.epSalzburg, departure: F.now, via: [F.epWien, F.epStPoelten, F.epInnsbruck])
        XCTAssertEqual(LivePriceService.normalized(r).via, [F.epWien, F.epStPoelten])
        XCTAssertEqual(ViaPricing.points(r).count, 4)
    }
}

private extension PriceEndpoint {
    func with(extId: String) -> PriceEndpoint {
        PriceEndpoint(stationID: nil, name: name, coordinate: nil, hafasExtId: extId)
    }
}
