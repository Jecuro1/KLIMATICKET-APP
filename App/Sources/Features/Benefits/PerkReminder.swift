import Foundation
import UserNotifications
import KlimaCore

// Local state of the Fahrgastrechte assistant: the one-off reminder after the ticket expires
// (UNUserNotificationCenter, identifier prefix "perk.passengerRights.") and the per-ticket checklist /
// marked-months state (device-local convenience, kept in UserDefaults).

/// Schedules the "Hol dir deine Entschädigung" reminder a few days after the ticket expired.
@MainActor
enum PerkReminderScheduler {
    static let identifierPrefix = "perk.passengerRights."

    enum Outcome: Equatable {
        case scheduled(Date)
        /// Notifications are switched off for the app (iOS Settings).
        case denied
        /// The reminder date already lies in the past.
        case tooLate
    }

    static func identifier(for ticketID: UUID) -> String { identifierPrefix + ticketID.uuidString }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isScheduled(ticketID: UUID) async -> Bool {
        let id = identifier(for: ticketID)
        return await UNUserNotificationCenter.current().pendingNotificationRequests().contains { $0.identifier == id }
    }

    /// Asks for permission when still undetermined (the caller explains why first), then schedules.
    static func schedule(ticketID: UUID, ticketName: String, expiry: Date, requestingPermission: Bool) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let fireDate = PerkPassengerRights.reminderDate(expiry: expiry)
        guard fireDate > Date() else { return .tooLate }

        var status = await authorizationStatus()
        if status == .notDetermined, requestingPermission {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = "Fahrgastrechte: Entschädigung holen"
        content.body = "\(ticketName) ist abgelaufen. Warst du bei den ÖBB angemeldet? Für Monate unter 93 % Pünktlichkeit gibt es jetzt Geld zurück."
        content.sound = .default
        content.threadIdentifier = "perk.passengerRights"

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let id = identifier(for: ticketID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        do {
            try await center.add(request)
            return .scheduled(fireDate)
        } catch {
            return .denied
        }
    }

    static func cancel(ticketID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: ticketID)])
    }
}

/// Per-ticket state of the assistant (checked steps, months marked as "unter 93 %").
/// Device-local on purpose: it is a personal checklist, not data that needs to sync.
@MainActor
enum PerkRightsStore {
    /// Screenshot mode uses its own suite so CI runs never touch real preferences.
    static var defaults: UserDefaults {
        LaunchMode.isScreenshot ? (UserDefaults(suiteName: "screenshots") ?? .standard) : .standard
    }

    private static func key(_ kind: String, _ ticketID: UUID) -> String {
        "perk.passengerRights.\(kind).\(ticketID.uuidString)"
    }

    static func completedSteps(ticketID: UUID) -> Set<Int> {
        Set(defaults.array(forKey: key("steps", ticketID)) as? [Int] ?? [])
    }

    static func setCompletedSteps(_ steps: Set<Int>, ticketID: UUID) {
        defaults.set(steps.sorted(), forKey: key("steps", ticketID))
    }

    static func badMonths(ticketID: UUID) -> Set<Int> {
        Set(defaults.array(forKey: key("months", ticketID)) as? [Int] ?? [])
    }

    static func setBadMonths(_ months: Set<Int>, ticketID: UUID) {
        defaults.set(months.sorted(), forKey: key("months", ticketID))
    }
}
