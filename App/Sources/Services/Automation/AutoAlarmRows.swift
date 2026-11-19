import Foundation
import KlimaCore

// MARK: automation – the rules in Einstellungen › Mitteilungen › Alle Alarme (docs/ROUTES_ALARMS.md §2): one row per rule under
// the kind „Automatik“, built from the rules themselves (not from iOS's pending list, which only holds the planned ones). The
// switch turns the rule on or off; deleting the row deletes the rule. While the master switch is off no row is shown.

@MainActor
enum AutoAlarmRows {
    static let prefix = AlarmIdentifier.rulePrefix

    static func rows(now: Date) -> [AlarmItem] {
        let store = AutoStore.shared
        guard store.book.isEnabled else { return [] }
        let runner = AutoRunner.shared
        return store.book.rules.map { rule in
            let normalized = rule.normalized
            return AlarmItem(id: prefix + rule.id.uuidString, kind: .automation, title: normalized.name,
                             detail: AutoText.sentence(normalized),
                             nextDate: rule.isEnabled ? runner.shownPlan.next(for: rule.id) : nil,   // nothing is due without the permission
                             scheduleText: scheduleText(rule, runner: runner),
                             isOn: rule.isEnabled)
        }
    }

    /// When a rule speaks: „Nach dem Speichern einer Fahrt“ for an event rule; for a planned one its date (nextDate), or why
    /// there is none while iOS may not show notices („kein Termin“ would hide the reason).
    private static func scheduleText(_ rule: AutoRule, runner: AutoRunner) -> String? {
        guard rule.trigger.isScheduled else { return AutoText.kindTiming(rule.trigger.kind).autoSentenceStart }
        guard runner.isBlocked(rule) else { return nil }
        return AutoText.notificationsBlockedLine(denied: runner.authorization == .denied).autoSentenceStart
    }

    static func setOn(_ item: AlarmItem, _ on: Bool) {
        guard let id = ruleID(item) else { return }
        AutoStore.shared.setEnabled(id, on, ticket: AutoRunner.shared.currentTicket)
        AutoRunner.shared.rulesChanged(asksPermission: on)
    }

    static func remove(_ item: AlarmItem) {
        guard let id = ruleID(item) else { return }
        AutoStore.shared.delete(id)
        AutoRunner.shared.rulesChanged(asksPermission: false)
    }

    private static func ruleID(_ item: AlarmItem) -> UUID? {
        UUID(uuidString: String(item.id.dropFirst(prefix.count)))
    }
}

extension String {
    /// „Nach dem Speichern …“ – the first letter upper-cased (sentence parts used as a line of their own).
    var autoSentenceStart: String { prefix(1).uppercased() + dropFirst() }
}
