import Foundation

// Gespeicherte Routen („Meine Routen“, docs/ROUTES_ALARMS.md §1): a weekday and clock pattern for a saved route. Pure values:
// no notification and no network here. The app turns `reminderSlots` into repeating local notifications and `nextDeparture`
// into the „nächste Abfahrt“ line.

/// A weekday, Monday first (the Austrian calendar order).
public enum RouteWeekday: Int, CaseIterable, Codable, Sendable, Hashable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    /// The `Calendar` numbering: 1 = Sunday … 7 = Saturday.
    public var calendarWeekday: Int {
        self == .sunday ? 1 : rawValue + 2
    }

    public init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2...7: self = RouteWeekday.allCases[calendarWeekday - 2]
        default: return nil
        }
    }

    /// „Mo“ … „So“.
    public var shortName: String {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][rawValue]
    }
}

/// One repeating reminder moment: a weekday and a clock time (already shifted by the lead time).
public struct ReminderSlot: Codable, Hashable, Sendable {
    public var weekday: RouteWeekday
    public var hour: Int
    public var minute: Int

    public init(weekday: RouteWeekday, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

/// Weekday pattern and time of a saved route. `leadMinutes` is how long before the departure the reminder fires.
public struct RouteSchedule: Codable, Hashable, Sendable {
    public var weekdays: Set<RouteWeekday>
    public var hour: Int
    public var minute: Int
    public var leadMinutes: Int

    /// The lead times the editor offers.
    public static let leadChoices = [0, 5, 10, 15, 30]

    public init(weekdays: Set<RouteWeekday>, hour: Int, minute: Int, leadMinutes: Int = 10) {
        self.weekdays = weekdays
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.leadMinutes = RouteSchedule.leadChoices.contains(leadMinutes) ? leadMinutes : 10
    }

    /// The stored form (`FavoriteRouteEntity.scheduleRaw`): "<weekday numbers>;HH:mm;<lead>", e.g. "0,1,2,3,4;07:30;10".
    public var raw: String {
        let days = weekdays.map(\.rawValue).sorted().map(String.init).joined(separator: ",")
        return "\(days);\(timeText);\(leadMinutes)"
    }

    /// Reads `raw`. nil for an empty or malformed value (an unknown weekday or clock time makes the whole value invalid).
    public init?(raw: String) {
        let parts = raw.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 3 else { return nil }
        let days = parts[0].split(separator: ",").compactMap { Int($0) }.compactMap { RouteWeekday(rawValue: $0) }
        let clock = parts[1].split(separator: ":").compactMap { Int($0) }
        guard !days.isEmpty, clock.count == 2, (0...23).contains(clock[0]), (0...59).contains(clock[1]),
              let lead = Int(parts[2]), RouteSchedule.leadChoices.contains(lead) else { return nil }
        self.init(weekdays: Set(days), hour: clock[0], minute: clock[1], leadMinutes: lead)
    }

    /// "07:30".
    public var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// "Mo–Fr", "Sa–So", "Täglich" or "Mo, Mi, Fr".
    public var dayText: String {
        let set = weekdays
        if set.count == 7 { return "Täglich" }
        if set == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Mo–Fr" }
        if set == [.saturday, .sunday] { return "Sa–So" }
        return RouteWeekday.allCases.filter { set.contains($0) }.map(\.shortName).joined(separator: ", ")
    }

    /// "Mo–Fr · 07:30".
    public var summary: String {
        weekdays.isEmpty ? "Kein Zeitplan" : "\(dayText) · \(timeText)"
    }

    /// One reminder per weekday, `leadMinutes` before the departure. The lead can move a slot to the day before (Monday
    /// 00:05 with a 10-minute lead fires on Sunday 23:55). Ordered by weekday.
    public var reminderSlots: [ReminderSlot] {
        let week = 7 * 24 * 60
        let departureMinute = hour * 60 + minute
        return weekdays.sorted { $0.rawValue < $1.rawValue }.map { day in
            let raw = day.rawValue * 24 * 60 + departureMinute - leadMinutes
            let wrapped = ((raw % week) + week) % week
            return ReminderSlot(weekday: RouteWeekday(rawValue: wrapped / (24 * 60)) ?? .monday,
                                hour: (wrapped % (24 * 60)) / 60, minute: wrapped % 60)
        }
    }

    /// The next departure strictly after `now`, in the calendar's time zone (Vienna for the app). nil when no weekday is set.
    public func nextDeparture(after now: Date, calendar: Calendar) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let weekday = RouteWeekday(calendarWeekday: calendar.component(.weekday, from: day)),
                  weekdays.contains(weekday),
                  let departure = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  departure > now else { continue }
            return departure
        }
        return nil
    }

    /// The next moment a reminder fires (departure minus lead), strictly after `now`.
    public func nextReminder(after now: Date, calendar: Calendar) -> Date? {
        let lead = TimeInterval(leadMinutes * 60)
        guard let departure = nextDeparture(after: now.addingTimeInterval(lead), calendar: calendar) else { return nil }
        return departure.addingTimeInterval(-lead)
    }
}
