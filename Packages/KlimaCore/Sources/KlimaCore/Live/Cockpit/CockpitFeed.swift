import Foundation

// Cockpit-Ansicht, part 8: what feeds the cockpit (docs/RADAR_COCKPIT.md). The followed train arrives in two kinds of answers: the radar for a small
// box around it (the position, and its four stops with the freshest delays) every 20 seconds, and JourneyDetails (every stop, the polyline) once and
// then now and then. `CockpitFeed` merges them into one picture: the route, the train's place along it between two answers (`RadarEstimate`, the
// same rule as the radar), the speed, the session state and the numbers of the HUD. Pure: `now` is a parameter, nothing here sends a request.

// MARK: - Merge

public enum CockpitMerge {
    /// The same stop in two answers: the same HAFAS location id, else the same extId, else the same place (within 100 m).
    static func sameStop(_ a: Location, _ b: Location) -> Bool {
        if a.lid == b.lid { return true }
        if let x = a.extId, let y = b.extId, !x.isEmpty, x == y { return true }
        if let p = a.coordinate, let q = b.coordinate { return p.distanceKm(to: q) <= 0.1 }
        return false
    }

    /// The stops of `details` with the events of the radar's answer where that answer is the fresher one: the radar's four stops carry
    /// the delays of the last few seconds, the details those of the last minutes. An event is replaced when the radar's carries a realtime
    /// (or a cancellation) for the same planned time; an event without a realtime never replaces one that has it (a delay does not vanish
    /// because one answer says nothing about it).
    public static func stopovers(details: [Stopover], radar: [Stopover]) -> [Stopover] {
        guard !radar.isEmpty else { return details }
        func fresher(_ old: StopEvent?, _ new: StopEvent?) -> StopEvent? {
            guard let new else { return old }
            guard let old else { return new }
            guard let oldPlanned = old.planned, let newPlanned = new.planned, oldPlanned == newPlanned else { return old }
            return new.realtime != nil || new.isCancelled ? new : old
        }
        return details.map { stop in
            guard let hit = radar.first(where: { sameStop($0.location, stop.location) }) else { return stop }
            var merged = stop
            merged.arrival = fresher(stop.arrival, hit.arrival)
            merged.departure = fresher(stop.departure, hit.departure)
            return merged
        }
    }
}

// MARK: - Request plan

/// What the cockpit asks the radar for: a small box around the train, only its kind of train.
public enum CockpitRequestPlan {
    /// Half the side of the box at least, kilometres: 5 km each way, so the train stays inside for the 20 seconds between two answers at 250 km/h
    /// (1.4 km) with room to spare.
    public static let minHalfKm = 5.0
    public static let maxHalfKm = 30.0

    /// The box: centred on where the train is thought to be, wider the older that position is (the train may have gone on: at `speedKmh`,
    /// `age` seconds and one more refresh interval, with a margin of half as much again).
    public static func box(around center: GeoPoint, ageSeconds: TimeInterval, speedKmh: Double?, interval: TimeInterval = 20) -> RadarBox {
        let speed = min(max(speedKmh ?? 200, 0), 300)
        let travelled = speed / 3600 * (max(ageSeconds, 0) + interval) * 1.5
        let half = min(max(minHalfKm, 1.5 + travelled), maxHalfKm)
        let dLat = half / 110.574
        let dLon = half / (111.32 * max(cos(center.latitude * .pi / 180), 0.2))
        return RadarBox(north: center.latitude + dLat, west: center.longitude - dLon, south: center.latitude - dLat, east: center.longitude + dLon).clamped
    }

    /// The product filter: the train's own product class (one bit: Railjet, regional train, S-Bahn ...), so the answer holds the trains of that
    /// kind only. Without a class: all rail.
    public static func products(for line: Line?) -> ProductMask {
        guard let line, line.productClass != 0 else { return .rail }
        return ProductMask(rawValue: line.productClass)
    }
}

// MARK: - Scheduler

/// When the cockpit asks: the position every 20 seconds, the full run once and then every three minutes (its stop list keeps the delays beyond
/// the four stops of the radar fresh). Pure: the caller asks `next(now:)`, sends what it names through the radar's request budget and reports
/// the outcome.
public struct CockpitScheduler: Sendable {
    public enum Kind: Sendable, Hashable { case position, details }

    public enum Step: Sendable, Equatable {
        case request(Kind)
        case wait(until: Date)
    }

    public struct Config: Sendable, Equatable {
        public var positionInterval: TimeInterval = 20
        /// While the train is lost: slower, the train may come back.
        public var lostInterval: TimeInterval = 30
        public var detailsInterval: TimeInterval = 180
        /// While the train is lost: JourneyDetails carries its position too, so it is asked more often. Counted from the answer (the caller
        /// reports it with the time it came back), and not shorter than the client keeps an answer (`HafasClient`, 60 s): at 45 s every
        /// second request was the same answer out of that cache, a slot of the budget for nothing (review 2).
        public var lostDetailsInterval: TimeInterval = 60
        public var baseBackoff: TimeInterval = 15
        public var maxBackoff: TimeInterval = 120
        /// A request that never reported back frees its slot after this long: longer than the client can take for one request (two tries of
        /// at most 60 s, 1.5 s between them, up to 5 s in the throttle before each: 131.5 s), as on the radar (`RadarSchedulerConfig`). At 90 s
        /// a slow answer that was still loading was asked a second time (review 2).
        public var requestTimeout: TimeInterval = 150

        public init() {}
    }

    private struct State: Sendable {
        var lastRequestAt: Date?
        var lastAnswerAt: Date?
        var failures = 0
        var retryAt: Date?
        var isInFlight = false
    }

    public let config: Config
    private var states: [Kind: State] = [:]
    private var pausedUntil: Date?
    private var manual = false

    public init(config: Config = Config()) {
        self.config = config
    }

    private func due(_ kind: Kind, now: Date, lost: Bool) -> Date {
        let state = states[kind] ?? State()
        // On its way: nothing else of this kind until it answers, or until the request has timed out (then its slot is free again).
        if state.isInFlight, let last = state.lastRequestAt { return last.addingTimeInterval(config.requestTimeout) }
        var at: Date
        switch kind {
        case .position:
            at = state.lastRequestAt.map { $0.addingTimeInterval(lost ? config.lostInterval : config.positionInterval) } ?? .distantPast
        case .details:
            let interval = lost ? config.lostDetailsInterval : config.detailsInterval
            at = state.lastAnswerAt.map { $0.addingTimeInterval(interval) } ?? (state.lastRequestAt.map { $0.addingTimeInterval(config.baseBackoff) } ?? .distantPast)
        }
        if manual, kind == .position, !state.isInFlight { at = .distantPast }
        if let retryAt = state.retryAt { at = max(at, retryAt) }
        if let pausedUntil { at = max(at, pausedUntil) }
        return at
    }

    /// What to do now. The position goes first, details (the full run) when the position is not due. `lost`: the train has no position
    /// for a while, the position is asked more slowly. `wantsDetails`: false once the run has ended (nothing is asked then at all).
    public mutating func next(now: Date, lost: Bool = false, ended: Bool = false) -> Step {
        guard !ended else { return .wait(until: .distantFuture) }
        // The first thing after opening: the full run (stop list and polyline) next to the first position.
        var earliest = Date.distantFuture
        for kind in [Kind.position, .details] {
            let at = due(kind, now: now, lost: lost)
            if at <= now {
                var state = states[kind] ?? State()
                state.lastRequestAt = now
                state.isInFlight = true
                states[kind] = state
                if kind == .position { manual = false }
                return .request(kind)
            }
            earliest = min(earliest, at)
        }
        return .wait(until: earliest)
    }

    /// An answer: the next request of this kind is due after its interval.
    public mutating func recordAnswer(_ kind: Kind, at now: Date) {
        var state = states[kind] ?? State()
        state.lastAnswerAt = now
        state.failures = 0
        state.retryAt = nil
        state.isInFlight = false
        states[kind] = state
    }

    /// A failed request: this kind backs off (15 s, 30 s ... up to 2 min). A rate limit or an open circuit pauses both.
    public mutating func recordFailure(_ kind: Kind, error: Error?, at now: Date) {
        var state = states[kind] ?? State()
        state.failures += 1
        var wait = min(config.baseBackoff * pow(2, Double(state.failures - 1)), config.maxBackoff)
        if let live = error as? LiveError {
            switch live {
            case .rateLimited(_, let retryAfter):
                let pause = max(retryAfter ?? 20, 10)
                pausedUntil = now.addingTimeInterval(pause)
                wait = max(wait, pause)
            case .circuitOpen(_, let until):
                pausedUntil = max(until, now.addingTimeInterval(10))
                wait = max(wait, until.timeIntervalSince(now))
            case .disabled:
                pausedUntil = now.addingTimeInterval(300)
                wait = max(wait, 300)
            default:
                break
            }
        }
        state.retryAt = now.addingTimeInterval(wait)
        state.isInFlight = false
        states[kind] = state
    }

    /// The request was cancelled before it answered (the cockpit closed): due again as before.
    public mutating func recordCancelled(_ kind: Kind) {
        states[kind]?.isInFlight = false
        states[kind]?.lastRequestAt = nil
    }

    /// The whole cockpit waits until `time` (a rate limit that another request ran into).
    public mutating func pause(until time: Date) {
        pausedUntil = max(pausedUntil ?? .distantPast, time)
    }

    /// "Jetzt aktualisieren", "Erneut versuchen": the position is asked at once, whatever the interval, the backoff or this cockpit's own
    /// pause say. A rate limit or an open circuit still holds it: the caller sends only through the radar's budget, which carries that
    /// pause (`RadarScheduler.claimSlot`, `CockpitModel.Services.pause`).
    public mutating func refreshNow() {
        manual = true
        states[.position]?.retryAt = nil
        states[.position]?.failures = 0
        pausedUntil = nil
    }

    public func failures(_ kind: Kind) -> Int { states[kind]?.failures ?? 0 }
    public func isInFlight(_ kind: Kind) -> Bool { states[kind]?.isInFlight ?? false }
}

// MARK: - Frame

/// Everything the views draw at one moment.
public struct CockpitFrame: Sendable {
    /// Where to draw the train: the estimate between two answers, put on the route when it is within 300 m of it.
    public var coordinate: GeoPoint
    /// Along the route, when it is known.
    public var km: Double?
    /// The marker is between two answers that differ (it moves) rather than at the latest one.
    public var isEstimate: Bool
    public var route: CockpitRoute?
    /// Only the radar's four stops are known so far (the full run is on its way): the next stop and its time are right, the route and the
    /// progress are not shown.
    public var isProvisional: Bool
    public var summary: CockpitSummary?
    /// Direction of travel, degrees clockwise from north.
    public var heading: Double?
    public var speed: CockpitSpeedEstimator.Reading
    /// Age of the latest answer that carried the position.
    public var fixAge: TimeInterval?
    public var state: CockpitSession.State
    public var isCancelled: Bool
    /// The marker shows where the train was, not where it is: lost, or a position older than two minutes on a run that has not ended
    /// (back from the background, in Low Power Mode, without live data). Drawn grey and without glow until a fresh answer comes.
    public var isStale: Bool
}

/// Where the train is drawn, and which way it points.
public struct CockpitMarker: Sendable, Equatable {
    public var coordinate: GeoPoint
    public var km: Double?
    public var isEstimate: Bool
    /// Direction of travel, degrees clockwise from north.
    public var heading: Double?
}

// MARK: - Feed

public struct CockpitFeed: Sendable {
    public let tripID: String
    public private(set) var line: Line?
    public private(set) var direction: String?
    public private(set) var session: CockpitSession
    public private(set) var speed = CockpitSpeedEstimator()
    public private(set) var details: TripDetails?
    public private(set) var route: CockpitRoute?

    private var detailsAt: Date?
    private var radarStops: [Stopover] = []
    private var radarAt: Date?
    private var radarCancelled = false
    private var store = RadarFrameStore(retention: 12 * 3600)
    /// Where the train was along the route at the latest answer and at the one before: the window the next projection searches in.
    private var kmLatest: Double?
    private var kmPrevious: Double?

    /// Opened from a train on the radar: its position and four stops are the first answer (`seenAt`), the cached details (when the trip sheet
    /// loaded them) give the whole run at once.
    public init(vehicle: RadarVehicle, seenAt: Date, now: Date, mode: CockpitCameraMode = .follow, details: TripDetails? = nil, detailsAt: Date? = nil) {
        tripID = vehicle.tripID
        session = CockpitSession(startedAt: now, mode: mode)
        if let details {
            self.details = details
            self.detailsAt = detailsAt ?? seenAt
        }
        ingest(vehicle, at: seenAt)
        session.answer(at: seenAt, hasPosition: true)
    }

    // MARK: Answers

    /// An answer of the radar for the cockpit's box: the train is in it, or not.
    public mutating func applyRadar(_ snapshot: RadarSnapshot, requestedAt: Date) {
        if let vehicle = snapshot.vehicles.first(where: { $0.tripID == tripID }) {
            ingest(vehicle, at: requestedAt)
            session.answer(at: requestedAt, hasPosition: true)
        } else {
            session.answer(at: requestedAt, hasPosition: false)
        }
    }

    /// An answer of JourneyDetails: every stop, the polyline, and (measured, docs/RADAR_COCKPIT.md §2) the train's own position `pos`. That
    /// position is used only when the radar has not given one for a while (the train was not in its box): two sources for the same
    /// moment would make the marker step back and forth.
    /// `at` is the time the answer was asked for (`TripDetails.fetchedAt`), not the time it arrived: the client hands out an answer it already
    /// has for 60 s, and its position is as old as that answer (review 2: stamped with the time of the call, a cached position from the trip sheet
    /// replaced the radar's fresh one, and "Stand vor 0 s" was wrong by up to a minute).
    public mutating func applyDetails(_ trip: TripDetails, at: Date) {
        // The answer is for the trip that was asked for, whatever form its id comes back in.
        if let known = detailsAt, at < known { return }
        details = trip
        detailsAt = at
        line = trip.line ?? line
        direction = trip.direction ?? direction
        rebuild()
        let usable = trip.currentPosition.flatMap { CockpitGeo.isUsable($0) ? $0 : nil }
        if let position = usable, session.lastPositionAt.map({ at.timeIntervalSince($0) > Self.detailsPositionAfter }) ?? true {
            ingestPosition(RadarVehicle(tripID: tripID, line: line, direction: direction, coordinate: position, stopovers: radarStops,
                                        isCancelled: radarCancelled || trip.isCancelled), at: at)
            session.answer(at: at, hasPosition: true)
        } else {
            // A position the cockpit does not take (the radar's is fresher) still says that the train is running.
            session.answer(at: at, hasPosition: false, listsTrain: usable != nil)
        }
    }

    /// The position of JourneyDetails is taken when the radar's is older than this.
    static let detailsPositionAfter: TimeInterval = 40

    private mutating func ingest(_ vehicle: RadarVehicle, at: Date) {
        let isNewest = radarAt.map { at >= $0 } ?? true
        guard isNewest else {
            store.merge([vehicle], at: at)   // the store keeps the newer one
            return
        }
        radarAt = at
        radarStops = vehicle.stopovers
        radarCancelled = vehicle.isCancelled
        line = vehicle.line ?? line
        direction = vehicle.direction ?? direction
        rebuild()
        ingestPosition(vehicle, at: at)
    }

    /// The position of an answer: into the store (the estimate between two answers), the place along the route, the speed. A position older
    /// than the one the store holds changes nothing (two answers can arrive out of order).
    private mutating func ingestPosition(_ vehicle: RadarVehicle, at: Date) {
        if let held = store.entries[tripID], at < held.seenAt { return }
        store.merge([vehicle], at: at)
        var km: Double?
        if let route, details != nil {
            km = kmLatest.flatMap { route.km(of: vehicle.coordinate, hintKm: $0, windowKm: 15) } ?? route.km(of: vehicle.coordinate)
        }
        kmPrevious = kmLatest
        kmLatest = km
        speed.add(coordinate: vehicle.coordinate, km: km, at: at)
    }

    private mutating func rebuild() {
        var stops = details?.stopovers ?? radarStops
        if let details, let radarAt, radarAt >= (detailsAt ?? .distantPast), !radarStops.isEmpty {
            stops = CockpitMerge.stopovers(details: details.stopovers, radar: radarStops)
        }
        route = CockpitRoute(stopovers: stops, polyline: details?.polyline, isCancelled: radarCancelled || details?.isCancelled == true)
    }

    // MARK: Clock

    /// The time moved on: the session decides lost, ended. The run is over when the train stands at its last stop, or when it left the radar
    /// near the end of its run (a train that arrived is taken off the radar).
    public mutating func tick(now: Date) {
        // The end of the run is the last stop the train calls at (a train that turns short ends there, `CockpitRoute.endIndex`).
        let end = route.flatMap { $0.endStop.arrival ?? $0.endStop.departure }
        var atEnd = false
        // Only the place along the route is needed here: `position`, not a whole frame with its summary and strings.
        if let route, details != nil, let km = position(now: now)?.km {
            if case .arrived = route.situation(atKm: km, now: now) { atEnd = true }
            // Taken off the radar: an answer after the last position did not list the train. Time alone is no evidence (review 2: back from the
            // background after minutes, nothing had been asked, and the run ended for good before the first new answer).
            if !atEnd, let seen = session.lastPositionAt, let missing = session.lastMissingAt, missing > seen,
               now.timeIntervalSince(seen) >= Self.vanishedAfter, let end, now >= end.addingTimeInterval(-120),
               let latest = kmLatest, latest >= route.lastKm - Self.nearEndKm {
                atEnd = true
            }
        }
        session.tick(now: now, atLastStop: atEnd, scheduleEnd: end)
    }

    /// A train that is missing this long near the end of its run has arrived.
    static let vanishedAfter: TimeInterval = 45
    static let nearEndKm = 6.0

    // MARK: Session

    public mutating func select(_ mode: CockpitCameraMode) { session.select(mode) }
    /// The cockpit does not ask right now, or asks again (`CockpitSession.pauseLostClock`).
    public mutating func pauseLostClock(at now: Date) { session.pauseLostClock(at: now) }
    public mutating func userMovedMap() { session.userMovedMap() }
    public mutating func returnToTrain() { session.returnToTrain() }

    // MARK: Position

    /// Where the train is now. nil until a position is known (never, after `init`).
    public func position(now: Date) -> (coordinate: GeoPoint, km: Double?, isEstimate: Bool)? {
        guard let entry = store.entries[tripID] else { return nil }
        let shown = RadarEstimate.shown(entry, now: now)
        guard let route, details != nil else { return (shown.coordinate, nil, shown.isEstimate) }
        let low = min(kmPrevious ?? kmLatest ?? 0, kmLatest ?? 0) - 0.5
        let high = max(kmPrevious ?? kmLatest ?? 0, kmLatest ?? 0) + 0.5
        let hit: (km: Double, point: GeoPoint, offKm: Double)?
        if kmLatest != nil { hit = route.place(shown.coordinate, fromKm: low, toKm: high) } else { hit = route.place(shown.coordinate) }
        guard let hit else { return (shown.coordinate, nil, shown.isEstimate) }
        return (hit.offKm <= CockpitRoute.snapKm ? hit.point : shown.coordinate, hit.km, shown.isEstimate)
    }

    /// The next answer's box: around the train where it is thought to be, wide enough for the time that went by.
    public func requestBox(now: Date, interval: TimeInterval = 20) -> RadarBox? {
        guard let place = position(now: now), let entry = store.entries[tripID] else { return nil }
        // After the latest answer the train goes on: the box is centred on the latest answer and widened by the age, so the train is inside
        // wherever the estimate is.
        let age = max(now.timeIntervalSince(entry.seenAt), 0)
        return CockpitRequestPlan.box(around: entry.vehicle.coordinate, ageSeconds: age, speedKmh: speed.reading(now: now).kmh, interval: interval)
            .union(with: place.coordinate)
    }

    public var products: ProductMask { CockpitRequestPlan.products(for: line) }

    // MARK: Frame

    /// The cheap part of a frame, asked every few hundredths of a second: where to draw the train and what the camera needs.
    private struct Context {
        var place: (coordinate: GeoPoint, km: Double?, isEstimate: Bool)
        var entry: RadarFrameStore.Entry
        var reading: CockpitSpeedEstimator.Reading
        var held: Bool
        var next: GeoPoint?
        var effectiveKm: Double?
    }

    private func context(now: Date) -> Context? {
        guard let entry = store.entries[tripID], let place = position(now: now) else { return nil }
        let reading = speed.reading(now: now)
        var held = false
        var next: GeoPoint?
        var effectiveKm = place.km
        if let route {
            effectiveKm = place.km ?? provisionalKm(route, at: place.coordinate)
            if let km = effectiveKm {
                switch route.situation(atKm: km, now: now) {
                case .atStop, .beforeDeparture, .arrived: held = true
                case .between: break
                }
                next = route.nextStopIndex(atKm: km, now: now).map { route.stops[$0].coordinate }
            }
        }
        return Context(place: place, entry: entry, reading: reading, held: held, next: next, effectiveKm: effectiveKm)
    }

    private func cameraInput(_ context: Context, mode: CockpitCameraMode, reduceMotion: Bool) -> CockpitCameraInput {
        let provisional = details == nil
        let kmh: Double? = context.held ? 0 : (context.reading.kmh ?? (context.reading == .standing ? 0 : nil))
        return CockpitCameraInput(train: context.place.coordinate, trainKm: provisional ? nil : context.place.km,
                                  path: provisional ? nil : route?.path, speedKmh: kmh, previous: context.entry.previousCoordinate,
                                  nextStop: context.next, mode: mode, reduceMotion: reduceMotion)
    }

    /// What the camera planner needs, now. nil until a position is known.
    public func cameraInput(now: Date, mode: CockpitCameraMode, reduceMotion: Bool) -> CockpitCameraInput? {
        context(now: now).map { cameraInput($0, mode: mode, reduceMotion: reduceMotion) }
    }

    /// The train's marker, now: the cheap part of a frame (no summary, no strings).
    public func marker(now: Date) -> CockpitMarker? {
        guard let context = context(now: now) else { return nil }
        let heading = CockpitCameraPlanner.travelHeading(cameraInput(context, mode: .follow, reduceMotion: false))
        return CockpitMarker(coordinate: context.place.coordinate, km: context.place.km, isEstimate: context.place.isEstimate, heading: heading)
    }

    /// Everything the views draw, now. The summary costs a few allocations: once a second is enough.
    public func frame(now: Date) -> CockpitFrame? {
        guard let context = context(now: now) else { return nil }
        let age = max(now.timeIntervalSince(context.entry.seenAt), 0)
        var summary: CockpitSummary?
        if let route, let km = context.effectiveKm {
            summary = CockpitSummary.make(route: route, km: km, now: now, speed: context.reading, fixAge: age,
                                          lineTitle: line.map { LinePresentation.title($0) } ?? "Zug", destination: direction ?? route.stops.last?.name)
            if details == nil {
                // The chain of the radar's four stops is not the route: a distance or a share of the run along it would be a guess
                // that looks like a measurement.
                summary?.isProvisional = true
                summary?.distanceKm = nil
            }
        }
        let input = cameraInput(context, mode: .follow, reduceMotion: false)
        let state = session.state
        let stale = state == .lost || (state != .ended && age >= session.config.lostAfter)
        return CockpitFrame(coordinate: context.place.coordinate, km: context.place.km, isEstimate: context.place.isEstimate, route: route,
                            isProvisional: details == nil, summary: summary, heading: CockpitCameraPlanner.travelHeading(input),
                            speed: context.reading, fixAge: age, state: state, isCancelled: route?.isCancelled ?? radarCancelled, isStale: stale)
    }

    /// With only the radar's four stops there is no polyline: the train's place on the chain of stops (for the next stop and the delay).
    private func provisionalKm(_ route: CockpitRoute, at coordinate: GeoPoint) -> Double? {
        route.km(of: coordinate) ?? route.path.project(coordinate)?.km
    }
}

extension RadarBox {
    /// The box grown to contain `point`.
    func union(with point: GeoPoint) -> RadarBox {
        RadarBox(north: max(north, point.latitude), west: min(west, point.longitude), south: min(south, point.latitude), east: max(east, point.longitude))
    }
}
