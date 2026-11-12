import Foundation

/// The deadline printed in the holder's renewal letter („Einladungsschreiben zur Vertragserneuerung“, AGB 20.1) and the two
/// local reminders before it. The AGB tie the deadline to that letter, so the app cannot know it: the holder enters it.
public struct LetterDeadline: Equatable, Sendable {
    /// The last day of the deadline (start of that day, Vienna).
    public let day: Date
    public let calendar: Calendar

    /// Reminders this many days before the deadline day.
    public static let reminderOffsets = [5, 1]
    /// … at 09:00 Vienna time (like the other renewal reminders of the app).
    public static let reminderHour = 9
    /// Notification identifiers start with this; the Alarms screen lists them with the objection reminders.
    public static let prefix = AlarmIdentifier.letterPrefix

    public init(day: Date, calendar: Calendar = .vienna) {
        self.calendar = calendar
        self.day = calendar.startOfDay(for: day)
    }

    public enum Status: Equatable, Sendable {
        /// Still `days` days to go (≥ 1).
        case open(days: Int)
        case today
        /// Over since `days` days (≥ 1).
        case passed(days: Int)
    }

    public func status(now: Date = Date()) -> Status {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
        if days > 0 { return .open(days: days) }
        if days == 0 { return .today }
        return .passed(days: -days)
    }

    public func isPassed(now: Date = Date()) -> Bool {
        if case .passed = status(now: now) { return true }
        return false
    }

    public struct Reminder: Equatable, Sendable, Identifiable {
        public var daysBefore: Int
        public var fireDate: Date
        public var id: Int { daysBefore }
    }

    /// The reminders that still lie ahead of `now`: one 5 days and one 1 day before the deadline, each at 09:00. A reminder whose
    /// moment has passed is skipped (a deadline in 3 days gets only the one-day reminder; a deadline today or past, none).
    public func reminders(now: Date = Date()) -> [Reminder] {
        Self.reminderOffsets.compactMap { offset in
            guard let base = calendar.date(byAdding: .day, value: -offset, to: day),
                  let fire = calendar.date(bySettingHour: Self.reminderHour, minute: 0, second: 0, of: base),
                  fire > now else { return nil }
            return Reminder(daysBefore: offset, fireDate: fire)
        }
    }

    // MARK: Notification contract

    /// „letter.<ticket id>.“ – shared by the reminders of one ticket.
    public static func identifierPrefix(ticketID: String) -> String { "\(prefix)\(ticketID)." }

    /// „letter.<ticket id>.d5“, „letter.<ticket id>.d1“.
    public static func identifier(ticketID: String, daysBefore: Int) -> String { "\(identifierPrefix(ticketID: ticketID))d\(daysBefore)" }

    public static func reminderTitle(daysBefore: Int) -> String {
        daysBefore == 1 ? "Morgen endet deine Widerspruchsfrist" : "In \(daysBefore) Tagen endet deine Widerspruchsfrist"
    }

    public func reminderBody(ticketName: String) -> String {
        "Laut deinem Verlängerungsbrief endet die Frist für \(ticketName) am \(LetterFormat.date(day, calendar: calendar)). Schick den Widerspruch eingeschrieben ab und heb den Beleg auf."
    }
}

// MARK: - Extraordinary cancellation window

/// AGB 17.2: the ticket and the signed form must be handed in within four weeks after the reason arose.
public struct FilingWindow: Equatable, Sendable {
    /// The day the reason arose (start of day, Vienna).
    public let since: Date
    public let calendar: Calendar

    public init(since: Date, calendar: Calendar = .vienna) {
        self.calendar = calendar
        self.since = calendar.startOfDay(for: since)
    }

    /// Last day to hand in ticket and form: four weeks (28 days) after `since`.
    public var lastDay: Date {
        calendar.date(byAdding: .day, value: AdvisorRules.extraordinaryFilingWeeks * 7, to: since) ?? since
    }

    public enum Status: Equatable, Sendable {
        /// The reason lies in the future – it cannot count yet.
        case notYet
        /// Still `days` days left (0 = last day is today).
        case open(days: Int)
        case closed(days: Int)
    }

    public func status(now: Date = Date()) -> Status {
        let today = calendar.startOfDay(for: now)
        if since > today { return .notYet }
        let left = calendar.dateComponents([.day], from: today, to: lastDay).day ?? 0
        return left >= 0 ? .open(days: left) : .closed(days: -left)
    }
}
