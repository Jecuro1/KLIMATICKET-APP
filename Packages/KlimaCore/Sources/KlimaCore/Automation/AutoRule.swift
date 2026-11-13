import Foundation

// Automatik (docs/AUTOMATION.md): rules that live on the device – „Wenn …, dann …“. Pure values: no network, no storage, and
// nothing here can write a trip. A rule can only fire when the app is open, when a „Live verfolgen“ answer arrives, after a
// save, or as a local notification the app planned in advance (AutoRuleScheduler).

/// What starts a rule.
public enum AutoTrigger: Hashable, Sendable {
    /// `daysBefore` days before the active ticket ends, at 09:00 Vienna time. Planned in advance.
    case ticketDeadline(daysBefore: Int)
    /// The active ticket's amortisation reached one of these percentages (25, 50, 75, 100). Checked after a save; each
    /// percentage fires once per ticket (AutoLedger).
    case milestone(percents: Set<Int>)
    /// On these weekdays at this clock time (minutes after midnight, Vienna) when no trip is logged that day. Planned in
    /// advance; a day that gets a trip is cancelled.
    case dayWithoutTrip(weekdays: Set<RouteWeekday>, minuteOfDay: Int)
    /// The followed ride is at least `minutes` late at the alighting stop. Needs an active „Live verfolgen“; uses the answer
    /// the follow fetched anyway.
    case followDelay(minutes: Int)
    /// A trip that matches the filter was logged. Checked after a save.
    case tripLogged(AutoTripFilter)

    public var kind: AutoTriggerKind {
        switch self {
        case .ticketDeadline: .ticketDeadline
        case .milestone: .milestone
        case .dayWithoutTrip: .dayWithoutTrip
        case .followDelay: .followDelay
        case .tripLogged: .tripLogged
        }
    }

    /// Planned as local notifications in advance (the others fire on an event while the app runs).
    public var isScheduled: Bool { kind.isScheduled }

    /// The values a picker offers.
    public static let deadlineChoices = [1, 7, 14, 30, 60]
    public static let milestoneChoices = [25, 50, 75, 100]
    public static let delayChoices = [3, 5, 10, 15, 20, 30]

    /// The trigger with every value inside its allowed range (a stored rule from an older or broken file stays usable).
    public var normalized: AutoTrigger {
        switch self {
        case let .ticketDeadline(days):
            return .ticketDeadline(daysBefore: min(max(days, 0), 180))
        case let .milestone(percents):
            let valid = percents.filter { AutoTrigger.milestoneChoices.contains($0) }
            return .milestone(percents: valid.isEmpty ? [100] : valid)
        case let .dayWithoutTrip(weekdays, minute):
            return .dayWithoutTrip(weekdays: weekdays, minuteOfDay: AutoClock.clamp(minute))
        case let .followDelay(minutes):
            return .followDelay(minutes: min(max(minutes, 1), 180))
        case let .tripLogged(filter):
            return .tripLogged(filter.normalized)
        }
    }
}

/// The five triggers, for pickers and icons.
public enum AutoTriggerKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case ticketDeadline, milestone, dayWithoutTrip, followDelay, tripLogged

    public var id: String { rawValue }

    public var isScheduled: Bool { self == .ticketDeadline || self == .dayWithoutTrip }

    /// The trigger a new rule of this kind starts with.
    public var defaultTrigger: AutoTrigger {
        switch self {
        case .ticketDeadline: .ticketDeadline(daysBefore: 30)
        case .milestone: .milestone(percents: [50, 75, 100])
        case .dayWithoutTrip: .dayWithoutTrip(weekdays: AutoClock.workdays, minuteOfDay: 19 * 60)
        case .followDelay: .followDelay(minutes: 10)
        case .tripLogged: .tripLogged(AutoTripFilter(minValueEUR: 20))
        }
    }

    /// The conditions that make sense for this trigger. A planned trigger is checked at its moment; „heute noch keine
    /// Fahrt“ is part of „Tag ohne Fahrt“ already and means nothing after a save (a trip was just logged).
    public var allowedConditions: [AutoConditionKind] {
        switch self {
        case .ticketDeadline: []
        case .milestone: [.weekdays, .timeWindow]
        case .dayWithoutTrip: [.validTicket]
        case .followDelay: [.weekdays, .timeWindow]
        case .tripLogged: [.weekdays, .timeWindow, .validTicket]
        }
    }

    /// A cooldown only matters for triggers that can repeat within a day.
    public var usesCooldown: Bool { self == .followDelay || self == .tripLogged }
}

/// Which logged trips a „Fahrt erfasst“ rule reacts to. Empty fields match every trip.
public struct AutoTripFilter: Codable, Hashable, Sendable {
    /// Any of these modes (empty = every mode).
    public var modes: Set<TransportMode>
    /// At least this value (all legs, one person); nil = any value.
    public var minValueEUR: Double?
    /// One route in either direction (nil = every route).
    public var route: AutoRouteRef?

    public static let valueChoices: [Double] = [10, 20, 30, 50, 100]

    public init(modes: Set<TransportMode> = [], minValueEUR: Double? = nil, route: AutoRouteRef? = nil) {
        self.modes = modes
        self.minValueEUR = minValueEUR
        self.route = route
    }

    public var normalized: AutoTripFilter {
        var copy = self
        if let value = minValueEUR, !(value > 0) || !value.isFinite { copy.minValueEUR = nil }
        return copy
    }

    public var isEmpty: Bool { modes.isEmpty && minValueEUR == nil && route == nil }

    private enum CodingKeys: String, CodingKey { case modes, minValueEUR, route }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown mode (a newer app version) is skipped, not fatal.
        let raw = (try? c.decodeIfPresent([String].self, forKey: .modes)) ?? []
        modes = Set(raw.compactMap(TransportMode.init(rawValue:)))
        minValueEUR = try? c.decodeIfPresent(Double.self, forKey: .minValueEUR)
        route = try? c.decodeIfPresent(AutoRouteRef.self, forKey: .route)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modes.map(\.rawValue).sorted(), forKey: .modes)
        try c.encodeIfPresent(minValueEUR, forKey: .minValueEUR)
        try c.encodeIfPresent(route, forKey: .route)
    }
}

/// A route a rule refers to: two stations, in either direction. Station ids when known, the names otherwise.
public struct AutoRouteRef: Codable, Hashable, Sendable {
    public var fromName: String
    public var toName: String
    public var fromStationID: String?
    public var toStationID: String?

    public init(fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil) {
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
    }

    /// Same two ends, either direction. Ids decide where both sides have them; names (case-insensitive) otherwise.
    public func matches(fromName otherFrom: String, toName otherTo: String, fromStationID otherFromID: String?, toStationID otherToID: String?) -> Bool {
        func same(_ a: String, _ aID: String?, _ b: String, _ bID: String?) -> Bool {
            if let aID, let bID { return aID == bID }
            return a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let forward = same(fromName, fromStationID, otherFrom, otherFromID) && same(toName, toStationID, otherTo, otherToID)
        let backward = same(fromName, fromStationID, otherTo, otherToID) && same(toName, toStationID, otherFrom, otherFromID)
        return forward || backward
    }
}

/// An extra check before a rule fires.
public enum AutoCondition: Hashable, Sendable {
    /// Only on these weekdays (of the moment it would fire).
    case weekdays(Set<RouteWeekday>)
    /// Only between these clock times (minutes after midnight, Vienna; `start > end` runs over midnight, 22:00–06:00).
    case timeWindow(startMinute: Int, endMinute: Int)
    /// Only when no trip is logged today.
    case noTripToday
    /// Only while a ticket is valid.
    case validTicket

    public var kind: AutoConditionKind {
        switch self {
        case .weekdays: .weekdays
        case .timeWindow: .timeWindow
        case .noTripToday: .noTripToday
        case .validTicket: .validTicket
        }
    }
}

public enum AutoConditionKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case weekdays, timeWindow, noTripToday, validTicket

    public var id: String { rawValue }

    public var defaultCondition: AutoCondition {
        switch self {
        case .weekdays: .weekdays(AutoClock.workdays)
        case .timeWindow: .timeWindow(startMinute: 7 * 60, endMinute: 22 * 60)
        case .noTripToday: .noTripToday
        case .validTicket: .validTicket
        }
    }
}

/// What a rule does. Every rule tells the user (`notify`, with the automatic text when title and body are empty); the
/// other actions change what a tap on the notice or the toast opens. Nothing writes a trip.
public enum AutoAction: Hashable, Sendable {
    /// In the app a toast with a haptic; otherwise a local notification. Empty strings: the rule's automatic text.
    case notify(title: String, body: String)
    /// A tap opens „Fahrt erfassen“ (klimabilanz://add), optionally with two stations. It never saves anything.
    case openAddTrip(fromStationID: String?, toStationID: String?)
    /// A button that opens the Kurzbefehle app with this shortcut (shortcuts://run-shortcut). Not silent: iOS shows the app.
    case openShortcut(name: String)

    public var kind: AutoActionKind {
        switch self {
        case .notify: .notify
        case .openAddTrip: .openAddTrip
        case .openShortcut: .openShortcut
        }
    }
}

public enum AutoActionKind: String, CaseIterable, Codable, Sendable, Hashable {
    case notify, openAddTrip, openShortcut
}

/// One rule.
public struct AutoRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var trigger: AutoTrigger
    public var conditions: [AutoCondition]
    public var actions: [AutoAction]
    /// After a firing the rule stays silent this long (event triggers only; 0 = no cooldown).
    public var cooldownMinutes: Int
    public var createdAt: Date
    /// The template it was made from (AutoTemplates), so a template's switch finds its rule again.
    public var templateID: String?

    public static let cooldownChoices = [0, 15, 30, 60, 180, 1440]
    public static let maxNameLength = 40

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, trigger: AutoTrigger, conditions: [AutoCondition] = [],
                actions: [AutoAction] = [.notify(title: "", body: "")], cooldownMinutes: Int = 0, createdAt: Date, templateID: String? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.cooldownMinutes = cooldownMinutes
        self.createdAt = createdAt
        self.templateID = templateID
    }

    /// The rule as the engine reads it: values in range, conditions this trigger allows (one of each kind), a notice action.
    public var normalized: AutoRule {
        var copy = self
        copy.trigger = trigger.normalized
        let allowed = Set(trigger.kind.allowedConditions)
        var seen = Set<AutoConditionKind>()
        copy.conditions = conditions.filter { allowed.contains($0.kind) && seen.insert($0.kind).inserted }.map { condition in
            if case let .timeWindow(start, end) = condition { return .timeWindow(startMinute: AutoClock.clamp(start), endMinute: AutoClock.clamp(end)) }
            return condition
        }
        var kinds = Set<AutoActionKind>()
        copy.actions = actions.filter { kinds.insert($0.kind).inserted }
        if !kinds.contains(.notify) { copy.actions.insert(.notify(title: "", body: ""), at: 0) }
        copy.cooldownMinutes = trigger.kind.usesCooldown ? min(max(cooldownMinutes, 0), 7 * 24 * 60) : 0
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? AutoText.defaultName(for: trigger.kind) : String(trimmed.prefix(AutoRule.maxNameLength))
        return copy
    }

    // MARK: Convenience

    public var customTitle: String {
        for case let .notify(title, _) in actions { return title.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ""
    }

    public var customBody: String {
        for case let .notify(_, body) in actions { return body.trimmingCharacters(in: .whitespacesAndNewlines) }
        return ""
    }

    /// The draft a tap opens, when the rule opens „Fahrt erfassen“.
    public var addTrip: (from: String?, to: String?)? {
        for case let .openAddTrip(from, to) in actions { return (from, to) }
        return nil
    }

    public var shortcutName: String? {
        for case let .openShortcut(name) in actions {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    public func condition(_ kind: AutoConditionKind) -> AutoCondition? {
        conditions.first { $0.kind == kind }
    }
}

/// Everything the app stores of the rules (UserDefaults `rules.v1`): a version, the master switch, „Wochenende ruhig“ and
/// the rules. Decoding is tolerant: a rule that cannot be read (an unknown trigger of a newer version, a broken value) is
/// dropped on its own, and a file that cannot be read at all gives the empty book.
public struct AutoRuleBook: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let maxRules = 40

    public var version: Int
    /// The master switch („Automatik“). Off: nothing fires and nothing is planned.
    public var isEnabled: Bool
    /// „Wochenende ruhig“: no rule notifies on Saturday and Sunday.
    public var quietWeekend: Bool
    public var rules: [AutoRule]

    public init(isEnabled: Bool = true, quietWeekend: Bool = false, rules: [AutoRule] = []) {
        version = AutoRuleBook.currentVersion
        self.isEnabled = isEnabled
        self.quietWeekend = quietWeekend
        self.rules = rules
    }

    /// The rules that may fire.
    public var activeRules: [AutoRule] { isEnabled ? rules.filter(\.isEnabled).map(\.normalized) : [] }

    /// Reads a stored book. Garbage gives the empty book; a newer version is read as far as it is understood.
    public static func decode(_ data: Data?) -> AutoRuleBook {
        guard let data, let book = try? JSONDecoder().decode(AutoRuleBook.self, from: data) else { return AutoRuleBook() }
        return book
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    private enum CodingKeys: String, CodingKey { case version, isEnabled, quietWeekend, rules }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? AutoRuleBook.currentVersion
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true
        quietWeekend = (try? c.decode(Bool.self, forKey: .quietWeekend)) ?? false
        let lossy = (try? c.decode([AutoLossy<AutoRule>].self, forKey: .rules)) ?? []
        var seen = Set<UUID>()
        rules = lossy.compactMap(\.value).filter { seen.insert($0.id).inserted }.prefix(AutoRuleBook.maxRules).map { $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(AutoRuleBook.currentVersion, forKey: .version)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(quietWeekend, forKey: .quietWeekend)
        try c.encode(rules, forKey: .rules)
    }
}

/// Decodes one element of an array and keeps nil when it fails, so one broken element does not lose the others.
struct AutoLossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Codable forms (a "type" field and the values; an unknown type throws, and AutoLossy drops the rule)

extension AutoTrigger: Codable {
    private enum CodingKeys: String, CodingKey { case type, daysBefore, percents, weekdays, minuteOfDay, minutes, filter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case AutoTriggerKind.ticketDeadline.rawValue:
            self = .ticketDeadline(daysBefore: try c.decode(Int.self, forKey: .daysBefore))
        case AutoTriggerKind.milestone.rawValue:
            self = .milestone(percents: Set(try c.decode([Int].self, forKey: .percents)))
        case AutoTriggerKind.dayWithoutTrip.rawValue:
            let days = try c.decode([Int].self, forKey: .weekdays).compactMap(RouteWeekday.init(rawValue:))
            self = .dayWithoutTrip(weekdays: Set(days), minuteOfDay: try c.decode(Int.self, forKey: .minuteOfDay))
        case AutoTriggerKind.followDelay.rawValue:
            self = .followDelay(minutes: try c.decode(Int.self, forKey: .minutes))
        case AutoTriggerKind.tripLogged.rawValue:
            self = .tripLogged((try? c.decode(AutoTripFilter.self, forKey: .filter)) ?? AutoTripFilter())
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown trigger \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .type)
        switch self {
        case let .ticketDeadline(days): try c.encode(days, forKey: .daysBefore)
        case let .milestone(percents): try c.encode(percents.sorted(), forKey: .percents)
        case let .dayWithoutTrip(weekdays, minute):
            try c.encode(weekdays.map(\.rawValue).sorted(), forKey: .weekdays)
            try c.encode(minute, forKey: .minuteOfDay)
        case let .followDelay(minutes): try c.encode(minutes, forKey: .minutes)
        case let .tripLogged(filter): try c.encode(filter, forKey: .filter)
        }
    }
}

extension AutoCondition: Codable {
    private enum CodingKeys: String, CodingKey { case type, weekdays, startMinute, endMinute }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case AutoConditionKind.weekdays.rawValue:
            self = .weekdays(Set(try c.decode([Int].self, forKey: .weekdays).compactMap(RouteWeekday.init(rawValue:))))
        case AutoConditionKind.timeWindow.rawValue:
            self = .timeWindow(startMinute: try c.decode(Int.self, forKey: .startMinute), endMinute: try c.decode(Int.self, forKey: .endMinute))
        case AutoConditionKind.noTripToday.rawValue: self = .noTripToday
        case AutoConditionKind.validTicket.rawValue: self = .validTicket
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown condition \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .type)
        switch self {
        case let .weekdays(days): try c.encode(days.map(\.rawValue).sorted(), forKey: .weekdays)
        case let .timeWindow(start, end):
            try c.encode(start, forKey: .startMinute)
            try c.encode(end, forKey: .endMinute)
        case .noTripToday, .validTicket: break
        }
    }
}

extension AutoAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, title, body, fromStationID, toStationID, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case AutoActionKind.notify.rawValue:
            self = .notify(title: (try? c.decode(String.self, forKey: .title)) ?? "", body: (try? c.decode(String.self, forKey: .body)) ?? "")
        case AutoActionKind.openAddTrip.rawValue:
            self = .openAddTrip(fromStationID: try? c.decodeIfPresent(String.self, forKey: .fromStationID),
                                toStationID: try? c.decodeIfPresent(String.self, forKey: .toStationID))
        case AutoActionKind.openShortcut.rawValue:
            self = .openShortcut(name: try c.decode(String.self, forKey: .name))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind.rawValue, forKey: .type)
        switch self {
        case let .notify(title, body):
            try c.encode(title, forKey: .title)
            try c.encode(body, forKey: .body)
        case let .openAddTrip(from, to):
            try c.encodeIfPresent(from, forKey: .fromStationID)
            try c.encodeIfPresent(to, forKey: .toStationID)
        case let .openShortcut(name):
            try c.encode(name, forKey: .name)
        }
    }
}

extension AutoRule {
    private enum CodingKeys: String, CodingKey { case id, name, isEnabled, trigger, conditions, actions, cooldownMinutes, createdAt, templateID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trigger = try c.decode(AutoTrigger.self, forKey: .trigger)   // unknown trigger: the whole rule is dropped
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? false
        // An unknown condition or action is dropped on its own. A dropped condition would make the rule fire more often
        // than its owner chose, so such a rule comes back switched off.
        let rawConditions = (try? c.decode([AutoLossy<AutoCondition>].self, forKey: .conditions)) ?? []
        conditions = rawConditions.compactMap(\.value)
        if conditions.count != rawConditions.count { isEnabled = false }
        actions = ((try? c.decode([AutoLossy<AutoAction>].self, forKey: .actions)) ?? []).compactMap(\.value)
        if actions.isEmpty { actions = [.notify(title: "", body: "")] }
        cooldownMinutes = (try? c.decode(Int.self, forKey: .cooldownMinutes)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        templateID = try? c.decodeIfPresent(String.self, forKey: .templateID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(actions, forKey: .actions)
        try c.encode(cooldownMinutes, forKey: .cooldownMinutes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(templateID, forKey: .templateID)
    }
}
