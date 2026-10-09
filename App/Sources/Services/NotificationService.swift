import Foundation
import UserNotifications

/// Local notifications: ticket renewal reminders and an optional weekly summary.
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Schedules reminders `offsets` days before `end` at 09:00 (Vienna) and on the expiry day.
    func scheduleRenewalReminders(ticketID: UUID, ticketName: String, end: Date, offsets: [Int]) async {
        let prefix = "renewal.\(ticketID.uuidString)."
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        for offset in Set(offsets + [0]).sorted(by: >) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: end), day > Date() else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 9
            comps.minute = 0
            let content = UNMutableNotificationContent()
            switch offset {
            case 0:
                content.title = "Dein Ticket läuft heute ab"
                content.body = "\(ticketName) ist nur noch heute gültig. Jetzt verlängern und weiter klimafreundlich fahren."
            case 1:
                content.title = "Morgen läuft dein Ticket ab"
                content.body = "\(ticketName) ist nur noch bis morgen gültig."
            default:
                content.title = "Noch \(offset) Tage gültig"
                content.body = "\(ticketName) läuft bald ab – denk an die Verlängerung."
            }
            content.sound = .default
            content.threadIdentifier = "renewal"
            let request = UNNotificationRequest(identifier: prefix + "\(offset)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
        }
    }

    func cancelRenewalReminders(ticketID: UUID) async {
        let prefix = "renewal.\(ticketID.uuidString)."
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }

    /// Sunday 18:00 nudge to review the week ("Deine Woche: 6 Fahrten, € 84 Wert").
    func setWeeklySummary(enabled: Bool) async {
        center.removePendingNotificationRequests(withIdentifiers: ["weekly.summary"])
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Deine Woche mit den Öffis"
        content.body = "Schau nach, wie viel du diese Woche gespart hast – und ob alle Fahrten erfasst sind."
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = 1
        comps.hour = 18
        let request = UNNotificationRequest(identifier: "weekly.summary", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        try? await center.add(request)
    }

    /// Immediate celebratory notification (used when the app is in the background during sync).
    func notifyBreakEven(ticketName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Geschafft – dein Ticket hat sich rentiert! 🎉"
        content.body = "\(ticketName) hat sich bezahlt gemacht. Ab jetzt ist jede Fahrt reiner Gewinn."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "breakeven.\(ticketName)", content: content, trigger: nil))
    }
}
