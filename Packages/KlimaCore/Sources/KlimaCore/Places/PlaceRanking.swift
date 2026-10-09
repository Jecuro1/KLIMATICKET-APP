import Foundation

// SUGGEST_SPEC §5: ranking formula. Mirrors scripts/places_reference.py (text_score / final_score) 1:1.

enum PlaceWeights {
    static let text = 100.0, importance = 40.0, first = 0.15, order = 0.05, covExact = 0.20, covPartial = 0.10
    static let exact = 0.50, skipStop = 0.05, skipNum = 0.05, skipRelaxed = 0.40, relaxedAnchor = 0.25
    static let foreign = -20.0, townNonExact = -3.0, townMinor = -12.0
    static let poiStopIntent = -40.0, addrStopIntent = -40.0, addrStreetIntent = 10.0, addrNumberIntent = 40.0
    static let poiNumberIntent = 0.0
    static let liveRank = 5.0, fav = 35.0, recent = 25.0
    /// Context word (ENRICH_SPEC §2.4) not matched by a name token while the place lies there (cancels the optional
    /// skip, +0.05). A place outside the area counts the word as unmatched (relaxed matching only, −0.40).
    static let contextHit = 0.10
    /// Context words act only when the query has a selective place word (≤ this many postings): "bad gastein",
    /// "st johann" name the place with the area word itself.
    static let contextMaxGenerator = 500
    static let near = 8.0, nearShort = 16.0, nearKm = 30.0, nearGeneric = 60.0, nearGenericKm = 20.0
    static let placeExact: [String: Double] = ["city": 1.0, "town": 0.8, "village": 0.3, "suburb": 0.3, "hamlet": 0,
                                               "neighbourhood": 0, "quarter": 0, "isolated_dwelling": 0]
    static let minorPlaces: Set<String> = ["hamlet", "neighbourhood", "quarter", "isolated_dwelling"]
    /// Max candidates scored per keystroke (importance order); exact-name and personal hits are always added.
    static let nMax = 1500

    static func liveBonus(rank: Int) -> Double { liveRank * (1 - Double(rank - 1) / 10) }
}

/// A query compiled against one table: everything the per-candidate loop needs, as integers.
struct CompiledQuery {
    struct Key {
        var exactForm: Int32
        var lo: Int
        var hi: Int
        var len: Int32
    }
    var text: String
    var n: Int
    var raw: [String]
    var flags: [UInt8]
    var weight: [Double]
    var keys: [[Key]]
    /// Per token: dense distance per form id (0 = not a fuzzy form), empty when the token has no fuzzy forms.
    var fuzzy: [[UInt8]]
    /// Per token: (canonical form id of a name token, weak synonym value).
    var weak: [[(Int32, Double)]]
    var lastPartial: Bool
    var genericOnly: Bool
    var hasNumber: Bool
    var streetIntent: Bool
    var est: [Int]
    var ranges: [[Range<Int>]]
    /// Trimmed text length (near bonus for very short queries).
    var shortText: Bool
    /// Per token: context-word sets (`PlaceContextIndex` set indices), empty for ordinary tokens.
    var context: [[Int32]]
    var hasContext: Bool
}

extension PlaceTable {
    /// §3.7 query compound split ('mariahilferstrasse' → 'mariahilfer' + 'strasse'; last token: 'mariahilferstr').
    func splitCompounds(_ toks: [PlaceToken], lastPartial: Bool, fuzzyCache: inout [String: [(Int32, Int)]]) -> [PlaceToken] {
        var out: [PlaceToken] = []
        var changed = false
        for (i, t) in toks.enumerated() {
            let sc = Array(t.raw.unicodeScalars)
            if !prefixRange(t.raw).isEmpty || sc.count < 6 || !sc.allSatisfy(PlaceNormalizer.isAlpha) {
                out.append(t)
                continue
            }
            let fz = fuzzyCache[t.raw] ?? fuzzyForms(t.raw)
            fuzzyCache[t.raw] = fz
            if !fz.isEmpty { out.append(t); continue }                   // a typo of a real word is not a compound
            let last = lastPartial && i == toks.count - 1
            var done = false
            var p = sc.count - 2
            while p > 3 {                                                // head ≥ 4 characters
                let head = String(String.UnicodeScalarView(sc[..<p])), tail = String(String.UnicodeScalarView(sc[p...]))
                let okTail = PlaceLexicon.splitTails.contains(tail)
                    || (last && tail.unicodeScalars.count >= 2 && PlaceLexicon.partialTails.contains { $0.hasPrefix(tail) })
                if okTail && !prefixRange(head).isEmpty {
                    let q = t.isQualifier
                    out.append(PlaceToken(raw: head, flags: PlaceTok.flags(head, qualifier: q), forms: []))
                    out.append(PlaceToken(raw: tail, flags: PlaceTok.flags(tail, qualifier: q), forms: []))
                    done = true
                    changed = true
                    break
                }
                p -= 1
            }
            if !done { out.append(t) }
        }
        return changed ? out : toks
    }

    /// Compiles `text`. `split` enables the compound split, `fuzzy` the typo forms (offline index only).
    func compile(_ text: String, split: Bool = true, fuzzy: Bool = true) -> CompiledQuery? {
        let text = text.unicodeScalars.count > 64 ? String(String.UnicodeScalarView(text.unicodeScalars.prefix(64))) : text
        var (t0, trailing) = PlaceNormalizer.tokenize(text, isName: false)
        if t0.count > 8 { t0 = Array(t0.prefix(8)); trailing = true }       // limits [DECISION] §3.7
        guard !t0.isEmpty else { return nil }
        let hasNumber = t0.contains { $0.isNumeric }
        let street = t0.contains { t in
            PlaceLexicon.streetTokens.contains(t.raw) || t.raw.hasSuffix("strasse") || t.raw.hasSuffix("gasse") || t.raw.hasSuffix("str")
        }
        let hard0 = t0.filter { !$0.isStop }
        let genericOnly = !hard0.isEmpty && hard0.allSatisfy { PlaceLexicon.genericQuery.contains($0.canonical) }
        var fuzzyCache: [String: [(Int32, Int)]] = [:]
        let toks = split ? splitCompounds(t0, lastPartial: !trailing, fuzzyCache: &fuzzyCache) : t0
        var keys: [[CompiledQuery.Key]] = [], fz: [[UInt8]] = [], weak: [[(Int32, Double)]] = []
        var est: [Int] = [], ranges: [[Range<Int>]] = []
        keys.reserveCapacity(toks.count)
        for t in toks {
            var ks = [t.raw]
            for m in PlaceLexicon.synMembers[t.raw] ?? [] where !ks.contains(m) { ks.append(m) }
            var tokRanges: [Range<Int>] = []
            keys.append(ks.map { k in
                let r = prefixRange(k)
                if !r.isEmpty { tokRanges.append(r) }
                let ex: Int32 = (!r.isEmpty && Int(formOff[r.lowerBound + 1] - formOff[r.lowerBound]) == k.utf8.count)
                    ? Int32(r.lowerBound) : -1
                return CompiledQuery.Key(exactForm: ex, lo: r.lowerBound, hi: r.upperBound, len: Int32(k.unicodeScalars.count))
            })
            var fuzzyMap: [UInt8] = []
            if fuzzy && tokRanges.isEmpty && t.raw.unicodeScalars.count >= 4 && t.raw.unicodeScalars.allSatisfy(PlaceNormalizer.isAlpha) {
                let forms = fuzzyCache[t.raw] ?? fuzzyForms(t.raw)
                if !forms.isEmpty { fuzzyMap = [UInt8](repeating: 0, count: formCount) }
                for (fi, d) in forms {
                    tokRanges.append(Int(fi)..<Int(fi) + 1)
                    fuzzyMap[Int(fi)] = UInt8(d)
                }
            }
            fz.append(fuzzyMap)
            ranges.append(tokRanges)
            est.append(tokRanges.reduce(0) { $0 + Int(postStart[$1.upperBound] - postStart[$1.lowerBound]) })
            var w: [(Int32, Double)] = []
            let c = t.canonical
            for (a, b, v) in PlaceLexicon.weakSyn where a == c { if let fid = formID(b) { w.append((fid, v)) } }
            weak.append(w)
        }
        var qflags = toks.map(\.flags)
        for k in toks.indices where k > 0 && PlaceLexicon.optionalQuery.contains(toks[k].canonical) { qflags[k] |= PlaceTok.optional }
        // §2.4: a context word after the first token is scored by membership when the name does not contain it – when
        // another word already names a place selectively (postings ≤ contextMaxGenerator). An exact area word is
        // optional for candidate generation; a still-typed prefix of one ("warth arlb") stays an ordinary word there.
        var ctx = [[Int32]](repeating: [], count: toks.count)
        if let context {
            var cand = ctx, exactTerm = [Bool](repeating: false, count: toks.count)
            for k in toks.indices where k > 0 && !toks[k].isStop && !toks[k].isNumeric
                && !PlaceContextVocabulary.genericWords.contains(toks[k].raw)
                && !toks[..<k].contains(where: { $0.raw == toks[k].raw || $0.canonical == toks[k].canonical }) {
                // (a word repeating an earlier one is a name word again: "innsbruck innsbruck" needs two name tokens)
                let hit = context.lookup(raw: toks[k].raw, canonical: toks[k].canonical, partial: !trailing && k == toks.count - 1)
                cand[k] = hit.sets
                exactTerm[k] = hit.exact
            }
            if cand.contains(where: { !$0.isEmpty }) {
                let place = toks.indices.filter {
                    cand[$0].isEmpty && qflags[$0] & (PlaceTok.stop | PlaceTok.numeric | PlaceTok.optional) == 0
                }
                if let g = place.min(by: { est[$0] < est[$1] }), est[g] <= PlaceWeights.contextMaxGenerator {
                    ctx = cand
                    for k in toks.indices where exactTerm[k] { qflags[k] |= PlaceTok.optional }
                }
            }
        }
        return CompiledQuery(text: text, n: toks.count, raw: toks.map(\.raw), flags: qflags,
                             weight: toks.map { Double(max(2, $0.raw.unicodeScalars.count)) }, keys: keys, fuzzy: fz,
                             weak: weak, lastPartial: !trailing, genericOnly: genericOnly, hasNumber: hasNumber,
                             streetIntent: street, est: est, ranges: ranges,
                             shortText: text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count <= 3,
                             context: ctx, hasContext: ctx.contains { !$0.isEmpty })
    }

    /// §5.1 best match of query token `i` against name token `t`.
    @inline(__always)
    func tokenMatch(_ q: CompiledQuery, _ i: Int, _ lastPartial: Bool, _ t: Int) -> Double {
        var best = 0.0
        if !q.weak[i].isEmpty {
            let c = tokCanon[t]
            for (fid, v) in q.weak[i] where fid == c { best = v }
        }
        let fz = q.fuzzy[i]
        let keys = q.keys[i]
        for k in Int(tokFormStart[t])..<Int(tokFormStart[t + 1]) {
            let fid = tokForm[k]
            let fac = tokFormFac[k]
            for key in keys {
                if fid == key.exactForm {
                    if fac > best { best = fac }
                } else if Int(fid) >= key.lo && Int(fid) < key.hi && formLen[Int(fid)] > key.len && (fac > 0.8 || key.len >= 3) {
                    let ratio = Double(key.len) / Double(formLen[Int(fid)])
                    let v = ((lastPartial ? 0.70 : 0.60) + 0.30 * ratio) * fac
                    if v > best { best = v }
                }
            }
            if !fz.isEmpty {
                let d = fz[Int(fid)]
                if d > 0 {
                    let v = (0.50 - 0.10 * Double(Int(d) - 1)) * fac
                    if v > best { best = v }
                }
            }
        }
        return best
    }

    struct Candidate {
        var wm: Double
        var i: Int
        var j: Int
        var m: Double
    }

    /// Reusable buffers of one search (no allocation per candidate).
    struct Scratch {
        var cand: [Candidate] = []
        var aj: [Int] = []
        var am: [Double] = []
        init(n: Int) {
            cand.reserveCapacity(64)
            aj = [Int](repeating: -1, count: max(1, n))
            am = [Double](repeating: 0, count: max(1, n))
        }
    }

    /// §5.2 text score of record `ri` (best over its variants) and the scaled exact bonus; nil = no match.
    func textScore(_ q: CompiledQuery, _ ri: Int, relaxed: Bool, scratch: inout Scratch) -> (Double, Double)? {
        let kind = info[ri].kind
        let isAP = kind == .address || kind == .poi
        var best: (Double, Double)?
        let n = q.n
        for v in Int(recVarStart[ri])..<Int(recVarStart[ri + 1]) {
            let t0 = Int(varTokStart[v]), t1 = Int(varTokStart[v + 1])
            let vfac = varFactor[v]
            let sec = Int(varSecondary[v])
            scratch.cand.removeAll(keepingCapacity: true)
            for i in 0..<n {
                let lp = q.lastPartial && i == n - 1
                for t in t0..<t1 {
                    var m = tokenMatch(q, i, lp, t)
                    if m > 0 {
                        if t - t0 >= sec { m *= 0.6 } else if tokFlags[t] & PlaceTok.qualifier != 0 { m *= 0.8 }
                        scratch.cand.append(Candidate(wm: q.weight[i] * m, i: i, j: t - t0, m: m))
                    }
                }
            }
            if scratch.cand.isEmpty { continue }
            if scratch.cand.count > 1 {
                scratch.cand.sort { a, b in
                    if a.wm != b.wm { return a.wm > b.wm }
                    if a.i != b.i { return a.i > b.i }
                    if a.j != b.j { return a.j > b.j }
                    return a.m > b.m
                }
            }
            var usedI: UInt64 = 0, usedJ: UInt64 = 0
            for k in 0..<n { scratch.aj[k] = -1; scratch.am[k] = 0 }
            for c in scratch.cand where usedI & (1 << UInt64(c.i)) == 0 && usedJ & (1 << UInt64(min(c.j, 63))) == 0 {
                usedI |= 1 << UInt64(c.i)
                usedJ |= 1 << UInt64(min(c.j, 63))
                scratch.aj[c.i] = c.j
                scratch.am[c.i] = c.m
            }
            var skip = 0.0, unmatchedHard = 0, nAssigned = 0
            var wsum = 0.0, wq = 0.0, allExact = true, adj = 0.0
            for i in 0..<n {
                let f = q.flags[i]
                var skippable = f & (PlaceTok.stop | PlaceTok.optional) != 0
                if q.hasContext, scratch.aj[i] < 0, !q.context[i].isEmpty, let context {
                    // §2.4: an area word not in the name – the place lies there (skip like a stopword, +0.10) or the word
                    // stays unmatched (relaxed matching only)
                    if q.context[i].contains(where: { context.contains($0, Int32(ri)) }) {
                        skippable = true
                        adj += PlaceWeights.contextHit
                    } else {
                        skippable = false
                    }
                }
                if scratch.aj[i] >= 0 {
                    nAssigned += 1
                    wsum += q.weight[i]
                    wq += q.weight[i] * scratch.am[i]
                    if scratch.am[i] < 0.95 { allExact = false }
                } else {
                    if !skippable { wsum += q.weight[i] }
                    if skippable { skip += PlaceWeights.skipStop }
                    else if f & PlaceTok.numeric != 0 && kind != .address { skip += PlaceWeights.skipNum }
                    else { unmatchedHard += 1; skip += PlaceWeights.skipRelaxed }
                }
            }
            if unmatchedHard > (relaxed ? 1 : 0) || nAssigned == 0 { continue }
            if unmatchedHard > 0 { allExact = false }
            let quality = wq / max(1, wsum)
            var first = (scratch.aj[0] == 0 && scratch.am[0] >= 0.7) ? PlaceWeights.first : 0
            var order = 0.0
            if nAssigned >= 2 {
                var ok = true, last = -1
                for i in 0..<n where scratch.aj[i] >= 0 {
                    if scratch.aj[i] <= last { ok = false; break }
                    last = scratch.aj[i]
                }
                if ok { order = PlaceWeights.order }
            }
            var essN = 0.0, essM = 0.0, qualN = 0.0, qualM = 0.0, allName = true
            for t in t0..<t1 {
                let j = t - t0
                if j >= sec { break }
                let f = tokFlags[t]
                let matched = j < 64 && usedJ & (1 << UInt64(j)) != 0
                if f & PlaceTok.essential != 0 { essN += 1; if matched { essM += 1 } }
                if f & PlaceTok.qualifier != 0 && f & PlaceTok.generic == 0 && f & PlaceTok.stop == 0 {
                    qualN += 1
                    if matched { qualM += 1 }
                }
                if f & PlaceTok.stop == 0 && f & PlaceTok.qualifier == 0 && !matched { allName = false }
            }
            let anchorHit = usedJ & 1 != 0
            let denom = essN + 0.5 * qualN
            let cov = denom > 0 ? (essM + 0.5 * qualM) / denom : 1.0
            let lastExact = (scratch.aj[n - 1] >= 0 && scratch.am[n - 1] >= 0.95) || !q.lastPartial
            var compl = (lastExact ? PlaceWeights.covExact : PlaceWeights.covPartial) * cov
            var exact = (allExact && allName && lastExact) ? PlaceWeights.exact : 0
            if exact > 0 && (isAP || vfac < 0.9) { exact *= 0.5 }
            if exact > 0 && kind == .town { exact *= info[ri].localityExactFactor }
            let anchor = (relaxed && unmatchedHard > 0 && anchorHit) ? PlaceWeights.relaxedAnchor : 0
            if q.genericOnly { first = 0; order = 0; compl = 0; exact = 0 }
            let s = (quality + first + order + compl + exact + anchor - skip) * vfac + adj
            if best == nil || s > best!.0 { best = (s, exact) }
        }
        return best
    }

    /// Personal boosts per record id (favourite +35, recent 25 × 0.5^(age/14) + 3 × min(uses, 5)).
    func personalBoosts(_ ctx: PlaceSearchContext) -> [Int32: Double] {
        var out: [Int32: Double] = [:]
        for id in ctx.favourites { if let ri = byID[id] { out[ri, default: 0] += PlaceWeights.fav } }
        for (id, use) in ctx.recents {
            if let ri = byID[id] {
                out[ri, default: 0] += PlaceWeights.recent * pow(0.5, use.ageDays / 14) + 3 * Double(min(use.uses, 5))
            }
        }
        return out
    }

    /// §5.3 final score of record `ri` with text score `ts` (town non-exact adjustment included).
    func finalScore(_ q: CompiledQuery, _ ri: Int, _ ts: Double, exact: Double, _ ctx: PlaceSearchContext,
                    personal: [Int32: Double]) -> Double {
        let r = info[ri]
        var s = PlaceWeights.text * ts + PlaceWeights.importance * r.importance
        if r.foreign { s += PlaceWeights.foreign }
        if r.kind == .town {
            if r.minorLocality { s += PlaceWeights.townMinor }
            if exact == 0 { s += PlaceWeights.townNonExact }
        }
        if r.kind == .poi { s += q.hasNumber ? PlaceWeights.poiNumberIntent : PlaceWeights.poiStopIntent }
        if r.kind == .address {
            s += q.hasNumber ? PlaceWeights.addrNumberIntent : (q.streetIntent ? PlaceWeights.addrStreetIntent : PlaceWeights.addrStopIntent)
        }
        if r.liveRank > 0 { s += PlaceWeights.liveBonus(rank: Int(r.liveRank)) }
        if let near = ctx.near {
            let dkm = Self.haversine(near.latitude, near.longitude, r.lat, r.lon) / 1000
            if q.genericOnly {
                s += PlaceWeights.nearGeneric * max(0, 1 - dkm / PlaceWeights.nearGenericKm)
            } else {
                s += (q.shortText ? PlaceWeights.nearShort : PlaceWeights.near) * max(0, 1 - dkm / PlaceWeights.nearKm)
            }
        }
        if !personal.isEmpty, let b = personal[Int32(ri)] { s += b }
        return s
    }

    struct SearchStats {
        var generator = ""
        var est = 0
        var scored = 0
        var relaxed = false
    }

    /// §4.5 offline search: (score, record id) sorted best first.
    func search(_ text: String, _ ctx: PlaceSearchContext, limit: Int, stats: inout SearchStats) -> [(Double, Int)] {
        guard limit > 0, let q = compile(text) else { return [] }
        var hard = (0..<q.n).filter { q.flags[$0] & (PlaceTok.stop | PlaceTok.numeric | PlaceTok.optional) == 0 }
        if hard.isEmpty { hard = Array(0..<q.n) }
        let gen = hard.min { q.est[$0] < q.est[$1] }!
        let cands = iterate(q.ranges[gen], limit: PlaceWeights.nMax)
        let personal = personalBoosts(ctx)
        var extra = Set(exact.lookup(Self.fnv1a(q.raw.map(PlaceLexicon.canonical).joined(separator: " "))))
        for ri in personal.keys { extra.insert(ri) }
        var pool = cands
        for c in extra.sorted() where !Self.sortedContains(cands, c) { pool.append(c) }
        var results = scoreSet(q, pool, ctx, personal: personal, relaxed: false)
        var relaxed = false
        if results.count < 3 && hard.count >= 2 {
            relaxed = true
            let two = hard.sorted { (q.est[$0], $0) < (q.est[$1], $1) }.prefix(2)
            let union = iterate(two.flatMap { q.ranges[$0] }, limit: PlaceWeights.nMax)
            var pool2 = union
            for c in pool where !Self.sortedContains(union, c) { pool2.append(c) }
            results = scoreSet(q, pool2, ctx, personal: personal, relaxed: true)
        }
        stats = SearchStats(generator: q.raw[gen], est: q.est[gen], scored: pool.count, relaxed: relaxed)
        return topK(results, limit)
    }

    @inline(__always) static func sortedContains(_ a: [Int32], _ x: Int32) -> Bool {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if a[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo < a.count && a[lo] == x
    }

    /// Best `limit` results with the full tie-break order (score, importance, shorter name, name, id).
    func topK(_ results: [(Double, Int)], _ limit: Int) -> [(Double, Int)] {
        guard !results.isEmpty, limit > 0 else { return [] }
        var bySore = results
        bySore.sort { $0.0 > $1.0 }
        let cutoff = bySore[min(limit, bySore.count) - 1].0
        var head = Array(bySore.prefix { $0.0 >= cutoff })
        sortResults(&head)
        return Array(head.prefix(limit))
    }

    func sortResults(_ results: inout [(Double, Int)]) {
        results.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            let ia = info[a.1], ib = info[b.1]
            if ia.importance != ib.importance { return ia.importance > ib.importance }
            if ia.nameLen != ib.nameLen { return ia.nameLen < ib.nameLen }
            let na = recs[a.1].name, nb = recs[b.1].name
            if na != nb { return na.unicodeScalars.lexicographicallyPrecedes(nb.unicodeScalars) }
            return recs[a.1].id.unicodeScalars.lexicographicallyPrecedes(recs[b.1].id.unicodeScalars)
        }
    }

    func scoreSet(_ q: CompiledQuery, _ pool: [Int32], _ ctx: PlaceSearchContext, personal: [Int32: Double],
                  relaxed: Bool) -> [(Double, Int)] {
        var out: [(Double, Int)] = []
        out.reserveCapacity(pool.count)
        var scratch = Scratch(n: q.n)
        let skipTowns = ctx.mode == .tripLog
        for c in pool {
            let ri = Int(c)
            if skipTowns && info[ri].kind == .town { continue }
            guard let (ts, ex) = textScore(q, ri, relaxed: relaxed, scratch: &scratch) else { continue }
            out.append((finalScore(q, ri, ts, exact: ex, ctx, personal: personal), ri))
        }
        return out
    }
}
