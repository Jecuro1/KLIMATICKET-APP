import Foundation

// SUGGEST_SPEC §4.3: flat, allocation-free search structures. Used for the 60k-record offline index and, with
// the same code, for the handful of live LocMatch rows of one query (so offline and live rows score identically).
//
//   recs[]                sorted by (importance desc, name, id); record id = position → postings are importance-ordered
//   forms (bytes/offsets) every index form, unique, sorted by UTF-8 bytes (= Unicode scalar order)
//   postStart/postings    CSR: record ids per form, ascending
//   recVarStart → varFactor/varSecondary/varTokStart → tokFlags/tokCanon/tokFormStart → tokForm/tokFormFac
//   trigrams              packed trigram → form ids (alphabetic forms ≥ 3 scalars), fuzzy candidates
//   exact                 canonical full name → record ids;  byID: id → record id;  grid: ~1 km cells → stop ids
final class PlaceTable: @unchecked Sendable {
    /// Plain-data per-record facts used by the scorer (no reference counting in the hot loop).
    struct RecInfo {
        var importance: Double
        var lat: Double
        var lon: Double
        var nameLen: Int32
        var kind: PlaceKind
        var foreign: Bool
        var minorLocality: Bool
        var localityExactFactor: Double
        var liveRank: Int32      // 0 = none
        var products: Int
    }

    let recs: [PlaceRecord]
    let info: [RecInfo]
    let municipalities: Set<String>

    let formBytes: [UInt8]
    let formOff: [Int32]
    let formLen: [Int32]
    let postStart: [Int32]
    let postings: [Int32]

    let recVarStart: [Int32]
    let varFactor: [Double]
    /// Token index (relative to the variant) where secondary tokens start (POI address part), or Int32.max.
    let varSecondary: [Int32]
    let varTokStart: [Int32]
    let tokFlags: [UInt8]
    let tokCanon: [Int32]
    let tokFormStart: [Int32]
    let tokForm: [Int32]
    let tokFormFac: [Double]
    /// Raw token strings per token (live tables only; plausibility filter).
    let tokRaw: [String]

    /// Flat multimap: sorted keys, CSR offsets, values (no per-key heap arrays).
    struct FlatMap<Key: Comparable> {
        var keys: [Key] = []
        var start: [Int32] = [0]
        var values: [Int32] = []

        /// Builds from (key, value) pairs; values of a key keep ascending order, duplicates removed.
        init(pairs: [(Key, Int32)]) {
            let sorted = pairs.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
            keys.reserveCapacity(sorted.count / 2)
            values.reserveCapacity(sorted.count)
            for (k, v) in sorted {
                if keys.last != k {
                    if !keys.isEmpty { start.append(Int32(values.count)) }
                    keys.append(k)
                } else if values.last == v {
                    continue
                }
                values.append(v)
            }
            if !keys.isEmpty { start.append(Int32(values.count)) }
        }
        init() {}
        init(keys: [Key], start: [Int32], values: [Int32]) {
            self.keys = keys
            self.start = start
            self.values = values
        }

        func lookup(_ k: Key) -> ArraySlice<Int32> {
            var lo = 0, hi = keys.count
            while lo < hi {
                let mid = (lo + hi) >> 1
                if keys[mid] < k { lo = mid + 1 } else { hi = mid }
            }
            guard lo < keys.count, keys[lo] == k else { return [] }
            return values[Int(start[lo])..<Int(start[lo + 1])]
        }
    }

    let trigrams: FlatMap<UInt64>
    let hasTrigrams: Bool
    /// FNV-1a hash of the canonical full name → record ids (collisions only add candidates, which are scored anyway).
    let exact: FlatMap<UInt64>
    let byID: [String: Int32]
    let grid: FlatMap<Int64>

    var formCount: Int { formLen.count }

    struct BuildOptions {
        var trigrams = true
        var grid = true
        var exact = true
        var keepRawTokens = false
    }

    init(records: [PlaceRecord], municipalities: Set<String>, options: BuildOptions = BuildOptions()) {
        self.municipalities = municipalities
        self.hasTrigrams = options.trigrams
        let recs = records.sorted { a, b in
            if a.importance != b.importance { return a.importance > b.importance }
            if a.name != b.name { return a.name.unicodeScalars.lexicographicallyPrecedes(b.name.unicodeScalars) }
            return a.id.unicodeScalars.lexicographicallyPrecedes(b.id.unicodeScalars)
        }
        self.recs = recs
        info = recs.map { r in
            RecInfo(importance: r.importance, lat: r.lat, lon: r.lon, nameLen: Int32(r.name.unicodeScalars.count), kind: r.kind,
                    foreign: (!r.country.isEmpty && r.country != "at") || r.state == "X",
                    minorLocality: r.kind == .town && PlaceWeights.minorPlaces.contains(r.localityClass ?? ""),
                    localityExactFactor: r.kind == .town ? (PlaceWeights.placeExact[r.localityClass ?? ""] ?? 1.0) : 1.0,
                    liveRank: Int32(r.liveRank ?? 0), products: r.products)
        }
        let b = Self.build(recs, municipalities, options)
        formBytes = b.formBytes
        formOff = b.formOff
        formLen = b.formLen
        postStart = b.postStart
        postings = b.postings
        recVarStart = b.recVarStart
        varFactor = b.varFactor
        varSecondary = b.varSecondary
        varTokStart = b.varTokStart
        tokFlags = b.tokFlags
        tokCanon = b.tokCanon
        tokFormStart = b.tokFormStart
        tokForm = b.tokForm
        tokFormFac = b.tokFormFac
        tokRaw = b.tokRaw
        trigrams = b.trigrams
        exact = FlatMap(pairs: b.exactPairs)
        byID = b.byID
        grid = FlatMap(pairs: b.gridPairs)
    }

    // MARK: build

    private struct Built {
        var formBytes: [UInt8] = []
        var formOff: [Int32] = [0]
        var formLen: [Int32] = []
        var postStart: [Int32] = [0]
        var postings: [Int32] = []
        var recVarStart: [Int32] = [0]
        var varFactor: [Double] = []
        var varSecondary: [Int32] = []
        var varTokStart: [Int32] = [0]
        var tokFlags: [UInt8] = []
        var tokCanon: [Int32] = []
        var tokFormStart: [Int32] = [0]
        var tokForm: [Int32] = []
        var tokFormFac: [Double] = []
        var tokRaw: [String] = []
        var trigrams = FlatMap<UInt64>()
        var exactPairs: [(UInt64, Int32)] = []
        var byID: [String: Int32] = [:]
        var gridPairs: [(Int64, Int32)] = []
    }

    private static func build(_ recs: [PlaceRecord], _ municipalities: Set<String>, _ options: BuildOptions) -> Built {
        var b = Built()
        var tokCache: [String: [PlaceToken]] = [:]
        tokCache.reserveCapacity(recs.count + recs.count / 4)
        let baseCache = PlaceNormalizer.TokenCache()
        func toks(_ s: String) -> [PlaceToken] {
            if let t = tokCache[s] { return t }
            let t = PlaceNormalizer.tokenize(s, isName: true, cache: baseCache).0
            tokCache[s] = t
            return t
        }
        // provisional form ids in first-seen order, remapped to sorted order afterwards
        var provID: [String: Int32] = [:]
        provID.reserveCapacity(recs.count)
        var provForms: [String] = []
        func intern(_ f: String) -> Int32 {
            if let id = provID[f] { return id }
            let id = Int32(provForms.count)
            provID[f] = id
            provForms.append(f)
            return id
        }
        var pairForm: [Int32] = []           // (form, record) pairs for the postings
        var pairRec: [Int32] = []
        pairForm.reserveCapacity(recs.count * 5)
        pairRec.reserveCapacity(recs.count * 5)
        var recForms: [Int32] = []
        b.tokFlags.reserveCapacity(recs.count * 4)
        b.tokForm.reserveCapacity(recs.count * 6)

        for ri in recs.indices {
            let r = recs[ri]
            let vs = variants(of: r, municipalities: municipalities, tokenize: toks)
            recForms.removeAll(keepingCapacity: true)
            for v in vs {
                b.varFactor.append(v.factor)
                b.varSecondary.append(Int32(v.secondaryFrom ?? Int(Int32.max)))
                for t in v.tokens {
                    b.tokFlags.append(t.flags)
                    for (f, fac) in t.forms {
                        let fid = intern(f)
                        b.tokForm.append(fid)
                        b.tokFormFac.append(fac)
                        if !recForms.contains(fid) { recForms.append(fid) }
                    }
                    // canonical spelling as a form id (always one of the token's own forms for name tokens)
                    b.tokCanon.append(provID[t.canonical] ?? -1)
                    b.tokFormStart.append(Int32(b.tokForm.count))
                    if options.keepRawTokens { b.tokRaw.append(t.raw) }
                }
                b.varTokStart.append(Int32(b.tokFlags.count))
            }
            b.recVarStart.append(Int32(b.varFactor.count))
            for fid in recForms {
                pairForm.append(fid)
                pairRec.append(Int32(ri))
            }
            if options.exact {
                for n in [r.name] + r.aliases {
                    b.exactPairs.append((Self.fnv1a(toks(n).map(\.canonical).joined(separator: " ")), Int32(ri)))
                }
            }
            if b.byID[r.id] == nil { b.byID[r.id] = Int32(ri) }
            if options.grid && r.kind.isStopLike { b.gridPairs.append((cellKey(r.lat, r.lon), Int32(ri))) }
        }
        // sort forms by UTF-8 bytes, remap provisional ids
        let order = provForms.indices.sorted { provForms[$0].utf8.lexicographicallyPrecedes(provForms[$1].utf8) }
        var remap = [Int32](repeating: 0, count: provForms.count)
        b.formLen.reserveCapacity(order.count)
        b.formOff.reserveCapacity(order.count + 1)
        for (newID, old) in order.enumerated() {
            remap[old] = Int32(newID)
            let f = provForms[old]
            b.formBytes.append(contentsOf: f.utf8)
            b.formOff.append(Int32(b.formBytes.count))
            b.formLen.append(Int32(f.unicodeScalars.count))
        }
        for k in b.tokForm.indices { b.tokForm[k] = remap[Int(b.tokForm[k])] }
        for k in b.tokCanon.indices where b.tokCanon[k] >= 0 { b.tokCanon[k] = remap[Int(b.tokCanon[k])] }

        // CSR postings by counting sort; records were visited in id order → each list is ascending
        var counts = [Int32](repeating: 0, count: order.count + 1)
        for k in pairForm.indices {
            let f = Int(remap[Int(pairForm[k])])
            pairForm[k] = Int32(f)
            counts[f + 1] += 1
        }
        for f in 0..<order.count { counts[f + 1] += counts[f] }
        b.postStart = counts
        var postings = [Int32](repeating: 0, count: pairForm.count)
        var fill = counts
        for k in pairForm.indices {
            let f = Int(pairForm[k])
            postings[Int(fill[f])] = pairRec[k]
            fill[f] += 1
        }
        b.postings = postings
        if options.trigrams {
            // group by trigram with a temporary slot dictionary; forms are visited in ascending id order
            var slot: [UInt64: Int32] = [:]
            var slotKeys: [UInt64] = []
            var pairSlot: [Int32] = [], pairFormID: [Int32] = []
            for (newID, old) in order.enumerated() where b.formLen[newID] >= 3 {
                let s = provForms[old]
                guard s.unicodeScalars.allSatisfy(PlaceNormalizer.isAlpha) else { continue }
                for g in trigramSet(s) {
                    let sl: Int32
                    if let x = slot[g] { sl = x } else { sl = Int32(slotKeys.count); slot[g] = sl; slotKeys.append(g) }
                    pairSlot.append(sl)
                    pairFormID.append(Int32(newID))
                }
            }
            let keyOrder = slotKeys.indices.sorted { slotKeys[$0] < slotKeys[$1] }
            var rank = [Int32](repeating: 0, count: slotKeys.count)
            for (r, sl) in keyOrder.enumerated() { rank[sl] = Int32(r) }
            var start = [Int32](repeating: 0, count: slotKeys.count + 1)
            for sl in pairSlot { start[Int(rank[Int(sl)]) + 1] += 1 }
            for k in 0..<slotKeys.count { start[k + 1] += start[k] }
            var fill = start
            var values = [Int32](repeating: 0, count: pairSlot.count)
            for k in pairSlot.indices {
                let r = Int(rank[Int(pairSlot[k])])
                values[Int(fill[r])] = pairFormID[k]
                fill[r] += 1
            }
            b.trigrams = FlatMap(keys: keyOrder.map { slotKeys[$0] }, start: start, values: values)
        }
        return b
    }

    struct Variant {
        var factor: Double
        var secondaryFrom: Int?
        var tokens: [PlaceToken]
    }

    /// Searchable variants of a record (SUGGEST_SPEC §3.6, §6.2): official name (+ "Ort X" for "X (Ort)"),
    /// aliases (0.97, or 0.85 for local aliases lacking the place prefix); addresses as "Straße Nr Ort PLZ";
    /// POIs as name + secondary address tokens.
    static func variants(of r: PlaceRecord, municipalities: Set<String>,
                         tokenize toks: (String) -> [PlaceToken]) -> [Variant] {
        var names: [(String, Double)] = nameVariants(r.name, municipalities).map { ($0, 1.0) }
        if !r.aliases.isEmpty {
            let nameToks = toks(r.name)
            let first = nameToks.first?.raw ?? ""
            let firstCanon = PlaceLexicon.canonical(first)
            for a in r.aliases {
                let at = toks(a)
                let local = r.kind.isStopLike && !first.isEmpty && !at.contains { $0.raw == first }
                    && !at.contains { $0.canonical == firstCanon }
                for n in nameVariants(a, municipalities) { names.append((n, local ? 0.85 : 0.97)) }
            }
        }
        if r.kind == .address, let reordered = addressSearchName(r.name) { names = [(reordered, 1.0)] }
        if r.kind == .poi {
            let parts = r.name.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let head = toks(PlaceNames.strippingPOICounter(parts.first ?? r.name))
            var tail = toks(parts.dropFirst().joined(separator: " "))
            for k in tail.indices {
                var f = tail[k].flags | PlaceTok.qualifier
                f &= ~PlaceTok.essential
                tail[k].flags = f
            }
            return [Variant(factor: 1.0, secondaryFrom: head.count, tokens: head + tail)]
        }
        return names.map { Variant(factor: $0.1, secondaryFrom: nil, tokens: toks($0.0)) }
    }

    /// "6020 Innsbruck, Maria-Theresien-Straße 1" → "Maria-Theresien-Straße 1 Innsbruck 6020".
    static func addressSearchName(_ name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count > 6, scalars.prefix(4).allSatisfy({ $0.isASCII && PlaceNormalizer.isDigit($0) }),
              scalars[4].properties.isWhitespace, let comma = name.firstIndex(of: ",") else { return nil }
        let plz = String(name.prefix(4))
        let ort = name[name.index(name.startIndex, offsetBy: 4)..<comma].trimmingCharacters(in: .whitespaces)
        let rest = name[name.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        guard !ort.isEmpty, !rest.isEmpty else { return nil }
        return "\(rest) \(ort) \(plz)"
    }

    /// Official name plus "Ort X" for a name "X (Ort)" when the bracket holds a known municipality.
    static func nameVariants(_ name: String, _ municipalities: Set<String>) -> [String] {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return [name] }
        let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
        guard !inner.isEmpty, !inner.contains("("), !inner.contains(")") else { return [name] }
        let i = inner.trimmingCharacters(in: .whitespaces)
        let head = name[..<open].trimmingCharacters(in: .whitespaces)
        guard !i.isEmpty, municipalities.contains(PlaceNormalizer.fold(i)) else { return [name] }
        return [name, "\(i) \(head)"]
    }

    // MARK: forms

    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    /// Form id of exactly `s`, if it is an index form.
    func formID(_ s: String) -> Int32? {
        let r = prefixRange(s)
        guard !r.isEmpty, Int(formOff[r.lowerBound + 1] - formOff[r.lowerBound]) == s.utf8.count else { return nil }
        return Int32(r.lowerBound)
    }

    @inline(__always) func formString(_ fi: Int) -> String {
        let a = Int(formOff[fi]), b = Int(formOff[fi + 1])
        return formBytes.withUnsafeBufferPointer { String(decoding: UnsafeBufferPointer(rebasing: $0[a..<b]), as: UTF8.self) }
    }

    /// Forms having `prefix` as a prefix (two binary searches over the sorted dictionary).
    func prefixRange(_ prefix: String) -> Range<Int> {
        var key = Array(prefix.utf8)
        return key.withUnsafeMutableBufferPointer { kp in
            formBytes.withUnsafeBufferPointer { fb in
                formOff.withUnsafeBufferPointer { fo in
                    let n = fo.count - 1
                    // compare form f with key: <0, 0 (equal or key is a prefix of f), >0
                    @inline(__always) func cmp(_ f: Int, prefixMode: Bool) -> Int {
                        let a = Int(fo[f]), b = Int(fo[f + 1])
                        let la = b - a, lk = kp.count
                        let m = min(la, lk)
                        var i = 0
                        while i < m {
                            let x = fb[a + i], y = kp[i]
                            if x != y { return x < y ? -1 : 1 }
                            i += 1
                        }
                        if la < lk { return -1 }
                        return prefixMode ? 0 : (la == lk ? 0 : 1)
                    }
                    var lo = 0, hi = n
                    while lo < hi {                      // first form >= key
                        let mid = (lo + hi) >> 1
                        if cmp(mid, prefixMode: false) < 0 { lo = mid + 1 } else { hi = mid }
                    }
                    let start = lo
                    hi = n
                    while lo < hi {                      // first form that does not start with key
                        let mid = (lo + hi) >> 1
                        if cmp(mid, prefixMode: true) == 0 { lo = mid + 1 } else { hi = mid }
                    }
                    return start..<lo
                }
            }
        }
    }

    // MARK: fuzzy (SUGGEST_SPEC §4.5.2)

    static func trigramSet(_ s: String) -> Set<UInt64> {
        var a: [UInt32] = [32, 32]
        for u in s.unicodeScalars { a.append(u.value) }
        a.append(32)
        var out = Set<UInt64>(minimumCapacity: a.count)
        for i in 0..<(a.count - 2) { out.insert(UInt64(a[i]) << 42 | UInt64(a[i + 1]) << 21 | UInt64(a[i + 2])) }
        return out
    }

    /// Forms within prefix-edit distance 1 (≤ 6 letters) or 2 of `q`, from trigram candidates, ascending form id.
    func fuzzyForms(_ q: String) -> [(Int32, Int)] {
        guard hasTrigrams else { return [] }
        let qa = q.unicodeScalars.map(\.value)
        let limit = qa.count <= 6 ? 1 : 2
        let grams = Self.trigramSet(q)
        var counts = [UInt8](repeating: 0, count: formCount)
        var touched: [Int32] = []
        for g in grams {
            let list = trigrams.lookup(g)
            for fi in list {
                if counts[Int(fi)] == 0 { touched.append(fi) }
                counts[Int(fi)] &+= 1
            }
        }
        let need = max(1, grams.count - 3 * limit)
        var res: [(Int32, Int)] = []
        var dp = EditDP(capacity: qa.count + limit + 2)
        var t: [UInt32] = []
        t.reserveCapacity(64)
        for fi in touched where Int(counts[Int(fi)]) >= need {
            formScalars(Int(fi), into: &t)
            if let d = dp.prefixDistance(qa, t, limit) { res.append((fi, d)) }
        }
        res.sort { $0.0 < $1.0 }
        return res
    }

    /// Unicode scalars of form `fi` (forms are almost always ASCII).
    func formScalars(_ fi: Int, into out: inout [UInt32]) {
        out.removeAll(keepingCapacity: true)
        let a = Int(formOff[fi]), b = Int(formOff[fi + 1])
        var ascii = true
        for k in a..<b where formBytes[k] >= 128 { ascii = false; break }
        if ascii {
            for k in a..<b { out.append(UInt32(formBytes[k])) }
        } else {
            for u in formString(fi).unicodeScalars { out.append(u.value) }
        }
    }

    /// Bounded optimal-string-alignment (Damerau) DP with reusable rows.
    struct EditDP {
        var prev2: [Int]
        var prev: [Int]
        var cur: [Int]
        init(capacity: Int) {
            prev2 = [Int](repeating: 0, count: capacity + 1)
            prev = prev2
            cur = prev2
        }

        /// min over L ∈ [|q|−limit, |q|+limit] of OSA(q, t[0..<L]); nil when above `limit`.
        /// One DP over q × t[0..<hi]: the last row holds the distance to every prefix (row-min pruning is exact).
        mutating func prefixDistance(_ q: [UInt32], _ t: [UInt32], _ limit: Int) -> Int? {
            let n = q.count
            let lo = max(1, n - limit), hi = min(t.count, n + limit)
            if lo > hi || n == 0 { return nil }
            let m = hi
            if prev.count < m + 1 {
                prev2 = [Int](repeating: 0, count: m + 1)
                prev = prev2
                cur = prev2
            }
            for j in 0...m { prev[j] = j }
            for i in 1...n {
                cur[0] = i
                var rmin = i
                let qi = q[i - 1]
                for j in 1...m {
                    let tj = t[j - 1]
                    var v = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (qi == tj ? 0 : 1))
                    if i > 1 && j > 1 && qi == t[j - 2] && q[i - 2] == tj { v = Swift.min(v, prev2[j - 2] + 1) }
                    cur[j] = v
                    if v < rmin { rmin = v }
                }
                if rmin > limit { return nil }
                swap(&prev2, &prev)
                swap(&prev, &cur)
            }
            var best = Int.max
            for L in lo...hi where prev[L] < best { best = prev[L] }
            return best <= limit ? best : nil
        }
    }

    /// Scalar-array form of the prefix edit distance (plausibility filter of live rows).
    static func prefixEditDistance(_ q: [Unicode.Scalar], _ t: [Unicode.Scalar], _ limit: Int) -> Int? {
        var dp = EditDP(capacity: q.count + limit + 2)
        return dp.prefixDistance(q.map(\.value), t.map(\.value), limit)
    }

    // MARK: candidates

    /// First `limit` distinct record ids (ascending = most important first) in the union of the forms in `ranges`.
    func iterate(_ ranges: [Range<Int>], limit: Int) -> [Int32] {
        var bits = [UInt64](repeating: 0, count: (recs.count >> 6) + 1)
        postings.withUnsafeBufferPointer { p in
            postStart.withUnsafeBufferPointer { ps in
                bits.withUnsafeMutableBufferPointer { bp in
                    for r in ranges {
                        for fi in r {
                            for k in Int(ps[fi])..<Int(ps[fi + 1]) {
                                let id = Int(p[k])
                                bp[id >> 6] |= 1 << UInt64(id & 63)
                            }
                        }
                    }
                }
            }
        }
        var out: [Int32] = []
        out.reserveCapacity(min(limit, 512))
        for (w, word) in bits.enumerated() where word != 0 {
            var x = word
            while x != 0 {
                out.append(Int32(w << 6 | x.trailingZeroBitCount))
                if out.count >= limit { return out }
                x &= x - 1
            }
        }
        return out
    }

    // MARK: geo

    static func cell(_ lat: Double, _ lon: Double) -> (Int, Int) {
        (Int((lat / 0.009).rounded(.down)), Int((lon / 0.0135).rounded(.down)))   // ≈ 1 km × 1 km in Austria
    }

    static func cellKey(_ lat: Double, _ lon: Double) -> Int64 {
        let (y, x) = cell(lat, lon)
        return Int64(y) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: x)))
    }

    static func cellKey(_ y: Int, _ x: Int) -> Int64 { Int64(y) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: x))) }

    /// Stops within `maxMeters`, nearest first (exact: rings grow until no closer stop can exist).
    func nearest(lat: Double, lon: Double, k: Int, maxMeters: Double, products: Int = 0) -> [(Int32, Double)] {
        guard k > 0, lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180, !maxMeters.isNaN, maxMeters >= 0 else { return [] }
        let maxMeters = min(maxMeters, 10_000_000)
        let (cy, cx) = Self.cell(lat, lon)
        var found: [(Int32, Double)] = []
        // cell size ≈ 1,000 m north-south, ≥ 0.0135° × 111 km × cos(49°) ≈ 980 m east-west in Austria
        let cellMeters = 0.009 * 111_195.0
        let lonCellMeters = 0.0135 * 111_195.0 * cos(min(abs(lat), 80) * .pi / 180)
        let minCell = max(1, min(cellMeters, lonCellMeters))
        let maxRing = min(60, Int((maxMeters / minCell).rounded(.up)) + 1)
        var ring = 0
        while ring <= maxRing {
            for dy in -ring...ring {
                for dx in -ring...ring where max(abs(dy), abs(dx)) == ring {
                    let ids = grid.lookup(Self.cellKey(cy + dy, cx + dx))
                    for ri in ids {
                        let r = info[Int(ri)]
                        if products != 0 && r.products & products == 0 { continue }
                        let d = Self.haversine(lat, lon, r.lat, r.lon)
                        if d <= maxMeters { found.append((ri, d)) }
                    }
                }
            }
            // every stop not yet visited is at least `ring × minCell` away
            if found.count >= k {
                found.sort { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
                if found[k - 1].1 <= Double(ring) * minCell { break }
            }
            if Double(ring) * minCell > maxMeters { break }
            ring += 1
        }
        found.sort { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        return Array(found.prefix(k))
    }

    static func haversine(_ la1: Double, _ lo1: Double, _ la2: Double, _ lo2: Double) -> Double {
        let r = 6_371_000.0, p = Double.pi / 180
        let a = sin((la2 - la1) * p / 2), b = sin((lo2 - lo1) * p / 2)
        let h = a * a + cos(la1 * p) * cos(la2 * p) * b * b
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
