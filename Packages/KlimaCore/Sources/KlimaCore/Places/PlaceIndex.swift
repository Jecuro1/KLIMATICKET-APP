import Foundation

/// Offline index over every Austrian stop (places.bin) and locality (localities.bin): Scotty-like suggestions while
/// typing, nearby stops, lookup by id (incl. the ids of the previous stations.json), and the merge with live
/// ÖBB LocMatch rows. Immutable after construction and safe to share across threads.
///
/// Typical use (station picker):
/// ```swift
/// let index = try await PlaceIndexLoader.shared.load()          // built once, off the main thread
/// var rows = index.search(text, context: ctx)                    // offline, < 5 ms per keystroke
/// // after 250 ms idle, if live is allowed: LocMatch ALL/10 (OEBB_LIVE §A3.3)
/// let live = LocMatchDecoder.places(fromResponse: data)          // or Place values from the HAFAS client
/// rows = index.merged(offline: rows, live: live, query: text, context: ctx)
/// ```
public final class PlaceIndex: @unchecked Sendable {
    let table: PlaceTable
    private let byLegacy: [String: Int32]
    let nameKeys = NameKeyCache()
    public let stopCount: Int
    public let localityCount: Int
    /// Seconds spent building the search structures (diagnostics).
    public let buildSeconds: Double

    /// Ids of the "Beliebte Bahnhöfe" shown for an empty query (SUGGEST_SPEC §8).
    public static let topStationIDs = ["at:49:1349", "at:49:1468", "at:45:50002", "at:47:1187", "at:46:3040", "at:44:41164",
                                       "at:43:4848", "at:42:3642", "at:42:3654", "at:48:452"]

    public convenience init(dataset: PlaceDataset) {
        self.init(stops: dataset.stops, localities: dataset.localities)
    }

    /// Loads and indexes the bundled binary files. Takes ~1–3 s for the full dataset: call it off the main thread
    /// (`PlaceIndexLoader` does).
    public convenience init(placesURL: URL, localitiesURL: URL?) throws {
        self.init(dataset: try PlaceDataset(placesURL: placesURL, localitiesURL: localitiesURL))
    }

    init(stops: [PlaceRecord], localities: [PlaceRecord], municipalities: Set<String>? = nil) {
        let t0 = Date()
        let munis = municipalities ?? Self.municipalityKeys(stops: stops, localities: localities)
        table = PlaceTable(records: stops + localities, municipalities: munis)
        var legacy: [String: Int32] = [:]
        for (ri, r) in table.recs.enumerated() {
            for l in r.legacyIDs where legacy[l] == nil { legacy[l] = Int32(ri) }
        }
        byLegacy = legacy
        stopCount = stops.count
        localityCount = localities.count
        buildSeconds = Date().timeIntervalSince(t0)
    }

    /// Municipality keys (SUGGEST_SPEC §3.6): folded Gemeinde names, folded names of cities/towns/villages/suburbs,
    /// and first name tokens shared by ≥ 3 stops. Used for "X (Ort)" variants and dedupe similarity.
    static func municipalityKeys(stops: [PlaceRecord], localities: [PlaceRecord]) -> Set<String> {
        var m = Set<String>()
        for r in stops where !r.municipality.isEmpty { m.insert(PlaceNormalizer.fold(r.municipality)) }
        for l in localities where ["city", "town", "village", "suburb"].contains(l.localityClass ?? "") {
            m.insert(PlaceNormalizer.fold(l.name))
        }
        var first: [String: Int] = [:]
        for r in stops {
            if let f = PlaceNormalizer.tokenize(r.name, isName: false).0.first { first[f.raw, default: 0] += 1 }
        }
        for (t, c) in first where c >= 3 { m.insert(t) }
        return m
    }

    public var count: Int { table.recs.count }

    // MARK: lookup

    /// Place by id: an offline place id (`at:47:1187`, `osm:n…`) or an id of the previous stations.json
    /// (`uic:8100227`, `wl:60201349`, `osm:hub:…`), so existing trips and favourites resolve.
    public func place(id: String) -> Place? {
        if let ri = table.byID[id] ?? byLegacy[id] { return place(Int(ri)) }
        return nil
    }

    /// Legacy bridge: `Station` for a place id or old station id (nil if unknown).
    public func station(id: String) -> Station? {
        guard var p = place(id: id) else { return nil }
        if p.legacyStationIDs.contains(id) {
            // keep the exact id the caller stored (a trip may reference the metro entry of a combined record)
            p.legacyStationIDs = [id]
        }
        return p.station
    }

    func place(_ ri: Int, score: Double = 0) -> Place {
        let r = table.recs[ri]
        return Place(id: r.id, kind: r.kind, name: r.name, aliases: r.aliases,
                     coordinate: GeoPoint(latitude: r.lat, longitude: r.lon), products: PlaceProducts(rawValue: r.products),
                     importance: r.importance, state: r.state.isEmpty ? nil : r.state,
                     municipality: r.municipality.isEmpty ? nil : r.municipality,
                     country: r.country, extId: r.extId, lid: r.lid, isMeta: r.isMeta, weight: r.wt, liveRank: r.liveRank,
                     poiCategory: r.poiCategory, poiCategoryLabel: r.poiCategoryLabel,
                     localityClass: r.localityClass, mainStopID: r.mainStopID,
                     legacyStationIDs: r.legacyIDs, departures: r.weight, lines: r.lines, score: score, source: .offline)
    }

    /// Resolves legacy ids in favourites/recents to place ids (personal boosts are keyed by place id).
    func normalized(_ ctx: PlaceSearchContext) -> PlaceSearchContext {
        guard !ctx.favourites.isEmpty || !ctx.recents.isEmpty else { return ctx }
        var c = ctx
        c.favourites = Set(ctx.favourites.map { id in table.byID[id] != nil ? id : (byLegacy[id].map { table.recs[Int($0)].id } ?? id) })
        var rec: [String: PlaceRecentUse] = [:]
        for (id, use) in ctx.recents {
            let key = table.byID[id] != nil ? id : (byLegacy[id].map { table.recs[Int($0)].id } ?? id)
            if let old = rec[key], old.ageDays <= use.ageDays { continue }
            rec[key] = use
        }
        c.recents = rec
        return c
    }

    // MARK: search

    /// Ranked offline suggestions for typed text (SUGGEST_SPEC §4–§6.7): umlauts/ß folded, abbreviations
    /// (Hbf, Bf, St., Sankt, Wr., i.T., a.d., Ibk …), prefix + token + 1–2 typo matching, importance, proximity,
    /// favourites/recents; duplicates merged and diversity caps applied. Empty text → `[]` (use `popularStations`,
    /// `nearest`). Towns only in `.planner` mode.
    public func search(_ query: String, context: PlaceSearchContext = .planner, limit: Int = 20) -> [Place] {
        guard limit > 0 else { return [] }
        let ctx = normalized(context)
        let raw = searchRaw(query, context: ctx, limit: max(12, limit + 8))
        return merged(offline: raw, live: [], query: query, context: ctx, limit: limit)
    }

    /// Offline ranking without dedupe/caps (tests, diagnostics).
    func searchRaw(_ query: String, context: PlaceSearchContext, limit: Int) -> [Place] {
        var stats = PlaceTable.SearchStats()
        return table.search(query, context, limit: limit, stats: &stats).map { place($0.1, score: $0.0) }
    }

    func searchStats(_ query: String, context: PlaceSearchContext = .planner) -> PlaceTable.SearchStats {
        var stats = PlaceTable.SearchStats()
        _ = table.search(query, normalized(context), limit: 1, stats: &stats)
        return stats
    }

    /// Stops (stations and every other stop) nearest to `point`, closest first.
    public func nearest(to point: GeoPoint, limit: Int = 5, maxMeters: Double = 2_000,
                        products: PlaceProducts = []) -> [(place: Place, distanceMeters: Double)] {
        table.nearest(lat: point.latitude, lon: point.longitude, k: limit, maxMeters: maxMeters, products: products.rawValue)
            .map { (place: place(Int($0.0)), distanceMeters: $0.1) }
    }

    /// "Beliebte Bahnhöfe" for the empty state (Wien Hbf, Wien Westbahnhof, Salzburg Hbf, Innsbruck Hbf, Graz Hbf,
    /// Linz Hbf, St. Pölten Hbf, Klagenfurt Hbf, Villach Hbf, Bregenz).
    public func popularStations(limit: Int = 10) -> [Place] {
        Array(Self.topStationIDs.compactMap(place(id:)).prefix(max(0, limit)))
    }

    // MARK: address / POI / location → stop (SUGGEST_SPEC §7)

    public struct ResolvedStop: Sendable, Hashable {
        public var place: Place
        public var distanceMeters: Double
        public var walkSeconds: Double
        /// Ranking cost: walk seconds − 300 × importance (lower is better).
        public var cost: Double
    }

    /// Best stops to value a trip from/to a coordinate (address, POI, current location): offline stops ≤ `maxMeters`
    /// plus optional live LocGeoPos rows (`LocMatchDecoder.nearby`), deduped, best first (≤ 3).
    public func resolveStops(near point: GeoPoint, live: [(place: Place, distanceMeters: Double)] = [],
                             maxMeters: Double = 1_500) -> [ResolvedStop] {
        var out: [ResolvedStop] = []
        for (p, d) in nearest(to: point, limit: 8, maxMeters: maxMeters) {
            let w = Place.walkSeconds(meters: d)
            out.append(ResolvedStop(place: p, distanceMeters: d, walkSeconds: w, cost: w - 300 * p.importance))
        }
        let rules = SimilarityRules(municipalities: table.municipalities)
        let offlineKeys = out.map { dedupeKey($0.place) }
        for (l, d) in live where d <= maxMeters && l.kind.isStopLike {
            let lk = dedupeKey(l)
            if offlineKeys.contains(where: { rules.samePlace($0, lk) }) { continue }
            let imp = l.weight.map { PlaceDataset.importance(wt: $0) } ?? 0.5
            let w = Place.walkSeconds(meters: d)
            out.append(ResolvedStop(place: l, distanceMeters: d, walkSeconds: w, cost: w - 300 * imp))
        }
        out.sort { $0.cost < $1.cost || ($0.cost == $1.cost && $0.distanceMeters < $1.distanceMeters) }
        return Array(out.prefix(3))
    }
}
