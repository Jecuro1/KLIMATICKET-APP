import Foundation

// Cockpit-Ansicht, part 2: the run of the followed train as a route (docs/RADAR_COCKPIT.md). The stops of `JourneyDetails` with their times
// and delays, laid along the polyline when the answer has one (else along the straight lines between the stops), with a kilometre mark per
// stop. From it: where the train is in the run, the stop it heads for, the progress, and the delay tint of every leg.
// Pure: `now` is a parameter.

// MARK: - Stop

/// One stop of the run as the cockpit shows it.
public struct CockpitStop: Sendable, Hashable, Identifiable {
    /// Position in `CockpitRoute.stops`.
    public var id: Int
    public var name: String
    public var coordinate: GeoPoint
    /// Kilometres along the route.
    public var km: Double
    /// Expected times: the realtime when there is one, else the planned time.
    public var arrival: Date?
    public var departure: Date?
    public var plannedArrival: Date?
    public var plannedDeparture: Date?
    /// Seconds late, only when the operator reported it for this very stop (arrival, else departure).
    public var arrivalDelay: Int?
    public var departureDelay: Int?
    public var platform: PlatformLabel?
    /// The train does not stop here (the stop is only on the list because the line passes it): never "next stop".
    public var passesWithoutStop: Bool
    /// Every event of this stop is cancelled: the train skips it.
    public var isCancelled: Bool

    /// The train calls here: not a pass-through and not cancelled.
    public var isServed: Bool { !passesWithoutStop && !isCancelled }

    /// The delay this stop carries on its own: the arrival's, else the departure's.
    public var ownDelay: Int? { arrivalDelay ?? departureDelay }

    /// When the train is expected: the arrival, the departure at the first stop.
    public var expected: Date? { arrival ?? departure }
}

/// A piece of the route between two stops, tinted by the delay at its end.
public struct CockpitLeg: Sendable, Hashable, Identifiable {
    public var id: Int
    public var fromKm: Double
    public var toKm: Double
    public var state: RadarDelayState
}

/// Where the train is in its run.
public enum CockpitSituation: Sendable, Hashable {
    /// At the first stop, before the departure time.
    case beforeDeparture(stop: Int)
    /// Standing at a stop (between its arrival and its departure).
    case atStop(Int)
    /// On the way from the stop `from` (the last one it passed) to the stop `to` (the next one that it serves).
    case between(from: Int, to: Int)
    /// At the last stop.
    case arrived(stop: Int)
}

// MARK: - Route

public struct CockpitRoute: Sendable {
    public let stops: [CockpitStop]
    public let path: CockpitPath
    /// No polyline (or one that does not fit the stops): the route is the straight lines between the stops. Said in the cockpit:
    /// "Luftlinie zwischen den Halten".
    public let isStraightLine: Bool
    /// The whole run is cancelled (`isCncl`).
    public let isCancelled: Bool

    /// A stop further than this from the polyline means the polyline is not the route between the stops: the straight lines are used.
    static let maxOffRouteKm = 2.0
    /// Within this distance of a stop (and between its times) the train stands at it.
    static let atStopKm = 0.35
    /// Within this distance of the last stop the run is over.
    static let arrivedKm = 0.08

    /// The route of a run. `stopovers` in HAFAS order; stops without a usable coordinate or without any time are left out. nil with
    /// fewer than two stops left. `polyline` is the route's shape when the answer has one.
    public init?(stopovers: [Stopover], polyline: [GeoPoint]?, isCancelled: Bool = false) {
        var rows: [(stop: Stopover, coordinate: GeoPoint)] = []
        for stop in stopovers {
            guard let coordinate = stop.location.coordinate, CockpitGeo.isUsable(coordinate) else { continue }
            guard stop.arrival?.effective != nil || stop.departure?.effective != nil else { continue }
            rows.append((stop, coordinate))
        }
        guard rows.count >= 2 else { return nil }

        // Along the polyline when every stop sits on it, in order; else along the lines between the stops.
        var kms: [Double]?
        var chosen: CockpitPath?
        if let polyline, let shape = CockpitPath(polyline) {
            var found: [Double] = []
            var from = 0.0
            for row in rows {
                guard let hit = shape.project(row.coordinate, fromKm: from), hit.offKm <= Self.maxOffRouteKm else { found = []; break }
                found.append(hit.km)
                from = hit.km
            }
            if found.count == rows.count, let first = found.first, let last = found.last, last > first {
                kms = found
                chosen = shape
            }
        }
        let straight = chosen == nil
        guard let path = chosen ?? CockpitPath(rows.map(\.coordinate)) else { return nil }
        if kms == nil {
            // The path is the stops in a row: a stop's mark is its distance along it (stops at the same place share a mark).
            var sums = [0.0]
            for index in 1..<rows.count {
                sums.append(sums[index - 1] + rows[index - 1].coordinate.distanceKm(to: rows[index].coordinate))
            }
            kms = sums
        }
        let marks = kms ?? []

        var built: [CockpitStop] = []
        built.reserveCapacity(rows.count)
        for (index, row) in rows.enumerated() {
            let stop = row.stop
            let events = [stop.arrival, stop.departure].compactMap { $0 }
            built.append(CockpitStop(
                id: index, name: stop.location.name, coordinate: row.coordinate, km: marks[index],
                arrival: stop.arrival?.effective, departure: stop.departure?.effective,
                plannedArrival: stop.arrival?.planned, plannedDeparture: stop.departure?.planned,
                arrivalDelay: Self.delay(stop.arrival), departureDelay: Self.delay(stop.departure),
                platform: (stop.arrival ?? stop.departure).flatMap { JourneyPresentation.platformLabel($0, mode: .train) },
                passesWithoutStop: stop.passesWithoutStop,
                isCancelled: !events.isEmpty && events.allSatisfy(\.isCancelled)))
        }
        self.stops = built
        self.path = path
        self.isStraightLine = straight
        self.isCancelled = isCancelled
    }

    private static func delay(_ event: StopEvent?) -> Int? {
        guard let event, !event.isCancelled else { return nil }
        return event.delaySeconds
    }

    // MARK: Geometry

    public var firstKm: Double { stops.first?.km ?? 0 }
    public var lastKm: Double { stops.last?.km ?? 0 }
    /// Kilometres from the first to the last stop.
    public var runKm: Double { max(lastKm - firstKm, 0) }

    /// 0 ... 1 along the run, from the first to the last stop.
    public func progress(atKm km: Double) -> Double {
        guard runKm > 0 else { return 0 }
        return min(max((km - firstKm) / runKm, 0), 1)
    }

    /// A stop's place on the progress bar, 0 ... 1.
    public func fraction(of stop: CockpitStop) -> Double { progress(atKm: stop.km) }

    /// The train's kilometre mark for a position: the nearest point of the route, searched in a window around where the train was
    /// (`hintKm`) so a parallel track or a loop cannot catch it. Without a hint the whole route is searched. nil when the position is
    /// more than `maxOffRouteKm` from the route.
    public func km(of position: GeoPoint, hintKm: Double? = nil, windowKm: Double = 12) -> Double? {
        let hit: (km: Double, offKm: Double)?
        if let hintKm {
            hit = path.project(position, fromKm: hintKm - 0.5, toKm: hintKm + windowKm)
        } else {
            hit = path.project(position)
        }
        guard let hit, hit.offKm <= max(Self.maxOffRouteKm, 0.5) else { return nil }
        return hit.km
    }

    /// The point on the route at a mark.
    public func point(atKm km: Double) -> GeoPoint { path.point(atKm: km) }

    // MARK: Situation

    /// Where the train is, from its position along the route (`km`) and the clock. The position decides which leg it is on; the times
    /// decide whether it stands at a stop (the server holds a standing train at the stop between its arrival and its departure).
    public func situation(atKm km: Double, now: Date) -> CockpitSituation {
        let lastIndex = stops.count - 1
        // At the end of the run: the server keeps the train at the last stop.
        if km >= stops[lastIndex].km - Self.arrivedKm { return .arrived(stop: lastIndex) }
        // Close to a stop that the train serves: standing there between its arrival and its departure, or still waiting at the first stop.
        for stop in stops where stop.isServed && abs(km - stop.km) <= Self.atStopKm {
            let arrived = stop.arrival.map { $0 <= now } ?? true
            let departed = stop.departure.map { $0 <= now } ?? true
            if stop.id == 0 {
                if !departed { return .beforeDeparture(stop: 0) }
            } else if arrived && !departed {
                return .atStop(stop.id)
            } else if !arrived && km <= stop.km {
                return .between(from: stop.id - 1, to: stop.id)   // its time has not come: still approaching
            }
        }
        if km < stops[0].km - Self.atStopKm { return .beforeDeparture(stop: 0) }
        let from = stops.lastIndex { $0.km <= km } ?? 0
        return .between(from: from, to: nextServed(after: from, km: km) ?? lastIndex)
    }

    /// The first served stop after `index` that lies ahead of `km`.
    private func nextServed(after index: Int, km: Double) -> Int? {
        stops.first { $0.id > index && $0.km > km && ($0.isServed || $0.id == stops.count - 1) }?.id
    }

    /// The stop the train will arrive at next: the end of the leg it is on, or the first served stop after the one it stands at. nil at the end.
    public func nextStopIndex(atKm km: Double, now: Date) -> Int? {
        switch situation(atKm: km, now: now) {
        case .beforeDeparture(let stop), .atStop(let stop): return nextServed(after: stop, km: stops[stop].km)
        case .between(_, let to): return to
        case .arrived: return nil
        }
    }

    /// The served stops the train has still to reach, `limit` at most, nearest first.
    public func upcoming(atKm km: Double, now: Date, limit: Int) -> [CockpitStop] {
        guard let next = nextStopIndex(atKm: km, now: now) else { return [] }
        return Array(stops.filter { $0.id >= next && ($0.isServed || $0.id == stops.count - 1) }.prefix(max(limit, 0)))
    }

    // MARK: Tint

    /// What a delay says on the map: the radar's own rule (5 minutes or more is late).
    public static func state(forDelay seconds: Int?) -> RadarDelayState {
        guard let seconds else { return .unknown }
        return seconds >= RadarDelay.lateThresholdSeconds ? .late : .onTime
    }

    /// The legs between consecutive stops, each tinted by the delay at its end: the reported one, else the one carried on from the
    /// stop before (delays run along the line), else unknown. A cancelled stop colours the leg that ends there red; a cancelled run
    /// colours everything red.
    public var legs: [CockpitLeg] {
        var carried: Int?
        if let first = stops.first { carried = first.ownDelay }
        var out: [CockpitLeg] = []
        for index in 1..<stops.count {
            let stop = stops[index]
            if let own = stop.ownDelay { carried = own }
            let state: RadarDelayState
            if isCancelled || stop.isCancelled { state = .cancelled } else { state = Self.state(forDelay: stop.ownDelay ?? carried) }
            out.append(CockpitLeg(id: index - 1, fromKm: stops[index - 1].km, toKm: stop.km, state: state))
        }
        return out
    }

    /// The delay the train carries at the stop it heads for: that stop's own, else the last reported one before it.
    public func carriedDelay(at index: Int) -> Int? {
        guard stops.indices.contains(index) else { return nil }
        if let own = stops[index].ownDelay { return own }
        return stops[..<index].reversed().lazy.compactMap(\.ownDelay).first
    }
}
