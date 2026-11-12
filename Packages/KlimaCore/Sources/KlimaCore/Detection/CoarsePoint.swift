import Foundation

// "Fahrten erkennen" (docs/TRIP_DETECTION.md) – the pure input types of the detector. A track is what the phone's location
// service delivered: coarse points (significant-location changes), visits (arrival and departure of a stay) or, while
// "Fahrt aufzeichnen" runs, dense fixes. Nothing here talks to CoreLocation; the app maps CLLocation / CLVisit onto these
// types, and the tests and demo scenes feed scripted ones. None of it ever leaves the device.

/// Plain geometry helpers of the detection (own namespace: no clash with other `GeoPoint` extensions).
public enum DetectionGeo {
    /// Great-circle distance in metres.
    public static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double { a.distanceKm(to: b) * 1000 }

    /// A point `meters` away from `origin` towards `bearingDegrees` (0 = north, 90 = east) – scripted tracks and tests.
    public static func offset(_ origin: GeoPoint, meters: Double, bearingDegrees: Double) -> GeoPoint {
        let r = 6_371_008.8
        let bearing = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180, lon1 = origin.longitude * .pi / 180
        let angular = meters / r
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return GeoPoint(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Straight-line interpolation (fine for the few tens of km of a ride): `t` 0 = a, 1 = b.
    public static func lerp(_ a: GeoPoint, _ b: GeoPoint, _ t: Double) -> GeoPoint {
        GeoPoint(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}

/// One position fix. `source` tells how dense the data around it can be: significant-change points come every few
/// minutes and kilometres, recording fixes every second or two.
public struct CoarsePoint: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// `startMonitoringSignificantLocationChanges` (cell-tower level, hundreds of metres to kilometres of accuracy).
        case significantChange
        /// The coordinate of a visit, kept as a point for the track's shape.
        case visit
        /// A fix of "Fahrt aufzeichnen" (GPS, metres of accuracy).
        case recording
    }

    public var time: Date
    public var latitude: Double
    public var longitude: Double
    /// Horizontal accuracy in metres (the radius of the 68 % circle, like `CLLocation.horizontalAccuracy`).
    public var accuracyMeters: Double
    /// Speed in m/s when the provider knows it; nil otherwise (never negative).
    public var speedMetersPerSecond: Double?
    public var source: Source

    public init(time: Date, latitude: Double, longitude: Double, accuracyMeters: Double = 50, speedMetersPerSecond: Double? = nil,
                source: Source = .significantChange) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters.isFinite ? max(0, accuracyMeters) : 0
        if let speed = speedMetersPerSecond, speed.isFinite, speed >= 0 { self.speedMetersPerSecond = speed } else { self.speedMetersPerSecond = nil }
        self.source = source
    }

    public init(time: Date, at point: GeoPoint, accuracyMeters: Double = 50, speedMetersPerSecond: Double? = nil, source: Source = .significantChange) {
        self.init(time: time, latitude: point.latitude, longitude: point.longitude, accuracyMeters: accuracyMeters,
                  speedMetersPerSecond: speedMetersPerSecond, source: source)
    }

    public var geo: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    /// Finite, on the globe, with a sane timestamp (corrupt values never reach the detector).
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 && time.timeIntervalSince1970 > 0
    }
}

/// A stay as iOS reports it (`CLVisit`): where, from when to when. `arrival` is nil when iOS does not know it
/// (`distantPast`), `departure` is nil while the person is still there (`distantFuture`).
public struct VisitRecord: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracyMeters: Double
    public var arrival: Date?
    public var departure: Date?
    /// When the app was told about it (iOS reports a visit only after the stay has lasted a while).
    public var observedAt: Date

    public init(latitude: Double, longitude: Double, accuracyMeters: Double = 100, arrival: Date?, departure: Date? = nil, observedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters.isFinite ? max(0, accuracyMeters) : 0
        self.arrival = arrival
        self.departure = departure
        self.observedAt = observedAt
    }

    public init(at point: GeoPoint, accuracyMeters: Double = 100, arrival: Date?, departure: Date? = nil, observedAt: Date) {
        self.init(latitude: point.latitude, longitude: point.longitude, accuracyMeters: accuracyMeters, arrival: arrival,
                  departure: departure, observedAt: observedAt)
    }

    public var geo: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
            && (arrival ?? observedAt).timeIntervalSince1970 > 0
    }

    /// The first moment this record says anything about.
    var firstTime: Date { arrival ?? departure ?? observedAt }
    /// The last moment this record says anything about.
    var lastTime: Date { departure ?? observedAt }
}

/// Everything the detector looks at: points and visits of the rolling buffer.
public struct CoarseTrack: Codable, Hashable, Sendable {
    public var points: [CoarsePoint]
    public var visits: [VisitRecord]

    public init(points: [CoarsePoint] = [], visits: [VisitRecord] = []) {
        self.points = points
        self.visits = visits
    }

    public var isEmpty: Bool { points.isEmpty && visits.isEmpty }
}

// MARK: - Providers

/// Where positions come from: CoreLocation on the device (App/Sources/Services/Detection), a scripted track in CI, the demo
/// scenes and the tests. `positions()` is an endless stream until `stop()`; calling it again after `stop()` starts over.
public protocol LocationProviding: AnyObject, Sendable {
    /// Starts delivering fixes. The stream finishes after `stop()` (or, for a scripted track, when it is played out).
    func positions() -> AsyncStream<CoarsePoint>
    func stop()
}

/// Plays a prepared track: instantly (tests, scenes) or paced like the clock (`pace` seconds between fixes).
public final class ScriptedLocationProvider: LocationProviding, @unchecked Sendable {
    private let script: [CoarsePoint]
    private let pace: Double?
    private let lock = NSLock()
    private var stopped = false

    /// `pace` nil: every fix at once; otherwise that many seconds of real time between two fixes.
    public init(script: [CoarsePoint], pace: Double? = nil) {
        self.script = script.sorted { $0.time < $1.time }
        self.pace = pace
    }

    public func positions() -> AsyncStream<CoarsePoint> {
        lock.lock()
        stopped = false
        lock.unlock()
        let script = self.script, pace = self.pace
        return AsyncStream { continuation in
            let task = Task {
                for point in script {
                    if Task.isCancelled || self.isStopped { break }
                    continuation.yield(point)
                    if let pace, pace > 0 { try? await Task.sleep(nanoseconds: UInt64(pace * 1_000_000_000)) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}
