import Foundation

/// Fast, diacritic-insensitive station search over the bundled station list.
///
/// Façade over the full place database: once a `PlaceIndex` is attached (`attach(places:)`, e.g. from
/// `PlaceIndexLoader.whenReady`), id lookups, text search and `nearest` cover every Austrian stop (bus, tram,
/// U-Bahn, ship, cable car) while ids of the bundled stations.json keep resolving to the same entries.
public final class StationIndex: @unchecked Sendable {
    public let stations: [Station]
    private let byID: [String: Station]
    private let keys: [String]
    /// All searchable keys per station: normalized name first, then aliases.
    private let allKeys: [[String]]
    private let allTokens: [[[String]]]
    private let placeLock = NSLock()
    private var attachedPlaces: PlaceIndex?

    public init(stations: [Station]) {
        self.stations = stations
        var map: [String: Station] = [:]
        for s in stations { map[s.id] = s }
        byID = map
        keys = stations.map { StationIndex.normalize($0.name) }
        allKeys = stations.map { s in
            var k = [StationIndex.normalize(s.name)]
            for a in s.aliases ?? [] {
                let n = StationIndex.normalize(a)
                if !n.isEmpty && !k.contains(n) { k.append(n) }
            }
            return k
        }
        allTokens = allKeys.map { list in list.map { $0.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" }).map(String.init) } }
    }

    /// Decodes the bundled `stations.json` array.
    public convenience init(jsonData: Data) throws {
        let stations = try JSONDecoder().decode([Station].self, from: jsonData)
        self.init(stations: stations)
    }

    /// The attached full place index (nil until `attach(places:)`).
    public var places: PlaceIndex? {
        placeLock.lock()
        defer { placeLock.unlock() }
        return attachedPlaces
    }

    /// Routes lookups, search and `nearest` through the full place database from now on (nil detaches).
    public func attach(places: PlaceIndex?) {
        placeLock.lock()
        attachedPlaces = places
        placeLock.unlock()
    }

    /// Station by id: bundled stations.json first, then every stop of the attached place database
    /// (`at:47:1187`, `at:46:…` bus stops, …).
    public func station(id: String) -> Station? { byID[id] ?? places?.station(id: id) }

    /// Exact (normalized) name or alias lookup.
    public func station(named name: String) -> Station? {
        let key = StationIndex.normalize(name)
        if let i = keys.firstIndex(of: key) { return stations[i] }
        if let i = allKeys.firstIndex(where: { $0.contains(key) }) { return stations[i] }
        guard let places else { return nil }
        let want = PlaceNormalizer.key(name)
        return places.search(name, context: .tripLog, limit: 5)
            .first { p in ([p.name] + p.aliases).contains { PlaceNormalizer.key($0) == want } }?.station
    }

    /// Ranked search. Empty query returns the most important stations (optionally nearest to `near`).
    /// With an attached place index, non-empty queries search every stop (Scotty-like ranking, „Fahrt erfassen“ mode).
    public func search(_ query: String, limit: Int = 30, near: GeoPoint? = nil) -> [Station] {
        let q = StationIndex.normalize(query)
        if !q.isEmpty, let places {
            return places.search(query, context: PlaceSearchContext(mode: .tripLog, near: near), limit: limit).map(\.station)
        }
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

    /// Nearest stations to a coordinate (every stop when a place index is attached).
    public func nearest(to point: GeoPoint, limit: Int = 5, maxKm: Double = 25) -> [(station: Station, distanceKm: Double)] {
        if let places {
            return places.nearest(to: point, limit: limit, maxMeters: maxKm * 1000)
                .map { (station: $0.place.station, distanceKm: $0.distanceMeters / 1000) }
        }
        return stations
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
        var best: Double?
        for (n, key) in allKeys[i].enumerated() {
            if let s = score(key: key, words: allTokens[i][n], query: q, queryTokens: queryTokens) {
                let adjusted = n == 0 ? s : s - 2   // prefer the official name slightly
                best = max(best ?? adjusted, adjusted)
            }
        }
        return best
    }

    private func score(key: String, words: [String], query q: String, queryTokens: [String]) -> Double? {
        if key == q { return 120 }
        if key.hasPrefix(q) { return 100 - Double(key.count - q.count) * 0.2 }
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
        // Umlauts fold to the plain vowel on both sides ("Pölten", "Poelten", "Polten" → "polten").
        var out = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
        out = out.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_AT"))
        out = out.replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
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
