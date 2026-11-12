import Foundation

/// The shape of a ride as a few points in a unit square – for the mini route on the inbox card. It carries NO real
/// coordinates: the points are relative to the ride's own bounding box (aspect ratio kept, centred, north up), rounded to
/// two decimals, so the sketch can be kept with a candidate without keeping where anybody was.
public struct RouteSketch: Codable, Hashable, Sendable {
    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// 2 … `maxPoints` points from the start to the destination, `0…1` each.
    public var points: [Point]
    /// Only the two stations (no track in between): drawn as a dashed straight line, because that is all the data says.
    public var isStraight: Bool

    public static let maxPoints = 16

    public init(points: [Point], isStraight: Bool) {
        self.points = points
        self.isStraight = isStraight
    }

    /// Sketch of a ride: the stations at both ends and the track between them (may be empty).
    public static func make(from: GeoPoint, to: GeoPoint, track: [GeoPoint], maxPoints: Int = RouteSketch.maxPoints) -> RouteSketch {
        var geo = [from] + track + [to]
        let isStraight = track.count < 2
        if geo.count > maxPoints {
            // Evenly along the list (the track is already in time order); first and last stay.
            let step = Double(geo.count - 1) / Double(maxPoints - 1)
            geo = (0..<maxPoints).map { geo[min(Int((Double($0) * step).rounded()), geo.count - 1)] }
        }
        let lat0 = geo.map(\.latitude).reduce(0, +) / Double(geo.count)
        let k = cos(lat0 * .pi / 180)
        let xs = geo.map { $0.longitude * k }, ys = geo.map(\.latitude)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        let side = max(maxX - minX, maxY - minY, 1e-9)
        let offsetX = (1 - (maxX - minX) / side) / 2, offsetY = (1 - (maxY - minY) / side) / 2
        let points = geo.indices.map { i in
            Point(x: round2(offsetX + (xs[i] - minX) / side), y: round2(1 - (offsetY + (ys[i] - minY) / side)))
        }
        return RouteSketch(points: points, isStraight: isStraight)
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // MARK: Compact text form (SwiftData: one String)

    /// "S|0.10,0.80;0.52,0.44;0.90,0.12" – `S` straight, `T` with a track.
    public var encoded: String {
        (isStraight ? "S|" : "T|") + points.map { "\(Self.text($0.x)),\(Self.text($0.y))" }.joined(separator: ";")
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "S" || parts[0] == "T" else { return nil }
        let points = parts[1].split(separator: ";").compactMap { pair -> Point? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2, xy.allSatisfy({ $0.isFinite }) else { return nil }
            return Point(x: min(max(xy[0], 0), 1), y: min(max(xy[1], 0), 1))
        }
        guard points.count >= 2 else { return nil }
        self.init(points: points, isStraight: parts[0] == "S")
    }

    private static func text(_ v: Double) -> String {
        let hundredths = Int((v * 100).rounded())
        return "\(hundredths / 100).\(String(format: "%02d", abs(hundredths % 100)))"
    }
}
