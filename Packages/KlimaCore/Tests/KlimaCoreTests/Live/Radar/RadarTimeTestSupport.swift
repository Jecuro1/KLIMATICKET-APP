import XCTest
@testable import KlimaCore

/// Synthetic runs for the Zeitreise tests: a west-east line at 48.0° N, one degree of longitude (about 74 km) between the stops.
/// Nothing here is a real train.
enum RadarTimeFixtures {
    /// Thursday 2026-11-12 19:00 UTC (20:00 in Vienna).
    static let t0 = Date(timeIntervalSince1970: 1_794_510_000)

    static func at(_ minutes: Double, from base: Date = t0) -> Date { base.addingTimeInterval(minutes * 60) }

    static func point(_ lon: Double, lat: Double = 48.0) -> GeoPoint { GeoPoint(latitude: lat, longitude: lon) }

    /// One stop: longitude, planned arrival and departure in minutes from `t0` (nil: none), reported delays in minutes (nil: no report).
    struct Stop {
        var lon: Double
        var arr: Double?
        var dep: Double?
        var arrDelay: Double? = nil
        var depDelay: Double? = nil
        var lat = 48.0
        var hasCoordinate = true
    }

    static func stopover(_ index: Int, _ stop: Stop, base: Date) -> Stopover {
        func event(_ minutes: Double?, _ delay: Double?) -> StopEvent? {
            guard let minutes else { return nil }
            let planned = at(minutes, from: base)
            return StopEvent(planned: planned, realtime: delay.map { planned.addingTimeInterval($0 * 60) }, prognosis: delay == nil ? nil : .prognosed)
        }
        let location = Location(lid: "test|\(index)", kind: .station, extId: nil, name: "Halt \(index)",
                                coordinate: stop.hasCoordinate ? GeoPoint(latitude: stop.lat, longitude: stop.lon) : nil)
        return Stopover(location: location, arrival: event(stop.arr, stop.arrDelay), departure: event(stop.dep, stop.depDelay), index: index)
    }

    /// A vehicle with the given stops. `position` is the server's position (default: the first stop).
    static func vehicle(_ id: String, stops: [Stop], position: GeoPoint? = nil, base: Date = t0, cancelled: Bool = false,
                        category: String = "RJX") -> RadarVehicle {
        let line = Line(name: "\(category) 1", fullName: "\(category) 1", category: category, categoryShort: category, productClass: 1, mode: .train)
        return RadarVehicle(tripID: id, line: line, direction: "Ziel", coordinate: position ?? point(stops[0].lon, lat: stops[0].lat),
                            stopovers: stops.enumerated().map { stopover($0.offset, $0.element, base: base) }, isCancelled: cancelled)
    }

    /// Three stops, 74 km apart: leaves A at +0, B +30 (stands 2 min), C +62.
    static func threeStops(delay: Double? = nil, delayAtC: Double? = nil) -> [Stop] {
        [Stop(lon: 14.0, arr: nil, dep: 0, depDelay: delay),
         Stop(lon: 15.0, arr: 30, dep: 32, arrDelay: delay, depDelay: delay),
         Stop(lon: 16.0, arr: 62, dep: nil, arrDelay: delayAtC ?? delay)]
    }

    static func assertClose(_ a: GeoPoint?, _ b: GeoPoint, accuracy: Double = 1e-6, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no position \(message)", file: file, line: line) }
        XCTAssertEqual(a.latitude, b.latitude, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.longitude, b.longitude, accuracy: accuracy, message, file: file, line: line)
    }

    /// Vienna wall-clock to an instant.
    static func vienna(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day; parts.hour = hour; parts.minute = minute; parts.second = second
        return Calendar.vienna.date(from: parts) ?? .distantPast
    }
}
