import Foundation

// Automatik (docs/AUTOMATION.md): the notices planned in advance. Only the two time triggers are planned: „Tag ohne Fahrt“ for
// the next 14 days and „vor Ablauf“ once (its one moment, however far away). At most 16 of the 64 pending notifications iOS
// keeps for an app belong to the rules; when there are more moments than places the plan says so (`AutoPlan.overflow`)
// instead of dropping them silently. Identifier of a planned notice: "rule.<rule id>.<yyyyMMdd>" (Vienna day).

/// One planned notice.
public struct AutoSlot: Hashable, Sendable, Identifiable {
    /// "rule.<rule id>.<yyyyMMdd>".
    public var id: String
    public var ruleID: UUID
    public var ruleName: String
    public var fireAt: Date
    public var title: String
    public var body: String
    public var opensAddTrip: Bool
    public var addTripFrom: String?
    public var addTripTo: String?
    public var shortcutName: String?

    public init(id: String, ruleID: UUID, ruleName: String, fireAt: Date, title: String, body: String, opensAddTrip: Bool = false,
                addTripFrom: String? = nil, addTripTo: String? = nil, shortcutName: String? = nil) {
        self.id = id
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.fireAt = fireAt
        self.title = title
        self.body = body
        self.opensAddTrip = opensAddTrip
        self.addTripFrom = addTripFrom
        self.addTripTo = addTripTo
        self.shortcutName = shortcutName
    }
}

/// What the scheduler decided: the planned notices (at most `slotCeiling`, by time) and what did not fit.
public struct AutoPlan: Hashable, Sendable {
    public var slots: [AutoSlot]
    /// Moments that found no place under the ceiling (planned later, when places free up).
    public var overflow: [AutoSlot]
    /// Rules with moments but no planned notice at all.
    public var rulesWithoutSlot: [UUID]
    public var ceiling: Int
    /// The rules the plan was made for (enabled, planned triggers).
    public var plannedRules: Set<UUID>

    public init(slots: [AutoSlot] = [], overflow: [AutoSlot] = [], rulesWithoutSlot: [UUID] = [], ceiling: Int = AutoRuleScheduler.slotCeiling,
                plannedRules: Set<UUID> = []) {
        self.slots = slots
        self.overflow = overflow
        self.rulesWithoutSlot = rulesWithoutSlot
        self.ceiling = ceiling
        self.plannedRules = plannedRules
    }

    public var isOverCeiling: Bool { !overflow.isEmpty }

    /// The first planned notice of a rule.
    public func next(for ruleID: UUID) -> Date? {
        slots.first { $0.ruleID == ruleID }?.fireAt
    }

    public func slotCount(for ruleID: UUID) -> Int {
        slots.reduce(0) { $0 + ($1.ruleID == ruleID ? 1 : 0) }
    }
}

/// A notice iOS holds for the app, as the reconcile step reads it.
public struct AutoPendingSlot: Hashable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fireAt: Date?

    public init(id: String, title: String, body: String, fireAt: Date?) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

/// What to change in iOS's pending notices so they equal the plan.
public struct AutoReconcile: Hashable, Sendable {
    public var toRemove: [String]
    public var toAdd: [AutoSlot]
    /// Removed because their day got a trip (the log says „abgesagt“).
    public var cancelledForTrip: [AutoPendingSlot]

    public var isEmpty: Bool { toRemove.isEmpty && toAdd.isEmpty }
}

public enum AutoRuleScheduler {
    public static let identifierPrefix = "rule."
    /// Days planned ahead for „Tag ohne Fahrt“, today included.
    public static let horizonDays = 14
    /// Places of the 64 pending notifications the rules may take.
    public static let slotCeiling = 16
    /// „vor Ablauf“ rings at 09:00, like the ticket's own reminders.
    public static let deadlineMinute = 9 * 60

    // MARK: Identifiers

    /// "rule.<rule id>.<yyyyMMdd>".
    public static func identifier(ruleID: UUID, day: Date, calendar: Calendar) -> String {
        "\(identifierPrefix)\(ruleID.uuidString).\(AutoClock.dayKey(day, calendar: calendar))"
    }

    /// The rule and the day of a planned notice; nil for anything else (a notice sent at once has a fourth part).
    public static func parse(_ identifier: String) -> (ruleID: UUID, dayKey: String)? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let parts = identifier.dropFirst(identifierPrefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              parts[1].count == 8, parts[1].allSatisfy(\.isNumber) else { return nil }
        return (id, String(parts[1]))
    }

    /// The rule a "rule." identifier belongs to (planned or sent at once).
    public static func ruleID(of identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(identifierPrefix.count)
        return UUID(uuidString: String(rest.prefix { $0 != "." }))
    }

    /// Identifier of a notice sent at once: "rule.<rule id>.<yyyyMMdd>.<HHmmss>" (never confused with a planned one).
    public static func immediateIdentifier(ruleID: UUID, at date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.hour, .minute, .second], from: date)
        return identifier(ruleID: ruleID, day: date, calendar: calendar) + String(format: ".%02d%02d%02d", p.hour ?? 0, p.minute ?? 0, p.second ?? 0)
    }

    // MARK: Planning

    /// Every moment of one rule that may be planned, earliest first (conditions, trips and „Wochenende ruhig“ applied).
    public static func candidates(for rule: AutoRule, state: AutoState, now: Date, calendar: Calendar) -> [AutoSlot] {
        let rule = rule.normalized
        switch rule.trigger {
        case .ticketDeadline:
            guard let ticket = state.ticket,
                  let planned = AutoRuleEngine.deadlineMoment(rule: rule, ticket: ticket, state: state, calendar: calendar),
                  planned.moment > now else { return [] }
            let reason = AutoReason.deadline(days: deadlineDays(rule), ticketName: ticket.name, end: ticket.end, movedForWeekend: planned.moved)
            return [slot(rule, at: planned.moment, reason: reason, calendar: calendar)]
        case let .dayWithoutTrip(weekdays, minute):
            guard !weekdays.isEmpty else { return [] }
            let today = calendar.startOfDay(for: now)
            var out: [AutoSlot] = []
            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      weekdays.contains(AutoClock.weekday(day, calendar: calendar)),
                      let moment = AutoClock.moment(on: day, minuteOfDay: minute, calendar: calendar),
                      moment > now,
                      AutoRuleEngine.dayBlock(rule, day: moment, state: state, calendar: calendar) == nil else { continue }
                out.append(slot(rule, at: moment, reason: .dayWithoutTrip(day: moment, isToday: offset == 0), calendar: calendar))
            }
            return out
        case .milestone, .followDelay, .tripLogged:
            return []
        }
    }

    /// The notices to keep pending for `rules` (pass the enabled ones). Every rule gets its earliest moment first, then its
    /// second, and so on, until the ceiling is reached – so a rule with a far deadline is not pushed out by a daily one.
    public static func plan(rules: [AutoRule], state: AutoState, now: Date, calendar: Calendar,
                            ceiling: Int = slotCeiling) -> AutoPlan {
        let scheduled = rules.filter { $0.isEnabled && $0.trigger.isScheduled }
        let perRule = scheduled.map { candidates(for: $0, state: state, now: now, calendar: calendar) }.filter { !$0.isEmpty }
        var chosen: [AutoSlot] = []
        var rank = 0
        let deepest = perRule.map(\.count).max() ?? 0
        while chosen.count < ceiling, rank < deepest {
            let layer = perRule.compactMap { $0.count > rank ? $0[rank] : nil }.sorted(by: earlier)
            for slot in layer where chosen.count < ceiling { chosen.append(slot) }
            rank += 1
        }
        let chosenIDs = Set(chosen.map(\.id))
        let overflow = perRule.flatMap { $0 }.filter { !chosenIDs.contains($0.id) }.sorted(by: earlier)
        let planned = Set(chosen.map(\.ruleID))
        let without = perRule.compactMap(\.first?.ruleID).filter { !planned.contains($0) }
        return AutoPlan(slots: chosen.sorted(by: earlier), overflow: overflow, rulesWithoutSlot: without, ceiling: ceiling,
                        plannedRules: Set(scheduled.map(\.id)))
    }

    /// The changes that make iOS's pending "rule." notices equal the plan. A notice whose moment or text changed is replaced;
    /// one whose day got a trip, or whose rule is gone or off, is removed. Other notices of the app are never touched.
    public static func reconcile(pending: [AutoPendingSlot], plan: AutoPlan, state: AutoState, calendar: Calendar) -> AutoReconcile {
        let wanted = Dictionary(plan.slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var remove: [String] = []
        var keep = Set<String>()
        var cancelled: [AutoPendingSlot] = []
        for item in pending where item.id.hasPrefix(identifierPrefix) {
            guard let slot = wanted[item.id], slot.title == item.title, slot.body == item.body,
                  item.fireAt.map({ abs($0.timeIntervalSince(slot.fireAt)) < 60 }) ?? false else {
                remove.append(item.id)
                if wanted[item.id] == nil, let fireAt = item.fireAt, state.hasTrip(on: fireAt, calendar: calendar),
                   let parsed = parse(item.id), plan.plannedRules.contains(parsed.ruleID) {
                    cancelled.append(item)
                }
                continue
            }
            keep.insert(item.id)
        }
        let add = plan.slots.filter { !keep.contains($0.id) }
        return AutoReconcile(toRemove: remove, toAdd: add, cancelledForTrip: cancelled)
    }

    // MARK: Helpers

    private static func earlier(_ a: AutoSlot, _ b: AutoSlot) -> Bool {
        a.fireAt != b.fireAt ? a.fireAt < b.fireAt : a.id < b.id
    }

    private static func deadlineDays(_ rule: AutoRule) -> Int {
        if case let .ticketDeadline(days) = rule.trigger { return days }
        return 0
    }

    private static func slot(_ rule: AutoRule, at moment: Date, reason: AutoReason, calendar: Calendar) -> AutoSlot {
        let content = AutoText.content(rule: rule, reason: reason, calendar: calendar)
        let draft = rule.addTrip
        return AutoSlot(id: identifier(ruleID: rule.id, day: moment, calendar: calendar), ruleID: rule.id, ruleName: rule.name,
                        fireAt: moment, title: content.title, body: content.body, opensAddTrip: draft != nil,
                        addTripFrom: draft?.from ?? nil, addTripTo: draft?.to ?? nil, shortcutName: rule.shortcutName)
    }
}
