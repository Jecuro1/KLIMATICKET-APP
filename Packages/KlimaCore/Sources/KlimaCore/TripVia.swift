import Foundation

/// A via station ("Über …", Zwischenhalt) of a logged trip or favourite, in travel order (docs/VIA.md).
/// Same limit as the live planner's `JourneyQuery.via` (`JourneyQuery.maxViaStops`).
public struct TripVia: Hashable, Codable, Sendable {
    /// Station / stop name as shown ("Feldkirch").
    public var name: String
    /// Bundled station or place id ("at:48:817"); nil for a name without a known station (CSV import).
    public var stationID: String?

    public init(name: String, stationID: String? = nil) {
        self.name = name
        self.stationID = stationID
    }

    public init(_ station: Station) {
        self.init(name: station.name, stationID: station.id)
    }

    /// At most this many via stops per trip or favourite (owner requirement, shared with the live planner).
    public static let maxCount = JourneyQuery.maxViaStops
}

/// Stable text encoding of a via list for SwiftData (`TripEntity.viaRaw`, `FavoriteRouteEntity.viaRaw`), the sync DTOs
/// (`via`) and the backup (docs/VIA.md §1):
///
///     "<stationID>\t<name>\n<stationID>\t<name>"      e.g. "at:48:817\tFeldkirch"
///
/// One line per via in travel order, fields separated by a tab; an unknown station leaves the id empty ("\tLech").
/// "" = direct route (the default every old row has). Decoders read field 0 and 1 and ignore further fields, so a later
/// version may append e.g. a dwell time without breaking older apps. Tabs and line breaks inside names become spaces.
public enum TripViaCodec {
    public static func encode(_ vias: [TripVia]) -> String {
        sanitized(vias).map { via in
            clean(via.stationID ?? "") + "\t" + clean(via.name)
        }
        .joined(separator: "\n")
    }

    public static func decode(_ raw: String) -> [TripVia] {
        guard !raw.isEmpty else { return [] }
        let vias = raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).compactMap { line -> TripVia? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count == 1 {
                // A bare name (hand-written backup, older experiments).
                let name = fields[0].trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : TripVia(name: name)
            }
            let id = fields[0].trimmingCharacters(in: .whitespaces)
            let name = fields[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return TripVia(name: name, stationID: id.isEmpty ? nil : id)
        }
        return sanitized(vias)
    }

    /// At most `TripVia.maxCount`, no empty names, no stop listed twice in a row.
    public static func sanitized(_ vias: [TripVia]) -> [TripVia] {
        var out: [TripVia] = []
        for via in vias {
            let name = via.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let item = TripVia(name: name, stationID: via.stationID.flatMap { $0.isEmpty ? nil : $0 })
            if let last = out.last, last.isSameStop(as: item) { continue }
            out.append(item)
            if out.count == TripVia.maxCount { break }
        }
        return out
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}

public extension TripVia {
    /// Same station id, or – when either has none – the same name (case-insensitive).
    func isSameStop(as other: TripVia) -> Bool {
        if let a = stationID, let b = other.stationID { return a == b }
        return name.compare(other.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Same via stops in the same order (`isSameStop` pairwise) – a route over other vias is another route (favourites).
    static func sameStops(_ a: [TripVia], _ b: [TripVia]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.isSameStop(as: $1) }
    }

    /// Names for one line of text: "Feldkirch · Bludenz" (CSV column "Über", share text). `parseNames` reads it back.
    static func joinedNames(_ vias: [TripVia]) -> String {
        vias.map(\.name).joined(separator: " · ")
    }

    /// Reads a CSV "Über" cell: "Feldkirch · Bludenz", "Feldkirch / Bludenz", "Feldkirch > Bludenz", "Feldkirch → Bludenz",
    /// "Feldkirch | Bludenz" or one name per line. A slash only separates with spaces around it ("Linz/Donau" stays one).
    static func parseNames(_ cell: String) -> [String] {
        var text = cell
        for separator in [" / ", "·", "→", ">", "|", "\r\n", "\r"] {
            text = text.replacingOccurrences(of: separator, with: "\n")
        }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

public extension TripRecord {
    /// Every stop in travel order: start, vias, destination (names only).
    var stopNames: [String] { [fromName] + via.map(\.name) + [toName] }
}
