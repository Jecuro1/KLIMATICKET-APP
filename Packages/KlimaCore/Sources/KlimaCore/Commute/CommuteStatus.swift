import Foundation

// Pendel-Modus (docs/COMMUTE.md §4): the connection rows of the card, built from one journey search (origin → destination).
// The delay is the departure delay of the first ride at the origin, in whole minutes like every realtime label of the app.

/// How a connection's departure stands. Never shown by colour alone: the badge always carries text („+5“, „Ausfall“).
public enum CommuteSeverity: Int, Comparable, Sendable, Hashable, Codable {
    /// No realtime from the operator: the plan only.
    case scheduled
    /// 0 minutes (or early).
    case onTime
    /// 1–2 minutes: shown as „+2“, not highlighted.
    case slight
    /// From 3 minutes: amber.
    case late
    /// From 10 minutes: red, and the card looks for an alternative.
    case veryLate
    /// Cancelled (any ride of the connection): struck through, „Ausfall“.
    case cancelled

    public static func < (lhs: CommuteSeverity, rhs: CommuteSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One connection of the commute card.
public struct CommuteRow: Hashable, Sendable, Identifiable, Codable {
    public var id: String
    /// „RJX 162“, „S 1“, „Bus 4176“.
    public var lineTitle: String
    public var line: Line?
    public var mode: TransportMode
    /// Final destination of the first ride („Wien Hbf“), display-cleaned.
    public var direction: String?
    public var plannedDeparture: Date
    public var realtimeDeparture: Date?
    public var plannedArrival: Date?
    public var realtimeArrival: Date?
    /// Rounded departure delay; nil without realtime.
    public var delayMinutes: Int?
    public var severity: CommuteSeverity
    public var isCancelled: Bool
    public var platform: PlatformLabel?
    public var changes: Int
    /// HAFAS run id of the first ride („Live verfolgen“).
    public var tripID: String?

    public init(id: String, lineTitle: String, line: Line? = nil, mode: TransportMode, direction: String? = nil,
                plannedDeparture: Date, realtimeDeparture: Date? = nil, plannedArrival: Date? = nil, realtimeArrival: Date? = nil,
                delayMinutes: Int? = nil, severity: CommuteSeverity, isCancelled: Bool = false, platform: PlatformLabel? = nil,
                changes: Int = 0, tripID: String? = nil) {
        self.id = id
        self.lineTitle = lineTitle
        self.line = line
        self.mode = mode
        self.direction = direction
        self.plannedDeparture = plannedDeparture
        self.realtimeDeparture = realtimeDeparture
        self.plannedArrival = plannedArrival
        self.realtimeArrival = realtimeArrival
        self.delayMinutes = delayMinutes
        self.severity = severity
        self.isCancelled = isCancelled
        self.platform = platform
        self.changes = changes
        self.tripID = tripID
    }

    public var effectiveDeparture: Date { realtimeDeparture ?? plannedDeparture }
    public var effectiveArrival: Date? { realtimeArrival ?? plannedArrival }
    public var hasRealtime: Bool { delayMinutes != nil }
    /// „07:42“ (planned, Vienna).
    public var timeText: String { RealtimePresentation.time(plannedDeparture) }
    /// The badge: „pünktlich“, „+5“, „−1“, „Ausfall“; nil without realtime.
    public var badgeText: String? { CommuteStatus.badgeText(delayMinutes: delayMinutes, cancelled: isCancelled) }
}

public enum CommuteStatus {
    /// Amber from 3 minutes, red from 10 (the plan's thresholds).
    public static let amberFrom = 3
    public static let redFrom = 10
    /// A connection stays on the card until a minute after it left.
    public static let graceSeconds: TimeInterval = 60

    public static func severity(delayMinutes: Int?, cancelled: Bool) -> CommuteSeverity {
        if cancelled { return .cancelled }
        guard let delay = delayMinutes else { return .scheduled }
        if delay >= redFrom { return .veryLate }
        if delay >= amberFrom { return .late }
        if delay >= 1 { return .slight }
        return .onTime
    }

    public static func badgeText(delayMinutes: Int?, cancelled: Bool) -> String? {
        if cancelled { return "Ausfall" }
        guard let delay = delayMinutes else { return nil }
        if delay == 0 { return "pünktlich" }
        return delay > 0 ? "+\(delay)" : "−\(-delay)"
    }

    /// The row of one connection; nil when it has no ride (a walk only) or no planned departure.
    public static func row(_ journey: Journey) -> CommuteRow? {
        let rides = journey.rideLegs
        guard let first = rides.first, let planned = first.departure.planned else { return nil }
        let last = rides.last ?? first
        let cancelled = rides.contains { $0.isCancelled || $0.departure.isCancelled || $0.arrival.isCancelled }
        let delay = cancelled ? nil : minutes(first.departure)
        let mode = first.line?.mode ?? .train
        return CommuteRow(id: journey.id,
                          lineTitle: first.line.map { LinePresentation.title($0) } ?? mode.displayName,
                          line: first.line, mode: mode,
                          direction: first.direction.map { DisplayNames.name($0) },
                          plannedDeparture: planned, realtimeDeparture: cancelled ? nil : first.departure.realtime,
                          plannedArrival: last.arrival.planned, realtimeArrival: cancelled ? nil : last.arrival.realtime,
                          delayMinutes: delay, severity: severity(delayMinutes: delay, cancelled: cancelled), isCancelled: cancelled,
                          platform: JourneyPresentation.platformLabel(first.departure, mode: mode),
                          changes: max(0, rides.count - 1), tripID: first.tripID)
    }

    /// The connections still ahead (left at most a minute ago; a cancelled one by its plan), in planned order, one per id.
    public static func rows(_ journeys: [Journey], now: Date) -> [CommuteRow] {
        var seen: Set<String> = []
        return journeys.compactMap(row)
            .filter { ($0.isCancelled ? $0.plannedDeparture : $0.effectiveDeparture) >= now.addingTimeInterval(-graceSeconds) }
            .sorted { $0.plannedDeparture != $1.plannedDeparture ? $0.plannedDeparture < $1.plannedDeparture : $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
    }

    /// Rounded minutes like `RealtimePresentation` (nil without realtime).
    static func minutes(_ event: StopEvent) -> Int? {
        guard let planned = event.planned, let realtime = event.realtime else { return nil }
        return Int((realtime.timeIntervalSince(planned) / 60).rounded(.toNearestOrEven))
    }

    // MARK: Texts

    /// The line under the rows: „Stand 07:31 · Echtzeit“, „Stand 07:31 · Fahrplan“ (the answer had no realtime),
    /// „Stand 07:31 · jetzt offline“ (older rows kept while the network is gone) or „ohne Echtzeit (offline)“ (no rows: the plan).
    public static func dataAge(fetchedAt: Date?, hasRealtime: Bool, isOffline: Bool) -> String {
        guard let fetchedAt else { return "ohne Echtzeit (offline)" }
        if isOffline { return "Stand \(RealtimePresentation.time(fetchedAt)) · jetzt offline" }
        return "Stand \(RealtimePresentation.time(fetchedAt)) · \(hasRealtime ? "Echtzeit" : "Fahrplan")"
    }

    /// VoiceOver for one row: „Zug 07:42 nach Innsbruck, 5 Minuten verspätet, Gleis 4“.
    public static func spoken(_ row: CommuteRow, destination: String) -> String {
        var parts = ["\(row.mode.displayName) \(row.timeText) nach \(destination)"]
        if row.isCancelled {
            parts[0] += " fällt aus"
        } else if let delay = row.delayMinutes {
            parts.append(CommuteSpeech.delayPhrase(delay))
        } else {
            parts.append("laut Fahrplan")
        }
        if let platform = row.platform, !row.isCancelled {
            parts.append(platform.spoken + (platform.changed ? ", geändert" : ""))
        }
        if row.changes > 0 { parts.append(row.changes == 1 ? "1 Umstieg" : "\(row.changes) Umstiege") }
        return parts.joined(separator: ", ")
    }
}
