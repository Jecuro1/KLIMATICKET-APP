// Opt-in, ONE-TIME measurement for docs/RADAR_COCKPIT.md §2 (Cockpit-Ansicht). At most THREE requests, at least 2 s apart, honest User-Agent, never a
// retry, everything stops at the first problem:
//   1. one JourneyGeoPos for a corridor box (finds one running train, rail only),
//   2. one JourneyDetails with polyline for that train (is there a polyline, how big, is there a `pos`, how many stops carry realtime),
//   3. one JourneyGeoPos for a small box around that train (what the cockpit's refresh costs, and what two answers a few seconds apart say).
//   KB_LIVE_TESTS=1 KB_RADAR_COCKPIT=1 swift test --package-path Packages/KlimaCore --no-parallel --filter RadarCockpitLiveTests
// Never part of CI. Two switches on purpose: a plain `--filter LiveSmoke` run must not spend the requests.
// Prints counts, sizes, distances and JSON key names only (lines start with RADAR_COCKPIT): no trip id, no line, no stop name, no coordinate.
import Foundation
import XCTest
@testable import KlimaCore

final class RadarCockpitLiveTests: XCTestCase {
    static let budget = 3

    private func keys(of data: Data, path: [String]) -> [String] {
        guard var node = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        for step in path {
            if let next = node[step] as? [String: Any] { node = next; continue }
            if let list = node[step] as? [[String: Any]], let first = list.first { node = first; continue }
            return []
        }
        return node.keys.sorted()
    }

    func testMeasureCockpitFeed() async throws {
        guard HafasLiveTests.enabled else { throw XCTSkip("KB_LIVE_TESTS=1 not set") }
        guard ProcessInfo.processInfo.environment["KB_RADAR_COCKPIT"] == "1" else { throw XCTSkip("KB_RADAR_COCKPIT=1 not set") }

        var config = LiveConfig.default
        config.hafasFallback = nil   // a fallback profile would be a second request on a PARSE/AUTH answer
        let transport = BudgetedTransport(URLSessionTransport(), limit: Self.budget)
        let client = HafasClient(config: config, transport: transport, throttle: RequestThrottle(), health: LiveHealth(), appVersion: "live-test")

        var vienna = Calendar(identifier: .gregorian)
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let startParts = vienna.dateComponents([.weekday, .hour, .minute], from: Date())
        print("RADAR_COCKPIT start weekday=\(startParts.weekday ?? 0) (1=Sunday) viennaTime=\(startParts.hour ?? 0):" +
              String(format: "%02d", startParts.minute ?? 0) + " budget=\(Self.budget)")

        // 1. A corridor box (Westbahn, Wien to Salzburg): the first answer finds a train that is running between two stops.
        let corridor = RadarBox(north: 48.40, west: 13.00, south: 47.70, east: 16.50)
        let t1 = Date()
        let first: RadarSnapshot
        do {
            let data = try await client.send([HafasRequests.journeyGeoPos(RadarQuery(box: corridor, when: t1, products: .rail, maxVehicles: 1000))])
            first = try HafasCodec.radar(from: data)
            let entry = transport.entries.last
            print("RADAR_COCKPIT r1 corridor http=\(entry?.status ?? -1) ms=\(Int((entry?.seconds ?? 0) * 1000)) bytes=\(data.count) vehicles=\(first.vehicles.count) " +
                  "answered=\(first.answeredCount) request#\(transport.requestCount)")
        } catch {
            print("RADAR_COCKPIT r1 outcome=\(error) requests=\(transport.requestCount)")
            throw XCTSkip("ÖBB did not answer JourneyGeoPos: \(error)")
        }

        // The candidate: not cancelled, between two stops (not within 400 m of any of them), at least three stops with a coordinate, away from the
        // box edge, nearest to the middle of the box.
        let middle = corridor.center
        func candidate(_ vehicle: RadarVehicle) -> Bool {
            guard !vehicle.isCancelled, !vehicle.tripID.isEmpty else { return false }
            let coordinates = vehicle.stopovers.compactMap(\.location.coordinate)
            guard coordinates.count >= 3 else { return false }
            guard vehicle.coordinate.latitude < corridor.north - 0.12, vehicle.coordinate.latitude > corridor.south + 0.12,
                  vehicle.coordinate.longitude < corridor.east - 0.2, vehicle.coordinate.longitude > corridor.west + 0.2 else { return false }
            return coordinates.allSatisfy { $0.distanceKm(to: vehicle.coordinate) > 0.4 }
        }
        let pool = first.vehicles.filter(candidate)
        print("RADAR_COCKPIT r1 candidates=\(pool.count) ofVehicles=\(first.vehicles.count)")
        guard let train = pool.min(by: { $0.coordinate.distanceKm(to: middle) < $1.coordinate.distanceKm(to: middle) }) else {
            print("RADAR_COCKPIT outcome=noCandidate requests=\(transport.requestCount)")
            throw XCTSkip("no running train between two stops in the corridor right now (\(transport.requestCount) request used)")
        }

        // 2. JourneyDetails with polyline.
        let t2 = Date()
        let detailsData: Data
        let details: TripDetails
        do {
            detailsData = try await client.send([HafasRequests.journeyDetails(train.tripID, includePolyline: true)])
            details = try HafasCodec.trip(from: detailsData)
        } catch {
            print("RADAR_COCKPIT r2 outcome=\(error) requests=\(transport.requestCount)")
            throw XCTSkip("ÖBB did not answer JourneyDetails: \(error)")
        }
        let entry2 = transport.entries.last
        let journeyKeys = keys(of: detailsData, path: ["svcResL", "res", "journey"])
        let resKeys = keys(of: detailsData, path: ["svcResL", "res"])
        let withRealtime = details.stopovers.filter { $0.arrival?.realtime != nil || $0.departure?.realtime != nil }.count
        print("RADAR_COCKPIT r2 details http=\(entry2?.status ?? -1) ms=\(Int((entry2?.seconds ?? 0) * 1000)) bytes=\(detailsData.count) stops=\(details.stopovers.count) " +
              "stopsWithRealtime=\(withRealtime) polylinePoints=\(details.polyline?.count ?? 0) hasPos=\(details.currentPosition != nil) " +
              "realtimeAgeSec=\(details.realtimeUpdatedAt.map { Int(t2.timeIntervalSince($0)) }.map(String.init) ?? "-") request#\(transport.requestCount)")
        print("RADAR_COCKPIT r2 journeyKeys=\(journeyKeys) resKeys=\(resKeys)")

        if let route = CockpitRoute(stopovers: details.stopovers, polyline: details.polyline) {
            let km = route.km(of: train.coordinate)
            let off = route.path.project(train.coordinate)?.offKm
            print("RADAR_COCKPIT r2 route straightLine=\(route.isStraightLine) runKm=\(String(format: "%.1f", route.runKm)) pathKm=\(String(format: "%.1f", route.path.lengthKm)) " +
                  "stops=\(route.stops.count) served=\(route.stops.filter(\.isServed).count) trainKm=\(km.map { String(format: "%.1f", $0) } ?? "-") " +
                  "trainOffRouteM=\(off.map { String(Int($0 * 1000)) } ?? "-") legs=\(route.legs.count) " +
                  "legStates=\(Dictionary(grouping: route.legs, by: \.state).mapValues(\.count).map { "\($0.key.rawValue):\($0.value)" }.sorted())")
        } else {
            print("RADAR_COCKPIT r2 route=nil (fewer than two usable stops)")
        }

        // 3. A small box around the train: the refresh of the cockpit.
        let halfLat = 0.05, halfLon = 0.075
        let small = RadarBox(north: train.coordinate.latitude + halfLat, west: train.coordinate.longitude - halfLon,
                             south: train.coordinate.latitude - halfLat, east: train.coordinate.longitude + halfLon)
        let insideInFirst = first.vehicles.filter { small.contains($0.coordinate) }.count
        let t3 = Date()
        do {
            let data = try await client.send([HafasRequests.journeyGeoPos(RadarQuery(box: small, when: t3, products: .rail, maxVehicles: 1000))])
            let second = try HafasCodec.radar(from: data)
            let entry = transport.entries.last
            let seconds = t3.timeIntervalSince(t1)
            let same = second.vehicles.first { $0.tripID == train.tripID }
            let moved = same.map { $0.coordinate.distanceKm(to: train.coordinate) * 1000 }
            // The train's own schedule speed between the two stops around it, for comparison with what the positions did.
            var scheduleKmh: Double?
            if let route = CockpitRoute(stopovers: details.stopovers, polyline: details.polyline), let km = route.km(of: train.coordinate),
               case .between(let from, let to) = route.situation(atKm: km, now: t1),
               let leave = route.stops[from].departure, let arrive = route.stops[to].arrival, arrive > leave {
                scheduleKmh = (route.stops[to].km - route.stops[from].km) / arrive.timeIntervalSince(leave) * 3600
            }
            print("RADAR_COCKPIT r3 small http=\(entry?.status ?? -1) ms=\(Int((entry?.seconds ?? 0) * 1000)) bytes=\(data.count) vehicles=\(second.vehicles.count) " +
                  "answered=\(second.answeredCount) boxKm=\(String(format: "%.1f x %.1f", halfLat * 2 * 110.6, halfLon * 2 * 74.5)) " +
                  "sameBoxInFirstAnswer=\(insideInFirst) request#\(transport.requestCount)")
            print("RADAR_COCKPIT r3 train found=\(same != nil) secondsBetweenRequests=\(String(format: "%.1f", seconds)) movedMeters=\(moved.map { String(Int($0)) } ?? "-") " +
                  "impliedKmh=\(moved.map { String(format: "%.0f", $0 / 1000 / max(seconds, 0.1) * 3600) } ?? "-") scheduleKmh=\(scheduleKmh.map { String(format: "%.0f", $0) } ?? "-") " +
                  "stopsInAnswer=\(same?.stopovers.count ?? 0) stopsWithRealtimeInAnswer=\(same?.stopovers.filter { $0.arrival?.realtime != nil || $0.departure?.realtime != nil }.count ?? 0)")
            print("RADAR_COCKPIT r3 realtimeStamps first=\(first.realtimeUpdatedAt.map { String(Int(t1.timeIntervalSince($0))) } ?? "-")s second=\(second.realtimeUpdatedAt.map { String(Int(t3.timeIntervalSince($0))) } ?? "-")s " +
                  "sameStamp=\(first.realtimeUpdatedAt != nil && first.realtimeUpdatedAt == second.realtimeUpdatedAt)")
            print("RADAR_COCKPIT r3 bytesPerVehicle=\(second.vehicles.isEmpty ? 0 : data.count / second.vehicles.count)")
        } catch {
            print("RADAR_COCKPIT r3 outcome=\(error) requests=\(transport.requestCount)")
        }
        XCTAssertLessThanOrEqual(transport.requestCount, Self.budget, "at most three requests")
    }
}
