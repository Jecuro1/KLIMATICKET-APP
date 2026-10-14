import Foundation
import UserNotifications
import KlimaCore

// „Meine Routen“ (docs/ROUTES_ALARMS.md §1.4): the weekday/time reminders of a saved route. One repeating local notification
// per weekday, `leadMinutes` before the departure, in Vienna time. Nothing is requested from the network and nothing runs in
// the background: iOS fires the notifications itself. The identifiers are `AlarmIdentifier.routeReminder`, so the Alarms
// screen can pause and resume them.

@MainActor
enum SavedRouteReminders {
    /// The reminders of the route are replaced by the ones of its current schedule (none when it has no schedule).
    /// The permission is asked only for a route that has a schedule, and only when `requestingPermission` is set.
    /// Returns false when a schedule exists but iOS does not allow notifications for the app.
    @discardableResult
    static func apply(to route: FavoriteRouteEntity, requestingPermission: Bool = true) async -> Bool {
        let center = UNUserNotificationCenter.current()
        await removeReminders(routeID: route.id.uuidString)
        guard let schedule = route.schedule, !schedule.weekdays.isEmpty else { return true }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined, requestingPermission {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return false }

        let copy = RouteCopy(route)
        for slot in schedule.reminderSlots {
            let content = UNMutableNotificationContent()
            content.title = schedule.leadMinutes == 0 ? "Abfahrt jetzt" : "Abfahrt in \(schedule.leadMinutes) Min"
            content.body = "\(copy.title) · \(copy.line)"
            content.sound = .default
            content.threadIdentifier = AlarmIdentifier.routePrefix + copy.id
            var components = DateComponents()
            components.weekday = slot.weekday.calendarWeekday
            components.hour = slot.hour
            components.minute = slot.minute
            let request = UNNotificationRequest(
                identifier: AlarmIdentifier.routeReminder(routeID: copy.id, weekday: slot.weekday), content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            try? await center.add(request)
        }
        return true
    }

    /// Removes every reminder of one route, pending or paused in the Alarms screen (its schedule was switched off, the
    /// route was changed or deleted; the new schedule brings its own reminders).
    static func removeReminders(routeID: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = AlarmIdentifier.routeReminderPrefix(routeID: routeID)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        PausedAlarmStore.removeGroup(AlarmIdentifier.routePrefix + routeID)
    }

    /// The values the notification text needs, read once from the entity.
    private struct RouteCopy {
        let id: String
        let title: String
        let line: String

        init(_ route: FavoriteRouteEntity) {
            id = route.id.uuidString
            title = route.displayTitle
            line = SavedRoutes.routeLine(from: route.fromName, via: route.via.map(\.name), to: route.toName)
        }
    }
}
