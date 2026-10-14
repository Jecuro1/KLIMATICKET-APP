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

    public init(stationName: String, plannedDeparture: Date, lineName: String? = nil) {
        self.stationName = stationName
        self.plannedDeparture = plannedDeparture
        self.lineName = lineName
    }
}
