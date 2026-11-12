import Foundation

// Cockpit-Ansicht, part 4: a speed estimate (docs/RADAR_COCKPIT.md). The radar gives positions, not speeds: the speed is the distance between two
// answers divided by the time between them, smoothed over a few answers. The positions themselves are calculated by the server from the timetable
// and the reported delays (`trainPosMode` CALC), so this is the speed of that calculated point, not a speedometer. The cockpit says so ("geschätzt")
// and shows nothing while the train stands or when there is not yet an estimate.

public struct CockpitSpeedEstimator: Sendable {
    public enum Reading: Sendable, Hashable {
        /// Fewer than two answers, a gap too long to bridge, or the last answer is too old.
        case unknown
        /// The train did not move between the last two answers.
        case standing
        case moving(kmh: Double)

        public var kmh: Double? {
            if case .moving(let value) = self { return value }
            return nil
        }
    }

    public struct Config: Sendable, Equatable {
        /// Answers closer together than this are one answer (the same one twice).
        public var minSegment: TimeInterval = 3
        /// A gap longer than this restarts the estimate: the train could have done anything in between.
        public var maxGap: TimeInterval = 150
        /// The estimate is dropped when the last answer is older than this.
        public var staleAfter: TimeInterval = 90
        /// Time constant of the smoothing, seconds: about two answers at the 20 s rhythm.
        public var tau: TimeInterval = 40
        /// Above this the two positions are not one train moving (a jump of the calculation): the sample is dropped.
        public var maxPlausibleKmh = 350.0
        /// Below this between two answers the train stands.
        public var standingKmh = 2.0

        public init() {}
    }

    private struct Sample: Sendable {
        var coordinate: GeoPoint
        var km: Double?
        var at: Date
    }

    public let config: Config
    private var last: Sample?
    private var smoothedKmh: Double?
    private var lastSegmentKmh: Double?

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func reset() {
        last = nil
        smoothedKmh = nil
        lastSegmentKmh = nil
    }

    /// One answer: where the train was at `at`. `km` is the place along the route when known; the distance then follows the route, which is
    /// longer than the straight line on a curve.
    public mutating func add(coordinate: GeoPoint, km: Double? = nil, at: Date) {
        let sample = Sample(coordinate: coordinate, km: km, at: at)
        defer { if last.map({ at > $0.at }) ?? true { last = sample } }
        guard let previous = last, at > previous.at else { return }
        let dt = at.timeIntervalSince(previous.at)
        guard dt >= config.minSegment else { return }
        guard dt <= config.maxGap else {
            smoothedKmh = nil
            lastSegmentKmh = nil
            return
        }
        let metres: Double
        if let km, let before = previous.km, km >= before - 0.02 {
            metres = max(km - before, 0) * 1000
        } else {
            metres = previous.coordinate.distanceKm(to: coordinate) * 1000
        }
        let kmh = metres / dt * 3.6
        guard kmh.isFinite, kmh <= config.maxPlausibleKmh else {
            smoothedKmh = nil
            lastSegmentKmh = nil
            return
        }
        lastSegmentKmh = kmh
        if kmh < config.standingKmh {
            smoothedKmh = nil   // a stop is a stop: the next departure starts a new estimate, it is not averaged with the speed before
        } else if let smoothed = smoothedKmh {
            smoothedKmh = smoothed + (kmh - smoothed) * (1 - exp(-dt / config.tau))
        } else {
            smoothedKmh = kmh
        }
    }

    public func reading(now: Date) -> Reading {
        guard let last, let segment = lastSegmentKmh, now.timeIntervalSince(last.at) <= config.staleAfter else { return .unknown }
        if segment < config.standingKmh { return .standing }
        guard let smoothed = smoothedKmh else { return .unknown }
        return .moving(kmh: smoothed)
    }
}
