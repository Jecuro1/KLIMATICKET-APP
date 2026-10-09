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
        let text = ref + " " + name
        let folded = PlaceNormalizer.fold(text)
        if flags.contains(.railReplacement) || RailRef.isReplacementRef(ref) { return .sev }
        if flags.contains(.night) || RailRef.isNightBusRef(ref) { return .nachtbus }
        if flags.contains(.ski) || Self.containsSkiBus(folded) { return .skibus }
        if flags.contains(.onDemand) || folded.contains("rufbus") || folded.contains("anrufsammel")
            || folded.contains("anruf-sammel") || Self.hasWord(text, in: ["AST", "ALT"]) {
            return .rufbus
        }
        if Self.containsHikingBus(folded) { return .wanderbus }
        if !ref.contains(where: \.isNumber) {
            if services.contains(.hikingBus) { return .wanderbus }
            if services.contains(.skiBus), folded.contains("ski") || folded.contains("schi") { return .skibus }
        }
        return .bus
    }

    /// `S[ck]h?i[- ]?bus` on folded text: Skibus, Schibus, Ski-Bus, Ski Bus, Schi-Bus.
    static func containsSkiBus(_ folded: String) -> Bool {
        for stem in ["skibus", "schibus", "ski-bus", "schi-bus", "ski bus", "schi bus", "scibus"]
            where folded.contains(stem) { return true }
        return false
    }

    static func containsHikingBus(_ folded: String) -> Bool {
        for stem in ["wanderbus", "wander-bus", "wander- und", "wandershuttle", "almbus", "alm-bus", "bergsteigerbus",
                     "hikerbus", "hiking bus"] where folded.contains(stem) { return true }
        return false
    }

    /// Case-sensitive whole-word match (AST/ALT must not match "Pasta" or "Altenmarkt").
    static func hasWord(_ text: String, in words: Set<String>) -> Bool {
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

    /// `SEV`, `SEV 4`, `SV400`, `SV 400`.
    static func isReplacementRef(_ ref: String) -> Bool {
        let r = RailRef(ref)
        let c = r.category.uppercased()
        return c == "SEV" || (c == "SV" && !r.number.isEmpty)
    }

    /// `^N\d` (N25, N8, N60A).
    static func isNightBusRef(_ ref: String) -> Bool {
        let r = RailRef(ref)
        return r.category == "N" && !r.number.isEmpty
    }
}
