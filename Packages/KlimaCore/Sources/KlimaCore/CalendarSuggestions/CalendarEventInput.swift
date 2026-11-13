import Foundation

// MARK: calendarsuggestions – one calendar event as the suggestion logic sees it (docs/CALENDAR_SUGGESTIONS.md §3). The app builds it
// from EventKit (App/Sources/Services/Calendar) or from the demo source; nothing of it is stored, logged or synced. Only a hash of
// `id` + `start` outlives the moment (`CalendarEventKey`).

public struct CalendarEventInput: Hashable, Sendable, Identifiable {
    /// The event's identifier in the calendar database (EventKit `eventIdentifier`). The occurrences of a recurring event share it.
    public var id: String
    public var title: String
    /// The location field as the calendar holds it ("Salzburg Hbf", "Mirabellplatz 4, 5020 Salzburg", "Zoom"); nil when empty.
    public var location: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    /// Recurring events: the key all occurrences of the series share (EventKit `calendarItemIdentifier`); nil for a single event.
    public var seriesID: String?

    public init(id: String, title: String, location: String?, start: Date, end: Date, isAllDay: Bool = false, calendarID: String,
                seriesID: String? = nil) {
        self.id = id
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.seriesID = seriesID
    }

    /// The key a dismissal, a snooze and a follow-up are remembered by (SHA-256 of id and start, see `CalendarEventKey`).
    public var key: String { CalendarEventKey.make(eventID: id, start: start) }
}

/// What iOS allows the app to do with the calendars (EventKit `EKAuthorizationStatus`, iOS 17+ names).
public enum CalendarAccess: String, Sendable, CaseIterable {
    /// Not asked yet.
    case notDetermined
    /// Refused by the user (iOS Settings › Apps › KlimaBilanz › Kalender).
    case denied
    /// Blocked by Screen Time or a device profile; the user cannot change it.
    case restricted
    /// "Nur hinzufügen": the app may add events but not read them – not enough for suggestions.
    case writeOnly
    /// "Vollzugriff": events may be read.
    case fullAccess
}

/// One calendar the picker offers.
public struct CalendarInfo: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// The account it belongs to ("iCloud", "Exchange", "Auf meinem iPhone").
    public var sourceTitle: String
    /// #RRGGBB of the calendar's colour.
    public var colorHex: String?
    /// The calendar new events go to – the only one selected before the user picks.
    public var isDefault: Bool

    public init(id: String, title: String, sourceTitle: String, colorHex: String? = nil, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.isDefault = isDefault
    }
}

/// Which face the settings page and the Übersicht show, from the switch, the permission and the calendars (docs/CALENDAR_SUGGESTIONS.md §2).
public enum CalendarSetupState: Equatable, Sendable {
    /// The switch is off (the default).
    case off
    /// On, but iOS has not asked yet – the explanation sheet leads to the system question.
    case needsPermission
    case denied
    case restricted
    case writeOnly
    /// Read access, but the iPhone has no calendar the picker offers (no account, only birthdays or subscriptions).
    case noCalendars
    /// Read access and calendars, none ticked.
    case noneSelected
    /// Suggestions run.
    case active

    public static func make(isEnabled: Bool, access: CalendarAccess, offeredCalendars: Int, selectedCalendars: Int) -> CalendarSetupState {
        guard isEnabled else { return .off }
        switch access {
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .writeOnly
        case .fullAccess:
            if offeredCalendars == 0 { return .noCalendars }
            return selectedCalendars == 0 ? .noneSelected : .active
        }
    }

    /// Cards may show on the Übersicht.
    public var showsSuggestions: Bool { self == .active }
}
