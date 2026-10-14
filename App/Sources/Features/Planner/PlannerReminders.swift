import Foundation
import UserNotifications
import KlimaCore

/// Departure reminders of a connection (docs/PLANNER.md §Erinnerung): a local notification `lead` minutes before the planned
/// departure. Nothing is requested from the network and nothing runs in the background; the date comes from the timetable
/// the user already looked at (`PlannerReminder`, KlimaCore).
enum PlannerReminders {
    enum Outcome: Equatable {
        case scheduled(fireAt: Date)
        /// The moment of the reminder has passed (or the train leaves within the lead time).
        case tooLate
        case denied
    }

    static func identifier(for journeyID: String) -> String { "planner.reminder.\(journeyID)" }

    /// When the pending reminder of this connection fires, nil when none is set.
    static func pendingFireDate(journeyID: String) async -> Date? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let request = requests.first(where: { $0.identifier == identifier(for: journeyID) }),
              let trigger = request.trigger as? UNTimeIntervalNotificationTrigger else { return nil }
        return trigger.nextTriggerDate()
    }

    /// Asks for the permission once (the system remembers the answer) and schedules the notification.
    static func schedule(_ journey: Journey, title: String, leadMinutes: Int, now: Date = Date()) async -> Outcome {
        guard let departure = journey.departure?.effective,
              let fire = PlannerReminder.fireDate(departure: departure, leadMinutes: leadMinutes, now: now) else { return .tooLate }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return .denied }
        let content = UNMutableNotificationContent()
        content.title = "Abfahrt in \(leadMinutes) Min"
        content.body = title
        content.sound = .default
        content.threadIdentifier = "planner"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSince(now)), repeats: false)
        let id = identifier(for: journey.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            return .scheduled(fireAt: fire)
        } catch {
            return .denied
        }
    }

    static func cancel(journeyID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: journeyID)])
    }
}
