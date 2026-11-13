import Foundation

// MARK: calendarsuggestions – what the app remembers about calendar suggestions (UserDefaults JSON, docs/CALENDAR_SUGGESTIONS.md §4).
// No event text: a dismissed, snoozed or suggested event is known only by `CalendarEventKey` (SHA-256 of its identifier and start)
// and a date; a follow-up keeps the id and name of the matched station (the app's own data), not the event's title or location.

/// SHA-256 hex of an event's identifier and start: the only trace of an event the app keeps.
public enum CalendarEventKey {
    public static func make(eventID: String, start: Date) -> String {
        let text = eventID + "|" + String(Int64(start.timeIntervalSince1970.rounded(.down)))
        return SHA256Hex.digest(Array(text.utf8))
    }
}

/// A suggested event the "Warst du gefahren?" card may ask about the day after (station id and name, the planned arrival – no
/// event text).
public struct CalendarFollowUpEntry: Codable, Hashable, Sendable {
    public var stationID: String
    public var stationName: String
    /// The arrival the card proposed (event start − buffer); its day is the event's day.
    public var arrival: Date

    public init(stationID: String, stationName: String, arrival: Date) {
        self.stationID = stationID
        self.stationName = stationName
        self.arrival = arrival
    }
}

public struct CalendarSuggestionPrefs: Codable, Equatable, Sendable {
    /// "Kalender-Vorschläge" in Einstellungen – off until the user switches it on.
    public var isEnabled = false
    /// Calendars the user ticked (EventKit `calendarIdentifier`s).
    public var calendarIDs: [String] = []
    /// The picker was confirmed once; before that only the default calendar is ticked.
    public var hasPickedCalendars = false
    /// Minutes between the arrival and the event's start (10, 20, 30 or 45).
    public var bufferMinutes = CalendarBuffer.defaultMinutes
    /// "Kein Zug": event key → the event's start. Pruned 60 days after that start.
    public var dismissed: [String: Date] = [:]
    /// "Später": event key → the card returns after this moment.
    public var snoozed: [String: Date] = [:]
    /// Shown suggestions the follow-up card may ask about (event key → station and day).
    public var followUps: [String: CalendarFollowUpEntry] = [:]

    public init() {}

    /// Entries are dropped this long after the event (spec: dismissed hashes are pruned after 60 days).
    public static let retentionDays = 60

    public mutating func dismiss(key: String, eventStart: Date) {
        dismissed[key] = eventStart
        snoozed[key] = nil
        followUps[key] = nil
    }

    public mutating func undoDismiss(key: String) { dismissed[key] = nil }

    public mutating func snooze(key: String, until: Date) { snoozed[key] = until }

    public func isHidden(key: String, now: Date) -> Bool {
        if dismissed[key] != nil { return true }
        if let until = snoozed[key], until > now { return true }
        return false
    }

    /// Drops what is older than the retention: dismissals 60 days after the event, snoozes once they ran out, follow-ups after
    /// their last day (`CalendarFollowUpPlanner.askDays`).
    public mutating func prune(now: Date, calendar: Calendar = .vienna) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        dismissed = dismissed.filter { $0.value >= cutoff }
        snoozed = snoozed.filter { $0.value > now }
        let lastAskDay = calendar.date(byAdding: .day, value: -CalendarFollowUpPlanner.askDays, to: calendar.startOfDay(for: now)) ?? cutoff
        followUps = followUps.filter { calendar.startOfDay(for: $0.value.arrival) >= lastAskDay }
    }

    // Older or newer builds may lack a key: every field falls back to its default.
    private enum CodingKeys: String, CodingKey {
        case isEnabled, calendarIDs, hasPickedCalendars, bufferMinutes, dismissed, snoozed, followUps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs) ?? []
        hasPickedCalendars = try c.decodeIfPresent(Bool.self, forKey: .hasPickedCalendars) ?? false
        bufferMinutes = CalendarBuffer.clamp(try c.decodeIfPresent(Int.self, forKey: .bufferMinutes) ?? CalendarBuffer.defaultMinutes)
        dismissed = try c.decodeIfPresent([String: Date].self, forKey: .dismissed) ?? [:]
        snoozed = try c.decodeIfPresent([String: Date].self, forKey: .snoozed) ?? [:]
        followUps = try c.decodeIfPresent([String: CalendarFollowUpEntry].self, forKey: .followUps) ?? [:]
    }
}

/// The arrival buffer: how long before the event's start the train should arrive.
public enum CalendarBuffer {
    public static let options = [10, 20, 30, 45]
    public static let defaultMinutes = 20

    public static func clamp(_ minutes: Int) -> Int { options.contains(minutes) ? minutes : defaultMinutes }

    /// Arrival = start − buffer (an absolute interval: across a DST change the event's wall-clock start stays what it is).
    public static func arrival(eventStart: Date, bufferMinutes: Int) -> Date {
        eventStart.addingTimeInterval(-Double(clamp(bufferMinutes)) * 60)
    }
}

/// "Später": the card comes back the next morning at 07:00 – or three hours before the arrival when that is earlier – but never
/// sooner than in one hour.
public enum CalendarSnooze {
    public static func until(now: Date, arrival: Date, calendar: Calendar = .vienna) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let beforeArrival = arrival.addingTimeInterval(-3 * 3600)
        return max(min(morning, beforeArrival), now.addingTimeInterval(3600))
    }
}

// MARK: - SHA-256

/// FIPS 180-4 SHA-256 in plain Swift (KlimaCore has no CryptoKit on Linux; the input here is a few dozen bytes).
enum SHA256Hex {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func digest(_ message: [UInt8]) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        let paddedCount = (message.count + 9 + 63) / 64 * 64
        var data = [UInt8](repeating: 0, count: paddedCount)
        data.replaceSubrange(0..<message.count, with: message)
        data[message.count] = 0x80
        let bitLength = UInt64(message.count) * 8
        for i in 0..<8 { data[paddedCount - 1 - i] = UInt8(truncatingIfNeeded: bitLength >> UInt64(8 * i)) }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: paddedCount, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(data[b]) << 24 | UInt32(data[b + 1]) << 16 | UInt32(data[b + 2]) << 8 | UInt32(data[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        var hex = [UInt8](repeating: 0, count: 64)
        let digits = Array("0123456789abcdef".utf8)
        for (n, word) in h.enumerated() {
            for j in 0..<8 { hex[n * 8 + j] = digits[Int((word >> UInt32(28 - 4 * j)) & 0xf)] }
        }
        return String(decoding: hex, as: UTF8.self)
    }

    @inline(__always) private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}
