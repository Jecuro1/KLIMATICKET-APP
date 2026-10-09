// Step-0 contract tests (owned by WP-A afterwards). Keep green; extend, never weaken.
import XCTest
@testable import KlimaCore

final class LiveContractTests: XCTestCase {
    struct Case: Decodable { let label: String; let family: String; let expected: String; let leg: CoverageLegInput }
    struct File: Decodable { let cases: [Case] }

    func testSyntheticCoverageCasesDecode() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/OEBB/coverage/synthetic_cases", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.cases.count, 14)
        XCTAssertEqual(file.cases[0].leg.from.state, "W")
        XCTAssertNotNil(CoverageResult(rawValue: file.cases[0].expected))
    }

    func testDomainRoundTripAndIDs() throws {
        let ibk = Location.station(extId: "8100108", name: "Innsbruck Hbf")
        let sta = Location.station(extId: "8100064", name: "St. Anton am Arlberg Bahnhof")
        let dep = Date(timeIntervalSince1970: 1_791_542_000)
        let leg = Leg(id: "C-0:0", kind: .ride, origin: sta, destination: ibk,
                      departure: StopEvent(planned: dep, realtime: dep.addingTimeInterval(120), plannedPlatform: Platform(text: "3", kind: .track)),
                      arrival: StopEvent(planned: dep.addingTimeInterval(4200)),
                      line: Line(name: "RJX 19915", category: "RJX", trainNumber: "19915", productClass: 1, mode: .train))
        let j = Journey(legs: [leg], durationSeconds: 4200, changes: 0, refreshToken: "¶HKI¶T$…")
        let data = try JSONEncoder().encode(j)
        let back = try JSONDecoder().decode(Journey.self, from: data)
        XCTAssertEqual(back, j)
        XCTAssertEqual(j.departure?.delaySeconds, 120)
        XCTAssertEqual(j.id, "\(Int(dep.timeIntervalSince1970 / 60))|19915|8100108")
        XCTAssertEqual(ProductMask.rail.rawValue, 4157)
        XCTAssertEqual(ProductMask.klimaTicket.rawValue, 4991)
        XCTAssertEqual(LiveConfig.default.hafas.ver, "1.88")
        let cfg = try JSONDecoder().decode(LiveConfig.self, from: JSONEncoder().encode(LiveConfig.default))
        XCTAssertEqual(cfg, .default)
    }

    func testLeadTimeTier() {
        let cal = Calendar.vienna
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 30))!
        XCTAssertEqual(LeadTimeTier.tier(departure: now.addingTimeInterval(600), now: now), .travelDay)
        XCTAssertEqual(LeadTimeTier.tier(departure: now.addingTimeInterval(3600), now: now), .advanceShort)
        XCTAssertEqual(LeadTimeTier.tier(departure: now.addingTimeInterval(20 * 86400), now: now), .advanceLong)
    }

    struct NoLive: LivePriceProvider {
        func livePrice(_ request: PriceRequest) async throws -> PriceQuote { throw LiveError.disabled(.oebbShop) }
    }

    func testEstimateLiveFallsBackOffline() async {
        let est = FareEstimator(catalog: TariffCatalog(version: 1, updatedAt: "2026-01-01", products: [], fareModel: .fallback, cityFares: [],
                                                       kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.47, emissions: .fallback))
        let a = Station(id: "at:49:1349", name: "Wien Hbf", lat: 48.18519, lon: 16.37641, state: "W")
        let b = Station(id: "at:45:50002", name: "Salzburg Hbf", lat: 47.81306, lon: 13.04513, state: "S")
        let e = await est.estimateLive(from: a, to: b, mode: .train, live: NoLive())
        XCTAssertEqual(e.method, .distanceTariff)
        XCTAssertNil(e.quote)
    }
}
