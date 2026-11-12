import Foundation

/// Synthetic tracks for the tests, the CI scenes and the demo mode – deterministic (no randomness), invented geometry.
/// Real traces never enter the repository.
public enum ScriptedTrack {
    /// Dense fixes along `waypoints` at `cruiseKmh`, one every `interval` seconds, with a stand of `halts[index]` seconds at
    /// waypoint `index` (a train stop). Speed is reported like GPS does. `jitterMeters` shakes the fixes deterministically.
    public static func ride(waypoints: [GeoPoint], start: Date, cruiseKmh: Double, interval: TimeInterval = 5, halts: [Int: TimeInterval] = [:],
                            accuracy: Double = 8, jitterMeters: Double = 3, source: CoarsePoint.Source = .recording) -> [CoarsePoint] {
        guard waypoints.count >= 2, cruiseKmh > 0, interval > 0 else { return [] }
        var out: [CoarsePoint] = []
        var time = start
        var counter = 0
        let speed = cruiseKmh / 3.6

        func emit(_ point: GeoPoint, speed: Double) {
            counter += 1
            let angle = Double(counter) * 2.399
            let shaken = DetectionGeo.offset(point, meters: jitterMeters * abs(sin(Double(counter) * 1.7)), bearingDegrees: angle * 180 / .pi)
            out.append(CoarsePoint(time: time, at: shaken, accuracyMeters: accuracy, speedMetersPerSecond: speed, source: source))
            time = time.addingTimeInterval(interval)
        }

        emit(waypoints[0], speed: 0)
        for index in 1..<waypoints.count {
            let a = waypoints[index - 1], b = waypoints[index]
            let length = DetectionGeo.meters(a, b)
            let steps = max(1, Int((length / (speed * interval)).rounded()))
            for step in 1...steps where step < steps || halts[index] == nil { emit(DetectionGeo.lerp(a, b, Double(step) / Double(steps)), speed: speed) }
            if let stand = halts[index] {
                // Braking, standing, accelerating: fixes at the stop with speed 0.
                var elapsed = 0.0
                while elapsed < stand {
                    emit(b, speed: 0)
                    elapsed += interval
                }
            }
        }
        return out
    }

    /// Fixes of a stay: one every `interval` seconds near `place`, shaking a few metres (or tens of metres for a poor fix).
    public static func stay(at place: GeoPoint, from: Date, to: Date, interval: TimeInterval = 60, accuracy: Double = 30,
                            jitterMeters: Double = 15, source: CoarsePoint.Source = .significantChange) -> [CoarsePoint] {
        guard to > from, interval > 0 else { return [] }
        var out: [CoarsePoint] = []
        var time = from
        var counter = 0
        while time <= to {
            counter += 1
            let moved = DetectionGeo.offset(place, meters: jitterMeters * abs(sin(Double(counter) * 0.9)), bearingDegrees: Double(counter * 47 % 360))
            out.append(CoarsePoint(time: time, at: moved, accuracyMeters: accuracy, speedMetersPerSecond: 0, source: source))
            time = time.addingTimeInterval(interval)
        }
        return out
    }

    /// Coarse fixes along a straight line, `count` of them spread evenly over `from…to` (what significant-change
    /// monitoring delivers on a ride: a handful of cell-tower fixes).
    public static func coarseLine(from a: GeoPoint, to b: GeoPoint, start: Date, end: Date, count: Int, accuracy: Double = 800) -> [CoarsePoint] {
        guard count > 0, end > start else { return [] }
        return (1...count).map { i in
            let t = Double(i) / Double(count + 1)
            return CoarsePoint(time: start.addingTimeInterval(end.timeIntervalSince(start) * t), at: DetectionGeo.lerp(a, b, t),
                               accuracyMeters: accuracy, source: .significantChange)
        }
    }
}
