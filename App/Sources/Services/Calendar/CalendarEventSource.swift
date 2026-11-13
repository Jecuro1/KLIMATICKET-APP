import Foundation
import KlimaCore

// MARK: calendarsuggestions – where calendar events come from (docs/CALENDAR_SUGGESTIONS.md §5). `EventKitSource` reads the iPhone's
// calendars (the only file that imports EventKit); `FakeCalendarSource` serves the demo, the CI scenes and the denied / write-only /
// empty states without a system dialog. Neither keeps event text: the events live as long as one refresh.

@MainActor
protocol CalendarEventSource: AnyObject {
    /// What iOS allows right now (re-read on every refresh: the user may change it in iOS Settings at any time).
    func currentAccess() -> CalendarAccess
    /// Shows the system question "Vollzugriff auf Kalender?" once; afterwards iOS answers without asking.
    func requestFullAccess() async -> CalendarAccess
    /// Calendars the picker offers: no birthdays, no subscriptions.
    func calendars() -> [CalendarInfo]
    /// Events of the given calendars that overlap the interval (all-day events and series occurrences included; the planner filters).
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEventInput]
}

/// The demo calendar: twelve fictional events (`CalendarDemoEvents`) and a fixed permission state.
@MainActor
final class FakeCalendarSource: CalendarEventSource {
    var access: CalendarAccess
    var offered: [CalendarInfo]
    var stored: [CalendarEventInput]
    /// What `requestFullAccess()` turns the state into (the demo's "Erlauben").
    var answer: CalendarAccess

    init(access: CalendarAccess = .fullAccess, calendars: [CalendarInfo] = CalendarDemoEvents.calendars,
         events: [CalendarEventInput] = CalendarDemoEvents.events(), answer: CalendarAccess = .fullAccess) {
        self.access = access
        offered = calendars
        stored = events
        self.answer = answer
    }

    func currentAccess() -> CalendarAccess { access }

    func requestFullAccess() async -> CalendarAccess {
        if access == .notDetermined { access = answer }
        return access
    }

    func calendars() -> [CalendarInfo] { access == .fullAccess ? offered : [] }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEventInput] {
        guard access == .fullAccess else { return [] }
        return stored.filter { calendarIDs.contains($0.calendarID) && $0.end >= start && $0.start <= end }
    }
}
