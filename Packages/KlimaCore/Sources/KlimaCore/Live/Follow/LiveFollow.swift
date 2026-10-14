import Foundation

// Live verfolgen (pure, injected clock): where the train is, what is next, what changed since the last update, and which
// stage the user is in. The app polls `JourneyDetails` (`TripDetails`) for one trip and feeds every answer through
// `snapshot` and `notices`. Nothing here does I/O; "now" is always a parameter.

/// The ride the user wants to follow: the HAFAS trip id plus the stations they board and leave.
public struct LiveFollowTarget: Sendable, Hashable, Codable {
    public var tripID: String
    public var lineName: String
    public var boardingStop: Location
    public var alightStop: Location
    public var plannedDeparture: Date?
    public var plannedArrival: Date?
    /// The next leg of the connection, when the user changes at `alightStop` (docs/OEBB_LIVE.md §R8). Nil for a single ride.
    public var transfer: FollowTransfer?

    public init(tripID: String, lineName: String, boardingStop: Location, alightStop: Location,
                plannedDeparture: Date? = nil, plannedArrival: Date? = nil, transfer: FollowTransfer? = nil) {
        self.tripID = tripID
        self.lineName = lineName
        self.boardingStop = boardingStop
        self.alightStop = alightStop
        self.plannedDeparture = plannedDeparture
        self.plannedArrival = plannedArrival
        self.transfer = transfer
    }
}

public struct LiveFollowSnapshot: Sendable, Hashable, Codable {
    public enum Phase: String, Sendable, Hashable, Codable {
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
    /// The user's stage (before departure, boarding, riding, transfer, arrived, cancelled), derived at the answer's time.
    public var stage: FollowStage
    /// The next leg, when the user changes at the alighting stop.
    public var transfer: FollowTransfer?
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

    /// Expected arrival at the alighting stop (realtime when known, else planned).
    public var arrivalEstimate: Date? { alighting?.arrival?.effective ?? alighting?.departure?.effective }

    /// Seconds between the expected arrival and the next leg's planned departure. Negative: the connection is missed.
    public var transferBufferSeconds: Int? {
        guard let transfer, let arrival = arrivalEstimate else { return nil }
        return Int(transfer.plannedDeparture.timeIntervalSince(arrival).rounded(.down))
    }

    /// Delay at the alighting stop (arrival, else departure); otherwise the latest delay the run reports.
    public var delaySeconds: Int? {
        if let d = alighting?.arrival?.delaySeconds ?? alighting?.departure?.delaySeconds { return d }
        return stopovers.reversed().lazy.compactMap { $0.arrival?.delaySeconds ?? $0.departure?.delaySeconds }.first
    }

    /// Platform the user boards on (realtime when announced, else planned).
    public var boardingPlatform: String? { boarding?.departure?.platform?.text ?? boarding?.arrival?.platform?.text }
    /// Platform at the alighting stop.
    public var alightingPlatform: String? { alighting?.arrival?.platform?.text ?? alighting?.departure?.platform?.text }

    public init(phase: Phase, stage: FollowStage = .beforeDeparture, stopovers: [Stopover], lastPassedIndex: Int?,
                boardingIndex: Int?, alightIndex: Int?, updatedAt: Date?, transfer: FollowTransfer? = nil) {
        self.phase = phase
        self.stage = stage
        self.transfer = transfer
        self.stopovers = stopovers
        self.lastPassedIndex = lastPassedIndex
        self.boardingIndex = boardingIndex
        self.alightIndex = alightIndex
        self.updatedAt = updatedAt
    }
}

/// Changes worth a notification (or an in-app line). Stop names are the HAFAS names, ready for display.
public enum LiveFollowNotice: Sendable, Hashable {
    /// Delay of at least the threshold started, or grew by that much again.
    case delay(minutes: Int, stop: String)
    /// Delay fell back below the threshold.
    case delayRecovered(stop: String)
    /// Platform changed at the boarding (`isBoarding`) or the alighting stop.
    case platform(stop: String, from: String?, to: String, isBoarding: Bool)
    case cancelled(stop: String)
    case arrived(stop: String)
    /// The train left the boarding stop.
    case departed(stop: String)
    /// The alighting stop is expected within `LiveFollow.arrivingSoonWindow`.
    case arrivingSoon(stop: String, minutes: Int)
    /// The change at `station` has less than `LiveFollow.tightTransferSeconds` to spare (negative: missed).
    case tightTransfer(station: String, bufferMinutes: Int)
}

public enum LiveFollow {
    /// Default delay threshold (5 min). The user can choose 3, 5 or 10 min (`FollowNoticeSettings`).
    public static let delayThresholdSeconds = 300
    /// Before the boarding departure, from this long on the stage is `.boarding`.
    public static let boardingWindow: TimeInterval = 10 * 60
    /// The "arriving soon" notice fires once the expected arrival is this close.
    public static let arrivingSoonWindow: TimeInterval = 10 * 60
    /// A change with less spare time than this is reported as tight.
    public static let tightTransferSeconds = 5 * 60

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
        let boardingIdx = index(of: target.boardingStop, in: stops) ?? (stops.isEmpty ? nil : 0)
        let alight = index(of: target.alightStop, in: stops) ?? (stops.isEmpty ? nil : stops.count - 1)

        let phase: LiveFollowSnapshot.Phase
        if trip.isCancelled {
            phase = .cancelled
        } else if let alight, let arrivedAt = stops[alight].arrival?.effective ?? stops[alight].departure?.effective, arrivedAt <= now {
            phase = .arrived
        } else if let boardingIdx, let left = stops[boardingIdx].departure?.effective ?? stops[boardingIdx].arrival?.effective, left <= now {
            phase = .underway
        } else if let boardingIdx, let lastPassed, lastPassed >= boardingIdx {
            phase = .underway
        } else {
            phase = .upcoming
        }
        let boardingDeparture = boardingIdx.flatMap { stops[$0].departure?.effective ?? stops[$0].arrival?.effective }
        return LiveFollowSnapshot(phase: phase,
                                  stage: stage(phase: phase, boardingDeparture: boardingDeparture,
                                               transfer: target.transfer, now: now),
                                  stopovers: stops, lastPassedIndex: lastPassed, boardingIndex: boardingIdx,
                                  alightIndex: alight, updatedAt: trip.realtimeUpdatedAt, transfer: target.transfer)
    }

    /// The user's stage. Before departure, the stage turns into `.boarding` `boardingWindow` before the departure.
    /// After arrival it is `.transfer` while the next leg is still ahead.
    public static func stage(phase: LiveFollowSnapshot.Phase, boardingDeparture: Date?, transfer: FollowTransfer?,
                             now: Date) -> FollowStage {
        switch phase {
        case .cancelled:
            return .cancelled
        case .arrived:
            if let transfer, transfer.plannedDeparture > now { return .transfer }
            return .arrived
        case .underway:
            return .riding
        case .upcoming:
            if let boardingDeparture, boardingDeparture.timeIntervalSince(now) <= boardingWindow { return .boarding }
            return .beforeDeparture
        }
    }

    /// What changed between two answers, plus the time-based notices (arriving soon, tight transfer) for the answer at
    /// `now`. Change notices need a previous answer: the first answer shows the state and is silent about it. Callers
    /// deduplicate with `FollowNoticeLedger`, so a time-based notice is delivered once, not on every poll.
    public static func notices(from previous: LiveFollowSnapshot?, to current: LiveFollowSnapshot, now: Date,
                               delayThreshold: Int = delayThresholdSeconds) -> [LiveFollowNotice] {
        var out: [LiveFollowNotice] = []
        let alightName = current.alighting?.location.name ?? "Ziel"
        let boardName = current.boarding?.location.name ?? "Start"

        if let previous {
            // Delay: a new threshold crossing, or growth by another threshold step.
            let before = previous.delaySeconds ?? 0
            let after = current.delaySeconds ?? 0
            if after >= delayThreshold, before < delayThreshold || after - before >= delayThreshold {
                out.append(.delay(minutes: after / 60, stop: alightName))
            } else if before >= delayThreshold, after < delayThreshold {
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
            if previous.phase == .upcoming, current.phase == .underway {
                out.append(.departed(stop: boardName))
            }
            if current.phase == .arrived, previous.phase != .arrived {
                out.append(.arrived(stop: alightName))
            }
        }

        // Time-based notices: the expected arrival and the change. Only while the train is underway.
        if current.phase == .underway, let eta = current.arrivalEstimate {
            let remaining = eta.timeIntervalSince(now)
            if remaining > 0, remaining <= arrivingSoonWindow {
                out.append(.arrivingSoon(stop: alightName, minutes: max(1, Int((remaining / 60).rounded(.up)))))
            }
            if let transfer = current.transfer, let buffer = current.transferBufferSeconds, buffer < tightTransferSeconds {
                out.append(.tightTransfer(station: transfer.stationName, bufferMinutes: Int((Double(buffer) / 60).rounded(.down))))
            }
        }
        return out
    }

    static func index(of stop: Location, in stops: [Stopover]) -> Int? {
        if let i = stops.firstIndex(where: { $0.location.lid == stop.lid }) { return i }
        if let ext = stop.extId, let i = stops.firstIndex(where: { $0.location.extId == ext }) { return i }
        return nil
    }
}
