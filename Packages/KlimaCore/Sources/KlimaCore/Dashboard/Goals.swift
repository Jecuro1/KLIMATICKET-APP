import Foundation

// MARK: uebersicht – own goals with a ring on the Übersicht (docs/DASHBOARD_LAYOUT.md §4): at most three, per Vienna calendar month
// (Fahrten, Wert, CO₂) or „Break-even bis …“. Stored under `goals.v1`; the ledger `goals.ledger.v1` remembers which goal was celebrated
// in which period, so reaching a goal pops once. The figures are the ones Statistik counts: Fahrten as journeys, values and CO₂ like the
// SavingsCalculator, only trips inside the ticket year. A projection is always called „Prognose“; no text promises a result.

public enum GoalKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case tripsPerMonth, valuePerMonth, co2PerMonth, breakEvenBy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tripsPerMonth: "Fahrten im Monat"
        case .valuePerMonth: "Wert im Monat"
        case .co2PerMonth: "CO₂ im Monat"
        case .breakEvenBy: "Break-even bis"
        }
    }

    public var symbol: String {
        switch self {
        case .tripsPerMonth: "tram.fill"
        case .valuePerMonth: "eurosign.circle.fill"
        case .co2PerMonth: "leaf.fill"
        case .breakEvenBy: "flag.checkered"
        }
    }

    public var isMonthly: Bool { self != .breakEvenBy }

    /// Stepper range and step of the target (N trips, euros, kilograms); nil for the date goal.
    public var targetRange: ClosedRange<Double>? {
        switch self {
        case .tripsPerMonth: 1...100
        case .valuePerMonth: 10...2000
        case .co2PerMonth: 1...500
        case .breakEvenBy: nil
        }
    }

    public var targetStep: Double {
        switch self {
        case .valuePerMonth: 10
        default: 1
        }
    }

    /// A first target that fits most people.
    public var suggestedTarget: Double {
        switch self {
        case .tripsPerMonth: 20
        case .valuePerMonth: 120
        case .co2PerMonth: 30
        case .breakEvenBy: 0
        }
    }

    /// The target snapped to the step and clamped to the range.
    public func clamped(_ target: Double) -> Double {
        guard let range = targetRange, target.isFinite else { return suggestedTarget }
        let snapped = (target / targetStep).rounded() * targetStep
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

public struct Goal: Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: GoalKind
    /// N trips, euros or kilograms per month (unused for `breakEvenBy`).
    public var target: Double
    /// The day of `breakEvenBy` (its end counts).
    public var until: Date?

    public init(id: UUID = UUID(), kind: GoalKind, target: Double? = nil, until: Date? = nil) {
        self.id = id
        self.kind = kind
        self.target = kind.clamped(target ?? kind.suggestedTarget)
        self.until = kind == .breakEvenBy ? until : nil
    }
}

/// The goals, stored under `goals.v1`.
public struct GoalList: Equatable, Sendable {
    public static let storageKey = "goals.v1"
    public static let currentVersion = 1
    public static let maxGoals = 3

    public private(set) var goals: [Goal]

    public init(_ goals: [Goal] = []) {
        var seen = Set<UUID>()
        self.goals = Array(goals.filter { seen.insert($0.id).inserted && ($0.kind != .breakEvenBy || $0.until != nil) }
            .prefix(Self.maxGoals))
    }

    public static let empty = GoalList()
    public var isFull: Bool { goals.count >= Self.maxGoals }

    /// Adds or replaces (same id) a goal. False when a new one does not fit.
    @discardableResult
    public mutating func upsert(_ goal: Goal) -> Bool {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = Goal(id: goal.id, kind: goal.kind, target: goal.target, until: goal.until)
            return true
        }
        guard !isFull, goal.kind != .breakEvenBy || goal.until != nil else { return false }
        goals.append(Goal(id: goal.id, kind: goal.kind, target: goal.target, until: goal.until))
        return true
    }

    public mutating func remove(id: UUID) {
        goals.removeAll { $0.id == id }
    }

    public static func decode(_ data: Data?) -> GoalList {
        guard let data, !data.isEmpty, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let version = stored.version, version >= 1, version <= currentVersion else { return .empty }
        let goals = stored.goals.compactMap { item -> Goal? in
            guard let item, let id = item.id.flatMap(UUID.init(uuidString:)), let kind = item.kind.flatMap(GoalKind.init(rawValue:))
            else { return nil }
            if kind == .breakEvenBy {
                guard let until = item.until else { return nil }
                return Goal(id: id, kind: kind, until: Date(timeIntervalSince1970: until))
            }
            return Goal(id: id, kind: kind, target: item.target)
        }
        return GoalList(goals)
    }

    public func encoded() -> Data {
        let items = goals.map { Stored.Item(id: $0.id.uuidString, kind: $0.kind.rawValue,
                                            target: $0.kind == .breakEvenBy ? nil : $0.target,
                                            until: $0.until?.timeIntervalSince1970) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Stored(version: Self.currentVersion, goals: items))) ?? Data()
    }

    private struct Stored: Codable {
        struct Item: Codable {
            var id: String?
            var kind: String?
            var target: Double?
            var until: Double?

            init(id: String?, kind: String?, target: Double?, until: Double?) {
                self.id = id
                self.kind = kind
                self.target = target
                self.until = until
            }

            private enum CodingKeys: String, CodingKey { case id, kind, target, until }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try? c.decodeIfPresent(String.self, forKey: .id)
                kind = try? c.decodeIfPresent(String.self, forKey: .kind)
                target = try? c.decodeIfPresent(Double.self, forKey: .target)
                until = try? c.decodeIfPresent(Double.self, forKey: .until)
            }
        }

        var version: Int?
        var goals: [Item?]

        init(version: Int?, goals: [Item?]) {
            self.version = version
            self.goals = goals
        }

        private enum CodingKeys: String, CodingKey { case version, goals }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            var read: [Item?] = []
            if var array = try? c.nestedUnkeyedContainer(forKey: .goals) {
                while !array.isAtEnd {
                    if let item = try? array.decode(Item.self) { read.append(item) }
                    else if (try? array.decode(DashSkip.self)) == nil { break } else { read.append(nil) }
                }
            }
            goals = read
        }
    }
}

/// Consumes one JSON element of any type.
struct DashSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

// MARK: - Evaluation

public enum GoalState: String, Sendable, Hashable {
    /// The target is met in this period.
    case reached
    /// At or above the linear pace of the period so far.
    case onTrack
    /// Below the linear pace.
    case behind
    /// `breakEvenBy`: the day has passed without the break-even.
    case missed
}

public struct GoalProgress: Equatable, Sendable, Identifiable {
    public var goal: Goal
    /// Trips, euros or kilograms so far in the period (the ticket's value for `breakEvenBy`).
    public var actual: Double
    /// The target (the ticket price for `breakEvenBy`).
    public var target: Double
    /// actual / target – can exceed 1.
    public var progress: Double
    public var state: GoalState
    /// What the linear pace asks for by now (the completed days of the period).
    public var expectedNow: Double
    /// Days left in the period, today included (0 once it is over).
    public var daysLeft: Int
    /// „2026-11“ for a month, „bis-2027-03-01“ for a date goal – the ledger's period.
    public var periodKey: String
    /// End of the month at the current pace (shown from the 7th) or, for `breakEvenBy`, the app's forecast of the break-even day.
    public var projectedValue: Double?
    public var projectedDate: Date?

    public var id: UUID { goal.id }
    public var remaining: Double { max(0, target - actual) }
    /// The ring's fill, 0 … 1.
    public var ringFraction: Double { progress.isFinite ? min(max(progress, 0), 1) : 0 }
}

/// Formats amounts in the app's style (Format.* in the app; tests pass their own).
public struct GoalFormatter: Sendable {
    public var euro: @Sendable (Double) -> String
    public var kg: @Sendable (Double) -> String
    public var day: @Sendable (Date) -> String

    public init(euro: @escaping @Sendable (Double) -> String, kg: @escaping @Sendable (Double) -> String,
                day: @escaping @Sendable (Date) -> String) {
        self.euro = euro
        self.kg = kg
        self.day = day
    }
}

public enum GoalEvaluator {
    /// Days before a monthly projection is shown (the first days would extrapolate wildly).
    public static let projectionFromDay = 7

    /// Progress of `goal` at `now`. Monthly goals read the trips of the Vienna calendar month that lie in the ticket year; the date goal
    /// reads the ticket's summary (the same SavingsSummary the Übersicht shows, so its Prognose is the Bilanz card's).
    public static func evaluate(_ goal: Goal, trips: [TripRecord], ticket: TicketPeriod, summary: SavingsSummary, now: Date,
                                emissions: EmissionFactors = .fallback, calendar: Calendar = .vienna) -> GoalProgress {
        if goal.kind == .breakEvenBy { return breakEven(goal, ticket: ticket, summary: summary, now: now, calendar: calendar) }

        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
        // Calendar days, not seconds: a month with the DST switch has 743 or 745 hours but still its 31 days.
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = min(daysInMonth, max(1, calendar.component(.day, from: now)))
        let inMonth = trips.filter { $0.date >= monthStart && $0.date < nextMonth && ticket.contains($0.date) }

        let actual: Double
        switch goal.kind {
        case .tripsPerMonth: actual = Double(JourneySummary.tripCount(inMonth))
        case .valuePerMonth: actual = inMonth.reduce(0) { $0 + $1.totalValue }
        case .co2PerMonth: actual = inMonth.reduce(0) { $0 + emissions.savedKg(km: $1.totalDistanceKm, mode: $1.mode) }
        case .breakEvenBy: actual = 0
        }
        let target = goal.target
        let completedShare = Double(dayOfMonth - 1) / Double(daysInMonth)
        let expected = target * completedShare
        let state: GoalState
        if actual >= target - 1e-9 {
            state = .reached
        } else if actual + 1e-9 >= (goal.kind == .tripsPerMonth ? floor(expected + 1e-9) : expected) {
            state = .onTrack
        } else {
            state = .behind
        }
        var projected: Double?
        if state != .reached, dayOfMonth >= projectionFromDay {
            projected = actual / Double(dayOfMonth) * Double(daysInMonth)
        }
        let year = calendar.component(.year, from: monthStart), month = calendar.component(.month, from: monthStart)
        return GoalProgress(goal: goal, actual: actual, target: target, progress: target > 0 ? actual / target : 0, state: state,
                            expectedNow: expected, daysLeft: daysInMonth - dayOfMonth + 1,
                            periodKey: String(format: "%04d-%02d", year, month), projectedValue: projected, projectedDate: nil)
    }

    private static func breakEven(_ goal: Goal, ticket: TicketPeriod, summary: SavingsSummary, now: Date,
                                  calendar: Calendar) -> GoalProgress {
        let target = summary.ticketPrice
        let actual = summary.totalValue
        let until = goal.until ?? ticket.end
        let startDay = calendar.startOfDay(for: ticket.start)
        let goalDay = calendar.startOfDay(for: until)
        let today = calendar.startOfDay(for: now)
        let totalDays = max(1, (calendar.dateComponents([.day], from: startDay, to: goalDay).day ?? 0) + 1)
        let completed = min(totalDays, max(0, calendar.dateComponents([.day], from: startDay, to: today).day ?? 0))
        let expected = target * Double(completed) / Double(totalDays)
        let daysLeft = max(0, (calendar.dateComponents([.day], from: today, to: goalDay).day ?? 0) + 1)

        let state: GoalState
        if summary.isPaidOff, summary.paidOffDate.map({ calendar.startOfDay(for: $0) <= goalDay }) ?? true {
            state = .reached
        } else if today > goalDay {
            state = .missed
        } else if let forecast = summary.forecastBreakEvenDate {
            // The app's forecast decides – the goal never contradicts the Bilanz card's „Break-even · Prognose“.
            state = calendar.startOfDay(for: forecast) <= goalDay ? .onTrack : .behind
        } else {
            state = actual + 1e-9 >= expected ? .onTrack : .behind
        }
        let key = "bis-" + dayKey(goalDay, calendar: calendar)
        return GoalProgress(goal: goal, actual: actual, target: target, progress: target > 0 ? actual / target : 1, state: state,
                            expectedNow: expected, daysLeft: state == .missed ? 0 : daysLeft, periodKey: key,
                            projectedValue: nil,
                            projectedDate: state == .reached || state == .missed ? nil : summary.forecastBreakEvenDate)
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The first and last day a `breakEvenBy` goal may name: from today (or the ticket's start) to the ticket's last day.
    public static func dateRange(for ticket: TicketPeriod, now: Date, calendar: Calendar = .vienna) -> ClosedRange<Date> {
        let first = calendar.startOfDay(for: max(now, ticket.start))
        let last = calendar.startOfDay(for: ticket.end)
        return first...max(first, last)
    }
}

// MARK: - Texts

public enum GoalText {
    /// „1 Fahrt“ · „20 Fahrten“.
    public static func trips(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(n) Fahrten" }

    /// „20 Fahrten im Monat“ · „€ 150 Wert im Monat“ · „30 kg CO₂ im Monat“ · „Break-even bis 1. März“.
    public static func title(_ goal: Goal, format: GoalFormatter) -> String {
        switch goal.kind {
        case .tripsPerMonth: "\(trips(Int(goal.target))) im Monat"
        case .valuePerMonth: "\(format.euro(goal.target)) Wert im Monat"
        case .co2PerMonth: "\(format.kg(goal.target)) CO₂ im Monat"
        case .breakEvenBy: "Break-even bis \(goal.until.map(format.day) ?? "Ticketende")"
        }
    }

    /// The amount in the goal's unit: „4 Fahrten“, „€ 36“, „12 kg“. Euros and kilograms are rounded up for what is still missing.
    static func amount(_ value: Double, kind: GoalKind, format: GoalFormatter, roundingUp: Bool) -> String {
        let shown = roundingUp ? (value - 1e-9).rounded(.up) : value.rounded()
        switch kind {
        case .tripsPerMonth: return trips(Int(max(0, shown)))
        case .valuePerMonth, .breakEvenBy: return format.euro(max(0, shown))
        case .co2PerMonth: return format.kg(max(0, shown))
        }
    }

    /// „12 von 20 Fahrten“ · „€ 84 von € 150“ · „€ 946 von € 1.400“.
    public static func status(_ p: GoalProgress, format: GoalFormatter) -> String {
        let actual = p.goal.kind == .tripsPerMonth ? Double(Int(p.actual.rounded())) : p.actual
        switch p.goal.kind {
        case .tripsPerMonth: return "\(Int(actual)) von \(trips(Int(p.target)))"
        case .valuePerMonth, .breakEvenBy: return "\(format.euro(actual.rounded(.down))) von \(format.euro(p.target.rounded()))"
        case .co2PerMonth: return "\(format.kg(actual.rounded(.down))) von \(format.kg(p.target))"
        }
    }

    /// What is left, with a pace that is a fact, not a promise: „noch 4 Fahrten · etwa 1 pro Woche“, „noch € 36 · 5 Tage übrig“,
    /// „noch 2 Fahrten · heute ist der letzte Tag“, „Geschafft · 24 von 20 Fahrten“.
    public static func remaining(_ p: GoalProgress, format: GoalFormatter) -> String {
        let kind = p.goal.kind
        switch p.state {
        case .reached:
            if kind == .breakEvenBy { return "Geschafft · dein Ticket hat sich rentiert" }
            return "Geschafft · \(status(p, format: format))"
        case .missed:
            return "Der Tag ist vorbei · noch \(amount(p.remaining, kind: kind, format: format, roundingUp: true)) bis zum Break-even"
        case .onTrack, .behind:
            let rest = "noch \(amount(p.remaining, kind: kind, format: format, roundingUp: true))"
            if kind == .breakEvenBy {
                return rest + " · " + (p.daysLeft == 1 ? "heute ist der Tag" : "\(p.daysLeft) Tage bis zum Ziel")
            }
            switch p.daysLeft {
            case ...1:
                return rest + " · heute ist der letzte Tag"
            case 2...7:
                return rest + " · \(p.daysLeft) Tage übrig"
            default:
                let perWeek = p.remaining / (Double(p.daysLeft) / 7)
                let pace = kind == .tripsPerMonth
                    ? String(max(1, Int((perWeek - 1e-9).rounded(.up))))
                    : amount(perWeek, kind: kind, format: format, roundingUp: true)
                return rest + " · etwa \(pace) pro Woche"
            }
        }
    }

    /// „Prognose: etwa 22 Fahrten bis Monatsende“ · „Prognose: Break-even am 14. Dez.“ – nil without one.
    public static func projection(_ p: GoalProgress, format: GoalFormatter) -> String? {
        if let date = p.projectedDate { return "Prognose: Break-even am \(format.day(date))" }
        guard let value = p.projectedValue, value.isFinite else { return nil }
        return "Prognose: etwa \(amount(value, kind: p.goal.kind, format: format, roundingUp: false)) bis Monatsende"
    }

    /// „Auf Kurs“ · „Etwas hinter Plan“ · „Geschafft“ · „Nicht geschafft“ – the state in words (the ring is never the only sign).
    public static func stateLabel(_ state: GoalState) -> String {
        switch state {
        case .reached: "Geschafft"
        case .onTrack: "Auf Kurs"
        case .behind: "Hinter Plan"
        case .missed: "Nicht geschafft"
        }
    }
}

// MARK: - Ledger

/// Which goal was celebrated in which period (`goals.ledger.v1`): one haptic and one pop per goal and period.
public struct GoalLedger: Equatable, Sendable {
    public static let storageKey = "goals.ledger.v1"
    /// Entries kept (three goals for about a year of months).
    public static let capacity = 48

    public private(set) var entries: [String]

    public init(_ entries: [String] = []) {
        self.entries = Array(entries.suffix(Self.capacity))
    }

    static func key(_ progress: GoalProgress) -> String { "\(progress.goal.id.uuidString)|\(progress.periodKey)" }

    public func hasCelebrated(_ progress: GoalProgress) -> Bool { entries.contains(Self.key(progress)) }

    /// True exactly once per goal and period, the first time it is reached; records it.
    public mutating func celebrate(_ progress: GoalProgress) -> Bool {
        guard progress.state == .reached else { return false }
        let key = Self.key(progress)
        guard !entries.contains(key) else { return false }
        entries.append(key)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        return true
    }

    /// Records a reached goal without celebrating (a goal saved while already met).
    public mutating func markSeen(_ progress: GoalProgress) {
        _ = celebrate(progress)
    }

    public static func decode(_ data: Data?) -> GoalLedger {
        guard let data, !data.isEmpty, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return GoalLedger() }
        return GoalLedger(stored.entries)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Stored(version: 1, entries: entries))) ?? Data()
    }

    private struct Stored: Codable {
        var version: Int?
        var entries: [String]

        init(version: Int?, entries: [String]) {
            self.version = version
            self.entries = entries
        }

        private enum CodingKeys: String, CodingKey { case version, entries }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            entries = DashTolerant.strings(c, .entries)
        }
    }
}
