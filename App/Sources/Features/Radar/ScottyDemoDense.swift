import Foundation
import KlimaCore

// MARK: radarall – about 1500 synthetic vehicles for the CI screenshots of the Austria-wide radar (demo only, no network).
// Generated from a fixed seed along invented corridors between the main places; nothing here is a real train, timetable or
// position. The service answers like the real one: only the vehicles inside the asked rectangle, at most `maxVehicles`.

extension DemoRadarService {
    func denseVehicles(for query: RadarQuery, at time: Date) -> [RadarVehicle] {
        let all = DenseDemo.vehicles(now: time) + DemoScotty.vehicles(now: time)
        let inside = all.filter { vehicle in
            guard let line = vehicle.line else { return false }
            return !line.product.intersection(query.products).isEmpty && query.box.contains(vehicle.coordinate)
        }
        return Array(inside.prefix(max(query.maxVehicles, 0)))
    }
}

enum DenseDemo {
    static let count = 1500

    /// A corridor: a polyline between places, a share of the vehicles, and the line names that run on it.
    private struct Corridor {
        var places: [(String, Double, Double)]
        var weight: Int
        var lines: [(category: String, number: Int, suburban: Bool)]
    }

    private static let corridors: [Corridor] = [
        // Westbahn: Wien – Salzburg – Innsbruck – Bregenz.
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("St. Pölten Hbf", 48.208, 15.623), ("Amstetten", 48.122, 14.872),
                          ("Linz Hbf", 48.290, 14.291), ("Wels Hbf", 48.163, 14.026), ("Attnang-Puchheim", 48.002, 13.736),
                          ("Salzburg Hbf", 47.813, 13.045)], weight: 150,
                 lines: [("RJX", 60, false), ("RJX", 62, false), ("REX", 1, false), ("IC", 512, false), ("REX", 3, false)]),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Wörgl Hbf", 47.492, 12.077), ("Innsbruck Hbf", 47.263, 11.401),
                          ("Landeck-Zams", 47.139, 10.567), ("Bludenz", 47.153, 9.822), ("Feldkirch", 47.239, 9.598),
                          ("Bregenz", 47.505, 9.747)], weight: 90,
                 lines: [("RJX", 66, false), ("RJX", 68, false), ("REX", 5, false), ("R", 5, false)]),
        // Südbahn and Semmering.
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("Wiener Neustadt Hbf", 47.812, 16.234), ("Mürzzuschlag", 47.606, 15.686),
                          ("Bruck an der Mur", 47.411, 15.268), ("Graz Hbf", 47.073, 15.417), ("Spielfeld-Straß", 46.717, 15.620)],
                 weight: 120, lines: [("RJX", 70, false), ("REX", 2, false), ("R", 2, false), ("IC", 516, false)]),
        // Tauern and Kärnten.
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Bischofshofen", 47.415, 13.218), ("Spittal-Millstättersee", 46.800, 13.490),
                          ("Villach Hbf", 46.617, 13.845), ("Klagenfurt Hbf", 46.616, 14.308)], weight: 70,
                 lines: [("RJX", 560, false), ("REX", 4, false), ("R", 4, false)]),
        Corridor(places: [("Bischofshofen", 47.415, 13.218), ("Selzthal", 47.545, 14.306), ("Leoben Hbf", 47.382, 15.094),
                          ("Bruck an der Mur", 47.411, 15.268)], weight: 50,
                 lines: [("IC", 518, false), ("REX", 6, false), ("R", 6, false)]),
        Corridor(places: [("Selzthal", 47.545, 14.306), ("Kirchdorf", 47.920, 14.120), ("Linz Hbf", 48.290, 14.291)], weight: 35,
                 lines: [("REX", 7, false), ("IC", 514, false), ("R", 7, false)]),
        // Nord, Ost, Franz-Josefs-Bahn.
        Corridor(places: [("Wien Floridsdorf", 48.264, 16.398), ("Gänserndorf", 48.340, 16.720), ("Hohenau", 48.620, 16.900)],
                 weight: 60, lines: [("REX", 8, false), ("S", 1, true), ("R", 8, false)]),
        Corridor(places: [("Wien Franz-Josefs-Bf", 48.226, 16.361), ("Tulln", 48.330, 16.050), ("Absdorf-Hippersdorf", 48.400, 15.900),
                          ("Gmünd NÖ", 48.770, 14.980)], weight: 40, lines: [("R", 40, false), ("REX", 9, false)]),
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("Bruck an der Leitha", 48.025, 16.780), ("Hegyeshalom", 47.880, 17.150)],
                 weight: 60, lines: [("RJX", 130, false), ("REX", 10, false), ("S", 60, true)]),
        // Westen und Süden.
        Corridor(places: [("Innsbruck Hbf", 47.263, 11.401), ("Brenner/Brennero", 47.000, 11.505)], weight: 25,
                 lines: [("RJX", 80, false), ("EC", 80, false), ("REX", 11, false)]),
        Corridor(places: [("Wörgl Hbf", 47.492, 12.077), ("Kufstein", 47.583, 12.168), ("Rosenheim", 47.857, 12.120)], weight: 25,
                 lines: [("RJX", 64, false), ("R", 12, false)]),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Freilassing", 47.840, 12.980), ("München Hbf", 48.140, 11.560)],
                 weight: 40, lines: [("RJX", 62, false), ("REX", 13, false)]),
        // S-Bahn: Wien and the other cities. Many short runs close to each other: this is what makes the clusters.
        Corridor(places: [("Wien Meidling", 48.175, 16.333), ("Mödling", 48.085, 16.290), ("Baden", 48.007, 16.231)], weight: 130,
                 lines: [("S", 1, true), ("S", 2, true), ("S", 3, true)]),
        Corridor(places: [("Wien Floridsdorf", 48.264, 16.398), ("Wien Hbf", 48.185, 16.375), ("Flughafen Wien", 48.120, 16.560)],
                 weight: 110, lines: [("S", 7, true), ("S", 80, true), ("S", 45, true)]),
        Corridor(places: [("Wien Hütteldorf", 48.196, 16.265), ("Wien Hbf", 48.185, 16.375), ("Wien Simmering", 48.168, 16.420)],
                 weight: 90, lines: [("S", 45, true), ("S", 50, true), ("S", 40, true)]),
        Corridor(places: [("Wien Floridsdorf", 48.264, 16.398), ("Mistelbach", 48.570, 16.570), ("Laa an der Thaya", 48.720, 16.390)],
                 weight: 40, lines: [("S", 2, true), ("R", 20, false)]),
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("Tullnerfeld", 48.250, 15.980), ("St. Pölten Hbf", 48.208, 15.623)],
                 weight: 70, lines: [("S", 50, true), ("REX", 14, false), ("RJX", 63, false)]),
        Corridor(places: [("Graz Hbf", 47.073, 15.417), ("Leibnitz", 46.780, 15.540), ("Spielfeld-Straß", 46.717, 15.620)], weight: 40,
                 lines: [("S", 5, true), ("S", 6, true)]),
        Corridor(places: [("Graz Hbf", 47.073, 15.417), ("Gleisdorf", 47.110, 15.710), ("Fehring", 46.930, 15.990)], weight: 35,
                 lines: [("S", 3, true), ("R", 30, false)]),
        Corridor(places: [("Graz Hbf", 47.073, 15.417), ("Köflach", 47.067, 15.083)], weight: 25, lines: [("S", 6, true), ("S", 7, true)]),
        Corridor(places: [("Linz Hbf", 48.290, 14.291), ("Steyr", 48.040, 14.420), ("Garsten", 47.980, 14.390)], weight: 30,
                 lines: [("S", 3, true), ("R", 31, false)]),
        Corridor(places: [("Linz Hbf", 48.290, 14.291), ("Gmunden", 47.918, 13.795), ("Attnang-Puchheim", 48.002, 13.736)],
                 weight: 35, lines: [("S", 6, true), ("R", 32, false)]),
        Corridor(places: [("Innsbruck Hbf", 47.263, 11.401), ("Hall in Tirol", 47.281, 11.505), ("Jenbach", 47.390, 11.760)],
                 weight: 40, lines: [("S", 1, true), ("S", 2, true), ("R", 33, false)]),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Hallein", 47.680, 13.100), ("Golling-Abtenau", 47.600, 13.170)],
                 weight: 25, lines: [("S", 3, true), ("S", 2, true)]),
        Corridor(places: [("Klagenfurt Hbf", 46.616, 14.308), ("Villach Hbf", 46.617, 13.845), ("Hermagor", 46.630, 13.370)],
                 weight: 20, lines: [("S", 1, true), ("R", 34, false)]),
        Corridor(places: [("Feldkirch", 47.239, 9.598), ("Dornbirn", 47.414, 9.740), ("Bregenz", 47.505, 9.747)], weight: 30,
                 lines: [("S", 1, true), ("S", 3, true)]),
    ]

    /// A fixed-seed generator, so a screenshot shows the same trains every time.
    private struct SplitMix {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    private struct Spec {
        var corridor: Int
        var offset: Double
        var forward: Bool
        var speed: Double          // corridor lengths per hour
        var line: Line
        var delayMinutes: Int?     // nil: no realtime
        var cancelled: Bool
    }

    private static let specs: [Spec] = {
        var rng = SplitMix(state: 0x4B4C_494D_4142_494C)
        let total = corridors.reduce(0) { $0 + $1.weight }
        var result: [Spec] = []
        for (index, corridor) in corridors.enumerated() {
            let share = Int((Double(corridor.weight) / Double(total) * Double(count)).rounded())
            let lengthKm = max(length(of: corridor), 1)
            for _ in 0..<share {
                let pick = corridor.lines[Int(rng.next() % UInt64(corridor.lines.count))]
                let roll = rng.unit()
                let delay: Int?
                if roll < 0.74 { delay = Int(rng.next() % 3) }
                else if roll < 0.90 { delay = 5 + Int(rng.next() % 21) }
                else if roll < 0.96 { delay = nil }
                else { delay = Int(rng.next() % 3) }
                let speedKmh = pick.suburban ? 45.0 : (pick.category == "RJX" ? 140.0 : 80.0)
                result.append(Spec(corridor: index, offset: rng.unit(), forward: rng.next() % 2 == 0,
                                   speed: speedKmh / lengthKm, line: line(pick.category, pick.number, suburban: pick.suburban),
                                   delayMinutes: delay, cancelled: roll >= 0.995))
            }
        }
        return result
    }()

    /// Rough length of a corridor in km (degrees to kilometres at Austria's latitude).
    private static func length(of corridor: Corridor) -> Double {
        zip(corridor.places, corridor.places.dropFirst()).reduce(0) { sum, pair in
            let dLat = (pair.1.1 - pair.0.1) * 111, dLon = (pair.1.2 - pair.0.2) * 74.5
            return sum + (dLat * dLat + dLon * dLon).squareRoot()
        }
    }

    private static func line(_ category: String, _ number: Int, suburban: Bool) -> Line {
        let name = "\(category) \(number)"
        let cls = suburban ? 32 : (category == "RJX" ? 1 : (category == "IC" || category == "EC" ? 4 : 16))
        return Line(name: name, fullName: name, category: category, categoryShort: category, lineNumber: String(number),
                    operatorName: "Demo", productClass: cls, mode: suburban ? .sBahn : .train)
    }

    /// The synthetic vehicles at `now`: each one moves along its corridor at a steady speed and turns round at the ends.
    static func vehicles(now: Date) -> [RadarVehicle] {
        let hours = now.timeIntervalSince1970 / 3600
        return specs.enumerated().map { index, spec in
            let corridor = corridors[spec.corridor]
            let travelled = spec.offset + (spec.forward ? 1 : -1) * spec.speed * hours
            // Fold into 0...1 and back: the vehicle runs to the end of the corridor and returns.
            let wrapped = travelled - 2 * (travelled / 2).rounded(.down)
            let along = wrapped <= 1 ? wrapped : 2 - wrapped
            let heading = (wrapped <= 1) == spec.forward   // true: towards the last place
            let (point, next) = position(on: corridor, at: along, towardsEnd: heading)
            let planned = now.addingTimeInterval(Double(300 + (index % 11) * 60))
            let realtime = spec.delayMinutes.map { planned.addingTimeInterval(Double($0) * 60) }
            let stop = Stopover(location: Location(lid: "demo|dense|\(next.0)", kind: .station, extId: nil, name: next.0,
                                                   coordinate: GeoPoint(latitude: next.1, longitude: next.2)),
                                arrival: StopEvent(planned: planned, realtime: realtime), departure: nil, index: 0)
            return RadarVehicle(tripID: "demo|dense|\(index)", line: spec.line, direction: next.0,
                                coordinate: point, stopovers: [stop], isCancelled: spec.cancelled)
        }
    }

    /// The point at `fraction` of the corridor's length, and the place the vehicle is heading for.
    private static func position(on corridor: Corridor, at fraction: Double, towardsEnd: Bool) -> (GeoPoint, (String, Double, Double)) {
        let places = corridor.places
        let lengths = zip(places, places.dropFirst()).map { a, b -> Double in
            let dLat = (b.1 - a.1) * 111, dLon = (b.2 - a.2) * 74.5
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        var remaining = fraction * lengths.reduce(0, +)
        for (index, length) in lengths.enumerated() {
            if remaining <= length || index == lengths.count - 1 {
                let t = length > 0 ? min(remaining / length, 1) : 0
                let a = places[index], b = places[index + 1]
                let point = GeoPoint(latitude: a.1 + (b.1 - a.1) * t, longitude: a.2 + (b.2 - a.2) * t)
                return (point, towardsEnd ? b : a)
            }
            remaining -= length
        }
        return (GeoPoint(latitude: places[0].1, longitude: places[0].2), places[0])
    }
}
