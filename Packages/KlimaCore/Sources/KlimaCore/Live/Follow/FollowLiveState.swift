import Foundation

// Live verfolgen, the state shown in the Live Activity (docs/OEBB_LIVE.md §R8). Pure and small: ActivityKit caps the
// content state at 4 KB, so this carries only what the Dynamic Island and the Lock Screen show.

public struct FollowLiveState: Codable, Hashable, Sendable {
    public var stage: FollowStage
    /// The next stop: the boarding stop before departure, the next stop while riding. Nil at the end.
    public var nextStopName: String?
    /// Effective time of `nextStopName` (realtime when known).
    public var nextStopTime: Date?
    /// Delay at the alighting stop in whole minutes (negative: early). Nil when HAFAS reports none.
    public var delayMinutes: Int?
    /// Platform: the boarding platform before and during boarding, the alighting platform while riding.
    public var platform: String?
    /// 0 to 1 across the stops between boarding and alighting.
    public var progress: Double
    /// Station where the user changes, when the follow is one leg of a connection.
    public var transferStation: String?
    /// Planned departure of the next leg, when the user changes.
    public var transferDeparture: Date?
    /// Time of the last answer that this state is built from.
    public var updatedAt: Date?

    public init(stage: FollowStage, nextStopName: String? = nil, nextStopTime: Date? = nil, delayMinutes: Int? = nil,
                platform: String? = nil, progress: Double = 0, transferStation: String? = nil,
                transferDeparture: Date? = nil, updatedAt: Date? = nil) {
        self.stage = stage
        self.nextStopName = nextStopName
        self.nextStopTime = nextStopTime
        self.delayMinutes = delayMinutes
        self.platform = platform
        self.progress = min(max(progress, 0), 1)
        self.transferStation = transferStation
        self.transferDeparture = transferDeparture
        self.updatedAt = updatedAt
    }

    /// The state for `snapshot` at `now`. `stage` is the snapshot's own stage, which is derived at the same time.
    public static func make(from snapshot: LiveFollowSnapshot, now: Date) -> FollowLiveState {
        let stage = snapshot.stage
        let delay = snapshot.delaySeconds.map { Int((Double($0) / 60).rounded()) }

        var nextName: String?
        var nextTime: Date?
        switch stage {
        case .beforeDeparture, .boarding:
            nextName = snapshot.boarding?.location.name
            nextTime = snapshot.boarding?.departure?.effective
        case .riding:
            if let next = snapshot.nextStops(limit: 1).first {
                nextName = next.location.name
                nextTime = (next.arrival ?? next.departure)?.effective
            }
        case .transfer, .arrived, .cancelled:
            break
        }

        let platform: String? = (stage == .beforeDeparture || stage == .boarding)
            ? snapshot.boardingPlatform
            : snapshot.alightingPlatform

        return FollowLiveState(stage: stage, nextStopName: nextName, nextStopTime: nextTime, delayMinutes: delay,
                               platform: platform, progress: progress(of: snapshot), transferStation: snapshot.transfer?.stationName,
                               transferDeparture: snapshot.transfer?.plannedDeparture, updatedAt: snapshot.updatedAt ?? now)
    }

    static func progress(of snapshot: LiveFollowSnapshot) -> Double {
        guard let boarding = snapshot.boardingIndex, let alight = snapshot.alightIndex, alight > boarding else {
            return snapshot.stage == .arrived || snapshot.stage == .transfer ? 1 : 0
        }
        switch snapshot.stage {
        case .beforeDeparture, .boarding, .cancelled:
            return 0
        case .transfer, .arrived:
            return 1
        case .riding:
            let passed = min(max(snapshot.lastPassedIndex ?? boarding, boarding), alight)
            return Double(passed - boarding) / Double(alight - boarding)
        }
    }
}

/// When the app should look at a follow again. These are requests and suggestions: iOS decides when a background refresh
/// runs (or whether it runs at all), so nothing here promises a time.
public enum FollowRefreshPlan {
    /// Foreground polling interval, in seconds, while the app is open.
    public static func pollInterval(stage: FollowStage, plannedDeparture: Date?, now: Date) -> TimeInterval {
        switch stage {
        case .riding: 60
        case .boarding, .transfer: 120
        case .beforeDeparture:
            if let plannedDeparture, plannedDeparture.timeIntervalSince(now) > 30 * 60 { 600 } else { 120 }
        case .arrived, .cancelled: 600
        }
    }

    /// The earliest moment to ask iOS for a background refresh, or nil when the follow is over. A request, not a schedule.
    public static func earliestBackgroundRefresh(stage: FollowStage, plannedDeparture: Date?, now: Date) -> Date? {
        switch stage {
        case .arrived, .cancelled:
            return nil
        case .boarding, .transfer:
            return now.addingTimeInterval(10 * 60)
        case .riding:
            return now.addingTimeInterval(15 * 60)
        case .beforeDeparture:
            if let plannedDeparture, plannedDeparture.timeIntervalSince(now) > 60 * 60 {
                return now.addingTimeInterval(60 * 60)
            }
            return now.addingTimeInterval(20 * 60)
        }
    }

    /// The Live Activity's stale date: ten minutes after the expected arrival, or 30 minutes from now when it is unknown.
    public static func staleDate(arrival: Date?, now: Date) -> Date {
        if let arrival { return arrival.addingTimeInterval(10 * 60) }
        return now.addingTimeInterval(30 * 60)
    }
}
