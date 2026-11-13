import Foundation

// MARK: radarmodes – „Zugart“ of the radar filter (docs/RADAR_MODES.md §6): the kind of a train or S-Bahn from its category. Buses, Bims and U-Bahnen
// have no Zugart: a Zugart filter never hides them.

public enum RadarTrainClass: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case rjx, rj, icec, njen, wb, cjx, rex, r, s, other

    public var id: Self { self }

    /// The chip title.
    public var title: String {
        switch self {
        case .rjx: "RJX"
        case .rj: "RJ"
        case .icec: "IC/EC"
        case .njen: "NJ/EN"
        case .wb: "WB"
        case .cjx: "CJX"
        case .rex: "REX"
        case .r: "R"
        case .s: "S"
        case .other: "Andere"
        }
    }

    /// What VoiceOver says for the chip.
    public var spoken: String {
        switch self {
        case .rjx: "Railjet Xpress"
        case .rj: "Railjet"
        case .icec: "Intercity und Eurocity"
        case .njen: "Nachtzug"
        case .wb: "WESTbahn"
        case .cjx: "Cityjet Xpress"
        case .rex: "Regionalexpress"
        case .r: "Regionalzug"
        case .s: "S-Bahn"
        case .other: "andere Züge"
        }
    }

    /// The Zugart of a vehicle's line: from the product class (WESTbahn 4096, S-Bahn 32) and the category; nil for everything that is no train or
    /// S-Bahn (Bus, Bim, U-Bahn, ship, rail replacement, no class).
    public static func of(_ line: Line?) -> RadarTrainClass? {
        guard let line else { return nil }
        switch line.productClass {
        case 4096: return .wb
        case 32: return .s
        case 1, 4, 8, 16: break
        default: return nil
        }
        return of(category: RadarLine.category(of: line))
    }

    /// The Zugart of a train category ("RJX", "IC", "EN", "REX", …); unknown categories are „Andere“.
    public static func of(category raw: String) -> RadarTrainClass {
        switch raw.uppercased().trimmingCharacters(in: .whitespaces) {
        case "RJX": .rjx
        case "RJ": .rj
        case "IC", "EC", "ICE", "ECE", "IR", "D": .icec
        case "NJ", "EN": .njen
        case "WB", "WESTBAHN": .wb
        case "CJX": .cjx
        case "REX": .rex
        case "R": .r
        case "S": .s
        default: .other
        }
    }
}
