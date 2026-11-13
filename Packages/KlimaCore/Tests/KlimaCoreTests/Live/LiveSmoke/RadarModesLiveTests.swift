// Opt-in, ONE-TIME measurement for docs/RADAR_MODES.md §8 (Radar für alle Verkehrsmittel). At most FOUR JourneyGeoPos requests, at least 2.1 s
// apart, honest User-Agent (the app's own HafasClient), never a retry, no fallback profile, everything stops at the first problem:
//   1. the level-5 tile with Wien Stephansplatz, Bus|Bim|U-Bahn (832): counts per product class, cut off, size, share with stops, realtime and
//      operator fields,
//   2. the Wien box of docs/OEBB_LIVE.md §R11.1 d, U-Bahn (256) only: does JourneyGeoPos give U-Bahn positions at all,
//   3. all of Austria, rail replacement | ship | on-demand and cable car (2|128|2048): which of these classes come with a position,
//   4. if (1) was cut off its level-6 child with Stephansplatz, else the level-5 tile with Graz Hbf, both with 832.
//   KB_LIVE_TESTS=1 KB_RADAR_MODES=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarModesLiveTests
// Never part of CI. Two switches on purpose: a plain `--filter LiveSmoke` run must not spend the requests.
// Prints counts, sizes, durations and booleans only (lines start with RADAR_MODES): no trip id, no line, no stop name, no operator, no coordinate.
import Foundation
import XCTest
@testable import KlimaCore

final class RadarModesLiveTests: XCTestCase {
    static let budget = 4
    static let city: ProductMask = [.bus, .tram, .subway]   // 832

    private struct Answer {
        var snapshot: RadarSnapshot
        var bytes: Int
        var ms: Int
        var status: Int
    }

    private func ask(_ client: HafasClient, _ transport: BudgetedTransport, box: RadarBox, products: ProductMask) async throws -> Answer {
        let data = try await client.send([HafasRequests.journeyGeoPos(RadarQuery(box: box, when: Date(), products: products, maxVehicles: 1000))])
        let snapshot = try HafasCodec.radar(from: data)
        let entry = transport.entries.last
        return Answer(snapshot: snapshot, bytes: data.count, ms: Int((entry?.seconds ?? 0) * 1000), status: entry?.status ?? -1)
    }

    private func percent(_ part: Int, of whole: Int) -> Int { whole == 0 ? 0 : Int((Double(part) / Double(whole) * 100).rounded()) }

    private func classes(_ vehicles: [RadarVehicle]) -> String {
        Dictionary(grouping: vehicles, by: { $0.line?.productClass ?? 0 }).mapValues(\.count)
            .sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
    }

    /// Shares, never names: how many carry two stops or more, realtime, an operator name, an admin code; how many different operators.
    private func shape(_ label: String, _ answer: Answer, request: Int) {
        let vehicles = answer.snapshot.vehicles
        let stops = vehicles.filter { $0.stopovers.count >= 2 }.count
        let realtime = vehicles.filter { $0.stopovers.contains { $0.arrival?.realtime != nil || $0.departure?.realtime != nil } }.count
        let named = vehicles.filter { !($0.line?.operatorName ?? "").isEmpty }.count
        let admin = vehicles.filter { !($0.line?.admin ?? "").isEmpty }.count
        let operators = Set(vehicles.compactMap { $0.line?.operatorName }.filter { !$0.isEmpty }).count
        print("RADAR_MODES \(label) http=\(answer.status) ms=\(answer.ms) bytes=\(answer.bytes) vehicles=\(vehicles.count) answered=\(answer.snapshot.answeredCount) " +
              "capped=\(RadarTiling.isTruncated(count: answer.snapshot.answeredCount)) bytesPerEntry=\(answer.snapshot.answeredCount == 0 ? 0 : answer.bytes / answer.snapshot.answeredCount) " +
              "classes=[\(classes(vehicles))] withTwoStopsPct=\(percent(stops, of: vehicles.count)) withRealtimePct=\(percent(realtime, of: vehicles.count)) " +
              "withOperatorNamePct=\(percent(named, of: vehicles.count)) withAdminPct=\(percent(admin, of: vehicles.count)) distinctOperators=\(operators) request#\(request)")
    }

    func testMeasureModes() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_MODES"] == "1" else { throw XCTSkip("KB_RADAR_MODES=1 not set") }

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        let transport = BudgetedTransport(URLSessionTransport(), limit: Self.budget)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")

        var vienna = Calendar(identifier: .gregorian)
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let parts = vienna.dateComponents([.weekday, .hour, .minute], from: Date())
        print("RADAR_MODES start weekday=\(parts.weekday ?? 0) (1=Sunday) viennaTime=\(parts.hour ?? 0):" + String(format: "%02d", parts.minute ?? 0) +
              " budget=\(Self.budget)")

        func tile(_ point: GeoPoint, level: Int) -> RadarTileKey? {
            RadarTileGrid.tiles(intersecting: RadarBox(north: point.latitude + 1e-4, west: point.longitude - 1e-4,
                                                       south: point.latitude - 1e-4, east: point.longitude + 1e-4), level: level).first
        }
        let stephansplatz = GeoPoint(latitude: 48.2085, longitude: 16.3725)
        guard let wien5 = tile(stephansplatz, level: 5) else { return XCTFail("no level-5 tile") }

        // 1. Wien city tile, Bus|Bim|U-Bahn.
        let first: Answer
        do {
            first = try await ask(client, transport, box: RadarTileGrid.box(of: wien5), products: Self.city)
            let box = RadarTileGrid.box(of: wien5)
            print("RADAR_MODES r1 tileLevel=5 tileKm=\(String(format: "%.1f x %.1f", (box.north - box.south) * 111.2, (box.east - box.west) * 74.0))")
            shape("r1 wien5 products=832", first, request: transport.requestCount)
        } catch {
            print("RADAR_MODES r1 outcome=\(error) requests=\(transport.requestCount)")
            throw XCTSkip("ÖBB did not answer JourneyGeoPos: \(error)")
        }

        // 2. Wien box of §R11.1 d, U-Bahn only.
        do {
            let answer = try await ask(client, transport, box: RadarBox(north: 48.32, west: 16.18, south: 48.10, east: 16.58), products: .subway)
            shape("r2 wienBox products=256", answer, request: transport.requestCount)
            print("RADAR_MODES r2 subwayPositions=\(!answer.snapshot.vehicles.isEmpty)")
        } catch {
            print("RADAR_MODES r2 outcome=\(error) requests=\(transport.requestCount)")
            return
        }

        // 3. Austria, rail replacement | ship | on-demand and cable car.
        do {
            let answer = try await ask(client, transport, box: .austria, products: [.railReplacement, .ship, .onDemand])
            shape("r3 austria products=2178", answer, request: transport.requestCount)
            for cls in [2, 128, 2048] {
                let of = answer.snapshot.vehicles.filter { $0.line?.productClass == cls }
                print("RADAR_MODES r3 class=\(cls) withPosition=\(of.count) withTwoStops=\(of.filter { $0.stopovers.count >= 2 }.count)")
            }
        } catch {
            print("RADAR_MODES r3 outcome=\(error) requests=\(transport.requestCount)")
            return
        }

        // 4. A finer Wien tile when (1) was cut off, else Graz's level-5 tile.
        let capped = RadarTiling.isTruncated(count: first.snapshot.answeredCount)
        let fourth = capped ? tile(stephansplatz, level: 6) : tile(GeoPoint(latitude: 47.0727, longitude: 15.4170), level: 5)
        if let fourth {
            do {
                let answer = try await ask(client, transport, box: RadarTileGrid.box(of: fourth), products: Self.city)
                shape("r4 \(capped ? "wien6" : "graz5") products=832", answer, request: transport.requestCount)
            } catch {
                print("RADAR_MODES r4 outcome=\(error) requests=\(transport.requestCount)")
            }
        }
        XCTAssertLessThanOrEqual(transport.requestCount, Self.budget, "at most four requests")
    }
}
