import Foundation

// SUGGEST_SPEC §6.3–§6.7: live row scoring, plausibility filter, offline ↔ live dedupe (D0–D4), diversity caps.
// Mirrors scripts/places_reference.py (merge / same_place / name_sim) 1:1.

/// Per-name facts for dedupe: sorted essential canonical tokens and the last essential token.
struct NameKey: Sendable {
    var essential: [String]
    var last: String?

    init(_ name: String, municipalities: Set<String>) {
        let v = PlaceTable.nameVariants(name, municipalities)
        let moved = v.count > 1
        let toks = PlaceNormalizer.tokenize(v[v.count - 1], isName: false).0
        essential = Array(Set(toks.filter { ($0.isEssential || (moved && $0.isQualifier)) && !$0.isGeneric }.map(\.canonical))).sorted()
        let own = moved ? PlaceNormalizer.tokenize(name, isName: false).0 : toks
        last = own.last { $0.isEssential }?.canonical
    }
}

/// Everything the dedupe rules need about one row, computed once per row.
struct DedupeKey {
    var names: [NameKey]
    var lat: Double
    var lon: Double
    var kind: PlaceKind
    var isMeta: Bool
    var isRail: Bool
    var extId: String?
}

/// Dedupe rules D0–D4 (SUGGEST_SPEC §6.6) over `DedupeKey`s.
struct SimilarityRules {
    let municipalities: Set<String>

    /// Jaccard over essential tokens; a single extra municipality token counts as equal
    /// ("Riedenburg" ≈ "Bregenz Riedenburg Bahnhst", "Floridsdorf (Wien)" ≈ "Wien Floridsdorf").
    func nameSim(_ a: [String], _ b: [String]) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        var i = 0, j = 0, inter = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { inter += 1; i += 1; j += 1 } else if a[i] < b[j] { i += 1 } else { j += 1 }
        }
        if a.count != b.count && inter == min(a.count, b.count) && max(a.count, b.count) - inter == 1 {
            let (small, big) = a.count < b.count ? (a, b) : (b, a)
            if let extra = big.first(where: { !small.contains($0) }), municipalities.contains(extra) { return 1.0 }
        }
        return Double(inter) / Double(a.count + b.count - inter)
    }

    func recordSim(_ o: DedupeKey, _ l: DedupeKey) -> Double {
        var best = 0.0
        for x in o.names {
            for y in l.names {
                best = max(best, nameSim(x.essential, y.essential))
                if best >= 1 { return best }
            }
        }
        return best
    }

    /// D3′: same stop-specific last token ("Lech am Arlberg Dorfhus" ≈ "Lech Dorfhus").
    func lastTokenMatch(_ o: DedupeKey, _ l: DedupeKey) -> Bool {
        for x in o.names {
            guard let a = x.last else { continue }
            for y in l.names {
                guard let b = y.last else { continue }
                if a == b { return true }
                if min(a.unicodeScalars.count, b.unicodeScalars.count) >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
            }
        }
        return false
    }

    func samePlace(_ o: DedupeKey, _ l: DedupeKey) -> Bool {
        if let a = o.extId, let b = l.extId, !a.isEmpty, a == b { return true }                       // D1
        if o.kind == .address || o.kind == .poi || l.kind == .address || l.kind == .poi { return false } // D0
        if (o.kind == .town) != (l.kind == .town) { return false }
        // cheap pre-filter (equirectangular, generous margin) before the exact haversine distance
        let dy = (o.lat - l.lat) * 111_195, dx = (o.lon - l.lon) * 111_195 * cos(o.lat * .pi / 180)
        let approx = (dx * dx + dy * dy).squareRoot()
        if o.kind == .town {                                                                             // D4
            if approx > 5_100 || PlaceTable.haversine(o.lat, o.lon, l.lat, l.lon) > 5_000 { return false }
            return recordSim(o, l) == 1.0
        }
        if approx > 620 { return false }
        let d = PlaceTable.haversine(o.lat, o.lon, l.lat, l.lon)
        if d > 600 { return false }
        let sim = recordSim(o, l)
        if sim == 1.0 && (d <= 300 || o.isMeta || l.isMeta || (o.isRail && l.isRail)) { return true }  // D2
        if sim >= 0.75 && d <= 150 { return true }                                                       // D3
        return d <= 80 && lastTokenMatch(o, l)                                                           // D3′
    }
}

/// Lock-protected cache of `NameKey`s of offline records (names repeat across keystrokes).
final class NameKeyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byRecord: [Int32: [NameKey]] = [:]

    func keys(_ ri: Int32, make: () -> [NameKey]) -> [NameKey] {
        lock.lock()
        if let k = byRecord[ri] { lock.unlock(); return k }
        lock.unlock()
        let k = make()
        lock.lock()
        if byRecord.count > 20_000 { byRecord.removeAll(keepingCapacity: true) }
        byRecord[ri] = k
        lock.unlock()
        return k
    }
}

extension PlaceIndex {
    struct Row {
        var place: Place
        var base: Double?
        var liveBonus = 0.0
        var liveScore: Double?
        var score: Double {
            let a = base.map { $0 + liveBonus }
            switch (a, liveScore) {
            case let (x?, y?): return max(x, y)
            case let (x?, nil): return x
            case let (nil, y?): return y
            default: return 0
            }
        }
    }

    /// Scores live LocMatch rows against the query with the offline formula (§6.3: relaxed, importance from `wt`,
    /// live rank bonus), drops implausible rows (§6.4) and, in „Fahrt erfassen“, towns. Addresses and POIs keep
    /// Scotty's relative order. Returns the kept rows in their original order with `score` set.
    public func rankLive(_ live: [Place], query: String, context: PlaceSearchContext = .planner) -> [Place] {
        guard !live.isEmpty else { return [] }
        let ctx = normalized(context)
        // unique ids inside the mini table
        var recs: [PlaceRecord] = []
        var seen = Set<String>()
        var keys: [String] = []
        for (k, p) in live.enumerated() {
            var id = p.id
            if !seen.insert(id).inserted { id = "\(p.id)#\(k)"; seen.insert(id) }
            keys.append(id)
            recs.append(Self.record(from: p, id: id))
        }
        let t = PlaceTable(records: recs, municipalities: table.municipalities,
                           options: .init(trigrams: false, grid: false, exact: false, keepRawTokens: true))
        guard let q = t.compile(query, split: false, fuzzy: false) else { return [] }
        var caps: [PlaceKind: Double] = [:]
        var out: [Place] = []
        var scratch = PlaceTable.Scratch(n: q.n)
        let personal = t.personalBoosts(ctx)
        for (k, p) in live.enumerated() {
            if ctx.mode == .tripLog && p.kind == .town { continue }
            guard let ri = t.byID[keys[k]].map(Int.init) else { continue }
            var ts: Double, ex: Double
            if let r = t.textScore(q, ri, relaxed: true, scratch: &scratch) {
                (ts, ex) = r
            } else {
                guard plausible(q, table: t, record: ri) else { continue }
                (ts, ex) = (0.30, 0)
            }
            var s = t.finalScore(q, ri, ts, exact: ex, ctx, personal: personal)
            if p.kind == .address || p.kind == .poi {
                if let c = caps[p.kind] { s = min(s, c - 0.5) }
                caps[p.kind] = s
            }
            var copy = p
            copy.score = s
            copy.source = .live
            out.append(copy)
        }
        return out
    }

    /// §6.4: keep an unmatched live row if a query token of ≥ 3 letters is a prefix of, or within prefix-edit
    /// distance 2 of, one of its tokens.
    private func plausible(_ q: CompiledQuery, table t: PlaceTable, record ri: Int) -> Bool {
        let a = Int(t.varTokStart[Int(t.recVarStart[ri])]), b = Int(t.varTokStart[Int(t.recVarStart[ri + 1])])
        let names = t.tokRaw[a..<b].map { Array($0.unicodeScalars) }
        for raw in q.raw {
            let qs = Array(raw.unicodeScalars)
            guard qs.count >= 3, qs.allSatisfy(PlaceNormalizer.isAlpha) else { continue }
            for n in names {
                if n.starts(with: qs) || PlaceTable.prefixEditDistance(qs, n, 2) != nil { return true }
            }
        }
        return false
    }

    static func record(from p: Place, id: String) -> PlaceRecord {
        var r = PlaceRecord(id: id, name: p.name, aliases: p.aliases, lat: p.coordinate.latitude, lon: p.coordinate.longitude,
                            kind: p.kind, products: p.products.rawValue, importance: p.importance, country: p.country,
                            state: p.state ?? "", municipality: p.municipality ?? "", localityClass: p.localityClass,
                            weight: p.departures, flags: 0)
        if !p.legacyStationIDs.isEmpty { r.legacyIDs = p.legacyStationIDs }
        if let m = p.mainStopID { r.mainStopID = m }
        r.extIdString = p.extId
        r.lid = p.lid
        r.isMeta = p.isMeta
        r.liveRank = p.liveRank
        r.wt = p.weight
        r.poiCategory = p.poiCategory
        r.poiCategoryLabel = p.poiCategoryLabel
        return r
    }

    /// Dedupe facts of a row (offline records: cached per record).
    func dedupeKey(_ p: Place) -> DedupeKey {
        let names: [NameKey]
        if let ri = table.byID[p.id], table.recs[Int(ri)].name == p.name, table.recs[Int(ri)].aliases == p.aliases {
            names = nameKeys.keys(ri) { ([p.name] + p.aliases).map { NameKey($0, municipalities: table.municipalities) } }
        } else {
            names = ([p.name] + p.aliases).map { NameKey($0, municipalities: table.municipalities) }
        }
        return DedupeKey(names: names, lat: p.coordinate.latitude, lon: p.coordinate.longitude, kind: p.kind,
                         isMeta: p.isMeta, isRail: p.products.isRail, extId: p.extId)
    }

    /// Offline rows that are the same physical place → one row (the more important / unbracketed / shorter name
    /// is the identity). Works on copies.
    func dedupeOffline(_ offline: [Place], rules: SimilarityRules, keys: inout [DedupeKey]) -> [Row] {
        var rows: [Row] = []
        for p in offline {
            let pk = dedupeKey(p)
            if let h = keys.firstIndex(where: { rules.samePlace($0, pk) }) {
                func repKey(_ x: Place) -> (Double, Int, Int) {
                    ((x.importance * 1000).rounded() / 1000, (x.name.contains("(") || x.name.contains("[")) ? 0 : 1,
                     -x.name.unicodeScalars.count)
                }
                if repKey(p) > repKey(rows[h].place) {
                    var r = p
                    r.products.formUnion(rows[h].place.products)
                    r.mergedNames = rows[h].place.mergedNames + [rows[h].place.name]
                    rows[h].place = r
                    keys[h] = pk
                    keys[h].isRail = r.products.isRail
                } else {
                    rows[h].place.products.formUnion(p.products)
                    rows[h].place.mergedNames.append(p.name)
                    keys[h].isRail = rows[h].place.products.isRail
                }
                rows[h].base = max(rows[h].base ?? -.infinity, p.score)
            } else {
                rows.append(Row(place: p, base: p.score))
                keys.append(pk)
            }
        }
        return rows
    }

    /// Merges offline suggestions (from `search`) with live LocMatch rows for the same text: scores live rows
    /// (§6.3), drops implausible ones (§6.4), merges duplicates into the offline identity (§6.6: stable id,
    /// municipality, state; gains HAFAS `lid`/`extId`, products union, max importance, source `.both`),
    /// sorts and applies the diversity caps (§6.7: ≤ 2 addresses (5 with a house number), ≤ 3 POIs (5 when a POI
    /// ranks first), ≤ 2 towns and one per name — overflow rows move to the end).
    public func merged(offline: [Place], live: [Place], query: String, context: PlaceSearchContext = .planner,
                       limit: Int = 20) -> [Place] {
        let ranked = rankLive(live, query: query, context: context)
        let hasNumber = PlaceNormalizer.tokenize(query, isName: false).0.contains { $0.isNumeric }
        return mergeScored(offline: offline, live: ranked, hasNumber: hasNumber, limit: limit)
    }

    /// Merge of already scored lists (`search` results and `rankLive` rows). Unscored live rows (`score == 0`) get
    /// a neutral score (text 0.30 + importance + live rank bonus). Prefer `merged(offline:live:query:context:)`.
    public func merged(offline: [Place], live: [Place]) -> [Place] {
        let scored = live.map { p -> Place in
            guard p.score == 0 else { return p }
            var c = p
            c.score = PlaceWeights.text * 0.30 + PlaceWeights.importance * p.importance
                + (p.liveRank.map { PlaceWeights.liveBonus(rank: $0) } ?? 0)
            c.source = .live
            return c
        }
        let hasNumber = live.contains { $0.kind == .address && $0.title.contains(where: \.isNumber) }
        return mergeScored(offline: offline, live: scored, hasNumber: hasNumber, limit: offline.count + live.count)
    }

    func mergeScored(offline: [Place], live: [Place], hasNumber: Bool, limit: Int) -> [Place] {
        let rules = SimilarityRules(municipalities: table.municipalities)
        var keys: [DedupeKey] = []
        var rows = dedupeOffline(offline, rules: rules, keys: &keys)
        for l in live {
            let s = l.score
            if l.kind == .address || l.kind == .poi {
                rows.append(Row(place: l, base: nil, liveScore: s))
                keys.append(dedupeKey(l))
                continue
            }
            let lk = dedupeKey(l)
            if let h = keys.firstIndex(where: { rules.samePlace($0, lk) }) {
                var hit = rows[h]
                var o = hit.place
                if o.source == .offline { o.source = .both }
                o.extId = o.extId ?? l.extId
                o.lid = o.lid ?? l.lid
                o.liveRank = min(o.liveRank ?? 99, l.liveRank ?? 99)
                o.products.formUnion(l.products)
                if o.weight == nil { o.weight = l.weight }
                if let wt = l.weight, hit.base != nil { o.importance = max(o.importance, PlaceDataset.importance(wt: wt)) }
                o.mergedNames.append(l.name)
                hit.place = o
                hit.liveBonus = max(hit.liveBonus, l.liveRank.map { PlaceWeights.liveBonus(rank: $0) } ?? 0)
                hit.liveScore = max(hit.liveScore ?? -1e9, s)
                rows[h] = hit
                keys[h].extId = o.extId
                keys[h].isRail = o.products.isRail
            } else {
                var c = l
                c.source = .live
                rows.append(Row(place: c, base: nil, liveScore: s))
                keys.append(lk)
            }
        }
        var scored = rows.map { r -> (Double, Place) in
            var p = r.place
            p.score = r.score
            return (r.score, p)
        }
        scored.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            if a.1.importance != b.1.importance { return a.1.importance > b.1.importance }
            let la = a.1.name.unicodeScalars.count, lb = b.1.name.unicodeScalars.count
            if la != lb { return la < lb }
            if a.1.name != b.1.name { return a.1.name.unicodeScalars.lexicographicallyPrecedes(b.1.name.unicodeScalars) }
            return a.1.id.unicodeScalars.lexicographicallyPrecedes(b.1.id.unicodeScalars)
        }
        let cap: [PlaceKind: Int] = [.address: hasNumber ? 5 : 2,
                                     .poi: scored.first?.1.kind == .poi ? 5 : 3,
                                     .town: 2]
        var seen: [PlaceKind: Int] = [:]
        var townNames = Set<String>()
        var top: [Place] = [], overflow: [Place] = []
        for (_, p) in scored {
            if p.kind == .town {
                let key = PlaceNormalizer.key(p.name)
                if !townNames.insert(key).inserted { overflow.append(p); continue }
            }
            if let c = cap[p.kind] {
                seen[p.kind, default: 0] += 1
                if seen[p.kind]! > c { overflow.append(p); continue }
            }
            top.append(p)
        }
        return Array((top + overflow).prefix(max(0, limit)))
    }

    /// Whether two places are the same physical place under the dedupe rules D0–D4 (SUGGEST_SPEC §6.6).
    public func isSamePlace(_ a: Place, _ b: Place) -> Bool {
        SimilarityRules(municipalities: table.municipalities).samePlace(dedupeKey(a), dedupeKey(b))
    }
}
