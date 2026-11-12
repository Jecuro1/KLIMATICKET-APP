// Opt-in, ONE-TIME measurement for docs/RADAR_HEATMAP.md §7 (Verspätungs-Heatmap). Exactly ONE JourneyGeoPos request (Austria, rail,
// maxJny 1000), honest User-Agent, never a retry, nothing after a problem.
//   KB_LIVE_TESTS=1 KB_RADAR_HEAT=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarHeatLiveTests
// Never part of CI. Two switches on purpose: a plain `--filter LiveSmoke` run must not spend the request.
// Prints counts only (lines start with RADAR_HEAT): how many vehicles carry a realtime delay, how they spread over the buckets, how
// many are cancelled, how many grid cells that fills and how many reach the minimum sample. No vehicle list, no trip ids, no names,
// no positions: nothing of this is stored.
import Foundation
import XCTest
@testable import KlimaCore

final class RadarHeatLiveTests: XCTestCase {
    func testMeasureRealtimeCoverageAndBuckets() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_HEAT"] == "1" else { throw XCTSkip("KB_RADAR_HEAT=1 not set") }

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        let transport = BudgetedTransport(URLSessionTransport(), limit: 1)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")

        let now = Date()
        let snapshot: RadarSnapshot
        do {
            snapshot = try await client.radar(RadarQuery(box: .austria, when: now, products: .rail, maxVehicles: 1000))
        } catch {
            print("RADAR_HEAT outcome=\(error) requests=\(transport.requestCount)")
            throw XCTSkip("ÖBB did not answer JourneyGeoPos: \(error)")
        }

        var vienna = Calendar(identifier: .gregorian)
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let parts = vienna.dateComponents([.weekday, .hour, .minute], from: now)
        print("RADAR_HEAT outcome=ok requests=\(transport.requestCount) http=\(transport.entries.last?.status ?? -1) " +
              "ms=\(Int((transport.entries.last?.seconds ?? 0) * 1000)) weekday=\(parts.weekday ?? 0) (1=Sunday) viennaTime=\(parts.hour ?? 0):" +
              String(format: "%02d", parts.minute ?? 0))

        // What the server sent, and how many of the vehicles carry realtime data at any stop or at the next stop.
        let vehicles = snapshot.vehicles
        let anyRealtime = vehicles.filter { v in v.stopovers.contains { $0.arrival?.delaySeconds != nil || $0.departure?.delaySeconds != nil } }.count
        let samples = vehicles.map { HeatSample(vehicle: $0, coordinate: $0.coordinate, now: now) }
        let heat = RadarHeat.snapshot(samples)
        let s = heat.summary
        print("RADAR_HEAT answered=\(snapshot.answeredCount) vehicles=\(vehicles.count) anyStopWithRealtime=\(anyRealtime) " +
              "noStopOverData=\(vehicles.filter { $0.stopovers.isEmpty }.count)")
        print("RADAR_HEAT buckets total=\(s.total) withRealtime=\(s.withRealtime) noRealtime=\(s.noRealtime) onTime=\(s.onTime) " +
              "delayed5to15=\(s.delayed) severeOver15=\(s.severe) cancelled=\(s.cancelled)")
        print("RADAR_HEAT punctualPercent=\(s.punctualPercent.map(String.init) ?? "-") " +
              "averageLateMinutes=\(s.averageLateSeconds.map { String(format: "%.1f", $0 / 60) } ?? "-") late=\(s.late)")

        // Distribution of the delay values (counts per minute class), so the limits can be judged.
        let delays = samples.compactMap(\.delaySeconds)
        let classes: [(String, Int, Int)] = [("<0", Int.min, 0), ("0-2", 0, 180), ("3-4", 180, 300), ("5-9", 300, 600), ("10-14", 600, 900),
                                             ("15-29", 900, 1800), ("30+", 1800, Int.max)]
        let spread = classes.map { name, low, high in "\(name):\(delays.filter { $0 >= low && $0 < high }.count)" }.joined(separator: " ")
        print("RADAR_HEAT delayClassesMinutes \(spread) median=\(RadarHeat.median(delays).map { String(format: "%.0f s", $0) } ?? "-")")

        // The grid: how many cells hold trains, how many reach the minimum, how full the fullest is.
        let coloured = heat.cells.filter { !$0.isNeutral }
        let counts = heat.cells.map(\.trainCount)
        print("RADAR_HEAT cells populated=\(heat.cells.count) coloured=\(coloured.count) neutral=\(heat.cells.count - coloured.count) " +
              "trainsInColoured=\(coloured.reduce(0) { $0 + $1.trainCount }) maxTrainsInCell=\(counts.max() ?? 0) " +
              "cellsWith1=\(counts.filter { $0 == 1 }.count) cellsWith2=\(counts.filter { $0 == 2 }.count) " +
              "cellsWith3to5=\(counts.filter { (3...5).contains($0) }.count) cellsWith6plus=\(counts.filter { $0 >= 6 }.count)")
        print("RADAR_HEAT cellBuckets onTime=\(coloured.filter { $0.bucket == .onTime }.count) delayed=\(coloured.filter { $0.bucket == .delayed }.count) " +
              "severe=\(coloured.filter { $0.bucket == .severe }.count) hotspots=\(heat.hotspots.count) topDelays=\(heat.topDelays.count) " +
              "drawn=\(HeatLayer.drawCells(from: heat).count)")
        XCTAssertEqual(transport.requestCount, 1, "exactly one request")
    }
}
