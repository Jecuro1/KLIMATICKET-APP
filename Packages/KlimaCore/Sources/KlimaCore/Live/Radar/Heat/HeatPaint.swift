import Foundation

// Verspätungs-Heatmap, what is drawn (docs/RADAR_HEATMAP.md §3). The colour of a cell as three weights (green, orange, red), how
// many cells the map may draw at most, and the in-between states of a cross-fade. Pure: the app turns weights into colours.

/// A colour as weights of the three heat colours; they add up to 1.
public struct HeatBlend: Sendable, Hashable {
    public var green: Double
    public var orange: Double
    public var red: Double

    public init(green: Double, orange: Double, red: Double) {
        self.green = green
        self.orange = orange
        self.red = red
    }

    public static let none = HeatBlend(green: 0, orange: 0, red: 0)

    func mixed(with other: HeatBlend, _ t: Double) -> HeatBlend {
        HeatBlend(green: green + (other.green - green) * t, orange: orange + (other.orange - orange) * t, red: red + (other.red - red) * t)
    }
}

public enum HeatRamp {
    /// The colour of a median delay: pure green up to 3 minutes, pure orange from 7 to 13, pure red from 17, and a straight blend
    /// in between. The blends are centred on the limits (5 and 15 minutes): at 5:00 it is half green and half orange, at 15:00
    /// half orange and half red. Under 5 minutes green wins, between 5 and 15 orange, over 15 red.
    public static func blend(medianSeconds: Double) -> HeatBlend {
        let minutes = medianSeconds.isFinite ? medianSeconds / 60 : 0
        switch minutes {
        case ..<3:
            return HeatBlend(green: 1, orange: 0, red: 0)
        case 3..<7:
            let t = (minutes - 3) / 4
            return HeatBlend(green: 1 - t, orange: t, red: 0)
        case 7...13:
            return HeatBlend(green: 0, orange: 1, red: 0)
        case 13..<17:
            let t = (minutes - 13) / 4
            return HeatBlend(green: 0, orange: 1 - t, red: t)
        default:
            return HeatBlend(green: 0, orange: 0, red: 1)
        }
    }

    /// How solid a cell is drawn, 0.55 to 1: three trains are a faint colour, twelve or more a full one. The colour says how late;
    /// its strength says how much it rests on.
    public static func strength(sampleCount: Int) -> Double {
        0.55 + 0.45 * min(1, max(0, Double(sampleCount - RadarHeat.minimumSample) / 9))
    }
}

/// A cell as the map draws it. `strength` is its fade as well: a cell that appears or goes away runs between 0 and its value.
public struct HeatDrawCell: Sendable, Hashable, Identifiable {
    public var id: HeatCellID
    public var center: GeoPoint
    /// Fewer trains with a delay than `RadarHeat.minimumSample`: grey and hatched, never coloured.
    public var isNeutral: Bool
    public var blend: HeatBlend
    public var strength: Double
    public var trainCount: Int

    public init(id: HeatCellID, center: GeoPoint, isNeutral: Bool, blend: HeatBlend, strength: Double, trainCount: Int) {
        self.id = id
        self.center = center
        self.isNeutral = isNeutral
        self.blend = blend
        self.strength = strength
        self.trainCount = trainCount
    }

    /// Map overlays one cell costs: coloured, a scrim, a halo and the body; neutral, a body and its hatching.
    public var overlayCount: Int { isNeutral ? 2 : 3 }
}

public enum HeatLayer {
    /// Most cells the map draws at once. Austria has about 1 200 cells in all, and the ones that matter (coloured, with the most
    /// delay minutes) are kept first. At most three map overlays a cell: 3 × 300 = 900 overlays in the steady state, never one view
    /// per train.
    public static let maxDrawnCells = 300
    /// The most overlays the steady state may hold.
    public static let maxOverlays = 3 * maxDrawnCells

    /// The cells to draw: coloured cells first (most delay minutes, then most trains), then neutral ones (most trains), at most
    /// `cap`; the result is sorted by id, so the drawing order never changes between two answers.
    public static func drawCells(from snapshot: HeatSnapshot, cap: Int = maxDrawnCells) -> [HeatDrawCell] {
        guard cap > 0 else { return [] }
        let coloured = snapshot.cells.filter { !$0.isNeutral }.sorted { a, b in
            if a.delaySumMinutes != b.delaySumMinutes { return a.delaySumMinutes > b.delaySumMinutes }
            if a.trainCount != b.trainCount { return a.trainCount > b.trainCount }
            return a.id < b.id
        }
        let neutral = snapshot.cells.filter(\.isNeutral).sorted { a, b in
            a.trainCount != b.trainCount ? a.trainCount > b.trainCount : a.id < b.id
        }
        return (coloured + neutral).prefix(cap).map { cell in
            if let median = cell.medianDelaySeconds {
                return HeatDrawCell(id: cell.id, center: cell.center, isNeutral: false, blend: HeatRamp.blend(medianSeconds: median),
                                    strength: HeatRamp.strength(sampleCount: cell.sampleCount), trainCount: cell.trainCount)
            }
            return HeatDrawCell(id: cell.id, center: cell.center, isNeutral: true, blend: .none, strength: 1, trainCount: cell.trainCount)
        }.sorted { $0.id < $1.id }
    }

    /// The state between two sets of cells, `progress` 0 (the old cells) to 1 (the new ones): colours and strengths move linearly,
    /// a cell that is new fades in, one that is gone fades out. At 1 the new cells, exactly. Sorted by id. The result has at most the
    /// cells of both sets (2 × the cap, for a fraction of a second after an answer).
    public static func interpolate(from old: [HeatDrawCell], to new: [HeatDrawCell], progress: Double) -> [HeatDrawCell] {
        let t = progress.isFinite ? min(max(progress, 0), 1) : 1
        if t >= 1 { return new.sorted { $0.id < $1.id } }
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [HeatDrawCell] = []
        for id in Set(before.keys).union(after.keys).sorted() {
            switch (before[id], after[id]) {
            case let (a?, b?):
                var cell = b
                cell.isNeutral = t < 0.5 ? a.isNeutral : b.isNeutral
                cell.blend = a.blend.mixed(with: b.blend, t)
                cell.strength = a.strength + (b.strength - a.strength) * t
                result.append(cell)
            case let (nil, b?):
                var cell = b
                cell.strength = b.strength * t
                if cell.strength > 0.001 { result.append(cell) }
            case let (a?, nil):
                var cell = a
                cell.strength = a.strength * (1 - t)
                if cell.strength > 0.001 { result.append(cell) }
            case (nil, nil):
                break
            }
        }
        return result
    }
}
