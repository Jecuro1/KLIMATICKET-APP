import XCTest
@testable import KlimaCore

/// Synthetic runs for the cockpit tests: a west-east line at 48.0° N, one degree of longitude (about 74 km) between the stops.
/// Nothing here is a real train.
enum CockpitFixtures {
    /// Thursday 2026-11-12 19:00 UTC (20:00 in Vienna).
    static let t0 = Date(timeIntervalSince1970: 1_794_510_000)

    static func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    static func point(_ lon: Double, lat: Double = 48.0) -> GeoPoint { GeoPoint(latitude: lat, longitude: lon) }

    /// One stop: longitude, planned arrival and departure in minutes from `t0` (nil: none), reported delays in minutes (nil: no report).
    struct Stop {
        var lon: Double
        var arr: Double?
        var dep: Double?
        var arrDelay: Double? = nil
        var depDelay: Double? = nil
        var lat = 48.0
        var passes = false
        var arrCancelled = false
        var depCancelled = false
        var platform: String? = nil
    }

    static func stopover(_ index: Int, _ stop: Stop) -> Stopover {
        func event(_ minutes: Double?, _ delay: Double?, cancelled: Bool) -> StopEvent? {
            guard let minutes else { return nil }
            let planned = at(minutes)
            return StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval($0 * 60) },
                             plannedPlatform: stop.platform.map { Platform(text: $0, kind: .track) }, isCancelled: cancelled,
                             prognosis: delay == nil ? nil : .prognosed)
        }
        let location = Location(lid: "cockpit|\(index)", kind: .station, extId: "\(index)", name: "Halt \(index)",
                                coordinate: GeoPoint(latitude: stop.lat, longitude: stop.lon))
        return Stopover(location: location, arrival: event(stop.arr, stop.arrDelay, cancelled: stop.arrCancelled),
                        departure: event(stop.dep, stop.depDelay, cancelled: stop.depCancelled), index: index, passesWithoutStop: stop.passes)
    }

    static func stopovers(_ stops: [Stop]) -> [Stopover] {
        stops.enumerated().map { stopover($0.offset, $0.element) }
    }

    /// Four stops, about 74 km apart: leaves A at +0, B +30 (stands 2 min), C +62 (stands 2 min), D +95.
    static func fourStops(delay: Double? = nil) -> [Stop] {
        [Stop(lon: 14.0, arr: nil, dep: 0, depDelay: delay, platform: "1"),
         Stop(lon: 15.0, arr: 30, dep: 32, arrDelay: delay, depDelay: delay, platform: "3"),
         Stop(lon: 16.0, arr: 62, dep: 64, arrDelay: delay, depDelay: delay, platform: "2"),
         Stop(lon: 17.0, arr: 95, dep: nil, arrDelay: delay, platform: "4")]
    }

    /// The route of `fourStops` laid on a polyline along the same line, with a bend: no, a straight polyline with many points.
    static func straightPolyline(from: Double = 13.9, to: Double = 17.1, steps: Int = 64) -> [GeoPoint] {
        (0...steps).map { point(from + (to - from) * Double($0) / Double(steps)) }
    }

    static func route(_ stops: [Stop] = fourStops(), polyline: [GeoPoint]? = straightPolyline(), cancelled: Bool = false) -> CockpitRoute {
        guard let route = CockpitRoute(stopovers: stopovers(stops), polyline: polyline, isCancelled: cancelled) else {
            fatalError("fixture route")
        }
        return route
    }

    static func assertClose(_ a: GeoPoint?, _ b: GeoPoint, accuracy: Double = 1e-6, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no position \(message)", file: file, line: line) }
        XCTAssertEqual(a.latitude, b.latitude, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.longitude, b.longitude, accuracy: accuracy, message, file: file, line: line)
    }
}
