import Foundation

// MARK: calendarsuggestions – from a calendar location to one station, or to nothing (docs/CALENDAR_SUGGESTIONS.md §3).
// Precision over recall: only exact names and aliases of the bundled station list count (no fuzzy search), two far-apart stations
// with the same name are ambiguous (nil), a street line alone never matches, and a town matches only through its Hauptbahnhof, a
// station named exactly like it, or – with the place database attached – the one rail station of its municipality.

/// The station list the matcher looks names up in: the bundled stations.json (rail, U-Bahn, tram hubs), optionally with the
/// municipality of each rail station from the place database.
public final class CalendarStationCatalog: @unchecked Sendable {
    public let stations: [Station]
    /// `key(name)` of every station, computed once.
    let nameKeys: [String]
    /// Normalized official name or alias → stations with it.
    private var byKey: [String: [Int]] = [:]
    /// Normalized official name → stations (no aliases): "a station named exactly like the town".
    private var byName: [String: [Int]] = [:]
    /// Town → its Hauptbahnhof ("salzburg" → Salzburg Hauptbahnhof).
    private var townHbf: [String: Int] = [:]
    /// Normalized municipality → its rail stations.
    private var municipalityRail: [String: [Int]] = [:]
    /// Stations named "<town> <part>" of a town with a Hauptbahnhof or a namesake station ("Salzburg Süd", "Bregenz Hafen").
    private var districtStations: Set<Int> = []

    /// - Parameter municipalities: station id → municipality ("Gemeinde") from the place database; empty without it.
    public init(stations: [Station], municipalities: [String: String] = [:]) {
        self.stations = stations
        nameKeys = stations.map { Self.key($0.name) }
        for (i, s) in stations.enumerated() {
            let name = nameKeys[i]
            guard !name.isEmpty else { continue }
            byKey[name, default: []].append(i)
            byName[name, default: []].append(i)
            if s.kind == .rail {
                let words = name.split(separator: " ")
                if words.count >= 2, words.last == "hbf" { townHbf[words.dropLast().joined(separator: " ")] = i }
                for alias in s.aliases ?? [] {
                    let key = Self.key(alias)
                    guard !key.isEmpty, key != name, Self.isUsableAlias(key) else { continue }
                    if !(byKey[key]?.contains(i) ?? false) { byKey[key, default: []].append(i) }
                }
                if let municipality = municipalities[s.id] {
                    let key = Self.key(municipality)
                    if !key.isEmpty { municipalityRail[key, default: []].append(i) }
                }
            }
        }
        for i in stations.indices {
            let words = nameKeys[i].split(separator: " ").map(String.init)
            guard words.count >= 2 else { continue }
            for k in 1..<words.count {
                let prefix = words[0..<k].joined(separator: " ")
                if townHbf[prefix] != nil || (byName[prefix]?.contains { stations[$0].kind == .rail } ?? false) {
                    districtStations.insert(i)
                    break
                }
            }
        }
    }

    /// The catalog of the bundled list with the municipalities the place database knows for its rail stations.
    public static func make(stations: [Station], places: PlaceIndex?) -> CalendarStationCatalog {
        var municipalities: [String: String] = [:]
        if let places {
            for s in stations where s.kind == .rail {
                if let m = places.station(id: s.id)?.municipality, !m.isEmpty { municipalities[s.id] = m }
            }
        }
        return CalendarStationCatalog(stations: stations, municipalities: municipalities)
    }

    // MARK: Lookups

    /// One station for a normalized key, or nil when there is none or two different places share it. Entries of the same place
    /// (the rail station and the U-Bahn station "Wien Hauptbahnhof", within 1,5 km) count once, the rail station first.
    func station(forKey key: String, names onlyNames: Bool = false, inTown town: String? = nil) -> Int? {
        guard var hits = (onlyNames ? byName[key] : byKey[key]), !hits.isEmpty else { return nil }
        if let town, hits.count > 1 {
            let inTown = hits.filter { nameKeys[$0].hasPrefix(town + " ") }
            if !inTown.isEmpty { hits = inTown }
        }
        let ranked = hits.sorted { a, b in
            let ra = stations[a].kind == .rail, rb = stations[b].kind == .rail
            if ra != rb { return ra }
            return stations[a].importance > stations[b].importance
        }
        let first = ranked[0]
        let samePlace = ranked.dropFirst().allSatisfy { stations[$0].location.distanceKm(to: stations[first].location) <= 1.5 }
        return samePlace ? first : nil
    }

    /// The station a town stands for: its Hauptbahnhof, else a rail station named exactly like it, else the only rail station of
    /// its municipality. nil for a town with several stations and none of these ("Lech" has none at all).
    func townStation(forKey key: String) -> (index: Int, score: Double)? {
        if let hbf = townHbf[key] { return (hbf, 0.75) }
        if let named = byName[key]?.filter({ stations[$0].kind == .rail }), !named.isEmpty,
           let i = station(forKey: key, names: true), stations[i].kind == .rail {
            return (i, 0.75)
        }
        if let rail = municipalityRail[key], rail.count == 1 { return (rail[0], 0.6) }
        return nil
    }

    func isDistrictStation(_ index: Int) -> Bool { districtStations.contains(index) }

    func hasTownHbf(_ key: String) -> Bool { townHbf[key] != nil }

    // MARK: Keys

    /// Station-name key: `StationIndex.normalize` ("Hauptbahnhof" → "hbf", "Bahnhof" → "bf", "St." → "st") plus the other
    /// spellings of a station marker ("Bhf", "Hbhf", "Bahnhst", "Haltestelle").
    static func key(_ text: String) -> String { keyWords(text).joined(separator: " ") }

    static func keyWords(_ text: String) -> [String] {
        StationIndex.normalize(text).split(separator: " ").map { marker(String($0)) }
    }

    /// The same words from text that is already folded (`StationIndex.foldedWords`): "hauptbahnhof" → "hbf", "…bahnhof" → "…bf",
    /// "sankt" → "st" – what `StationIndex.normalize` does, without folding the text a second time.
    static func keyWords(folded: [String]) -> [String] {
        folded.map { word in
            if word == "sankt" { return "st" }
            guard word.contains("bahnhof") else { return marker(word) }
            return marker(word.replacingOccurrences(of: "hauptbahnhof", with: "hbf").replacingOccurrences(of: "bahnhof", with: "bf"))
        }
    }

    private static func marker(_ word: String) -> String {
        switch word {
        case "bhf", "bhof": return "bf"
        case "hbhf", "hauptbhf", "hptbf": return "hbf"
        case "haltestelle", "bahnhst", "hst", "haltepunkt", "hp": return "hst"
        default: return word
        }
    }

    /// Words that name no place on their own ("Hauptbahnhof", "Mitte", "Flughafen") and street-like one-word aliases
    /// ("Siemensstraße", "Karlsplatz") never become a lookup key.
    private static let genericWords: Set<String> = [
        "hbf", "bf", "hst", "westbf", "ostbf", "sudbf", "nordbf", "mitte", "sud", "nord", "west", "ost", "zentrum", "flughafen",
        "messe", "airport", "station", "hafen", "bahn", "markt", "stadt", "dorf", "platz",
    ]

    static func isUsableAlias(_ key: String) -> Bool {
        let words = key.split(separator: " ")
        guard words.count == 1, let word = words.first.map(String.init) else { return !key.isEmpty }
        if genericWords.contains(word) || word.count < 3 || word.allSatisfy(\.isNumber) { return false }
        if word.first == "u", word.dropFirst().allSatisfy(\.isNumber) { return false }   // "U3"
        return !LocationNormalizer.isStreet(word)
    }
}

/// The station an event's location points to.
public struct CalendarPlaceMatch: Hashable, Sendable {
    public enum Precision: String, Sendable {
        /// The location names the station ("Salzburg Hbf", "Hauptbahnhof Salzburg", "Westbahnhof, 1150 Wien").
        case station
        /// The location names only a town; the station is its Hauptbahnhof or namesake ("Ort: Wien (ungefähr)").
        case town
    }

    public var station: Station
    public var precision: Precision
    /// The town as written for `.town` ("Wien", "St. Anton am Arlberg"); the matched piece for `.station`.
    public var placeText: String
    /// 0…1, informational: 1 exact official name, 0,95 alias, 0,9 station marker turned around, 0,85 with the postcode's town,
    /// 0,75 town through its Hauptbahnhof or namesake, 0,6 the only rail station of the municipality.
    public var score: Double
}

public struct CalendarTripMatcher: Sendable {
    public let catalog: CalendarStationCatalog

    public init(catalog: CalendarStationCatalog) {
        self.catalog = catalog
    }

    public func match(location: String?) -> CalendarPlaceMatch? {
        match(LocationNormalizer.normalize(location))
    }

    public func match(_ location: NormalizedLocation) -> CalendarPlaceMatch? {
        guard !location.isVirtual, !location.isEmpty else { return nil }
        let town = location.postalTown.map(CalendarStationCatalog.key)
        let segmentWords = location.segments.map {
            $0.folded.isEmpty ? CalendarStationCatalog.keyWords($0.text) : CalendarStationCatalog.keyWords(folded: $0.folded)
        }
        for (segment, words) in zip(location.segments, segmentWords) {
            if let hit = stationMatch(segment.text, words: words, town: town) { return hit }
        }
        if let postal = location.postalTown,
           let hit = townMatch(postal, words: CalendarStationCatalog.keyWords(postal), allowsPrefix: true) { return hit }
        for (segment, words) in zip(location.segments, segmentWords) where !segment.isStreet {
            if let hit = townMatch(segment.text, words: words, allowsPrefix: false) { return hit }
        }
        return nil
    }

    // MARK: Station names

    private static let markers: Set<String> = ["hbf", "bf", "hst", "station"]

    private func stationMatch(_ text: String, words keyWords: [String], town: String?) -> CalendarPlaceMatch? {
        var words = keyWords
        guard !words.isEmpty else { return nil }
        let plain = words.joined(separator: " ")
        // "S-Bahn" / "U-Bahn" after a name is a marker too ("Salzburg Süd S-Bahn" is an alias, "Linz Hbf S-Bahn" is not).
        var hasMarker = words.contains { Self.markers.contains($0) }
        if words.count >= 3, words.suffix(2) == ["s", "bahn"] || words.suffix(2) == ["u", "bahn"] {
            hasMarker = true
        }
        var variants: [(key: String, score: Double)] = [(plain, 1)]
        if hasMarker {
            let isHbf = words.contains("hbf")
            if words.suffix(2) == ["s", "bahn"] || words.suffix(2) == ["u", "bahn"] { words.removeLast(2) }
            let core = words.filter { !Self.markers.contains($0) }.joined(separator: " ")
            if !core.isEmpty {
                variants += isHbf ? [(core + " hbf", 0.9)] : [(core + " bf", 0.9), (core, 0.9), (core + " hbf", 0.9)]
            } else if let town {
                variants += isHbf ? [(town + " hbf", 0.85)] : [(town + " hbf", 0.85), (town + " bf", 0.85), (town, 0.85)]
            }
        } else if words.count >= 2, let first = words.first, first.count > 2, first.hasSuffix("bf") {
            // "Westbahnhof Wien" → "Wien Westbahnhof"
            variants.append(((words.dropFirst() + [first]).joined(separator: " "), 0.9))
        }
        if let town, !plain.hasPrefix(town + " "), plain != town {
            for v in variants where !v.key.hasPrefix(town + " ") && v.key != town {
                variants.append((town + " " + v.key, 0.85))
            }
        }
        var seen: Set<String> = []
        for variant in variants where seen.insert(variant.key).inserted {
            guard let i = catalog.station(forKey: variant.key, inTown: town) else { continue }
            let station = catalog.stations[i]
            let isOfficial = catalog.nameKeys[i] == variant.key
            let names = !hasMarker && variant.score == 1 && isTownLike(i)
            return CalendarPlaceMatch(station: station, precision: names ? .town : .station,
                                      placeText: display(text),
                                      score: names ? 0.75 : (variant.score == 1 && !isOfficial ? 0.95 : variant.score))
        }
        return nil
    }

    /// A station named exactly like its town ("Bregenz", "Kitzbühel", "St. Anton am Arlberg") – written without a station marker
    /// the location names the town, so the card says "ungefähr". Hauptbahnhöfe and parts of a town ("Salzburg Süd") are stations.
    private func isTownLike(_ index: Int) -> Bool {
        let station = catalog.stations[index]
        guard station.kind == .rail, !catalog.isDistrictStation(index) else { return false }
        let last = catalog.nameKeys[index].split(separator: " ").last.map(String.init) ?? ""
        return !(last == "hbf" || last == "bf" || last == "hst" || last.hasSuffix("bf"))
    }

    // MARK: Towns

    private func townMatch(_ text: String, words: [String], allowsPrefix: Bool) -> CalendarPlaceMatch? {
        guard !words.isEmpty, !words.contains(where: { Self.markers.contains($0) }) else { return nil }
        let key = words.joined(separator: " ")
        if let hit = catalog.townStation(forKey: key) {
            return CalendarPlaceMatch(station: catalog.stations[hit.index], precision: .town, placeText: display(text), score: hit.score)
        }
        // "1060 Wien-Mariahilf", "1150 Wien 15" → Wien – only a town with a Hauptbahnhof, only after a postcode.
        guard allowsPrefix, words.count >= 2 else { return nil }
        for k in stride(from: words.count - 1, through: 1, by: -1) {
            let prefix = words[0..<k].joined(separator: " ")
            if catalog.hasTownHbf(prefix), let hit = catalog.townStation(forKey: prefix) {
                let shown = text.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(k).joined(separator: " ")
                return CalendarPlaceMatch(station: catalog.stations[hit.index], precision: .town, placeText: display(shown), score: 0.7)
            }
        }
        return nil
    }

    private func display(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
