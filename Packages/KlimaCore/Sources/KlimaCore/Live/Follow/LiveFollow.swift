import Foundation

// Live verfolgen (pure, injected clock): where the train is, what is next, and what changed since the last update.
// The app polls `JourneyDetails` (`TripDetails`) for one trip and feeds every answer through `snapshot` and `notices`.
// Nothing here does I/O; "now" is always a parameter.

/// The ride the user wants to follow: the HAFAS trip id plus the stations they board and leave.
public struct LiveFollowTarget: Sendable, Hashable, Codable {
    public var tripID: String
    public var lineName: String
    public var boardingStop: Location
    public var alightStop: Location
    public var plannedDeparture: Date?
    public var plannedArrival: Date?

    public init(tripID: String, lineName: String, boardingStop: Location, alightStop: Location,
                plannedDeparture: Date? = nil, plannedArrival: Date? = nil) {
        self.tripID = tripID
        self.lineName = lineName
        self.boardingStop = boardingStop
        self.alightStop = alightStop
        self.plannedDeparture = plannedDeparture
        self.plannedArrival = plannedArrival
    }
}

public struct LiveFollowSnapshot: Sendable, Hashable {
    public enum Phase: String, Sendable, Hashable {
        /// Not yet departed from the boarding stop.
        case upcoming
        /// Left the boarding stop, not yet at the alighting stop.
        case underway
        /// Reached the alighting stop.
        case arrived
        /// HAFAS reports the run as cancelled.
        case cancelled
    }

    public var phase: Phase
    /// The full run in HAFAS order.
    public var stopovers: [Stopover]
    /// Index of the last stop the train has left (nil before the first departure).
    public var lastPassedIndex: Int?
    public var boardingIndex: Int?
    public var alightIndex: Int?
    /// Realtime time of the last data change for this run (`TripDetails.realtimeUpdatedAt`).
    public var updatedAt: Date?

    /// The next stops after the last one left, at most `limit`.
    public func nextStops(limit: Int) -> [Stopover] {
        let start = (lastPassedIndex ?? -1) + 1
        guard start < stopovers.count, limit > 0 else { return [] }
        return Array(stopovers[start..<min(stopovers.count, start + limit)])
    }

    public var boarding: Stopover? { boardingIndex.flatMap { stopovers.indices.contains($0) ? stopovers[$0] : nil } }
    public var alighting: Stopover? { alightIndex.flatMap { stopovers.indices.contains($0) ? stopovers[$0] : nil } }

    /// Delay at the alighting stop (arrival, else departure); otherwise the latest delay the run reports.
    public var delaySeconds: Int? {
        if let d = alighting?.arrival?.delaySeconds ?? alighting?.departure?.delaySeconds { return d }
        return stopovers.reversed().lazy.compactMap { $0.arrival?.delaySeconds ?? $0.departure?.delaySeconds }.first
    }

    /// Platform the user boards on (realtime when announced, else planned).
    public var boardingPlatform: String? { boarding?.departure?.platform?.text ?? boarding?.arrival?.platform?.text }
    /// Platform at the alighting stop.
    public var alightingPlatform: String? { alighting?.arrival?.platform?.text ?? alighting?.departure?.platform?.text }

    public init(phase: Phase, stopovers: [Stopover], lastPassedIndex: Int?, boardingIndex: Int?, alightIndex: Int?, updatedAt: Date?) {
        self.phase = phase
        self.stopovers = stopovers
        self.lastPassedIndex = lastPassedIndex
        self.boardingIndex = boardingIndex
        self.alightIndex = alightIndex
        self.updatedAt = updatedAt
    }
}

/// Changes worth a notification (or an in-app line). Stop names are the HAFAS names, ready for display.
public enum LiveFollowNotice: Sendable, Hashable {
    /// Delay of at least `LiveFollow.delayThresholdSeconds` started, or grew by that much again.
    case delay(minutes: Int, stop: String)
    /// Delay fell back below the threshold.
    case delayRecovered(stop: String)
    /// Platform changed at the boarding (`isBoarding`) or the alighting stop.
    case platform(stop: String, from: String?, to: String, isBoarding: Bool)
    case cancelled(stop: String)
    case arrived(stop: String)
}

public enum LiveFollow {
    public static let delayThresholdSeconds = 300

    /// Builds the snapshot for `target` from one `TripDetails` answer at time `now`. Stops are matched by location id
    /// (then extId); when a stop is not part of the run, the boarding falls back to the first and the alighting to the
    /// last stop, so the view still shows the train.
    public static func snapshot(_ trip: TripDetails, target: LiveFollowTarget, now: Date) -> LiveFollowSnapshot {
        let stops = trip.stopovers
        // Last stop whose departure (or, at the terminus, arrival) lies in the past.
        var lastPassed: Int?
        for (i, s) in stops.enumerated() {
            guard let left = s.departure?.effective ?? s.arrival?.effective else { continue }
            if left <= now { lastPassed = i }
        }
        let boarding = index(of: target.boardingStop, in: stops) ?? (stops.isEmpty ? nil : 0)
        let alight = index(of: target.alightStop, in: stops) ?? (stops.isEmpty ? nil : stops.count - 1)

        let phase: LiveFollowSnapshot.Phase
        if trip.isCancelled {
            phase = .cancelled
        } else if let alight, let arrivedAt = stops[alight].arrival?.effective ?? stops[alight].departure?.effective, arrivedAt <= now {
            phase = .arrived
        } else if let boarding, let left = stops[boarding].departure?.effective ?? stops[boarding].arrival?.effective, left <= now {
            phase = .underway
        } else if let boarding, let lastPassed, lastPassed >= boarding {
            phase = .underway
        } else {
            phase = .upcoming
        }
        return LiveFollowSnapshot(phase: phase, stopovers: stops, lastPassedIndex: lastPassed, boardingIndex: boarding,
                                  alightIndex: alight, updatedAt: trip.realtimeUpdatedAt)
    }

    /// What changed between two answers. No notices on the first answer (`previous == nil`): the user just opened the
    /// trip and already sees its state.
    public static func notices(from previous: LiveFollowSnapshot?, to current: LiveFollowSnapshot) -> [LiveFollowNotice] {
        guard let previous else { return [] }
        var out: [LiveFollowNotice] = []
        let alightName = current.alighting?.location.name ?? "Ziel"
        let boardName = current.boarding?.location.name ?? "Start"

        // Delay: a new threshold crossing, or growth by another threshold step.
        let before = previous.delaySeconds ?? 0
        let after = current.delaySeconds ?? 0
        if after >= delayThresholdSeconds, before < delayThresholdSeconds || after - before >= delayThresholdSeconds {
            out.append(.delay(minutes: after / 60, stop: alightName))
        } else if before >= delayThresholdSeconds, after < delayThresholdSeconds {
            out.append(.delayRecovered(stop: alightName))
        }

        // Platform changes at both ends of the ride.
        if let to = current.boardingPlatform, previous.boardingPlatform != to, let from = previous.boardingPlatform {
            out.append(.platform(stop: boardName, from: from, to: to, isBoarding: true))
        }
        if let to = current.alightingPlatform, previous.alightingPlatform != to, let from = previous.alightingPlatform {
            out.append(.platform(stop: alightName, from: from, to: to, isBoarding: false))
        }

        if current.phase == .cancelled, previous.phase != .cancelled {
            out.append(.cancelled(stop: boardName))
        }
        if current.phase == .arrived, previous.phase != .arrived {
            out.append(.arrived(stop: alightName))
        }
        return out
    }

    static func index(of stop: Location, in stops: [Stopover]) -> Int? {
        if let i = stops.firstIndex(where: { $0.location.lid == stop.lid }) { return i }
        if let ext = stop.extId, let i = stops.firstIndex(where: { $0.location.extId == ext }) { return i }
        return nil
    }
}
