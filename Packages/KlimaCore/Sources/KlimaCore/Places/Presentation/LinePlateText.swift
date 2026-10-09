import Foundation

/// Glyph shown on (or instead of) a plate's text. `symbolName` is the SF Symbol (BADGE_SPEC §2.1, §6).
public enum PlateGlyph: String, Sendable, Hashable, CaseIterable {
    case snowflake, moonStars, phone, hiking, cableCar, ferry, bus, tram, train

    public var symbolName: String {
        switch self {
        case .snowflake: return "snowflake"
        case .moonStars: return "moon.stars.fill"
        case .phone: return "phone.fill"
        case .hiking: return "figure.hiking"
        case .cableCar: return "cablecar.fill"
        case .ferry: return "ferry.fill"
        case .bus: return "bus.fill"
        case .tram: return "tram.fill"
        case .train: return "train.side.front.car"
        }
    }
}

/// Plate text normalisation (docs/ENRICH_SPEC.md §2.5, BADGE_SPEC §2.1 „Plakettentext normalisieren“). The text never
/// exceeds the size's character budget and is never cut with „…“: what does not fit falls back to a shorter rule or
/// to the glyph alone.
public enum LinePlateText {
    /// Plate sizes (BADGE_SPEC §2.1). The SwiftUI `PlateSize` maps 1:1 by raw value.
    public enum Size: String, Sendable, Hashable, CaseIterable {
        case xs, s, m, l

        /// 5 at xs/s, 6 at m, 8 at l.
        public var maxCharacters: Int {
            switch self {
            case .xs, .s: return 5
            case .m: return 6
            case .l: return 8
            }
        }
        /// Cable cars and ships keep names up to 10 characters from m on (rule 5: „Hungerburg“, „Twin City“).
        var maxNameCharacters: Int {
            switch self {
            case .xs, .s: return 5
            case .m, .l: return 10
            }
        }
    }

    public typealias Plate = (text: String, glyph: PlateGlyph?)

    /// Text and glyph of `line`'s plate at `size`. `services` = the stop's services (classification hint, see
    /// `LineKind.classify`).
    public static func text(for line: LineRef, size: Size, services: [PlaceService] = []) -> Plate {
        text(for: line, kind: LineKind.classify(line, services: services), size: size)
    }

    /// Same with an already classified kind (live lines, tests).
    public static func text(for line: LineRef, kind: LineKind, size: Size) -> Plate {
        let ref = trimmed(line.ref)
        let cap = size.maxCharacters
        switch kind {
        case .fern, .nacht:
            let glyph: PlateGlyph? = kind == .nacht ? .moonStars : nil
            let cat = canonicalCategory(RailRef(ref.isEmpty ? (line.name ?? "") : ref).category)
            return cat.isEmpty || cat.count > cap ? ("", glyph ?? .train) : (cat, glyph)
        case .regio, .sBahn:
            if let t = railLineText(ref: ref, kind: kind, cap: cap), !t.isEmpty { return (t, nil) }
            return ("", .train)
        case .uBahn:
            let r = RailRef(ref)
            let t = r.category.isEmpty ? (r.number.isEmpty ? "U" : "U" + r.number) : r.category.uppercased() + r.number
            return t.count <= cap ? (t, nil) : ("U", nil)
        case .seilbahn, .schiff:
            let glyph: PlateGlyph = kind == .seilbahn ? .cableCar : .ferry
            let t = namedTransportText(ref: ref, name: line.name, maxCharacters: size.maxNameCharacters)
            return t.isEmpty ? ("", glyph) : (t, glyph)
        case .tram, .bus, .nachtbus, .skibus, .wanderbus, .rufbus, .sev, .sonst:
            return busText(ref: ref.isEmpty ? (line.name ?? "") : ref, kind: kind, size: size, cap: cap)
        }
    }

    /// Dedupe key of M3 / `LinePlateOrder`: family + the plate at the largest size (glyph-only plates by glyph).
    public static func dedupeKey(_ line: LineRef, services: [PlaceService] = []) -> String {
        let kind = LineKind.classify(line, services: services)
        return dedupeKey(kind: kind, plate: text(for: line, kind: kind, size: .l))
    }

    static func dedupeKey(kind: LineKind, plate p: Plate) -> String {
        "\(kind.rawValue)|\(p.text.uppercased())|\(p.text.isEmpty ? (p.glyph?.rawValue ?? "") : "")"
    }

    // MARK: rules

    /// Long-distance and night trains: the category only (`EN 40465` → `EN`, `RJ 255` → `RJ`, `WESTbahn` → `WB`).
    static func canonicalCategory(_ letters: String) -> String {
        let u = letters.uppercased()
        if u == "WESTBAHN" { return "WB" }
        if LineKind.fernCategories.contains(u) || LineKind.nachtCategories.contains(u) { return u }
        return letters
    }

    /// Regional trains and S-Bahn: category + line number without spaces (`REX 41` → `REX41`, `S 4` → `S4`);
    /// `RB 6/S6` → `S6` (S wins); train numbers (3+ digits or a letter suffix: `REX 154x`) → the category alone.
    static func railLineText(ref: String, kind: LineKind, cap: Int) -> String? {
        let parts = ref.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 1, let s = parts.map(RailRef.init).first(where: { $0.category.uppercased() == "S" && !$0.number.isEmpty }) {
            return fit("S" + s.number, cap)
        }
        let r = RailRef(parts.first ?? ref)
        var cat = r.category
        switch cat.lowercased() {
        case "regionalzug": cat = "R"
        case "regionalexpress": cat = "REX"
        case "s-bahn", "sbahn": cat = "S"
        default: break
        }
        if cat.isEmpty {
            // a bare number: S-Bahn "4" → "S4"; anything else keeps the number
            guard !r.number.isEmpty else { return nil }
            return fit(kind == .sBahn ? "S" + r.number : r.number, cap)
        }
        if LineKind.regioCategories.contains(cat.uppercased()) || cat.uppercased() == "S" || cat.uppercased() == "CJX" {
            cat = cat.uppercased()
        }
        if !r.number.isEmpty, r.number.count <= 2, r.suffix.isEmpty, let t = fit(cat + r.number, cap) { return t }
        return fit(cat, cap)
    }

    /// Bus, tram and the special buses (BADGE_SPEC §2.1 rules 3 + 4).
    static func busText(ref: String, kind: LineKind, size: Size, cap: Int) -> Plate {
        let glyph: PlateGlyph?
        switch kind {
        case .skibus: glyph = .snowflake
        case .wanderbus: glyph = .hiking
        case .rufbus: glyph = .phone
        case .nachtbus: glyph = ref.uppercased().hasPrefix("N") ? nil : .moonStars
        default: glyph = nil
        }
        let modeGlyph: PlateGlyph = kind == .tram ? .tram : .bus
        // rule 3: short refs as they are; with a slash only the first part ("9773/5" → "9773")
        let first = ref.utf8.contains(0x2F)
            ? ref.split(separator: "/", omittingEmptySubsequences: true).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ref
            : ref                                           // `text(for:)` already trimmed it
        if !first.isEmpty, first.utf8.count <= 5 || first.count <= 5 { return (first, glyph) }
        if first.isEmpty { return ("", glyph ?? modeGlyph) }
        // rule 4: named refs longer than 5 characters, at every size („Skibus“ → ❄ / „Ski“, „Stadtbus“ → „Stadt“)
        switch kind {
        case .skibus, .wanderbus, .rufbus:
            guard size == .m || size == .l else { return ("", glyph) }
            let short = kind == .skibus ? "Ski" : (kind == .rufbus ? "Ruf" : "Wander")
            return short.count <= cap ? (short, glyph) : ("", glyph)
        default:
            var word = first.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == ":" || $0 == "–" }).first
                .map(String.init) ?? first
            if word.count > 7, word.lowercased().hasSuffix("bus") { word = String(word.dropLast(3)) }
            if !word.isEmpty, word.count <= min(7, cap) { return (word, glyph) }
            return ("", glyph ?? modeGlyph)
        }
    }

    /// Cable cars and ships (rule 5): the name without the ending „bahn“ / „schifffahrt“, at most `maxCharacters`
    /// (`Hungerburgbahn` → `Hungerburg`, `Achenseeschifffahrt` → `Achensee`, `Twin City Liner` → `Twin City`);
    /// refs like „Nord“/„Süd“ get the lake from `name` („Attersee N“).
    static func namedTransportText(ref: String, name: String?, maxCharacters: Int) -> String {
        let compass = ["nord", "sud", "ost", "west"]
        if compass.contains(PlaceNormalizer.fold(ref)), let name, let lake = name.split(separator: " ").first {
            let t = stripTransportSuffix(String(lake)) + " " + String(ref.prefix(1)).uppercased()
            if t.count <= maxCharacters { return t }
        }
        let base = ref.isEmpty ? (name ?? "") : ref
        if base.count <= maxCharacters, !base.isEmpty { return base }
        var words = base.split(separator: " ").map { stripTransportSuffix(String($0)) }.filter { !$0.isEmpty }
        while !words.isEmpty {
            let t = words.joined(separator: " ")
            if t.count <= maxCharacters { return t }
            words.removeLast()
        }
        return ""
    }

    static func stripTransportSuffix(_ word: String) -> String {
        for suffix in ["schifffahrt", "schiffahrt", "schiffart", "bahn"] where word.count > suffix.count + 2 {
            if word.lowercased().hasSuffix(suffix) { return String(word.dropLast(suffix.count)) }
        }
        return word
    }

    static func fit(_ t: String, _ cap: Int) -> String? { t.count <= cap ? t : nil }

    /// `trimmingCharacters(in: .whitespacesAndNewlines)` without the Foundation call when both ends are printable
    /// ASCII (nothing to trim) – every ref in the data.
    static func trimmed(_ s: String) -> String {
        if let f = s.utf8.first, let l = s.utf8.last, f > 0x20, f < 0x7F, l > 0x20, l < 0x7F { return s }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
