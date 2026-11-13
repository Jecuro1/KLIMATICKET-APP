import Foundation

// Cockpit-Ansicht, part 6: the numbers of the HUD (docs/RADAR_COCKPIT.md). From the route, the train's place along it and the clock: the stop it
// heads for with platform, expected arrival and delay, the distance to it, the progress along the whole run with the stop ticks, the next flags.
// Pure: `now` is a parameter. The words are in `CockpitText`.

/// A stop ahead as a flag on the map and a row in the list: name, expected arrival, delay.
public struct CockpitStopFlag: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var eta: Date?
    public var delaySeconds: Int?
    public var state: RadarDelayState
    public var platform: PlatformLabel?
    /// Along the route from the train.
    public var distanceKm: Double
}

public struct CockpitSummary: Sendable, Equatable {
    public enum Phase: Sendable, Hashable {
        /// At the first stop, before the departure time.
        case beforeDeparture(stop: String, departure: Date?)
        /// Standing at a stop; leaves at `departure`.
        case atStop(stop: String, departure: Date?)
        case underway
        case arrived(stop: String)
        /// The whole run is cancelled.
        case cancelled
    }

    public var phase: Phase
    public var lineTitle: String
    public var destination: String?
    /// The stop the train will arrive at next; nil once arrived.
    public var nextStop: String?
    /// The next stop is the last one of the run (the last one the train calls at).
    public var nextIsFinal: Bool
    public var platform: PlatformLabel?
    /// Expected arrival there (the realtime when there is one).
    public var eta: Date?
    public var plannedETA: Date?
    /// Seconds late at that stop: the reported one, else carried on from the stop before; nil without any report.
    public var delaySeconds: Int?
    public var delayState: RadarDelayState
    /// Along the route; nil without a next stop.
    public var distanceKm: Double?
    /// 0 ... 1 along the whole run.
    public var progress: Double
    /// The stops on the progress bar, 0 ... 1 (the stops where the train calls).
    public var stopTicks: [Double]
    public var speed: CockpitSpeedEstimator.Reading
    /// How old the position behind this is.
    public var fixAge: TimeInterval?
    public var upcoming: [CockpitStopFlag]
    /// The route is the straight lines between the stops (no polyline).
    public var isStraightLine: Bool
    /// Only the radar's four stops are known (the full run is on its way): the next stop and its time are right, the distance and the
    /// progress along the chain of four stops are not, so neither is shown nor spoken (`CockpitFeed.frame`).
    public var isProvisional = false
    /// The next stop has no realtime of its own: `eta` is the planned time (nothing is predicted). With a delay carried on from an earlier
    /// stop, "21:02 +7 min" would read as "arrives 21:02, seven minutes late" and a countdown to 21:02 would be wrong by those minutes; the
    /// texts say "laut Fahrplan" and "zuletzt" instead (review 2, `CockpitText.arrivalNote`).
    public var etaIsPlanned = false

    /// The delay shown is the one of an earlier stop, and the time is the planned one.
    public var delayIsCarried: Bool { etaIsPlanned && delaySeconds != nil && delayState != .cancelled }

    /// The wait after which a stop's time counts as passed: the countdown is hidden, not shown negative.
    static let overdueSeconds = 120.0

    /// How many flags the map and the list show.
    public static let flagCount = 4

    public static func make(route: CockpitRoute, km: Double, now: Date, speed: CockpitSpeedEstimator.Reading = .unknown,
                            fixAge: TimeInterval? = nil, lineTitle: String, destination: String? = nil) -> CockpitSummary {
        let situation = route.situation(atKm: km, now: now)
        let nextIndex = route.nextStopIndex(atKm: km, now: now)
        let next = nextIndex.map { route.stops[$0] }
        let phase: Phase
        switch situation {
        case .beforeDeparture(let stop): phase = .beforeDeparture(stop: route.stops[stop].name, departure: route.stops[stop].departure)
        case .atStop(let stop): phase = .atStop(stop: route.stops[stop].name, departure: route.stops[stop].departure)
        case .between: phase = .underway
        case .arrived(let stop): phase = .arrived(stop: route.stops[stop].name)
        }
        let delay = nextIndex.flatMap { route.carriedDelay(at: $0) }
        let state: RadarDelayState = route.isCancelled ? .cancelled : CockpitRoute.state(forDelay: delay)
        let flags = route.upcoming(atKm: km, now: now, limit: flagCount).map { stop in
            CockpitStopFlag(id: stop.id, name: stop.name, eta: stop.expected, delaySeconds: route.carriedDelay(at: stop.id),
                            state: route.isCancelled ? .cancelled : CockpitRoute.state(forDelay: route.carriedDelay(at: stop.id)),
                            platform: stop.platform, distanceKm: max(stop.km - km, 0))
        }
        var summary = CockpitSummary(
            phase: route.isCancelled ? .cancelled : phase, lineTitle: lineTitle, destination: destination,
            nextStop: next?.name, nextIsFinal: next.map { $0.id == route.endIndex } ?? false, platform: next?.platform, eta: next?.expected, plannedETA: next.flatMap { $0.plannedArrival ?? $0.plannedDeparture },
            delaySeconds: delay, delayState: state, distanceKm: next.map { max($0.km - km, 0) },
            progress: route.progress(atKm: km), stopTicks: route.stops.filter(\.isServed).map { route.fraction(of: $0) },
            speed: speed, fixAge: fixAge, upcoming: flags, isStraightLine: route.isStraightLine)
        summary.etaIsPlanned = next.map { $0.ownDelay == nil } ?? false
        return summary
    }

    /// Seconds until the expected arrival: nil without one. Negative once it has passed.
    public func secondsToArrival(now: Date) -> TimeInterval? {
        eta.map { $0.timeIntervalSince(now) }
    }

    /// The countdown is shown: there is an arrival, and it has not been past for long. Not to a planned time while the train is known to be
    /// late: that count would be short by the delay.
    public func showsCountdown(now: Date) -> Bool {
        guard !delayIsCarried, let seconds = secondsToArrival(now: now) else { return false }
        return seconds > -Self.overdueSeconds
    }
}
