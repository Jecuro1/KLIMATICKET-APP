// MARK: radar2-radarmine – opt-in, ONE-TIME measurement for docs/RADAR_MINE.md §7 („Meine Fahrzeuge“, specs radar2 radarmine §12). At most TWO
// requests, at least 2.1 s apart, honest User-Agent (the app's own HafasClient), never a retry, no fallback profile, no LocMatch (the meta station id of
// Wien Hbf is known), everything stops at the first problem:
//   1. StationBoard departures at Wien Hbf, Bus|Bim|U-Bahn (832), 30 minutes, at most 30: entries, entries with a position, the share with a position
//      among those leaving within 15 minutes, the distance position → station (median, 90 %, max), bytes, ms,
//   2. JourneyGeoPos in a box of ±0.015° around Wien Hbf, 832, maxJny 1000: vehicles, how many board trips with a position the radar holds under the
//      same trip id, for those the distance between the board's and the radar's position (metres, median and max), and how often Wien Hbf is among
//      the radar's four stops of such a trip.
//   KB_LIVE_TESTS=1 KB_RADAR_MINE=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarMineLiveTests
// Only on a weekday between 09:00 and 19:00 in Vienna (at night the city's buses are few and the answer says little). Never part of CI. Two switches on
// purpose: a plain `--filter LiveSmoke` run must not spend the requests. Prints counts, distances, durations and booleans only (lines start with
// RADAR_MINE): no trip id, no line, no stop name, no coordinate.
import Foundation
import XCTest
@testable import KlimaCore

final class RadarMineLiveTests: XCTestCase {
    static let budget = 2
    static let city: ProductMask = [.bus, .tram, .subway]   // 832
    static let wienHbf = Location(lid: "A=1@L=1290401@", kind: .station, extId: "1290401", name: "Wien Hbf",
                                  coordinate: GeoPoint(latitude: 48.185, longitude: 16.375))

    private func quantiles(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "n=0" }
        let sorted = values.sorted()
        func at(_ q: Double) -> Double { sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded()))] }
        return String(format: "n=%d median=%.2f p90=%.2f max=%.2f", sorted.count, at(0.5), at(0.9), sorted[sorted.count - 1])
    }

    func testMeasureBoardAndRadar() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_MINE"] == "1" else { throw XCTSkip("KB_RADAR_MINE=1 not set") }

        var vienna = Calendar(identifier: .gregorian)
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let parts = vienna.dateComponents([.weekday, .hour, .minute], from: Date())
        let weekday = parts.weekday ?? 1, hour = parts.hour ?? 0
        guard (2...6).contains(weekday), (9..<19).contains(hour) else {
            throw XCTSkip("only on a weekday between 09:00 and 19:00 in Vienna (now weekday \(weekday), \(hour) h)")
        }
        print("RADAR_MINE start weekday=\(weekday) (1=Sunday) viennaTime=\(hour):" + String(format: "%02d", parts.minute ?? 0) + " budget=\(Self.budget)")

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        let transport = BudgetedTransport(URLSessionTransport(), limit: Self.budget)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")
        let now = Date()

        // 1. The board.
        let board: Board
        do {
            let query = BoardQuery(station: Self.wienHbf, kind: .departures, date: now, durationMinutes: 30, maxResults: 30, products: Self.city)
            let data = try await client.send([HafasRequests.stationBoard(query)])
            board = try HafasCodec.board(from: data)
            let entry = transport.entries.last
            let withPosition = board.entries.filter { $0.currentPosition != nil }
            let soon = board.entries.filter { ($0.event.realtime ?? $0.event.planned).map { $0.timeIntervalSince(now) <= 15 * 60 } ?? false }
            let soonWith = soon.filter { $0.currentPosition != nil }
            let km = withPosition.compactMap { $0.currentPosition?.distanceKm(to: Self.wienHbf.coordinate ?? GeoPoint(latitude: 48.185, longitude: 16.375)) }
            print("RADAR_MINE r1 http=\(entry?.status ?? -1) ms=\(Int((entry?.seconds ?? 0) * 1000)) bytes=\(data.count) entries=\(board.entries.count) " +
                  "withPosition=\(withPosition.count) leavingWithin15=\(soon.count) leavingWithin15WithPosition=\(soonWith.count) " +
                  "distanceKm[\(quantiles(km))] request#\(transport.requestCount)")
        } catch {
            print("RADAR_MINE r1 outcome=\(error) requests=\(transport.requestCount)")
            throw XCTSkip("ÖBB did not answer StationBoard: \(error)")
        }

        // 2. The radar around the station: are the board's trips the radar's trips?
        do {
            try await Task.sleep(for: .milliseconds(2100))
            let box = RadarBox(north: 48.185 + 0.015, west: 16.375 - 0.015, south: 48.185 - 0.015, east: 16.375 + 0.015)
            let data = try await client.send([HafasRequests.journeyGeoPos(RadarQuery(box: box, when: Date(), products: Self.city, maxVehicles: 1000))])
            let snapshot = try HafasCodec.radar(from: data)
            let entry = transport.entries.last
            let radar = Dictionary(snapshot.vehicles.map { ($0.tripID, $0) }, uniquingKeysWith: { first, _ in first })
            let positioned = board.entries.filter { $0.currentPosition != nil }
            let matched = positioned.filter { radar[$0.tripID] != nil }
            let metres = matched.compactMap { entry -> Double? in
                guard let board = entry.currentPosition, let vehicle = radar[entry.tripID] else { return nil }
                return board.distanceKm(to: vehicle.coordinate) * 1000
            }
            let hbfAmongStops = matched.filter { entry in
                radar[entry.tripID]?.stopovers.contains { $0.location.extId == Self.wienHbf.extId || $0.location.name.hasPrefix("Wien Hbf") } ?? false
            }.count
            print("RADAR_MINE r2 http=\(entry?.status ?? -1) ms=\(Int((entry?.seconds ?? 0) * 1000)) bytes=\(data.count) vehicles=\(snapshot.vehicles.count) " +
                  "boardWithPosition=\(positioned.count) sameTripIDInRadar=\(matched.count) idsMatch=\(!matched.isEmpty) " +
                  "boardToRadarMetres[\(quantiles(metres))] wienHbfAmongRadarStops=\(hbfAmongStops) request#\(transport.requestCount)")
        } catch {
            print("RADAR_MINE r2 outcome=\(error) requests=\(transport.requestCount)")
        }
        XCTAssertLessThanOrEqual(transport.requestCount, Self.budget, "at most two requests")
    }
}
