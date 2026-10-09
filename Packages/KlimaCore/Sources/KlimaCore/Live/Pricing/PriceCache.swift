import Foundation

/// Live price cache (SPEC §B6): in memory plus a JSON file (app: `Caches/Live/prices.json`), at most 500 entries with
/// LRU eviction. Holds quotes and negative results only – never tokens, sessions or errors other than the negative
/// cases (VAO `NA`, shop `noPrice`).
///
/// | Kind | Key | TTL |
/// |---|---|---|
/// | Relation quote | `rel|fromKey|toKey|yyyy-MM-dd|class|discount` | 24 h |
/// | Connection quote | `con|Journey.id|class|discount` | 24 h |
/// | Negative | `neg|provider|fromKey|toKey|yyyy-MM-dd|class` | 24 h (VAO NA) / 1 h (shop noPrice) |
/// | Negative, one planner connection | `neg|oebbShop|con|Journey.id|class` | 1 h |
///
/// `fromKey` = `stationID ?? "eva:<hafasExtId>" ?? "name:<normalized name>"`. Via stops (owner request 2026-10-09) add
/// `|via:<key>,<key>` at the end of relation, connection and negative keys. The class is part of the negative keys
/// (review 2026-10-09): a 1st-class „kein Standard-Ticket“ must not block the 2nd-class price of the same relation, and a
/// connection-level shop failure (`offerError` of one train) must not block the other trains of the day.
public struct PriceCache: Sendable {
    public static let capacity = 500
    public static let quoteTTL: TimeInterval = 24 * 3600
    public static let notAvailableTTL: TimeInterval = 24 * 3600
    public static let noPriceTTL: TimeInterval = 3600
    /// Write-behind: at most one file write per this interval.
    public static let writeInterval: TimeInterval = 5

    public struct Entry: Codable, Sendable, Hashable {
        public var quote: PriceQuote?
        /// Reason of a negative entry ("NA", "offerError", …).
        public var negative: String?
        public var storedAt: Date
        public var expiresAt: Date
        public var lastAccess: Date
    }

    struct File: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    public let fileURL: URL?
    private(set) var entries: [String: Entry] = [:]
    private(set) var isDirty = false
    private(set) var lastWrite: Date?

    /// Loads `fileURL` when present (a missing or unreadable file starts empty).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let file = try? dec.decode(File.self, from: data), file.version == 1 { entries = file.entries }
    }

    public var count: Int { entries.count }

    // MARK: - Keys

    /// `stationID ?? "eva:<hafasExtId>" ?? "name:<normalized name>"`.
    public static func endpointKey(_ e: PriceEndpoint) -> String {
        if let id = e.stationID?.nilIfEmpty { return id }
        if let ext = e.hafasExtId?.nilIfEmpty { return "eva:\(ext)" }
        return "name:\(StationIndex.normalize(e.name))"
    }

    static func viaSuffix(_ r: PriceRequest) -> String { viaSuffix(r.via) }

    static func viaSuffix(_ via: [PriceEndpoint]) -> String {
        via.isEmpty ? "" : "|via:" + via.prefix(JourneyQuery.maxViaStops).map(endpointKey).joined(separator: ",")
    }

    static func day(_ date: Date) -> String { TicketProduct.isoDay(date, calendar: .vienna) }

    public static func relationKey(_ r: PriceRequest) -> String {
        ["rel", endpointKey(r.from), endpointKey(r.to), day(r.departure), r.travelClass.rawValue, r.discount.rawValue].joined(separator: "|")
            + viaSuffix(r)
    }

    /// `via` = the request's via stops: the same journey priced with and without via stops gives different quotes
    /// (one through ticket or a segment sum vs. the direct price), so they must not share a cache entry.
    public static func connectionKey(_ journey: Journey, travelClass: TravelClass, discount: FareDiscount,
                                     via: [PriceEndpoint] = []) -> String {
        ["con", journey.id, travelClass.rawValue, discount.rawValue].joined(separator: "|") + viaSuffix(via)
    }

    public static func negativeKey(_ provider: LiveProvider, _ r: PriceRequest) -> String {
        ["neg", provider.rawValue, endpointKey(r.from), endpointKey(r.to), day(r.departure), r.travelClass.rawValue].joined(separator: "|")
            + viaSuffix(r)
    }

    /// Negative shop result of one planner connection (plan `.connection`): blocks only that train.
    public static func negativeConnectionKey(_ journey: Journey, travelClass: TravelClass) -> String {
        ["neg", LiveProvider.oebbShop.rawValue, "con", journey.id, travelClass.rawValue].joined(separator: "|")
    }

    // MARK: - Access

    /// Fresh quote for `key` (marks it recently used); nil when missing, expired or negative.
    public mutating func quote(for key: String, now: Date) -> PriceQuote? {
        guard let e = fresh(key, now: now), let q = e.quote else { return nil }
        entries[key]?.lastAccess = now
        return q
    }

    /// Reason of a fresh negative entry for `key`, else nil.
    public mutating func negative(for key: String, now: Date) -> String? {
        guard let e = fresh(key, now: now), e.quote == nil else { return nil }
        entries[key]?.lastAccess = now
        return e.negative
    }

    public mutating func insert(_ quote: PriceQuote, for key: String, ttl: TimeInterval = PriceCache.quoteTTL, now: Date) {
        entries[key] = Entry(quote: quote, negative: nil, storedAt: now, expiresAt: now.addingTimeInterval(ttl), lastAccess: now)
        didChange()
    }

    public mutating func insertNegative(_ reason: String, for key: String, ttl: TimeInterval, now: Date) {
        entries[key] = Entry(quote: nil, negative: reason, storedAt: now, expiresAt: now.addingTimeInterval(ttl), lastAccess: now)
        didChange()
    }

    /// Removes entries whose quote matches (e.g. `.table` quotes after a tariff catalog reload).
    public mutating func removeAll(where shouldRemove: (PriceQuote) -> Bool) {
        let before = entries.count
        entries = entries.filter { _, e in !(e.quote.map(shouldRemove) ?? false) }
        if entries.count != before { isDirty = true }
    }

    public mutating func removeAll() {
        if !entries.isEmpty { isDirty = true }
        entries = [:]
    }

    private mutating func fresh(_ key: String, now: Date) -> Entry? {
        guard let e = entries[key] else { return nil }
        // Expired, or stored "in the future" (clock moved backwards by more than a minute): drop it.
        guard now < e.expiresAt, now >= e.storedAt.addingTimeInterval(-60) else {
            entries[key] = nil
            isDirty = true
            return nil
        }
        return e
    }

    private mutating func didChange() {
        isDirty = true
        evict()
    }

    /// LRU: keeps the `capacity` most recently used entries.
    private mutating func evict() {
        guard entries.count > Self.capacity else { return }
        let overflow = entries.count - Self.capacity
        for key in entries.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }).prefix(overflow).map(\.key) {
            entries[key] = nil
        }
    }

    // MARK: - Persistence (write-behind)

    /// True when dirty and the last write is at least `writeInterval` ago.
    public func shouldWrite(now: Date) -> Bool {
        guard isDirty, fileURL != nil else { return false }
        guard let last = lastWrite else { return true }
        return now.timeIntervalSince(last) >= Self.writeInterval
    }

    /// Seconds until the next write is allowed (0 when it may happen now).
    public func writeDelay(now: Date) -> TimeInterval {
        guard let last = lastWrite else { return 0 }
        return max(0, Self.writeInterval - now.timeIntervalSince(last))
    }

    /// Serialized cache (sorted keys, ISO-8601 dates). Contains quotes only – no tokens or sessions.
    public func encoded() -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(File(version: 1, entries: entries))
    }

    /// Writes the file atomically when dirty (ignores the write interval). Returns true when written.
    @discardableResult
    public mutating func write(now: Date) -> Bool {
        guard isDirty, let fileURL, let data = encoded() else { return false }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return false }
        isDirty = false
        lastWrite = now
        return true
    }
}
