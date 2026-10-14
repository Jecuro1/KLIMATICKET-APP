import Foundation

// Alarme einsehen (docs/ROUTES_ALARMS.md §2): the values behind the Alarms screen. No UserNotifications import here; the app
// reads the pending requests and maps them to these values.

/// When a local notification fires, stored as plain values so a paused alarm can be scheduled again.
public struct AlarmTrigger: Codable, Hashable, Sendable {
    /// A single moment (a departure reminder, a ticket reminder). nil for a calendar trigger.
    public var date: Date?
    /// A calendar pattern (weekday and clock time, a day of the month …). nil for a single moment.
    public var components: DateComponents?
    public var repeats: Bool

    public static func once(_ date: Date) -> AlarmTrigger {
        AlarmTrigger(date: date, components: nil, repeats: false)
    }

    public static func calendar(_ components: DateComponents, repeats: Bool) -> AlarmTrigger {
        AlarmTrigger(date: nil, components: components, repeats: repeats)
    }

    /// The next moment this trigger fires strictly after `now`; nil when it will not fire again.
    public func nextDate(after now: Date, calendar: Calendar) -> Date? {
        if let date { return date > now ? date : nil }
        guard let components else { return nil }
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }
}

/// An alarm the user switched off. Its notification is removed from the system while it is paused; this keeps what is needed
/// to schedule it again.
public struct PausedAlarm: Codable, Hashable, Sendable, Identifiable {
    /// The request identifier the alarm had.
    public var id: String
    public var kind: AlarmKind
    public var title: String
    public var body: String
    public var trigger: AlarmTrigger
    public var pausedAt: Date

    public init(id: String, kind: AlarmKind, title: String, body: String, trigger: AlarmTrigger, pausedAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.trigger = trigger
        self.pausedAt = pausedAt
    }

    /// A paused alarm can be switched on again while it still has a moment to fire.
    public func canResume(now: Date, calendar: Calendar) -> Bool {
        trigger.nextDate(after: now, calendar: calendar) != nil
    }
}

/// One row of the Alarms screen. `id` is a request identifier, or the group id of a saved route ("route.<id>").
public struct AlarmItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: AlarmKind
    public var title: String
    public var detail: String
    /// The next moment it fires; for a paused alarm the moment it would fire; nil when none is left.
    public var nextDate: Date?
    /// The schedule in words, e.g. "Mo–Fr · 07:20" for a repeating alarm; nil for a single moment.
    public var scheduleText: String?
    public var isOn: Bool
    /// False for a paused alarm whose moment has passed: it cannot be switched on again.
    public var canResume: Bool

    public init(id: String, kind: AlarmKind, title: String, detail: String, nextDate: Date?, scheduleText: String? = nil,
                isOn: Bool, canResume: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.nextDate = nextDate
        self.scheduleText = scheduleText
        self.isOn = isOn
        self.canResume = canResume
    }
}

public enum AlarmSorting {
    /// Switched-on alarms first, the soonest first. Then the paused ones, grouped by kind. Alarms without a moment come last
    /// within their group. Ties fall back to the identifier, so the order is stable.
    public static func sorted(_ items: [AlarmItem]) -> [AlarmItem] {
        items.sorted { a, b in
            if a.isOn != b.isOn { return a.isOn }
            if a.isOn {
                switch (a.nextDate, b.nextDate) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            } else if a.kind.sortRank != b.kind.sortRank {
                return a.kind.sortRank < b.kind.sortRank
            }
            return a.id < b.id
        }
    }
}

/// iOS accepts a limited number of pending local notifications per app (64 as far as the app knows; check Apple's current
/// documentation before relying on the exact number). The Alarms screen shows how full that is.
public enum PendingNoticeBudget {
    public static let systemLimit = 64

    public enum Level: Equatable, Sendable {
        case ok
        /// Three quarters of the limit or more: the Alarms screen warns.
        case nearLimit
        case full
    }

    public static func level(pending count: Int) -> Level {
        if count >= systemLimit { return .full }
        if count * 4 >= systemLimit * 3 { return .nearLimit }
        return .ok
    }
}
