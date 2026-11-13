import Foundation
import CoreGraphics
import EventKit
import KlimaCore

// MARK: calendarsuggestions – the iPhone's calendars through EventKit (docs/CALENDAR_SUGGESTIONS.md §5). The only file of the app that
// imports EventKit. Reads only while the app is open (the Übersicht asks on appear, on return to the foreground and when the calendar
// database changes); asks for full read access only after the explanation sheet; needs no entitlement, only the usage text
// NSCalendarsFullAccessUsageDescription in Info.plist. Titles, locations and times are handed to the planner and dropped.

@MainActor
final class EventKitSource: CalendarEventSource {
    /// Created on first use: with the switch off (the default) the app never opens the calendar database.
    private lazy var store = EKEventStore()

    func currentAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .denied
        }
    }

    func requestFullAccess() async -> CalendarAccess {
        guard currentAccess() == .notDetermined else { return currentAccess() }
        _ = try? await store.requestFullAccessToEvents()
        // A store created before the grant does not see the calendars until it is reset.
        store.reset()
        return currentAccess()
    }

    func calendars() -> [CalendarInfo] {
        guard currentAccess() == .fullAccess else { return [] }
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter { $0.type != .birthday && $0.type != .subscription && !$0.isSubscribed }
            .map { calendar in
                let source: EKSource? = calendar.source
                return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title, sourceTitle: source?.title ?? "",
                                    colorHex: Self.hex(calendar.cgColor), isDefault: calendar.calendarIdentifier == defaultID)
            }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEventInput] {
        guard currentAccess() == .fullAccess, !calendarIDs.isEmpty else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            let begin: Date? = event.startDate
            let finish: Date? = event.endDate
            let calendar: EKCalendar? = event.calendar
            guard let begin, let calendar else { return nil }
            let identifier: String = event.eventIdentifier ?? event.calendarItemIdentifier
            return CalendarEventInput(id: identifier, title: event.title ?? "", location: event.location, start: begin,
                                      end: finish ?? begin, isAllDay: event.isAllDay, calendarID: calendar.calendarIdentifier,
                                      seriesID: event.hasRecurrenceRules ? event.calendarItemIdentifier : nil)
        }
    }

    /// Notifies when the calendar database changes (an event added or moved in Kalender while KlimaBilanz is open).
    static let changeNotification = Notification.Name.EKEventStoreChanged

    private static func hex(_ color: CGColor?) -> String? {
        guard let color, let c = color.components, !c.isEmpty else { return nil }
        let rgb: [CGFloat] = c.count >= 3 ? Array(c.prefix(3)) : [c[0], c[0], c[0]]
        let bytes = rgb.map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}
