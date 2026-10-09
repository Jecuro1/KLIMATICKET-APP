import Foundation

/// Plate and title texts of live lines (SPEC §C3.2).
///
/// **Plates delegate to the stop-enrichment presentation** (docs/ENRICH_SPEC.md D7 / §2.5 [DECISION]): live and
/// offline lines look identical, so `plate(_:)` returns `LinePlateText.text(for: <LineRef of the live line>, size: .s).text`.
/// The BADGE_SPEC plates supersede the C3.2 table: S-Bahn „S4“, regional „CJX5“ / „REX51“, tram „5“, metro „U6“
/// (never „UU6“), long distance the category („RJX“), bus the line number („750“).
public enum LinePresentation {
    /// Plate text at the list size (`.s`, at most 5 characters). Empty when the plate is a glyph only (e.g. a Skibus
    /// at small sizes) – use `plate(_:size:)` for the glyph.
    public static func plate(_ line: Line) -> String {
        plate(line, size: .s).text
    }

    /// Text and glyph of the plate at `size` (BADGE_SPEC §2.1).
    public static func plate(_ line: Line, size: LinePlateText.Size) -> LinePlateText.Plate {
        let ref = LiveLineRefAdapter.lineRef(from: line)
        return LinePlateText.text(for: ref, kind: LineKind.classify(ref), size: size)
    }

    /// Plate family (styling: shape, fill) – same classifier as offline lines.
    public static func kind(_ line: Line) -> LineKind {
        LineKind.classify(LiveLineRefAdapter.lineRef(from: line))
    }

    /// Detail title: „RJX 19910“, „Bus 760“, „REX 51 (Zug-Nr. 1628)“, „S 4“, „U6“, „Tram 5“.
    public static func title(_ line: Line) -> String {
        let cat = category(line)
        let lineNo = trimmed(line.lineNumber)
        let num = trimmed(line.trainNumber)
        let k = kind(line)
        if k == .fern || k == .nacht {
            guard !cat.isEmpty else { return line.name }
            return num.map { "\(cat) \($0)" } ?? cat
        }
        switch line.mode {
        case .bus:
            let n = busNumber(line)
            return n.map { "Bus \($0)" } ?? "Bus"
        case .tram:
            return lineNo.map { "Tram \($0)" } ?? line.name
        case .sBahn:
            return lineNo.map { "S \($0)" } ?? (cat.isEmpty ? line.name : cat)
        case .metro:
            guard let lineNo else { return line.name }
            return lineNo.uppercased().hasPrefix("U") ? lineNo : "U\(lineNo)"
        case .train:
            guard !cat.isEmpty else { return line.name }
            if let lineNo {
                let plate = "\(cat) \(lineNo)"
                if let num, num != lineNo { return "\(plate) (Zug-Nr. \(num))" }
                return plate
            }
            return num.map { "\(cat) \($0)" } ?? cat
        case .ferry, .cableCar, .other:
            return line.name
        }
    }

    /// „RJX 19910 · Bus 760“ – titles of the ride legs.
    public static func lineSummary(_ lines: [Line]) -> String {
        lines.map(title).joined(separator: " · ")
    }

    // MARK: helpers

    /// Display category: `catOutS` unless it is a lower-case code („s“, „str“, „obu“), else `catOut`.
    static func category(_ line: Line) -> String {
        if let s = trimmed(line.categoryShort), s.first?.isUppercase == true { return s }
        return trimmed(line.category) ?? trimmed(line.categoryShort) ?? ""
    }

    /// Bus line number: `lineNumber`, else the name without „Bus“ (reference `product()`); nil when nothing is left.
    static func busNumber(_ line: Line) -> String? {
        if let n = trimmed(line.lineNumber) { return n }
        var rest = line.name
        if rest.hasPrefix("Bus") { rest = String(rest.dropFirst(3)) }
        return trimmed(rest)
    }

    static func trimmed(_ s: String?) -> String? {
        s?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }
}

/// Live `Line` → offline `LineRef` (ENRICH_SPEC §4.3 step 3, „live plate key“). Tiny internal adapter until the
/// enrichment work package WP-L ships `LiveLineMatcher.lineRef(from:)`; `LinePresentation` should then call that.
///
/// - Mode from the ÖBB HAFAS product class: 1/4/8/16/4096 → rail, 2 → rail replacement, 32 → S-Bahn, 64 → bus,
///   128 → ship, 256 → subway, 512 → tram, 1024 (long-distance coach) → other, 2048 → cable.
/// - Ref like the offline refs: long distance the category („RJX“, „NJ“, „WB“); REX/CJX/R/S `category + lineNumber`
///   without spaces („REX51“, „S4“); bus, tram, subway the line number („750“, „5“, „U6“); ships and cable cars the name.
enum LiveLineRefAdapter {
    static func lineRef(from line: Line) -> LineRef {
        let mode = lineMode(line)
        let cat = (LinePresentation.trimmed(line.category) ?? LinePresentation.trimmed(line.categoryShort) ?? "")
        let lineNo = LinePresentation.trimmed(line.lineNumber)
        let ref: String
        switch mode {
        case .rail:
            if [1, 4, 8, 4096].contains(line.productClass) || lineNo == nil {
                ref = cat.isEmpty ? line.name : cat
            } else if let lineNo {
                // A line number that already carries the category („S4“) is kept as it is.
                ref = (lineNo.uppercased().hasPrefix(cat.uppercased()) ? lineNo : cat + lineNo).replacingOccurrences(of: " ", with: "")
            } else {
                ref = cat
            }
        case .sBahn:
            if let lineNo {
                ref = (lineNo.uppercased().hasPrefix("S") ? lineNo : "S" + lineNo).replacingOccurrences(of: " ", with: "")
            } else {
                ref = "S"
            }
        case .bus, .tram, .subway, .railReplacement, .trolleybus, .onDemand:
            ref = lineNo ?? LinePresentation.busNumber(line) ?? cat
        case .ship, .cable, .other:
            ref = lineNo ?? line.name
        }
        return LineRef(id: "live:\(line.lineId ?? ref)", ref: ref, mode: mode, operatorName: line.operatorName,
                       name: line.fullName ?? line.name, sources: .live)
    }

    static func lineMode(_ line: Line) -> LineMode {
        switch line.productClass {
        case 1, 4, 8, 16, 4096: return .rail
        case 2: return .railReplacement
        case 32: return .sBahn
        case 64: return .bus
        case 128: return .ship
        case 256: return .subway
        case 512: return .tram
        case 1024: return .other
        case 2048: return .cable
        default:
            // Lines without a HAFAS class (demo data, other providers): fall back to the app mode.
            switch line.mode {
            case .train: return .rail
            case .sBahn: return .sBahn
            case .metro: return .subway
            case .tram: return .tram
            case .bus: return .bus
            case .ferry: return .ship
            case .cableCar: return .cable
            case .other: return .other
            }
        }
    }
}
