import Foundation

/// Row and hero titles (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §3). `Place.title` stays the official display name; these
/// are presentation-only foldings, so the full name stays searchable and is what VoiceOver reads.
public enum PlaceTitle {
    /// Folded bracket words (dots and spaces removed) → state code. BADGE_SPEC §3: Vorarlberg, Vbg, Tirol, Kärnten,
    /// Ktn, Steiermark, Stmk, Salzburg, Sbg, NÖ, Niederösterreich, OÖ, Oberösterreich, Burgenland, Bgld, Wien.
    public static let stateBracketWords: [String: String] = [
        "vorarlberg": "V", "vbg": "V", "vlbg": "V",
        "tirol": "T",
        "karnten": "K", "ktn": "K",
        "steiermark": "ST", "stmk": "ST",
        "salzburg": "S", "sbg": "S",
        "no": "NÖ", "niederosterreich": "NÖ",
        "oo": "OÖ", "oberosterreich": "OÖ",
        "burgenland": "B", "bgld": "B",
        "wien": "W",
    ]

    /// Row title: `St.X` → `St. X`, arrow markers removed, and – only when the Landesmarke is visible in the same row
    /// (`stateShown`) – a bracket that holds a state name or abbreviation is folded:
    /// `Warth (Vorarlberg) Dorfplatz` → `Warth Dorfplatz`; `Lechen (Grafendorf) Fink` is unchanged.
    /// With `state` set, only a bracket naming that state is folded.
    public static func display(name: String, stateShown: Bool, state: String? = nil) -> String {
        var s = stripArrows(name)
        if stateShown { s = foldStateBrackets(s, state: state) }
        return PlaceNames.display(s)
    }

    /// Detail hero title: `display` without a trailing „Bahnhof“/„Hbf“/„Hauptbahnhof“ (the eyebrow says „BAHNHOF · …“):
    /// „St.Anton am Arlberg Bahnhof“ → („St. Anton am Arlberg“, „Bahnhof“). Rows keep the full name (people search
    /// for „Bahnhof“).
    public static func hero(name: String, stateShown: Bool = true, state: String? = nil)
        -> (title: String, droppedStationWord: String?) {
        let t = display(name: name, stateShown: stateShown, state: state)
        for word in ["Hauptbahnhof", "Bahnhof", "Hbf", "Hbf.", "Bhf", "Bhf.", "Bf", "Bf."] where t.hasSuffix(" " + word) {
            let rest = String(t.dropLast(word.count + 1)).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return (rest, word) }
        }
        return (t, nil)
    }

    /// Ranges of `title` to set in bold: each word whose folded form starts with a folded query token, up to the end
    /// of the matched prefix („warth“ in „Warth Dorfplatz“, „pol“ in „St. Pölten“). Sorted, non-overlapping.
    public static func highlightRanges(title: String, query: String) -> [Range<String.Index>] {
        let tokens = words(in: query).map { PlaceNormalizer.fold(String(query[$0])) }.filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var out: [Range<String.Index>] = []
        for w in words(in: title) {
            let word = title[w]
            let folded = PlaceNormalizer.fold(String(word))
            var best: String.Index?
            for t in tokens where folded.hasPrefix(t) {
                // shortest original prefix whose fold covers the token (folding can merge "oe" → "o" or expand "ß")
                var end = word.startIndex
                while end < word.endIndex {
                    end = word.index(after: end)
                    if PlaceNormalizer.fold(String(word[word.startIndex..<end])).count >= t.count { break }
                }
                if best == nil || end > best! { best = end }
            }
            if let best { out.append(w.lowerBound..<best) }
        }
        return out
    }

    // MARK: helpers

    /// Alphanumeric runs.
    static func words(in s: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isLetter || c.isNumber {
                if start == nil { start = i }
            } else if let st = start {
                out.append(st..<i)
                start = nil
            }
            i = s.index(after: i)
        }
        if let st = start { out.append(st..<s.endIndex) }
        return out
    }

    /// „Amstetten ---> Fa Avenarius“ → „Amstetten Fa Avenarius“ (SUGGEST_SPEC §9: `/\s*-+>\s*/` → space).
    static func stripArrows(_ s: String) -> String {
        guard s.contains("->") else { return s }
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "-" {
                var j = i
                while j < chars.count && chars[j] == "-" { j += 1 }
                if j < chars.count && chars[j] == ">" {
                    while out.last == " " { out.removeLast() }
                    out.append(" ")
                    i = j + 1
                    while i < chars.count && chars[i] == " " { i += 1 }
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func foldStateBrackets(_ s: String, state: String?) -> String {
        guard s.contains("(") else { return s }
        var out = ""
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let inner = rest[rest.index(after: open)..<close]
            let key = PlaceNormalizer.fold(String(inner)).filter { $0 != "." && $0 != " " }
            if let code = stateBracketWords[key], state == nil || state == code {
                out += rest[..<open]
                while out.last == " " { out.removeLast() }
                rest = rest[rest.index(after: close)...]
                if !out.isEmpty, let f = rest.first, f != " " { out.append(" ") }
            } else {
                out += rest[...close]
                rest = rest[rest.index(after: close)...]
            }
        }
        out += rest
        return out.trimmingCharacters(in: .whitespaces)
    }
}
