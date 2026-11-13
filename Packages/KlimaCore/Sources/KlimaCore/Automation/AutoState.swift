import Foundation

// Automatik (docs/AUTOMATION.md): what the engine reads – facts the app hands over (read from its store and from the follow it
// runs anyway) – and the small records it keeps on the device (ledger, log). Plain values.

/// Clock and calendar helpers. Every moment of the automation is Vienna local time; days are counted with the calendar, never
/// with 86 400 seconds, so the daylight-saving changes (2026-03-29, 2026-10-25) keep 19:00 at 19:00.
public enum AutoClock {
    public static let workdays: Set<RouteWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let weekend: Set<RouteWeekday> = [.saturday, .sunday]

    public static func clamp(_ minute: Int) -> Int { min(max(minute, 0), 24 * 60 - 1) }

    /// „07:05“.
    public static func clockText(_ minuteOfDay: Int) -> String {
        let m = clamp(minuteOfDay)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    public static func weekday(_ date: Date, calendar: Calendar) -> RouteWeekday {
        RouteWeekday(calendarWeekday: calendar.component(.weekday, from: date)) ?? .monday
    }

    /// „20261116“ – the calendar day of `date` (the identifier part of a planned notice).
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// `minuteOfDay` on the calendar day of `day`, as wall-clock time. A time that does not exist on that day (02:30 on the
    /// spring change) moves forward by the gap, as the calendar does; a time that exists twice (02:30 in autumn) is the
    /// first one.
    public static func moment(on day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        let m = clamp(minuteOfDay)
        parts.hour = m / 60
        parts.minute = m % 60
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// True when `minute` lies in the window; `start > end` runs over midnight, `start == end` is the whole day.
    public static func window(_ start: Int, _ end: Int, contains minute: Int) -> Bool {
        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }
}

/// The active ticket, as the rules see it.
public struct AutoTicketFact: Hashable, Sendable {
    /// Stable id (the ticket's UUID): the milestone ledger counts per ticket.
    public var id: String
    public var name: String
    public var start: Date
    /// The last moment of the validity (TicketPeriod.end).
    public var end: Date
    /// Value logged so far ÷ own share of the price (can exceed 1).
    public var amortizedFraction: Double
    public var price: Double
    public var value: Double

    public init(id: String, name: String, start: Date, end: Date, amortizedFraction: Double, price: Double, value: Double) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.amortizedFraction = amortizedFraction
        self.price = price
        self.value = value
    }

    public func isValid(at date: Date) -> Bool { date >= start && date <= end }

    /// Whole percent, rounded down (51.9 % is 51 %, so „50 % erreicht“ is never said too early).
    public var percent: Int { Int((amortizedFraction * 100 + 1e-9).rounded(.down)) }
}

/// One logged trip (a journey of several legs is one trip: first start, last destination, summed value).
public struct AutoTripFact: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    /// When it was saved – only trips saved after the last check count as „neu erfasst“.
    public var createdAt: Date
    public var fromName: String
    public var toName: String
    public var fromStationID: String?
    public var toStationID: String?
    public var modes: Set<TransportMode>
    /// All legs, one person.
    public var value: Double

    public init(id: UUID, date: Date, createdAt: Date, fromName: String, toName: String, fromStationID: String? = nil,
                toStationID: String? = nil, modes: Set<TransportMode>, value: Double) {
        self.id = id
        self.date = date
        self.createdAt = createdAt
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.modes = modes
        self.value = value
    }
}

/// The active „Live verfolgen“, from its last answer. No request is made for it.
public struct AutoFollowFact: Hashable, Sendable {
    public var tripID: String
    public var lineName: String
    /// The alighting stop.
    public var stopName: String
    /// Delay at the alighting stop (arrival, else departure); nil while the answer has no realtime for it.
    public var delayMinutes: Int?
    public var isFinished: Bool
    /// When the answer was received.
    public var updatedAt: Date

    public init(tripID: String, lineName: String, stopName: String, delayMinutes: Int?, isFinished: Bool, updatedAt: Date) {
        self.tripID = tripID
        self.lineName = lineName
        self.stopName = stopName
        self.delayMinutes = delayMinutes
        self.isFinished = isFinished
        self.updatedAt = updatedAt
    }

    /// Whole minutes late from seconds (rounded down; early counts as on time).
    public static func minutes(fromDelaySeconds seconds: Int?) -> Int? {
        guard let seconds else { return nil }
        return max(0, seconds) / 60
    }
}

/// Everything the engine reads besides the rule, the event and the clock.
public struct AutoState: Hashable, Sendable {
    public var ticket: AutoTicketFact?
    /// Day keys (AutoClock.dayKey) of the days that have at least one trip – today and the planning horizon.
    public var tripDays: Set<String>
    /// Trips saved since the last check („Fahrt erfasst“).
    public var newTrips: [AutoTripFact]
    /// The newest trip (the Testlauf of „Fahrt erfasst“).
    public var lastTrip: AutoTripFact?
    public var follow: AutoFollowFact?
    public var ledger: AutoLedger
    /// „Wochenende ruhig“ of the book.
    public var quietWeekend: Bool

    public init(ticket: AutoTicketFact? = nil, tripDays: Set<String> = [], newTrips: [AutoTripFact] = [], lastTrip: AutoTripFact? = nil,
                follow: AutoFollowFact? = nil, ledger: AutoLedger = AutoLedger(), quietWeekend: Bool = false) {
        self.ticket = ticket
        self.tripDays = tripDays
        self.newTrips = newTrips
        self.lastTrip = lastTrip
        self.follow = follow
        self.ledger = ledger
        self.quietWeekend = quietWeekend
    }

    public func hasTrip(on date: Date, calendar: Calendar) -> Bool {
        tripDays.contains(AutoClock.dayKey(date, calendar: calendar))
    }
}

/// What the rules remember between checks (UserDefaults `rules.ledger.v1`): the milestones each rule reached per ticket,
/// the follow it reported, its last firing (cooldown) and the newest trip it has seen.
public struct AutoLedger: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// "<rule id>|<ticket id>" → percents already celebrated (or reached before the rule was switched on).
    public var milestones: [String: Set<Int>]
    /// rule id → the follow (trip id) whose delay it reported and that has not dropped below the threshold since.
    public var followReported: [String: String]
    /// rule id → its last firing.
    public var lastFired: [String: Date]
    /// Trips saved up to this moment have been checked („Fahrt erfasst“).
    public var tripWatermark: Date?

    public init(milestones: [String: Set<Int>] = [:], followReported: [String: String] = [:], lastFired: [String: Date] = [:],
                tripWatermark: Date? = nil) {
        version = AutoLedger.currentVersion
        self.milestones = milestones
        self.followReported = followReported
        self.lastFired = lastFired
        self.tripWatermark = tripWatermark
    }

    public static func milestoneKey(ruleID: UUID, ticketID: String) -> String { "\(ruleID.uuidString)|\(ticketID)" }

    public func celebrated(ruleID: UUID, ticketID: String) -> Set<Int> {
        milestones[AutoLedger.milestoneKey(ruleID: ruleID, ticketID: ticketID)] ?? []
    }

    /// A rule that is switched on remembers what is reached already, so it celebrates what comes next, not the past.
    public mutating func seedMilestones(rule: AutoRule, ticket: AutoTicketFact?) {
        guard case let .milestone(percents) = rule.trigger.normalized, let ticket else { return }
        let reached = percents.filter { ticket.amortizedFraction * 100 + 1e-9 >= Double($0) }
        let key = AutoLedger.milestoneKey(ruleID: rule.id, ticketID: ticket.id)
        milestones[key, default: []].formUnion(reached)
    }

    /// Applies the changes of a verdict (after its firings were delivered).
    public mutating func apply(_ marks: [AutoMark]) {
        for mark in marks {
            switch mark {
            case let .milestones(ruleID, ticketID, percents):
                milestones[AutoLedger.milestoneKey(ruleID: ruleID, ticketID: ticketID), default: []].formUnion(percents)
            case let .followReported(ruleID, tripID):
                followReported[ruleID.uuidString] = tripID
            case let .followRecovered(ruleID):
                followReported[ruleID.uuidString] = nil
            case let .fired(ruleID, at):
                lastFired[ruleID.uuidString] = at
            }
        }
    }

    /// Forgets everything of rules that no longer exist.
    public mutating func prune(keeping ruleIDs: Set<UUID>) {
        let ids = Set(ruleIDs.map(\.uuidString))
        milestones = milestones.filter { key, _ in ids.contains(String(key.prefix { $0 != "|" })) }
        followReported = followReported.filter { ids.contains($0.key) }
        lastFired = lastFired.filter { ids.contains($0.key) }
    }

    public static func decode(_ data: Data?) -> AutoLedger {
        guard let data, let ledger = try? JSONDecoder().decode(AutoLedger.self, from: data) else { return AutoLedger() }
        return ledger
    }

    private enum CodingKeys: String, CodingKey { case version, milestones, followReported, lastFired, tripWatermark }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? AutoLedger.currentVersion
        let raw = (try? c.decode([String: [Int]].self, forKey: .milestones)) ?? [:]
        milestones = raw.mapValues(Set.init)
        followReported = (try? c.decode([String: String].self, forKey: .followReported)) ?? [:]
        lastFired = (try? c.decode([String: Date].self, forKey: .lastFired)) ?? [:]
        tripWatermark = try? c.decodeIfPresent(Date.self, forKey: .tripWatermark)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(AutoLedger.currentVersion, forKey: .version)
        try c.encode(milestones.mapValues { $0.sorted() }, forKey: .milestones)
        try c.encode(followReported, forKey: .followReported)
        try c.encode(lastFired, forKey: .lastFired)
        try c.encodeIfPresent(tripWatermark, forKey: .tripWatermark)
    }
}

/// A change to the ledger that a verdict asks for. Applied only once the firing was delivered (the Testlauf applies nothing).
public enum AutoMark: Hashable, Sendable {
    case milestones(ruleID: UUID, ticketID: String, percents: Set<Int>)
    case followReported(ruleID: UUID, tripID: String)
    case followRecovered(ruleID: UUID)
    case fired(ruleID: UUID, at: Date)
}

/// One line of „Zuletzt ausgelöst“.
public struct AutoLogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Channel: String, Codable, Sendable, Hashable {
        /// Shown in the open app (toast and haptic).
        case inApp
        /// Sent as a local notification right away (the app was in the background, e.g. a follow answer).
        case notification
        /// A notice planned in advance that iOS delivered.
        case delivered
        /// A planned notice taken back: the day got a trip, or the rule changed.
        case cancelled
    }

    public var id: String
    public var ruleID: UUID
    public var ruleName: String
    public var at: Date
    public var title: String
    public var detail: String
    public var channel: Channel

    public init(id: String, ruleID: UUID, ruleName: String, at: Date, title: String, detail: String, channel: Channel) {
        self.id = id
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.at = at
        self.title = title
        self.detail = detail
        self.channel = channel
    }
}

/// The newest 30 entries (UserDefaults `rules.log.v1`), newest first, each id once. Kept on this device only.
public struct AutoLog: Codable, Hashable, Sendable {
    public static let limit = 30
    public static let currentVersion = 1

    public private(set) var entries: [AutoLogEntry]

    public init(entries: [AutoLogEntry] = []) {
        self.entries = AutoLog.normalized(entries)
    }

    /// Adds an entry unless its id is known (the first record wins). Returns whether it was added.
    @discardableResult
    public mutating func record(_ entry: AutoLogEntry) -> Bool {
        guard !entries.contains(where: { $0.id == entry.id }) else { return false }
        entries = AutoLog.normalized(entries + [entry])
        return true
    }

    public func contains(id: String) -> Bool { entries.contains { $0.id == id } }

    public mutating func clear() { entries = [] }

    static func normalized(_ entries: [AutoLogEntry]) -> [AutoLogEntry] {
        var seen = Set<String>()
        let sorted = entries.sorted { a, b in a.at != b.at ? a.at > b.at : a.id < b.id }
        var out: [AutoLogEntry] = []
        for entry in sorted where seen.insert(entry.id).inserted {
            out.append(entry)
            if out.count == limit { break }
        }
        return out
    }

    public static func decode(_ data: Data?) -> AutoLog {
        guard let data, let log = try? JSONDecoder().decode(AutoLog.self, from: data) else { return AutoLog() }
        return log
    }

    private enum CodingKeys: String, CodingKey { case version, entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode([AutoLossy<AutoLogEntry>].self, forKey: .entries)) ?? []
        entries = AutoLog.normalized(raw.compactMap(\.value))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(AutoLog.currentVersion, forKey: .version)
        try c.encode(entries, forKey: .entries)
    }
}
