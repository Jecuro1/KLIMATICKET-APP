import SwiftUI
import MapKit
import KlimaCore

// MARK: radarcockpit – the model of the Cockpit-Ansicht (docs/RADAR_COCKPIT.md). The logic lives in KlimaCore (`CockpitFeed`, `CockpitScheduler`,
// `CockpitCameraController`); this model runs the one loop of the cockpit: the position of the followed train every 20 seconds through the radar's
// request budget, the clock once a second, the camera a few times a second. The radar loop below the cockpit is stopped while it is open.

/// What opens the cockpit: the train as the radar knows it, and where the camera starts.
struct CockpitLaunch: Identifiable {
    /// Demo scenes only: what the scene shows.
    enum Scenario { case live, lost, ended }

    var vehicle: RadarVehicle
    /// The details the trip sheet already loaded (stops, polyline); nil: the cockpit asks for them first thing.
    var details: TripDetails?
    /// When the radar saw the train at `vehicle.coordinate`.
    var seenAt: Date
    var mode: CockpitCameraMode = .follow
    /// Where the radar's map was: the camera flies from there to the train.
    var startCamera: CockpitCamera?
    /// A scene that holds its camera (the free scene).
    var staticCamera: CockpitCamera?
    var scenario: Scenario = .live
    /// Demo scenes only: earlier answers of the radar for this train (oldest first, before `seenAt`), so a scene starts as the live cockpit is
    /// after a minute: with a speed estimate. The live cockpit starts with the one answer the radar has.
    var earlier: [Sighting] = []

    struct Sighting {
        var vehicle: RadarVehicle
        var at: Date
    }

    var id: String { vehicle.tripID }
}

/// A piece of the route as the map draws it.
struct CockpitMapLine: Identifiable {
    var id: Int
    var coordinates: [CLLocationCoordinate2D]
    var state: RadarDelayState
}

/// A stop on the map: a dot, or a flag with its time for the next ones.
struct CockpitMapStop: Identifiable {
    var id: Int
    var coordinate: CLLocationCoordinate2D
    var isPassed: Bool
    var flag: CockpitStopFlag?
}

/// The route as the map draws it, rebuilt when the train has moved a little or an answer came in.
struct CockpitMapLines {
    var passed: [CLLocationCoordinate2D] = []
    var ahead: [CockpitMapLine] = []
    var stops: [CockpitMapStop] = []
    static let empty = CockpitMapLines()
}

/// What the HUD and the banners read. Changes once a second (and on every answer), never per camera frame.
struct CockpitHUD: Equatable {
    enum Banner: Equatable {
        case waiting
        case lost(String)
        case ended(String)
    }

    var summary: CockpitSummary?
    var state: CockpitSession.State = .waiting
    var mode: CockpitCameraMode = .follow
    var offersReturn = false
    var clock = Date()
    /// Only the radar's four stops are known: the progress is not shown.
    var isProvisional = true
    /// The marker shows where the train was, not where it is (`CockpitFrame.isStale`): grey, without glow.
    var isStale = false
    var isStraightLine = false
    var isCancelled = false
    var banner: Banner?
    /// A failure or an unavailable service, said once and plainly.
    var note: String?
    var lowPower = false
}

/// A camera move the map performs itself (MapKit flies the camera): the opening flight and "Zurück zum Zug".
struct CockpitFlight: Equatable {
    var id: Int
    var target: CockpitCamera
    var duration: TimeInterval
}

@MainActor
@Observable
final class CockpitModel {
    /// What the model asks of the outside world, as closures so the demo scenes bring their own and the live cockpit goes through the gate.
    struct Services {
        /// The radar for a box; nil when live data is not available (no request is sent then).
        var radar: ((RadarQuery) async throws -> RadarSnapshot)?
        var trip: ((String) async throws -> TripDetails)?
        /// One slot of the radar's budget (24 a minute for the whole radar, docs/OEBB_LIVE.md §R11): nil = send now, else the time one frees.
        var claim: @MainActor (Date) -> Date? = { _ in nil }
        /// A rate limit or an open circuit: the radar's budget waits too.
        var pause: @MainActor (Date) -> Void = { _ in }
        /// Why nothing is asked ("Live-Daten sind aus ...").
        var unavailable: String?

        static let offline = Services()
    }

    // MARK: What the views read

    /// The camera the planner wants (about 20 times a second in the follow and bird views, never in the free view).
    private(set) var camera: CockpitCamera?
    private(set) var marker: CockpitMarker?
    private(set) var hud = CockpitHUD()
    private(set) var lines = CockpitMapLines.empty
    private(set) var flight: CockpitFlight?
    let line: Line?

    // MARK: Inside

    @ObservationIgnored private var feed: CockpitFeed
    @ObservationIgnored private var scheduler = CockpitScheduler()
    @ObservationIgnored private var controller = CockpitCameraController()
    @ObservationIgnored private let services: Services
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var holdCameraUntil = Date.distantPast
    @ObservationIgnored private var linesKm: Double?
    @ObservationIgnored private var linesVersion = 0
    @ObservationIgnored private var answers = 0
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var manualRefresh = false
    @ObservationIgnored private var holdRequestsUntil = Date.distantPast
    @ObservationIgnored private var lastError: Error?
    @ObservationIgnored private var flightCount = 0
    @ObservationIgnored private var began = false
    @ObservationIgnored private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The planner's camera has stopped moving by more than a hair (`CockpitCamera.isClose`): nothing new for the map.
    @ObservationIgnored private var cameraSettled = false
    @ObservationIgnored private let launch: CockpitLaunch

    init(launch: CockpitLaunch, services: Services, clock: @escaping () -> Date = { Date() }) {
        self.launch = launch
        self.services = services
        self.clock = clock
        line = launch.vehicle.line
        let now = clock()
        switch launch.scenario {
        case .live, .ended:
            let first = launch.earlier.first
            // The trip sheet's details are as old as their request (`TripDetails.fetchedAt`; the sheet keeps them five minutes), not as new
            // as the radar's answer.
            feed = CockpitFeed(vehicle: first?.vehicle ?? launch.vehicle, seenAt: first?.at ?? launch.seenAt, now: now, mode: launch.mode,
                               details: launch.details, detailsAt: launch.details?.fetchedAt ?? launch.seenAt)
            if first != nil {
                for sighting in launch.earlier.dropFirst() { feed.applyRadar(RadarSnapshot(vehicles: [sighting.vehicle]), requestedAt: sighting.at) }
                feed.applyRadar(RadarSnapshot(vehicles: [launch.vehicle]), requestedAt: launch.seenAt)
            }
        case .lost:
            // A train that was seen two and a half minutes ago and has not been in the answers since.
            feed = CockpitFeed(vehicle: launch.vehicle, seenAt: launch.seenAt, now: launch.seenAt, mode: launch.mode, details: launch.details,
                               detailsAt: launch.seenAt)
            feed.applyRadar(RadarSnapshot(), requestedAt: now.addingTimeInterval(-10))
        }
        feed.tick(now: now)
        if let first = feed.cameraInput(now: now, mode: launch.mode, reduceMotion: false) {
            camera = launch.staticCamera ?? CockpitCameraPlanner.target(for: first)
        }
        publish(now: now)
    }

    // MARK: Actions

    func select(_ mode: CockpitCameraMode) {
        guard feed.session.mode != mode else { return }
        let wasFree = feed.session.mode == .free
        feed.select(mode)
        if wasFree, mode.isDriven { startReturn() }
        publish(now: clock())
    }

    /// The map was moved or zoomed by a finger: the camera is the user's.
    func userMovedMap() {
        guard feed.session.mode != .free else { return }
        feed.userMovedMap()
        publish(now: clock())
    }

    /// "Zurück zum Zug": the camera flies back and the planner takes over again.
    func returnToTrain() {
        feed.returnToTrain()
        startReturn()
        publish(now: clock())
    }

    private func startReturn() {
        let now = clock()
        guard let input = feed.cameraInput(now: now, mode: feed.session.mode, reduceMotion: reduceMotion) else { return }
        let target = CockpitCameraPlanner.target(for: input)
        fly(to: target, duration: reduceMotion ? 0 : 1.4)
        controller.reset(to: target)
    }

    private func fly(to target: CockpitCamera, duration: TimeInterval) {
        flightCount += 1
        holdCameraUntil = clock().addingTimeInterval(duration + 0.1)
        flight = CockpitFlight(id: flightCount, target: target, duration: duration)
    }

    /// The opening flight from the radar's map to the train (nothing in screenshots and under Reduce Motion: the camera is simply there).
    func begin(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard !began else { return }
        began = true
        guard let target = launch.staticCamera ?? camera else { return }
        controller.reset(to: nil)
        if MotionPolicy.isStatic || reduceMotion || launch.startCamera == nil || launch.staticCamera != nil {
            camera = target
            flightCount += 1
            flight = CockpitFlight(id: flightCount, target: target, duration: 0)
            controller.reset(to: target)
            return
        }
        fly(to: target, duration: 2.0)
        controller.reset(to: target)
    }

    func setReduceMotion(_ value: Bool) { reduceMotion = value }

    /// "Jetzt aktualisieren" (Stromspar-Modus, "Erneut versuchen"): the position is asked at once, as the budget allows.
    func refreshNow() {
        scheduler.refreshNow()
        manualRefresh = true
        holdRequestsUntil = .distantPast
    }

    // MARK: Derived

    var session: CockpitSession { feed.session }

    /// The stops of the whole run (the exit alarm picks one), and the train as a vehicle the follow helpers understand.
    var followVehicle: RadarVehicle {
        RadarVehicle(tripID: feed.tripID, line: feed.line, direction: feed.direction, coordinate: marker?.coordinate ?? launch.vehicle.coordinate,
                     stopovers: feed.details?.stopovers ?? launch.vehicle.stopovers, isCancelled: hud.isCancelled)
    }

    var tripID: String { feed.tripID }

    // MARK: The loop

    /// The one loop of the cockpit, owned by the view: leaving the cockpit or the foreground cancels it and every request on its way. A cancelled
    /// request is due again in the cockpit's own schedule; its slot of the radar's budget stays used (it may have reached the server), as on the
    /// radar. A discarding group: a finished request is gone at once (a plain task group keeps every finished child until it is awaited, about 200
    /// an hour here).
    func run() async {
        var last = clock()
        var lastSecond = Date.distantPast
        // Back from the background (or just opened): nothing was asked in the meantime, so that time is no sign that the train has gone. The
        // marker is grey while its position is older than two minutes (`CockpitFrame.isStale`), and the position is asked at once.
        feed.pauseLostClock(at: last)
        await withDiscardingTaskGroup { group in
            while !Task.isCancelled {
                let now = clock()
                let dt = min(max(now.timeIntervalSince(last), 0), 0.5)
                last = now
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                sendDueRequests(now: now, into: &group)
                if now.timeIntervalSince(lastSecond) >= 1 {
                    lastSecond = now
                    feed.tick(now: now)
                    publish(now: now)
                } else {
                    updateMarker(now: now)
                }
                stepCamera(now: now, dt: dt)
                // Once the run has ended nothing moves: when the camera has come to rest (or is the user's) the loop only keeps the clock.
                let resting = feed.session.state == .ended && (cameraSettled || feed.session.mode == .free)
                let interval = (reduceMotion || MotionPolicy.isStatic || resting) ? 1.0 : CockpitCameraController.frameInterval(lowPower: lowPower)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func sendDueRequests(now: Date, into group: inout DiscardingTaskGroup) {
        guard feed.session.state != .ended else { return }
        // No live data, or Low Power Mode (it pauses the requests, as it does on the radar; "Jetzt aktualisieren" sends one round anyway): the
        // cockpit does not ask, so the time does not count towards "Keine Position mehr" (that banner would say "Keine Verbindung zu ÖBB").
        guard services.radar != nil || services.trip != nil, !(lowPower && !manualRefresh) else {
            feed.pauseLostClock(at: now)
            return
        }
        guard now >= holdRequestsUntil else { return }
        let lost = feed.session.state == .lost
        switch scheduler.next(now: now, lost: lost, ended: false) {
        case .request(let kind):
            // The radar's budget: when no slot is free the request waits (and is due again at once afterwards).
            if let free = services.claim(now) {
                scheduler.recordCancelled(kind)
                holdRequestsUntil = free
                return
            }
            group.addTask { await self.fetch(kind, at: now) }
        case .wait:
            if manualRefresh, !scheduler.isInFlight(.position) { manualRefresh = false }
        }
    }

    private func fetch(_ kind: CockpitScheduler.Kind, at requestedAt: Date) async {
        do {
            switch kind {
            case .position:
                guard let radar = services.radar else { scheduler.recordCancelled(.position); return }
                let box = feed.requestBox(now: requestedAt) ?? .around(launch.vehicle.coordinate, halfSpan: 0.06)
                let snapshot = try await radar(RadarQuery(box: box, when: requestedAt, products: feed.products))
                feed.applyRadar(snapshot, requestedAt: requestedAt)
                scheduler.recordAnswer(.position, at: requestedAt)
            case .details:
                guard let trip = services.trip else { scheduler.recordCancelled(.details); return }
                let details = try await trip(feed.tripID)
                RadarRouteCache.shared.store(details)
                // The answer is as old as its request: the client hands out the same answer for 60 s (`TripDetails.fetchedAt`), and its
                // position must not count as one of now.
                feed.applyDetails(details, at: min(details.fetchedAt ?? requestedAt, requestedAt))
                // The next one counts from the answer, so it is never the client's cached copy of this one.
                scheduler.recordAnswer(.details, at: clock())
            }
            answers += 1
            lastError = nil
        } catch is CancellationError {
            scheduler.recordCancelled(kind)
            return
        } catch {
            lastError = error
            let now = clock()
            scheduler.recordFailure(kind, error: error, at: now)
            if let live = error as? LiveError {
                switch live {
                case .rateLimited(_, let retryAfter): services.pause(now.addingTimeInterval(max(retryAfter ?? 20, 10)))
                case .circuitOpen(_, let until): services.pause(until)
                default: break
                }
            }
        }
        feed.tick(now: clock())
        publish(now: clock())
    }

    // MARK: Publishing

    private func updateMarker(now: Date) {
        let next = feed.marker(now: now)
        if next != marker { marker = next }
    }

    private func stepCamera(now: Date, dt: TimeInterval) {
        guard now >= holdCameraUntil, feed.session.mode != .free else { return }
        guard let input = feed.cameraInput(now: now, mode: feed.session.mode, reduceMotion: reduceMotion) else { return }
        let next = controller.step(input, dt: dt)
        // The glide comes closer to its target by ever smaller steps: a step of less than a hair is not handed to the map (it would
        // redraw the map 20 times a second for nothing while the train stands).
        if let camera, camera.isClose(to: next) {
            cameraSettled = true
            return
        }
        cameraSettled = false
        camera = next
    }

    /// The clock moved on or an answer came in: the HUD, the route lines, the marker.
    private func publish(now: Date) {
        updateMarker(now: now)
        let frame = feed.frame(now: now)
        var next = CockpitHUD()
        next.summary = frame?.summary
        next.state = feed.session.state
        next.mode = feed.session.mode
        next.offersReturn = feed.session.offersReturn
        next.clock = now
        next.isProvisional = frame?.isProvisional ?? true
        next.isStale = frame?.isStale ?? false
        // Straight lines only once the whole run is there: before it, with the radar's four stops, no line is drawn at all.
        next.isStraightLine = frame?.isProvisional == false && frame?.route?.isStraightLine == true
        next.isCancelled = frame?.isCancelled ?? false
        next.lowPower = lowPower
        switch feed.session.state {
        case .waiting: next.banner = .waiting
        case .lost:
            let since = (feed.session.lastPositionAt ?? feed.session.startedAt).distance(to: now)
            next.banner = .lost(CockpitText.lostDetail(reason: feed.session.lostReason(now: now) ?? .noAnswers, sinceSeconds: since))
        case .ended:
            // The stop the train reached: the end of its run, which is not the last stop of the list when the train turned short.
            var reached: String?
            if case .arrived(let stop)? = frame?.summary?.phase { reached = stop }
            next.banner = .ended(CockpitText.endedDetail(lastStop: reached, reachedLastStop: reached != nil))
        case .following, .free: next.banner = nil
        }
        if services.radar == nil && services.trip == nil {
            next.note = services.unavailable
        } else if let lastError, scheduler.failures(.position) > 0 || scheduler.failures(.details) > 0 {
            next.note = LiveMessage.text(for: lastError)
        }
        // Reduce Motion holds a fixed top-down view: said, so "Verfolgen" in the switcher is not a promise the camera does not keep.
        if reduceMotion, feed.session.mode == .follow, next.note == nil {
            next.note = "Bewegung reduzieren ist an: Die Kamera schaut fest von oben, Norden oben."
        }
        if next != hud { hud = next }
        updateLines(frame: frame)
    }

    private func updateLines(frame: CockpitFrame?) {
        guard let frame, let route = frame.route else { return }
        guard !frame.isProvisional, let km = frame.km else {
            // Only the radar's four stops: the flags of the next ones, no line.
            let stops = (frame.summary?.upcoming ?? []).map { flag in
                CockpitMapStop(id: flag.id, coordinate: route.stops[flag.id].coordinate.clCoordinate, isPassed: false, flag: flag)
            }
            if lines.stops.map(\.id) != stops.map(\.id) || !lines.ahead.isEmpty || !lines.passed.isEmpty { lines = CockpitMapLines(stops: stops) }
            return
        }
        // Rebuilt when the train has gone 120 m on, or when an answer changed the delays.
        if let last = linesKm, abs(km - last) < 0.12, linesVersion == answers { return }
        linesKm = km
        linesVersion = answers
        let split = route.lines(atKm: km)
        let flags = Dictionary(uniqueKeysWithValues: (frame.summary?.upcoming ?? []).map { ($0.id, $0) })
        lines = CockpitMapLines(
            passed: split.passed.map(\.clCoordinate),
            ahead: split.ahead.map { CockpitMapLine(id: $0.id, coordinates: $0.points.map(\.clCoordinate), state: $0.state) },
            stops: route.stops.filter(\.isServed).compactMap { stop -> CockpitMapStop? in
                // MapKit orders annotations itself (SwiftUI's Map has no z-index): the dot of a stop the train stands at, or is just
                // passing, would now and then be drawn over the train (CI screenshot radarCockpitEnded, run 43336170151). It is left out.
                if flags[stop.id] == nil, abs(stop.km - km) < Self.dotClearKm { return nil }
                return CockpitMapStop(id: stop.id, coordinate: stop.coordinate.clCoordinate, isPassed: stop.km < km - 0.05, flag: flags[stop.id])
            })
    }

    /// A stop dot closer to the train than this (along the route) is not drawn: the marker covers it.
    static let dotClearKm = 0.35
}

extension CockpitModel.Services {
    /// The live cockpit: the radar and the timetable through the gate (consent, switch, kill switch, connection), the radar's budget from the radar
    /// view below. Consent and the switches are decided once: they cannot change while the cockpit covers the app, and a kill switch that arrives
    /// with a new remote config reaches the client itself, which then sends nothing (`LiveError.disabled`). The connection is asked again before
    /// every request: opened offline, the cockpit asked nothing ever again, even once the connection was back (review 2).
    @MainActor static func live(_ app: AppState, budget: RadarModel?) -> Self {
        var services = CockpitModel.Services()
        if let reason = app.live.timetableUnavailable, reason != .offline {
            services.unavailable = Self.text(for: reason)
            return services
        }
        let live = app.live
        services.radar = { query in
            guard let radar = await live.radar else { throw await Self.closed(live) }
            return try await radar.radar(query)
        }
        services.trip = { tripID in
            guard let timetable = await live.timetable else { throw await Self.closed(live) }
            return try await timetable.trip(tripID, includePolyline: true)
        }
        if !app.live.isDemo, let budget {
            // Without the radar's model there is no budget to ask: wait (nil would mean "taken, send now").
            services.claim = { [weak budget] now in
                guard let budget else { return now.addingTimeInterval(1) }
                return budget.claimRequestSlot(now: now)
            }
            services.pause = { [weak budget] time in budget?.pauseRadar(until: time) }
        }
        return services
    }

    /// Why the gate is shut for this request: offline (backs off and comes back), else live data is off (`LiveError.disabled`: a long pause).
    @MainActor private static func closed(_ live: LiveDataService) -> LiveError {
        live.timetableUnavailable == .offline ? .offline : .disabled(.oebbHafas)
    }

    private static func text(for reason: LiveDataService.Unavailable) -> String {
        switch reason {
        case .consentUndecided, .declined, .switchedOff: "Live-Daten sind aus. Ohne sie bewegt sich der Zug nicht."
        case .killSwitch(let notice): notice ?? "Die Zugpositionen sind gerade abgeschaltet."
        case .offline: "Keine Verbindung zum Internet. Die Position wird nicht aktualisiert."
        }
    }
}

extension CockpitCamera {
    /// Within a hair of `other`: about 10 cm, a centimetre of distance, a hundredth of a degree. Nothing on screen moves for that.
    func isClose(to other: CockpitCamera) -> Bool {
        abs(center.latitude - other.center.latitude) < 1e-6 && abs(center.longitude - other.center.longitude) < 1e-6
            && abs(distance - other.distance) < 0.01 && abs(CockpitAngle.delta(from: heading, to: other.heading)) < 0.01
            && abs(pitch - other.pitch) < 0.01
    }

    var mapCamera: MapCamera {
        MapCamera(centerCoordinate: center.clCoordinate, distance: distance, heading: heading, pitch: pitch)
    }
}
