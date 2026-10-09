import Foundation

// Plate family of a line (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §3.1). Pure, so offline and live lines
// (OEBB_LIVE `LinePresentation.plate` delegates here) get the same plate on iOS and in the Linux tests.

extension LineKind {
    /// BADGE_SPEC §3.1:
    /// - **rail:** category ∈ {RJX, RJ, ICE, ECE, EC, IC, D, TGV, WB, WESTbahn} → `fern`; {NJ, EN} or flag night →
    ///   `nacht`; {REX, CJX, R, RE, RB} → `regio`; `S`/`S\d` → `sBahn`; any other rail (private railways STB, ZB, MBS …)
    ///   → `regio`.
    /// - sbahn → `sBahn`, subway → `uBahn`, tram → `tram`, trolleybus → like bus.
    /// - **bus:** flag railReplacement or ref `SEV…`/`SV\d` → `sev`; flag night or `^N\d` → `nachtbus`; flag ski or
    ///   `S[ck]h?i-?bus` → `skibus`; flag onDemand or Rufbus/AST/ALT/Anrufsammel → `rufbus`; Wanderbus/Almbus → `wanderbus`;
    ///   else `bus`.
    /// - sev → `sev`, cable → `seilbahn`, ship → `schiff`, onDemand → `rufbus`, other → `sonst`.
    ///
    /// `services` are the stop's services (`PlaceTags.services`). They only classify lines without a number of their
    /// own: a stop tagged `hikingBus` turns a named line such as „Bus“ into a Wanderbus, never „852“ (the service
    /// tag says *a* hiking bus stops there, not which line it is).
    public static func classify(_ line: LineRef, services: [PlaceService] = []) -> LineKind {
        let ref = line.ref.trimmingCharacters(in: .whitespacesAndNewlines)
        switch line.mode {
        case .rail:
            return railKind(ref: ref, flags: line.flags)
        case .sBahn:
            return .sBahn
        case .subway:
            return .uBahn
        case .tram:
            return .tram
        case .bus, .trolleybus:
            return busKind(ref: ref, name: line.name ?? "", flags: line.flags, services: services)
        case .railReplacement:
            return .sev
        case .cable:
            return .seilbahn
        case .ship:
            return .schiff
        case .onDemand:
            return .rufbus
        case .other:
            return .sonst
        }
    }

    static let fernCategories: Set<String> = ["RJX", "RJ", "ICE", "ECE", "EC", "IC", "D", "TGV", "WB", "WESTBAHN"]
    static let nachtCategories: Set<String> = ["NJ", "EN"]
    static let regioCategories: Set<String> = ["REX", "CJX", "R", "RE", "RB"]

    static func railKind(ref: String, flags: LineFlags) -> LineKind {
        let cat = RailRef(ref).category.uppercased()
        if fernCategories.contains(cat) { return .fern }
        if nachtCategories.contains(cat) || flags.contains(.night) { return .nacht }
        if regioCategories.contains(cat) { return .regio }
        if cat == "S" { return .sBahn }
        return .regio
    }

    static func busKind(ref: String, name: String, flags: LineFlags, services: [PlaceService]) -> LineKind {
        if flags.contains(.railReplacement) || RailRef.isReplacementRef(ref) { return .sev }
        if flags.contains(.night) || RailRef.isNightBusRef(ref) { return .nachtbus }
        let text = ref + " " + name
        let folded = Array(PlaceNormalizer.fold(text).utf8)
        if flags.contains(.ski) || Self.containsAny(folded, Self.skiBusStems) { return .skibus }
        if flags.contains(.onDemand) || Self.containsAny(folded, Self.onDemandStems) || Self.hasWord(text, in: Self.onDemandWords) {
            return .rufbus
        }
        if Self.containsAny(folded, Self.hikingBusStems) { return .wanderbus }
        if !ref.contains(where: \.isNumber) {
            if services.contains(.hikingBus) { return .wanderbus }
            if services.contains(.skiBus), Self.containsAny(folded, Self.skiStems) { return .skibus }
        }
        return .bus
    }

    // stems on folded text, as UTF-8 bytes (built once)
    static let skiBusStems = ["skibus", "schibus", "ski-bus", "schi-bus", "ski bus", "schi bus", "scibus"].map { Array($0.utf8) }
    static let hikingBusStems = ["wanderbus", "wander-bus", "wander- und", "wandershuttle", "almbus", "alm-bus",
                                 "bergsteigerbus", "hikerbus", "hiking bus"].map { Array($0.utf8) }
    static let onDemandStems = ["rufbus", "anrufsammel", "anruf-sammel"].map { Array($0.utf8) }
    static let skiStems = ["ski", "schi"].map { Array($0.utf8) }
    static let onDemandWords: Set<String> = ["AST", "ALT"]

    /// `S[ck]h?i[- ]?bus` on folded text: Skibus, Schibus, Ski-Bus, Ski Bus, Schi-Bus.
    static func containsSkiBus(_ folded: String) -> Bool { containsAny(Array(folded.utf8), skiBusStems) }

    static func containsHikingBus(_ folded: String) -> Bool { containsAny(Array(folded.utf8), hikingBusStems) }

    static func containsAny(_ haystack: [UInt8], _ needles: [[UInt8]]) -> Bool {
        haystack.withUnsafeBufferPointer { h in needles.contains { n in n.first.map { contains(h, n, $0) } ?? true } }
    }

    /// Substring test on the UTF-8 bytes (exact for any needle; UTF-8 is self-synchronising). Foundation's
    /// `String.contains(_:)` bridges to NSString on Linux and is ~50× slower – this runs for every line of a stop.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let n = Array(needle.utf8)
        guard let first = n.first else { return true }
        let found: Bool? = haystack.utf8.withContiguousStorageIfAvailable { h -> Bool in
            Self.contains(h, n, first)
        }
        if let found { return found }
        return Array(haystack.utf8).withUnsafeBufferPointer { Self.contains($0, n, first) }
    }

    private static func contains(_ h: UnsafeBufferPointer<UInt8>, _ n: [UInt8], _ first: UInt8) -> Bool {
        guard h.count >= n.count else { return false }
        var i = 0
        let last = h.count - n.count
        while i <= last {
            if h[i] == first {
                var k = 1
                while k < n.count && h[i + k] == n[k] { k += 1 }
                if k == n.count { return true }
            }
            i += 1
        }
        return false
    }

    /// Case-sensitive whole-word match (AST/ALT must not match "Pasta" or "Altenmarkt").
    static func hasWord(_ text: String, in words: Set<String>) -> Bool {
        guard words.contains(where: { contains(text, $0) }) else { return false }      // fast path: no candidate at all
        var word = ""
        for c in text + " " {
            if c.isLetter {
                word.append(c)
            } else {
                if words.contains(word) { return true }
                word = ""
            }
        }
        return false
    }
}

/// Parts of a rail / line ref: "REX 41" → category "REX", number "41"; "EN40406" → "EN", "40406"; "RB 6/S6" keeps the
/// raw parts for the S-Bahn priority rule.
struct RailRef: Hashable {
    let raw: String
    /// Leading letters ("REX", "WESTbahn", "S"); "" for a numeric ref.
    let category: String
    /// The digits right after the category (optional space), "" if none.
    let number: String
    /// Anything after the digits ("x" in "REX 154x").
    let suffix: String

    init(_ ref: String) {
        if let fast = Self.asciiParts(ref) {
            (raw, category, number, suffix) = fast
            return
        }
        let s = ref.trimmingCharacters(in: .whitespaces)
        raw = s
        var cat = "", num = "", rest = ""
        var phase = 0
        for c in s {
            switch phase {
            case 0:
                if c.isLetter { cat.append(c) } else if c == " " && !cat.isEmpty { phase = 1 } else if c.isNumber {
                    num.append(c)
                    phase = 2
                } else { rest.append(c); phase = 3 }
            case 1:
                if c.isNumber { num.append(c); phase = 2 } else if c != " " { rest.append(c); phase = 3 }
            case 2:
                if c.isNumber { num.append(c) } else { rest.append(c); phase = 3 }
            default:
                rest.append(c)
            }
        }
        category = cat
        number = num
        suffix = rest.trimmingCharacters(in: .whitespaces)
    }

    /// The same parse on the bytes of an ASCII ref (every line ref in the data; `Character` iteration is the slow part
    /// of classifying a stop's lines). nil → the general path. ASCII letters/digits are exactly the ASCII characters
    /// with `isLetter` / `isNumber`; CR is excluded because "\r\n" is one `Character`.
    static func asciiParts(_ ref: String) -> (String, String, String, String)? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(ref.utf8.count)
        for b in ref.utf8 {
            guard b < 0x80, b != 0x0D else { return nil }
            bytes.append(b)
        }
        var lo = 0, hi = bytes.count
        while lo < hi && (bytes[lo] == 0x20 || bytes[lo] == 0x09) { lo += 1 }
        while hi > lo && (bytes[hi - 1] == 0x20 || bytes[hi - 1] == 0x09) { hi -= 1 }
        @inline(__always) func isLetter(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) }
        @inline(__always) func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
        var catEnd = lo, numStart = lo, numEnd = lo, restStart = hi
        var phase = 0, i = lo
        loop: while i < hi {
            let c = bytes[i]
            switch phase {
            case 0:
                if isLetter(c) { catEnd = i + 1 } else if c == 0x20 && catEnd > lo { phase = 1 } else if isDigit(c) {
                    numStart = i
                    numEnd = i + 1
                    phase = 2
                } else { restStart = i; break loop }
            case 1:
                if isDigit(c) { numStart = i; numEnd = i + 1; phase = 2 } else if c != 0x20 { restStart = i; break loop }
            default:
                if isDigit(c) { numEnd = i + 1 } else { restStart = i; break loop }
            }
            i += 1
        }
        if phase < 2 { numStart = catEnd; numEnd = catEnd }
        // the rest, trimmed like `trimmingCharacters(in: .whitespaces)` (ASCII: space and tab)
        var rs = restStart, re = hi
        while rs < re && (bytes[rs] == 0x20 || bytes[rs] == 0x09) { rs += 1 }
        while re > rs && (bytes[re - 1] == 0x20 || bytes[re - 1] == 0x09) { re -= 1 }
        func str(_ a: Int, _ b: Int) -> String { a < b ? String(decoding: bytes[a..<b], as: UTF8.self) : "" }
        return (str(lo, hi), str(lo, catEnd), str(numStart, numEnd), str(rs, re))
    }

    /// First byte of a ref is an ASCII letter (or not ASCII): only then can it have a category.
    @inline(__always) static func mayHaveCategory(_ ref: String) -> Bool {
        guard let f = ref.utf8.first(where: { $0 != 0x20 && $0 != 0x09 }) else { return false }
        return f >= 0x80 || (f >= 65 && f <= 90) || (f >= 97 && f <= 122)
    }

    /// `SEV`, `SEV 4`, `SV400`, `SV 400`.
    static func isReplacementRef(_ ref: String) -> Bool {
        guard mayHaveCategory(ref) else { return false }      // "852": no category, no parse
        let r = RailRef(ref)
        let c = r.category.uppercased()
        return c == "SEV" || (c == "SV" && !r.number.isEmpty)
    }

    /// `^N\d` (N25, N8, N60A).
    static func isNightBusRef(_ ref: String) -> Bool {
        guard mayHaveCategory(ref) else { return false }
        let r = RailRef(ref)
        return r.category == "N" && !r.number.isEmpty
    }
}
