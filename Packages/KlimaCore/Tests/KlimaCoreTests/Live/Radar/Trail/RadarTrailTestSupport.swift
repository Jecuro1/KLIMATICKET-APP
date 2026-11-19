import Foundation
@testable import KlimaCore

/// Synthetic vehicles for the „Spuren“ tests: one stop ahead with the given delay, positions offset from a base point in metres.
enum TrailFixture {
    static let t0 = Date(timeIntervalSince1970: 1_795_000_000)   // a fixed moment, no clock
    static let base = GeoPoint(latitude: 48.2, longitude: 16.37)
    static let metersPerDegree = 111_195.0

    /// A point `north` and `east` metres from `base` (longitude scaled by the cosine of the latitude).
    static func point(north: Double = 0, east: Double = 0, from origin: GeoPoint = base) -> GeoPoint {
        GeoPoint(latitude: origin.latitude + north / metersPerDegree,
                 longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180)))
    }

    static func vehicle(_ id: String, at coordinate: GeoPoint, delayMinutes: Int? = 0, productClass: Int = 1, cancelled: Bool = false,
                        now: Date = t0) -> RadarVehicle {
        let planned = now.addingTimeInterval(3_600)
        let event = StopEvent(planned: planned, realtime: delayMinutes.map { planned.addingTimeInterval(Double($0) * 60) })
        let stop = Stopover(location: Location(lid: "x", name: "Ziel"), arrival: event)
        return RadarVehicle(tripID: id, line: Line(name: "T \(id)", productClass: productClass), direction: "Ziel", coordinate: coordinate,
                            stopovers: [stop], isCancelled: cancelled)
    }

    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
}
