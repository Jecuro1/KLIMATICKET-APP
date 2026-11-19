import Foundation
import KlimaCore

// MARK: radar2-radartrail – synthetic history for „Spuren“ in -KBDemo and the CI scenes (docs/RADAR_TRAILS.md §9). Nothing here is real: the corridor
// trains of `DemoScotty` on their invented timetable (positions earlier on their line, a train that waited at its first station stands there), one
// delay that grows for the trip sheet's line (REX 92: on time when it left, +9 now, as its stop list says), and the synthetic city fleets of radarmodes
// at earlier times (they run on the clock). Only vehicles with a synthetic id (`demo|…`) ever get a history, and only in demo or screenshot launches.
// No network.

/// The CI scenes of „Spuren“; the raw value is the screen name of `ScreenshotRouter`.
enum RadarTrailScene: String, CaseIterable, Sendable {
    case westbahn = "radarTrails"
    case city = "radarTrailsCity"
    case tooMany = "radarTrailsTooMany"
    case sheet = "radarTrailSheet"
    case settings = "radarTrailsSettings"
    case ax5 = "radarTrailsAX5"
    case sheetAX5 = "radarTrailSheetAX5"

    /// The setting the scene starts with (screenshot launches never read the stored one).
    var setting: RadarTrailSetting {
        switch self {
        case .westbahn: RadarTrailSetting(mode: .mine, minutes: 20)
        case .city: RadarTrailSetting(mode: .all, minutes: 5)
        case .tooMany: RadarTrailSetting(mode: .all, minutes: 10)
        default: .standard
        }
    }
}

enum RadarTrailDemo {
    /// The scene of this screenshot launch (set by `RadarTrailScreenshotHost` before the radar is built).
    @MainActor static var scene: RadarTrailScene?

    struct Answer: Sendable {
        var at: Date
        var vehicles: [RadarVehicle]
    }

    /// How far back the synthetic history reaches (the longest length), and its cadence (the radar's 20 s).
    static let historyMinutes = 20
    static let step = 20

    static let selectedTrip = "demo|radar|RJX66"
    static let followedTrip = "demo|radar|REX92"
    /// Between Amstetten and Wien: RJX 66 west of St. Pölten, REX 92 just out of Wien.
    static let westbahnCentre = GeoPoint(latitude: 48.17, longitude: 15.70)

    /// Demo data or a screenshot launch: the only launches whose radar answers come from the synthetic fleets.
    static var prefills: Bool { LaunchMode.isSandboxed || LaunchMode.useDemoData }

    static func isSynthetic(_ tripID: String) -> Bool { tripID.hasPrefix("demo|") }
    static func isCity(_ tripID: String) -> Bool { tripID.hasPrefix("demo|city|") }

    /// The corridor trains of `ids` every 20 s over the last ten minutes, on the timetable of `now` (the one the live demo answer uses).
    static func corridorHistory(ids: Set<String>, now: Date) -> [Answer] {
        let runs = DemoScotty.runs.filter { ids.contains($0.tripID) }
        guard !runs.isEmpty else { return [] }
        return stride(from: historyMinutes * 60, through: step, by: -step).map { back in
            let minutes = -Double(back) / 60
            let vehicles = runs.compactMap { run -> RadarVehicle? in
                guard let position = DemoScotty.position(of: run, at: minutes, now: now) ?? waiting(run, at: minutes) else { return nil }
                var stops = DemoScotty.stopovers(run, now: now)
                if run.tripID == followedTrip { stops = stops.map { delayed($0, minutes: risingDelay(minutesBack: -minutes)) } }
                return RadarVehicle(tripID: run.tripID, line: run.line, direction: run.direction, coordinate: position, stopovers: stops)
            }
            return Answer(at: now.addingTimeInterval(-Double(back)), vehicles: vehicles)
        }
    }

    /// The synthetic city fleets around `centre` every 20 s over the last ten minutes. Pure and off the main actor (about 30 fleets).
    static func cityHistory(around centre: GeoPoint, now: Date) -> [Answer] {
        let box = RadarBox.around(centre, halfSpan: 0.15)
        return stride(from: historyMinutes * 60, through: step, by: -step).map { back in
            let at = now.addingTimeInterval(-Double(back))
            let answer = RadarCityDemoFleet.answer(RadarQuery(box: box, when: at, products: [.bus, .tram, .subway], maxVehicles: 100_000))
            return Answer(at: at, vehicles: answer.vehicles)
        }
    }

    /// Before its first departure a run waits at its first station.
    private static func waiting(_ run: DemoScotty.Run, at minutes: Double) -> GeoPoint? {
        guard let first = run.stops.first, let departure = first.2, minutes < departure,
              let place = DemoScotty.stations[first.0] else { return nil }
        return GeoPoint(latitude: place.0, longitude: place.1)
    }

    /// REX 92 left Wien on time six minutes ago and has collected its delay on the way, minute by minute, up to the +9 of its stop list.
    static func risingDelay(minutesBack: Double) -> Int {
        switch minutesBack {
        case 5...: 0
        case 4..<5: 2
        case 3..<4: 4
        case 2..<3: 5
        case 1..<2: 7
        default: 9
        }
    }

    private static func delayed(_ stop: Stopover, minutes: Int) -> Stopover {
        var stop = stop
        func shift(_ event: StopEvent?) -> StopEvent? {
            guard var event, let planned = event.planned else { return event }
            event.realtime = planned.addingTimeInterval(Double(minutes) * 60)
            return event
        }
        stop.arrival = shift(stop.arrival)
        stop.departure = shift(stop.departure)
        return stop
    }

    /// The trip sheet's scenes: the run's own demo details in the sheet's cache before it asks (the demo timetable answers every trip with one
    /// sample run), so its header and stops say what the radar said.
    @MainActor static func prepareSheet(now: Date) {
        if let details = DemoScotty.trip(followedTrip, now: now) { RadarRouteCache.shared.store(details, now: now) }
    }

    /// The trip sheet's scenes: one answer of the corridor trains now, with the history before it (as the radar would have recorded it).
    @MainActor static func fill(_ trail: RadarTrailModel, now: Date) {
        trail.didMerge(RadarAnswerEvent(tile: RadarTileKey(level: 0, row: 0, col: 0), vehicles: DemoScotty.vehicles(now: now), requestedAt: now,
                                        products: .rail))
    }
}
