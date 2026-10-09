import Foundation

// Search context words (docs/ENRICH_SPEC.md §2.4): ski-area, region and Bundesland names in a query that say *where*
// a stop is ("Warth am Arlberg Dorfplatz", "Sölden Ötztal", "Warth Vorarlberg"). Mirrors scripts/places_reference.py
// (CONTEXT_* / context_index) 1:1.

/// Which words are context terms and which area entities / states they stand for.
struct PlaceContextVocabulary: Sendable {
    /// Never context terms (generic parts of area names).
    static let genericWords: Set<String> = [
        "ski", "skigebiet", "arena", "region", "card", "pass", "superskipass", "resort", "bergbahnen", "und", "city",
        "plus", "zentrum", "am", "im", "an", "der", "die", "das", "see", "tal", "land", "welt", "gletscher",
        "nationalpark", "naturpark", "stadt", "umgebung", "alpen", "berg", "3000", "sportwelt", "hohe", "wiener", "the",
    ]
    /// Bundesland terms (folded names and the usual abbreviations).
    static let stateTerms: [(state: String, terms: [String])] = [
        ("V", ["vorarlberg", "vbg", "vlbg"]), ("T", ["tirol"]), ("S", ["salzburg", "sbg"]), ("K", ["karnten", "ktn"]),
        ("ST", ["steiermark", "stmk"]), ("OÖ", ["oberosterreich", "oo", "ooe"]), ("NÖ", ["niederosterreich", "no", "noe"]),
        ("B", ["burgenland", "bgld"]), ("W", ["wien"]),
    ]

    /// term → entity names ("ski:<id>", "region:<id>", "landscape:<id>").
    var entities: [String: [String]] = [:]
    /// term → state codes.
    var states: [String: [String]] = [:]

    /// Folded single words (≥ 3 letters, not generic) of an area name, as the query tokenizer splits them.
    static func words(_ name: String) -> [String] {
        var out: [String] = []
        for t in PlaceNormalizer.tokenize(name, isName: false).0 where t.raw.unicodeScalars.count >= 3
            && !genericWords.contains(t.raw) && !out.contains(t.raw) {
            out.append(t.raw)
        }
        return out
    }

    init(catalog: SkiAreaCatalog) {
        func add(_ term: String, _ entity: String) {
            if !(entities[term]?.contains(entity) ?? false) { entities[term, default: []].append(entity) }
        }
        for a in catalog.areas.values where a.kind != .alliance {
            for w in Self.words(a.name) + Self.words(a.shortName ?? "") { add(w, "ski:" + a.id) }
        }
        for r in catalog.regions.values {
            for w in Self.words(r.name) { add(w, (r.kind == .landscape ? "landscape:" : "region:") + r.id) }
        }
        for (state, terms) in Self.stateTerms {
            for t in terms where !(states[t]?.contains(state) ?? false) { states[t, default: []].append(state) }
        }
    }

    init() {}
}

/// Context term → sorted record ids of the table that lie there (ski tag ≥ 70, region/landscape ≥ 80, or the
/// state; towns through their main stop plus their own state). Terms without any member are dropped.
struct PlaceContextIndex: Sendable {
    /// Terms sorted by UTF-8 bytes; `sets[k]` = members of `terms[k]`.
    let terms: [String]
    let sets: [[Int32]]

    /// `entitiesOfStop(stopIndex)` = entity ids (indices into `entityNames`) of a stop.
    init(records: [PlaceRecord], vocabulary: PlaceContextVocabulary, entityNames: [String],
         entitiesOfStop: (Int) -> ArraySlice<Int32>) {
        let all = Set(vocabulary.entities.keys).union(vocabulary.states.keys).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var termIndex: [String: Int] = [:]
        for (k, t) in all.enumerated() { termIndex[t] = k }
        var entityTerms = [[Int]](repeating: [], count: entityNames.count)
        var entityByName: [String: Int] = [:]
        for (e, name) in entityNames.enumerated() { entityByName[name] = e }
        for (term, ents) in vocabulary.entities {
            for name in ents { if let e = entityByName[name] { entityTerms[e].append(termIndex[term]!) } }
        }
        var stateTerms: [String: [Int]] = [:]
        for (term, states) in vocabulary.states { for s in states { stateTerms[s, default: []].append(termIndex[term]!) } }
        var stopOf: [String: Int32] = [:]
        for r in records where r.stopIndex >= 0 { stopOf[r.id] = r.stopIndex }

        var sets = [[Int32]](repeating: [], count: all.count)
        for (ri, r) in records.enumerated() {
            let id = Int32(ri)
            func put(_ k: Int) { if sets[k].last != id { sets[k].append(id) } }
            var stop = Int(r.stopIndex)
            if stop < 0, r.kind == .town, let m = r.mainStopID, let s = stopOf[m] { stop = Int(s) }
            if stop >= 0 { for e in entitiesOfStop(stop) where Int(e) < entityTerms.count { for k in entityTerms[Int(e)] { put(k) } } }
            for k in stateTerms[r.state] ?? [] { put(k) }
        }
        var t: [String] = [], s: [[Int32]] = []
        for (k, term) in all.enumerated() where !sets[k].isEmpty {
            t.append(term)
            s.append(sets[k])
        }
        terms = t
        self.sets = s
    }

    /// Set indices of a query token (§2.4 rule 4): a term equal to the token or its canonical form (`exact`); for the
    /// last, still-typed token also every term it is a prefix of (≥ 4 letters).
    func lookup(raw: String, canonical: String, partial: Bool) -> (sets: [Int32], exact: Bool) {
        var out: [Int32] = []
        for w in canonical == raw ? [raw] : [canonical, raw] {
            if let k = exact(w), !out.contains(k) { out.append(k) }
        }
        let isExact = !out.isEmpty
        if partial && raw.unicodeScalars.count >= 4 {
            for k in prefixRange(raw) where !out.contains(Int32(k)) { out.append(Int32(k)) }
        }
        return (out.sorted(), isExact)
    }

    func contains(_ set: Int32, _ record: Int32) -> Bool { PlaceTable.sortedContains(sets[Int(set)], record) }

    private func lowerBound(_ key: [UInt8]) -> Int {
        var lo = 0, hi = terms.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if terms[mid].utf8.lexicographicallyPrecedes(key) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func exact(_ w: String) -> Int32? {
        let k = lowerBound(Array(w.utf8))
        return k < terms.count && terms[k] == w ? Int32(k) : nil
    }

    private func prefixRange(_ p: String) -> Range<Int> {
        let key = Array(p.utf8)
        let lo = lowerBound(key)
        var hi = lo
        while hi < terms.count && terms[hi].utf8.starts(with: key) { hi += 1 }
        return lo..<hi
    }
}
