import Foundation

// Verspätungs-Heatmap, the grid (docs/RADAR_HEATMAP.md §2). A fixed hexagonal grid over Austria, pointy-top, cells about 0.12°
// (13 km) from centre to centre. Pure geometry: no network, no clock, no UI. The grid does not depend on the screen or the zoom:
// the same place always falls into the same cell, whatever the camera shows, so a cell keeps its id from one answer to the next.

/// One cell of the heat grid, in axial hex coordinates (q: column, r: row counted north from the grid origin).
public struct HeatCellID: Sendable, Hashable, Comparable, Codable, Identifiable {
    public var q: Int
    public var r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    /// Row by row from the south, west to east inside a row: the order cells are listed and drawn in.
    public static func < (a: HeatCellID, b: HeatCellID) -> Bool {
        a.r != b.r ? a.r < b.r : a.q < b.q
    }

    public var id: HeatCellID { self }

    /// "12|-3": for logs, tests and accessibility identifiers.
    public var label: String { "\(q)|\(r)" }
}

public enum HeatGrid {
    /// Distance of two neighbouring cell centres in degrees of latitude (about 13.3 km). "About 0.12 degrees" of the brief.
    public static let spacingDegrees = 0.12
    /// Where the grid starts: the middle of Austria. A cell's id is its offset from here; changing these moves every id.
    public static let originLatitude = 47.7
    public static let originLongitude = 13.35

    public static let kmPerDegreeLatitude = 111.2
    /// One degree of longitude in km at the origin's latitude. The whole grid uses this one value, so the cells are regular in km
    /// at 47.7° and a few percent off in the north and south of Austria (46.3° to 49.1°), which nobody sees.
    static let kmPerDegreeLongitude = 111.2 * cos(47.7 * Double.pi / 180)
    /// Centre to corner of a hexagon in km: neighbours are `spacingDegrees` of latitude apart, which is √3 × radius.
    public static let radiusKm = spacingDegrees * kmPerDegreeLatitude / 3.0.squareRoot()
    /// Area of one cell in km² (a regular hexagon: 3/2 · √3 · r²).
    public static var cellAreaKm2: Double { 1.5 * 3.0.squareRoot() * radiusKm * radiusKm }

    // MARK: Projection

    /// Kilometres east and north of the origin.
    static func project(_ point: GeoPoint) -> (x: Double, y: Double) {
        ((point.longitude - originLongitude) * kmPerDegreeLongitude, (point.latitude - originLatitude) * kmPerDegreeLatitude)
    }

    static func unproject(x: Double, y: Double) -> GeoPoint {
        GeoPoint(latitude: originLatitude + y / kmPerDegreeLatitude, longitude: originLongitude + x / kmPerDegreeLongitude)
    }

    // MARK: Cells

    /// The cell a point falls into. Cube rounding: the one centre that is nearest, so every point has exactly one cell and a
    /// point on an edge goes to one side only. Non-finite coordinates give the origin's cell; callers drop such points first.
    public static func cell(containing point: GeoPoint) -> HeatCellID {
        guard point.latitude.isFinite, point.longitude.isFinite else { return HeatCellID(q: 0, r: 0) }
        let (x, y) = project(point)
        let q = (3.0.squareRoot() / 3 * x - y / 3) / radiusKm
        let r = (2.0 / 3 * y) / radiusKm
        let s = -q - r
        var rq = q.rounded(), rr = r.rounded()
        let rs = s.rounded()
        let dq = abs(rq - q), dr = abs(rr - r), ds = abs(rs - s)
        if dq > dr && dq > ds {
            rq = -rr - rs
        } else if dr > ds {
            rr = -rq - rs
        }
        return HeatCellID(q: Int(rq), r: Int(rr))
    }

    /// The centre of a cell.
    public static func center(of id: HeatCellID) -> GeoPoint {
        let x = radiusKm * 3.0.squareRoot() * (Double(id.q) + Double(id.r) / 2)
        let y = radiusKm * 1.5 * Double(id.r)
        return unproject(x: x, y: y)
    }

    /// The six corners of a cell, starting east-north-east and going counter-clockwise. `scale` 1 is the cell itself; a smaller
    /// value is the same hexagon around the same centre (the inner layers of the glow, the gap between two cells).
    public static func vertices(of id: HeatCellID, scale: Double = 1) -> [GeoPoint] {
        let centre = project(center(of: id))
        return (0..<6).map { index in
            let angle = (30 + 60 * Double(index)) * Double.pi / 180
            return unproject(x: centre.x + radiusKm * scale * cos(angle), y: centre.y + radiusKm * scale * sin(angle))
        }
    }

    /// The six neighbours, east first and counter-clockwise.
    public static func neighbors(of id: HeatCellID) -> [HeatCellID] {
        [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)].map { HeatCellID(q: id.q + $0.0, r: id.r + $0.1) }
    }

    /// Steps between two cells (0 for the same cell, 1 for neighbours).
    public static func distance(_ a: HeatCellID, _ b: HeatCellID) -> Int {
        let dq = a.q - b.q, dr = a.r - b.r
        return max(abs(dq), abs(dr), abs(dq + dr))
    }

    /// Straight-line distance of two points in km (plane, from the grid's own projection: good to a percent inside Austria).
    public static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let p = project(a), q = project(b)
        return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
    }

    // MARK: Hatching

    /// A zig-zag path of diagonal lines across a cell (`lines` parallel chords at 45°, joined at their ends): the hatching of a
    /// cell that has too few trains for a colour. One polyline instead of one per line keeps the number of map overlays small.
    /// Empty when `lines` is below one.
    public static func hatchPath(of id: HeatCellID, lines: Int = 3, scale: Double = 0.78) -> [GeoPoint] {
        guard lines >= 1 else { return [] }
        let centre = project(center(of: id))
        let corners = vertices(of: id, scale: scale).map(project)
        // Lines along (1, 1)/√2, stacked along the normal (1, -1)/√2 from -extent to +extent.
        let along = (x: 0.5.squareRoot(), y: 0.5.squareRoot())
        let normal = (x: 0.5.squareRoot(), y: -(0.5.squareRoot()))
        let extent = radiusKm * scale * 0.72
        var path: [GeoPoint] = []
        for index in 0..<lines {
            let offset = lines == 1 ? 0 : -extent + 2 * extent * Double(index) / Double(lines - 1)
            let origin = (x: centre.x + normal.x * offset, y: centre.y + normal.y * offset)
            guard var ends = clip(origin: origin, direction: along, to: corners) else { continue }
            if index % 2 == 1 { ends = (ends.1, ends.0) }
            path.append(unproject(x: ends.0.x, y: ends.0.y))
            path.append(unproject(x: ends.1.x, y: ends.1.y))
        }
        return path
    }

    /// The part of the infinite line `origin + t · direction` that lies inside a convex polygon (its two outermost crossings).
    private static func clip(origin: (x: Double, y: Double), direction: (x: Double, y: Double),
                             to polygon: [(x: Double, y: Double)]) -> ((x: Double, y: Double), (x: Double, y: Double))? {
        var hits: [Double] = []
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let edge = (x: b.x - a.x, y: b.y - a.y)
            let denominator = direction.x * edge.y - direction.y * edge.x
            guard abs(denominator) > 1e-12 else { continue }
            let rel = (x: a.x - origin.x, y: a.y - origin.y)
            let t = (rel.x * edge.y - rel.y * edge.x) / denominator
            let u = (rel.x * direction.y - rel.y * direction.x) / denominator
            if u >= -1e-9, u <= 1 + 1e-9 { hits.append(t) }
        }
        guard let low = hits.min(), let high = hits.max(), high - low > 1e-6 else { return nil }
        return ((origin.x + direction.x * low, origin.y + direction.y * low), (origin.x + direction.x * high, origin.y + direction.y * high))
    }
}
