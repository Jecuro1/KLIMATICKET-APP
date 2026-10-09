import Foundation

// "Unterwegs" – a ride that is tracked live (Live Activity on the Lock Screen and in the Dynamic Island) and saved
// as a trip when it ends. Pure value types and rules, shared by the app, the widget extension and the tests.
// ActivityKit / App Intents glue lives in Shared/RideActivityAttributes.swift and App/Sources/Features/LiveActivity/.

// MARK: - Trip payload

/// Everything needed to save a ride as a trip once it ends – the trip editor's form or a favourite route.
public struct RideTrip: Codable, Hashable, Sendable {
    public var fromName: String
    public var toName: String
    public var fromStationID: String?
    public var toStationID: String?
    public var mode: TransportMode
    /// One direction, km.
    public var distanceKm: Double
    /// Regular fare for one direction and one person, EUR.
    public var fareEUR: Double
    public var isFareManual: Bool
    public var isRoundTrip: Bool
    public var travelClass: TravelClass
    public var companions: Int
    public var states: [String]
    public var note: String
    public var category: TripCategory?
    public var isInduced: Bool
    /// Started from a favourite: the app logs it like a quick log (current fare, category and usage count of the favourite).
    public var favoriteID: UUID?

    public init(fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil,
                mode: TransportMode, distanceKm: Double, fareEUR: Double, isFareManual: Bool = false, isRoundTrip: Bool = false,
                travelClass: TravelClass = .second, companions: Int = 0, states: [String] = [], note: String = "",
                category: TripCategory? = nil, isInduced: Bool = false, favoriteID: UUID? = nil) {
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.mode = mode
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.isFareManual = isFareManual
        self.isRoundTrip = isRoundTrip
        self.travelClass = travelClass
        self.companions = companions
        self.states = states
        self.note = note
        self.category = category
        self.isInduced = isInduced
        self.favoriteID = favoriteID
    }

    /// Value of the whole ride (both directions for a round trip), EUR.
    public var totalValue: Double {
        guard fareEUR.isFinite, fareEUR > 0 else { return 0 }
        return fareEUR * (isRoundTrip ? 2 : 1)
    }

    public var totalDistanceKm: Double {
        guard distanceKm.isFinite, distanceKm > 0 else { return 0 }
        return distanceKm * (isRoundTrip ? 2 : 1)
    }

    /// A ride can only be started (and saved) with two different named endpoints and a price.
    public var isValid: Bool {
        let from = fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !from.isEmpty && !to.isEmpty && from != to && totalValue > 0
    }

    // Tolerant decoding: records written by an older or newer build (App Group) must never be lost.
    private enum CodingKeys: String, CodingKey {
        case fromName, toName, fromStationID, toStationID, mode, distanceKm, fareEUR, isFareManual, isRoundTrip
        case travelClass, companions, states, note, category, isInduced, favoriteID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromName = try c.decodeIfPresent(String.self, forKey: .fromName) ?? ""
        toName = try c.decodeIfPresent(String.self, forKey: .toName) ?? ""
        fromStationID = try c.decodeIfPresent(String.self, forKey: .fromStationID)
        toStationID = try c.decodeIfPresent(String.self, forKey: .toStationID)
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)).flatMap(TransportMode.init(rawValue:)) ?? .other
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm) ?? 0
        fareEUR = try c.decodeIfPresent(Double.self, forKey: .fareEUR) ?? 0
        isFareManual = try c.decodeIfPresent(Bool.self, forKey: .isFareManual) ?? false
        isRoundTrip = try c.decodeIfPresent(Bool.self, forKey: .isRoundTrip) ?? false
        travelClass = (try? c.decodeIfPresent(String.self, forKey: .travelClass)).flatMap(TravelClass.init(rawValue:)) ?? .second
        companions = try c.decodeIfPresent(Int.self, forKey: .companions) ?? 0
        states = try c.decodeIfPresent([String].self, forKey: .states) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        category = (try? c.decodeIfPresent(String.self, forKey: .category)).flatMap(TripCategory.init(rawValue:))
        isInduced = try c.decodeIfPresent(Bool.self, forKey: .isInduced) ?? false
        favoriteID = try c.decodeIfPresent(UUID.self, forKey: .favoriteID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fromName, forKey: .fromName)
        try c.encode(toName, forKey: .toName)
        try c.encodeIfPresent(fromStationID, forKey: .fromStationID)
        try c.encodeIfPresent(toStationID, forKey: .toStationID)
        try c.encode(mode.rawValue, forKey: .mode)
        try c.encode(distanceKm, forKey: .distanceKm)
        try c.encode(fareEUR, forKey: .fareEUR)
        try c.encode(isFareManual, forKey: .isFareManual)
        try c.encode(isRoundTrip, forKey: .isRoundTrip)
        try c.encode(travelClass.rawValue, forKey: .travelClass)
        try c.encode(companions, forKey: .companions)
        try c.encode(states, forKey: .states)
        try c.encode(note, forKey: .note)
        try c.encodeIfPresent(category?.rawValue, forKey: .category)
        try c.encode(isInduced, forKey: .isInduced)
        try c.encodeIfPresent(favoriteID, forKey: .favoriteID)
    }
}

// MARK: - Payoff

/// Amortisation of the active ticket before and after a ride – the "73 % → 77 %" of the Live Activity.
/// Fractions of the price the payoff is measured against (the holder's own share), not clamped (> 1 = in profit).
public struct RidePayoff: Codable, Hashable, Sendable {
    public var before: Double
    public var after: Double
    public var ticketPrice: Double

    public init(before: Double, after: Double, ticketPrice: Double) {
        self.before = before.isFinite ? max(0, before) : 0
        self.after = after.isFinite ? max(self.before, after) : self.before
        self.ticketPrice = ticketPrice.isFinite ? max(0, ticketPrice) : 0
    }

    /// From the ticket's value so far; nil without a priced ticket.
    public init?(currentValue: Double, ticketPrice: Double, rideValue: Double) {
        guard ticketPrice.isFinite, ticketPrice > 0 else { return nil }
        let current = currentValue.isFinite ? max(0, currentValue) : 0
        let ride = rideValue.isFinite ? max(0, rideValue) : 0
        self.init(before: current / ticketPrice, after: (current + ride) / ticketPrice, ticketPrice: ticketPrice)
    }

    /// The same ride on top of a changed ticket total (another trip was logged meanwhile).
    public func rebased(currentValue: Double, rideValue: Double) -> RidePayoff {
        RidePayoff(currentValue: currentValue, ticketPrice: ticketPrice, rideValue: rideValue) ?? self
    }

    /// Gain in fraction points (0.038 = 3,8 Prozentpunkte).
    public var delta: Double { max(0, after - before) }
    /// This ride crosses the summit (break-even).
    public var reachesSummit: Bool { before < 1 && after >= 1 }
    /// The ticket had already paid off – the whole ride is profit.
    public var isPaidOffBefore: Bool { before >= 1 }
    public var isPaidOffAfter: Bool { after >= 1 }
    /// Profit after the ride (≤ 0 while below the summit), EUR.
    public var profitAfter: Double { (after - 1) * ticketPrice }
    /// Still missing to break-even after the ride, EUR.
    public var remainingAfter: Double { max(0, (1 - after) * ticketPrice) }

    /// Whole percent as shown everywhere in the app ("75 %"); never 100 before the summit is actually reached.
    public static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        var value = (max(0, fraction) * 100).rounded()
        if fraction < 1, value >= 100 { value = 99 }
        return Int(value)
    }

    public var percentBefore: Int { Self.percent(before) }
    public var percentAfter: Int { Self.percent(after) }

    /// True when "73 % → 73 %" would hide a real gain – the labels then need one decimal ("73,2 % → 73,6 %").
    public var needsDecimals: Bool { delta > 0 && percentBefore == percentAfter }
}

// MARK: - Live state

public enum RidePhase: String, Codable, Sendable, CaseIterable {
    /// Unterwegs.
    case riding
    /// Arrived (rides tracked with timetable data) – waiting for "Fahrt speichern".
    case arrived
    /// Saved as a trip (end state).
    case saved
    /// Ended without saving (end state).
    case ended

    /// End states show no buttons any more.
    public var isFinal: Bool { self == .saved || self == .ended }

    /// Tolerant decoding (a newer build might add phases).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RidePhase(rawValue: raw) ?? .riding
    }
}

/// Optional live line for rides followed with timetable data (ÖBB planner): "RJX 662 · pünktlich · Gl. 3".
public struct RideStatusLine: Codable, Hashable, Sendable {
    public enum Tone: String, Codable, Sendable {
        case neutral, onTime, delayed, disrupted

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Tone(rawValue: raw) ?? .neutral
        }
    }

    public var text: String
    public var tone: Tone

    public init(text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

// MARK: - Persisted ride

/// A running ride, persisted in the App Group so that it survives app restarts and can be saved from the Live Activity.
public struct RideRecord: Codable, Hashable, Sendable, Identifiable {
    /// Ride id – also used as the id of the saved trip (saving twice never creates a duplicate).
    public var id: UUID
    /// ActivityKit activity id (nil until the activity was requested).
    public var activityID: String?
    public var trip: RideTrip
    public var startedAt: Date
    public var payoff: RidePayoff?
    /// "RJX 662" when known (live planner).
    public var lineLabel: String?
    public var ticketName: String

    public init(id: UUID = UUID(), activityID: String? = nil, trip: RideTrip, startedAt: Date, payoff: RidePayoff? = nil,
                lineLabel: String? = nil, ticketName: String = "") {
        self.id = id
        self.activityID = activityID
        self.trip = trip
        self.startedAt = startedAt
        self.payoff = payoff
        self.lineLabel = lineLabel
        self.ticketName = ticketName
    }
}

// MARK: - Rules

public enum RidePolicy {
    /// A ride ends automatically after 8 hours – also the system limit for an active Live Activity.
    public static let maxDuration: TimeInterval = 8 * 60 * 60
    /// How long the "Gespeichert" end state stays on the Lock Screen.
    public static let savedDismissal: TimeInterval = 10 * 60

    /// When the Live Activity turns stale ("Fahrt noch speichern?").
    public static func staleDate(for start: Date) -> Date { start.addingTimeInterval(maxDuration) }

    public static func isOverdue(startedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= maxDuration
    }
}

/// Decides what to do with rides and activities when the app comes to the foreground.
public enum RideReconciler {
    public enum ActivityStatus: String, Sendable {
        case pending, active, stale, ended, dismissed

        /// Still shown and updatable (not ended by anyone yet).
        public var isRunning: Bool { self == .pending || self == .active || self == .stale }
    }

    /// What the app sees of one of its Live Activities.
    public struct LiveActivity: Hashable, Sendable {
        public var activityID: String
        public var rideID: UUID?
        public var status: ActivityStatus

        public init(activityID: String, rideID: UUID?, status: ActivityStatus) {
            self.activityID = activityID
            self.rideID = rideID
            self.status = status
        }
    }

    public struct Plan: Equatable, Sendable {
        /// Activities to end now and dismiss immediately (overdue rides, rides waiting for a decision, orphans).
        public var endActivityIDs: [String] = []
        /// Rides that ended without "Fahrt speichern" / "Beenden" (swiped away, ended by the system, overdue) –
        /// the app asks whether to save them. Oldest first.
        public var needsDecision: [UUID] = []
        /// Rides that are still running.
        public var running: [UUID] = []

        public init(endActivityIDs: [String] = [], needsDecision: [UUID] = [], running: [UUID] = []) {
            self.endActivityIDs = endActivityIDs
            self.needsDecision = needsDecision
            self.running = running
        }
    }

    public static func plan(records: [RideRecord], activities: [LiveActivity], now: Date) -> Plan {
        var plan = Plan()
        var claimed = Set<String>()
        for record in records.sorted(by: { $0.startedAt < $1.startedAt }) {
            let match = activities.first { $0.rideID == record.id }
                ?? record.activityID.flatMap { id in activities.first { $0.activityID == id } }
            if let match { claimed.insert(match.activityID) }
            guard let match, match.status.isRunning else {
                // Gone (swiped away) or ended by the system: still visible end states are cleared, the ride needs a decision.
                if let match, match.status == .ended { plan.endActivityIDs.append(match.activityID) }
                plan.needsDecision.append(record.id)
                continue
            }
            if RidePolicy.isOverdue(startedAt: record.startedAt, now: now) {
                plan.endActivityIDs.append(match.activityID)
                plan.needsDecision.append(record.id)
            } else {
                plan.running.append(record.id)
            }
        }
        // Running activities without a ride (e.g. data wiped) cannot be saved any more. Ended ones are left alone:
        // that is the "Gespeichert" confirmation of a ride the intent already handed over.
        for activity in activities where !claimed.contains(activity.activityID) && activity.status.isRunning {
            plan.endActivityIDs.append(activity.activityID)
        }
        return plan
    }
}

// MARK: - Mini summit data

public enum RideClimb {
    /// Down-samples the ticket's cumulative value series to at most `maxPoints` fractions of the ticket price, keeping the
    /// first and the last point (the value right now). Used for the mini summit of the Live Activity (attributes are capped at 4 KB).
    public static func fractions(cumulative values: [Double], ticketPrice: Double, maxPoints: Int = 16) -> [Double] {
        guard ticketPrice.isFinite, ticketPrice > 0, maxPoints >= 2 else { return [] }
        let clean = values.map { $0.isFinite ? max(0, $0) / ticketPrice : 0 }
        guard clean.count > maxPoints else { return clean.map(round3) }
        let step = Double(clean.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { i in
            let index = i == maxPoints - 1 ? clean.count - 1 : Int((Double(i) * step).rounded())
            return round3(clean[min(index, clean.count - 1)])
        }
    }

    private static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

// MARK: - Names

public enum RideNames {
    /// Short station names for the tight Live Activity layouts: "Innsbruck Hauptbahnhof" → "Innsbruck Hbf",
    /// "St. Anton am Arlberg" → "St. Anton" (same rules as the app's trip rows).
    public static func short(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Hauptbahnhof", with: "Hbf")
        for suffix in [" am Arlberg", " im Pongau", " an der Donau", " in Tirol"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
        }
        return n
    }

    /// "St. Anton → Innsbruck Hbf" / "St. Anton ⇄ Innsbruck Hbf" (round trip).
    public static func route(from: String, to: String, roundTrip: Bool) -> String {
        "\(short(from)) \(roundTrip ? "⇄" : "→") \(short(to))"
    }
}
