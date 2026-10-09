// Opt-in live checks against the real ÖBB ticket shop and VAO (SPEC §D3 Prices). Never part of CI:
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --filter LiveSmoke --no-parallel
// Budget ≤ 20 requests per run through the real RequestThrottle (one shared shop session: 2 + 2 per priced relation);
// structure is asserted, not exact values. A .blocked / .rateLimited / .offline / .circuitOpen result (e.g. the shop's
// Cloudflare filter, Risk R1) skips with the reason – it never fails.
import Foundation
import XCTest
@testable import KlimaCore

final class PriceLiveTests: XCTestCase {
    static let enabled = ProcessInfo.processInfo.environment["KB_LIVE_TESTS"] == "1"
    static let throttle = RequestThrottle()
    static let health = LiveHealth()
    static let transport = URLSessionTransport()
    static let shop = OebbShopClient(config: .default, transport: transport, throttle: throttle, health: health, appVersion: "live-test")
    static let verbund = VerbundTariffClient(config: .default, transport: transport, throttle: throttle, health: health, appVersion: "live-test")

    // Shop station objects as in SPEC §B3.2 (HAFAS extId, name, µdeg).
    static let innsbruck = OebbShopClient.Station(number: 8100108, name: "Innsbruck Hbf", latitude: 47263040, longitude: 11401020)
    static let landeck = OebbShopClient.Station(number: 8100063, name: "Landeck-Zams Bahnhof", latitude: 47140260, longitude: 10566610)
    static let wien = OebbShopClient.Station(number: 1290401, name: "Wien Hbf (U)", latitude: 48184986, longitude: 16377950)
    static let salzburg = OebbShopClient.Station(number: 8100002, name: "Salzburg Hbf", latitude: 47813057, longitude: 13045856)

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.enabled, "set KB_LIVE_TESTS=1 for live checks")
    }

    func live<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let e as LiveError {
            switch e {
            case .blocked, .rateLimited, .offline, .circuitOpen, .network, .timeout:
                throw XCTSkip("live service not usable here: \(e)")
            case .noPrice(let reason):
                throw XCTSkip("nothing sellable right now: \(reason)")
            default:
                throw e
            }
        }
    }

    /// Departure in one hour (a same-day relation price).
    var departure: Date { Date().addingTimeInterval(3600) }

    func shopFare(_ from: OebbShopClient.Station, _ to: OebbShopClient.Station, _ cls: TravelClass) async throws -> ShopFare {
        let at = departure
        let list = try await live { try await Self.shop.timetable(from: from, to: to, departure: at, discount: .none) }
        let fastest = try XCTUnwrap(LivePriceService.fastest(list))
        let offers = try await live { try await Self.shop.offers(connectionID: try XCTUnwrap(fastest.id), departure: at, discount: .none) }
        return try XCTUnwrap(ShopOfferSelector.standardFare(offers, travelClass: cls), "no FLEX ONEWAY offer")
    }

    // 1 + 2: Innsbruck → Landeck: 2nd class is the VVT ticket, 1st class the ÖBB Standard-Ticket.
    func testShopInnsbruckLandeck() async throws {
        let second = try await shopFare(Self.innsbruck, Self.landeck, .second)
        XCTAssertGreaterThan(second.amountEUR, 0)
        XCTAssertEqual(second.owner, "VVT")
        let first = try await shopFare(Self.innsbruck, Self.landeck, .first)
        XCTAssertEqual(first.owner, "ÖBB")
        XCTAssertGreaterThan(first.amountEUR, second.amountEUR)
    }

    // 3: Wien Hbf → Salzburg: ÖBB Standard-Ticket between 40 and 120 €.
    func testShopWienSalzburg() async throws {
        let fare = try await shopFare(Self.wien, Self.salzburg, .second)
        XCTAssertEqual(fare.owner, "ÖBB")
        XCTAssertGreaterThan(fare.amountEUR, 40)
        XCTAssertLessThan(fare.amountEUR, 120)
    }

    // 4: VAO Innsbruck → Hall: VVT single ticket.
    func testVaoInnsbruckHall() async throws {
        let fare = try await live {
            try await Self.verbund.singleFare(fromLid: "A=1@L=470118700@", toLid: "A=1@L=470118400@", departure: self.departure)
        }
        XCTAssertGreaterThan(fare.amountEUR, 0)
        XCTAssertEqual(fare.provider, "VVT")
    }

    /// Assumption check (via stops, owner request 2026-10-09): VAO accepts `viaLocL` and prices the via route – a detour
    /// Innsbruck → Völs → Hall in Tirol crosses more VVT zones than the direct Innsbruck → Hall (4,70 €). One request.
    /// `KB_LIVE_RECORD_DIR=<dir>` writes the exchange as `vao_tripsearch_tariff_via_voels_ibk-hall.json` (FX/vao format).
    func testVaoViaRouteIsPriced() async throws {
        let recorder = RecordingTransport(Self.transport)
        let client = VerbundTariffClient(config: .default, transport: recorder, throttle: Self.throttle, health: Self.health, appVersion: "live-test")
        let fare = try await live {
            try await client.singleFare(fromLid: "A=1@L=470118700@", toLid: "A=1@L=470118400@", via: ["A=1@L=470119100@"],
                                        departure: self.departure)
        }
        XCTAssertEqual(fare.provider, "VVT")
        XCTAssertGreaterThanOrEqual(fare.amountEUR, 4.70, "via route is not cheaper than the direct relation")
        print("[PriceLiveTests] VAO Innsbruck → Völs → Hall: \(fare.productName) · \(fare.fareSet) · \(FareEstimator.euro(fare.amountEUR))")
        try Self.recordVao(recorder, "vao_tripsearch_tariff_via_voels_ibk-hall")
    }

    /// FX/vao format: `{_meta{captured_at, method, url, status, latency_s}, request: <envelope>, response: <raw>}`.
    static func recordVao(_ recorder: RecordingTransport, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["KB_LIVE_RECORD_DIR"], let (req, resp, seconds) = recorder.last else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let f = ISO8601DateFormatter()
        let meta: [String: Any] = ["captured_at": f.string(from: Date()), "method": req.method, "url": req.url.absoluteString,
                                   "status": resp.status, "latency_s": (seconds * 100).rounded() / 100]
        let object: [String: Any] = ["_meta": meta, "request": try JSONSerialization.jsonObject(with: req.body ?? Data("{}".utf8)),
                                     "response": try JSONSerialization.jsonObject(with: resp.body)]
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url.appendingPathComponent("\(name).json"))
    }
}
