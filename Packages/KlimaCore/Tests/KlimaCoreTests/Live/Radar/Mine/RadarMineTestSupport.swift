import Foundation
@testable import KlimaCore

/// Synthetic lines, vehicles and boards for the „Meine Fahrzeuge“ tests. Fixed moments, no clock, no network.
enum MineFixture {
    static let t0 = Date(timeIntervalSince1970: 1_795_000_000)
    static let neubau = GeoPoint(latitude: 48.2015, longitude: 16.3480)
    static let metersPerDegree = 111_195.0

    /// A point `north` and `east` metres from `origin`.
    static func point(north: Double = 0, east: Double = 0, from origin: GeoPoint = neubau) -> GeoPoint {
        GeoPoint(latitude: origin.latitude + north / metersPerDegree,
                 longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180)))
    }

    static func bus(_ number: String = "13A", name: String? = nil, lineNumber: String?? = .none) -> Line {
        Line(name: name ?? "Bus \(number)", category: "Bus", categoryShort: "bus", lineNumber: lineNumber ?? number, productClass: 64, mode: .bus)
    }

    static func sBahn(_ number: String = "45", name: String? = nil) -> Line {
        Line(name: name ?? "S \(number)", category: "S", categoryShort: "s", lineNumber: number, productClass: 32, mode: .sBahn)
    }

    static let u6 = Line(name: "U6", category: "U", categoryShort: "U", lineNumber: "U6", productClass: 256, mode: .metro)
    static let tramD = Line(name: "Tram D", category: "Tram", categoryShort: "str", lineNumber: "D", productClass: 512, mode: .tram)
    static let rjx66 = Line(name: "RJX 66", category: "RJX", categoryShort: "RJX", trainNumber: "66", productClass: 1, mode: .train)
    /// Rail replacement: the codec calls it a bus, the radar's modes do not.
    static let sev = Line(name: "Bus SEV", category: "Bus", lineNumber: "SEV", productClass: 2, mode: .bus)

    /// A vehicle with its next stop `next` seconds after `now` and the given delay (nil: no realtime).
    static func vehicle(_ id: String, line: Line?, at coordinate: GeoPoint = neubau, direction: String? = "Hauptbahnhof",
                        nextIn seconds: TimeInterval = 120, delayMinutes: Int? = 1, cancelled: Bool = false, now: Date = t0,
                        nextName: String = "Neubaugasse") -> RadarVehicle {
        let planned = now.addingTimeInterval(seconds)
        let event = StopEvent(planned: planned, realtime: delayMinutes.map { planned.addingTimeInterval(Double($0) * 60) })
        let left = Stopover(location: Location(lid: "l", name: "Vorher"), departure: StopEvent(planned: now.addingTimeInterval(-120)))
        let next = Stopover(location: Location(lid: "n", name: nextName), arrival: event)
        return RadarVehicle(tripID: id, line: line, direction: direction, coordinate: coordinate, stopovers: [left, next], isCancelled: cancelled)
    }

    static func entry(_ id: String, line: Line? = bus(), inMinutes: Double, delayMinutes: Int? = 0, cancelled: Bool = false, position: GeoPoint? = nil,
                      platform: Platform? = Platform(text: "2", kind: .stand), stop: GeoPoint? = neubau, now: Date = t0) -> BoardEntry {
        let planned = now.addingTimeInterval(inMinutes * 60)
        let event = StopEvent(planned: planned, realtime: delayMinutes.map { planned.addingTimeInterval(Double($0) * 60) }, plannedPlatform: platform,
                              isCancelled: cancelled)
        return BoardEntry(tripID: id, line: line, direction: "Hauptbahnhof", stop: Location(lid: "A=1@L=1@", name: "Neubaugasse", coordinate: stop),
                          event: event, currentPosition: position)
    }
}
