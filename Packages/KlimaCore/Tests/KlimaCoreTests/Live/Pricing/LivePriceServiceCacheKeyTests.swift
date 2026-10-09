import XCTest
@testable import KlimaCore

/// Review 2026-10-09: cache entries must not leak between requests that are priced differently – a failed train vs. the
/// rest of the day, 1st vs. 2nd class, a journey with vs. without via stops.
final class LivePriceServiceCacheKeyTests: XCTestCase {
    typealias F = PricingFixtures

    /// `offerError` of one planner connection (e.g. sales closed shortly before departure) blocks only that train: the
    /// relation price of the same day is still fetched live.
    func testConnectionOfferErrorBlocksOnlyThatTrain() async throws {
        let offers = FixtureTransport.Route(urlSuffix: F.offersSuffix, response: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult"),
                                            sequence: [try F.shop("shop_offers_v6_past_yesterday_wien-salzburg_2026-10-08T0800"),
                                                       try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")])
        let r = PricingRig(routes: try F.sessionRoutes() + [
            .init(urlSuffix: F.timetableSuffix, response: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable")), offers,
        ])
        let train = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index)
        do {
            _ = try await r.service.livePrice(train)
            XCTFail("offerError must not give a price")
        } catch LiveError.noPrice(let reason) {
            XCTAssertEqual(reason, "offerError")
        }
        // Same relation and day, no journey: not blocked by the train's negative entry.
        let relation = PriceRequest(from: F.epWien, to: F.epSalzburg, departure: F.vienna("2026-10-10T08:00:00"), mode: .train)
        XCTAssertEqual(relation.from.stationID, train.from.stationID)
        XCTAssertEqual(relation.to.stationID, train.to.stationID)
        let q = try await r.service.livePrice(relation)
        XCTAssertEqual(q.source, .table)
        XCTAssertEqual(q.amountEUR, 67.70)
        XCTAssertEqual(q.alternatives.first?.text, "Vorverkauf heute € 66,40")
        XCTAssertEqual(r.count(F.offersSuffix), 2)
        // The failed train itself stays negative-cached (no new request).
        let n = r.transport.recorded.count
        await XCTAssertThrowsLiveError(try await r.service.livePrice(train))
        XCTAssertEqual(r.transport.recorded.count, n)
    }

    /// 1st class without a Standard-Ticket (only 2nd class offered) does not block the 2nd-class price.
    func testFirstClassNoPriceDoesNotBlockSecondClass() async throws {
        let offers = FixtureTransport.Route(urlSuffix: F.offersSuffix, response: try F.shop("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult"),
                                            sequence: [try F.offers(second: 59.90),
                                                       try F.shop("shop_wien-salzburg_sameday_2026-10-09_07_offers_v6_adult")])
        let r = PricingRig(routes: try F.sessionRoutes() + [
            .init(urlSuffix: F.timetableSuffix, response: try F.shop("shop_wien-salzburg_sameday_2026-10-09_05_timetable")), offers,
        ])
        let at = F.vienna("2026-10-09T16:00:00")
        let first = PriceRequest(from: F.epWien, to: F.epSalzburg, departure: at, mode: .train, travelClass: .first)
        do {
            _ = try await r.service.livePrice(first)
            XCTFail("no 1st-class Standard-Ticket")
        } catch LiveError.noPrice(let reason) {
            XCTAssertEqual(reason, "kein Standard-Ticket")
        }
        let second = PriceRequest(from: F.epWien, to: F.epSalzburg, departure: at, mode: .train, travelClass: .second)
        let q = try await r.service.livePrice(second)
        XCTAssertEqual(q.source, .liveOebb)
        XCTAssertEqual(q.amountEUR, 67.70)
    }

    /// The same journey priced with and without a via stop: two different quotes, two cache entries.
    func testViaAndDirectQuotesOfTheSameJourneyAreCachedApart() async throws {
        let r = PricingRig(routes: try F.shopRoutes(timetable: try F.shop("shop_wien-salzburg_2026-10-10_05_timetable"),
                                                    offers: try F.shop("shop_wien-salzburg_2026-10-10_07_offers_v6_adult")))
        let direct = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index)
        let d = try await r.service.livePrice(direct)
        XCTAssertFalse(d.explanation.contains("über"), d.explanation)
        let stPoelten = ViaStop(location: F.location("8100008", "St. Pölten Hauptbahnhof", 48.20819, 15.62404))
        let via = PriceRequest(journey: F.rjx19962, travelClass: .second, discount: .none, stations: F.index, via: [stPoelten])
        let n = r.transport.recorded.count
        let v = try await r.service.livePrice(via)
        XCTAssertGreaterThan(r.transport.recorded.count, n, "the direct quote must not answer the via request")
        XCTAssertTrue(v.explanation.hasSuffix(" · über St. Pölten Hbf"), v.explanation)
        // Both are cached now, each under its own key.
        let m = r.transport.recorded.count
        let d2 = try await r.service.livePrice(direct)
        let v2 = try await r.service.livePrice(via)
        XCTAssertEqual(r.transport.recorded.count, m)
        XCTAssertEqual(d2, d)
        XCTAssertEqual(v2, v)
    }

    /// Via names in explanations are display names (one space after „St.“, „Hbf“, no trailing „Bahnhof“) – the same
    /// names the planner cards show.
    func testViaNamesAreDisplayNames() {
        XCTAssertEqual(StationLinker.displayName("St. Pölten Hauptbahnhof"), "St. Pölten Hbf")
        XCTAssertEqual(StationLinker.displayName("St.Anton am Arlberg Bahnhof"), "St. Anton am Arlberg")
        XCTAssertEqual(StationLinker.displayName("Wien Hbf (Bahnsteige 3-12)"), "Wien Hbf")
        XCTAssertEqual(ViaPricing.name(PriceEndpoint(name: "St. Pölten Hauptbahnhof")), "St. Pölten Hbf")
        XCTAssertEqual(ViaPricing.name(PriceEndpoint(name: "Feldkirch Bahnhof")), "Feldkirch")
    }
}

func XCTAssertThrowsLiveError<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("expected a LiveError", file: file, line: line)
    } catch is LiveError {
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}
