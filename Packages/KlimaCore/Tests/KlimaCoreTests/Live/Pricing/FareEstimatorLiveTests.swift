import XCTest
@testable import KlimaCore

/// `FareEstimator.estimateLive` (SPEC §B7, §D2 WP-B 6).
final class FareEstimatorLiveTests: XCTestCase {
    typealias F = PricingFixtures

    func quote(_ source: PriceSource, _ amount: Double = 12.3) -> PriceQuote {
        PriceQuote(amountEUR: amount, source: source, provider: "VVT", travelDate: F.now, fetchedAt: F.now, explanation: "live \(source.rawValue)")
    }

    func testSourceToMethodMapping() async {
        let expected: [PriceSource: FareEstimate.Method] = [
            .liveOebb: .liveOebb, .liveVerbund: .liveVerbund, .table: .officialTable, .cityTicket: .cityTicket,
            .distanceModel: .distanceTariff, .manual: .manual,
        ]
        XCTAssertEqual(Set(expected.keys), Set(PriceSource.allCases))
        for (source, method) in expected {
            let stub = StubPriceProvider(.success(quote(source)))
            let e = await F.estimator.estimateLive(from: F.innsbruck, to: F.hall, mode: .train, date: F.now, live: stub)
            XCTAssertEqual(e.method, method, "\(source)")
            XCTAssertEqual(e.fareEUR, 12.3)
            XCTAssertEqual(e.explanation, "live \(source.rawValue)")
            XCTAssertEqual(e.quote, quote(source))
            XCTAssertEqual(stub.calls.count, 1)
            XCTAssertEqual(stub.calls.first?.from.stationID, F.innsbruck.id)
            XCTAssertGreaterThan(e.distanceKm, 0, "distance from the offline estimate")
        }
    }

    func testCityTicketNeverCallsLive() async {
        let wien = CityFare(id: "wien", name: "Wien", singleTicketEUR: 3.2, latitude: 48.2082, longitude: 16.3738, radiusKm: 11)
        let est = FareEstimator(catalog: F.catalog(cityFares: [wien]), relations: F.relations)
        let stub = StubPriceProvider(.success(quote(.liveVerbund, 3.0)))
        let e = await est.estimateLive(from: F.karlsplatz, to: F.wienHbf, mode: .metro, date: F.now, live: stub)
        XCTAssertEqual(e.method, .cityTicket)
        XCTAssertEqual(e.fareEUR, 3.2, "catalog Kernzone fare stays authoritative (§B5 open item)")
        XCTAssertTrue(stub.calls.isEmpty)
    }

    func testNilProviderAndFailureGiveOffline() async {
        let offline = F.estimator.estimate(from: F.wienHbf, to: F.salzburg, mode: .train, date: F.now)
        XCTAssertEqual(offline.method, .officialTable)
        let none = await F.estimator.estimateLive(from: F.wienHbf, to: F.salzburg, mode: .train, date: F.now, live: nil)
        XCTAssertEqual(none, offline)
        XCTAssertNil(none.quote)
        let failing = StubPriceProvider(.failure(.offline))
        let failed = await F.estimator.estimateLive(from: F.wienHbf, to: F.salzburg, mode: .train, date: F.now, live: failing)
        XCTAssertEqual(failed, offline)
        XCTAssertEqual(failing.calls.count, 1)
    }

    func testViaOverload() async {
        // Without via stops it is the plain call.
        let plain = await F.estimator.estimateLive(from: F.wienHbf, to: F.salzburg, via: [], mode: .train, date: F.now, live: nil)
        XCTAssertEqual(plain, F.estimator.estimate(from: F.wienHbf, to: F.salzburg, mode: .train, date: F.now))
        // Offline via route = sum of the segments.
        let via = await F.estimator.estimateLive(from: F.graz, to: F.salzburg, via: [F.wienHbf], mode: .train, date: F.now, live: nil)
        XCTAssertEqual(via.fareEUR, 44.30 + 67.70, accuracy: 0.001)
        XCTAssertEqual(via.method, .officialTable)
        XCTAssertEqual(via.explanation, "Summe von 2 Teilstrecken über Wien Hauptbahnhof: Graz Hauptbahnhof – Wien Hauptbahnhof € 44,30 (Tarif-Tabelle) + Wien Hauptbahnhof – Salzburg Hauptbahnhof € 67,70 (Tarif-Tabelle)")
        // Live: the request carries the via stop.
        let stub = StubPriceProvider(.success(quote(.liveOebb, 99)))
        let live = await F.estimator.estimateLive(from: F.graz, to: F.salzburg, via: [F.wienHbf, F.graz], mode: .train, date: F.now, live: stub)
        XCTAssertEqual(live.fareEUR, 99)
        XCTAssertEqual(stub.calls.first?.via.map(\.stationID), [F.wienHbf.id], "ends are not via stops")
    }
}
