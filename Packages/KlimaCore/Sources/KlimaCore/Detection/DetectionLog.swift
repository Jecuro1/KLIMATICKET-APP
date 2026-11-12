import Foundation

/// The local "Erkennungs-Protokoll" (Einstellungen › Fahrten erkennen): why a ride was or was not proposed, so the owner can
/// judge the accuracy on the device. Station names, times and distances only – never a coordinate. Kept on the device,
/// at most 14 days and 120 entries, emptied with "Alle Standortdaten löschen".
public struct DetectionLogEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// A ride was put into the inbox.
        case proposed
        /// A movement that looked like it might be a ride and was not proposed (with the reason).
        case rejected
        /// Detected, but already entered.
        case duplicate
        /// Replaced by a longer ride (A → Hub became A → B).
        case replaced
        /// The person's decision (confirmed, dismissed, edited).
        case decision
        /// Something about the feature itself (switched on, data deleted).
        case info
    }

    public var id: UUID
    public var loggedAt: Date
    public var kind: Kind
    /// "Feldkirch → Innsbruck Hbf", "Ohne Haltestelle am Ziel".
    public var title: String
    /// Why, in one or two German sentences.
    public var detail: String
    public var tripStart: Date?
    public var tripEnd: Date?
    /// Identifies the movement, so the same one is not logged again at the next run.
    public var key: String

    public init(id: UUID = UUID(), loggedAt: Date, kind: Kind, title: String, detail: String, tripStart: Date? = nil, tripEnd: Date? = nil,
                key: String? = nil) {
        self.id = id
        self.loggedAt = loggedAt
        self.kind = kind
        self.title = title
        self.detail = detail
        self.tripStart = tripStart
        self.tripEnd = tripEnd
        self.key = key ?? "\(kind.rawValue)|\(title)|\(Int((tripStart ?? loggedAt).timeIntervalSince1970 / 60))"
    }

    // MARK: Builders

    public static func proposed(_ c: DetectedCandidate, at now: Date) -> DetectionLogEntry {
        let positives = c.rank.positives.filter { $0.code != "rules" }.map(\.text)
        let negatives = c.rank.negatives.map(\.text)
        var detail = "Vorgeschlagen (\(c.confidence.rawValue)): " + (positives.isEmpty ? "Strecke, Tempo und Halt passen" : positives.joined(separator: "; "))
        if !negatives.isEmpty { detail += " – dagegen: " + negatives.joined(separator: "; ") }
        if c.rank.carNotExcluded { detail += ". Auto nicht ausgeschlossen." }
        return DetectionLogEntry(loggedAt: now, kind: .proposed, title: route(c.from.station.name, c.to.station.name), detail: detail,
                                 tripStart: c.departure, tripEnd: c.arrival,
                                 key: "p|\(c.from.station.id)|\(c.to.station.id)|\(Int(c.departure.timeIntervalSince1970 / 300))")
    }

    public static func rejected(_ r: DetectionRejection, at now: Date) -> DetectionLogEntry {
        var title = route(r.fromName ?? "ohne Haltestelle", r.toName ?? "ohne Haltestelle")
        if r.fromName == nil && r.toName == nil { title = "Ortswechsel ohne Haltestellen" }
        var detail = r.text
        if let speed = r.averageSpeedKmh, r.straightKm >= 1, !detail.contains("km/h") {
            detail += " · \(Format1.km(r.straightKm)) km Luftlinie, Ø \(Int(speed.rounded())) km/h"
        }
        return DetectionLogEntry(loggedAt: now, kind: .rejected, title: title, detail: "Nicht vorgeschlagen: " + detail,
                                 tripStart: r.departure, tripEnd: r.arrival,
                                 key: "r|\(r.code)|\(Int(r.departure.timeIntervalSince1970 / 300))|\(title)")
    }

    public static func duplicate(_ c: DetectedCandidate, at now: Date) -> DetectionLogEntry {
        DetectionLogEntry(loggedAt: now, kind: .duplicate, title: route(c.from.station.name, c.to.station.name),
                          detail: "Nicht vorgeschlagen: diese Fahrt ist schon erfasst", tripStart: c.departure, tripEnd: c.arrival,
                          key: "d|\(c.from.station.id)|\(c.to.station.id)|\(Int(c.departure.timeIntervalSince1970 / 300))")
    }

    public static func replaced(_ c: DetectedCandidate, count: Int, at now: Date) -> DetectionLogEntry {
        DetectionLogEntry(loggedAt: now, kind: .replaced, title: route(c.from.station.name, c.to.station.name),
                          detail: count == 1 ? "Ersetzt einen kürzeren Vorschlag: der Zug fuhr weiter" : "Ersetzt \(count) kürzere Vorschläge: der Zug fuhr weiter",
                          tripStart: c.departure, tripEnd: c.arrival)
    }

    public static func decision(_ text: String, title: String, at now: Date) -> DetectionLogEntry {
        DetectionLogEntry(loggedAt: now, kind: .decision, title: title, detail: text)
    }

    public static func info(_ text: String, at now: Date) -> DetectionLogEntry {
        DetectionLogEntry(loggedAt: now, kind: .info, title: "Fahrten erkennen", detail: text)
    }

    private static func route(_ from: String, _ to: String) -> String { "\(from) → \(to)" }
}

public struct DetectionLog: Codable, Hashable, Sendable {
    public static let maxEntries = 120
    public static let maxAge: TimeInterval = 14 * 86_400

    /// Newest first.
    public private(set) var entries: [DetectionLogEntry]

    public init(entries: [DetectionLogEntry] = []) { self.entries = entries }

    /// Adds an entry (newest first) unless the same movement was logged already; trims by age and count.
    public mutating func add(_ entry: DetectionLogEntry, now: Date) {
        if entries.contains(where: { $0.key == entry.key }) { return }
        entries.insert(entry, at: 0)
        prune(now: now)
    }

    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        entries.removeAll { $0.loggedAt < cutoff }
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
    }

    public mutating func removeAll() { entries = [] }

    /// What one detector run adds to the log.
    public mutating func record(_ outcome: DetectionOutcome, duplicates: [DetectedCandidate] = [], at now: Date) {
        for rejection in outcome.rejections { add(.rejected(rejection, at: now), now: now) }
        for candidate in duplicates { add(.duplicate(candidate, at: now), now: now) }
    }

    private enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? c.decodeIfPresent([DetectionLogEntry].self, forKey: .entries)) ?? []
    }
}
