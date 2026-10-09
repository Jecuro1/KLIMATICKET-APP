import Foundation

/// Fast, diacritic-insensitive station search over the bundled station list.
public final class StationIndex: @unchecked Sendable {
    public let stations: [Station]
    private let byID: [String: Station]
    private let keys: [String]
    private let tokens: [[String]]

    public init(stations: [Station]) {
        self.stations = stations
        var map: [String: Station] = [:]
        for s in stations { map[s.id] = s }
        byID = map
        keys = stations.map { StationIndex.normalize($0.name) }
        tokens = keys.map { $0.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init) }
    }

    /// Decodes the bundled `stations.json` array.
    public convenience init(jsonData: Data) throws {
        let stations = try JSONDecoder().decode([Station].self, from: jsonData)
        self.init(stations: stations)
    }

    public func station(id: String) -> Station? { byID[id] }

    /// Exact (normalized) name lookup.
    public func station(named name: String) -> Station? {
        let key = StationIndex.normalize(name)
        guard let i = keys.firstIndex(of: key) else { return nil }
        return stations[i]
    }

    /// Ranked search. Empty query returns the most important stations (optionally nearest to `near`).
    public func search(_ query: String, limit: Int = 30, near: GeoPoint? = nil) -> [Station] {
        let q = StationIndex.normalize(query)
        if q.isEmpty {
            let ranked = stations.enumerated().sorted { lhs, rhs in
                rankEmpty(lhs.element, near: near) > rankEmpty(rhs.element, near: near)
            }
            return ranked.prefix(limit).map(\.element)
        }
        let qTokens = q.split(separator: " ").map(String.init)
        var scored: [(Int, Double)] = []
        scored.reserveCapacity(64)
        for i in stations.indices {
            guard let base = score(index: i, query: q, queryTokens: qTokens) else { continue }
            var s = base + Double(stations[i].importance) * 0.15
            if let near {
                let d = near.distanceKm(to: stations[i].location)
                s += max(0, 12 - d / 10)
            }
            scored.append((i, s))
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(limit).map { stations[$0.0] }
    }

    /// Nearest stations to a coordinate.
    public func nearest(to point: GeoPoint, limit: Int = 5, maxKm: Double = 25) -> [(station: Station, distanceKm: Double)] {
        stations
            .map { ($0, point.distanceKm(to: $0.location)) }
            .filter { $0.1 <= maxKm }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (station: $0.0, distanceKm: $0.1) }
    }

    private func rankEmpty(_ s: Station, near: GeoPoint?) -> Double {
        var r = Double(s.importance)
        if let near { r += max(0, 60 - near.distanceKm(to: s.location)) }
        return r
    }

    private func score(index i: Int, query q: String, queryTokens: [String]) -> Double? {
        let key = keys[i]
        if key == q { return 120 }
        if key.hasPrefix(q) { return 100 - Double(key.count - q.count) * 0.2 }
        let words = tokens[i]
        // Every query token must prefix-match some word.
        var allMatch = true
        var firstWordBonus = 0.0
        for (n, t) in queryTokens.enumerated() {
            if let idx = words.firstIndex(where: { $0.hasPrefix(t) }) {
                if n == 0 && idx == 0 { firstWordBonus = 10 }
            } else {
                allMatch = false
                break
            }
        }
        if allMatch { return 70 + firstWordBonus }
        if key.contains(q) { return 50 }
        // Typo tolerance for longer queries.
        if q.count >= 4 {
            for w in words where abs(w.count - q.count) <= 2 {
                if StationIndex.levenshtein(String(w.prefix(q.count + 1)), q, limit: q.count >= 7 ? 2 : 1) != nil {
                    return 30
                }
            }
        }
        return nil
    }

    /// Lowercases, strips diacritics, expands common abbreviations ("hbf" ↔ "hauptbahnhof", "st." → "st").
    public static func normalize(_ s: String) -> String {
        var out = s.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
        out = out.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_AT"))
        out = out.replacingOccurrences(of: "hauptbahnhof", with: "hbf")
            .replacingOccurrences(of: "bahnhof", with: "bf")
            .replacingOccurrences(of: "sankt ", with: "st ")
            .replacingOccurrences(of: "st.", with: "st ")
        let allowed = out.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(allowed).split(separator: " ").joined(separator: " ")
    }

    /// Bounded Levenshtein distance; returns nil when it exceeds `limit`.
    static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int? {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return nil }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return nil }
            swap(&prev, &cur)
        }
        let d = prev[b.count]
        return d <= limit ? d : nil
    }
}
