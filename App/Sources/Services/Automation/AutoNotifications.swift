import Foundation
import UserNotifications
import KlimaCore

// MARK: automation – the local notifications of the rules (docs/AUTOMATION.md §3). Planned notices ("rule.<id>.<yyyyMMdd>",
// at most 16) and notices sent at once while the app is in the background ("rule.<id>.<yyyyMMdd>.<HHmmss>"). Nothing is
// asked or scheduled in screenshot and perf runs; nothing goes to a server (no push).

enum AutoNotifications {
    /// Category of every rule notice; its one button opens the rule list.
    static let category = "rule"
    /// Category of a rule that offers a shortcut: „Kurzbefehl starten“ and „Regel ansehen“.
    static let shortcutCategory = "rule.shortcut"
    static let viewAction = "rule.view"
    static let shortcutAction = "rule.shortcut.run"

    /// userInfo keys.
    static let ruleKey = "ruleID"
    static let kindKey = "kind"
    static let opensAddTripKey = "opensAddTrip"
    static let fromKey = "from"
    static let toKey = "to"
    static let shortcutKey = "shortcut"

    /// The two categories, registered with all others in `NotificationCategories.registerAll` (one call replaces the set).
    static var categories: [UNNotificationCategory] {
        let view = UNNotificationAction(identifier: viewAction, title: "Regel ansehen", options: [.foreground])
        let run = UNNotificationAction(identifier: shortcutAction, title: "Kurzbefehl starten", options: [.foreground])
        return [
            UNNotificationCategory(identifier: category, actions: [view], intentIdentifiers: []),
            UNNotificationCategory(identifier: shortcutCategory, actions: [run, view], intentIdentifiers: []),
        ]
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    static func authorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once, when a rule that needs notices is switched on (as the route reminders do). Never in screenshot or perf runs.
    static func requestIfUndetermined() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined, !LaunchMode.isSandboxed else { return status }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        status = await center.notificationSettings().authorizationStatus
        return status
    }

    // MARK: Pending

    /// The rule notices iOS holds, as the reconcile step reads them.
    static func pending() async -> [AutoPendingSlot] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(AutoRuleScheduler.identifierPrefix) }
            .map { request in
                AutoPendingSlot(id: request.identifier, title: request.content.title, body: request.content.body,
                                fireAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
            }
    }

    /// Applies a reconcile: removes first, then adds. Returns how many notices iOS refused.
    @discardableResult
    static func apply(_ changes: AutoReconcile, kinds: [UUID: AutoTriggerKind]) async -> Int {
        let center = UNUserNotificationCenter.current()
        if !changes.toRemove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: changes.toRemove) }
        var failed = 0
        for slot in changes.toAdd {
            let content = content(title: slot.title, body: slot.body, ruleID: slot.ruleID, ruleName: slot.ruleName,
                                  kind: kinds[slot.ruleID], opensAddTrip: slot.opensAddTrip, from: slot.addTripFrom,
                                  to: slot.addTripTo, shortcut: slot.shortcutName)
            var parts = AlarmCalendar.vienna.dateComponents([.year, .month, .day, .hour, .minute], from: slot.fireAt)
            parts.timeZone = AlarmCalendar.vienna.timeZone   // the moment the screen shows is the moment it fires
            let request = UNNotificationRequest(identifier: slot.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do { try await center.add(request) } catch { failed += 1 }
        }
        return failed
    }

    /// Removes every planned rule notice (master switch off, „Alle Daten löschen“).
    static func removeAllPending() async {
        let ids = await pending().map(\.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: At once

    /// Sends a firing as a notice right away (the app is in the background, e.g. a follow answer of the background refresh).
    static func post(_ firing: AutoFiring, kind: AutoTriggerKind, identifier: String) async -> Bool {
        guard isAllowed(await authorization()) else { return false }
        let content = content(title: firing.title, body: firing.body, ruleID: firing.ruleID, ruleName: firing.ruleName, kind: kind,
                              opensAddTrip: firing.opensAddTrip, from: firing.addTripFrom, to: firing.addTripTo,
                              shortcut: firing.shortcutName)
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }

    // MARK: Delivered

    /// Rule notices iOS delivered (they are still in the Notification Center).
    static func delivered() async -> [UNNotification] {
        await UNUserNotificationCenter.current().deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(AutoRuleScheduler.identifierPrefix) }
    }

    // MARK: Content

    private static func content(title: String, body: String, ruleID: UUID, ruleName: String, kind: AutoTriggerKind?,
                                opensAddTrip: Bool, from: String?, to: String?, shortcut: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "Automatik · \(ruleName)"   // which rule speaks is never a secret to its owner
        content.body = body
        content.sound = .default
        content.threadIdentifier = AlarmIdentifier.rulePrefix + ruleID.uuidString
        content.categoryIdentifier = shortcut == nil ? category : shortcutCategory
        var info: [String: Any] = [ruleKey: ruleID.uuidString, opensAddTripKey: opensAddTrip]
        if let kind { info[kindKey] = kind.rawValue }
        if let from { info[fromKey] = from }
        if let to { info[toKey] = to }
        if let shortcut { info[shortcutKey] = shortcut }
        content.userInfo = info
        return content
    }
}
