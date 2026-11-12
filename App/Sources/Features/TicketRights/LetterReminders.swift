import Foundation
import UserNotifications
import KlimaCore

/// „Erinnerung setzen“ of the Widerspruchsbrief: two local notifications, 5 days and 1 day before the deadline from the
/// renewal letter, at 09:00 Vienna time. Identifiers „letter.<ticket id>.d5“ / „….d1“ (the Alarms screen lists them with the
/// other objection reminders). Permission is asked only when the holder taps the button; reminders whose moment has passed are
/// not scheduled.
@MainActor
enum LetterReminders {
    enum Outcome: Equatable {
        case scheduled([Date])
        case denied
        /// Nothing left to schedule: the deadline is too close or over.
        case tooLate
    }

    private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// The fire dates of the pending reminders of this ticket's letter (sorted).
    static func scheduledDates(ticketID: UUID) async -> [Date] {
        let prefix = LetterDeadline.identifierPrefix(ticketID: ticketID.uuidString)
        let pending = await center.pendingNotificationRequests()
        return pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .sorted()
    }

    /// Asks for permission if it was never asked, then (re)schedules both reminders for `deadline`.
    static func schedule(ticketID: UUID, ticketName: String, deadline: Date) async -> Outcome {
        let letterDeadline = LetterDeadline(day: deadline)
        let reminders = letterDeadline.reminders()
        guard !reminders.isEmpty else { return .tooLate }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .denied }

        await cancelNow(ticketID: ticketID)
        var scheduled: [Date] = []
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = LetterDeadline.reminderTitle(daysBefore: reminder.daysBefore)
            content.body = letterDeadline.reminderBody(ticketName: ticketName)
            content.sound = .default
            content.threadIdentifier = "renewal"
            let parts = Calendar.vienna.dateComponents(in: Calendar.vienna.timeZone, from: reminder.fireDate)
            let components = DateComponents(timeZone: Calendar.vienna.timeZone, year: parts.year, month: parts.month, day: parts.day,
                                            hour: parts.hour, minute: parts.minute)
            let identifier = LetterDeadline.identifier(ticketID: ticketID.uuidString, daysBefore: reminder.daysBefore)
            let request = UNNotificationRequest(identifier: identifier, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            do {
                try await center.add(request)
                scheduled.append(reminder.fireDate)
            } catch {
                continue
            }
        }
        return scheduled.isEmpty ? .denied : .scheduled(scheduled)
    }

    /// Removes the pending reminders of this ticket's letter.
    static func cancelNow(ticketID: UUID) async {
        let prefix = LetterDeadline.identifierPrefix(ticketID: ticketID.uuidString)
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
