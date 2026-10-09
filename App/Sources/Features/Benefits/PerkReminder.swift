import SwiftUI
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
        /// No known compensation scheme for this ticket (custom tickets).
        case notApplicable
    }

    static func identifier(for ticketID: UUID) -> String { identifierPrefix + ticketID.uuidString }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func isScheduled(ticketID: UUID) async -> Bool {
        let id = identifier(for: ticketID)
        return await UNUserNotificationCenter.current().pendingNotificationRequests().contains { $0.identifier == id }
    }

    /// Asks for permission when still undetermined (the caller explains why first), then (re)schedules the reminder
    /// for the ticket's current end date. A pending reminder of the same ticket is replaced.
    static func schedule(_ ticket: TicketEntity, requestingPermission: Bool) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: ticket.id)
        let scheme = PerkRightsScheme.forFamily(ticket.family)
        guard scheme != .unknown else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return .notApplicable
        }
        let fireDate = PerkPassengerRights.reminderDate(expiry: ticket.endDate)
        guard fireDate > Date() else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            return .tooLate
        }

        var status = await authorizationStatus()
        if status == .notDetermined, requestingPermission {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await authorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = "Fahrgastrechte: Entschädigung prüfen"
        content.body = body(ticketName: ticket.name, scheme: scheme)
        content.sound = .default
        content.threadIdentifier = "perk.passengerRights"

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
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

    /// Keeps pending reminders in line with the tickets: drops reminders of deleted tickets and moves a reminder
    /// whose ticket got a new end date or name (edits, renewals, sync from another device). No-op when nothing
    /// of this module is pending, so it is cheap to call whenever the tickets change.
    static func reconcile(tickets: [TicketEntity]) async {
        guard !LaunchMode.isScreenshot else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(identifierPrefix) }
        guard !pending.isEmpty else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        for request in pending {
            guard let ticket = tickets.first(where: { identifier(for: $0.id) == request.identifier }) else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                continue
            }
            let expected = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                              from: PerkPassengerRights.reminderDate(expiry: ticket.endDate))
            let current = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            let sameDate = current?.year == expected.year && current?.month == expected.month && current?.day == expected.day
                && current?.hour == expected.hour && current?.minute == expected.minute
            let sameText = request.content.body == body(ticketName: ticket.name, scheme: PerkRightsScheme.forFamily(ticket.family))
            if !sameDate || !sameText {
                _ = await schedule(ticket, requestingPermission: false)
            }
        }
    }

    static func body(ticketName: String, scheme: PerkRightsScheme) -> String {
        let threshold = Format.number(scheme.threshold * 100)
        return "\(ticketName) ist abgelaufen. Lagen die ÖBB in einem Monat unter \(threshold)\u{00A0}% Pünktlichkeit, steht dir jetzt eine Entschädigung zu – prüf deine Anmeldung auf oebb.at/fahrgastrechte."
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

/// Runs `PerkReminderScheduler.reconcile` whenever the live tickets change (deleted, edited, renewed, synced).
/// Attached to the always-visible `PerkSummaryCard`, so hosts need no extra hook.
struct PerkReminderReconciler: ViewModifier {
    let tickets: [TicketEntity]

    func body(content: Content) -> some View {
        content.task(id: key) {
            await PerkReminderScheduler.reconcile(tickets: tickets)
        }
    }

    private var key: String {
        tickets.map { "\($0.id.uuidString)|\($0.endDate.timeIntervalSince1970)|\($0.name)|\($0.familyRaw)" }.sorted().joined(separator: ";")
    }
}
