import Foundation

/// VAO location search, implemented by `VerbundTariffClient` (WP-B). Returns VAO locations (VAO lids embed the IFOPT id).
public protocol VaoLocationSearching: Sendable {
    func vaoLocations(_ query: String) async throws -> [Location]
}

/// App stations (`at:47:1187`, `uic:8100227`, `wl:60201349`, `osm:hub:…`, place-database stops) ⇄ live locations
/// (ÖBB HAFAS extIds, VAO lids). SPEC §A3.7. Results that needed a request are disk-cached for 30 days.
public actor StationLinker {
    static let cacheTTL: TimeInterval = 30 * 86_400
    static let cacheCapacity = 2_000
    static let maxDistanceMeters = 300.0
    static let maxMetaDistanceMeters = 800.0
    static let maxVaoDistanceMeters = 400.0

    struct CachedHafas: Codable, Hashable {
        var lid: String
        var extId: String?
        var name: String
        var lat: Double?
        var lon: Double?
    }

    struct CacheEntry: Codable, Hashable {
        var hafas: CachedHafas?
        var vaoLid: String?
        var fetchedAt: Date
    }

    struct CacheFile: Codable {
        var version: Int
        var entries: [String: CacheEntry]
    }

    private let stations: StationIndex
    private let timetable: (any TimetableService)?
    private let vao: VaoLocationSearching?
    private let cacheURL: URL?
    private let clock: @Sendable () -> Date
    private var entries: [String: CacheEntry] = [:]
    private var loaded = false

    public init(stations: StationIndex, timetable: (any TimetableService)?, vao: VaoLocationSearching?, cacheURL: URL?,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.stations = stations
        self.timetable = timetable
        self.vao = vao
        self.cacheURL = cacheURL
        self.clock = clock
    }

    // MARK: - HAFAS

    /// App station → ÖBB HAFAS location (for TripSearch/StationBoard/shop). Disk-cached 30 days.
    public func hafasLocation(for station: Station) async throws -> Location {
        if let direct = Self.directHafasLocation(for: station) { return direct }
        loadIfNeeded()
        if let e = entries[station.id], let h = e.hafas, isFresh(e) {
            return Location(lid: h.lid, kind: .station, extId: h.extId, name: h.name,
                            coordinate: h.lat.flatMap { lat in h.lon.map { GeoPoint(latitude: lat, longitude: $0) } })
        }
        guard let timetable else { throw LiveError.disabled(.oebbHafas) }
        let candidates = try await timetable.locations(station.name, types: .stations, maxResults: 8)
        guard let best = Self.bestHafasCandidate(for: station, among: candidates) else {
            throw LiveError.hafas(code: "LOCATION", message: nil)
        }
        var entry = entries[station.id] ?? CacheEntry(fetchedAt: clock())
        entry.hafas = CachedHafas(lid: best.lid, extId: best.extId, name: best.name, lat: best.coordinate?.latitude, lon: best.coordinate?.longitude)
        entry.fetchedAt = clock()
        store(entry, for: station.id)
        return best
    }

    /// Rule 1: `uic:<eva>` → `A=1@L=<eva>@`, no I/O.
    static func directHafasLocation(for station: Station) -> Location? {
        guard station.id.hasPrefix("uic:") else { return nil }
        let eva = String(station.id.dropFirst(4))
        guard !eva.isEmpty, eva.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var loc = Location.station(extId: eva, name: station.name)
        loc.coordinate = station.location
        return loc
    }

    /// Rule 2: LocMatch candidates scored by distance, kind preference, IFOPT hint and name similarity.
    static func bestHafasCandidate(for station: Station, among candidates: [Location]) -> Location? {
        let origin = station.location
        let ifoptHint = ifoptUIC(station.id)
        let wanted = StationIndex.normalize(station.name)
        var best: (score: Double, loc: Location)?
        for c in candidates where c.kind == .station {
            guard let coord = c.coordinate else { continue }
            let meters = origin.distanceKm(to: coord) * 1000
            guard meters <= (c.isMeta ? maxMetaDistanceMeters : maxDistanceMeters) else { continue }
            var score = 0.0
            let isRailStop = !c.isMeta && !c.products.intersection(.rail).isEmpty
            switch station.kind {
            case .rail: if isRailStop { score += 20 }
            case .metro, .tramHub: if c.isMeta { score += 20 }
            case .stop: if !c.isMeta { score += 5 }
            }
            if let ifoptHint, c.uicCode == ifoptHint { score += 10 }
            score += 8 * similarity(wanted, StationIndex.normalize(c.name))
            score -= meters / 400 // closer wins remaining ties
            if best == nil || score > best!.score { best = (score, c) }
        }
        return best?.loc
    }

    /// `at:47:1187` → "8101187" (the `globalIdL U` value HAFAS sends in Tirol and Kärnten): a hint, never a key.
    static func ifoptUIC(_ id: String) -> String? {
        let p = id.split(separator: ":")
        guard p.count >= 3, p[0] == "at", let stop = Int(p[2]), stop < 100_000 else { return nil }
        return "81" + String(format: "%05d", stop)
    }

    /// Token overlap (Dice coefficient) of two normalized names, 0…1.
    static func similarity(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " ")), tb = Set(b.split(separator: " "))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return 2 * Double(ta.intersection(tb).count) / Double(ta.count + tb.count)
    }

    // MARK: - VAO

    /// App station → VAO lid `A=1@L=<n>@` (for VerbundTariffClient). Disk-cached 30 days.
    public func vaoLid(for station: Station) async throws -> String {
        if let direct = Self.directVaoLid(for: station.id) { return direct }
        loadIfNeeded()
        if let e = entries[station.id], let lid = e.vaoLid, isFresh(e) { return lid }
        guard let vao else { throw LiveError.disabled(.vaoTariff) }
        let candidates = try await vao.vaoLocations(station.name)
        var best: (meters: Double, loc: Location)?
        for c in candidates {
            guard let coord = c.coordinate else { continue }
            let meters = station.location.distanceKm(to: coord) * 1000
            guard meters <= Self.maxVaoDistanceMeters else { continue }
            if best == nil || meters < best!.meters { best = (meters, c) }
        }
        guard let loc = best?.loc else { throw LiveError.hafas(code: "LOCATION", message: nil) }
        let lid = Self.minimalLid(loc.lid) ?? loc.lid
        var entry = entries[station.id] ?? CacheEntry(fetchedAt: clock())
        entry.vaoLid = lid
        entry.fetchedAt = clock()
        store(entry, for: station.id)
        return lid
    }

    /// Rules 1–2: `at:A:S[:x:P]` → `A=1@L=<A><S 5 digits><P 2 digits>@`; `wl:6020NNNN` → as `at:49:NNNN`.
    public nonisolated static func directVaoLid(for stationID: String) -> String? {
        let parts = stationID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "wl", parts.count == 2, parts[1].count == 8, parts[1].hasPrefix("6020"), let n = Int(parts[1].dropFirst(4)) {
            return lid(area: 49, stop: n, platform: 0)
        }
        guard parts.first == "at", parts.count >= 3, let area = Int(parts[1]), let stop = Int(parts[2]) else { return nil }
        var platform = 0
        if parts.count >= 5 {
            guard let p = Int(parts[4]) else { return nil }
            platform = p
        }
        return lid(area: area, stop: stop, platform: platform)
    }

    private nonisolated static func lid(area: Int, stop: Int, platform: Int) -> String? {
        guard (1...99).contains(area), (0..<100_000).contains(stop), (0..<100).contains(platform) else { return nil }
        return "A=1@L=\(area)\(String(format: "%05d", stop))\(String(format: "%02d", platform))@"
    }

    /// "A=1@O=Eferding Bahnhof@X=…@L=444250500@B=1@…" → "A=1@L=444250500@".
    static func minimalLid(_ lid: String) -> String? {
        for part in lid.split(separator: "@") where part.hasPrefix("L=") {
            let v = part.dropFirst(2)
            if !v.isEmpty { return "A=1@L=\(v)@" }
        }
        return nil
    }

    // MARK: - Reverse

    /// HAFAS location → best app station: the nearest within 300 m whose normalized name shares its first token with
    /// the location's display name. nil if none qualifies. Pure; no I/O.
    public nonisolated static func appStation(for location: Location, in index: StationIndex) -> Station? {
        guard let coord = location.coordinate else { return nil }
        guard let first = firstToken(displayName(location.name)) else { return nil }
        for candidate in index.nearest(to: coord, limit: 12, maxKm: maxDistanceMeters / 1000) {
            if firstToken(candidate.station.name) == first { return candidate.station }
        }
        return nil
    }

    /// Minimal display-name stripping (cf. `DisplayNames`, SPEC §C3.3): parenthesised suffixes go ("Wien Hbf
    /// (Bahnsteige 3-12)" → "Wien Hbf"), "St.Anton" gets its space.
    static func displayName(_ raw: String) -> String {
        var s = raw
        if let open = s.firstIndex(of: "(") { s = String(s[..<open]) }
        s = s.replacingOccurrences(of: "St.", with: "St. ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func firstToken(_ name: String) -> String? {
        StationIndex.normalize(name).split(separator: " ").first.map(String.init)
    }

    // MARK: - Cache

    public func invalidate(stationID: String) {
        loadIfNeeded()
        guard entries.removeValue(forKey: stationID) != nil else { return }
        persist()
    }

    private func isFresh(_ e: CacheEntry) -> Bool {
        clock().timeIntervalSince(e.fetchedAt) < Self.cacheTTL
    }

    private func store(_ entry: CacheEntry, for id: String) {
        entries[id] = entry
        if entries.count > Self.cacheCapacity {
            let overflow = entries.count - Self.cacheCapacity
            for key in entries.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(overflow).map(\.key) {
                entries[key] = nil
            }
        }
        persist()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let file = try? dec.decode(CacheFile.self, from: data), file.version == 1 else { return }
        entries = file.entries
    }

    private func persist() {
        guard let cacheURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(CacheFile(version: 1, entries: entries)) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
