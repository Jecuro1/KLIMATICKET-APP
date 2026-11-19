import Foundation

// MARK: radartrail – „Spuren“ (docs/RADAR_TRAILS.md): the radar's short memory. While the radar is open it keeps, in memory only, the positions
// the Auskunft sent for each vehicle, one sample per answer at the request time (the time the positions belong to). Nothing here is ever
// written anywhere: the recorder lives inside the radar's model and goes with it. Pure: every call gets its time. No request of any kind.

/// One position of a vehicle as the Auskunft calculated it for a moment. `from` and `to` are equal unless the vehicle stood: answers within
/// `RadarTrailRecorder.compactionMeters` of the previous one with the same delay only stretch `to`, so a standing vehicle costs one sample.
public struct RadarTrailSample: Sendable, Hashable {
    public var from: Date
    public var to: Date
    public var coordinate: GeoPoint
    /// The delay the vehicle carried at that moment (`RadarDelay.currentDelay`); nil: the answer had no realtime.
    public var delaySeconds: Int?
    public var isCancelled: Bool

    public init(from: Date, to: Date? = nil, coordinate: GeoPoint, delaySeconds: Int? = nil, isCancelled: Bool = false) {
        self.from = from
        self.to = max(to ?? from, from)
        self.coordinate = coordinate
        self.delaySeconds = delaySeconds
        self.isCancelled = isCancelled
    }
}

/// The samples of every vehicle the radar was told about while it is open, within a window, under hard caps. A value type: the app's
/// `RadarTrailModel` owns exactly one, and dropping the model drops everything.
public struct RadarTrailRecorder: Sendable {
    /// The longest window (20 minutes plus the margin) at the 20-s cadence is 66 samples: 70 keeps it whole.
    public static let maxSamplesPerTrip = 70
    public static let maxTrips = 4_000
    public static let maxSamples = 50_000
    /// An answer this close to the previous one (same delay, same cancellation) only stretches the previous sample.
    public static let compactionMeters: Double = 20
    /// Kept beyond the chosen length, so the delay line has its start.
    public static let sparklineMargin: TimeInterval = 120
    /// Upper bound of the memory the recorder may take (the soak test holds it to this, computed from `MemoryLayout`).
    public static let memoryBound = 5 * 1024 * 1024

    /// A sample as stored: 24 bytes instead of 48. Coordinates as `Float` keep well under a metre at Austria's latitudes, a stand of up
    /// to 18 hours fits `UInt16` seconds, `Int32.min` means „no delay known“.
    struct Packed: Sendable, Hashable {
        var from: Double
        var latitude: Float
        var longitude: Float
        var delay: Int32
        var stay: UInt16
        var cancelled: Bool

        static let noDelay = Int32.min

        init(_ sample: RadarTrailSample) {
            from = sample.from.timeIntervalSinceReferenceDate
            latitude = Float(sample.coordinate.latitude)
            longitude = Float(sample.coordinate.longitude)
            delay = sample.delaySeconds.map { Int32(clamping: $0) } ?? Self.noDelay
            stay = UInt16(clamping: Int(max(sample.to.timeIntervalSince(sample.from), 0).rounded()))
            cancelled = sample.isCancelled
        }

        var to: Double { from + Double(stay) }
        var coordinate: GeoPoint { GeoPoint(latitude: Double(latitude), longitude: Double(longitude)) }

        var sample: RadarTrailSample {
            RadarTrailSample(from: Date(timeIntervalSinceReferenceDate: from), to: Date(timeIntervalSinceReferenceDate: to),
                             coordinate: coordinate, delaySeconds: delay == Self.noDelay ? nil : Int(delay), isCancelled: cancelled)
        }

        /// Same delay and cancellation, and within `compactionMeters`.
        func compacts(with other: Packed) -> Bool {
            delay == other.delay && cancelled == other.cancelled
                && coordinate.distanceKm(to: other.coordinate) * 1000 <= RadarTrailRecorder.compactionMeters
        }

        mutating func stretch(to time: Double) {
            guard time > to else { return }
            stay = UInt16(clamping: Int((time - from).rounded()))
        }
    }

    struct Track: Sendable {
        var samples: [Packed] = []
        /// The product class of the vehicle (`Line.productClass`, 0 unknown): a mode switched off drops its trails.
        var productClass: Int
        /// The newest request time of an answer that held this vehicle: the trips seen least recently go first beyond a cap.
        var lastSeen: Double
        /// Changes with every change of the samples (the model caches its simplified lines by it).
        var revision: Int

        /// One answer for this vehicle: the sample, its class and recency, the per-trip cap. Returns how the sample count changed.
        mutating func note(_ sample: Packed, productClass newClass: Int, at time: Double, revision newRevision: Int) -> Int {
            revision = newRevision
            lastSeen = max(lastSeen, time)
            if newClass != 0 { productClass = newClass }
            var delta = insert(sample)
            let excess = samples.count - RadarTrailRecorder.maxSamplesPerTrip
            if excess > 0 {
                samples.removeFirst(excess)
                delta -= excess
            }
            return delta
        }

        /// Drops the first `count` samples (they ended before `cutoff`); a stand that began before keeps only its part from `cutoff` on.
        mutating func drop(first count: Int, startingAt cutoff: Double, revision newRevision: Int) -> Int {
            revision = newRevision
            samples.removeFirst(count)
            if let head = samples.first, head.from < cutoff {
                samples[0].from = cutoff
                samples[0].stay = UInt16(clamping: Int(max(head.to - cutoff, 0).rounded()))
            }
            return count
        }

        /// Inserts in time order and returns how the sample count changed. An answer older than the newest sample lands between (slow
        /// answers arrive out of order) and never replaces a newer one; the same moment twice (two tiles) keeps the first.
        mutating func insert(_ sample: Packed) -> Int {
            var index = samples.count
            while index > 0 && samples[index - 1].from > sample.from { index -= 1 }
            if index > 0 {
                let previous = samples[index - 1]
                if previous.from == sample.from { return 0 }
                if previous.compacts(with: sample) {
                    samples[index - 1].stretch(to: sample.from)
                    return 0
                }
                if previous.to > sample.from {
                    // The vehicle was said to stand there until `previous.to`, and this older answer puts it elsewhere in between: the stand
                    // ends at its first moment, this sample follows, and the stand's last moment comes after it, as the answers said.
                    var tail = previous
                    tail.from = previous.to
                    tail.stay = 0
                    samples[index - 1].stay = 0
                    samples.insert(contentsOf: [sample, tail], at: index)
                    return 2
                }
            }
            if index < samples.count, sample.compacts(with: samples[index]) {
                let end = samples[index].to
                samples[index] = sample
                samples[index].stretch(to: end)
                return 0
            }
            samples.insert(sample, at: index)
            return 1
        }
    }

    private(set) var tracks: [String: Track] = [:]
    /// All samples of all trips.
    public private(set) var sampleCount = 0
    /// The first answer recorded since the radar opened (or since the last `clear()`).
    public private(set) var firstRecordedAt: Date?
    /// The newest request time recorded.
    public private(set) var latestAt: Date?
    /// How far back samples are kept: the chosen length plus `sparklineMargin`.
    public var window: TimeInterval
    private var revisionCounter = 0

    public init(window: TimeInterval = RadarTrailSetting.standard.window) {
        self.window = window
    }

    public var tripCount: Int { tracks.count }
    public var isEmpty: Bool { tracks.isEmpty }

    /// The samples of one trip, oldest first.
    public func samples(for tripID: String) -> [RadarTrailSample] {
        tracks[tripID]?.samples.map(\.sample) ?? []
    }

    /// Changes whenever the trip's samples change; nil for a trip the recorder does not hold.
    public func revision(of tripID: String) -> Int? { tracks[tripID]?.revision }

    /// Records one answer: every vehicle gets a sample at `requestedAt`. Then prunes to the window and enforces the caps.
    public mutating func record(_ vehicles: [RadarVehicle], at requestedAt: Date) {
        guard !vehicles.isEmpty else { return }
        firstRecordedAt = min(firstRecordedAt ?? requestedAt, requestedAt)
        latestAt = max(latestAt ?? requestedAt, requestedAt)
        let time = requestedAt.timeIntervalSinceReferenceDate
        for vehicle in vehicles {
            let sample = Packed(RadarTrailSample(from: requestedAt, coordinate: vehicle.coordinate,
                                                 delaySeconds: RadarDelay.currentDelay(of: vehicle, now: requestedAt),
                                                 isCancelled: vehicle.isCancelled))
            let productClass = vehicle.line?.productClass ?? 0
            if tracks[vehicle.tripID] == nil {
                tracks[vehicle.tripID] = Track(productClass: productClass, lastSeen: time, revision: 0)
            }
            revisionCounter += 1
            // In place through the optional chain: no copy of the samples.
            let delta = tracks[vehicle.tripID]?.note(sample, productClass: productClass, at: time, revision: revisionCounter) ?? 0
            sampleCount += delta
        }
        prune(now: latestAt ?? requestedAt)
        enforceCaps()
    }

    /// Drops every sample that ended before `now - window`; a stand that began before keeps only its part inside the window.
    public mutating func prune(now: Date, window: TimeInterval) {
        let cutoff = now.timeIntervalSinceReferenceDate - window
        var removed = 0
        var emptied: [String] = []
        // Collected first, changed after: changing the dictionary while it is iterated would copy it and every array in it.
        let due = tracks.compactMap { id, track -> (String, Int)? in
            guard let first = track.samples.first, first.from < cutoff else { return nil }
            return (id, track.samples.firstIndex { $0.to >= cutoff } ?? track.samples.count)
        }
        for (id, ended) in due {
            revisionCounter += 1
            removed += tracks[id]?.drop(first: ended, startingAt: cutoff, revision: revisionCounter) ?? 0
            if tracks[id]?.samples.isEmpty ?? true { emptied.append(id) }
        }
        for id in emptied { tracks[id] = nil }
        sampleCount -= removed
    }

    public mutating func prune(now: Date) { prune(now: now, window: window) }

    /// Removes the trips whose product class the predicate matches (a mode was switched off). Class 0 (unknown) is passed as 0.
    public mutating func remove(where shouldRemove: (_ productClass: Int) -> Bool) {
        let due = tracks.compactMap { id, track in shouldRemove(track.productClass) ? id : nil }
        for id in due {
            sampleCount -= tracks[id]?.samples.count ?? 0
            tracks[id] = nil
        }
    }

    /// Removes the trips of these product classes; a vehicle of unknown class (0) stays.
    public mutating func remove(products mask: ProductMask) {
        remove { $0 != 0 && $0 & mask.rawValue != 0 }
    }

    /// Everything goes: the radar's access closed or the setting was switched off.
    public mutating func clear() {
        tracks = [:]
        sampleCount = 0
        firstRecordedAt = nil
        latestAt = nil
    }

    /// Beyond a cap the trips seen least recently go first (ties: by trip id, so the order is stable).
    private mutating func enforceCaps() {
        guard tracks.count > Self.maxTrips || sampleCount > Self.maxSamples else { return }
        let order = tracks.map { (id: $0.key, seen: $0.value.lastSeen) }
            .sorted { $0.seen != $1.seen ? $0.seen < $1.seen : $0.id < $1.id }
        for entry in order {
            guard tracks.count > Self.maxTrips || sampleCount > Self.maxSamples else { break }
            sampleCount -= tracks[entry.id]?.samples.count ?? 0
            tracks[entry.id] = nil
        }
    }

    /// The memory the recorder holds, from `MemoryLayout`: the samples' storage as allocated (capacity, not count), each trip's entry with
    /// its id and array header, and the dictionary's buckets. An estimate from above for the soak test and the docs.
    public var estimatedBytes: Int {
        let sample = MemoryLayout<Packed>.stride
        let entry = MemoryLayout<String>.stride + MemoryLayout<Track>.stride
        let arrayHeader = 32
        var bytes = tracks.capacity * (entry + 1)   // buckets plus their bitmap
        for (id, track) in tracks {
            bytes += track.samples.capacity * sample + arrayHeader
            let length = id.utf8.count
            if length > 15 { bytes += 32 + (length + 15) / 16 * 16 }   // a long id lives on the heap
        }
        return bytes
    }
}
