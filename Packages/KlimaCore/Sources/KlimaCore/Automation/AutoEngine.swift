import Foundation

// Automatik (docs/AUTOMATION.md): the one place that decides whether a rule fires. The runner calls it after a save, after a
// follow answer and when a planned notice arrives in the open app; the Testlauf calls it with `.probe` and shows the very
// verdict it returns (`AutoText.explanation`), so the explanation can never disagree with the decision.

/// What happened.
public enum AutoEvent: Hashable, Sendable {
    /// A save: milestones and newly logged trips are checked.
    case committed
    /// A „Live verfolgen“ answer arrived (`AutoState.follow`).
    case followUpdated
    /// A planned moment arrived while the app is open.
    case slotDue(Date)
    /// Testlauf: as if the trigger's own event happened now (a planned trigger names its next moment).
    case probe
}

/// When the rule fires.
public enum AutoOutcome: Hashable, Sendable {
    case now
    /// A planned trigger: at this moment, if nothing changes until then.
    case at(Date)
    case silent
}

/// Why a trip does not match a filter.
public enum AutoTripMismatch: Hashable, Sendable {
    case route(AutoRouteRef)
    case mode(found: Set<TransportMode>, wanted: Set<TransportMode>)
    case value(found: Double, minimum: Double)
}

/// The reason behind a verdict – one fact, in words by `AutoText.reasonText`.
public enum AutoReason: Hashable, Sendable {
    // Fires
    case deadline(days: Int, ticketName: String, end: Date, movedForWeekend: Bool)
    case milestone(percent: Int, current: Int, ticketName: String)
    case dayWithoutTrip(day: Date, isToday: Bool)
    case delay(minutes: Int, threshold: Int, stop: String, line: String)
    case tripMatched(trip: AutoTripFact, filter: AutoTripFilter, count: Int, isLastTrip: Bool)
    // Silent
    case ruleOff
    case noTicket
    case deadlinePassed(day: Date)
    case ticketEnded
    case milestoneBelow(current: Int, next: Int)
    case milestonesDone(current: Int)
    case tripToday(next: Date?)
    case noWeekday
    case noUpcomingSlot
    case noFollow
    case followEnded
    case noDelayData
    case delayBelow(minutes: Int, threshold: Int)
    case alreadyReported(threshold: Int)
    case noTrip
    case noNewTrip
    case tripNotMatched(trip: AutoTripFact, mismatch: AutoTripMismatch, isLastTrip: Bool)
    case weekdayExcluded(RouteWeekday)
    case outsideWindow(start: Int, end: Int)
    case ticketInvalid
    case quietWeekend
    case cooldown(until: Date)
    /// The event belongs to another trigger (the runner only asks the rules an event concerns).
    case otherEvent
}

/// A notice to deliver: in the app as a toast, otherwise as a local notification.
public struct AutoFiring: Hashable, Sendable {
    public var ruleID: UUID
    public var ruleName: String
    public var title: String
    public var body: String
    public var at: Date
    /// A tap opens „Fahrt erfassen“ (with these stations, when set).
    public var opensAddTrip: Bool
    public var addTripFrom: String?
    public var addTripTo: String?
    /// A button opens this shortcut in the Kurzbefehle app.
    public var shortcutName: String?
    /// The decision in words (the log keeps it).
    public var explanation: String
}

/// The decision about one rule for one event.
public struct AutoVerdict: Hashable, Sendable {
    public var ruleID: UUID
    public var outcome: AutoOutcome
    public var reason: AutoReason
    /// What the user gets (empty unless `outcome == .now`).
    public var firings: [AutoFiring]
    /// Ledger changes, applied by the runner once the firings went out (never by the Testlauf).
    public var marks: [AutoMark]
    /// The rule has conditions and all of them hold (said in the explanation).
    public var conditionsMet: Bool
    /// The rule has a cooldown and it is not running (said in the explanation).
    public var cooldownClear: Bool
    /// The moment the verdict was made.
    public var now: Date

    public var fires: Bool { outcome != .silent }
}

public enum AutoRuleEngine {
    /// Decides `rule` for `event`. Pure: same inputs, same verdict. `.probe` ignores the rule's own switch (the Testlauf of a
    /// rule that is off explains what it would do); every other event of a rule that is off is silent.
    public static func evaluate(_ rule: AutoRule, event: AutoEvent, state: AutoState, now: Date,
                                calendar: Calendar = .vienna) -> AutoVerdict {
        let rule = rule.normalized
        let ctx = Context(rule: rule, state: state, now: now, calendar: calendar)
        guard rule.isEnabled || event == .probe else { return ctx.silent(.ruleOff) }
        switch rule.trigger {
        case let .ticketDeadline(days):
            return deadline(days: days, event: event, ctx)
        case let .milestone(percents):
            return milestone(percents: percents, event: event, ctx)
        case let .dayWithoutTrip(weekdays, minute):
            return dayWithoutTrip(weekdays: weekdays, minute: minute, event: event, ctx)
        case let .followDelay(threshold):
            return followDelay(threshold: threshold, event: event, ctx)
        case let .tripLogged(filter):
            return tripLogged(filter: filter, event: event, ctx)
        }
    }

    // MARK: Ticket deadline

    private static func deadline(days: Int, event: AutoEvent, _ ctx: Context) -> AutoVerdict {
        switch event {
        case .probe, .slotDue: break
        default: return ctx.silent(.otherEvent)
        }
        guard let ticket = ctx.state.ticket else { return ctx.silent(.noTicket) }
        guard let planned = deadlineMoment(rule: ctx.rule, ticket: ticket, state: ctx.state, calendar: ctx.calendar) else {
            return ctx.silent(.noTicket)
        }
        let reason = AutoReason.deadline(days: days, ticketName: ticket.name, end: ticket.end, movedForWeekend: planned.moved)
        if case .slotDue = event { return ctx.fire(reason, conditionsAt: nil) }
        if planned.moment > ctx.now { return ctx.later(planned.moment, reason) }
        return ctx.silent(ctx.now <= ticket.end ? .deadlinePassed(day: planned.moment) : .ticketEnded)
    }

    /// 09:00 on the day `daysBefore` calendar days before the ticket's last day. With „Wochenende ruhig“ a Saturday or Sunday
    /// moves to the Friday before (a deadline must not be skipped).
    static func deadlineMoment(rule: AutoRule, ticket: AutoTicketFact, state: AutoState, calendar: Calendar) -> (moment: Date, moved: Bool)? {
        guard case let .ticketDeadline(days) = rule.trigger.normalized else { return nil }
        let lastDay = calendar.startOfDay(for: ticket.end)
        guard var day = calendar.date(byAdding: .day, value: -days, to: lastDay) else { return nil }
        var moved = false
        if state.quietWeekend {
            switch AutoClock.weekday(day, calendar: calendar) {
            case .saturday: day = calendar.date(byAdding: .day, value: -1, to: day) ?? day; moved = true
            case .sunday: day = calendar.date(byAdding: .day, value: -2, to: day) ?? day; moved = true
            default: break
            }
        }
        guard let moment = AutoClock.moment(on: day, minuteOfDay: AutoRuleScheduler.deadlineMinute, calendar: calendar) else { return nil }
        return (moment, moved)
    }

    // MARK: Milestone

    private static func milestone(percents: Set<Int>, event: AutoEvent, _ ctx: Context) -> AutoVerdict {
        guard event == .committed || event == .probe else { return ctx.silent(.otherEvent) }
        guard let ticket = ctx.state.ticket else { return ctx.silent(.noTicket) }
        let current = ticket.percent
        let reached = Set(percents.filter { ticket.amortizedFraction * 100 + 1e-9 >= Double($0) })
        let done = ctx.state.ledger.celebrated(ruleID: ctx.rule.id, ticketID: ticket.id)
        let fresh = reached.subtracting(done)
        guard let top = fresh.max() else {
            if let next = percents.subtracting(reached).min() { return ctx.silent(.milestoneBelow(current: current, next: next)) }
            return ctx.silent(.milestonesDone(current: current))
        }
        var verdict = ctx.fire(.milestone(percent: top, current: current, ticketName: ticket.name), conditionsAt: ctx.now)
        if verdict.outcome == .now {
            verdict.marks.insert(.milestones(ruleID: ctx.rule.id, ticketID: ticket.id, percents: fresh), at: 0)
        }
        return verdict
    }

    // MARK: Day without a trip

    private static func dayWithoutTrip(weekdays: Set<RouteWeekday>, minute: Int, event: AutoEvent, _ ctx: Context) -> AutoVerdict {
        guard !weekdays.isEmpty else { return ctx.silent(.noWeekday) }
        switch event {
        case let .slotDue(moment):
            if let blocked = dayBlock(ctx.rule, day: moment, state: ctx.state, calendar: ctx.calendar) { return ctx.silent(blocked) }
            return ctx.fire(.dayWithoutTrip(day: moment, isToday: true), conditionsAt: nil)
        case .probe:
            let today = ctx.calendar.startOfDay(for: ctx.now)
            let candidates = AutoRuleScheduler.candidates(for: ctx.rule, state: ctx.state, now: ctx.now, calendar: ctx.calendar)
            // Today's moment still ahead but blocked: say why today stays quiet and when the next one is.
            if weekdays.contains(AutoClock.weekday(ctx.now, calendar: ctx.calendar)),
               let todayMoment = AutoClock.moment(on: today, minuteOfDay: minute, calendar: ctx.calendar), todayMoment > ctx.now,
               let blocked = dayBlock(ctx.rule, day: todayMoment, state: ctx.state, calendar: ctx.calendar) {
                let next = candidates.first { !ctx.calendar.isDate($0.fireAt, inSameDayAs: today) }?.fireAt
                if case .tripToday = blocked { return ctx.silent(.tripToday(next: next)) }
                return ctx.silent(blocked)
            }
            guard let first = candidates.first else { return ctx.silent(.noUpcomingSlot) }
            let isToday = ctx.calendar.isDate(first.fireAt, inSameDayAs: ctx.now)
            return ctx.later(first.fireAt, .dayWithoutTrip(day: first.fireAt, isToday: isToday))
        default:
            return ctx.silent(.otherEvent)
        }
    }

    /// Why a planned day stays quiet (nil: it may fire). Shared by the scheduler and the Testlauf.
    static func dayBlock(_ rule: AutoRule, day moment: Date, state: AutoState, calendar: Calendar) -> AutoReason? {
        if state.hasTrip(on: moment, calendar: calendar) { return .tripToday(next: nil) }
        if state.quietWeekend, AutoClock.weekend.contains(AutoClock.weekday(moment, calendar: calendar)) { return .quietWeekend }
        return conditionBlock(rule, at: moment, state: state, calendar: calendar)
    }

    // MARK: Follow delay

    private static func followDelay(threshold: Int, event: AutoEvent, _ ctx: Context) -> AutoVerdict {
        guard event == .followUpdated || event == .probe else { return ctx.silent(.otherEvent) }
        let ruleKey = ctx.rule.id.uuidString
        let reported = ctx.state.ledger.followReported[ruleKey]
        let recover: [AutoMark] = reported == nil ? [] : [.followRecovered(ruleID: ctx.rule.id)]
        guard let follow = ctx.state.follow else { return ctx.silent(.noFollow, marks: recover) }
        if follow.isFinished { return ctx.silent(.followEnded, marks: recover) }
        guard let delay = follow.delayMinutes else { return ctx.silent(.noDelayData) }
        if delay < threshold {
            // Back under the threshold: the next rise is news again.
            return ctx.silent(.delayBelow(minutes: delay, threshold: threshold), marks: recover)
        }
        if reported == follow.tripID { return ctx.silent(.alreadyReported(threshold: threshold)) }
        var verdict = ctx.fire(.delay(minutes: delay, threshold: threshold, stop: follow.stopName, line: follow.lineName), conditionsAt: ctx.now)
        if verdict.outcome == .now { verdict.marks.insert(.followReported(ruleID: ctx.rule.id, tripID: follow.tripID), at: 0) }
        return verdict
    }

    // MARK: Trip logged

    private static func tripLogged(filter: AutoTripFilter, event: AutoEvent, _ ctx: Context) -> AutoVerdict {
        let trips: [AutoTripFact]
        let isLast: Bool
        switch event {
        case .committed:
            guard !ctx.state.newTrips.isEmpty else { return ctx.silent(.noNewTrip) }
            trips = ctx.state.newTrips
            isLast = false
        case .probe:
            guard let last = ctx.state.lastTrip else { return ctx.silent(.noTrip) }
            trips = [last]
            isLast = true
        default:
            return ctx.silent(.otherEvent)
        }
        let matched = trips.filter { mismatch(of: $0, filter: filter) == nil }
        guard let newest = matched.max(by: { $0.createdAt < $1.createdAt }) else {
            let shown = trips.max(by: { $0.createdAt < $1.createdAt }) ?? trips[0]
            let why = mismatch(of: shown, filter: filter) ?? .value(found: shown.value, minimum: 0)
            return ctx.silent(.tripNotMatched(trip: shown, mismatch: why, isLastTrip: isLast))
        }
        return ctx.fire(.tripMatched(trip: newest, filter: filter, count: matched.count, isLastTrip: isLast), conditionsAt: ctx.now)
    }

    /// The first reason a trip fails the filter: route, then mode, then value. nil when it matches.
    public static func mismatch(of trip: AutoTripFact, filter: AutoTripFilter) -> AutoTripMismatch? {
        if let route = filter.route,
           !route.matches(fromName: trip.fromName, toName: trip.toName, fromStationID: trip.fromStationID, toStationID: trip.toStationID) {
            return .route(route)
        }
        if !filter.modes.isEmpty, filter.modes.isDisjoint(with: trip.modes) {
            return .mode(found: trip.modes, wanted: filter.modes)
        }
        if let minimum = filter.minValueEUR, trip.value + 0.005 < minimum {
            return .value(found: trip.value, minimum: minimum)
        }
        return nil
    }

    // MARK: Conditions

    /// The first condition that does not hold at `moment` (nil: all hold).
    static func conditionBlock(_ rule: AutoRule, at moment: Date, state: AutoState, calendar: Calendar) -> AutoReason? {
        for condition in rule.conditions {
            switch condition {
            case let .weekdays(days):
                let weekday = AutoClock.weekday(moment, calendar: calendar)
                if !days.contains(weekday) { return .weekdayExcluded(weekday) }
            case let .timeWindow(start, end):
                if !AutoClock.window(start, end, contains: AutoClock.minuteOfDay(moment, calendar: calendar)) {
                    return .outsideWindow(start: start, end: end)
                }
            case .noTripToday:
                if state.hasTrip(on: moment, calendar: calendar) { return .tripToday(next: nil) }
            case .validTicket:
                if !(state.ticket?.isValid(at: moment) ?? false) { return .ticketInvalid }
            }
        }
        return nil
    }

    // MARK: Verdicts

    private struct Context {
        let rule: AutoRule
        let state: AutoState
        let now: Date
        let calendar: Calendar

        func silent(_ reason: AutoReason, marks: [AutoMark] = []) -> AutoVerdict {
            AutoVerdict(ruleID: rule.id, outcome: .silent, reason: reason, firings: [], marks: marks,
                        conditionsMet: false, cooldownClear: false, now: now)
        }

        /// A planned trigger's next moment (the Testlauf).
        func later(_ moment: Date, _ reason: AutoReason) -> AutoVerdict {
            AutoVerdict(ruleID: rule.id, outcome: .at(moment), reason: reason, firings: [], marks: [],
                        conditionsMet: !rule.conditions.isEmpty, cooldownClear: false, now: now)
        }

        /// Fires now unless „Wochenende ruhig“, a condition (checked at `conditionsAt`; nil when the scheduler checked them
        /// already) or the cooldown holds it back.
        func fire(_ reason: AutoReason, conditionsAt moment: Date?) -> AutoVerdict {
            if let moment {
                if state.quietWeekend, AutoClock.weekend.contains(AutoClock.weekday(moment, calendar: calendar)) { return silent(.quietWeekend) }
                if let blocked = AutoRuleEngine.conditionBlock(rule, at: moment, state: state, calendar: calendar) { return silent(blocked) }
            }
            let usesCooldown = rule.trigger.kind.usesCooldown && rule.cooldownMinutes > 0
            if usesCooldown, let last = state.ledger.lastFired[rule.id.uuidString] {
                let until = last.addingTimeInterval(TimeInterval(rule.cooldownMinutes * 60))
                if now < until { return silent(.cooldown(until: until)) }
            }
            var verdict = AutoVerdict(ruleID: rule.id, outcome: .now, reason: reason, firings: [], marks: [.fired(ruleID: rule.id, at: now)],
                                      conditionsMet: !rule.conditions.isEmpty, cooldownClear: usesCooldown, now: now)
            let content = AutoText.content(rule: rule, reason: reason, calendar: calendar)
            let draft = rule.addTrip
            verdict.firings = [AutoFiring(ruleID: rule.id, ruleName: rule.name, title: content.title, body: content.body, at: now,
                                          opensAddTrip: draft != nil, addTripFrom: draft?.from ?? nil, addTripTo: draft?.to ?? nil,
                                          shortcutName: rule.shortcutName,
                                          explanation: AutoText.explanation(verdict, calendar: calendar))]
            return verdict
        }
    }
}
