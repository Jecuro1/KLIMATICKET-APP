import Foundation
import KlimaCore

// Demo data for Zug-Radar, Störungen and Live verfolgen (-KBDemo and CI screenshots). Generated locally from the
// clock: no network, no real train. Times are relative to "now", so the map always shows trains mid-journey.

/// Radar stub: positions interpolated along the demo runs.
struct DemoRadarService: RadarService {
    var now: @Sendable () -> Date = { Date() }

    func radar(_ query: RadarQuery) async throws -> RadarSnapshot {
        let t = now()
        let vehicles = DemoScotty.vehicles(now: t).filter { v in
            guard let line = v.line else { return false }
            return !line.product.intersection(query.products).isEmpty && query.box.contains(v.coordinate)
        }
        return RadarSnapshot(vehicles: vehicles, realtimeUpdatedAt: t)
    }
}

enum DemoScotty {
    /// (name, lat, lon) of the demo stations.
    static let stations: [String: (Double, Double)] = [
        "Wien Hbf": (48.185, 16.375), "St. Pölten Hbf": (48.200, 15.620), "Amstetten": (48.122, 14.872),
        "Linz Hbf": (48.290, 14.291), "Attnang-Puchheim": (48.002, 13.736), "Salzburg Hbf": (47.813, 13.045),
        "Bischofshofen": (47.415, 13.218), "Wörgl Hbf": (47.492, 12.077), "Innsbruck Hbf": (47.263, 11.401),
        "Wien Floridsdorf": (48.264, 16.398),
    ]

    struct Run {
        var tripID: String
        var line: Line
        var direction: String
        /// (station, planned arrival in minutes from now, planned departure, realtime delay in minutes, platform)
        var stops: [(String, Double?, Double?, Int, String)]
    }

    static func location(_ name: String) -> Location {
        let coord = stations[name].map { GeoPoint(latitude: $0.0, longitude: $0.1) }
        return Location(lid: "demo|\(name)", kind: .station, extId: nil, name: name, coordinate: coord)
    }

    static let runs: [Run] = [
        Run(tripID: "demo|radar|RJX66", line: rjx("RJX 66", number: "66"), direction: "Innsbruck Hbf", stops: [
            ("Wien Hbf", nil, -22, 0, "9"), ("St. Pölten Hbf", -8, -7, 1, "3"), ("Amstetten", 3, 4, 2, "2"),
            ("Linz Hbf", 26, 28, 5, "4"), ("Attnang-Puchheim", 44, 45, 5, "2"), ("Salzburg Hbf", 62, 64, 6, "7"),
            ("Wörgl Hbf", 98, 99, 6, "1"), ("Innsbruck Hbf", 118, nil, 7, "10"),
        ]),
        Run(tripID: "demo|radar|RJX1830", line: rjx("RJX 1830", number: "1830"), direction: "Wien Hbf", stops: [
            ("Innsbruck Hbf", nil, -15, 0, "4"), ("Wörgl Hbf", 18, 19, 0, "3"), ("Salzburg Hbf", 52, 53, 0, "5"),
            ("Attnang-Puchheim", 77, 78, 2, "1"), ("Linz Hbf", 96, 98, 3, "2"), ("Amstetten", 127, 128, 3, "1"), ("Wien Hbf", 152, nil, 3, "11"),
        ]),
        Run(tripID: "demo|radar|REX92", line: regional("REX 92", number: "92"), direction: "Wiener Neustadt Hbf", stops: [
            ("Wien Hbf", nil, -6, 0, "2"), ("St. Pölten Hbf", 30, 31, 9, "1"), ("Amstetten", 48, nil, 9, "2"),
        ]),
        Run(tripID: "demo|radar|S45", line: suburban("S 45", number: "45"), direction: "Wien Floridsdorf", stops: [
            ("Wien Hbf", nil, -2, 0, "1"), ("Wien Floridsdorf", 9, nil, 0, "2"),
        ]),
    ]

    static func rjx(_ name: String, number: String) -> Line {
        Line(name: name, fullName: name, category: "RJX", categoryShort: "RJX", categoryLong: "railjet xpress", trainNumber: number,
             operatorName: "ÖBB", productClass: 1, mode: .train)
    }

    static func regional(_ name: String, number: String) -> Line {
        Line(name: name, fullName: name, category: "REX", categoryShort: "REX", categoryLong: "Regional-Express", lineNumber: number,
             operatorName: "ÖBB", productClass: 16, mode: .train)
    }

    static func suburban(_ name: String, number: String) -> Line {
        Line(name: name, fullName: name, category: "S", categoryShort: "s", categoryLong: "S-Bahn", lineNumber: number,
             operatorName: "ÖBB", productClass: 32, mode: .sBahn)
    }

    static func stopovers(_ run: Run, now: Date) -> [Stopover] {
        run.stops.enumerated().map { index, stop in
            let (name, arr, dep, delay, platform) = stop
            func event(_ minutes: Double?, delayed: Bool) -> StopEvent? {
                guard let minutes else { return nil }
                let planned = now.addingTimeInterval(minutes * 60)
                return StopEvent(planned: planned, realtime: planned.addingTimeInterval(delayed ? Double(delay) * 60 : 0),
                                 plannedPlatform: Platform(text: platform), realtimePlatform: Platform(text: platform),
                                 prognosis: .prognosed)
            }
            return Stopover(location: location(name), arrival: event(arr, delayed: true), departure: event(dep, delayed: true),
                            index: index)
        }
    }

    /// Trains currently on the corridor (the run's stops bracket "now").
    static func vehicles(now: Date) -> [RadarVehicle] {
        runs.compactMap { run in
            let stops = stopovers(run, now: now)
            guard let position = position(of: run, at: 0, now: now) else { return nil }
            return RadarVehicle(tripID: run.tripID, line: run.line, direction: run.direction, coordinate: position, stopovers: stops)
        }
    }

    /// Linear interpolation between the last left stop and the next one.
    static func position(of run: Run, at minutes: Double, now: Date) -> GeoPoint? {
        let stops = run.stops
        for i in stops.indices.dropLast() {
            guard let dep = stops[i].2, let next = stops[i + 1].1 ?? stops[i + 1].2 else { continue }
            let a = stations[stops[i].0]!, b = stations[stops[i + 1].0]!
            if minutes >= dep, minutes < next {
                let f = (minutes - dep) / max(next - dep, 1)
                return GeoPoint(latitude: a.0 + (b.0 - a.0) * f, longitude: a.1 + (b.1 - a.1) * f)
            }
        }
        return nil
    }

    /// Trip for "Live verfolgen" in demo mode (the radar's runs).
    static func trip(_ tripID: String, now: Date) -> TripDetails? {
        guard let run = runs.first(where: { $0.tripID == tripID }) else { return nil }
        return TripDetails(tripID: tripID, line: run.line, direction: run.direction, stopovers: stopovers(run, now: now),
                           currentPosition: position(of: run, at: 0, now: now), realtimeUpdatedAt: now)
    }

    /// Störungen (HIM messages), relative to now.
    static func disruptions(now: Date) -> [Remark] {
        [
            Remark(kind: .disruption, id: "demo-him-1", title: "Bauarbeiten Wien Meidling", text: "Zwischen Wien Hbf und Meidling fährt die S 45 nur alle 20 Minuten. Bitte Ersatzverkehr mit der Bim 6 nutzen.",
                   validFrom: now.addingTimeInterval(-86_400), validUntil: now.addingTimeInterval(14 * 86_400),
                   modifiedAt: now.addingTimeInterval(-1_800), affectedLines: ["S 45", "S 80"]),
            Remark(kind: .disruption, id: "demo-him-2", title: "Streckensperre Tirol", text: "Zwischen Innsbruck Hbf und Landeck besteht Schienenersatzverkehr mit Bussen. Reisezeit ca. 45 Minuten länger.",
                   validFrom: now.addingTimeInterval(-7_200), validUntil: now.addingTimeInterval(3 * 86_400),
                   modifiedAt: now.addingTimeInterval(-5_400), affectedLines: ["RJX 66", "REX 5"]),
            Remark(kind: .disruption, id: "demo-him-3", title: "Verspätungen Westbahn", text: "Aufgrund einer Stellwerksstörung im Raum Linz kommt es zu Verspätungen von bis zu 20 Minuten.",
                   validFrom: now.addingTimeInterval(-3_600), validUntil: now.addingTimeInterval(6 * 3_600),
                   modifiedAt: now.addingTimeInterval(-900), affectedLines: ["RJ 1830"]),
            Remark(kind: .disruption, id: "demo-him-4", title: "Baustelle Bregenz Hauptbahnhof", text: "Die Rampe am Bahnsteig 2 ist bis Ende des Monats gesperrt.",
                   validFrom: now.addingTimeInterval(-5 * 86_400), validUntil: now.addingTimeInterval(9 * 86_400),
                   modifiedAt: now.addingTimeInterval(-86_400), affectedLines: ["R 9"]),
        ]
    }
}

/// Timetable stub for the follow tracker in demo mode.
enum DemoFollow {
    static func trip(_ tripID: String, now: Date) -> TripDetails? { DemoScotty.trip(tripID, now: now) }
}
