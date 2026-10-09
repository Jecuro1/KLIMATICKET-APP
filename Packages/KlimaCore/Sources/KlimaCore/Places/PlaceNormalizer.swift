import Foundation

// SUGGEST_SPEC §3: normalisation and tokenisation, identical for index (names) and queries.
// Mirrors scripts/places_reference.py (fold/lex/abbreviate/tokenize) 1:1; golden: Tests/…/Fixtures/places/fold_golden.json.

enum PlaceLexicon {
    /// Synonym groups, canonical form first. Every member is indexed as a form of a name token; a query token that
    /// equals a member matches every member exactly.
    static let synGroups: [[String]] = [
        ["hbf", "hauptbahnhof", "hbhf"], ["bf", "bahnhof", "bhf", "bhnf"], ["bahnhst", "bahnhaltestelle", "bhst"],
        ["hst", "haltestelle"], ["st", "sankt"], ["str", "strasse"], ["wiener", "wr"], ["abzw", "abzweigung"],
        ["flughafen", "airport"], ["karnten", "ktn"], ["niederosterreich", "no"], ["oberosterreich", "oo"],
        ["steiermark", "stmk"], ["burgenland", "bgld"], ["vorarlberg", "vbg", "vlbg"],
    ]
    /// City abbreviations: indexed with factor 0.9 on the city token, so they apply to every stop of the city.
    static let cityAliases: [(String, [String])] = [("innsbruck", ["ibk"]), ("salzburg", ["sbg", "szbg"]),
                                                    ("klagenfurt", ["klgft"]), ("wiener", ["wr"])]
    static let stopwords: Set<String> = ["an", "am", "der", "die", "das", "dem", "den", "bei", "beim", "in", "im", "ob",
                                         "a", "d", "i", "b", "und", "zum", "zur", "vom", "von", "auf"]
    static let generic: Set<String> = ["hbf", "bf", "bahnhst", "hst", "u", "s", "abzw", "bahn"]
    /// Generic-only queries ("bahnhof", "hbf", "haltestelle") rank by place, not by text.
    static let genericQuery: Set<String> = generic.union(["bahnhof", "hauptbahnhof", "haltestelle"])
    static let splitSuffixes = ["hauptbahnhof", "bahnhof", "bahnhst", "strasse", "gasse", "platz", "weg", "brucke", "allee",
                                "kai", "gurtel", "ufer", "zeile", "steig", "siedlung", "kirche", "zentrum", "markt"]
    static let rivers: Set<String> = ["donau", "mur", "ybbs", "rhein", "enns", "inn", "thaya", "traun", "drau", "krems",
                                      "murz", "lafnitz", "raab", "salzach", "triesting", "traisen", "gail", "leitha",
                                      "erlauf", "pielach", "kamp", "ager"]
    static let streetTokens: Set<String> = ["str", "strasse", "gasse", "weg", "platz", "allee", "ring", "kai", "gurtel",
                                            "ufer", "zeile", "steig", "promenade", "lande", "damm"]
    /// Weak synonyms: (query canonical, name canonical, value).
    static let weakSyn: [(String, String, Double)] = [("bf", "hbf", 0.9), ("bf", "bahnhst", 0.85), ("hst", "bahnhst", 0.85),
                                                      ("hst", "bf", 0.8)]
    static let partialTails = ["strasse", "gasse", "platz", "bahnhof"]
    /// Region qualifiers and HAFAS suffixes a query may carry although the offline name lacks them
    /// ("Lauterach in Vlbg …", "Steinbrunn im Bgld …", "… NÖ Abzw Ort"): when unmatched they cost like a stopword.
    /// Never applied to the first query token.
    static let optionalQuery: Set<String> = ["niederosterreich", "oberosterreich", "vorarlberg", "burgenland", "steiermark",
                                             "karnten", "tirol", "ort", "ortsmitte"]

    static let (canon, synMembers, aliasForms): ([String: String], [String: [String]], [String: [String]]) = {
        var c: [String: String] = [:], m: [String: [String]] = [:], a: [String: [String]] = [:]
        for g in synGroups { for x in g { c[x] = g[0]; m[x] = g } }
        for (city, al) in cityAliases {
            for x in al {
                a[city, default: []].append(x)
                if c[x] == nil { c[x] = city }
                if m[x] == nil { m[x] = [city, x] }
            }
        }
        return (c, m, a)
    }()

    /// Split tails of the query compound split: every split suffix with its synonyms, plus "str".
    static let splitTails: Set<String> = Set(splitSuffixes.flatMap { synMembers[$0] ?? [$0] } + ["str"])

    @inline(__always) static func canonical(_ t: String) -> String { canon[t] ?? t }
}

/// Token flags (bit set).
enum PlaceTok {
    static let stop: UInt8 = 1, generic: UInt8 = 2, qualifier: UInt8 = 4, numeric: UInt8 = 8, essential: UInt8 = 16
    /// Query side only: region qualifier that may stay unmatched (`PlaceLexicon.optionalQuery`).
    static let optional: UInt8 = 32

    static func flags(_ t: String, qualifier: Bool) -> UInt8 {
        var f: UInt8 = 0
        if PlaceLexicon.stopwords.contains(t) { f |= stop }
        if PlaceLexicon.generic.contains(PlaceLexicon.canonical(t)) { f |= generic }
        if qualifier { f |= PlaceTok.qualifier }
        if let u = t.unicodeScalars.first, PlaceNormalizer.isDigit(u) { f |= numeric }
        if f == 0 { f |= essential }
        return f
    }
}

struct PlaceLexeme {
    var raw: String
    var qualifier: Bool
    var chunk: Double
    var dotted: Bool
}

struct PlaceToken {
    var raw: String
    var flags: UInt8
    /// Index forms with factor (names only): the token, synonyms (1.0), city abbreviations (0.9), compound
    /// remainder (0.95), split head/suffix (0.8).
    var forms: [(String, Double)]

    var canonical: String { PlaceLexicon.canonical(raw) }
    var isStop: Bool { flags & PlaceTok.stop != 0 }
    var isGeneric: Bool { flags & PlaceTok.generic != 0 }
    var isQualifier: Bool { flags & PlaceTok.qualifier != 0 }
    var isNumeric: Bool { flags & PlaceTok.numeric != 0 }
    var isEssential: Bool { flags & PlaceTok.essential != 0 }
}

/// Normalisation used by the place search (and usable by the UI, e.g. for "exact match" checks).
public enum PlaceNormalizer {
    // Explicit Latin table (SUGGEST_SPEC §3.1). Upper-case variants are added so the common path needs no
    // String.lowercased() call; anything else goes through lowercased() → table → NFKD minus combining marks.
    private static let table: [UInt32: String] = {
        var t: [UInt32: String] = [:]
        let rows: [(String, String)] = [("äàáâãåāăą", "a"), ("æ", "ae"), ("çćčĉċ", "c"), ("ďđ", "d"), ("èéêëēėęěĕ", "e"),
                                        ("ğĝģ", "g"), ("ìíîïīįı", "i"), ("ĺľłļ", "l"), ("ñńňņ", "n"), ("öòóôõøōőŏ", "o"),
                                        ("œ", "oe"), ("ŕřŗ", "r"), ("śšşŝș", "s"), ("ß", "ss"), ("ťţț", "t"),
                                        ("üùúûūůűųŭ", "u"), ("ýÿ", "y"), ("źżž", "z"), ("’‘`´", "'")]
        for (src, dst) in rows {
            for u in src.unicodeScalars {
                t[u.value] = dst
                // upper-case twin whose lower-case is exactly this scalar (Ä → ä, Ö → ö, …)
                let up = String(u).uppercased()
                if up.unicodeScalars.count == 1, let uu = up.unicodeScalars.first, !uu.isASCII,
                   String(uu).lowercased() == String(u), t[uu.value] == nil {
                    t[uu.value] = dst
                }
            }
        }
        t[0x1E9E] = "ss"   // ẞ
        return t
    }()

    @inline(__always) static func isDigit(_ u: Unicode.Scalar) -> Bool {
        if u.isASCII { return u.value >= 48 && u.value <= 57 }
        return u.properties.numericType != nil
    }

    @inline(__always) static func isAlnum(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        if v < 128 { return (v >= 97 && v <= 122) || (v >= 48 && v <= 57) || (v >= 65 && v <= 90) }
        return u.properties.isAlphabetic || u.properties.numericType != nil
    }

    @inline(__always) static func isAlpha(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        if v < 128 { return (v >= 97 && v <= 122) || (v >= 65 && v <= 90) }
        return u.properties.isAlphabetic
    }

    /// §3.1 fold: lower-case → explicit Latin table → NFKD minus combining marks → ae/oe/ue → a/o/u.
    /// "Sankt Pölten" → "sankt polten", "Poelten" → "polten", "Straße" → "strasse".
    public static func fold(_ s: String) -> String {
        foldFast(s) ?? foldGeneral(s)
    }

    private static let asciiTable: [UInt32: [UInt8]] = table.mapValues { Array($0.utf8) }

    /// Fast path: every scalar is ASCII or in the Latin table (all Austrian names) → ASCII bytes, same result.
    private static func foldFast(_ s: String) -> String? {
        var out: [UInt8] = []
        out.reserveCapacity(s.utf8.count + 4)
        var prev: UInt8 = 0
        for u in s.unicodeScalars {
            let v = u.value
            if v < 128 {
                let b = v >= 65 && v <= 90 ? UInt8(v + 32) : UInt8(v)
                if b == 101, prev == 97 || prev == 111 || prev == 117 { prev = 0; continue }
                out.append(b)
                prev = b
            } else if let r = asciiTable[v] {
                for b in r {
                    if b == 101, prev == 97 || prev == 111 || prev == 117 { prev = 0; continue }
                    out.append(b)
                    prev = b
                }
            } else {
                return nil
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func foldGeneral(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var prev: UInt32 = 0          // last appended scalar (for the ae/oe/ue pass); 0 after a skip
        @inline(__always) func emit(_ u: Unicode.Scalar) {
            if u.value == 101, prev == 97 || prev == 111 || prev == 117 { prev = 0; return }   // e after a/o/u
            out.append(u)
            prev = u.value
        }
        func emitMapped(_ u: Unicode.Scalar) {
            if u.isASCII { emit(u); return }
            if let r = table[u.value] { for x in r.unicodeScalars { emit(x) }; return }
            for d in String(u).decomposedStringWithCompatibilityMapping.unicodeScalars {
                switch d.properties.generalCategory {
                case .nonspacingMark, .spacingMark, .enclosingMark: continue
                default: emit(d)
                }
            }
        }
        for u in s.unicodeScalars {
            let v = u.value
            if v < 128 {
                emit(v >= 65 && v <= 90 ? Unicode.Scalar(v + 32)! : u)
            } else if let r = table[v] {
                for x in r.unicodeScalars { emit(x) }
            } else {
                for l in String(u).lowercased().unicodeScalars { emitMapped(l) }
            }
        }
        return String(out)
    }

    /// Canonical search key of a name: folded, abbreviations expanded, synonyms canonical ("Innsbruck Hauptbahnhof"
    /// and "innsbruck hbf" → "innsbruck hbf"). Use it to compare a typed text with a result title.
    public static func key(_ s: String) -> String {
        tokenize(s, isName: false).0.map(\.canonical).joined(separator: " ")
    }

    // MARK: lexing

    /// Raw lexemes of a folded string. Chunks are runs joined by '-' or '/'; any other non-alphanumeric character
    /// ends a chunk; '(' '[' … ')' ']' mark qualifiers; a '.' directly after a token marks it dotted.
    static func lex(_ folded: String) -> [PlaceLexeme] {
        if folded.utf8.allSatisfy({ $0 < 128 }) { return lexASCII(Array(folded.utf8)) }
        var toks: [PlaceLexeme] = []
        var depth = 0
        var chunk = 0.0
        var buf = String.UnicodeScalarView()
        func flush() {
            if !buf.isEmpty {
                toks.append(PlaceLexeme(raw: String(buf), qualifier: depth > 0, chunk: chunk, dotted: false))
                buf = String.UnicodeScalarView()
            }
        }
        for u in folded.unicodeScalars {
            if isAlnum(u) {
                buf.append(u)
            } else if u == "-" || u == "/" {
                flush()
            } else {
                flush()
                if u == ".", let last = toks.last, !last.dotted, last.chunk == chunk { toks[toks.count - 1].dotted = true }
                if u == "(" || u == "[" { depth += 1 } else if u == ")" || u == "]" { depth = max(0, depth - 1) }
                chunk += 1
            }
        }
        flush()
        return toks
    }

    /// `lex` for ASCII input (the common case after folding): byte scanning, one String per token.
    private static func lexASCII(_ b: [UInt8]) -> [PlaceLexeme] {
        var toks: [PlaceLexeme] = []
        toks.reserveCapacity(8)
        var depth = 0
        var chunk = 0.0
        var start = -1
        func flush(_ end: Int) {
            if start >= 0 {
                toks.append(PlaceLexeme(raw: String(decoding: b[start..<end], as: UTF8.self), qualifier: depth > 0,
                                        chunk: chunk, dotted: false))
                start = -1
            }
        }
        for i in b.indices {
            let c = b[i]
            if (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || (c >= 65 && c <= 90) {
                if start < 0 { start = i }
            } else if c == 45 || c == 47 {                                   // '-' '/'
                flush(i)
            } else {
                flush(i)
                if c == 46, let last = toks.last, !last.dotted, last.chunk == chunk { toks[toks.count - 1].dotted = true }
                if c == 40 || c == 91 { depth += 1 } else if c == 41 || c == 93 { depth = max(0, depth - 1) }
                chunk += 1
            }
        }
        flush(b.count)
        return toks
    }

    /// Per-token facts that do not depend on the neighbours (cached during the index build).
    struct TokenBase {
        var flags: UInt8            // without the qualifier bit
        var lexForms: [(String, Double)]     // synonyms + city abbreviations
        var splitForms: [(String, Double)]   // split head + suffix synonyms
    }

    final class TokenCache {
        var bases: [String: TokenBase] = [:]
        init() { bases.reserveCapacity(50_000) }
    }

    static func tokenBase(_ t: String) -> TokenBase {
        var lexForms: [(String, Double)] = []
        if let members = PlaceLexicon.synMembers[t] {
            let ct = PlaceLexicon.canon[t]
            for m in members { lexForms.append((m, PlaceLexicon.canon[m] == ct ? 1.0 : 0.9)) }
        }
        if let al = PlaceLexicon.aliasForms[t] { for a in al { lexForms.append((a, 0.9)) } }
        var split: [(String, Double)] = []
        let n = t.unicodeScalars.count
        if n >= 6 {
            for suf in PlaceLexicon.splitSuffixes where n - suf.utf8.count >= 3 && hasASCIISuffix(t, suf) {
                split.append((String(decoding: t.utf8.dropLast(suf.utf8.count), as: UTF8.self), 0.8))
                for m in PlaceLexicon.synMembers[suf] ?? [suf] { split.append((m, 0.8)) }
                break
            }
        }
        return TokenBase(flags: PlaceTok.flags(t, qualifier: false), lexForms: lexForms, splitForms: split)
    }

    /// §3.2 token-level abbreviation rules: i.T. → in tirol, i.Pg. → im pongau, i.M. → im muhlkreis, a.d. → an der,
    /// Wr. → wiener, b. → bei, i. → in (dotted forms only).
    static func abbreviate(_ lx: [PlaceLexeme]) -> [PlaceLexeme] {
        if !lx.contains(where: \.dotted) { return lx }
        let two: [((String, String), [String])] = [(("i", "t"), ["in", "tirol"]), (("i", "pg"), ["im", "pongau"]),
                                                   (("i", "m"), ["im", "muhlkreis"]), (("a", "d"), ["an", "der"])]
        let one: [String: String] = ["wr": "wiener", "b": "bei", "i": "in"]
        var out: [PlaceLexeme] = []
        out.reserveCapacity(lx.count + 2)
        var i = 0
        outer: while i < lx.count {
            let t = lx[i]
            let nxt: PlaceLexeme? = i + 1 < lx.count ? lx[i + 1] : nil
            if t.dotted, let n = nxt {
                for ((a, b), rep) in two where t.raw == a && n.raw == b && (b != "d" || n.dotted) {
                    for (k, w) in rep.enumerated() {
                        out.append(PlaceLexeme(raw: w, qualifier: t.qualifier, chunk: t.chunk + Double(k) * 0.5, dotted: false))
                    }
                    i += 2
                    continue outer
                }
            }
            if t.dotted, let rep = one[t.raw], t.raw == "wr" || nxt != nil {
                out.append(PlaceLexeme(raw: rep, qualifier: t.qualifier, chunk: t.chunk, dotted: false))
            } else {
                out.append(t)
            }
            i += 1
        }
        return out
    }

    @inline(__always) private static func hasASCIISuffix(_ t: String, _ suf: String) -> Bool {
        let a = t.utf8, b = suf.utf8
        guard a.count > b.count else { return a.count == b.count && a.elementsEqual(b) }
        return a.suffix(b.count).elementsEqual(b)
    }

    /// Tokens of a name or query plus "ends with a boundary" (space, '.' or ','; the last query token is then complete).
    static func tokenize(_ text: String, isName: Bool, cache: TokenCache? = nil) -> ([PlaceToken], Bool) {
        let lx = abbreviate(lex(fold(text)))
        var toks: [PlaceToken] = []
        toks.reserveCapacity(lx.count)
        var idx = 0
        while idx < lx.count {
            var end = idx
            while end + 1 < lx.count && lx[end + 1].chunk == lx[idx].chunk { end += 1 }
            let multi = end > idx
            for k in idx...end {
                let l = lx[k]
                let t = l.raw
                let qual = l.qualifier || (k > idx && PlaceLexicon.rivers.contains(t))   // 'Linz/Donau' → donau qualifier
                let base: TokenBase
                if let cache {
                    if let b = cache.bases[t] { base = b } else { base = tokenBase(t); cache.bases[t] = base }
                } else {
                    base = isName ? tokenBase(t) : TokenBase(flags: PlaceTok.flags(t, qualifier: false), lexForms: [], splitForms: [])
                }
                var flags = base.flags
                if qual { flags = (flags | PlaceTok.qualifier) & ~PlaceTok.essential }
                var tok = PlaceToken(raw: t, flags: flags, forms: [])
                if isName {
                    var forms: [(String, Double)] = [(t, 1.0)]
                    forms.reserveCapacity(1 + base.lexForms.count + base.splitForms.count + 1)
                    @inline(__always) func add(_ s: String, _ v: Double) {
                        if !forms.contains(where: { $0.0 == s }) { forms.append((s, v)) }
                    }
                    for (f, v) in base.lexForms { add(f, v) }
                    if multi && k < end {
                        var joined = ""
                        for j in k...end { joined += lx[j].raw }
                        add(joined, 0.95)
                    }
                    for (f, v) in base.splitForms { add(f, v) }
                    tok.forms = forms
                }
                toks.append(tok)
            }
            idx = end + 1
        }
        let trailing = text.unicodeScalars.last.map { $0.properties.isWhitespace || $0 == "." || $0 == "," } ?? false
        return (toks, trailing)
    }
}
