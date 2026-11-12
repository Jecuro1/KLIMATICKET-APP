import SwiftUI
import KlimaCore

// MARK: radartime – synthetic trains for the Zeitreise (demo and CI screenshots only, no network). Invented timetables on the real main lines:
// nothing here is a real train, timetable or position. The fleet answers like the real radar: for any time it returns the runs that are on
// their way then, each with the four stops of a radar answer (origin, the stop last left, the stop ahead, the destination) and the position
// at that time. Delays are reported only for trains that have started (or start within 20 minutes), as the real answers do (docs/RADAR_TIMETRAVEL.md §R12).

enum RadarTimeDemoFleet {
    struct Corridor {
        var places: [(name: String, lat: Double, lon: Double)]
        var category: String
        var number: Int
        var kind: Kind
        var speedKmh: Double
        var headwayMinutes: Int
        var phaseMinutes: Int
        var dwellMinutes: Double

        enum Kind { case rjx, regional, suburban }
    }

    static let corridors: [Corridor] = [
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("St. Pölten Hbf", 48.208, 15.623), ("Amstetten", 48.122, 14.872),
                          ("Linz Hbf", 48.290, 14.291), ("Wels Hbf", 48.163, 14.026), ("Attnang-Puchheim", 48.002, 13.736),
                          ("Salzburg Hbf", 47.813, 13.045)],
                 category: "RJX", number: 60, kind: .rjx, speedKmh: 135, headwayMinutes: 30, phaseMinutes: 7, dwellMinutes: 2),
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("St. Pölten Hbf", 48.208, 15.623), ("Amstetten", 48.122, 14.872), ("Linz Hbf", 48.290, 14.291)],
                 category: "REX", number: 1, kind: .regional, speedKmh: 75, headwayMinutes: 30, phaseMinutes: 19, dwellMinutes: 1),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Wörgl Hbf", 47.492, 12.077), ("Innsbruck Hbf", 47.263, 11.401),
                          ("Landeck-Zams", 47.139, 10.567), ("Bludenz", 47.153, 9.822), ("Feldkirch", 47.239, 9.598), ("Bregenz", 47.505, 9.747)],
                 category: "RJX", number: 66, kind: .rjx, speedKmh: 115, headwayMinutes: 60, phaseMinutes: 12, dwellMinutes: 2),
        Corridor(places: [("Wien Hbf", 48.185, 16.375), ("Wiener Neustadt Hbf", 47.812, 16.234), ("Mürzzuschlag", 47.606, 15.686),
                          ("Bruck an der Mur", 47.411, 15.268), ("Graz Hbf", 47.073, 15.417)],
                 category: "RJX", number: 70, kind: .rjx, speedKmh: 110, headwayMinutes: 60, phaseMinutes: 24, dwellMinutes: 2),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Bischofshofen", 47.415, 13.218), ("Spittal-Millstättersee", 46.800, 13.490),
                          ("Villach Hbf", 46.617, 13.845), ("Klagenfurt Hbf", 46.616, 14.308)],
                 category: "RJX", number: 560, kind: .rjx, speedKmh: 105, headwayMinutes: 60, phaseMinutes: 41, dwellMinutes: 2),
        Corridor(places: [("Wien Floridsdorf", 48.264, 16.398), ("Wien Hbf", 48.185, 16.375), ("Wien Meidling", 48.175, 16.333),
                          ("Mödling", 48.085, 16.290), ("Baden", 48.007, 16.231)],
                 category: "S", number: 1, kind: .suburban, speedKmh: 42, headwayMinutes: 10, phaseMinutes: 3, dwellMinutes: 0.7),
        Corridor(places: [("Wien Hütteldorf", 48.196, 16.265), ("Wien Hbf", 48.185, 16.375), ("Wien Simmering", 48.168, 16.420), ("Flughafen Wien", 48.120, 16.560)],
                 category: "S", number: 7, kind: .suburban, speedKmh: 40, headwayMinutes: 15, phaseMinutes: 6, dwellMinutes: 0.7),
        Corridor(places: [("Wien Franz-Josefs-Bf", 48.226, 16.361), ("Tulln", 48.330, 16.050), ("Absdorf-Hippersdorf", 48.400, 15.900)],
                 category: "REX", number: 9, kind: .regional, speedKmh: 70, headwayMinutes: 30, phaseMinutes: 11, dwellMinutes: 1),
        Corridor(places: [("Wien Floridsdorf", 48.264, 16.398), ("Gänserndorf", 48.340, 16.720), ("Hohenau", 48.620, 16.900)],
                 category: "REX", number: 8, kind: .regional, speedKmh: 72, headwayMinutes: 30, phaseMinutes: 2, dwellMinutes: 1),
        Corridor(places: [("Graz Hbf", 47.073, 15.417), ("Leibnitz", 46.780, 15.540), ("Spielfeld-Straß", 46.717, 15.620)],
                 category: "S", number: 5, kind: .suburban, speedKmh: 55, headwayMinutes: 20, phaseMinutes: 9, dwellMinutes: 1),
        Corridor(places: [("Innsbruck Hbf", 47.263, 11.401), ("Hall in Tirol", 47.281, 11.505), ("Jenbach", 47.390, 11.760)],
                 category: "S", number: 1, kind: .suburban, speedKmh: 55, headwayMinutes: 20, phaseMinutes: 4, dwellMinutes: 1),
        Corridor(places: [("Linz Hbf", 48.290, 14.291), ("Wels Hbf", 48.163, 14.026), ("Attnang-Puchheim", 48.002, 13.736)],
                 category: "REX", number: 3, kind: .regional, speedKmh: 72, headwayMinutes: 30, phaseMinutes: 15, dwellMinutes: 1),
        Corridor(places: [("Feldkirch", 47.239, 9.598), ("Dornbirn", 47.414, 9.740), ("Bregenz", 47.505, 9.747)],
                 category: "S", number: 3, kind: .suburban, speedKmh: 60, headwayMinutes: 20, phaseMinutes: 13, dwellMinutes: 1),
        Corridor(places: [("Salzburg Hbf", 47.813, 13.045), ("Hallein", 47.680, 13.100), ("Golling-Abtenau", 47.600, 13.170)],
                 category: "S", number: 3, kind: .suburban, speedKmh: 55, headwayMinutes: 30, phaseMinutes: 17, dwellMinutes: 1),
    ]

    private struct Stop {
        var name: String
        var lat: Double
        var lon: Double
        var arrival: Date?
        var departure: Date?
    }

    private struct Run {
        var id: String
        var corridor: Corridor
        var stops: [Stop]
        var delay: Int?   // seconds, reported for every stop; nil: no report
    }

    /// Deterministic delay by run (the same trains are late in every screenshot).
    private static func delaySeconds(corridor: Int, direction: Int, k: Int) -> Int {
        let mixed = UInt64(bitPattern: Int64(k &* 2_654_435_761 &+ corridor &* 40_503 &+ direction &* 977)) % 100
        switch mixed {
        case ..<62: return 0
        case ..<78: return Int(60 * (2 + mixed % 3))
        case ..<92: return Int(60 * (6 + mixed % 7))
        default: return Int(60 * (15 + mixed % 11))
        }
    }

    /// The runs that are on their way at `time`.
    private static func runs(at time: Date, reportedFor now: Date) -> [Run] {
        var result: [Run] = []
        for (index, corridor) in corridors.enumerated() {
            for direction in 0..<2 {
                let places = direction == 0 ? corridor.places : Array(corridor.places.reversed())
                // Minutes from the first stop to every stop.
                var minutes: [Double] = [0]
                for i in 1..<places.count {
                    let km = GeoPoint(latitude: places[i - 1].lat, longitude: places[i - 1].lon)
                        .distanceKm(to: GeoPoint(latitude: places[i].lat, longitude: places[i].lon))
                    minutes.append(minutes[i - 1] + (i > 1 ? corridor.dwellMinutes : 0) + km / corridor.speedKmh * 60)
                }
                let duration = (minutes.last ?? 0) * 60
                let headway = Double(corridor.headwayMinutes) * 60
                let phase = Double(corridor.phaseMinutes + direction * corridor.headwayMinutes / 2) * 60
                let latest = ((time.timeIntervalSince1970 - phase) / headway).rounded(.down)
                let earliest = ((time.timeIntervalSince1970 - duration - phase) / headway).rounded(.up)
                guard earliest <= latest else { continue }
                for k in Int(earliest)...Int(latest) {
                    let departure = Date(timeIntervalSince1970: Double(k) * headway + phase)
                    let stops = places.indices.map { i -> Stop in
                        let at = departure.addingTimeInterval(minutes[i] * 60)
                        return Stop(name: places[i].name, lat: places[i].lat, lon: places[i].lon,
                                    arrival: i == 0 ? nil : at,
                                    departure: i == places.count - 1 ? nil : at.addingTimeInterval(i == 0 ? 0 : corridor.dwellMinutes * 60))
                    }
                    let delay = delaySeconds(corridor: index, direction: direction, k: k)
                    let reported = departure <= now.addingTimeInterval(20 * 60)
                    result.append(Run(id: "demo|time|\(index)|\(direction)|\(k)", corridor: corridor, stops: stops, delay: reported ? delay : nil))
                }
            }
        }
        return result
    }

    private static func line(_ corridor: Corridor) -> Line {
        switch corridor.kind {
        case .rjx: DemoScotty.rjx("\(corridor.category) \(corridor.number)", number: String(corridor.number))
        case .regional: DemoScotty.regional("\(corridor.category) \(corridor.number)", number: String(corridor.number))
        case .suburban: DemoScotty.suburban("\(corridor.category) \(corridor.number)", number: String(corridor.number))
        }
    }

    /// The vehicles on their way at `time`, as the radar answers: four stops each and the position at `time`. `now` decides which trains have
    /// reported delays.
    static func vehicles(at time: Date, reportedFor now: Date) -> [RadarVehicle] {
        runs(at: time, reportedFor: now).compactMap { run in
            let shift = Double(run.delay ?? 0)
            func effective(_ date: Date?) -> Date? { date?.addingTimeInterval(shift) }
            // Where the run is at `time`, by the same timetable the projection uses.
            let times: [(Date, Date)] = run.stops.map { (effective($0.arrival ?? $0.departure) ?? .distantPast, effective($0.departure ?? $0.arrival) ?? .distantPast) }
            guard let first = times.first, let last = times.last, time >= first.1, time <= last.0 else { return nil }
            var leftIndex = 0
            for i in run.stops.indices where times[i].1 <= time { leftIndex = i }
            let nextIndex = min(leftIndex + 1, run.stops.count - 1)
            let a = run.stops[leftIndex], b = run.stops[nextIndex]
            let span = times[nextIndex].0.timeIntervalSince(times[leftIndex].1)
            let fraction = nextIndex == leftIndex || span <= 0 ? 0 : min(max(time.timeIntervalSince(times[leftIndex].1) / span, 0), 1)
            let position = GeoPoint(latitude: a.lat + (b.lat - a.lat) * fraction, longitude: a.lon + (b.lon - a.lon) * fraction)
            let window = [0, leftIndex, nextIndex, run.stops.count - 1].reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
            let stopovers = window.map { i -> Stopover in
                let stop = run.stops[i]
                func event(_ planned: Date?) -> StopEvent? {
                    guard let planned else { return nil }
                    return StopEvent(planned: planned, realtime: run.delay == nil ? nil : planned.addingTimeInterval(shift),
                                     prognosis: run.delay == nil ? nil : .prognosed)
                }
                return Stopover(location: Location(lid: "demo|time|\(stop.name)", kind: .station, extId: nil, name: stop.name,
                                                    coordinate: GeoPoint(latitude: stop.lat, longitude: stop.lon)),
                                arrival: event(stop.arrival), departure: event(stop.departure), index: i)
            }
            return RadarVehicle(tripID: run.id, line: line(run.corridor), direction: run.stops.last?.name, coordinate: position, stopovers: stopovers)
        }
    }
}

/// Counts the calls of a demo service (the loading scene stops answering after a few).
final class RadarTimeDemoCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// Radar stub with the synthetic fleet: honours the time of the query, so a Zeitreise has something to project. `stallAfter`: from this
/// many answers on, requests never answer (the "Zeitreise lädt 3/12" scene stays where it is).
struct RadarTimeDemoService: RadarService {
    var now: @Sendable () -> Date = { Date() }
    var stallAfter: Int? = nil
    var counter = RadarTimeDemoCounter()

    func radar(_ query: RadarQuery) async throws -> RadarSnapshot {
        let call = counter.next()
        if let stallAfter, call > stallAfter {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(120))   // a little latency, as the real answers have
        let t = now()
        let vehicles = RadarTimeDemoFleet.vehicles(at: query.when, reportedFor: t).filter { vehicle in
            guard let line = vehicle.line else { return false }
            return !line.product.intersection(query.products).isEmpty && query.box.contains(vehicle.coordinate)
        }
        return RadarSnapshot(vehicles: Array(vehicles.prefix(max(query.maxVehicles, 0))), realtimeUpdatedAt: t)
    }
}

// MARK: - Screenshot host

/// CI scenes: the Zeitreise open at +45 minutes, playing, loading, and at the largest text size (synthetic trains, no network).
struct RadarTimeScreenshotHost: View {
    static let screens: Set<String> = ["radarTime", "radarTimePlaying", "radarTimeLoading", "radarTimeAX5"]

    let screen: String

    var body: some View {
        switch screen {
        case "radarTimePlaying":
            RadarView(preset: .timeTravelPlaying)
        case "radarTimeLoading":
            RadarView(preset: .timeTravelLoading)
        case "radarTimeAX5":
            RadarView(preset: .timeTravel).dynamicTypeSize(.accessibility5)
        default:
            RadarView(preset: .timeTravel)
        }
    }
}
