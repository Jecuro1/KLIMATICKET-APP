import Foundation

/// Runtime merge of the official layer (places.bin) and the optional OSM layer (stops_osm.bin), docs/ENRICH_SPEC.md
/// §1.6 rules M1–M8. Built once with the index and immutable afterwards (thread-safe, like `PlaceIndex`).
///
/// Storage is flat (§1.9): the decoded `LSTP` / `TAGS` / `GTAG` bytes with per-stop offsets, the merged line catalogue
/// and the META lookups. `Place` values (`lines`, `tags`) are materialised per result row only.
/// Stop index = position in places.bin `RECS` (`PlaceRecord.stopIndex`).
final class PlaceEnrichment: @unchecked Sendable {
    let stopCount: Int
    /// RECS order.
    let stopIDs: [String]
    /// State of each stop as an index into `PlaceDataset.stateCodes` (0xFF = unknown).
    let stopStateCodes: [UInt8]
    let stopGKZ: [UInt32]
    let stopGem: [UInt16]

    let catalog: SkiAreaCatalog
    let lines: LineCatalog
    let hasOSMLayer: Bool

    /// Stop → lines of each layer, with the layer's LNAM headsign table.
    private let lstp: [(section: PerStopSection, names: [String])]
    private let officialTags: TagLayer?
    private let osmTags: TagLayer?
    private let gemeindeTags: GemeindeTags?
    /// RPRD: stop index → rail category mask (sorted by stop).
    private let railStops: [Int32]
    private let railMasks: [UInt32]
    /// M6 plates of the META `railCats`, presentation precomputed (bit → synthetic line).
    private let railLines: [RailCategoryLine]

    struct RailCategoryLine {
        var line: LineRef
        var dedupe: Int32
        var rank: Int32
        var kind: LineKind
        var category: String
    }

    /// Area entities "ski:<id>" (tag confidence ≥ 70), "region:<id>" and "landscape:<id>" (≥ 80) with their member
    /// stops (ascending) and confidences; per stop a CSR list of its entities (search context words, §2.4).
    let entityNames: [String]
    let entityIndex: [String: Int32]
    let entityStops: [[Int32]]
    let entityConfidence: [[UInt8]]
    let stopEntityStart: [Int32]
    let stopEntities: [Int32]
    let stopsWithLines: Int

    init(stops: [PlaceRecord], official: PlaceLayer, osm: PlaceLayer?) {
        let n = official.nStopRecords
        var ids = [String](repeating: "", count: n), names = [String](repeating: "", count: n)
        var states = [UInt8](repeating: 0xFF, count: n)
        var gkz = [UInt32](repeating: 0, count: n), gem = [UInt16](repeating: 0xFFFF, count: n)
        for r in stops where r.stopIndex >= 0 && Int(r.stopIndex) < n {
            let i = Int(r.stopIndex)
            ids[i] = r.id
            names[i] = r.name
            states[i] = PlaceDataset.stateCodes.firstIndex(of: r.state).map(UInt8.init) ?? 0xFF
            gkz[i] = r.gkz
            gem[i] = r.gemIndex
        }
        stopCount = n
        stopIDs = ids
        stopStateCodes = states
        stopGKZ = gkz
        stopGem = gem

        let metaO = official.metaJSON, metaX = osm?.metaJSON
        let cat = SkiAreaCatalog(official: metaO, osm: metaX)
        catalog = cat
        let lineCatalog = LineCatalog(official: official, osm: osm, meta: cat, stopIDs: ids, stopNames: names)
        lines = lineCatalog
        hasOSMLayer = osm != nil
        /// Dedupe id of a key outside the catalogue: the catalogue's, else a negative id unique in `local`.
        func outsideID(_ key: String, _ local: inout [String: Int32]) -> Int32 {
            if let x = lineCatalog.dedupeIDs[key] { return x }
            if let x = local[key] { return x }
            let x = Int32(-1_000_000 - local.count)
            local[key] = x
            return x
        }
        func rankOf(_ key: LinePlateOrder.SortKey) -> Int32 { lineCatalog.rank(of: key) }

        var lstp: [(PerStopSection, [String])] = []
        if let s = PerStopSection.lstp(official.section("LSTP"), stops: n) {
            lstp.append((s, LineCatalog.nameTable(official, strings: official.section("STRS") ?? [])))
        }
        if let osm, let s = PerStopSection.lstp(osm.section("LSTP"), stops: n) {
            lstp.append((s, LineCatalog.nameTable(osm, strings: osm.section("STRS") ?? [])))
        }
        self.lstp = lstp
        officialTags = TagLayer(layer: official, stops: n, meta: metaO)
        osmTags = TagLayer(layer: osm, stops: n, meta: metaX)
        gemeindeTags = GemeindeTags(official.section("GTAG"), gemeinden: official.nGemeinden, meta: metaO)

        var rs: [(Int32, UInt32)] = []
        if let r = official.section("RPRD") {
            for k in 0..<(r.count / 6) {
                let s = Int(Bytes.u16(r, 6 * k))
                if s < n { rs.append((Int32(s), Bytes.u32(r, 6 * k + 2))) }
            }
        }
        rs.sort { $0.0 < $1.0 }
        railStops = rs.map(\.0)
        railMasks = rs.map(\.1)
        var localKeys: [String: Int32] = [:]
        railLines = cat.railCategories.prefix(32).map { c in
            var line = LineRef(id: "cat:\(c)", ref: c, mode: .rail, network: .oebb, sources: [.timetable], isSynthetic: true)
            line.key = LineRef.persistentKey(network: .oebb, mode: .rail, ref: c)
            let pres = LineCatalog.presentation(of: line, services: [])
            let dedupe = outsideID(pres.key, &localKeys)
            return RailCategoryLine(line: line, dedupe: dedupe, rank: rankOf(pres.sort),
                                    kind: pres.kind, category: Self.plateCategory(pres.sort.text))
        }

        // membership pass (stops(inSkiArea:), stops(inRegion:), context words): value indices, no string work per tag
        var entityIndex: [String: Int32] = [:], entityNames: [String] = []
        var entityStops: [[Int32]] = [], entityConf: [[UInt8]] = []
        var start: [Int32] = [0], ents: [Int32] = []
        start.reserveCapacity(n + 1)
        var withLines = 0
        let gemTags = gemeindeTags, offTags = officialTags, xTags = osmTags
        let railSet = Set(rs.map(\.0))
        /// Per layer: value index → entity id per key kind (0 ski, 1 region, 2 landscape), -2 = not resolved yet.
        func cache(_ count: Int) -> [[Int32]] { [[Int32]](repeating: [Int32](repeating: -2, count: count), count: 3) }
        var offCache = cache(offTags?.vals.count ?? 0), gemCache = cache(gemTags?.vals.count ?? 0)
        var xCache = cache(xTags?.vals.count ?? 0)
        var mine: [Int32] = []
        for i in 0..<n {
            mine.removeAll(keepingCapacity: true)
            func visit(_ key: TagKey, _ v: Int, _ conf: Int, _ vals: [String], _ cache: inout [[Int32]]) {
                let kind: Int, prefix: String
                switch key {
                case .ski where conf >= PlaceTags.badgeMinConfidence: (kind, prefix) = (0, "ski:")
                case .region where conf >= PlaceTags.regionMinConfidence: (kind, prefix) = (1, "region:")
                case .landscape where conf >= PlaceTags.regionMinConfidence: (kind, prefix) = (2, "landscape:")
                default: return
                }
                var e = cache[kind][v]
                if e == -2 {
                    let name = prefix + vals[v]
                    if let x = entityIndex[name] { e = x } else {
                        e = Int32(entityNames.count)
                        entityIndex[name] = e
                        entityNames.append(name)
                        entityStops.append([])
                        entityConf.append([])
                    }
                    cache[kind][v] = e
                }
                let c = UInt8(clamping: conf)
                if entityStops[Int(e)].last == Int32(i) {
                    let k = entityConf[Int(e)].count - 1
                    if c > entityConf[Int(e)][k] { entityConf[Int(e)][k] = c }
                } else {
                    entityStops[Int(e)].append(Int32(i))
                    entityConf[Int(e)].append(c)
                }
                if !mine.contains(e) { mine.append(e) }
            }
            if let offTags {
                offTags.forEachIndex(i) { visit($0, $1, $2, offTags.vals, &offCache) }
                if !offTags.overridesGemeinde(i), let gemTags {
                    gemTags.forEachIndex(gemeinde: Int(gem[i])) { visit($0, $1, $2, gemTags.vals, &gemCache) }
                }
            } else if let gemTags {
                gemTags.forEachIndex(gemeinde: Int(gem[i])) { visit($0, $1, $2, gemTags.vals, &gemCache) }
            }
            if let xTags { xTags.forEachIndex(i) { visit($0, $1, $2, xTags.vals, &xCache) } }
            ents.append(contentsOf: mine)
            start.append(Int32(ents.count))
            if lstp.contains(where: { $0.0.count(i) > 0 }) || railSet.contains(Int32(i)) { withLines += 1 }
        }
        self.entityNames = entityNames
        self.entityIndex = entityIndex
        self.entityStops = entityStops
        entityConfidence = entityConf
        stopEntityStart = start
        stopEntities = ents
        stopsWithLines = withLines
    }

    /// Stops of a ski area with tag confidence ≥ 70 (ascending stop index).
    func skiMembers(_ id: String) -> [(stop: Int32, confidence: UInt8)] {
        guard let e = entityIndex["ski:" + id].map(Int.init) else { return [] }
        return zip(entityStops[e], entityConfidence[e]).map { (stop: $0.0, confidence: $0.1) }
    }

    /// Stops of a tourism region or landscape with tag confidence ≥ 80 (ascending stop index).
    func regionMembers(_ id: String) -> [Int32] {
        let a = entityIndex["region:" + id].map { entityStops[Int($0)] } ?? []
        let b = entityIndex["landscape:" + id].map { entityStops[Int($0)] } ?? []
        return b.isEmpty ? a : Array(Set(a + b)).sorted()
    }

    // MARK: row cache

    /// Compact lines + tags of the stops shown in rows. Typing re-shows the same stops on every keystroke; bounded
    /// (cleared when full), lock-protected like `NameKeyCache`.
    private let rowLock = NSLock()
    private var rowCache: [Int32: (lines: [LineRef], tags: PlaceTags)] = [:]
    static let rowCacheLimit = 2_048

    /// `compactLines(i)` and `tags(i)`, memoised.
    func rowFacts(_ i: Int) -> (lines: [LineRef], tags: PlaceTags) {
        guard i >= 0, i < stopCount else { return ([], .empty) }
        rowLock.lock()
        if let hit = rowCache[Int32(i)] { rowLock.unlock(); return hit }
        rowLock.unlock()
        let facts = (lines: compactLines(i), tags: tags(i))
        rowLock.lock()
        if rowCache.count >= Self.rowCacheLimit { rowCache.removeAll(keepingCapacity: true) }
        rowCache[Int32(i)] = facts
        rowLock.unlock()
        return facts
    }

    // MARK: tags (M5)

    /// Every tag of stop `i` (official + Gemeinde defaults + OSM layer).
    func tags(_ i: Int) -> PlaceTags {
        guard i >= 0, i < stopCount else { return .empty }
        var b = PlaceTagsBuilder()
        let cat = catalog
        if let t = officialTags {
            t.forEach(i) { b.add($0, catalog: cat) }
            if !t.overridesGemeinde(i) { gemeindeTags?.forEach(gemeinde: Int(stopGem[i])) { b.add($0, catalog: cat) } }
        } else {
            gemeindeTags?.forEach(gemeinde: Int(stopGem[i])) { b.add($0, catalog: cat) }
        }
        osmTags?.forEach(i) { b.add($0, catalog: cat) }
        return b.finish(state: stopState(i), gkz: stopGKZ[i] == 0 ? nil : Int(stopGKZ[i]),
                        catalog: cat)
    }

    /// State code of stop i ("V", "NÖ", "X"), nil if unknown.
    func stopState(_ i: Int) -> String? {
        guard i >= 0, i < stopCount else { return nil }
        let c = Int(stopStateCodes[i])
        return c < PlaceDataset.stateCodes.count ? PlaceDataset.stateCodes[c] : nil
    }

    /// Tags a town carries (§2.2): ski areas, regions and landscapes of its main stop, the town's own state,
    /// Gemeinde and KlimaTicket default.
    func townTags(mainStop: Int?, state: String?, gkz: UInt32) -> PlaceTags {
        var t = PlaceTags()
        if let m = mainStop {
            let s = rowFacts(m).tags
            t.skiAreas = s.skiAreas
            t.skiAlliances = s.skiAlliances
            t.regions = s.regions
            t.landscapes = s.landscapes
        }
        if gkz > 0 {
            t.gkz = Int(gkz)
            t.bezirk = SkiAreaCatalog.bezirk(gkz: Int(gkz))
            t.wienBezirk = SkiAreaCatalog.wienBezirk(gkz: Int(gkz))
        }
        t.klimaTicket = PlaceTagsBuilder.klimaTicket(nil, state: state, catalog: catalog)
        return t
    }

    /// Every raw tag of stop i in layer order (official, Gemeinde defaults, OSM), lift values resolved to
    /// (name, role). Diagnostics and the spot-check tests (AT-D5); the app uses `tags(_:)`.
    func rawTags(_ i: Int) -> [(key: String, value: String, confidence: Int, distance: Int?, role: String?)] {
        guard i >= 0, i < stopCount else { return [] }
        var out: [(key: String, value: String, confidence: Int, distance: Int?, role: String?)] = []
        let lifts = catalog.lifts
        func visit(_ t: RawTag) {
            if t.key == .lift, t.value.hasPrefix("#lift"), let k = Int(t.value.dropFirst(5)), k >= 0, k < lifts.count {
                out.append((t.key.rawValue, lifts[k].name, t.confidence, t.distance, lifts[k].role.rawValue))
            } else {
                out.append((t.key.rawValue, t.value, t.confidence, t.distance, nil))
            }
        }
        if let t = officialTags {
            t.forEach(i, visit)
            if !t.overridesGemeinde(i) { gemeindeTags?.forEach(gemeinde: Int(stopGem[i]), visit) }
        } else {
            gemeindeTags?.forEach(gemeinde: Int(stopGem[i]), visit)
        }
        osmTags?.forEach(i, visit)
        return out
    }

    /// Services of stop i (only these are needed to classify its lines).
    func services(_ i: Int) -> [PlaceService] {
        guard i >= 0, i < stopCount else { return [] }
        var out: [PlaceService] = []
        func visit(_ t: RawTag) {
            if t.key == .service, let s = PlaceService(rawValue: t.value), !out.contains(s) { out.append(s) }
        }
        officialTags?.forEach(i, visit)
        osmTags?.forEach(i, visit)
        return out
    }

    // MARK: lines (M3, M4, M6, M8)

    /// One line of a stop while merging: catalogue index (or `-1 - k` for the k-th synthetic line), presentation
    /// facts as integers (dedupe id, display rank), and the per-stop facts. `LineRef`s are materialised at the end.
    private struct Row {
        var line: Int32
        var dedupe: Int32
        var rank: Int32
        var kind: LineKind
        var category: String
        var confidence: LineConfidence
        var sources: LineSources
        var directions: [String]
        var next: [String]
        var position: Int32
    }

    /// Every line of stop `i` for the detail (M3 dedupe, M4 successor, M6 rail categories), display-sorted.
    func stopLines(_ i: Int) -> [StopLine] {
        let (rows, synth) = merge(i, details: true)
        return rows.map {
            StopLine(line: materialise($0, synth), directions: $0.directions, nextStopIDs: $0.next, confidence: $0.confidence)
        }
    }

    /// M8 subset: timetable-confirmed lines, special services of any source (Skibus, Wanderbus, Nachtbus, Rufbus) and,
    /// when the stop has no timetable line at all, the OSM-only lines. Display-sorted.
    func compactLines(_ i: Int) -> [LineRef] {
        let (rows, synth) = merge(i, details: false)
        let hasTimetable = rows.contains { $0.confidence >= .timetable }
        var out: [LineRef] = []
        out.reserveCapacity(rows.count)
        for r in rows where !hasTimetable || r.confidence >= .timetable || Self.specialKinds.contains(r.kind) {
            out.append(materialise(r, synth))
        }
        return out
    }

    static let specialKinds: Set<LineKind> = [.skibus, .wanderbus, .nachtbus, .rufbus]

    private func materialise(_ r: Row, _ synth: [LineRef]) -> LineRef {
        var l = r.line >= 0 ? lines.lines[Int(r.line)] : synth[Int(-1 - r.line)]
        if !l.sources.isSuperset(of: r.sources) { l.sources.formUnion(r.sources) }
        return l
    }

    /// Lines of stop `i`, deduped (M3) and sorted; `details` adds headsigns and next stops.
    private func merge(_ i: Int, details: Bool) -> (rows: [Row], synth: [LineRef]) {
        guard i >= 0, i < stopCount else { return ([], []) }
        let cat = lines
        var rows: [Row] = []
        var synth: [LineRef] = []
        var services: [PlaceService]?
        var localIDs: [String: Int32] = [:]
        /// Dedupe id of a key outside the catalogue (negative, unique within this stop).
        func id(of key: String) -> Int32 {
            if let x = cat.dedupeIDs[key] { return x }
            if let x = localIDs[key] { return x }
            let x = Int32(-1 - localIDs.count)
            localIDs[key] = x
            return x
        }
        for (layer, names) in lstp {
            let b = layer.bytes
            var p = Int(layer.offsets[i])
            for _ in 0..<layer.count(i) {
                let raw = Int(Bytes.u16(b, p)), bits = b[p + 2]
                let nTo = Int((bits >> 2) & 3), nNext = Int((bits >> 4) & 3)
                let entry = p
                p += 3 + 2 * nTo + 2 * nNext
                guard raw < cat.count, let li = cat.resolved(raw) else { continue }          // M4
                let conf: LineConfidence = (bits & 3) >= 3 ? .live : ((bits & 3) == 2 ? .timetable : .osmOnly)
                var dedupe = cat.dedupeID[li], rank = cat.rank[li], kind = cat.kinds[li], category = cat.plateCategory[li]
                if cat.serviceSensitive[li] {
                    if services == nil { services = self.services(i) }
                    if let sv = services, !sv.isEmpty {
                        let pres = LineCatalog.presentation(of: cat.lines[li], services: sv)
                        if pres.kind != kind {
                            kind = pres.kind
                            dedupe = id(of: pres.key)
                            rank = cat.rank(of: pres.sort)
                            category = Self.plateCategory(pres.sort.text)
                        }
                    }
                }
                var to: [String] = [], next: [String] = []
                if details {
                    for k in 0..<nTo {
                        let h = Int(Bytes.u16(b, entry + 3 + 2 * k))
                        if h < names.count, !names[h].isEmpty { to.append(PlaceNames.display(names[h])) }
                    }
                    for k in 0..<nNext {
                        let s = Int(Bytes.u16(b, entry + 3 + 2 * nTo + 2 * k))
                        if s < stopCount { next.append(stopIDs[s]) }
                    }
                }
                if let h = rows.firstIndex(where: { $0.dedupe == dedupe }) {                   // M3
                    for d in to where rows[h].directions.count < 3 && !rows[h].directions.contains(d) {
                        rows[h].directions.append(d)
                    }
                    for s in next where rows[h].next.count < 3 && !rows[h].next.contains(s) { rows[h].next.append(s) }
                    if conf > rows[h].confidence { rows[h].confidence = conf }
                    rows[h].sources.formUnion(cat.lines[li].sources)
                    continue
                }
                rows.append(Row(line: Int32(li), dedupe: dedupe, rank: rank, kind: kind, category: category,
                                confidence: conf, sources: [], directions: to, next: next, position: Int32(rows.count)))
            }
        }
        // M6: rail categories of RPRD as plates, unless a plate of that category is already shown
        if let mask = railMask(i) {
            for (bit, rc) in railLines.enumerated() where mask & (1 << UInt32(bit)) != 0 {
                if let h = rows.firstIndex(where: { $0.dedupe == rc.dedupe }) {
                    rows[h].confidence = max(rows[h].confidence, .timetable)       // OSM „RJ“ + RPRD „RJ“
                    rows[h].sources.insert(.timetable)
                    continue
                }
                if rows.contains(where: { $0.kind == rc.kind && $0.category == rc.category }) { continue }
                synth.append(rc.line)
                rows.append(Row(line: Int32(-synth.count), dedupe: rc.dedupe, rank: rc.rank, kind: rc.kind,
                                category: rc.category, confidence: .timetable, sources: [], directions: [], next: [],
                                position: Int32(rows.count)))
            }
        }
        if rows.count > 1 { rows.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.position < $1.position } }
        return (rows, synth)
    }

    /// Category letters of a plate text ("REX1" → "REX", "S" → "S", "EN" → "EN").
    static func plateCategory(_ text: String) -> String { RailRef(text).category.uppercased() }

    func railMask(_ i: Int) -> UInt32? {
        var lo = 0, hi = railStops.count
        let x = Int32(i)
        while lo < hi {
            let mid = (lo + hi) >> 1
            if railStops[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo < railStops.count && railStops[lo] == x ? railMasks[lo] : nil
    }

    /// Area entities of stop i (context words).
    func entities(_ i: Int) -> ArraySlice<Int32> {
        guard i >= 0, i < stopCount else { return [] }
        return stopEntities[Int(stopEntityStart[i])..<Int(stopEntityStart[i + 1])]
    }

    // MARK: v1 fallback

    /// v1 files carry a comma separated „lines“ string per stop (EXTR tag 5): best-effort `LineRef`s (no network,
    /// operator or termini), so rows still show plates until the v2 data ships.
    static func legacyLines(_ s: String, products: Int) -> [LineRef] {
        let refs = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let p = PlaceProducts(rawValue: products)
        let lines = refs.map { ref -> LineRef in
            let r = RailRef(ref), c = r.category.uppercased()
            let mode: LineMode
            if c == "U", !r.number.isEmpty { mode = .subway }
            else if c == "S", !r.number.isEmpty, p.contains(.suburban) { mode = .sBahn }
            else if (LineKind.fernCategories.contains(c) || LineKind.nachtCategories.contains(c)
                     || LineKind.regioCategories.contains(c)) && p.isRail { mode = .rail }
            else if p.contains(.tram) && !p.contains(.bus) { mode = .tram }
            else if p.contains(.bus) || p.contains(.railReplacement) { mode = .bus }
            else if p.contains(.ship) { mode = .ship }
            else if p.isRail { mode = .rail }
            else { mode = .bus }
            return LineRef(id: "v1:\(ref)", ref: ref, mode: mode, sources: [.oevgk])
        }
        return LinePlateOrder.sorted(lines)
    }
}
