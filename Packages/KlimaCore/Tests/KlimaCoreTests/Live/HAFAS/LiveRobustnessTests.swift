import Foundation
import XCTest
@testable import KlimaCore

/// Review 2026-10-09: corrupt or hostile input never traps the live layer (integer overflow, NaN → Int, unbounded
/// loops); it decodes to nil / garbage values or throws a `LiveError`.
final class LiveRobustnessTests: XCTestCase {

    // MARK: HAFAS times

    func testCorruptDayAndUTCOffsetsDoNotTrap() throws {
        // A 15-digit day offset would overflow `days * 86_400`.
        XCTAssertNil(HafasTime.duration("999999999999999000000"))
        XCTAssertNil(HafasTime.date(base: "20261009", time: "999999999999999120000", tzOffsetMinutes: nil))
        XCTAssertNil(HafasTime.duration("100000000"), "day offsets above 99 are corrupt")
        XCTAssertEqual(HafasTime.duration("99000000"), 99 * 86_400)
        // An absurd UTC offset (`offset * 60` would overflow) is ignored: the time is read in Vienna.
        let vienna = try XCTUnwrap(HafasTime.date(base: "20261009", time: "120000", tzOffsetMinutes: nil))
        XCTAssertEqual(HafasTime.date(base: "20261009", time: "120000", tzOffsetMinutes: Int.max / 2), vienna)
        XCTAssertEqual(HafasTime.date(base: "20261009", time: "120000", tzOffsetMinutes: Int.min), vienna)
        XCTAssertEqual(HafasTime.date(base: "20261009", time: "120000", tzOffsetMinutes: 120), vienna, "real offsets still apply")
    }

    // MARK: Polylines

    func testPolylineGarbageNeverTraps() {
        // 12-chunk values (≈ 2^60 each) used to overflow the running sum.
        let chunk = String(repeating: "~", count: 11) + "^"
        XCTAssertTrue(Polyline.decode(String(repeating: chunk, count: 40)).isEmpty, "over-long values are rejected")
        // 7-chunk values are the largest accepted; their sums wrap instead of trapping.
        let big = String(repeating: "~", count: 6) + "^"
        XCTAssertEqual(Polyline.decode(String(repeating: big, count: 2_000)).count, 1_000)
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let length = Int.random(in: 0...200, using: &rng)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &rng) }
            _ = Polyline.decode(String(decoding: bytes, as: UTF8.self))
        }
        // The reference string still decodes.
        XCTAssertEqual(Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@").count, 3)
    }

    // MARK: Coordinates

    func testNearbyWithAnInvalidFixSendsNothing() async throws {
        let transport = FixtureTransport(routes: [])
        let (client, _) = HafasClient.testClient(transport, clock: FakeClock(Date(timeIntervalSince1970: 1_791_000_000)))
        for p in [GeoPoint(latitude: .nan, longitude: 11.4), GeoPoint(latitude: 47.2, longitude: .infinity),
                  GeoPoint(latitude: -180, longitude: -180)] { // CoreLocation's kCLLocationCoordinate2DInvalid
            let result = try await client.nearby(p, maxDistanceMeters: 400, maxResults: 5, products: .all)
            XCTAssertTrue(result.isEmpty)
        }
        XCTAssertTrue(transport.recorded.isEmpty)
        let station = OebbShopClient.Station(number: 8100108, name: "Innsbruck Hbf", coordinate: GeoPoint(latitude: .nan, longitude: .nan))
        XCTAssertEqual(station.latitude, 0)
        XCTAssertNil(station.coordinate)
    }

    // MARK: Fuzzed fixtures

    /// Every HAFAS response fixture with hostile values patched in (huge offsets, day offsets, indices, polylines) and
    /// truncated: the codec must return or throw, never trap.
    func testFuzzedHafasFixturesNeverTrap() throws {
        let dir = Fixture.root.appendingPathComponent("hafas")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".response.json") }.sorted()
        XCTAssertGreaterThan(files.count, 30)
        let patches: [(String, String)] = [
            (#""(d|a)TZOffset(R?)":-?\d+"#, #""$1TZOffset$2":9223372036854775807"#),
            (#""(d|a)Time(S|R)":"\d+""#, #""$1Time$2":"999999999999999999999""#),
            (#""dur":"\d+""#, #""dur":"98765432109876543210""#),
            (#""(locX|prodX|remX|himX|oprX|dirX|idx)":\d+"#, #""$1":-7"#),
            (#""crdEncYX":"[^"]*""#, #""crdEncYX":"~~~~~~~~~~~^~~~~~~~~~~^~~~~~~~~~~~^~~~~~~~~~~^""#),
            (#""x":-?\d+"#, #""x":9223372036854775807"#),
            (#""date":"\d+""#, #""date":"99999999""#),
        ]
        // Every patch on its own for one fixture per decoder; the combined patch and a truncation for all fixtures.
        let representative: Set<String> = ["tripsearch_innsbruck_lech_bus.response.json", "stationboard_dep_innsbruck_hbf.response.json",
                                           "journeydetails_rjx133_koralm_polyline.response.json", "locmatch_batch_mixed.response.json",
                                           "himsearch_disruptions_rail.response.json"]
        var rng = SeededGenerator(seed: 7)
        for file in files {
            let original = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            var variants: [String] = []
            var all = original
            for (pattern, template) in patches {
                let re = try NSRegularExpression(pattern: pattern)
                let patched = re.stringByReplacingMatches(in: original, range: NSRange(location: 0, length: (original as NSString).length),
                                                          withTemplate: template)
                if representative.contains(file) { variants.append(patched) }
                all = re.stringByReplacingMatches(in: all, range: NSRange(location: 0, length: (all as NSString).length), withTemplate: template)
            }
            variants.append(all)
            let bytes = Array(original.utf8)
            for _ in 0..<1 { variants.append(String(decoding: bytes.prefix(Int.random(in: 0..<bytes.count, using: &rng)), as: UTF8.self)) }
            for v in variants {
                let data = Data(v.utf8)
                _ = HafasCodec.envelopeError(data)
                switch file.split(separator: "_").first ?? "" {
                case "stationboard": _ = try? HafasCodec.board(from: data)
                case "journeydetails": _ = try? HafasCodec.trip(from: data)
                case "locmatch", "locgeopos": _ = try? HafasCodec.locations(from: data, query: "Innsbruck")
                case "himsearch": _ = try? HafasCodec.remarks(from: data)
                default:
                    _ = try? HafasCodec.journeyPage(from: data)
                    _ = try? HafasCodec.journeyPages(from: data)
                }
            }
        }
    }

    // MARK: Small helpers

    func testHTMLWithUnclosedTagsStaysLinear() {
        let garbage = String(repeating: "<", count: 60_000)
        let started = Date()
        XCTAssertEqual(HTMLText.plain(garbage + "a"), garbage + "a")
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "no quadratic search for a closing „>“")
        XCTAssertEqual(HTMLText.plain("<b>Zug</b> fällt aus<br>heute"), "Zug fällt aus\nheute")
    }

    func testShopTimeRejectsAbsurdComponents() {
        XCTAssertNil(ShopTime.date("99999999999-01-01T00:00:00.000"))
        XCTAssertNil(ShopTime.date("2026-13-01T08:00:00.000"))
        XCTAssertNil(ShopTime.date("2026-10-10T99999999999999:00:00.000"))
        XCTAssertEqual(ShopTime.date("2026-10-10T08:28:00.000"), ISO.date("2026-10-10T08:28:00+02:00"))
        XCTAssertEqual(ShopTime.date("2026-10-10T08:28"), ISO.date("2026-10-10T08:28:00+02:00"))
    }

    func testServerRetryAfterCannotOpenTheCircuitForever() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_791_000_000))
        let health = LiveHealth(clock: clock.closure)
        await health.recordFailure(.oebbShop, .rateLimited(.oebbShop, retryAfter: .infinity))
        var until = await health.status()[.oebbShop]?.openUntil
        XCTAssertEqual(until, clock.now.addingTimeInterval(60), "∞ is not a usable Retry-After: default 60 s")
        await health.recordFailure(.oebbShop, .rateLimited(.oebbShop, retryAfter: 1e12))
        until = await health.status()[.oebbShop]?.openUntil
        XCTAssertEqual(until, clock.now.addingTimeInterval(6 * 3600), "capped at 6 h")
        await health.recordFailure(.vaoTariff, .rateLimited(.vaoTariff, retryAfter: 30))
        let vao = await health.status()[.vaoTariff]?.openUntil
        XCTAssertEqual(vao, clock.now.addingTimeInterval(30))
    }

    func testMalformedShopListElementsAreSkipped() throws {
        let json = #"{"offerError":false,"offerSections":[null,5,"x",{"travelClasses":[7,{"class":"2","offers":[null,{"flexibility":{"de":"FLEX"},"price":4.7,"products":[{"name":{"de":"VVT Einzelticket"},"trafficType":"ONEWAY","owners":[{"nameShort":"VVT"}]}]}]}]}]}"#
        let offers = try JSONDecoder().decode(ShopOffers.self, from: Data(json.utf8))
        XCTAssertEqual(offers.offerSections?.count, 1)
        XCTAssertEqual(ShopOfferSelector.standardFare(offers, travelClass: .second)?.amountEUR, 4.70)
    }
}

/// Deterministic SplitMix64 for reproducible fuzzing.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
