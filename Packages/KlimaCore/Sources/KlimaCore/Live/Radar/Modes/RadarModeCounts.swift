import Foundation

// MARK: radarmodes – how many vehicles of each mode the map shows (the counts line of the status card, docs/RADAR_MODES.md §9). Vehicles whose
// class is none of the five (class 0, rail replacement, coaches, ships, …) are „Andere“, so the line always adds up to the pill.

public struct RadarModeCounts: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        /// nil: „Andere“.
        public var mode: RadarMode?
        public var count: Int
        public var id: String { mode?.rawValue ?? "other" }

        public init(mode: RadarMode?, count: Int) {
            self.mode = mode
            self.count = count
        }
    }

    /// In chip order; „Andere“ last and only when there are any.
    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Counts the product classes of the shown vehicles. `shownModes`: the modes the line lists (on, and for city modes in zoom); a mode with
    /// 0 vehicles shows 0. A vehicle of a mode that is not listed (a class outside the five) counts as „Andere“.
    public init(productClasses: [Int], shownModes: [RadarMode]) {
        var counts: [RadarMode: Int] = [:]
        var other = 0
        for cls in productClasses {
            if let mode = RadarMode.of(productClass: cls), shownModes.contains(mode) {
                counts[mode, default: 0] += 1
            } else {
                other += 1
            }
        }
        var entries = RadarMode.allCases.filter(shownModes.contains).map { Entry(mode: $0, count: counts[$0] ?? 0) }
        if other > 0 { entries.append(Entry(mode: nil, count: other)) }
        self.entries = entries
    }

    public var total: Int { entries.reduce(0) { $0 + $1.count } }

    /// "Zug 21 · S-Bahn 28 · Bus 180 · Bim 92 · U-Bahn 12 · Andere 3".
    public var line: String {
        entries.map { "\(RadarModesText.label($0.mode)) \($0.count)" }.joined(separator: " · ")
    }

    /// "21 Züge, 28 S-Bahnen, 180 Busse, 92 Bims, 12 U-Bahnen, 3 andere Fahrzeuge".
    public var spoken: String {
        entries.map { RadarModesText.counted($0.count, $0.mode) }.joined(separator: ", ")
    }
}
