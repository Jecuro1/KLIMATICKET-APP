import MapKit
import KlimaCore

// MARK: radarheat – the corners of the cells as map coordinates, computed once per cell and size (docs/RADAR_HEATMAP.md §4). The map's
// content is rebuilt whenever the radar view's body runs (every few seconds while the trains are on), and a cell has up to three
// rings: 900 rings with six sines and cosines each, and two arrays per ring, would be rebuilt every time for the same hexagons. The
// grid is fixed, so a ring never changes: it is looked up instead. The cache is bounded (the radar's rectangle holds about 1 200
// cells, five sizes each) and starts over when it is full.

@MainActor
enum HeatGeometry {
    private struct Key: Hashable {
        var id: HeatCellID
        var scale: Int
    }

    private static var rings: [Key: [CLLocationCoordinate2D]] = [:]
    private static var hatches: [HeatCellID: [CLLocationCoordinate2D]] = [:]
    /// 1 200 cells × 5 rings = 6 000, with room: about a megabyte at most.
    static let ringLimit = 8_000
    static let hatchLimit = 2_000

    /// The six corners of a cell (`HeatGrid.vertices(of:scale:)`) as map coordinates.
    static func ring(_ id: HeatCellID, scale: Double) -> [CLLocationCoordinate2D] {
        let key = Key(id: id, scale: Int((scale * 100).rounded()))
        if let hit = rings[key] { return hit }
        if rings.count >= ringLimit { rings.removeAll(keepingCapacity: true) }
        let ring = HeatGrid.vertices(of: id, scale: scale).map(\.clCoordinate)
        rings[key] = ring
        return ring
    }

    /// The hatching of a neutral cell (`HeatGrid.hatchPath`) as map coordinates.
    static func hatch(_ id: HeatCellID) -> [CLLocationCoordinate2D] {
        if let hit = hatches[id] { return hit }
        if hatches.count >= hatchLimit { hatches.removeAll(keepingCapacity: true) }
        let path = HeatGrid.hatchPath(of: id).map(\.clCoordinate)
        hatches[id] = path
        return path
    }

    /// Entries held right now (for the test of the bound).
    static var cachedCount: Int { rings.count + hatches.count }
}
