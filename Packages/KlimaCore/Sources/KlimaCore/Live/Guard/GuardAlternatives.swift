import Foundation

// Anschluss-Wächter, alternatives (docs/CONNECTION_GUARD.md §5): when the change is gone or shaky, one TripSearch from the
// transfer station to the journey's final destination – searched like the planner (its products, so „Nur mit KlimaTicket
// gültig“ holds) – and the best three. At most one new search per three minutes per guard; the result is kept that long.

public enum GuardAlternatives {
    /// Results asked for.
    public static let resultCount = 4
    /// Rows shown.
    public static let shownCount = 3
    /// One new search per this many seconds per guard (the result is kept as long).
    public static let searchSpacing: TimeInterval = 3 * 60
    /// Journeys arriving later than the original planned arrival plus this are dropped.
    public static let maxLaterArrival: TimeInterval = 3 * 60 * 60

    /// Where the search starts and from when.
    public struct Origin: Sendable, Hashable {
        public var location: Location
        public var date: Date
        /// The feeder is cancelled before it left: the search starts at the boarding stop.
        public var fromBoardingStop: Bool
    }

    /// Origin and time: the transfer station from the feeder's expected arrival plus the walk (never before now); a feeder
    /// cancelled before it left starts at its boarding stop, now.
    public static func origin(journey: Journey, feederRide: Int = 0, assessment: GuardAssessment?, now: Date) -> Origin? {
        guard let (a, _) = ConnectionGuard.legIndices(journey, feederRide: feederRide) else { return nil }
        let feeder = journey.legs[a]
        if assessment?.cancelledLeg == .feeder {
            let leftAlready = (assessment?.feederDeparture ?? feeder.departure.effective).map { $0 <= now } ?? false
            if !leftAlready { return Origin(location: feeder.origin, date: now, fromBoardingStop: true) }
            return Origin(location: feeder.destination, date: now, fromBoardingStop: false)
        }
        let arrival = assessment?.feederArrival ?? feeder.arrival.effective
        let walk = assessment?.walkMinutes ?? 0
        let ready = arrival.map { $0.addingTimeInterval(Double(walk) * 60) } ?? now
        return Origin(location: feeder.destination, date: max(now, ready), fromBoardingStop: false)
    }

    /// The TripSearch: origin as above, the journey's final destination, the planner's products, 4 results, no via, no
    /// stopovers, no polyline.
    public static func query(journey: Journey, feederRide: Int = 0, assessment: GuardAssessment?, products: ProductMask,
                             now: Date) -> JourneyQuery? {
        guard let start = origin(journey: journey, feederRide: feederRide, assessment: assessment, now: now),
              let destination = journey.destination else { return nil }
        return JourneyQuery(origin: start.location, destination: destination, via: [], date: start.date, isArrival: false,
                            products: products, results: resultCount, includeStopovers: false, includePolyline: false)
    }

    /// Drops departures before `date` (to the minute), cancelled journeys and those arriving more than three hours after the
    /// original planned arrival; sorted by arrival, then departure; the first three.
    public static func pick(_ journeys: [Journey], after date: Date, originalArrival: Date?) -> [Journey] {
        let earliest = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
        let latest = originalArrival?.addingTimeInterval(maxLaterArrival)
        let kept = journeys.filter { j in
            guard let departure = j.departure?.effective, let arrival = j.arrival?.effective else { return false }
            if departure < earliest { return false }
            if JourneyPresentation.isCancelled(j) || j.legs.contains(where: { $0.kind == .ride && $0.isCancelled }) { return false }
            if let latest, arrival > latest { return false }
            return true
        }
        let sorted = kept.sorted { x, y in
            let ax = x.arrival?.effective ?? .distantFuture, ay = y.arrival?.effective ?? .distantFuture
            if ax != ay { return ax < ay }
            return (x.departure?.effective ?? .distantFuture) < (y.departure?.effective ?? .distantFuture)
        }
        return Array(sorted.prefix(shownCount))
    }

    /// Minutes the alternative arrives after the original planned arrival (negative: earlier); nil when a time is missing.
    public static func deltaMinutes(_ journey: Journey, originalArrival: Date?) -> Int? {
        guard let original = originalArrival, let arrival = journey.arrival?.effective else { return nil }
        return TransferBuffer.roundedMinutes(from: original, to: arrival)
    }

    /// A new search is allowed (none yet, or the last one is at least three minutes old).
    public static func canSearch(lastSearchAt: Date?, now: Date) -> Bool {
        guard let lastSearchAt else { return true }
        return now.timeIntervalSince(lastSearchAt) >= searchSpacing
    }

    /// Seconds until the next search is allowed (0 when allowed now).
    public static func secondsUntilSearch(lastSearchAt: Date?, now: Date) -> TimeInterval {
        guard let lastSearchAt else { return 0 }
        return max(0, searchSpacing - now.timeIntervalSince(lastSearchAt))
    }

    /// The follow target of a journey's ride `ride` (0: the first): that ride leg, with the next ride leg as the change (like the
    /// planner's „Live verfolgen“), carrying the walk when the journey has one.
    public static func followTarget(_ journey: Journey, ride: Int = 0) -> LiveFollowTarget? {
        guard let (a, b) = change(journey, after: ride) ?? lastRide(journey, ride: ride) else { return nil }
        let leg = journey.legs[a]
        guard let tripID = leg.tripID else { return nil }
        var transfer: FollowTransfer?
        if let b, let planned = journey.legs[b].departure.planned {
            let next = journey.legs[b]
            let walk = ConnectionGuard.walk(journey, feeder: a, connection: b)
            transfer = FollowTransfer(stationName: next.origin.name, plannedDeparture: planned,
                                      lineName: next.line.map { LinePresentation.title($0) },
                                      walkMinutes: walk.known ? walk.minutes : nil)
        }
        return LiveFollowTarget(tripID: tripID, lineName: leg.line.map { LinePresentation.title($0) } ?? "Verbindung",
                                boardingStop: leg.origin, alightStop: leg.destination,
                                plannedDeparture: leg.departure.planned, plannedArrival: leg.arrival.planned, transfer: transfer)
    }

    private static func change(_ journey: Journey, after ride: Int) -> (Int, Int?)? {
        ConnectionGuard.legIndices(journey, feederRide: ride).map { ($0.feeder, $0.connection) }
    }

    /// The ride `ride` when it is the journey's last ride (no change after it).
    private static func lastRide(_ journey: Journey, ride: Int) -> (Int, Int?)? {
        let rides = journey.legs.indices.filter { journey.legs[$0].kind == .ride }
        guard ride >= 0, ride < rides.count else { return nil }
        return (rides[ride], nil)
    }
}
