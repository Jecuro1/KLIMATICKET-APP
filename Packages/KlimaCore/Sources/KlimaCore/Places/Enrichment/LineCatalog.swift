import Foundation

/// The merged line catalogue (docs/ENRICH_SPEC.md §1.4 `LCAT`/`LNAM`, §1.5 `LCAT`/`LPAT`, rules M1/M2): official lines
/// of places.bin at indices 0..<nOfficial, OSM-only lines of stops_osm.bin after them (merged index = nOfficial +
/// position), with the OSM patches applied to the official lines. Every line is materialised once at load as a
/// `LineRef`, together with its presentation facts (plate family, dedupe key, sort key) so per-stop work stays cheap.
final class LineCatalog: Sendable {
    let lines: [LineRef]
    /// Plate family without stop services.
    let kinds: [LineKind]
    /// `LinePlateText.dedupeKey` without stop services (M3).
    let dedupeKeys: [String]
    /// Display sort key without stop services.
    let sortKeys: [LinePlateOrder.SortKey]
    /// The ref has no digit: the stop's services may change the family (`LineKind.classify`).
    let serviceSensitive: [Bool]
    /// Dense id of `dedupeKeys[i]` (same key → same id); `dedupeIDs` maps every catalogue key to its id.
    let dedupeID: [Int32]
    let dedupeIDs: [String: Int32]
    /// Display rank (odd numbers in `LinePlateOrder` order); keys outside the catalogue get even ranks between.
    let rank: [Int32]
    /// Line indices in display order (binary search for keys outside the catalogue).
    let order: [Int32]
    /// Category letters of the plate at size l ("REX1" → "REX"; M6 presence check).
    let plateCategory: [String]
    /// Merged index of the successor of a superseded line (M4), -1 none.
    let successor: [Int32]
    let nOfficial: Int
    /// Persistent key → first line with it.
    let byKey: [String: Int32]

    static let empty = LineCatalog(lines: [])

    var count: Int { lines.count }

    init(lines: [LineRef], successor: [Int32]? = nil, nOfficial: Int? = nil) {
        self.lines = lines
        self.successor = successor ?? [Int32](repeating: -1, count: lines.count)
        self.nOfficial = nOfficial ?? lines.count
        var kinds: [LineKind] = [], keys: [String] = [], sorts: [LinePlateOrder.SortKey] = [], sens: [Bool] = []
        var cats: [String] = [], ids: [Int32] = []
        kinds.reserveCapacity(lines.count)
        var byKey: [String: Int32] = [:], idOf: [String: Int32] = [:]
        for (i, l) in lines.enumerated() {
            let k = LineKind.classify(l, services: [])
            let plate = LinePlateText.text(for: l, kind: k, size: .l)
            let key = LinePlateText.dedupeKey(kind: k, plate: plate)
            kinds.append(k)
            keys.append(key)
            sorts.append(LinePlateOrder.SortKey(kind: k, text: plate.text, ref: l.ref))
            sens.append(!l.ref.utf8.contains { $0 >= 48 && $0 <= 57 } && !l.ref.contains(where: \.isNumber))
            cats.append(RailRef(plate.text).category.uppercased())
            if let id = idOf[key] { ids.append(id) } else {
                let id = Int32(idOf.count)
                idOf[key] = id
                ids.append(id)
            }
            if byKey[l.key] == nil { byKey[l.key] = Int32(i) }
        }
        // display order of every line once: SortKey order, with the natural-order byte forms precomputed
        let textBytes = sorts.map { LinePlateOrder.naturalBytes($0.text) }, refBytes = sorts.map { LinePlateOrder.naturalBytes($0.ref) }
        func less(_ a: Int, _ b: Int) -> Bool {
            let x = sorts[a], y = sorts[b]
            if x.family != y.family { return x.family < y.family }
            if x.category != y.category { return x.category < y.category }
            if let ta = textBytes[a], let tb = textBytes[b], let ra = refBytes[a], let rb = refBytes[b] {
                let c = LinePlateOrder.naturalCompare(bytes: ta, tb)
                if c != 0 { return c < 0 }
                let d = LinePlateOrder.naturalCompare(bytes: ra, rb)
                return d != 0 ? d < 0 : a < b
            }
            return x == y ? a < b : x < y
        }
        let order = sorts.indices.sorted(by: less)
        var rank = [Int32](repeating: 0, count: lines.count)
        for (pos, i) in order.enumerated() { rank[i] = Int32(2 * pos + 1) }
        self.kinds = kinds
        dedupeKeys = keys
        sortKeys = sorts
        serviceSensitive = sens
        self.byKey = byKey
        dedupeID = ids
        dedupeIDs = idOf
        self.rank = rank
        self.order = order.map { Int32($0) }
        plateCategory = cats
    }

    /// Rank of a sort key that is not a catalogue line's own key (synthetic rail categories, reclassified lines):
    /// equal to a catalogue line with the same key, else an even rank between its neighbours.
    func rank(of key: LinePlateOrder.SortKey) -> Int32 {
        var lo = 0, hi = order.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if sortKeys[Int(order[mid])] < key { lo = mid + 1 } else { hi = mid }
        }
        if lo < order.count, sortKeys[Int(order[lo])] == key { return rank[Int(order[lo])] }
        return Int32(2 * lo)
    }

    /// Family, dedupe key and sort key of line `i` at a stop with `services`.
    func presentation(_ i: Int, services: [PlaceService]) -> (kind: LineKind, key: String, sort: LinePlateOrder.SortKey) {
        if services.isEmpty || !serviceSensitive[i] { return (kinds[i], dedupeKeys[i], sortKeys[i]) }
        return Self.presentation(of: lines[i], services: services)
    }

    static func presentation(of line: LineRef, services: [PlaceService])
        -> (kind: LineKind, key: String, sort: LinePlateOrder.SortKey) {
        let k = LineKind.classify(line, services: services)
        let plate = LinePlateText.text(for: line, kind: k, size: .l)
        return (k, LinePlateText.dedupeKey(kind: k, plate: plate), LinePlateOrder.SortKey(kind: k, text: plate.text, ref: line.ref))
    }

    // MARK: decoding

    /// One raw LCAT entry (24 B).
    struct Entry {
        var refOff: Int
        var nameOff: Int
        var op: Int
        var mode: Int
        var net: Int
        var flags: UInt16
        var states: UInt16
        var sources: UInt8
        var terminiKind: UInt8
        var successor: Int
        var termFrom: Int
        var termTo: Int
    }

    static func entries(_ lcat: [UInt8]?) -> [Entry] {
        guard let c = lcat, c.count >= 24 else { return [] }
        return (0..<(c.count / 24)).map { k in
            let o = 24 * k
            return Entry(refOff: Int(Bytes.u32(c, o)), nameOff: Int(Bytes.u32(c, o + 4)), op: Int(Bytes.u16(c, o + 8)),
                         mode: Int(c[o + 10]), net: Int(c[o + 11]), flags: Bytes.u16(c, o + 12), states: Bytes.u16(c, o + 14),
                         sources: c[o + 16], terminiKind: c[o + 17], successor: Int(Bytes.u16(c, o + 18)),
                         termFrom: Int(Bytes.u16(c, o + 20)), termTo: Int(Bytes.u16(c, o + 22)))
        }
    }

    /// Builds the merged catalogue. `stops` resolves termini of kind 2 (stop record index → id, name).
    convenience init(official: PlaceLayer?, osm: PlaceLayer?, meta: SkiAreaCatalog, stopIDs: [String], stopNames: [String]) {
        let off = Self.entries(official?.section("LCAT"))
        let ext = Self.entries(osm?.section("LCAT"))
        let offStrings = official?.section("STRS") ?? [], osmStrings = osm?.section("STRS") ?? []
        let offNames = Self.nameTable(official, strings: offStrings), osmNames = Self.nameTable(osm, strings: osmStrings)

        struct Building {
            var ref: String
            var name: String?
            var op: Int
            var mode: LineMode
            var net: TransitNetwork?
            var flags: LineFlags
            var states: [String]
            var sources: LineSources
            var termini: LineTermini?
            var successor: Int
        }

        func flags(_ raw: UInt16) -> LineFlags {
            var f: LineFlags = []
            for b in 0..<16 where raw & (1 << UInt16(b)) != 0 {
                if b < meta.flagBits.count { f.formUnion(meta.flagBits[b]) }
            }
            return f
        }

        func states(_ raw: UInt16) -> [String] {
            PlaceDataset.stateCodes.enumerated().compactMap { raw & (1 << UInt16($0.offset)) != 0 ? $0.element : nil }
        }

        func termini(kind: UInt8, from: Int, to: Int, names: [String]) -> LineTermini? {
            func one(_ v: Int) -> (String?, String?) {
                guard v != 0xFFFF else { return (nil, nil) }
                switch kind {
                case 2: return v < stopIDs.count ? (stopNames[v], stopIDs[v]) : (nil, nil)
                case 1: return v < names.count ? (Self.nonEmpty(names[v]), nil) : (nil, nil)
                default: return (nil, nil)
                }
            }
            guard kind == 1 || kind == 2 else { return nil }
            let a = one(from), b = one(to)
            guard a.0 != nil || b.0 != nil else { return nil }
            return LineTermini(from: a.0, to: b.0, fromStopID: a.1, toStopID: b.1)
        }

        func build(_ e: Entry, strings: [UInt8], names: [String], isOSM: Bool) -> Building {
            var src = LineSources(rawValue: e.sources & 0x0F)
            if isOSM { src.insert(.osm) }
            return Building(ref: Bytes.cString(strings, e.refOff), name: Self.nonEmpty(Bytes.cString(strings, e.nameOff)),
                            op: e.op, mode: (e.mode < meta.modes.count ? meta.modes[e.mode] : nil) ?? .other,
                            net: e.net < meta.nets.count ? meta.nets[e.net] : nil, flags: flags(e.flags),
                            states: states(e.states), sources: src,
                            termini: termini(kind: e.terminiKind, from: e.termFrom, to: e.termTo, names: names),
                            successor: e.successor == 0xFFFF ? -1 : e.successor)
        }

        var all = off.map { build($0, strings: offStrings, names: offNames, isOSM: false) }
        all += ext.map { build($0, strings: osmStrings, names: osmNames, isOSM: true) }

        // M2: OSM patches fill what the official layer lacks and OR the flags
        if let pat = osm?.section("LPAT"), pat.count >= 16 {
            for k in 0..<(pat.count / 16) {
                let o = 16 * k
                let li = Int(Bytes.u16(pat, o)), mask = pat[o + 2], tk = pat[o + 3]
                guard li < off.count else { continue }
                if mask & 1 != 0, all[li].op == 0xFFFF { all[li].op = Int(Bytes.u16(pat, o + 4)) }
                if mask & 2 != 0, all[li].name == nil {
                    all[li].name = Self.nonEmpty(Bytes.cString(osmStrings, Int(Bytes.u32(pat, o + 6))))
                }
                if mask & 4 != 0, all[li].termini == nil {
                    all[li].termini = termini(kind: tk, from: Int(Bytes.u16(pat, o + 10)), to: Int(Bytes.u16(pat, o + 12)),
                                              names: osmNames)
                }
                if mask & 8 != 0 { all[li].flags.formUnion(flags(Bytes.u16(pat, o + 14))) }
            }
        }

        var lines: [LineRef] = []
        lines.reserveCapacity(all.count)
        var succ: [Int32] = []
        for (i, b) in all.enumerated() {
            let op = b.op != 0xFFFF && b.op < meta.operators.count ? meta.operators[b.op] : nil
            let s = b.successor >= 0 && b.successor < all.count && b.successor != i ? b.successor : -1
            lines.append(LineRef(id: "l:\(i)", ref: b.ref, mode: b.mode, network: b.net, operatorName: op?.display,
                                 operatorLegalName: op?.name, name: b.name, termini: b.termini, flags: b.flags,
                                 states: b.states, sources: b.sources, successorRef: s >= 0 ? all[s].ref : nil))
            succ.append(Int32(s))
        }
        self.init(lines: lines, successor: succ, nOfficial: off.count)
    }

    /// LNAM: `u32 STRS offset` per entry.
    static func nameTable(_ layer: PlaceLayer?, strings: [UInt8]) -> [String] {
        guard let l = layer?.section("LNAM"), l.count >= 4 else { return [] }
        return (0..<(l.count / 4)).map { Bytes.cString(strings, Int(Bytes.u32(l, 4 * $0))) }
    }

    static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    /// The successor a superseded line is shown as (M4), following at most 4 links; nil = hide the line.
    func resolved(_ i: Int) -> Int? {
        var cur = i
        for _ in 0..<4 {
            guard lines[cur].flags.contains(.superseded) else { return cur }
            let s = Int(successor[cur])
            guard s >= 0 else { return nil }
            cur = s
        }
        return lines[cur].flags.contains(.superseded) ? nil : cur
    }
}

/// Little-endian readers over decoded section bytes (bounds are checked by the callers).
enum Bytes {
    @inline(__always) static func u16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }

    @inline(__always) static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    /// NUL-terminated UTF-8 string at `o` ("" for offset 0 or out of range).
    static func cString(_ b: [UInt8], _ o: Int) -> String {
        guard o > 0, o < b.count else { return "" }
        var e = o
        while e < b.count && b[e] != 0 { e += 1 }
        return b.withUnsafeBufferPointer { String(decoding: UnsafeBufferPointer(rebasing: $0[o..<e]), as: UTF8.self) }
    }
}

extension LineFlags {
    /// German season / day notes of a line (M7): „nur im Winter“, „nur im Sommer“, „Schultage“, „Saison“.
    /// `schooldays?`, `ski_candidate` and `superseded` never show.
    public var displayNotes: [String] {
        var out: [String] = []
        if contains(.winter) { out.append("nur im Winter") }
        if contains(.summer) { out.append("nur im Sommer") }
        if contains(.schoolDays) || contains(.schoolOrSeasonal) || contains(.school) { out.append("Schultage") }
        if contains(.seasonal) && !contains(.winter) && !contains(.summer) { out.append("Saison") }
        return out
    }
}
