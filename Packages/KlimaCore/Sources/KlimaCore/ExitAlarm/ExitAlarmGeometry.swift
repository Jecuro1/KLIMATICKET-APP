import Foundation

// Aussteige-Wecker: distances along the run's stops and the speed estimate (docs/EXIT_ALARM.md §3). Pure.

/// The run as a polyline of its stops. The remaining distance of a fix is measured along it from the closest point.
public struct GeoPath: Sendable, Hashable {
    public let points: [GeoPoint]
    /// Metres from the first point to each point.
    public let cumulative: [Double]

    public var length: Double { cumulative.last ?? 0 }

    public init(_ points: [GeoPoint]) {
        self.points = points
        var total = 0.0
        var sums: [Double] = []
        for (index, point) in points.enumerated() {
            if index > 0 { total += GeoPath.meters(points[index - 1], point) }
            sums.append(total)
        }
        self.cumulative = sums
    }

    public struct Projection: Sendable, Hashable {
        /// Metres from the start of the path to the closest point.
        public var along: Double
        /// Metres between the position and the closest point.
        public var offPath: Double
    }

    /// The closest point of the path to `point`. Nil for a path of fewer than two points.
    public func project(_ point: GeoPoint) -> Projection? {
        guard points.count >= 2 else { return nil }
        var best: Projection?
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            let (t, off) = GeoPath.projectOnSegment(point, a, b)
            let segment = cumulative[index] - cumulative[index - 1]
            let candidate = Projection(along: cumulative[index - 1] + t * segment, offPath: off)
            if best == nil || off < best!.offPath { best = candidate }
        }
        return best
    }

    /// The point `distance` metres along the path (clamped to both ends). Nil for an empty path.
    public func point(at distance: Double) -> GeoPoint? {
        guard let first = points.first else { return nil }
        guard points.count >= 2 else { return first }
        let d = min(max(distance, 0), length)
        for index in 1..<points.count where cumulative[index] >= d {
            let segment = cumulative[index] - cumulative[index - 1]
            let f = segment > 0 ? (d - cumulative[index - 1]) / segment : 0
            let a = points[index - 1], b = points[index]
            return GeoPoint(latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f)
        }
        return points.last
    }

    /// Great-circle distance in metres.
    public static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double { a.distanceKm(to: b) * 1000 }

    /// Closest point on the segment a-b in a local flat projection (exact enough over a few hundred kilometres).
    static func projectOnSegment(_ p: GeoPoint, _ a: GeoPoint, _ b: GeoPoint) -> (t: Double, off: Double) {
        let radius = 6_371_008.8
        let lat0 = a.latitude * .pi / 180
        func xy(_ q: GeoPoint) -> (Double, Double) {
            ((q.longitude - a.longitude) * .pi / 180 * cos(lat0) * radius, (q.latitude - a.latitude) * .pi / 180 * radius)
        }
        let (bx, by) = xy(b)
        let (px, py) = xy(p)
        let lengthSquared = bx * bx + by * by
        guard lengthSquared > 0 else { return (0, (px * px + py * py).squareRoot()) }
        let t = min(max((px * bx + py * by) / lengthSquared, 0), 1)
        let dx = px - t * bx, dy = py - t * by
        return (t, (dx * dx + dy * dy).squareRoot())
    }
}

/// What one fix says about the target stop.
public struct ExitAlarmDistance: Sendable, Hashable {
    /// Metres still to go along the stops (or in a straight line when there is no path).
    public var remaining: Double
    /// Metres between the fix and the path. Large: the user is not on this run.
    public var offPath: Double
}

public enum ExitAlarmGeometry {
    /// A fix further from the stops' line than this is not on the run (a replacement bus, a car): no GPS estimate.
    public static let maxOffPath = 6_000.0
    /// Straight-line distance without a path is stretched by this, because rails are not straight.
    public static let detourFactor = 1.15

    /// The distance left for `fix` to the stop the spec names, or nil when it cannot be told.
    public static func distance(of fix: LocationFix, spec: ExitAlarmSpec) -> ExitAlarmDistance? {
        let path = GeoPath(spec.path)
        if let projection = path.project(fix.coordinate) {
            guard projection.offPath <= maxOffPath else { return nil }
            // The end of the path is the stop itself.
            return ExitAlarmDistance(remaining: max(path.length - projection.along, 0) + 0, offPath: projection.offPath)
        }
        guard let stop = spec.stopCoordinate else { return nil }
        let direct = GeoPath.meters(fix.coordinate, stop)
        return ExitAlarmDistance(remaining: direct * detourFactor, offPath: 0)
    }

    /// The straight-line distance to the stop in metres: the geofence and the "passed" detection use it.
    public static func straightDistance(of fix: LocationFix, spec: ExitAlarmSpec) -> Double? {
        guard let stop = spec.stopCoordinate ?? spec.path.last else { return nil }
        return GeoPath.meters(fix.coordinate, stop)
    }

    /// The average speed of the leg in metres per second (path length over the planned time), nil when unknown.
    public static func averageSpeed(of spec: ExitAlarmSpec) -> Double? {
        guard let start = spec.boardingDeparture, let end = spec.plannedArrival, end > start else { return nil }
        let length = GeoPath(spec.path).length
        guard length > 0 else { return nil }
        return length / end.timeIntervalSince(start)
    }

    /// Radius of the circle around the stop: `max(1500 m, speed × lead)`, capped. The speed is the smoothed one when there
    /// is one, else the leg's average speed, else a typical 25 m/s.
    public static func geofenceRadius(spec: ExitAlarmSpec, smoothedSpeed: Double?, config: ExitAlarmConfig = .standard) -> Double {
        let speed = smoothedSpeed.flatMap { $0 >= config.minTravelSpeed ? $0 : nil } ?? averageSpeed(of: spec) ?? 25
        return min(max(config.minGeofenceRadius, speed * spec.lead.seconds), config.maxGeofenceRadius)
    }
}

/// Speed smoothing over the fixes of one alarm. Not stored (it lives in memory with the newest fix only).
public struct ExitAlarmMotion: Sendable, Hashable {
    public private(set) var smoothedSpeed: Double?
    public private(set) var lastFix: LocationFix?

    public init() {}

    /// False when the fix is not usable: invalid, too inaccurate or older than the previous one.
    @discardableResult
    public mutating func ingest(_ fix: LocationFix, config: ExitAlarmConfig = .standard) -> Bool {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= config.maxAccuracy else { return false }
        if let last = lastFix, fix.time <= last.time { return false }
        var measured: Double?
        if let speed = fix.speed, speed >= 0 {
            measured = speed
        } else if let last = lastFix {
            let dt = fix.time.timeIntervalSince(last.time)
            if dt >= 1, dt <= 120 { measured = GeoPath.meters(last.coordinate, fix.coordinate) / dt }
        }
        if let measured {
            if let previous = smoothedSpeed, let last = lastFix {
                let dt = max(fix.time.timeIntervalSince(last.time), 0.1)
                let alpha = 1 - exp(-dt / config.speedTimeConstant)
                smoothedSpeed = previous + alpha * (measured - previous)
            } else {
                smoothedSpeed = measured
            }
        }
        lastFix = fix
        return true
    }

    /// True when there is a fix that is no older than `staleFixAge` at `now`.
    public func isFresh(at now: Date, config: ExitAlarmConfig = .standard) -> Bool {
        guard let lastFix else { return false }
        return now.timeIntervalSince(lastFix.time) <= config.staleFixAge
    }

    /// The moment the stop is reached by the GPS estimate: the time of the fix plus the remaining distance over the
    /// smoothed speed. Nil when standing (below `minTravelSpeed`), when the speed is unknown or when the fix is stale. A
    /// standing train gives no estimate instead of an infinite one: the timetable carries the alarm then.
    public func arrival(remaining: Double, at now: Date, config: ExitAlarmConfig = .standard) -> Date? {
        guard isFresh(at: now, config: config), let lastFix, let speed = smoothedSpeed, speed >= config.minTravelSpeed else { return nil }
        let seconds = remaining / speed
        guard seconds.isFinite, seconds < 24 * 3600 else { return nil }
        return lastFix.time.addingTimeInterval(seconds)
    }
}
