import Foundation

// "Fahrt aufzeichnen" (Mode A): the person starts a recording, the phone delivers dense GPS fixes, this value type turns them
// into the live screen's numbers (elapsed time, distance, speed, current and last station) and, when it is stopped, into a
// proposed ride. Pure: no CoreLocation, no clock – every call gets the time it needs.

public struct RecordingConfig: Hashable, Sendable {
    /// Fixes less accurate than this are not used (GPS in a tunnel or a building).
    public var maxAccuracyMeters = 100.0
    /// A step shorter than this is GPS jitter of a standing phone (it does not add distance).
    public var jitterMeters = 6.0
    /// Faster than this between two fixes is a GPS jump (360 km/h).
    public var maxPlausibleSpeed = 100.0
    /// A station counts as "here" within this distance.
    public var stationRadiusMeters = 400.0
    /// Below this speed the train stands.
    public var haltSpeed = 2.0
    /// … for at least this long at a station = a halt.
    public var haltSeconds: TimeInterval = 15
    /// Start and end are matched to stations within this distance (the person may have started on the forecourt).
    public var endpointRadiusMeters = 800.0
    /// Shorter than this is no ride (an accidental start).
    public var minRideMeters = 500.0
    public var minRideSeconds: TimeInterval = 60
    /// The live map line keeps at most this many points.
    public var maxTrackPoints = 1200

    public init() {}
}

public struct RecordingSnapshot: Hashable, Sendable {
    public var startedAt: Date
    public var elapsed: TimeInterval
    public var distanceKm: Double
    /// Smoothed estimate, 0 when standing.
    public var speedKmh: Double
    public var maxSpeedKmh: Double
    /// The station the phone is at right now (within 400 m).
    public var currentStation: StationMatch?
    /// The last station the phone was at (the one just left while riding).
    public var lastStation: Station?
    public var fixCount: Int
    /// Seconds since the last usable fix (nil before the first one): large = GPS lost.
    public var secondsSinceFix: TimeInterval?
    /// The live map line, thinned.
    public var track: [GeoPoint]
}

/// A recording turned into a ride, waiting for the person's decision.
public struct RecordingProposal: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var from: StationMatch?
    public var to: StationMatch?
    /// Stops at other rail stations on the way.
    public var halts: [Station]
    public var distanceKm: Double
    public var straightKm: Double
    public var averageSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var mode: TransportMode
    public var sketch: RouteSketch

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Both ends are known stations, so the value can be computed right away.
    public var isComplete: Bool { from != nil && to != nil }
}

public struct RecordingSession: Sendable {
    public let startedAt: Date
    public private(set) var config: RecordingConfig
    private let matcher: StationMatcher
    private let nearMatcher: StationMatcher

    private var fixes: [CoarsePoint] = []
    private var distanceMeters = 0.0
    private var speed = 0.0
    private var maxSpeed = 0.0
    private var lastAccepted: CoarsePoint?
    private var track: [GeoPoint] = []
    private var current: StationMatch?
    private var last: Station?
    private var lookupAt: GeoPoint?
    private var lowSpeedSince: Date?
    private var haltCandidate: Station?
    private var halts: [(station: Station, at: Date)] = []
    private var latestFixTime: Date?

    public init(startedAt: Date, lookup: any StationLookup, config: RecordingConfig = RecordingConfig()) {
        self.startedAt = startedAt
        self.config = config
        self.matcher = StationMatcher(lookup: lookup, maxDistanceMeters: config.endpointRadiusMeters)
        self.nearMatcher = StationMatcher(lookup: lookup, maxDistanceMeters: config.stationRadiusMeters)
    }

    // MARK: Fixes

    /// Takes a fix. Unusable ones (inaccurate, from before the start, jumps) are dropped.
    public mutating func ingest(_ point: CoarsePoint) {
        guard point.isValid, point.time >= startedAt.addingTimeInterval(-5), point.accuracyMeters <= config.maxAccuracyMeters else { return }
        guard let previous = lastAccepted else {
            accept(point, step: 0, dt: 0)
            return
        }
        let dt = point.time.timeIntervalSince(previous.time)
        guard dt > 0 else { return }
        let step = DetectionGeo.meters(previous.geo, point.geo)
        guard step / dt <= config.maxPlausibleSpeed else { return }   // a jump
        accept(point, step: step, dt: dt)
    }

    private mutating func accept(_ point: CoarsePoint, step: Double, dt: Double) {
        let slack = max(config.jitterMeters, min(point.accuracyMeters, 30) * 0.5)
        let moved = step >= slack
        if moved { distanceMeters += step }
        // Speed: the provider's when it has one, else the step over the time. Smoothed so the number does not flicker.
        let raw = point.speedMetersPerSecond ?? (dt > 0 ? (moved ? step / dt : 0) : 0)
        speed = fixes.isEmpty ? raw : speed * 0.65 + raw * 0.35
        if speed < 0.4 { speed = 0 }
        maxSpeed = max(maxSpeed, speed)
        lastAccepted = point
        latestFixTime = point.time
        fixes.append(point)
        if moved || track.isEmpty { appendTrack(point.geo) }
        refreshStation(at: point)
        trackHalts(point)
    }

    private mutating func appendTrack(_ geo: GeoPoint) {
        if let lastPoint = track.last, DetectionGeo.meters(lastPoint, geo) < 15 { return }
        track.append(geo)
        if track.count > config.maxTrackPoints {
            // Thin out: every second point (first and last stay).
            let kept = track.enumerated().filter { $0.offset % 2 == 0 || $0.offset == track.count - 1 }.map(\.element)
            track = kept
        }
    }

    /// Station lookups at most every 40 m (a main station has dozens of stops; a lookup per second would be wasted work).
    private mutating func refreshStation(at point: CoarsePoint) {
        if let lookupAt, DetectionGeo.meters(lookupAt, point.geo) < 40, current != nil || fixes.count > 1 { return }
        lookupAt = point.geo
        current = nearMatcher.best(near: point.geo)
        if let current { last = current.station }
    }

    private mutating func trackHalts(_ point: CoarsePoint) {
        guard speed <= config.haltSpeed, let station = current?.station, StationMatcher.isRailLike(station) else {
            lowSpeedSince = nil
            haltCandidate = nil
            return
        }
        if haltCandidate?.id != station.id {
            haltCandidate = station
            lowSpeedSince = point.time
            return
        }
        if let since = lowSpeedSince, point.time.timeIntervalSince(since) >= config.haltSeconds, !halts.contains(where: { $0.station.id == station.id }) {
            halts.append((station, since))
        }
    }

    // MARK: Read

    public func snapshot(now: Date) -> RecordingSnapshot {
        RecordingSnapshot(startedAt: startedAt, elapsed: max(0, now.timeIntervalSince(startedAt)), distanceKm: distanceMeters / 1000,
                          speedKmh: speed * 3.6, maxSpeedKmh: maxSpeed * 3.6, currentStation: current, lastStation: last,
                          fixCount: fixes.count, secondsSinceFix: latestFixTime.map { max(0, now.timeIntervalSince($0)) }, track: track)
    }

    /// The ride this recording makes, nil when it is too short to be one (an accidental start).
    public func proposal(endedAt end: Date) -> RecordingProposal? {
        guard let first = fixes.first, let lastFix = fixes.last else { return nil }
        let duration = max(end, lastFix.time).timeIntervalSince(startedAt)
        let straight = DetectionGeo.meters(first.geo, lastFix.geo)
        guard distanceMeters >= config.minRideMeters, duration >= config.minRideSeconds, straight >= config.minRideMeters * 0.5 else { return nil }
        let from = matcher.best(near: first.geo)
        let to = matcher.best(near: lastFix.geo)
        let endpoints = Set([from?.station.id, to?.station.id].compactMap { $0 })
        let viaHalts = halts.sorted { $0.at < $1.at }.map(\.station).filter { !endpoints.contains($0.id) }
        let straightKm: Double
        if let from, let to { straightKm = from.station.location.distanceKm(to: to.station.location) } else { straightKm = straight / 1000 }
        let hours = max(duration, 1) / 3600
        let mode: TransportMode
        if let from, let to { mode = TripModeGuess.mode(from: from.station, to: to.station) } else { mode = .train }
        return RecordingProposal(start: startedAt, end: max(end, lastFix.time), from: from, to: to, halts: viaHalts,
                                 distanceKm: distanceMeters / 1000, straightKm: straightKm, averageSpeedKmh: distanceMeters / 1000 / hours,
                                 maxSpeedKmh: maxSpeed * 3.6, mode: mode,
                                 sketch: RouteSketch.make(from: from?.station.location ?? first.geo, to: to?.station.location ?? lastFix.geo, track: track))
    }
}
