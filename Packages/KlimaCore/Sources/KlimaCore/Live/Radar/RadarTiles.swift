import Foundation

// Zug-Radar tile grid (docs/OEBB_LIVE.md §R11). A fixed global quadtree over Austria: every tile has a key, so answers are
// cached per tile and stay valid while the map moves. Level 0 is two tiles side by side (2.8° × 3.9° each, about 311 × 290 km,
// together exactly `RadarBox.austria`); every level halves both sides. The tile key is the same for the same place at any
// time and on any screen, so nothing depends on where the camera happens to be.

/// MARK: radarmodes – the two request lanes of the radar (docs/RADAR_MODES.md §3). The wide lane asks for trains and S-Bahnen on the grid down to
/// level 6, the city lane for Bus, Bim and U-Bahn one level finer and down to level 8, only while the map is zoomed in. Both lanes are tiles of
/// the one scheduler and share its one budget.
public enum RadarLane: Int, Sendable, Hashable, Comparable, CaseIterable {
    case wide = 0, city = 1

    public static func < (a: RadarLane, b: RadarLane) -> Bool { a.rawValue < b.rawValue }
}

/// One tile of the grid. `row` counts north from the south edge of Austria, `col` east from its west edge. `lane`: which request lane asks for
/// it (a city tile and a wide tile of the same place are two tiles with their own answers).
public struct RadarTileKey: Hashable, Sendable, Comparable {
    public var level: Int
    public var row: Int
    public var col: Int
    public var lane: RadarLane

    public init(level: Int, row: Int, col: Int, lane: RadarLane = .wide) {
        self.level = level
        self.row = row
        self.col = col
        self.lane = lane
    }

    public static func < (a: RadarTileKey, b: RadarTileKey) -> Bool {
        if a.lane != b.lane { return a.lane < b.lane }
        if a.level != b.level { return a.level < b.level }
        return a.row != b.row ? a.row < b.row : a.col < b.col
    }

    /// "2/1/3": level, row, column; a city tile "c7/1/3". For logs and tests.
    public var label: String { "\(lane == .city ? "c" : "")\(level)/\(row)/\(col)" }
}

public extension RadarBox {
    /// True when the two boxes share area. Boxes that only touch at an edge do not intersect, and neither do boxes that
    /// overlap by less than a nanodegree (0.1 mm): a view edge that is one rounding step past a tile edge asks for no tile.
    func intersects(_ other: RadarBox) -> Bool {
        let hair = 1e-9
        return south < other.north - hair && north > other.south + hair && west < other.east - hair && east > other.west + hair
    }
}

public enum RadarTileGrid {
    /// The area the radar covers: Austria with a small margin (`RadarBox.austria`). Outside there are no tiles.
    public static let coverage = RadarBox.austria
    /// Height and width of a level-0 tile in degrees. Two tiles side by side cover `coverage`.
    public static let rootLatitudeSpan = 2.8
    public static let rootLongitudeSpan = 3.9
    /// The finest level of the wide lane: 0.044° × 0.061° (about 4.9 × 4.6 km). A tile that is still cut off there is said so in the status.
    public static let maxLevel = 6
    /// MARK: radarmodes – the finest level of the city lane: 0.011° × 0.015° (about 1.2 × 1.1 km). Level 7 is about 2.4 × 2.3 km.
    public static let cityMaxLevel = 8

    /// The finest level a lane splits down to.
    public static func finestLevel(for lane: RadarLane) -> Int { lane == .city ? cityMaxLevel : maxLevel }

    /// Rows and columns at a level: 2^level rows, 2 · 2^level columns. Clamped at the finest level of any lane (8): a level-7 or level-8
    /// key of the city lane gets its own box, not a level-6 one.
    public static func rows(atLevel level: Int) -> Int { 1 << min(max(level, 0), cityMaxLevel) }
    public static func columns(atLevel level: Int) -> Int { 2 << min(max(level, 0), cityMaxLevel) }

    public static func latitudeSpan(atLevel level: Int) -> Double { rootLatitudeSpan / Double(rows(atLevel: level)) }
    public static func longitudeSpan(atLevel level: Int) -> Double { rootLongitudeSpan / Double(rows(atLevel: level)) }

    public static func isValid(_ key: RadarTileKey) -> Bool {
        (0...finestLevel(for: key.lane)).contains(key.level) && (0..<rows(atLevel: key.level)).contains(key.row)
            && (0..<columns(atLevel: key.level)).contains(key.col)
    }

    /// The rectangle of a tile. A child's edges are computed from the same integers as its parent's, so neighbouring tiles
    /// share their edge bit for bit and there is neither a gap nor an overlap between them.
    public static func box(of key: RadarTileKey) -> RadarBox {
        let latSize = latitudeSpan(atLevel: key.level), lonSize = longitudeSpan(atLevel: key.level)
        let south = coverage.south + Double(key.row) * latSize
        let west = coverage.west + Double(key.col) * lonSize
        return RadarBox(north: coverage.south + Double(key.row + 1) * latSize, west: west,
                        south: south, east: coverage.west + Double(key.col + 1) * lonSize)
    }

    /// The level whose tiles are at least as tall as the visible latitude span (and less than twice as tall), so a view
    /// touches at most 2 × 2 tiles: a country view two tiles, a city view one to four small ones. 0 for an invalid span.
    public static func level(forLatitudeSpan span: Double) -> Int {
        guard span.isFinite, span > 0 else { return 0 }
        let ratio = rootLatitudeSpan / span
        guard ratio >= 1 else { return 0 }
        guard ratio.isFinite else { return maxLevel }   // a denormal span: the finest level
        return min(Int(min(log2(ratio), 64).rounded(.down)), maxLevel)
    }

    /// MARK: radarmodes – the city lane's level for a view: one level finer than the wide lane would take (`cityLevelOffset`), from the span
    /// itself (not the wide lane's clamped level), at most `cityMaxLevel`. A Wien view of 0.12° gets level 5 (9.7 × 9 km tiles).
    public static func cityLevel(forLatitudeSpan span: Double, offset: Int = RadarLanePlan.cityLevelOffset) -> Int {
        guard span.isFinite, span > 0 else { return min(max(offset, 0), cityMaxLevel) }
        let ratio = rootLatitudeSpan / span
        guard ratio >= 1 else { return min(max(offset, 0), cityMaxLevel) }
        guard ratio.isFinite else { return cityMaxLevel }
        return min(max(Int(min(log2(ratio), 64).rounded(.down)) + offset, 0), cityMaxLevel)
    }

    /// The tiles of `level` that share area with `box`, south-west first. Only tiles inside the coverage exist.
    public static func tiles(intersecting box: RadarBox, level: Int) -> [RadarTileKey] {
        tiles(intersecting: box, level: level, lane: .wide)
    }

    /// The same for a lane: the level is clamped at the lane's finest level, the keys carry the lane.
    public static func tiles(intersecting box: RadarBox, level: Int, lane: RadarLane) -> [RadarTileKey] {
        guard box.isValid, box.intersects(coverage) else { return [] }
        let level = min(max(level, 0), finestLevel(for: lane))
        let latSize = latitudeSpan(atLevel: level), lonSize = longitudeSpan(atLevel: level)
        // The same hair as in `intersects`: an edge one rounding step past a tile edge does not reach into the next tile.
        let hair = 1e-9
        let rowLow = max(Int(((box.south - coverage.south) / latSize + hair).rounded(.down)), 0)
        let rowHigh = min(Int(((box.north - coverage.south) / latSize - hair).rounded(.up)) - 1, rows(atLevel: level) - 1)
        let colLow = max(Int(((box.west - coverage.west) / lonSize + hair).rounded(.down)), 0)
        let colHigh = min(Int(((box.east - coverage.west) / lonSize - hair).rounded(.up)) - 1, columns(atLevel: level) - 1)
        guard rowLow <= rowHigh, colLow <= colHigh else { return [] }
        var keys: [RadarTileKey] = []
        for row in rowLow...rowHigh {
            for col in colLow...colHigh {
                keys.append(RadarTileKey(level: level, row: row, col: col, lane: lane))
            }
        }
        return keys
    }

    /// The four tiles one level down (south-west, south-east, north-west, north-east); empty at the finest level of the key's lane. The
    /// children keep the lane.
    public static func children(of key: RadarTileKey) -> [RadarTileKey] {
        guard isValid(key), key.level < finestLevel(for: key.lane) else { return [] }
        let level = key.level + 1
        return [RadarTileKey(level: level, row: key.row * 2, col: key.col * 2, lane: key.lane),
                RadarTileKey(level: level, row: key.row * 2, col: key.col * 2 + 1, lane: key.lane),
                RadarTileKey(level: level, row: key.row * 2 + 1, col: key.col * 2, lane: key.lane),
                RadarTileKey(level: level, row: key.row * 2 + 1, col: key.col * 2 + 1, lane: key.lane)]
    }

    /// The tile one level up (same lane); nil at level 0.
    public static func parent(of key: RadarTileKey) -> RadarTileKey? {
        guard isValid(key), key.level > 0 else { return nil }
        return RadarTileKey(level: key.level - 1, row: key.row / 2, col: key.col / 2, lane: key.lane)
    }
}
