import Foundation

// MARK: radartrail – the lines of „Spuren“ (docs/RADAR_TRAILS.md §2). A trail ends exactly at the drawn marker, never at the newest answer:
// the radar draws every vehicle 20 to 120 s behind the clock (`RadarEstimate`), so the newest answer lies ahead of the marker. Samples newer
// than the drawn moment are left out, a gap of more than 150 s breaks the line (the missing minutes are a gap, never a line), the points are
// thinned to what the zoom can show, and the newest line is split by time into an older and a newer half for the fade.

/// One point of a trail with the moment it belongs to.
public struct RadarTrailPoint: Sendable, Hashable {
    public var coordinate: GeoPoint
    public var at: Date

    public init(coordinate: GeoPoint, at: Date) {
        self.coordinate = coordinate
        self.at = at
    }
}

/// One unbroken piece of a trail.
public struct RadarTrailLine: Sendable, Hashable {
    public var points: [RadarTrailPoint]
    /// The piece that ends at the marker (only it fades in two halves; older pieces are drawn pale).
    public var isNewest: Bool
    /// False when the whole piece is shorter than `RadarTrailGeometry.minimumVisiblePoints` on the screen: the marker would cover it.
    public var isVisible: Bool

    public init(points: [RadarTrailPoint], isNewest: Bool, isVisible: Bool) {
        self.points = points
        self.isNewest = isNewest
        self.isVisible = isVisible
    }

    public var coordinates: [GeoPoint] { points.map(\.coordinate) }

    /// The older and the newer half by time. They share their middle point (interpolated at the middle moment), so the line has no gap.
    public var halves: (older: [RadarTrailPoint], newer: [RadarTrailPoint]) {
        guard points.count >= 2, let first = points.first, let last = points.last, last.at > first.at else { return ([], points) }
        let middle = first.at.addingTimeInterval(last.at.timeIntervalSince(first.at) / 2)
        if let exact = points.firstIndex(where: { $0.at == middle }) {
            return (Array(points[...exact]), Array(points[exact...]))
        }
        guard let after = points.firstIndex(where: { $0.at > middle }), after > 0 else { return ([], points) }
        let a = points[after - 1], b = points[after]
        let f = middle.timeIntervalSince(a.at) / b.at.timeIntervalSince(a.at)
        let point = RadarTrailPoint(coordinate: GeoPoint(latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * f,
                                                         longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * f),
                                    at: middle)
        return (Array(points[..<after]) + [point], [point] + Array(points[after...]))
    }
}

public enum RadarTrailGeometry {
    /// Answers further apart than this break the line.
    public static let gapSeconds: TimeInterval = 150
    /// Points closer to the line than this many screen points are dropped (Douglas–Peucker) …
    public static let tolerancePoints = 2.0
    /// … but never closer than this in metres.
    public static let minimumToleranceMeters = 10.0
    /// At most this many points per piece, the drawn point included.
    public static let maxPoints = 30
    /// A piece shorter than this on the screen is not drawn.
    public static let minimumVisiblePoints = 6.0
    static let metersPerDegree = 111_195.0

    /// Metres one screen point stands for at this zoom.
    public static func metersPerPoint(spanDegrees: Double, heightPoints: Double) -> Double {
        let height = heightPoints > 1 ? heightPoints : 800
        return max(spanDegrees, 0.000_1) * metersPerDegree / height
    }

    /// The whole trail of one vehicle: `simplifiedRuns` then `finish`.
    public static func lines(for samples: [RadarTrailSample], until: Date, drawnPoint: GeoPoint?, spanDegrees: Double,
                             heightPoints: Double) -> [RadarTrailLine] {
        let scale = metersPerPoint(spanDegrees: spanDegrees, heightPoints: heightPoints)
        return finish(simplifiedRuns(for: samples, until: until, metersPerPoint: scale), until: until, drawnPoint: drawnPoint,
                      metersPerPoint: scale)
    }

    /// The samples up to `until` as unbroken runs (split at gaps over `gapSeconds`), each thinned to at most `maxPoints - 1` points. This
    /// part changes only with a new answer or another zoom, so the app caches it; `finish` adds the drawn point on every redraw.
    public static func simplifiedRuns(for samples: [RadarTrailSample], until: Date, metersPerPoint: Double) -> [[RadarTrailPoint]] {
        var runs: [[RadarTrailPoint]] = []
        var current: [RadarTrailPoint] = []
        var lastEnd: Date?
        for sample in samples where sample.from <= until {
            if let lastEnd, sample.from.timeIntervalSince(lastEnd) > gapSeconds, !current.isEmpty {
                runs.append(current)
                current = []
            }
            current.append(RadarTrailPoint(coordinate: sample.coordinate, at: sample.from))
            let end = min(sample.to, until)
            if end > sample.from { current.append(RadarTrailPoint(coordinate: sample.coordinate, at: end)) }
            lastEnd = end
        }
        if !current.isEmpty { runs.append(current) }
        let tolerance = max(tolerancePoints * metersPerPoint, minimumToleranceMeters)
        return runs.map { limited(simplify($0, toleranceMeters: tolerance), to: maxPoints - 1, toleranceMeters: tolerance) }
    }

    /// Adds the drawn point to the newest run (when that run reaches within `gapSeconds` of it; else the drawn point stands alone), marks
    /// the newest piece and which pieces are long enough to see.
    public static func finish(_ runs: [[RadarTrailPoint]], until: Date, drawnPoint: GeoPoint?, metersPerPoint: Double) -> [RadarTrailLine] {
        var runs = runs
        if let drawnPoint {
            let point = RadarTrailPoint(coordinate: drawnPoint, at: until)
            if let last = runs.last?.last, until.timeIntervalSince(last.at) <= gapSeconds, until >= last.at {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs.enumerated().map { index, points in
            let length = Self.length(points)
            return RadarTrailLine(points: points, isNewest: index == runs.count - 1,
                                  isVisible: points.count >= 2 && length / max(metersPerPoint, 0.000_1) >= minimumVisiblePoints)
        }
    }

    /// The length of a polyline in metres.
    public static func length(_ points: [RadarTrailPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0.coordinate, $1.1.coordinate) }
    }

    /// Douglas–Peucker in a local plane (longitude scaled by the cosine of the latitude). Keeps both ends.
    public static func simplify(_ points: [RadarTrailPoint], toleranceMeters: Double) -> [RadarTrailPoint] {
        guard points.count > 2 else { return points }
        let lat0 = points[0].coordinate.latitude * .pi / 180
        let scaleX = cos(lat0) * metersPerDegree
        let xy = points.map { ($0.coordinate.longitude * scaleX, $0.coordinate.latitude * metersPerDegree) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var worst = 0.0, index = start
            for i in (start + 1)..<end {
                let d = segmentDistance(xy[i], xy[start], xy[end])
                if d > worst { worst = d; index = i }
            }
            if worst > toleranceMeters {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Thins further (doubling the tolerance) until at most `limit` points are left; both ends stay.
    static func limited(_ points: [RadarTrailPoint], to limit: Int, toleranceMeters: Double) -> [RadarTrailPoint] {
        var result = points
        var tolerance = toleranceMeters
        var rounds = 0
        while result.count > limit && rounds < 12 {
            tolerance *= 2
            result = simplify(result, toleranceMeters: tolerance)
            rounds += 1
        }
        guard result.count > limit, limit >= 2 else { return result }
        // Still too many (a long zig-zag): every n-th point, the ends kept.
        let step = Double(result.count - 1) / Double(limit - 1)
        return (0..<limit).map { result[min(Int((Double($0) * step).rounded()), result.count - 1)] }
    }

    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat = (a.latitude + b.latitude) / 2 * .pi / 180
        let dx = (b.longitude - a.longitude) * cos(lat) * metersPerDegree
        let dy = (b.latitude - a.latitude) * metersPerDegree
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func segmentDistance(_ p: (Double, Double), _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return ((p.0 - a.0) * (p.0 - a.0) + (p.1 - a.1) * (p.1 - a.1)).squareRoot() }
        let t = min(max(((p.0 - a.0) * dx + (p.1 - a.1) * dy) / lengthSquared, 0), 1)
        let x = a.0 + t * dx - p.0, y = a.1 + t * dy - p.1
        return (x * x + y * y).squareRoot()
    }
}
