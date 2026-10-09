import Foundation
import UserNotifications
import KlimaCore

/// Local reminder before the renewal letter of an automatically renewing (SEPA) ticket arrives – so the objection
/// deadline printed in the letter is not missed. Identifier: "advisor.renewal.<ticket uuid>" (separate from the
/// expiry reminders "renewal.<uuid>.<offset>" of `NotificationService`).
@MainActor
enum AdvReminder {
    enum Outcome: Equatable {
        case scheduled(Date)
        case denied
        case past
    }

    static let prefix = "advisor.renewal."

    static func identifier(for ticketID: UUID) -> String { prefix + ticketID.uuidString }

    /// Fire date of the pending reminder for the ticket, nil when none is scheduled.
    static func scheduledDate(ticketID: UUID) async -> Date? {
        let id = identifier(for: ticketID)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == id }) else { return nil }
        return (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks for permission when needed, then (re)schedules the reminder at `renewal.reminderDate`.
    static func schedule(ticketID: UUID, ticketName: String, renewal: RenewalAdvice) async -> Outcome {
        let date = renewal.reminderDate
        guard date > Date() else { return .past }
        let center = UNUserNotificationCenter.current()
        var status = await authorizationStatus()
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = title(renewal: renewal)
        content.body = body(ticketName: ticketName, renewal: renewal)
        content.sound = .default
        content.threadIdentifier = "renewal"

        let components = Calendar.vienna.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: identifier(for: ticketID), content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: ticketID)])
        do {
            try await center.add(request)
        } catch {
            return .denied
        }
        return .scheduled(date)
    }

    static func cancel(ticketID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: ticketID)])
    }

    // MARK: Copy

    static func title(renewal: RenewalAdvice) -> String {
        renewal.cancellationDeadline != nil ? "Bald Kündigungsfrist für dein Ticket" : "Dein Verlängerungsbrief kommt bald"
    }

    static func body(ticketName: String, renewal: RenewalAdvice) -> String {
        let start = Format.date(renewal.renewalStart, .long)
        if let deadline = renewal.cancellationDeadline {
            return "\(ticketName) verlängert sich am \(start) automatisch. Willst du das nicht, kündige bis \(Format.date(deadline, .long)). Im Ratgeber siehst du, ob sich das nächste Jahr lohnt."
        }
        return "\(ticketName) verlängert sich am \(start) automatisch. Willst du das nicht, widersprich bis zur Frist im Brief. Im Ratgeber siehst du, ob sich das nächste Jahr lohnt."
    }
}
