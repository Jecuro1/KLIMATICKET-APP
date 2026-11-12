import Foundation

/// The only place raw positions of the background detection live: a rolling buffer of at most 36 hours on the device
/// (docs/TRIP_DETECTION.md §6). Older points are dropped on every write; a confirmed or dismissed candidate takes the
/// points it was made of with it; switching the feature off or "Alle Standortdaten löschen" empties it. The app keeps it
/// in one file in Application Support that is excluded from backups and from export and sync.
public struct RollingPointBuffer: Codable, Hashable, Sendable {
    /// How long a point may stay.
    public static let maxAge: TimeInterval = 36 * 3600
    /// Hard caps (a stuck location service must not fill the disk).
    public static let maxPoints = 3000
    public static let maxVisits = 300

    public private(set) var points: [CoarsePoint]
    public private(set) var visits: [VisitRecord]

    public init(points: [CoarsePoint] = [], visits: [VisitRecord] = []) {
        self.points = points
        self.visits = visits
    }

    public var isEmpty: Bool { points.isEmpty && visits.isEmpty }
    public var track: CoarseTrack { CoarseTrack(points: points, visits: visits) }

    // MARK: Writing

    /// Adds a fix (time order kept, exact duplicates ignored) and drops what is older than 36 hours.
    public mutating func append(_ point: CoarsePoint, now: Date) {
        guard point.isValid, point.time <= now.addingTimeInterval(300) else { return }
        if !points.contains(where: { $0.time == point.time && $0.latitude == point.latitude && $0.longitude == point.longitude }) {
            if let last = points.last, last.time > point.time {
                let index = points.firstIndex { $0.time > point.time } ?? points.count
                points.insert(point, at: index)
            } else {
                points.append(point)
            }
        }
        prune(now: now)
    }

    /// Adds a visit, or completes the open one it belongs to (iOS reports a visit twice: arrival, then departure).
    public mutating func upsert(_ visit: VisitRecord, now: Date) {
        guard visit.isValid else { return }
        if let index = visits.firstIndex(where: { isSameVisit($0, visit) }) {
            var merged = visits[index]
            merged.arrival = merged.arrival ?? visit.arrival
            merged.departure = visit.departure ?? merged.departure
            merged.observedAt = max(merged.observedAt, visit.observedAt)
            merged.accuracyMeters = min(merged.accuracyMeters, visit.accuracyMeters)
            visits[index] = merged
        } else {
            visits.append(visit)
            visits.sort { $0.firstTime < $1.firstTime }
        }
        prune(now: now)
    }

    /// Closes the open visit at `latitude/longitude` (a region exit) – the latest visit without a departure within 400 m.
    public mutating func closeOpenVisit(near point: GeoPoint, departure: Date, now: Date) {
        guard let index = visits.lastIndex(where: { $0.departure == nil && DetectionGeo.meters($0.geo, point) <= 400 }) else { return }
        visits[index].departure = departure
        visits[index].observedAt = max(visits[index].observedAt, departure)
        prune(now: now)
    }

    private func isSameVisit(_ a: VisitRecord, _ b: VisitRecord) -> Bool {
        guard DetectionGeo.meters(a.geo, b.geo) <= 300 else { return false }
        if let x = a.arrival, let y = b.arrival { return abs(x.timeIntervalSince(y)) < 60 }
        // The departure record of a visit whose arrival the app never saw: it completes the open one.
        return a.departure == nil || b.departure == nil
    }

    // MARK: Deleting

    /// Drops everything older than `maxAge` and what exceeds the caps (the oldest go first).
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        points.removeAll { $0.time < cutoff }
        visits.removeAll { $0.lastTime < cutoff }
        if points.count > Self.maxPoints { points.removeFirst(points.count - Self.maxPoints) }
        if visits.count > Self.maxVisits { visits.removeFirst(visits.count - Self.maxVisits) }
    }

    /// Removes the points and the finished visits of a time window (a candidate's evidence, after it was confirmed or
    /// dismissed). A visit that is still open stays: the person may be at the destination yet and the next ride starts there.
    public mutating func remove(from start: Date, to end: Date) {
        points.removeAll { $0.time >= start && $0.time <= end }
        visits.removeAll { $0.departure != nil && $0.firstTime >= start && $0.lastTime <= end }
    }

    /// "Alle Standortdaten löschen", feature switched off.
    public mutating func removeAll() {
        points = []
        visits = []
    }

    // MARK: Tolerant decoding

    private enum CodingKeys: String, CodingKey { case points, visits }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = (try? c.decodeIfPresent([CoarsePoint].self, forKey: .points)) ?? []
        visits = (try? c.decodeIfPresent([VisitRecord].self, forKey: .visits)) ?? []
    }
}
