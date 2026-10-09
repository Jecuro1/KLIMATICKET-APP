import Foundation

// "Reise mit Etappen" (docs/JOURNEYS.md): Bus → Zug → Bim logged as ONE journey. Every leg stays a trip of its own –
// own stations, mode, price, distance, CO₂ – and the legs share a `journeyID` (`legIndex` = travel order). Sums (value,
// km, CO₂, per-mode figures) add up the legs; counts of "Fahrten" count a journey once (`TripRecord.tripKey`).

public extension TripRecord {
    /// The "Fahrt" this record belongs to: its journey, or itself. Counts of trips count distinct keys.
    var tripKey: UUID { journeyID ?? id }

    /// Part of a multi-leg journey.
    var isJourneyLeg: Bool { journeyID != nil }
}

/// One leg of a favourite journey ("Kombi-Vorlage"), as stored in `FavoriteRouteEntity.legsRaw` (`JourneyLegCodec`).
public struct JourneyLeg: Codable, Hashable, Sendable {
    public var fromName: String
    public var fromStationID: String?
    public var toName: String
    public var toStationID: String?
    /// `TransportMode` raw value (unknown modes read as `.other`).
    public var modeRaw: String
    /// One direction, km.
    public var distanceKm: Double
    /// Regular fare of this leg for one direction, EUR.
    public var fareEUR: Double
    /// Via stations of this leg (`TripViaCodec` text, "" = direct).
    public var viaRaw: String
    /// Federal states the leg touches (comma separated, as `TripEntity.statesRaw`).
    public var statesRaw: String

    public init(fromName: String, fromStationID: String? = nil, toName: String, toStationID: String? = nil,
                mode: TransportMode, distanceKm: Double, fareEUR: Double, viaRaw: String = "", statesRaw: String = "") {
        self.fromName = fromName
        self.fromStationID = fromStationID
        self.toName = toName
        self.toStationID = toStationID
        self.modeRaw = mode.rawValue
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.viaRaw = viaRaw
        self.statesRaw = statesRaw
    }

    public var mode: TransportMode { TransportMode(rawValue: modeRaw) ?? .other }
    public var via: [TripVia] { TripViaCodec.decode(viaRaw) }

    /// At most this many legs per journey (Bus → Zug → Zug → Bim … – longer chains are several journeys).
    public static let maxCount = 6

    private enum CodingKeys: String, CodingKey {
        case fromName = "f", fromStationID = "fi", toName = "t", toStationID = "ti", modeRaw = "m", distanceKm = "km"
        case fareEUR = "eur", viaRaw = "v", statesRaw = "s"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? ""
        fromStationID = (try? c.decodeIfPresent(String.self, forKey: .fromStationID)).flatMap { $0.isEmpty ? nil : $0 }
        toName = (try? c.decodeIfPresent(String.self, forKey: .toName)) ?? ""
        toStationID = (try? c.decodeIfPresent(String.self, forKey: .toStationID)).flatMap { $0.isEmpty ? nil : $0 }
        modeRaw = (try? c.decodeIfPresent(String.self, forKey: .modeRaw)) ?? TransportMode.other.rawValue
        let km = (try? c.decodeIfPresent(Double.self, forKey: .distanceKm)) ?? 0
        distanceKm = km.isFinite ? max(0, km) : 0
        let fare = (try? c.decodeIfPresent(Double.self, forKey: .fareEUR)) ?? 0
        fareEUR = fare.isFinite ? max(0, fare) : 0
        viaRaw = (try? c.decodeIfPresent(String.self, forKey: .viaRaw)) ?? ""
        statesRaw = (try? c.decodeIfPresent(String.self, forKey: .statesRaw)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fromName, forKey: .fromName)
        try c.encodeIfPresent(fromStationID, forKey: .fromStationID)
        try c.encode(toName, forKey: .toName)
        try c.encodeIfPresent(toStationID, forKey: .toStationID)
        try c.encode(modeRaw, forKey: .modeRaw)
        try c.encode((distanceKm * 10).rounded() / 10, forKey: .distanceKm)
        try c.encode((fareEUR * 100).rounded() / 100, forKey: .fareEUR)
        if !viaRaw.isEmpty { try c.encode(viaRaw, forKey: .viaRaw) }
        if !statesRaw.isEmpty { try c.encode(statesRaw, forKey: .statesRaw) }
    }
}

/// Stable text encoding of a favourite's legs (`FavoriteRouteEntity.legsRaw`, sync `legs`, backup): a compact JSON array
/// with short keys (`f`/`fi`/`t`/`ti`/`m`/`km`/`eur`/`v`/`s`), "" = an ordinary single-leg favourite. Decoding ignores unknown
/// keys and malformed text (→ no legs), drops legs without names and caps at `JourneyLeg.maxCount`; one leg alone is no
/// journey (→ none).
public enum JourneyLegCodec {
    public static func encode(_ legs: [JourneyLeg]) -> String {
        let clean = sanitized(legs)
        guard clean.count > 1 else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(clean) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ raw: String) -> [JourneyLeg] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let legs = try? JSONDecoder().decode([JourneyLeg].self, from: data) else { return [] }
        let clean = sanitized(legs)
        return clean.count > 1 ? clean : []
    }

    static func sanitized(_ legs: [JourneyLeg]) -> [JourneyLeg] {
        Array(legs.filter {
            !$0.fromName.trimmingCharacters(in: .whitespaces).isEmpty && !$0.toName.trimmingCharacters(in: .whitespaces).isEmpty
        }.prefix(JourneyLeg.maxCount))
    }
}

public enum JourneySummary {
    /// The mode that carries a journey (most km, then highest fare, then travel order) – icon and filters of the whole
    /// journey, and what an older app shows for a combo favourite.
    public static func mainMode(_ legs: [(mode: TransportMode, distanceKm: Double, fareEUR: Double)]) -> TransportMode? {
        var best: (index: Int, leg: (mode: TransportMode, distanceKm: Double, fareEUR: Double))?
        for (index, leg) in legs.enumerated() {
            guard let current = best else { best = (index, leg); continue }
            if leg.distanceKm > current.leg.distanceKm + 0.05
                || (abs(leg.distanceKm - current.leg.distanceKm) <= 0.05 && leg.fareEUR > current.leg.fareEUR + 0.005) {
                best = (index, leg)
            }
        }
        return best?.leg.mode
    }

    /// Number of distinct "Fahrten" (a journey counts once).
    public static func tripCount(_ trips: [TripRecord]) -> Int {
        var keys = Set<UUID>()
        var plain = 0
        for trip in trips {
            if let journey = trip.journeyID { keys.insert(journey) } else { plain += 1 }
        }
        return plain + keys.count
    }

    /// One record per journey (start of the first leg → end of the last, values and km summed, the main mode, the stops in
    /// between as vias, at most `TripVia.maxCount`) – routes and records ("längste Fahrt") are about journeys; legs are
    /// kept as they are. Order: as given, a journey at its first leg.
    public static func collapsed(_ trips: [TripRecord]) -> [TripRecord] {
        var order: [UUID] = []
        var groups: [UUID: [TripRecord]] = [:]
        for trip in trips {
            let key = trip.tripKey
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(trip)
        }
        return order.compactMap { key in
            guard let legs = groups[key]?.sorted(by: { ($0.legIndex, $0.date) < ($1.legIndex, $1.date) }), let first = legs.first,
                  let last = legs.last else { return nil }
            guard legs.count > 1 else { return first }
            let isRoundTrip = legs.allSatisfy(\.isRoundTrip)
            let fare = legs.reduce(0) { $0 + (isRoundTrip ? $1.fareEUR : $1.totalValue) }
            let km = legs.reduce(0) { $0 + (isRoundTrip ? $1.distanceKm : $1.totalDistanceKm) }
            let mode = mainMode(legs.map { ($0.mode, $0.distanceKm, $0.fareEUR) }) ?? first.mode
            let transfers = legs.dropLast().map { TripVia(name: $0.toName, stationID: $0.toStationID) }
            var record = TripRecord(id: key, date: first.date, fromName: first.fromName, toName: last.toName,
                                    fromStationID: first.fromStationID, toStationID: last.toStationID, mode: mode,
                                    distanceKm: km, fareEUR: fare, isRoundTrip: isRoundTrip, companions: first.companions,
                                    states: legs.reduce(into: Set<String>()) { $0.formUnion($1.states) },
                                    category: first.category, isInduced: legs.contains(where: \.isInduced),
                                    via: TripViaCodec.sanitized(transfers))
            record.journeyID = first.journeyID
            return record
        }
    }
}
