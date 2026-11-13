import Foundation

// Live verfolgen, stages (docs/OEBB_LIVE.md §R8). Pure values: the stage is derived from the snapshot, the transfer and
// "now". Nothing here does I/O.

/// Where the user is on a followed ride, as the Live Activity, the notifications and the follow card show it.
public enum FollowStage: String, Sendable, Hashable, Codable, CaseIterable {
    /// More than `LiveFollow.boardingWindow` before the boarding departure.
    case beforeDeparture
    /// Within the boarding window before the boarding departure: platform and "Einsteigen" matter now.
    case boarding
    /// Left the boarding stop, not yet at the alighting stop.
    case riding
    /// Reached the alighting stop, and the next leg of the connection still lies ahead.
    case transfer
    /// Reached the alighting stop, nothing ahead.
    case arrived
    /// HAFAS reports the run as cancelled.
    case cancelled

    /// The follow is over: no more polling and no more notices.
    public var isFinished: Bool { self == .arrived || self == .cancelled }
}

/// The next leg of a connection. The user changes trains at the alighting stop of the followed ride.
public struct FollowTransfer: Sendable, Hashable, Codable {
    /// Name of the station where the user changes (the alighting stop of the followed ride).
    public var stationName: String
    /// Planned departure of the next leg at that station.
    public var plannedDeparture: Date
    /// Line of the next leg, e.g. "RJ 162", when known.
    public var lineName: String?
    // MARK: radar2-anschluss – the guard's estimate of the change (docs/CONNECTION_GUARD.md §6). Optional: records saved before decode as nil.
    /// Expected departure of the next leg at the station (realtime, else planned), as the Anschluss-Wächter last saw it.
    public var expectedDeparture: Date?
    /// When the guard saw `expectedDeparture`; older than `LiveFollow.transferEstimateLifetime` it is not used any more.
    public var expectedAt: Date?
    /// Walk between the two rides in whole minutes, when the connection says it.
    public var walkMinutes: Int?

    public init(stationName: String, plannedDeparture: Date, lineName: String? = nil,
                expectedDeparture: Date? = nil, expectedAt: Date? = nil, walkMinutes: Int? = nil) {
        self.stationName = stationName
        self.plannedDeparture = plannedDeparture
        self.lineName = lineName
        self.expectedDeparture = expectedDeparture
        self.expectedAt = expectedAt
        self.walkMinutes = walkMinutes
    }

    /// The departure the change is counted with at `now`: the guard's expected departure while it is at most
    /// `LiveFollow.transferEstimateLifetime` old, else the planned one (a warning too many rather than one too few).
    public func departureEstimate(now: Date) -> Date {   // MARK: radar2-anschluss
        if let expectedDeparture, let expectedAt, now.timeIntervalSince(expectedAt) <= LiveFollow.transferEstimateLifetime {
            return expectedDeparture
        }
        return plannedDeparture
    }
}
