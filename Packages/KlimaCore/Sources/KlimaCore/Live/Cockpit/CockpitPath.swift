import Foundation

// Cockpit-Ansicht, part 1: angles and a route as a polyline with distances along it (docs/RADAR_COCKPIT.md). Pure: no UI, no clock.
// The camera planner, the route and the speed estimate all work in "kilometres along the route": a train that is 12.4 km along a
// 90 km route is at 12.4, whatever the curves do to the coordinates.

// MARK: - Angles

public enum CockpitAngle {
    /// 0 ..< 360.
    public static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The shortest signed turn from `from` to `to`, in -180 ... 180: from 350 to 10 is +20, from 10 to 350 is -20.
    public static func delta(from: Double, to: Double) -> Double {
        let turn = normalized(to - from)
        return turn > 180 ? turn - 360 : turn
    }

    /// `fraction` (0 ... 1) of the way from `from` to `to` on the short side.
    public static func blend(_ from: Double, toward to: Double, fraction: Double) -> Double {
        normalized(from + delta(from: from, to: to) * min(max(fraction, 0), 1))
    }
}

// MARK: - Geometry helpers

public enum CockpitGeo {
    static let earthRadiusKm = 6371.0088

    /// The point `km` away from `origin` along the initial `bearing` (degrees clockwise from north), on the sphere.
    public static func destination(from origin: GeoPoint, bearing: Double, km: Double) -> GeoPoint {
        let angular = km / earthRadiusKm
        let theta = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(min(max(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta), -1), 1))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        var longitude = lon2 * 180 / .pi
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeoPoint(latitude: lat2 * 180 / .pi, longitude: longitude)
    }

    /// Kilometres east and north of `origin` (flat approximation: right for a few hundred kilometres at Austria's latitude).
    static func planar(_ point: GeoPoint, origin: GeoPoint) -> (x: Double, y: Double) {
        ((point.longitude - origin.longitude) * cos(origin.latitude * .pi / 180) * 111.32, (point.latitude - origin.latitude) * 110.574)
    }

    static func lerp(_ a: GeoPoint, _ b: GeoPoint, _ t: Double) -> GeoPoint {
        GeoPoint(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    static func isUsable(_ point: GeoPoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite && abs(point.latitude) <= 90 && abs(point.longitude) <= 180
    }
}

// MARK: - Path

/// A polyline with the kilometres along it. Built from the polyline of `JourneyDetails`, or from the stops in a row when the
/// answer has none (`CockpitRoute.isStraightLine`).
public struct CockpitPath: Sendable {
    public let points: [GeoPoint]
    private let cumulative: [Double]

    /// Unusable points (not finite, out of range) and a point that repeats the one before it are dropped; fewer than two left: nil.
    public init?(_ points: [GeoPoint]) {
        var usable: [GeoPoint] = []
        usable.reserveCapacity(points.count)
        for point in points where CockpitGeo.isUsable(point) {
            if let last = usable.last, last == point { continue }
            usable.append(point)
        }
        guard usable.count >= 2 else { return nil }
        var sums = [0.0]
        sums.reserveCapacity(usable.count)
        for index in 1..<usable.count {
            sums.append(sums[index - 1] + usable[index - 1].distanceKm(to: usable[index]))
        }
        self.points = usable
        cumulative = sums
    }

    public var lengthKm: Double { cumulative.last ?? 0 }

    /// The index of the segment that contains `km` (the one that starts at or before it).
    private func segment(containing km: Double) -> Int {
        var low = 0, high = cumulative.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= km { low = mid } else { high = mid }
        }
        return low
    }

    /// The point `km` along the path (clamped to its ends).
    public func point(atKm km: Double) -> GeoPoint {
        guard let last = cumulative.last, last > 0 else { return points[0] }
        let target = min(max(km.isFinite ? km : 0, 0), last)
        let low = segment(containing: target)
        let span = cumulative[low + 1] - cumulative[low]
        return CockpitGeo.lerp(points[low], points[low + 1], span > 0 ? (target - cumulative[low]) / span : 0)
    }

    /// The direction of the path at `km`, looking `lookKm` ahead (clockwise from north): from the point at `km` to the point
    /// `lookKm` further on, so a curve a few hundred metres ahead already turns the heading. At the end of the path it looks back.
    public func bearing(atKm km: Double, lookKm: Double = 0.4) -> Double {
        let length = lengthKm
        guard length > 0 else { return 0 }
        let look = min(max(lookKm, 0.02), length)
        let from = min(max(km, 0), length - look)
        return RadarBearing.degrees(from: point(atKm: from), to: point(atKm: from + look))
    }

    /// The nearest point of the path inside the window `fromKm ... toKm`: its distance along the path and how far off it is.
    /// The window keeps a loop or a parallel track from catching the projection: the train never goes back along its run.
    public func project(_ point: GeoPoint, fromKm: Double = 0, toKm: Double = .infinity) -> (km: Double, offKm: Double)? {
        guard CockpitGeo.isUsable(point), let length = cumulative.last, length > 0 else { return nil }
        let low = max(fromKm.isFinite ? fromKm : 0, 0)
        let high = min(toKm, length)
        guard low <= high else { return nil }
        var best: (km: Double, offKm: Double)?
        var index = segment(containing: low)
        while index < points.count - 1, cumulative[index] <= high {
            let a = points[index], b = points[index + 1]
            let span = cumulative[index + 1] - cumulative[index]
            let (bx, by) = CockpitGeo.planar(b, origin: a)
            let (qx, qy) = CockpitGeo.planar(point, origin: a)
            let squared = bx * bx + by * by
            var t = squared > 0 ? (qx * bx + qy * by) / squared : 0
            let tMin = span > 0 ? max((low - cumulative[index]) / span, 0) : 0
            let tMax = span > 0 ? min((high - cumulative[index]) / span, 1) : 1
            t = min(max(t, tMin), max(tMax, tMin))
            let dx = qx - t * bx, dy = qy - t * by
            let off = (dx * dx + dy * dy).squareRoot()
            if best == nil || off < best!.offKm { best = (cumulative[index] + t * span, off) }
            index += 1
        }
        return best
    }

    /// The points between `fromKm` and `toKm`, both ends included (cut on the segments they fall in). Empty when the range is empty.
    public func slice(fromKm: Double, toKm: Double) -> [GeoPoint] {
        guard let length = cumulative.last, length > 0 else { return [] }
        let low = min(max(fromKm.isFinite ? fromKm : 0, 0), length)
        let high = min(max(toKm.isFinite ? toKm : length, 0), length)
        guard low < high else { return [] }
        var out = [point(atKm: low)]
        var index = segment(containing: low) + 1
        while index < points.count - 1, cumulative[index] < high {
            if cumulative[index] > low { out.append(points[index]) }
            index += 1
        }
        out.append(point(atKm: high))
        return out
    }
}
