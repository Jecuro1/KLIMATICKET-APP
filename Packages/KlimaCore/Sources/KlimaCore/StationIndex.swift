import Foundation

/// Fast, diacritic-insensitive station search over the bundled station list.
///
/// Façade over the full place database: once a `PlaceIndex` is attached (`attach(places:)`, e.g. from
/// `PlaceIndexLoader.whenReady`), id lookups, text search and `nearest` cover every Austrian stop (bus, tram,
/// U-Bahn, ship, cable car) while ids of the bundled stations.json keep resolving to the same entries.
public final class StationIndex: @unchecked Sendable {
    public let stations: [Station]
    private let byID: [String: Station]
    /// `normalize`d official name → first station with it; aliases separately (names win, as before).
    private let nameIndex: [String: Int]
    private let aliasIndex: [String: Int]
    /// Search keys per station: official name first, then aliases (see `SearchKey`).
    private let searchKeys: [[SearchKey]]
    private let placeLock = NSLock()
    private var attachedPlaces: PlaceIndex?

    /// One searchable name in its long form ("linz hauptbahnhof"), so a half-typed word still prefix-matches
    /// ("Linz Haupt", "Wien Westbahn", "Sankt"); `shortWords` keeps the abbreviations ("hbf", "westbf", "st") per word,
    /// so typing those finds the long names too.
    private struct SearchKey {
        let text: String
        let words: [String]
        let shortWords: [String]

        init(_ name: String) {
            words = StationIndex.foldedWords(name).map(StationIndex.expanded)
            shortWords = words.map(StationIndex.abbreviated)
            text = words.joined(separator: " ")
        }
    }

    public init(stations: [Station]) {
        self.stations = stations
        var map: [String: Station] = [:]
        var names: [String: Int] = [:]
        var aliases: [String: Int] = [:]
        var keys: [[SearchKey]] = []
        keys.reserveCapacity(stations.count)
        for (i, s) in stations.enumerated() {
            map[s.id] = s
            let name = StationIndex.normalize(s.name)
            if names[name] == nil { names[name] = i }
            var seen: Set<String> = [name]
            var stationKeys = [SearchKey(s.name)]
            for alias in s.aliases ?? [] {
                let n = StationIndex.normalize(alias)
                guard !n.isEmpty, seen.insert(n).inserted else { continue }
                if aliases[n] == nil { aliases[n] = i }
                stationKeys.append(SearchKey(alias))
            }
            keys.append(stationKeys)
        }
        byID = map
        nameIndex = names
        aliasIndex = aliases
        searchKeys = keys
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
        if let i = nameIndex[key] ?? aliasIndex[key] { return stations[i] }
        guard let places else { return nil }
        let want = PlaceNormalizer.key(name)
        return places.search(name, context: .tripLog, limit: 5, enrich: false)
            .first { p in ([p.name] + p.aliases).contains { PlaceNormalizer.key($0) == want } }?.station
    }

    /// Ranked search. Empty query returns the most important stations (optionally nearest to `near`).
    /// With an attached place index, non-empty queries search every stop (Scotty-like ranking, „Fahrt erfassen“ mode).
    public func search(_ query: String, limit: Int = 30, near: GeoPoint? = nil) -> [Station] {
        let rawWords = StationIndex.foldedWords(query)
        if !rawWords.isEmpty, let places {
            return places.search(query, context: PlaceSearchContext(mode: .tripLog, near: near), limit: limit, enrich: false)
                .map(\.station)
        }
        if rawWords.isEmpty {
            // Rank once per station, not twice per comparison (a distance each time when `near` is set).
            let ranks = stations.map { rankEmpty($0, near: near) }
            return stations.indices.sorted { ranks[$0] > ranks[$1] }.prefix(limit).map { stations[$0] }
        }
        let words = rawWords.map(StationIndex.expanded)
        let q = words.joined(separator: " ")
        var scored: [(Int, Double)] = []
        scored.reserveCapacity(64)
        for i in stations.indices {
            guard let base = score(index: i, query: q, words: words, rawWords: rawWords) else { continue }
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
            return places.nearest(to: point, limit: limit, maxMeters: maxKm * 1000, enrich: false)
                .map { (station: $0.place.station, distanceKm: $0.distanceMeters / 1000) }
        }
        // Latitude band first: a station farther north or south than `maxKm` is farther than `maxKm` (the great-circle
        // distance is at least R·|Δφ|), so only the band needs a haversine. The coverage engine calls this for every stop
        // of every journey; same result as checking all stations.
        let band = maxKm / 6371.0088 * 180 / .pi * 1.001 + 1e-9
        var hits: [(Station, Double)] = []
        for s in stations where !(abs(s.location.latitude - point.latitude) > band) {
            let d = point.distanceKm(to: s.location)
            if d <= maxKm { hits.append((s, d)) }
        }
        return hits
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (station: $0.0, distanceKm: $0.1) }
    }

    private func rankEmpty(_ s: Station, near: GeoPoint?) -> Double {
        var r = Double(s.importance)
        if let near { r += max(0, 60 - near.distanceKm(to: s.location)) }
        return r
    }

    private func score(index i: Int, query q: String, words: [String], rawWords: [String]) -> Double? {
        var best: Double?
        for (n, key) in searchKeys[i].enumerated() {
            if let s = score(key: key, query: q, words: words, rawWords: rawWords) {
                let adjusted = n == 0 ? s : s - 2   // prefer the official name slightly
                best = max(best ?? adjusted, adjusted)
            }
        }
        return best
    }

    /// `words`: the query's words in long form; `rawWords`: as typed (folded), so "St" also finds "Stephansplatz".
    private func score(key: SearchKey, query q: String, words: [String], rawWords: [String]) -> Double? {
        if key.text == q { return 120 }
        if key.text.hasPrefix(q) { return 100 - Double(key.text.count - q.count) * 0.2 }
        // Every query word must prefix-match some word of the name (long or short form).
        var allMatch = true
        var firstWordBonus = 0.0
        for (n, word) in words.enumerated() {
            let raw = rawWords[n]
            let idx = key.words.indices.first { k in
                key.words[k].hasPrefix(word) || key.words[k].hasPrefix(raw) || key.shortWords[k].hasPrefix(raw)
            }
            if let idx {
                if n == 0 && idx == 0 { firstWordBonus = 10 }
            } else {
                allMatch = false
                break
            }
        }
        if allMatch { return 70 + firstWordBonus }
        if key.text.contains(q) { return 50 }
        // Typo tolerance for longer queries.
        if q.count >= 4 {
            for w in key.words where abs(w.count - q.count) <= 2 {
                if StationIndex.levenshtein(String(w.prefix(q.count + 1)), q, limit: q.count >= 7 ? 2 : 1) != nil {
                    return 30
                }
            }
        }
        return nil
    }

    /// Comparison key of a name: lowercases, strips diacritics, abbreviates ("hauptbahnhof" → "hbf", "st." → "st").
    /// Equal keys mean the same name; for search as you type see `foldedWords` / `expanded`.
    public static func normalize(_ s: String) -> String {
        // Umlauts fold to the plain vowel on both sides ("Pölten", "Poelten", "Polten" → "polten").
        var out = fold(s)
        out = out.replacingOccurrences(of: "hauptbahnhof", with: "hbf")
            .replacingOccurrences(of: "bahnhof", with: "bf")
            .replacingOccurrences(of: "sankt ", with: "st ")
            .replacingOccurrences(of: "st.", with: "st ")
        let allowed = out.unicodeScalars.map { alphanumerics.contains($0) ? Character($0) : " " }
        return String(allowed).split(separator: " ").joined(separator: " ")
    }

    /// The words of a name as typed, folded (case, "ß", diacritics, ae/oe/ue) – no abbreviation handling; every other
    /// character separates words ("St.Pölten" → ["st", "polten"]).
    static func foldedWords(_ s: String) -> [String] {
        let chars = fold(s).unicodeScalars.map { alphanumerics.contains($0) ? Character($0) : " " }
        return String(chars).split(separator: " ").map(String.init)
    }

    /// Long form of a word, so partial typing prefix-matches it: "hbf" → "hauptbahnhof", "westbf" → "westbahnhof",
    /// "st" → "sankt".
    static func expanded(_ word: String) -> String {
        switch word {
        case "hbf": return "hauptbahnhof"
        case "bf", "bhf": return "bahnhof"
        case "st": return "sankt"
        default: return word.count > 3 && word.hasSuffix("bf") ? String(word.dropLast(2)) + "bahnhof" : word
        }
    }

    /// Short form of a long word ("hauptbahnhof" → "hbf", "westbahnhof" → "westbf", "sankt" → "st").
    static func abbreviated(_ word: String) -> String {
        if word == "hauptbahnhof" { return "hbf" }
        if word == "sankt" { return "st" }
        if word.count > 7, word.hasSuffix("bahnhof") { return String(word.dropLast(7)) + "bf" }
        return word
    }

    private static func fold(_ s: String) -> String {
        var out = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
        out = out.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: deAT)
        return out.replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
    }

    private static let deAT = Locale(identifier: "de_AT")
    private static let alphanumerics = CharacterSet.alphanumerics

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
