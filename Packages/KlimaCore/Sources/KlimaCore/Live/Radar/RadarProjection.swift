import Foundation

// Radar time travel, part 1: where a train is at a time other than now (docs/RADAR_TIMETRAVEL.md). Pure: no network, no clock.
//
// What an answer of the radar knows about a run (measured 2026-11-12, docs/RADAR_TIMETRAVEL.md §R12): the position at the time asked for and
// exactly four stops, in this order: the origin, the stop the train last left, the stop it is heading for, and the destination. Everything
// in between is unknown. So a single answer gives a calculated position only on the current leg (exact) and, beyond the next stop, on a straight
// line to the destination (rough). Several answers of the same trip (the timeline's snapshots) are merged: the stops of all of them, the
// freshest delays, and each answer's own position as a point the train passes through at that time.
//
// `RadarSchedule` is one answer's stops with the times the train is expected there: the planned time plus the delay that is known (the
// reported one, carried on to the stops after it). Nothing about the future is predicted: a delay that is not reported yet is not guessed.
// `RadarRunPath` is a schedule plus anchors, ready to be asked "where at time T": at a stop between arrival and departure the train stands
// there; between two waypoints the position is interpolated by time, along the route polyline when one is known, else on the straight
// line (`RadarPathKind` says which).

// MARK: - Schedule

/// One stop of a run: where it is and when the train is there, delays included.
public struct RadarScheduleStop: Sendable, Hashable {
    public var coordinate: GeoPoint
    /// The planned time (departure, else arrival): the order of the stops along a run, whatever the delays do.
    public var planned: Date
    public var arrival: Date
    public var departure: Date
    /// Seconds the train is late on arrival and on departure (reported, or carried on from the stop before).
    public var arrivalDelay: Int
    public var departureDelay: Int
    /// The answer reported a delay for this very stop (not carried on from another one).
    public var isReported: Bool

    public init(coordinate: GeoPoint, arrival: Date, departure: Date, arrivalDelay: Int = 0, departureDelay: Int = 0, planned: Date? = nil,
                isReported: Bool = false) {
        self.coordinate = coordinate
        self.arrival = arrival
        self.departure = departure
        self.arrivalDelay = arrivalDelay
        self.departureDelay = departureDelay
        self.planned = planned ?? departure.addingTimeInterval(-Double(departureDelay))
        self.isReported = isReported
    }
}

/// The stops of one run with the times the train is expected there. Compact on purpose (no names): the timeline keeps one per vehicle per
/// snapshot, and a Zeitreise holds a thousand vehicles in up to a dozen snapshots.
public struct RadarSchedule: Sendable, Hashable {
    public var stops: [RadarScheduleStop]
    /// A delay was reported for at least one stop. False: planned times only, the ring is grey.
    public var hasRealtime: Bool

    public init(stops: [RadarScheduleStop] = [], hasRealtime: Bool = false) {
        self.stops = stops
        self.hasRealtime = hasRealtime
    }

    /// Built from a vehicle's stop list. A stop without a coordinate or without any time cannot be placed and is left out. A stop's delay is
    /// the one reported for it; a stop without a report takes the delay of the last stop that has one (delays carry on along the run), and
    /// 0 before the first report. Times never run backwards: an arrival is not before the previous departure, a departure not before its
    /// arrival (a delay that shrinks along the run cannot make the train leave before it came).
    public init(_ vehicle: RadarVehicle) {
        var rows: [RadarScheduleStop] = []
        rows.reserveCapacity(vehicle.stopovers.count)
        var carried: Int?
        var reported = false
        var previousDeparture: Date?
        for stop in vehicle.stopovers {
            guard let coordinate = stop.location.coordinate, RadarSchedule.isValid(coordinate) else { continue }
            let plannedArrival = stop.arrival.flatMap { $0.planned ?? $0.realtime }
            let plannedDeparture = stop.departure.flatMap { $0.planned ?? $0.realtime }
            guard let base = plannedArrival ?? plannedDeparture else { continue }
            let reportedIn = Self.reportedDelay(stop.arrival)
            let reportedOut = Self.reportedDelay(stop.departure)
            let delayIn = reportedIn ?? reportedOut ?? carried ?? 0
            let delayOut = reportedOut ?? reportedIn ?? carried ?? 0
            if reportedIn != nil || reportedOut != nil {
                carried = delayOut
                reported = true
            }
            var arrival = (plannedArrival ?? base).addingTimeInterval(Double(delayIn))
            if let previousDeparture, arrival < previousDeparture { arrival = previousDeparture }
            var departure = (plannedDeparture ?? base).addingTimeInterval(Double(delayOut))
            if departure < arrival { departure = arrival }
            previousDeparture = departure
            rows.append(RadarScheduleStop(coordinate: coordinate, arrival: arrival, departure: departure, arrivalDelay: delayIn,
                                          departureDelay: delayOut, planned: plannedDeparture ?? plannedArrival ?? base,
                                          isReported: reportedIn != nil || reportedOut != nil))
        }
        stops = rows
        hasRealtime = reported
    }

    private static func reportedDelay(_ event: StopEvent?) -> Int? {
        guard let event, !event.isCancelled, let realtime = event.realtime else { return nil }
        return Int(realtime.timeIntervalSince(event.planned ?? realtime).rounded())
    }

    static func isValid(_ point: GeoPoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite && abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }

    /// A run needs two stops to have a path.
    public var isProjectable: Bool { stops.count >= 2 }
    public var firstDeparture: Date? { stops.first?.departure }
    public var lastArrival: Date? { stops.last?.arrival }

    /// The delay in seconds the train carries at `time`: that of the next stop it arrives at, the last stop's when the run is over,
    /// the first stop's before it starts. nil without a report.
    public func delay(at time: Date) -> Int? {
        guard hasRealtime, let first = stops.first, let last = stops.last else { return nil }
        if time <= first.departure { return first.departureDelay }
        guard let next = stops.first(where: { $0.arrival >= time }) else { return last.departureDelay }
        return next.arrivalDelay
    }
}

// MARK: - Merging answers

public extension RadarSchedule {
    /// One schedule from the stops of several answers of the same trip. A stop is the same stop when its coordinate is (within about 10 m).
    /// Per stop the freshest answer that reported a delay for it wins, else the freshest answer; the stops are ordered by their planned times.
    /// Two different stops at the same planned minute are a diversion: the fresher one stays. Times never run backwards after the merge.
    static func merged(_ parts: [(schedule: RadarSchedule, fetchedAt: Date)]) -> RadarSchedule {
        guard parts.count > 1 else { return parts.first?.schedule ?? RadarSchedule() }
        struct Key: Hashable { var lat: Int; var lon: Int }
        func key(_ point: GeoPoint) -> Key { Key(lat: Int((point.latitude * 1e4).rounded()), lon: Int((point.longitude * 1e4).rounded())) }
        var best: [Key: (fetchedAt: Date, stop: RadarScheduleStop)] = [:]
        for part in parts {
            for stop in part.schedule.stops {
                let k = key(stop.coordinate)
                if let current = best[k] {
                    // A reported delay beats a carried one; between equals the fresher answer wins.
                    if current.stop.isReported != stop.isReported {
                        if current.stop.isReported { continue }
                    } else if current.fetchedAt > part.fetchedAt {
                        continue
                    }
                }
                best[k] = (part.fetchedAt, stop)
            }
        }
        let ordered = best.values.sorted { a, b in
            a.stop.planned != b.stop.planned ? a.stop.planned < b.stop.planned : a.fetchedAt < b.fetchedAt
        }
        var stops: [RadarScheduleStop] = []
        var freshness: [Date] = []
        for entry in ordered {
            if let last = stops.last, abs(last.planned.timeIntervalSince(entry.stop.planned)) < 30 {
                // The same planned minute at another place: only the fresher answer's stop is real.
                if entry.fetchedAt >= freshness[freshness.count - 1] {
                    stops[stops.count - 1] = entry.stop
                    freshness[freshness.count - 1] = entry.fetchedAt
                }
                continue
            }
            stops.append(entry.stop)
            freshness.append(entry.fetchedAt)
        }
        var previousDeparture: Date?
        for index in stops.indices {
            if let previousDeparture, stops[index].arrival < previousDeparture { stops[index].arrival = previousDeparture }
            if stops[index].departure < stops[index].arrival { stops[index].departure = stops[index].arrival }
            previousDeparture = stops[index].departure
        }
        return RadarSchedule(stops: stops, hasRealtime: parts.contains { $0.schedule.hasRealtime })
    }
}

// MARK: - Anchor and result

/// The server's position at the time of its answer. The run passes through it.
public struct RadarAnchor: Sendable, Hashable {
    public var time: Date
    public var coordinate: GeoPoint

    public init(time: Date, coordinate: GeoPoint) {
        self.time = time
        self.coordinate = coordinate
    }
}

/// How the position between two stops was found. Said to the user: "Luftlinie" is a statement, not a detail.
public enum RadarPathKind: Sendable, Hashable {
    /// The train stands at a stop.
    case atStop
    /// Interpolated along the route polyline (JourneyDetails of the selected train).
    case polyline
    /// Interpolated on the straight line between two known points: no route is known.
    case straight
}

public enum RadarRunPhase: Sendable, Hashable {
    /// Standing at the stop with this index (of `RadarRunPath.stops`).
    case atStop(Int)
    /// Between the stop with this index and the next one.
    case between(Int)
}

public struct RadarProjected: Sendable, Equatable {
    public var coordinate: GeoPoint
    public var phase: RadarRunPhase
    public var path: RadarPathKind
    /// Direction of travel, degrees clockwise from north; nil when the train stands at its last stop.
    public var bearing: Double?
}

// MARK: - Run

/// A run ready to be asked "where is it at time T": the waypoints are, in time order, the arrival and departure of every stop and the anchors
/// (the server's positions at the times of its answers).
public struct RadarRunPath: Sendable {
    struct Waypoint: Sendable, Hashable {
        var time: Date
        var coordinate: GeoPoint
        /// The stop this waypoint belongs to (an anchor: the stop last passed before it).
        var stop: Int
    }

    public let stops: [RadarScheduleStop]
    public let hasRealtime: Bool
    let waypoints: [Waypoint]

    public init(schedule: RadarSchedule, anchors: [RadarAnchor] = []) {
        stops = schedule.stops
        hasRealtime = schedule.hasRealtime
        var points: [Waypoint] = []
        points.reserveCapacity(schedule.stops.count * 2 + anchors.count)
        for (index, stop) in schedule.stops.enumerated() {
            points.append(Waypoint(time: stop.arrival, coordinate: stop.coordinate, stop: index))
            points.append(Waypoint(time: stop.departure, coordinate: stop.coordinate, stop: index))
        }
        for anchor in anchors.sorted(by: { $0.time < $1.time }) {
            var low = 0, high = points.count
            while low < high {
                let mid = (low + high) / 2
                if points[mid].time > anchor.time { high = mid } else { low = mid + 1 }
            }
            points.insert(Waypoint(time: anchor.time, coordinate: anchor.coordinate, stop: low > 0 ? points[low - 1].stop : 0), at: low)
        }
        waypoints = points
    }

    /// The run needs two stops to have a path.
    public var isProjectable: Bool { stops.count >= 2 }
    public var firstTime: Date? { waypoints.first?.time }
    public var lastTime: Date? { waypoints.last?.time }

    /// The delay in seconds the train carries at `time`: that of the next stop it arrives at, the last stop's when the run is over, the first
    /// stop's before it starts. nil without a report.
    public func delay(at time: Date) -> Int? {
        guard hasRealtime, let first = stops.first, let last = stops.last else { return nil }
        if time <= first.departure { return first.departureDelay }
        guard let next = stops.first(where: { $0.arrival >= time }) else { return last.departureDelay }
        return next.arrivalDelay
    }

    /// The position at `time`, or nil when the run has not started (and was not held at its first stop by an answer) or is over.
    public func position(at time: Date, route: RadarRoute? = nil) -> RadarProjected? {
        guard isProjectable, let first = waypoints.first, let last = waypoints.last, time >= first.time, time <= last.time else { return nil }
        // The last waypoint at or before `time`.
        var low = 0, high = waypoints.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if waypoints[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        let from = waypoints[low]
        guard low < waypoints.count - 1 else {
            return RadarProjected(coordinate: from.coordinate, phase: .atStop(min(from.stop, stops.count - 1)), path: .atStop, bearing: nil)
        }
        let to = waypoints[low + 1]
        let span = to.time.timeIntervalSince(from.time)
        let fraction = span > 0 ? min(max(time.timeIntervalSince(from.time) / span, 0), 1) : 1
        if from.coordinate == to.coordinate {
            let next = from.stop + 1 < stops.count ? stops[from.stop + 1].coordinate : nil
            return RadarProjected(coordinate: from.coordinate, phase: .atStop(min(from.stop, stops.count - 1)), path: .atStop,
                                  bearing: next.map { RadarBearing.degrees(from: from.coordinate, to: $0) })
        }
        var path = RadarPathKind.straight
        var point = RadarProjection.lerp(from.coordinate, to.coordinate, fraction)
        if let route, let along = route.position(from: from.coordinate, to: to.coordinate, fraction: fraction) {
            point = along
            path = .polyline
        }
        // A segment of a few metres (the anchor next to its stop) says nothing about the direction: head for the stop after it.
        var target = to.coordinate
        if from.coordinate.distanceKm(to: to.coordinate) < 0.15, to.stop + 1 < stops.count {
            target = stops[to.stop + 1].coordinate
        }
        return RadarProjected(coordinate: point, phase: .between(min(from.stop, stops.count - 1)), path: path,
                              bearing: RadarBearing.degrees(from: point, to: target))
    }
}

// MARK: - Projection

public enum RadarProjection {
    /// An anchor further than this from the line between two stops (or beyond a third of its length) is not trusted.
    static let anchorOffTrackKm = 3.0
    static let anchorOffTrackShare = 0.35
    /// A train standing at a stop is within this of its coordinate.
    static let anchorAtStopKm = 1.5

    /// The position of one answer's schedule at `time`, through its own anchor if it has one. For callers that have one answer only; the
    /// timeline merges all answers of a trip into one `RadarRunPath`.
    public static func position(of schedule: RadarSchedule, anchor: RadarAnchor?, at time: Date, route: RadarRoute? = nil) -> RadarProjected? {
        RadarRunPath(schedule: schedule, anchors: anchor.map { [$0] } ?? []).position(at: time, route: route)
    }

    /// The anchor if it fits the schedule, else nil. It fits when, at its time, the train is
    /// - before its first departure and the position is at the first stop: the answer held it there (the timetable says it stands there),
    /// - between two stops and the position lies near the line between them (within `anchorOffTrackKm` or a third of its length,
    ///   from slightly before the first stop to slightly beyond the second).
    /// A train standing at a stop needs no anchor (the stop is exact), a run that is over has none.
    public static func validatedAnchor(for schedule: RadarSchedule, time: Date, coordinate: GeoPoint) -> RadarAnchor? {
        guard schedule.isProjectable, RadarSchedule.isValid(coordinate) else { return nil }
        let stops = schedule.stops
        let anchor = RadarAnchor(time: time, coordinate: coordinate)
        if time < stops[0].departure {
            return coordinate.distanceKm(to: stops[0].coordinate) <= anchorAtStopKm ? anchor : nil
        }
        guard time <= stops[stops.count - 1].arrival else { return nil }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if time >= a.arrival && time <= a.departure { return nil }   // standing at stop i
            guard time > a.departure, time < b.arrival else { continue }
            let origin = a.coordinate
            let (bx, by) = planar(b.coordinate, origin: origin)
            let (qx, qy) = planar(coordinate, origin: origin)
            let length = (bx * bx + by * by).squareRoot()
            if length < 0.1 { return (qx * qx + qy * qy).squareRoot() <= anchorAtStopKm ? anchor : nil }
            let along = (qx * bx + qy * by) / (length * length)
            let off = ((qx - along * bx) * (qx - along * bx) + (qy - along * by) * (qy - along * by)).squareRoot()
            guard along >= -0.15, along <= 1.15, off <= max(anchorOffTrackKm, anchorOffTrackShare * length) else { return nil }
            return anchor
        }
        return nil
    }

    static func lerp(_ a: GeoPoint, _ b: GeoPoint, _ t: Double) -> GeoPoint {
        GeoPoint(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Kilometres east and north of `origin` (flat approximation, good for distances of a few hundred kilometres at Austria's latitude).
    static func planar(_ point: GeoPoint, origin: GeoPoint) -> (x: Double, y: Double) {
        ((point.longitude - origin.longitude) * cos(origin.latitude * .pi / 180) * 111.32, (point.latitude - origin.latitude) * 110.574)
    }
}

// MARK: - Route polyline

/// The route of a run as a polyline (JourneyDetails of the selected train). Between two stops the projection runs along it instead of on
/// the straight line. Only built for the selected train: a polyline is 20 to 50 KB of text, a thousand of them are not worth it.
public struct RadarRoute: Sendable {
    public let points: [GeoPoint]
    private let cumulative: [Double]   // kilometres from the first point
    /// A stop further than this from the polyline means the polyline is not the route between those stops: the straight line is used.
    static let maxOffRouteKm = 1.5

    public init?(_ points: [GeoPoint]) {
        let usable = points.filter(RadarSchedule.isValid)
        guard usable.count >= 2 else { return nil }
        var sums = [0.0]
        sums.reserveCapacity(usable.count)
        for i in 1..<usable.count {
            sums.append(sums[i - 1] + usable[i - 1].distanceKm(to: usable[i]))
        }
        self.points = usable
        cumulative = sums
    }

    public var lengthKm: Double { cumulative.last ?? 0 }

    /// The point of the route nearest to `point` that lies at or after `fromKm`: its distance along the route and how far off it is.
    func nearest(to point: GeoPoint, fromKm: Double) -> (km: Double, offKm: Double)? {
        var best: (km: Double, offKm: Double)?
        for i in 0..<(points.count - 1) where cumulative[i + 1] >= fromKm {
            let a = points[i], b = points[i + 1]
            let (bx, by) = RadarProjection.planar(b, origin: a)
            let (qx, qy) = RadarProjection.planar(point, origin: a)
            let squared = bx * bx + by * by
            var t = squared > 0 ? (qx * bx + qy * by) / squared : 0
            t = min(max(t, 0), 1)
            var km = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
            if km < fromKm { km = fromKm; t = (cumulative[i + 1] - cumulative[i]) > 0 ? (km - cumulative[i]) / (cumulative[i + 1] - cumulative[i]) : 0 }
            let dx = qx - t * bx, dy = qy - t * by
            let off = (dx * dx + dy * dy).squareRoot()
            if best == nil || off < best!.offKm { best = (km, off) }
        }
        return best
    }

    /// The point `km` along the route (clamped to its ends).
    func point(atKm km: Double) -> GeoPoint {
        guard let last = cumulative.last, last > 0 else { return points[0] }
        let target = min(max(km, 0), last)
        var low = 0, high = cumulative.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= target { low = mid } else { high = mid }
        }
        let span = cumulative[high] - cumulative[low]
        return RadarProjection.lerp(points[low], points[high], span > 0 ? (target - cumulative[low]) / span : 0)
    }

    /// `fraction` of the way from `a` to `b` along the route. nil when a stop is not on the route (more than 1.5 km off) or `b` lies
    /// before `a` along it: the caller then uses the straight line.
    public func position(from a: GeoPoint, to b: GeoPoint, fraction: Double) -> GeoPoint? {
        guard let start = nearest(to: a, fromKm: 0), start.offKm <= Self.maxOffRouteKm,
              let end = nearest(to: b, fromKm: start.km), end.offKm <= Self.maxOffRouteKm, end.km > start.km else { return nil }
        return point(atKm: start.km + (end.km - start.km) * min(max(fraction, 0), 1))
    }
}
