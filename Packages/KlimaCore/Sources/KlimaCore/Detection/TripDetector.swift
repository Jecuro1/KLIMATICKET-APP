import Foundation

// The pure detector: a coarse track in, candidate rides and the reasons for everything it did NOT propose out.
// No clock, no I/O, no CoreLocation. docs/TRIP_DETECTION.md §3 explains the rules; the numbers are `DetectorConfig`.

public struct DetectorConfig: Hashable, Sendable {
    /// A ride starts and ends at a station or stop at most this far from the place where the person stayed.
    public var maxStationDistanceMeters = 500.0
    /// Straight line between the two stations: shorter is a walk, a tram or a taxi.
    public var minStraightKm = 5.0
    /// Average speed between leaving the start and arriving at the destination: slower is walking or cycling …
    public var minSpeedKmh = 35.0
    /// … faster is not on the ground.
    public var maxSpeedKmh = 250.0
    /// A stay counts as a dwell from this long (a train stops 1–2 minutes; waiting on the platform takes longer).
    public var minDwell: TimeInterval = 3 * 60
    /// A stay without a known end (the person may still be there) has to last this long before it ends a ride.
    public var openStayMinDwell: TimeInterval = 5 * 60
    /// Rides longer than this are not rides (a night train takes up to 12 hours).
    public var maxTripDuration: TimeInterval = 12 * 3600
    /// Points of a stay lie within this radius (plus half their accuracy, at most another 250 m).
    public var stayRadiusMeters = 250.0
    /// A cluster of points shorter than this is no stay at all.
    public var minStaySpan: TimeInterval = 90
    /// Two fixes of one stay are at most this far apart in time: a phone that stands still sends no cell-tower fixes, so
    /// two fixes at the same place nine hours apart say nothing about where it was in between.
    public var maxClusterGap: TimeInterval = 20 * 60
    /// Points less accurate than this are ignored (a cell tower 5 km away says nothing about a station).
    public var maxPointAccuracyMeters = 1500.0
    /// Walked length of the track ÷ straight line: more than this means going back and forth, not a ride.
    public var maxWindingRatio = 3.0
    /// A change at a hub: two rides with a wait of at most this long become one ride "über Hub".
    public var maxTransferDwell: TimeInterval = 25 * 60
    /// Stays closer than this are the same place.
    public var samePlaceMeters = 400.0

    public init() {}
}

/// A ride the detector would propose.
public struct DetectedCandidate: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var source: DetectionSource
    public var from: StationMatch
    public var to: StationMatch
    /// Hubs where the person changed (0…`TripVia.maxCount`), in travel order.
    public var via: [Station]
    public var departure: Date
    public var arrival: Date
    public var straightKm: Double
    /// Length of the track between the two stays, when it had points (else nil).
    public var pathKm: Double?
    public var averageSpeedKmh: Double
    public var dwellAtStart: TimeInterval?
    public var dwellAtEnd: TimeInterval?
    public var mode: TransportMode
    /// The facts the rank was computed from – kept so the optional timetable lookup can re-rank without starting over.
    public var evidence: CandidateEvidence
    public var rank: CandidateRank
    public var sketch: RouteSketch
    /// The raw points and visits that led to this candidate – deleted when it is confirmed or dismissed.
    public var evidenceStart: Date
    public var evidenceEnd: Date

    public var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    public var confidence: DetectionConfidence { rank.confidence }

    /// The same ride with the timetable's answer taken into account.
    public func ranked(with verdict: TimetableVerdict) -> DetectedCandidate {
        var copy = self
        copy.evidence.timetable = verdict
        copy.rank = CandidateRanking.rank(copy.evidence)
        return copy
    }
}

/// Why a movement between two stays was not proposed – the "Erkennungs-Protokoll" shows these (names and times only).
public struct DetectionRejection: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case tooShort(km: Double)
        case noStationAtStart(nearestKm: Double?)
        case noStationAtEnd(nearestKm: Double?)
        case noStationAtEither
        case sameStation
        case tooSlow(kmh: Double)
        case tooFast(kmh: Double)
        case tooLong(hours: Double)
        case winding(ratio: Double)
        case tooUncertain(score: Double)
    }

    public var reason: Reason
    public var departure: Date
    public var arrival: Date
    public var fromName: String?
    public var toName: String?
    public var straightKm: Double
    public var averageSpeedKmh: Double?

    public init(reason: Reason, departure: Date, arrival: Date, fromName: String? = nil, toName: String? = nil, straightKm: Double,
                averageSpeedKmh: Double? = nil) {
        self.reason = reason
        self.departure = departure
        self.arrival = arrival
        self.fromName = fromName
        self.toName = toName
        self.straightKm = straightKm
        self.averageSpeedKmh = averageSpeedKmh
    }

    /// Short code for tests and the log's filter.
    public var code: String {
        switch reason {
        case .tooShort: "tooShort"
        case .noStationAtStart: "noStationAtStart"
        case .noStationAtEnd: "noStationAtEnd"
        case .noStationAtEither: "noStationAtEither"
        case .sameStation: "sameStation"
        case .tooSlow: "tooSlow"
        case .tooFast: "tooFast"
        case .tooLong: "tooLong"
        case .winding: "winding"
        case .tooUncertain: "tooUncertain"
        }
    }

    /// One German sentence for the log, without coordinates.
    public var text: String {
        switch reason {
        case .tooShort(let km): "Luftlinie nur \(Format1.km(km)) km (ab 5 km)"
        case .noStationAtStart(let km): "Start ohne Haltestelle in 500 m\(Self.nearest(km))"
        case .noStationAtEnd(let km): "Ziel ohne Haltestelle in 500 m\(Self.nearest(km))"
        case .noStationAtEither: "Weder Start noch Ziel nahe einer Haltestelle"
        case .sameStation: "Start und Ziel sind dieselbe Haltestelle"
        case .tooSlow(let kmh): "Mit \(Int(kmh.rounded())) km/h zu langsam für eine Zugfahrt (zu Fuß oder Rad)"
        case .tooFast(let kmh): "Mit \(Int(kmh.rounded())) km/h zu schnell für den Boden"
        case .tooLong(let h): "Dauer \(Format1.km(h)) Stunden – zu lang für eine Fahrt"
        case .winding: "Weg verläuft hin und her, keine Fahrt von A nach B"
        case .tooUncertain: "Zu unsicher (kein Bahnhof direkt am Ziel, Auto möglich)"
        }
    }

    private static func nearest(_ km: Double?) -> String {
        guard let km else { return "" }
        return " (nächste: \(Format1.km(km)) km)"
    }
}

public struct DetectionOutcome: Hashable, Sendable {
    public var candidates: [DetectedCandidate]
    public var rejections: [DetectionRejection]

    public static let empty = DetectionOutcome(candidates: [], rejections: [])
}

public struct TripDetector: Sendable {
    public var config: DetectorConfig
    public var matcher: StationMatcher
    /// Whether the official price table has a relation between two station ids (either direction).
    public var knownRelation: @Sendable (String, String) -> Bool

    public init(matcher: StationMatcher, config: DetectorConfig = DetectorConfig(), knownRelation: @escaping @Sendable (String, String) -> Bool = { _, _ in false }) {
        self.matcher = StationMatcher(lookup: matcher.lookup, maxDistanceMeters: config.maxStationDistanceMeters)
        self.config = config
        self.knownRelation = knownRelation
    }

    // MARK: Entry

    /// Every ride in `track`. `now` closes stays that are still open; `history` down-weights dismissed pairs.
    public func detect(_ track: CoarseTrack, now: Date, history: PairHistory = .empty) -> DetectionOutcome {
        let stays = makeStays(track, now: now)
        let ends = stays.filter { $0.isEndCapable(config) }
        guard ends.count >= 2 else { return .empty }

        var candidates: [DetectedCandidate] = []
        var rejections: [DetectionRejection] = []
        var i = 0
        while i < ends.count - 1 {
            let a = ends[i], b = ends[i + 1]
            // Same place: no movement to judge.
            if DetectionGeo.meters(a.center, b.center) < config.samePlaceMeters { i += 1; continue }

            // A change at a hub: A → H and H → B together, when the hub stay is short and both legs and the whole pass.
            if i + 2 < ends.count, b.dwell <= config.maxTransferDwell, b.departure != nil {
                let c = ends[i + 2]
                if DetectionGeo.meters(b.center, c.center) >= config.samePlaceMeters,
                   case .candidate(let first) = evaluate(a, b, track: track, stays: stays, history: history, now: now),
                   case .candidate(let second) = evaluate(b, c, track: track, stays: stays, history: history, now: now),
                   case .candidate(let merged) = evaluate(a, c, via: [b], track: track, stays: stays, history: history, now: now),
                   first.from.station.id != second.to.station.id {
                    candidates.append(merged)
                    i += 2
                    continue
                }
            }

            switch evaluate(a, b, track: track, stays: stays, history: history, now: now) {
            case .candidate(let candidate): candidates.append(candidate)
            case .rejected(let rejection?): rejections.append(rejection)
            case .rejected(nil): break
            }
            i += 1
        }
        return DetectionOutcome(candidates: candidates.sorted { $0.departure < $1.departure },
                                rejections: rejections.sorted { $0.departure < $1.departure })
    }

    // MARK: Stays

    struct Stay: Hashable {
        var center: GeoPoint
        var arrival: Date
        /// nil: no end known – the person may still be there.
        var departure: Date?
        /// The last moment the track says the person was there.
        var lastSeen: Date
        var accuracy: Double
        var viaVisit: Bool
        /// How long the person was (at least) there. An open stay counts up to the last time it was seen.
        var dwell: TimeInterval { max(0, (departure ?? lastSeen).timeIntervalSince(arrival)) }

        func isEndCapable(_ config: DetectorConfig) -> Bool {
            departure != nil ? dwell >= config.minDwell : dwell >= max(config.minDwell, config.openStayMinDwell)
        }
    }

    func makeStays(_ track: CoarseTrack, now: Date) -> [Stay] {
        var stays: [Stay] = []
        for visit in track.visits where visit.isValid {
            // iOS tells about a visit only after the stay lasted a while; no departure = still there.
            guard let arrival = visit.arrival else {
                // Arrival unknown: the stay's start (and so its dwell) can not be shown – it can still be a start.
                if let departure = visit.departure {
                    stays.append(Stay(center: visit.geo, arrival: departure, departure: departure, lastSeen: departure, accuracy: visit.accuracyMeters, viaVisit: true))
                }
                continue
            }
            let end = visit.departure
            // No departure: iOS says the person is still there – the stay lasts at least until now.
            stays.append(Stay(center: visit.geo, arrival: arrival, departure: end, lastSeen: end ?? max(visit.observedAt, now),
                              accuracy: visit.accuracyMeters, viaVisit: true))
        }
        stays.append(contentsOf: pointStays(track.points))
        return merge(stays.sorted { $0.arrival < $1.arrival })
    }

    /// Clusters of consecutive fixes within the stay radius.
    private func pointStays(_ allPoints: [CoarsePoint]) -> [Stay] {
        let points = allPoints.filter { $0.isValid && $0.accuracyMeters <= config.maxPointAccuracyMeters }.sorted { $0.time < $1.time }
        var stays: [Stay] = []
        var cluster: [CoarsePoint] = []
        var lat = 0.0, lon = 0.0

        func flush() {
            defer { cluster = [] }
            guard cluster.count >= 2, let first = cluster.first, let last = cluster.last,
                  last.time.timeIntervalSince(first.time) >= config.minStaySpan else { return }
            stays.append(Stay(center: GeoPoint(latitude: lat, longitude: lon), arrival: first.time, departure: nil, lastSeen: last.time,
                              accuracy: cluster.map(\.accuracyMeters).max() ?? 0, viaVisit: false))
        }

        for point in points {
            if cluster.isEmpty {
                cluster = [point]; lat = point.latitude; lon = point.longitude
                continue
            }
            let slack = min(point.accuracyMeters * 0.5, 250)
            let continuous = cluster.last.map { point.time.timeIntervalSince($0.time) <= config.maxClusterGap } ?? true
            if continuous, DetectionGeo.meters(GeoPoint(latitude: lat, longitude: lon), point.geo) <= config.stayRadiusMeters + slack {
                lat = (lat * Double(cluster.count) + point.latitude) / Double(cluster.count + 1)
                lon = (lon * Double(cluster.count) + point.longitude) / Double(cluster.count + 1)
                cluster.append(point)
            } else {
                // The next fix is elsewhere: the cluster ended when its last fix was seen (a stay left by moving away).
                flushClosing(&cluster, lat: lat, lon: lon, next: point.time, into: &stays)
                cluster = [point]; lat = point.latitude; lon = point.longitude
            }
        }
        flush()
        return stays
    }

    /// A cluster left because the next fix is far away: the stay has a departure (when the person was last seen there).
    private func flushClosing(_ cluster: inout [CoarsePoint], lat: Double, lon: Double, next: Date, into stays: inout [Stay]) {
        defer { cluster = [] }
        guard cluster.count >= 2, let first = cluster.first, let last = cluster.last,
              last.time.timeIntervalSince(first.time) >= config.minStaySpan else { return }
        stays.append(Stay(center: GeoPoint(latitude: lat, longitude: lon), arrival: first.time, departure: last.time, lastSeen: last.time,
                          accuracy: cluster.map(\.accuracyMeters).max() ?? 0, viaVisit: false))
    }

    /// Overlapping stays at the same place become one (a visit and the points inside it; a visit split in two).
    private func merge(_ sorted: [Stay]) -> [Stay] {
        var out: [Stay] = []
        for stay in sorted {
            if var last = out.last, DetectionGeo.meters(last.center, stay.center) <= config.samePlaceMeters + min(stay.accuracy, 300) * 0.5,
               stay.arrival <= (last.departure ?? last.lastSeen).addingTimeInterval(120) {
                if stay.viaVisit && !last.viaVisit { last.center = stay.center }
                last.arrival = min(last.arrival, stay.arrival)
                last.lastSeen = max(last.lastSeen, stay.lastSeen)
                switch (last.departure, stay.departure) {
                case (nil, _): last.departure = stay.departure
                case (_?, nil): break
                case (let a?, let b?): last.departure = max(a, b)
                }
                last.viaVisit = last.viaVisit || stay.viaVisit
                last.accuracy = max(last.accuracy, stay.accuracy)
                out[out.count - 1] = last
            } else {
                out.append(stay)
            }
        }
        return out
    }

    // MARK: One ride

    enum Evaluation {
        case candidate(DetectedCandidate)
        /// nil: nothing worth writing to the log (a short hop between two places with no station).
        case rejected(DetectionRejection?)
    }

    func evaluate(_ a: Stay, _ b: Stay, via: [Stay] = [], track: CoarseTrack, stays: [Stay], history: PairHistory, now: Date) -> Evaluation {
        let departure = leaveTime(of: a, track: track)
        let arrival = b.arrival
        guard arrival > departure else { return .rejected(nil) }
        let duration = arrival.timeIntervalSince(departure)
        let straightStays = DetectionGeo.meters(a.center, b.center) / 1000

        let from = matcher.best(near: a.center)
        let to = matcher.best(near: b.center)
        let straightKm: Double
        if let from, let to { straightKm = from.station.location.distanceKm(to: to.station.location) } else { straightKm = straightStays }
        let speed = straightKm / (duration / 3600)
        func rejection(_ reason: DetectionRejection.Reason, relevant: Bool = true) -> Evaluation {
            guard relevant else { return .rejected(nil) }
            return .rejected(DetectionRejection(reason: reason, departure: departure, arrival: arrival, fromName: from?.station.name,
                                                toName: to?.station.name, straightKm: straightKm, averageSpeedKmh: speed.isFinite ? speed : nil))
        }
        // The log is for rides that could have been one: a station at an end, or a ride-like distance and speed.
        let looksLikeARide = straightKm >= config.minStraightKm && speed >= config.minSpeedKmh && speed <= config.maxSpeedKmh
        let relevant = (from != nil || to != nil) && straightKm >= 2 || looksLikeARide

        if let from, let to, from.station.id == to.station.id
            || StationIndex.normalize(from.station.name) == StationIndex.normalize(to.station.name) {
            return rejection(.sameStation, relevant: relevant)
        }
        if straightKm < config.minStraightKm { return rejection(.tooShort(km: straightKm), relevant: relevant) }
        guard let from, let to else {
            switch (from, to) {
            case (nil, nil): return rejection(.noStationAtEither, relevant: relevant)
            case (nil, _): return rejection(.noStationAtStart(nearestKm: nearestKm(a.center)), relevant: relevant)
            default: return rejection(.noStationAtEnd(nearestKm: nearestKm(b.center)), relevant: relevant)
            }
        }
        if duration > config.maxTripDuration { return rejection(.tooLong(hours: duration / 3600)) }
        if speed < config.minSpeedKmh { return rejection(.tooSlow(kmh: speed)) }
        if speed > config.maxSpeedKmh { return rejection(.tooFast(kmh: speed)) }

        // The track between the two stays.
        let between = track.points.filter { $0.isValid && $0.accuracyMeters <= config.maxPointAccuracyMeters && $0.time > departure && $0.time < arrival }
            .sorted { $0.time < $1.time }
        var pathKm: Double?
        if between.count >= 2 {
            var length = DetectionGeo.meters(from.station.location, between[0].geo)
            for k in 1..<between.count { length += DetectionGeo.meters(between[k - 1].geo, between[k].geo) }
            length += DetectionGeo.meters(between[between.count - 1].geo, to.station.location)
            pathKm = length / 1000
            if length / 1000 / max(straightKm, 0.1) > config.maxWindingRatio { return rejection(.winding(ratio: length / 1000 / straightKm)) }
        }

        // Halts of the train on the way at rail stations other than the two ends (dense tracks only).
        let halts = stays.filter { s in
            s.arrival > departure && (s.departure ?? s.lastSeen) < arrival && !via.contains(where: { $0.center == s.center })
                && s != a && s != b
        }.compactMap { s -> Station? in
            matcher.best(near: s.center).flatMap { $0.isRailLike && $0.station.id != from.station.id && $0.station.id != to.station.id ? $0.station : nil }
        }
        let viaStations = via.compactMap { matcher.best(near: $0.center)?.station }.filter { $0.id != from.station.id && $0.id != to.station.id }

        let evidence = CandidateEvidence(source: .background, from: from, to: to, straightKm: straightKm, averageSpeedKmh: speed,
                                         dwellAtStart: a.dwell, dwellAtEnd: b.dwell, knownRelation: knownRelation(from.station.id, to.station.id),
                                         intermediateHalts: Set(halts.map(\.id)).count, history: history)
        let rank = CandidateRanking.rank(evidence)
        guard rank.isProposable else { return rejection(.tooUncertain(score: rank.score)) }

        let sketch = RouteSketch.make(from: from.station.location, to: to.station.location, track: between.map(\.geo))
        let candidate = DetectedCandidate(
            id: UUID(), source: .background, from: from, to: to, via: Array(viaStations.prefix(TripVia.maxCount)), departure: departure,
            arrival: arrival, straightKm: straightKm, pathKm: pathKm, averageSpeedKmh: speed, dwellAtStart: a.dwell, dwellAtEnd: b.dwell,
            mode: TripModeGuess.mode(from: from.station, to: to.station), evidence: evidence, rank: rank, sketch: sketch,
            evidenceStart: a.arrival, evidenceEnd: b.departure ?? b.arrival)
        return .candidate(candidate)
    }

    /// When the person left a stay. A stay without a recorded departure (a missed geofence exit, a visit iOS never closed) ended
    /// at the first fix clearly away from it – or counts as not left.
    private func leaveTime(of stay: Stay, track: CoarseTrack) -> Date {
        if let departure = stay.departure { return departure }
        let away = track.points.filter {
            $0.isValid && $0.time > stay.arrival && DetectionGeo.meters($0.geo, stay.center) > config.stayRadiusMeters * 2
        }.map(\.time).min()
        return min(stay.lastSeen, away ?? stay.lastSeen)
    }

    private func nearestKm(_ point: GeoPoint) -> Double? {
        // Looked up wider than the 500 m rule, only for the log's "nächste: 1,8 km".
        let hits = matcher.lookup.stations(near: point, withinMeters: 5000, limit: 1)
        return hits.first.map { $0.distanceMeters / 1000 }
    }
}

/// The mode a ride between two stations most likely has.
public enum TripModeGuess {
    public static func mode(from: Station, to: Station) -> TransportMode {
        let a = from.primaryMode, b = to.primaryMode
        let railA = StationMatcher.isRailLike(from), railB = StationMatcher.isRailLike(to)
        if railA || railB {
            if a == .metro && b == .metro { return .metro }
            if a == .sBahn && b == .sBahn { return .sBahn }
            return .train
        }
        if a == b, a != .other { return a }
        return .bus
    }
}
