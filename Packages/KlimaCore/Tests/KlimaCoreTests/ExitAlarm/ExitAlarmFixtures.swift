import XCTest
@testable import KlimaCore

/// The run of the tests: Salzburg Hbf → Attnang-Puchheim → Linz Hbf → Amstetten → St. Pölten Hbf (public coordinates), a train at
/// 40 m/s. `t0` is the departure at Salzburg.
enum ExitAlarmFixtures {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed morning, no clock dependence
    static let salzburg = GeoPoint(latitude: 47.813, longitude: 13.045)
    static let attnang = GeoPoint(latitude: 48.002, longitude: 13.736)
    static let linz = GeoPoint(latitude: 48.290, longitude: 14.291)
    static let amstetten = GeoPoint(latitude: 48.122, longitude: 14.872)
    static let stPoelten = GeoPoint(latitude: 48.200, longitude: 15.620)

    static let stops: [(name: String, point: GeoPoint)] = [("Salzburg Hbf", salzburg), ("Attnang-Puchheim", attnang),
                                                           ("Linz Hbf", linz), ("Amstetten", amstetten), ("St. Pölten Hbf", stPoelten)]
    static let speed = 40.0

    /// Path from Salzburg through the stop with index `index`.
    static func path(to index: Int) -> [GeoPoint] { stops[0...index].map(\.point) }
    static func length(to index: Int) -> Double { GeoPath(path(to: index)).length }
    /// Seconds after `t0` at which the train reaches stop `index` at `speed` (no dwell).
    static func arrival(at index: Int) -> Date { t0.addingTimeInterval(length(to: index) / speed) }

    static func spec(stop index: Int, lead: ExitAlarmLead = .fiveMinutes, isTransfer: Bool = false, platform: String? = "4") -> ExitAlarmSpec {
        ExitAlarmSpec(tripID: "trip-1", lineName: "RJX 66", stopID: "lid-\(index)", stopName: stops[index].name,
                      stopCoordinate: stops[index].point, platform: platform, path: path(to: index),
                      plannedArrival: arrival(at: index), boardingDeparture: t0, lead: lead, isTransfer: isTransfer,
                      createdAt: t0.addingTimeInterval(-600), soundKey: "standard")
    }

    /// The track of the whole ride to stop `index` at `speed`, 5 s between fixes, then `extra` metres beyond it.
    static func fixes(toStop index: Int, speed: Double = speed, extraMeters: Double = 0, on stopsPath: [GeoPoint]? = nil) -> [LocationFix] {
        let track = ExitAlarmTrack(path: stopsPath ?? path(to: stops.count - 1), interval: 5)
        var segments = [ExitAlarmTrack.Segment(meters: length(to: index), speed: speed)]
        if extraMeters > 0 { segments.append(.init(meters: extraMeters, speed: speed)) }
        return track.fixes(from: t0, segments: segments)
    }
}

/// An engine with fakes and a clock the test moves. It plays the system too: a scheduled alarm that falls due rings.
final class ExitAlarmHarness {
    var now: Date
    let location: ScriptedLocationProvider
    let scheduler: FakeAlarmScheduler
    let persistence: MemoryAlarmPersistence
    let engine: ExitAlarmEngine
    /// Rings that the (simulated) system produced from scheduled alarms.
    private(set) var systemRings: [String] = []

    init(authorization: ExitAlarmLocationAuthorization = .always, kind: ExitAlarmKind = .alarmKit, start: Date = ExitAlarmFixtures.t0.addingTimeInterval(-600),
         book: ExitAlarmBook? = nil) {
        now = start
        location = ScriptedLocationProvider(authorization: authorization)
        scheduler = FakeAlarmScheduler(kind: kind)
        persistence = MemoryAlarmPersistence(book)
        var clockRef: (() -> Date)?
        engine = ExitAlarmEngine(location: location, scheduler: scheduler, persistence: persistence, clock: { clockRef?() ?? Date() })
        clockRef = { [unowned self] in self.now }
    }

    /// Everything that rang, from the engine's own ring effects and from the system's scheduled alarms.
    var ringCount: Int { scheduler.rings.count + systemRings.count }

    /// Moves the clock; scheduled alarms that fall due ring on the way (in order).
    func advance(to date: Date) {
        while let next = scheduler.scheduled.filter({ $0.value <= date }).min(by: { $0.value < $1.value }) {
            now = max(now, next.value)
            systemRings.append(next.key)
            scheduler.fireScheduled(next.key)
        }
        now = max(now, date)
        engine.tick()
    }

    /// Plays fixes in order, as they would arrive (the clock is the fix's time, a tick in between).
    func play(_ fixes: [LocationFix]) {
        for fix in fixes {
            advance(to: fix.time)
            location.deliver(fix)
        }
    }

    func state(_ id: String) -> ExitAlarmState? { engine.book.state(id: id) }
}
