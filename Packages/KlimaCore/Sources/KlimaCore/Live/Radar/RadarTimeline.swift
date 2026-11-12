import Foundation

// Radar time travel, part 2: the timeline of snapshots (docs/RADAR_TIMETRAVEL.md). Pure: no network, no clock of its own.
//
// Every answer of the radar is a snapshot: the vehicles and where the server put them at the time asked for. The timeline keeps, per
// trip id, its observations (time, the position then, the four stops of that answer) and merges them into one `RadarRunPath`: the stops of all
// answers with the freshest delays, and each answer's position as a point the train passes through at that time. "Where is every vehicle
// at time T" is then one lookup per trip. A vehicle that is only in later snapshots (it starts later) appears from its first departure; one
// that is only in earlier ones runs on by the timetable until its run is over (the destination is in every answer).
//
// Memory: the vehicle with its stop names is kept once per trip (the newest answer, for the line plate, the filter and the sheet); the
// observations and the merged run are compact. The number of trips and of observations per trip is bounded.

/// What the timeline remembers about one answer: for the age of the delays and the progress, not for positions.
public struct RadarTimeFrame: Sendable, Hashable {
    /// The time the positions belong to.
    public var time: Date
    /// When the answer arrived: the delays in it are as old as this.
    public var fetchedAt: Date
    public var vehicleCount: Int
    /// The answer was not cut off at the request cap (a cut-off answer misses vehicles, so it never removes any).
    public var isComplete: Bool

    public init(time: Date, fetchedAt: Date, vehicleCount: Int, isComplete: Bool = true) {
        self.time = time
        self.fetchedAt = fetchedAt
        self.vehicleCount = vehicleCount
        self.isComplete = isComplete
    }
}

/// A vehicle as the Zeitreise draws it: where it is at the chosen time, how that was found, and the delay it carries.
public struct RadarTimePin: Sendable, Hashable, Identifiable {
    public var tripID: String
    /// The newest answer's vehicle: line, direction, stop names. Its own coordinate is the server's position at the time of that answer.
    public var vehicle: RadarVehicle
    public var coordinate: GeoPoint
    public var bearing: Double?
    public var phase: RadarRunPhase
    public var path: RadarPathKind
    /// Seconds between the chosen time and the nearest answer that knows this vehicle.
    public var distanceToAnswer: TimeInterval
    /// The delay the train carries at the chosen time (reported or carried on along the run); nil without any report.
    public var delaySeconds: Int?

    public var id: String { tripID }

    /// Within this of an answer the position is the server's own (the dashed "estimated" ring is only for calculated positions).
    public static let solidWithin: TimeInterval = 30
    public var isCalculated: Bool { distanceToAnswer > Self.solidWithin }

    public var delayState: RadarDelayState {
        if vehicle.isCancelled { return .cancelled }
        guard let delaySeconds else { return .unknown }
        return delaySeconds >= RadarDelay.lateThresholdSeconds ? .late : .onTime
    }
}

public struct RadarTimeline: Sendable {
    public struct Observation: Sendable, Hashable {
        /// The time the position belongs to (`RadarQuery.when`).
        public var time: Date
        /// When the answer arrived.
        public var fetchedAt: Date
        public var position: GeoPoint
        public var schedule: RadarSchedule
        /// The position as an anchor of the projection, when it fits the stops.
        public var anchor: RadarAnchor?
    }

    public struct Trip: Sendable {
        public var vehicle: RadarVehicle
        public var vehicleFetchedAt: Date
        /// Sorted by time.
        public var observations: [Observation]
        /// All observations merged: what the timeline asks.
        public var run: RadarRunPath
        /// The end of the run (the destination's arrival with its delay), or the last answer's time when the run has no path.
        public var endsAt: Date

        init(vehicle: RadarVehicle, fetchedAt: Date, observations: [Observation]) {
            self.vehicle = vehicle
            vehicleFetchedAt = fetchedAt
            self.observations = observations
            run = RadarRunPath(schedule: RadarSchedule())
            endsAt = observations.last?.time ?? .distantPast
            rebuild()
        }

        mutating func rebuild() {
            let schedule = RadarSchedule.merged(observations.map { ($0.schedule, $0.fetchedAt) })
            run = RadarRunPath(schedule: schedule, anchors: observations.compactMap(\.anchor))
            endsAt = run.lastTime ?? observations.last?.time ?? .distantPast
        }
    }

    public struct Limits: Sendable, Equatable {
        /// Trips kept. A full day of Austrian rail is about 3 000 runs; 6 000 leaves room for buses of a city.
        public var maxTrips = 6000
        public var maxObservationsPerTrip = 14
        /// Observations of one trip closer than this are one: the newer answer replaces the older (a refresh for a minute replaces that minute).
        public var mergeWindow: TimeInterval = 150
        public var maxFrames = 40

        public init() {}
    }

    public let limits: Limits
    public private(set) var trips: [String: Trip] = [:]
    public private(set) var frames: [RadarTimeFrame] = []

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    public var tripCount: Int { trips.count }
    public var observationCount: Int { trips.values.reduce(0) { $0 + $1.observations.count } }
    public var isEmpty: Bool { trips.isEmpty }

    /// The newest vehicle of a trip (for the sheet, the filter, the search).
    public func vehicle(_ tripID: String) -> RadarVehicle? { trips[tripID]?.vehicle }

    // MARK: Adding answers

    /// One answer for `time`. With `isComplete` the answer is the whole truth for that time (a request for all of Austria that was
    /// not cut off): observations of vehicles it does not contain, near that time and older than it, are removed, so a train that has
    /// ended or left is not projected on from an older answer. A cut-off or partial answer (one tile of a split) only adds.
    public mutating func addFrame(_ vehicles: [RadarVehicle], time: Date, fetchedAt: Date, isComplete: Bool = true) {
        var seen = Set<String>()
        seen.reserveCapacity(vehicles.count)
        for vehicle in vehicles {
            insert(vehicle, time: time, fetchedAt: fetchedAt)
            seen.insert(vehicle.tripID)
        }
        if isComplete {
            for (id, trip) in trips where !seen.contains(id) {
                let kept = trip.observations.filter { !(abs($0.time.timeIntervalSince(time)) <= limits.mergeWindow && $0.fetchedAt <= fetchedAt) }
                guard kept.count != trip.observations.count else { continue }
                if kept.isEmpty {
                    trips[id] = nil
                } else {
                    var changed = trip
                    changed.observations = kept
                    changed.rebuild()
                    trips[id] = changed
                }
            }
        }
        record(RadarTimeFrame(time: time, fetchedAt: fetchedAt, vehicleCount: vehicles.count, isComplete: isComplete))
        enforceTripLimit()
    }

    /// The vehicles of the live radar at the moment the Zeitreise starts: each with the time of its own answer.
    public mutating func addLive(_ entries: [(vehicle: RadarVehicle, time: Date)]) {
        for entry in entries { insert(entry.vehicle, time: entry.time, fetchedAt: entry.time) }
        if let newest = entries.map(\.time).max(), let oldest = entries.map(\.time).min() {
            record(RadarTimeFrame(time: newest, fetchedAt: oldest, vehicleCount: entries.count, isComplete: false))
        }
        enforceTripLimit()
    }

    private mutating func insert(_ vehicle: RadarVehicle, time: Date, fetchedAt: Date) {
        let schedule = RadarSchedule(vehicle)
        guard schedule.isProjectable else { return }
        let observation = Observation(
            time: time, fetchedAt: fetchedAt, position: vehicle.coordinate, schedule: schedule,
            anchor: RadarProjection.validatedAnchor(for: schedule, time: time, coordinate: vehicle.coordinate))
        guard var trip = trips[vehicle.tripID] else {
            trips[vehicle.tripID] = Trip(vehicle: vehicle, fetchedAt: fetchedAt, observations: [observation])
            return
        }
        // One observation per window: the newer answer wins, an older one never replaces a newer one.
        let near = trip.observations.indices.filter { abs(trip.observations[$0].time.timeIntervalSince(time)) <= limits.mergeWindow }
        if near.contains(where: { trip.observations[$0].fetchedAt > fetchedAt }) { return }
        for index in near.reversed() { trip.observations.remove(at: index) }
        let at = trip.observations.firstIndex { $0.time > time } ?? trip.observations.endIndex
        trip.observations.insert(observation, at: at)
        if trip.observations.count > limits.maxObservationsPerTrip,
           let oldest = trip.observations.indices.min(by: { trip.observations[$0].fetchedAt < trip.observations[$1].fetchedAt }) {
            trip.observations.remove(at: oldest)
        }
        if fetchedAt >= trip.vehicleFetchedAt {
            trip.vehicle = vehicle
            trip.vehicleFetchedAt = fetchedAt
        }
        trip.rebuild()
        trips[vehicle.tripID] = trip
    }

    private mutating func record(_ frame: RadarTimeFrame) {
        // An answer older than one already recorded for the same minute is not a frame of its own.
        if frames.contains(where: { abs($0.time.timeIntervalSince(frame.time)) <= limits.mergeWindow && $0.fetchedAt > frame.fetchedAt }) { return }
        frames.removeAll { abs($0.time.timeIntervalSince(frame.time)) <= limits.mergeWindow && $0.fetchedAt <= frame.fetchedAt }
        frames.append(frame)
        frames.sort { $0.time < $1.time }
        if frames.count > limits.maxFrames { frames.removeFirst(frames.count - limits.maxFrames) }
    }

    /// The most trips the timeline keeps: those whose run ends first go first.
    private mutating func enforceTripLimit() {
        guard trips.count > limits.maxTrips else { return }
        let doomed = trips.sorted { $0.value.endsAt < $1.value.endsAt }.prefix(trips.count - limits.maxTrips)
        for (id, _) in doomed { trips[id] = nil }
    }

    /// Drops what is over: trips whose run ended more than `grace` ago, and observations from before `now` that no later time needs
    /// (the newest one at or before `now` stays: it is the anchor for everything after it).
    public mutating func prune(now: Date, grace: TimeInterval = 120) {
        for (id, trip) in trips {
            if trip.endsAt < now.addingTimeInterval(-grace) {
                trips[id] = nil
                continue
            }
            guard let newestPast = trip.observations.lastIndex(where: { $0.time <= now }), newestPast > 0 else { continue }
            var changed = trip
            changed.observations.removeFirst(newestPast)
            changed.rebuild()
            trips[id] = changed
        }
        frames.removeAll { $0.time < now.addingTimeInterval(-3600) }
    }

    // MARK: Where is everything at T

    /// The age of the delays behind the positions at `time`: how long ago the answers on both sides of it arrived (the older one).
    public func delayDataAge(at time: Date, now: Date) -> TimeInterval? {
        let before = frames.last { $0.time <= time }
        let after = frames.first { $0.time > time }
        guard let oldest = [before?.fetchedAt, after?.fetchedAt].compactMap({ $0 }).min() else { return nil }
        return max(0, now.timeIntervalSince(oldest))
    }

    /// Every vehicle that is on its way at `time`, ordered by trip id. `routes` holds polylines for the trips that have one.
    public func pins(at time: Date, routes: [String: RadarRoute] = [:]) -> [RadarTimePin] {
        trips.keys.sorted().compactMap { id in pin(for: id, at: time, route: routes[id]) }
    }

    /// One vehicle at `time`; nil when it has not started, is over, or is unknown.
    public func pin(for tripID: String, at time: Date, route: RadarRoute? = nil) -> RadarTimePin? {
        guard let trip = trips[tripID], let projected = trip.run.position(at: time, route: route) else { return nil }
        let gap = trip.observations.map { abs($0.time.timeIntervalSince(time)) }.min() ?? .infinity
        return RadarTimePin(tripID: tripID, vehicle: trip.vehicle, coordinate: projected.coordinate, bearing: projected.bearing,
                            phase: projected.phase, path: projected.path, distanceToAnswer: gap, delaySeconds: trip.run.delay(at: time))
    }

    /// The path of one vehicle over the `minutes` before `time` (one point a minute, ending at `time`): the trail of the selected train.
    /// Minutes in which the vehicle had not started are left out; nothing when it is not on its way at `time`.
    public func trail(for tripID: String, endingAt time: Date, minutes: Int = 10, route: RadarRoute? = nil) -> [GeoPoint] {
        guard pin(for: tripID, at: time, route: route) != nil else { return [] }
        var points: [GeoPoint] = []
        for back in stride(from: max(minutes, 0), through: 0, by: -1) {
            guard let pin = pin(for: tripID, at: time.addingTimeInterval(-Double(back) * 60), route: route) else { continue }
            if points.last != pin.coordinate { points.append(pin.coordinate) }
        }
        return points
    }
}

// MARK: - Filter on a pin

public extension RadarFilter {
    /// The same filter as `matches(_:now:)`, with the delay of the projected pin instead of the one at "now": in a Zeitreise the delay
    /// that counts is the one the train carries at the chosen time.
    func matches(_ pin: RadarTimePin) -> Bool {
        if !categories.isEmpty, !categories.contains(RadarLine.category(of: pin.vehicle.line)) { return false }
        let delay = pin.delayState
        if !delays.isEmpty, !delays.contains(delay) { return false }
        if onlyLate, delay != .late { return false }
        if let state, AustrianState.guess(for: pin.vehicle) != state { return false }
        return true
    }
}
