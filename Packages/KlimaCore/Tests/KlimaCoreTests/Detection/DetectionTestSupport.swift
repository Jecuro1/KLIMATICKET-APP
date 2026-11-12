import Foundation
import XCTest
@testable import KlimaCore

/// Synthetic world of the detection tests: a few real station coordinates (public facts), invented tracks.
enum DetectFixtures {
    static let innsbruck = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T", kind: .rail,
                                   importance: 9, aliases: ["Innsbruck Hbf"])
    static let telfs = Station(id: "at:47:1196", name: "Telfs-Pfaffenhofen", lat: 47.3047, lon: 11.0717, state: "T", kind: .rail, importance: 2)
    static let imst = Station(id: "at:47:1203", name: "Imst-Pitztal", lat: 47.2386, lon: 10.7425, state: "T", kind: .rail, importance: 2)
    static let landeck = Station(id: "at:47:1212", name: "Landeck-Zams", lat: 47.14842, lon: 10.57828, state: "T", kind: .rail, importance: 4)
    static let hall = Station(id: "at:47:1184", name: "Hall in Tirol", lat: 47.27727, lon: 11.50165, state: "T", kind: .rail, importance: 3)
    static let wienHbf = Station(id: "at:49:1349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W", kind: .rail, importance: 10,
                                 aliases: ["Wien Hbf"])
    static let stPoelten = Station(id: "at:43:4848", name: "St. Pölten Hauptbahnhof", lat: 48.20819, lon: 15.62404, state: "NÖ", kind: .rail, importance: 6)
    static let schottentor = Station(id: "wl:schottentor", name: "Wien Schottentor", lat: 48.2147, lon: 16.3612, state: "W", kind: .tramHub)
    /// A tram stop 3.9 km from Schottentor (invented name).
    static let suedtirolerPlatz = Station(id: "wl:gudrunstrasse", name: "Wien Gudrunstraße", lat: 48.1795, lon: 16.3500, state: "W", kind: .tramHub)
    /// Bus stops of two towns (the place database): everywhere, so they say little.
    static let tarrenzBus = Station(id: "at:47:bus1", name: "Tarrenz Dorfplatz", lat: 47.2680, lon: 10.8250, state: "T", kind: .stop, products: PlaceProducts.bus.rawValue)
    static let miemingBus = Station(id: "at:47:bus2", name: "Mieming Kirche", lat: 47.3000, lon: 11.0000, state: "T", kind: .stop, products: PlaceProducts.bus.rawValue)

    static let all = [innsbruck, telfs, imst, landeck, hall, wienHbf, stPoelten, schottentor, suedtirolerPlatz, tarrenzBus, miemingBus]
    static let lookup = StationList(all)
    static let matcher = StationMatcher(lookup: lookup)

    /// The relations the "official table" knows in these tests.
    static let relations: Set<String> = [PairHistory.key(innsbruck.id, landeck.id), PairHistory.key(wienHbf.id, stPoelten.id),
                                         PairHistory.key(innsbruck.id, hall.id), PairHistory.key(innsbruck.id, imst.id)]

    static func detector(config: DetectorConfig = DetectorConfig()) -> TripDetector {
        let known = relations
        return TripDetector(matcher: matcher, config: config, knownRelation: { known.contains(PairHistory.key($0, $1)) })
    }

    // MARK: Time

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// "2026-11-12T08:05:00+01:00".
    static func date(_ s: String) -> Date { iso.date(from: s)! }

    /// 12 Nov 2026, Vienna wall clock (CET, +01:00).
    static func nov12(_ hhmm: String) -> Date { date("2026-11-12T\(hhmm):00+01:00") }

    // MARK: Building blocks

    /// A visit at a station: `offset` metres to the north of its coordinate (the phone is rarely exactly on the platform).
    static func visit(_ station: Station, offset: Double = 40, arrival: Date?, departure: Date?, observed: Date? = nil) -> VisitRecord {
        let place = DetectionGeo.offset(station.location, meters: offset, bearingDegrees: 0)
        return VisitRecord(at: place, accuracyMeters: 60, arrival: arrival, departure: departure,
                           observedAt: observed ?? departure ?? arrival ?? Date())
    }

    static func km(_ a: Station, _ b: Station) -> Double { a.location.distanceKm(to: b.location) }
}

extension DetectionOutcome {
    /// The candidate of a test that expects exactly one.
    func onlyCandidate(file: StaticString = #filePath, line: UInt = #line) throws -> DetectedCandidate {
        XCTAssertEqual(candidates.count, 1, "candidates: \(candidates.map { "\($0.from.station.name)→\($0.to.station.name)" }), rejections: \(rejections.map(\.code))",
                       file: file, line: line)
        return try XCTUnwrap(candidates.first, file: file, line: line)
    }
}
