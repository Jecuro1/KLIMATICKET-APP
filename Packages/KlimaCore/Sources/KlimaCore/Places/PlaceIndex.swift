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
    /// Format version and layers of the loaded files (ENRICH_SPEC §2.3; `hasOSMLayer` = M1).
    public let dataInfo: PlaceDataInfo
    /// Lines and tags of the v2 files (nil for v1 files: rows then carry the legacy line list only).
    let enrichment: PlaceEnrichment?
    /// Per table record: the enrichment stop index of the record (towns: of their main stop), -1 none.
    let enrichIndex: [Int32]

    /// Ids of the "Beliebte Bahnhöfe" shown for an empty query (SUGGEST_SPEC §8).
    public static let topStationIDs = ["at:49:1349", "at:49:1468", "at:45:50002", "at:47:1187", "at:46:3040", "at:44:41164",
                                       "at:43:4848", "at:42:3642", "at:42:3654", "at:48:452"]

    public convenience init(dataset: PlaceDataset) {
        let enrichment = dataset.officialLayer.map {
            PlaceEnrichment(stops: dataset.stops, official: $0, osm: dataset.osmLayer)
        }
        self.init(stops: dataset.stops, localities: dataset.localities, dataInfo: dataset.dataInfo, enrichment: enrichment)
    }

    /// Loads and indexes the bundled binary files (v1 or v2; `osmURL` = the optional ODbL layer stops_osm.bin).
    /// Takes ~1–3 s for the full dataset: call it off the main thread (`PlaceIndexLoader` does).
    public convenience init(placesURL: URL, localitiesURL: URL?, osmURL: URL? = nil) throws {
        self.init(dataset: try PlaceDataset(placesURL: placesURL, localitiesURL: localitiesURL, osmURL: osmURL))
    }

    init(stops: [PlaceRecord], localities: [PlaceRecord], municipalities: Set<String>? = nil,
         dataInfo: PlaceDataInfo? = nil, enrichment: PlaceEnrichment? = nil) {
        self.dataInfo = dataInfo ?? PlaceDataset.info(version: 1, stops: stops, official: nil, osm: nil, issue: nil)
        self.enrichment = enrichment
        let t0 = Date()
        let munis = municipalities ?? Self.municipalityKeys(stops: stops, localities: localities)
        // search context words (ENRICH_SPEC §2.4): sets built from the sorted table records
        let builder = enrichment.map { e -> ([PlaceRecord]) -> PlaceContextIndex in
            let vocabulary = PlaceContextVocabulary(catalog: e.catalog)
            return { PlaceContextIndex(records: $0, vocabulary: vocabulary, entityNames: e.entityNames, entitiesOfStop: e.entities) }
        }
        table = PlaceTable(records: stops + localities, municipalities: munis, context: builder)
        var legacy: [String: Int32] = [:]
        for (ri, r) in table.recs.enumerated() {
            for l in r.legacyIDs where legacy[l] == nil { legacy[l] = Int32(ri) }
        }
        byLegacy = legacy
        enrichIndex = Self.enrichmentIndex(table: table, enrichment: enrichment)
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
        // no lines/tags: a Station has none, and trip lists resolve every stored id through here
        guard let ri = table.byID[id] ?? byLegacy[id] else { return nil }
        var p = place(Int(ri), enriched: false)
        if p.legacyStationIDs.contains(id) {
            // keep the exact id the caller stored (a trip may reference the metro entry of a combined record)
            p.legacyStationIDs = [id]
        }
        return p.station
    }

    /// Place of table record `ri`; `enriched: false` leaves `lines`/`tags` empty (search candidates are enriched
    /// only once they survive the merge, see `search`).
    func place(_ ri: Int, score: Double = 0, enriched: Bool = true) -> Place {
        let r = table.recs[ri]
        return Place(id: r.id, kind: r.kind, name: r.name, aliases: r.aliases,
                     coordinate: GeoPoint(latitude: r.lat, longitude: r.lon), products: PlaceProducts(rawValue: r.products),
                     importance: r.importance, state: r.state.isEmpty ? nil : r.state,
                     municipality: r.municipality.isEmpty ? nil : r.municipality,
                     country: r.country, extId: r.extId, lid: r.lid, isMeta: r.isMeta, weight: r.wt, liveRank: r.liveRank,
                     poiCategory: r.poiCategory, poiCategoryLabel: r.poiCategoryLabel,
                     localityClass: r.localityClass, mainStopID: r.mainStopID,
                     legacyStationIDs: r.legacyIDs, departures: r.weight, lines: enriched ? compactLines(record: ri) : [],
                     tags: enriched ? tags(record: ri) : .empty, score: score, source: .offline)
    }

    /// Fills `lines` and `tags` of offline rows (and of live rows merged into an offline identity).
    func enriched(_ places: [Place]) -> [Place] {
        guard enrichment != nil || dataInfo.formatVersion == 1 else { return places }
        return places.map { p in
            guard p.source != .live, p.lines.isEmpty, p.tags == .empty, let ri = table.byID[p.id].map(Int.init) else { return p }
            var c = p
            c.lines = compactLines(record: ri)
            c.tags = tags(record: ri)
            return c
        }
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
        search(query, context: context, limit: limit, enrich: true)
    }

    /// `enrich: false` leaves `lines`/`tags` empty – for callers that only need `Place.station` (`StationIndex`).
    func search(_ query: String, context: PlaceSearchContext, limit: Int, enrich: Bool) -> [Place] {
        guard limit > 0 else { return [] }
        let ctx = normalized(context)
        let raw = searchRaw(query, context: ctx, limit: max(12, limit + 8))
        let rows = merged(offline: raw, live: [], query: query, context: ctx, limit: limit)
        return enrich ? enriched(rows) : rows
    }

    /// Offline ranking without dedupe/caps (tests, diagnostics); rows without `lines`/`tags` unless `enriched`.
    func searchRaw(_ query: String, context: PlaceSearchContext, limit: Int, enriched: Bool = false) -> [Place] {
        var stats = PlaceTable.SearchStats()
        return table.search(query, context, limit: limit, stats: &stats).map { place($0.1, score: $0.0, enriched: enriched) }
    }

    func searchStats(_ query: String, context: PlaceSearchContext = .planner) -> PlaceTable.SearchStats {
        var stats = PlaceTable.SearchStats()
        _ = table.search(query, normalized(context), limit: 1, stats: &stats)
        return stats
    }

    /// Stops (stations and every other stop) nearest to `point`, closest first.
    public func nearest(to point: GeoPoint, limit: Int = 5, maxMeters: Double = 2_000,
                        products: PlaceProducts = []) -> [(place: Place, distanceMeters: Double)] {
        nearest(to: point, limit: limit, maxMeters: maxMeters, products: products, enrich: true)
    }

    /// `enrich: false` leaves `lines`/`tags` empty – `StationIndex.nearest` (coverage engine, station linker: every
    /// stop of every journey) only needs `Place.station`.
    func nearest(to point: GeoPoint, limit: Int, maxMeters: Double, products: PlaceProducts = [],
                 enrich: Bool) -> [(place: Place, distanceMeters: Double)] {
        table.nearest(lat: point.latitude, lon: point.longitude, k: limit, maxMeters: maxMeters, products: products.rawValue)
            .map { (place: place(Int($0.0), enriched: enrich), distanceMeters: $0.1) }
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

// MARK: - Lines, tags, ski areas, regions (docs/ENRICH_SPEC.md §2.3)

extension PlaceIndex {
    /// Curated and OSM-only ski areas and sectors (no alliances), sorted by name. Empty for v1 files.
    public var skiAreas: [SkiArea] { enrichment?.catalog.sortedAreas ?? [] }

    /// Ski area, sector or ski-pass alliance by id ("ski-arlberg", "ski-amade").
    public func skiArea(id: String) -> SkiArea? { enrichment?.catalog.areas[id] }

    /// Tourism regions and landscapes, sorted by name.
    public var regions: [Region] { enrichment?.catalog.sortedRegions ?? [] }

    public func region(id: String) -> Region? { enrichment?.catalog.regions[id] }

    /// Display name of an operator (E4): the data build's table, else `OperatorNames.display` (live names).
    public func operatorName(_ legal: String) -> String {
        enrichment?.catalog.operatorDisplay(legal) ?? OperatorNames.display(legal)
    }

    /// Every line of a stop for the detail (M3–M7: deduped, superseded lines shown as their successor, rail
    /// categories as plates), display-sorted. `placeID` = place id or a legacy station id; a town gives the lines of
    /// its main stop; unknown ids and stops without lines give `[]`.
    public func stopLines(for placeID: String) -> [StopLine] {
        guard let ri = recordIndex(placeID) else { return [] }
        if let e = enrichment, enrichIndex[ri] >= 0 { return e.stopLines(Int(enrichIndex[ri])) }
        return legacyLines(record: ri).map { StopLine(line: $0, confidence: .timetable) }
    }

    /// M8 subset for compact rows (the same as `place(id:)?.lines`).
    public func compactLines(for placeID: String) -> [LineRef] {
        recordIndex(placeID).map { compactLines(record: $0) } ?? []
    }

    /// Every tag of a place (`.empty` for unknown ids).
    public func tags(for placeID: String) -> PlaceTags {
        recordIndex(placeID).map { tags(record: $0) } ?? .empty
    }

    /// Persistent line key ("VVV|bus|852") → the line of the current dataset (first match).
    public func line(key: String) -> LineRef? {
        guard let c = enrichment?.lines, let i = c.byKey[key] else { return nil }
        return c.lines[Int(i)]
    }

    /// Stops in a ski area (tag confidence ≥ `minConfidence`), by confidence, then importance.
    public func stops(inSkiArea id: String, minConfidence: Int = 70, limit: Int = 500) -> [Place] {
        guard let e = enrichment, limit > 0 else { return [] }
        let members = e.skiMembers(id)
        let hits = members.filter { Int($0.confidence) >= minConfidence }
            .compactMap { m in recordIndex(stop: Int(m.stop)).map { (ri: $0, conf: Int(m.confidence)) } }
            .sorted { $0.conf != $1.conf ? $0.conf > $1.conf : $0.ri < $1.ri }
        return hits.prefix(limit).map { place($0.ri) }
    }

    /// Stops in a tourism region or landscape (tag confidence ≥ 80), by importance.
    public func stops(inRegion id: String, limit: Int = 500) -> [Place] {
        guard let e = enrichment, limit > 0 else { return [] }
        let members = e.regionMembers(id)
        let ris = members.compactMap { recordIndex(stop: Int($0)) }.sorted()
        return ris.prefix(limit).map { place($0) }
    }

    // MARK: internals

    /// Table record of a place id or legacy station id.
    func recordIndex(_ placeID: String) -> Int? {
        (table.byID[placeID] ?? byLegacy[placeID]).map(Int.init)
    }

    /// Table record of an enrichment stop index.
    func recordIndex(stop: Int) -> Int? {
        guard let e = enrichment, stop >= 0, stop < e.stopCount else { return nil }
        return table.byID[e.stopIDs[stop]].map(Int.init)
    }

    static func enrichmentIndex(table: PlaceTable, enrichment: PlaceEnrichment?) -> [Int32] {
        guard let e = enrichment else { return [] }
        var out = [Int32](repeating: -1, count: table.recs.count)
        for (ri, r) in table.recs.enumerated() {
            if r.stopIndex >= 0 && Int(r.stopIndex) < e.stopCount {
                out[ri] = r.stopIndex
            } else if r.kind == .town, let m = r.mainStopID, let mi = table.byID[m] {
                let s = table.recs[Int(mi)].stopIndex
                if s >= 0 && Int(s) < e.stopCount { out[ri] = s }
            }
        }
        return out
    }

    /// Compact lines of table record `ri` (Place.lines).
    func compactLines(record ri: Int) -> [LineRef] {
        if let e = enrichment {
            let s = ri < enrichIndex.count ? Int(enrichIndex[ri]) : -1
            return s >= 0 ? e.rowFacts(s).lines : []
        }
        return legacyLines(record: ri)
    }

    /// v1 files: the legacy line string of the record (towns: of their main stop).
    func legacyLines(record ri: Int) -> [LineRef] {
        var r = table.recs[ri]
        if r.kind == .town, let m = r.mainStopID, let mi = table.byID[m] { r = table.recs[Int(mi)] }
        guard let s = r.legacyLines else { return [] }
        return PlaceEnrichment.legacyLines(s, products: r.products)
    }

    /// Tags of table record `ri` (Place.tags).
    func tags(record ri: Int) -> PlaceTags {
        guard let e = enrichment else { return .empty }
        let r = table.recs[ri]
        let s = ri < enrichIndex.count ? Int(enrichIndex[ri]) : -1
        if r.kind == .town {
            return e.townTags(mainStop: s >= 0 ? s : nil, state: r.state.isEmpty ? nil : r.state, gkz: r.gkz)
        }
        return s >= 0 ? e.rowFacts(s).tags : .empty
    }
}
