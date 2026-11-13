import Foundation

// Pendel-Modus (docs/COMMUTE.md): the values every part of the commute logic shares. Pure values, no network, no storage.

/// Which way the commute runs: from the origin (home) to the destination, or back.
public enum CommuteDirection: String, Codable, CaseIterable, Sendable, Hashable {
    /// Origin → destination („Hinfahrt“, usually the morning).
    case outbound
    /// Destination → origin („Rückfahrt“).
    case inbound

    public var opposite: CommuteDirection { self == .outbound ? .inbound : .outbound }

    /// „Hinfahrt“ / „Rückfahrt“.
    public var title: String { self == .outbound ? "Hinfahrt" : "Rückfahrt" }
}

/// The weekdays and the two usual departure times of a commute. Times are minutes after midnight in Vienna local time
/// (`7 * 60 + 20` = 07:20), so a daylight-saving change never moves them.
public struct CommutePlan: Codable, Hashable, Sendable {
    public var weekdays: Set<RouteWeekday>
    /// Usual departure from the origin.
    public var outboundMinute: Int
    /// Usual departure from the destination, back home.
    public var returnMinute: Int

    public static let workdays: Set<RouteWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let defaultOutboundMinute = 7 * 60
    public static let defaultReturnMinute = 17 * 60

    public init(weekdays: Set<RouteWeekday> = CommutePlan.workdays, outboundMinute: Int = CommutePlan.defaultOutboundMinute,
                returnMinute: Int = CommutePlan.defaultReturnMinute) {
        self.weekdays = weekdays
        self.outboundMinute = CommutePlan.clamp(outboundMinute)
        self.returnMinute = CommutePlan.clamp(returnMinute)
    }

    /// The plan of a saved route: its weekdays and clock time are the outbound departure; the return keeps `returnMinute`.
    public init(schedule: RouteSchedule, returnMinute: Int = CommutePlan.defaultReturnMinute) {
        self.init(weekdays: schedule.weekdays, outboundMinute: schedule.hour * 60 + schedule.minute, returnMinute: returnMinute)
    }

    /// „Mo–Fr“, „Täglich“, „Mo, Mi, Fr“ (the words of „Meine Routen“).
    public var dayText: String {
        weekdays.isEmpty ? "kein Wochentag" : RouteSchedule(weekdays: weekdays, hour: 0, minute: 0).dayText
    }

    public func minute(for direction: CommuteDirection) -> Int {
        direction == .outbound ? outboundMinute : returnMinute
    }

    /// „07:20“.
    public static func clockText(_ minute: Int) -> String {
        let m = clamp(minute)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func clamp(_ minute: Int) -> Int { min(max(minute, 0), 24 * 60 - 1) }
}

/// One end of the commute: an app station id when known, and the name the trips used.
public struct CommuteEndpoint: Codable, Hashable, Sendable {
    public var stationID: String?
    public var name: String

    public init(stationID: String?, name: String) {
        self.stationID = stationID
        self.name = name
    }

    /// The identity two trips share when they start or end here: the station id, else the normalised name.
    public var key: String {
        if let stationID, !stationID.isEmpty { return "id:" + stationID }
        return "name:" + CommuteEndpoint.normalise(name)
    }

    static func normalise(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
