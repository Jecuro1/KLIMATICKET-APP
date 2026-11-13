import SwiftUI
import KlimaCore
#if canImport(Network)
import Network   // the Linux type-check harness has no stub of this module; Xcode always builds the real branch
#endif

// The Zeitreise of the Zug-Radar (docs/RADAR_TIMETRAVEL.md): a scrubber from half an hour back to three hours ahead shows where the trains
// are at that time. Positions are CALCULATED: from the timetable, the delays known now and the snapshots the server answered for other times
// (`RadarTimeline`, `RadarProjection`). Scrubbing and playing are local; the requests are a coarse timeline of snapshots when the Zeitreise
// starts and one more for the minute the scrubber rests at, all through the live radar's budget (24 a minute) - `RadarTimeScheduler`.
//
// This model owns the scrubber's state, the loop that drives it (one task, owned by the radar view: leaving the radar or the layer
// cancels everything) and the pins the map draws while away from now. The live radar loop pauses while away and resumes on the way back.

@MainActor
@Observable
final class RadarTimeModel {
    // MARK: State the views read

    /// The card is expanded (a chip otherwise).
    private(set) var isOpen = false
    /// The time the scrubber is at, nil at "Jetzt": the live radar is then the picture, nothing of this model runs.
    private(set) var target: Date?
    /// The time the map shows: it glides to `target` (markers move instead of jumping), at once under Reduce Motion and in screenshots.
    private(set) var shown: Date?
    private(set) var isPlaying = false
    var speed: RadarPlaybackSpeed = .x1
    /// Ticks with the loop (about once a second): "in 45 Min" and the age of the delays are derived from it.
    private(set) var clock = Date()
    private(set) var pins: [RadarPin] = []
    private(set) var clusters: [RadarCluster] = []
    private(set) var pinsByID: [String: RadarPin] = [:]
    /// The last ten minutes of the selected train's projected path.
    private(set) var trail: [GeoPoint] = []
    private(set) var progress = (loaded: 0, failed: 0, total: 0)
    private(set) var isLoading = false
    private(set) var isRefreshingExact = false
    private(set) var isIncomplete = false
    private(set) var profile: RadarTimeProfile = .fine
    /// Cellular, hotspot or Low Data Mode: the plan is coarse and a resting minute is fetched only on a tap.
    private(set) var isMetered = false
    /// How old the delays behind the picture were at `delayAgeAt`; `delayAge(at:)` carries it on.
    @ObservationIgnored private var delayReference: (age: TimeInterval, at: Date)?
    private(set) var sky = RadarDaylight.sample(at: Date())
    /// Some vehicle between two stops is placed on the straight line (always, except the selected train with its route).
    private(set) var hasStraightPins = false
    private(set) var failure: String?
    /// The time of a fetched snapshot within two and a half minutes of the chosen one (the card names it: only for this very minute is the
    /// picture the server's own).
    private(set) var snapshotHere: Date?
    /// Low Power Mode is on: nothing is requested (as in the live radar) until "Trotzdem laden".
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The step the user last moved the scrubber to (drag, VoiceOver): the selection haptic follows it, not the clock, so a resting scrubber
    /// does not tick when the clock passes a five-minute mark.
    private(set) var userStep = 0

    @ObservationIgnored private var timeline = RadarTimeline()
    @ObservationIgnored private var scheduler = RadarTimeScheduler()
    @ObservationIgnored private weak var live: RadarModel?
    @ObservationIgnored private var began = false
    @ObservationIgnored private var meteredChecked = false
    @ObservationIgnored private var userChoseFine = false
    /// Synthetic trains, no network: no budget to keep (the demo service is local).
    @ObservationIgnored var demo = false
    @ObservationIgnored private var demoFeatured: (line: String, near: GeoPoint)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var needsRebuild = false
    @ObservationIgnored private var lastRebuild = Date.distantPast
    @ObservationIgnored private var returning = false
    @ObservationIgnored private var playBase = Date()
    @ObservationIgnored private var playOffset: TimeInterval = 0
    @ObservationIgnored private var routeCache: (tripID: String, count: Int, route: RadarRoute?)?
    @ObservationIgnored private var lastError: Error?
    @ObservationIgnored private var loadsInLowPower = false
    @ObservationIgnored private var lastReplan = Date.distantPast

    // MARK: Derived

    var isAway: Bool { target != nil }
    var isActive: Bool { isOpen || isAway }

    /// The scrubber's place in seconds from now: continuous (the thumb), 0 at "Jetzt".
    var offset: TimeInterval {
        guard let target else { return 0 }
        return RadarTimeAxis.offset(of: target, now: clock)
    }

    /// The step the scrubber is on (-6 ... 36), for the selection haptic and VoiceOver.
    var step: Int { RadarTimeAxis.step(for: offset) }

    var clockText: String { target.map { RadarTimeText.clock($0, now: clock) } ?? "Jetzt" }
    var dayNote: String? { target.flatMap { RadarTimeText.dayNote(for: $0, now: clock) } }
    var offsetTitle: String { RadarTimeText.offsetTitle(RadarTimeAxis.snapped(offset)) }

    var spokenValue: String { RadarTimeText.spokenValue(target: target, now: clock, offset: offset) }

    /// Low Power Mode holds the requests back (the demo has none to hold).
    var isHeldByLowPower: Bool { lowPower && !loadsInLowPower && !demo }

    var banner: String { RadarTimeText.banner(for: offset) }

    /// "812 Züge · berechnet für 22:32".
    var pill: String { RadarTimeText.pill(count: pins.count, rail: true, clock: clockText) }

    var summary: String {
        "\(RadarSummary.line(count: pins.count, late: pins.filter { $0.delay == .late }.count, rail: true)), berechnet für \(clockText)"
    }

    /// How old the delays behind the picture are at `date` (the clock keeps running between two rebuilds).
    func delayAge(at date: Date) -> TimeInterval? {
        delayReference.map { $0.age + max(date.timeIntervalSince($0.at), 0) }
    }

    var volumeNote: String { RadarTimeText.volume(points: max(progress.total, 1)) }
    var loadingText: String { RadarTimeText.loading(loaded: progress.loaded, total: progress.total) }

    // MARK: The scrubber

    func open() { isOpen = true }
    func close() { isOpen = false }
    func toggleOpen() { isOpen.toggle() }

    /// The thumb was moved to `seconds` from now. It snaps to the five-minute grid; "Jetzt" (step 0) is the live radar.
    func scrub(to seconds: TimeInterval) {
        stopPlaying()
        returning = false
        let snapped = RadarTimeAxis.snapped(seconds)
        let step = RadarTimeAxis.step(for: snapped)
        if step != userStep { userStep = step }
        if snapped == 0 {
            backToNow()
            return
        }
        let newTarget = RadarTimeAxis.target(base: RadarTimeAxis.base(now: Date()), offset: snapped)
        if newTarget == target {   // a drag reports many positions on the same step
            scheduler.setMoving(true, now: Date())
            return
        }
        set(target: newTarget, moving: true)
    }

    /// The finger was lifted: the rest timer for the minute's own snapshot starts.
    func scrubEnded() {
        scheduler.setMoving(isPlaying, now: Date())
    }

    /// VoiceOver: one step forward or back.
    func nudge(steps: Int) {
        scrub(to: Double(step + steps) * RadarTimeAxis.stepSeconds)
        scrubEnded()
    }

    /// "Zurück zu Jetzt": the markers glide to now, then the live radar is the picture again.
    func backToNow() {
        stopPlaying()
        guard isAway else { return }
        if MotionPolicy.isStatic || MotionPolicy.prefersReducedMotion {
            leave()
        } else {
            returning = true
            set(target: RadarTimeAxis.base(now: Date()), moving: false)
        }
    }

    func togglePlay() {
        if isPlaying {
            stopPlaying()
            return
        }
        let start = RadarPlayback.startOffset(from: offset)
        playBase = RadarTimeAxis.base(now: Date())
        playOffset = start
        returning = false
        isPlaying = true
        set(target: playBase.addingTimeInterval(start), moving: true)
    }

    private func stopPlaying() {
        guard isPlaying else { return }
        isPlaying = false
        scheduler.setMoving(false, now: Date())
    }

    private func set(target newTarget: Date, moving: Bool) {
        let now = Date()
        if target == nil { shown = RadarTimeAxis.base(now: now) }   // the markers start at now and glide to the chosen time
        target = newTarget
        scheduler.setMoving(moving, now: now)
        scheduler.setTarget(newTarget, now: now)
        needsRebuild = true
        if MotionPolicy.isStatic || MotionPolicy.prefersReducedMotion { shown = newTarget }
    }

    /// Back at the live radar: nothing of the Zeitreise runs any more, the snapshots stay for a quick return.
    private func leave() {
        target = nil
        shown = nil
        returning = false
        isPlaying = false
        began = false
        scheduler.end()
        pins = []
        clusters = []
        pinsByID = [:]
        trail = []
        snapshotHere = nil
    }

    /// The radar was closed, the train layer went off, another mode came on: everything of the Zeitreise ends.
    func reset() {
        generation += 1
        isOpen = false
        leave()
        timeline = RadarTimeline()
        scheduler = RadarTimeScheduler()
        progress = (0, 0, 0)
        isLoading = false
        isRefreshingExact = false
        isIncomplete = false
        failure = nil
        loadsInLowPower = false
    }

    /// "Trotzdem laden" in Low Power Mode: the plan is loaded after all, until the radar closes or the train layer goes off.
    func loadDespiteLowPower() {
        loadsInLowPower = true
    }

    /// A metered connection: "Fein laden" fetches the plan every 20 minutes and the resting minutes by themselves after all.
    func useFine() {
        userChoseFine = true
        profile = .fine
        scheduler.allowsAutoExact = true
        if isAway, let live { scheduler.begin(now: Date(), profile: .fine, includeNow: !live.holdsAllOfAustria) }
        needsRebuild = true
    }

    /// "Für diese Zeit genau laden": a snapshot for exactly the minute shown, where none is fetched by itself.
    func refreshExactNow() {
        guard let target else { return }
        scheduler.requestExact(for: target)
    }

    // MARK: Things that change under the picture

    func viewChanged() { needsRebuild = true }
    func filterChanged() { needsRebuild = true }
    func selectionChanged() { needsRebuild = true }

    /// The trip details of the selected train arrived (the trip sheet loaded them): its whole stop list and its route make its path exact.
    func noteDetails(tripID: String) {
        if isAway { addCachedDetails(tripID) }
        needsRebuild = true
    }

    /// The whole stop list of a trip from the trip sheet's cache (five minutes), into the timeline. Also when a Zeitreise starts with a train
    /// already selected: its sheet loaded the details before.
    private func addCachedDetails(_ tripID: String) {
        guard let details = RadarRouteCache.shared.value(for: tripID), details.stopovers.count > 1,
              let vehicle = timeline.vehicle(tripID) else { return }
        let full = RadarVehicle(tripID: tripID, line: vehicle.line, direction: vehicle.direction, coordinate: vehicle.coordinate,
                                stopovers: details.stopovers, isCancelled: details.isCancelled)
        timeline.addDetails(full, fetchedAt: Date())
    }

    // MARK: Demo

    /// The CI scenes: the scrubber open at `minutes` from now, optionally playing. Demo data only.
    func applyDemo(minutes: Double, playing: Bool, featured: (line: String, near: GeoPoint)? = nil) {
        demo = true
        demoFeatured = featured
        isOpen = true
        let base = RadarTimeAxis.base(now: Date())
        playBase = base
        playOffset = minutes * 60
        isPlaying = playing
        target = base.addingTimeInterval(minutes * 60)
        shown = target
        needsRebuild = true
    }

    // MARK: The loop

    /// Runs while the Zeitreise is active and the radar is visible. One task: it moves the time, glides the markers, sends the snapshot requests
    /// the scheduler names (never waiting for an answer) and rebuilds the pins as often as a move can be seen. Cancelling it cancels every
    /// request on its way; each gives its snapshot back to the scheduler.
    func run(service: any RadarService, live: RadarModel) async {
        self.live = live
        var last = Date()
        await withTaskGroup(of: Void.self) { group in
            while !Task.isCancelled {
                let now = Date()
                let elapsed = min(now.timeIntervalSince(last), 0.5)
                last = now
                if now.timeIntervalSince(clock) >= 1 { clock = now }
                if isAway, !began { await start(live: live) }
                let saving = ProcessInfo.processInfo.isLowPowerModeEnabled
                if saving != lowPower { lowPower = saving }
                if isAway {
                    advance(elapsed: elapsed, now: now)
                    if now.timeIntervalSince(lastReplan) >= 60 { replan(now: now) }
                    // Low Power Mode: no request (the live radar pauses the same way); the picture is calculated from what is loaded.
                    if !isHeldByLowPower {
                        switch scheduler.next(now: now, claim: claim(live)) {
                        case .request(let request):
                            group.addTask { await self.fetch(request, service) }
                        case .wait, .idle:
                            break
                        }
                    }
                    updateProgress(now: now)
                }
                if isAway, needsRebuild || now.timeIntervalSince(lastRebuild) >= 2 {
                    rebuild(now: now)
                }
                let moving = isAway && (isPlaying || isGliding)
                try? await Task.sleep(for: .milliseconds(moving ? 80 : 250))
            }
        }
    }

    /// The shown time has not reached the target yet: the markers are still moving.
    private var isGliding: Bool {
        guard let shown, let target else { return false }
        return abs(target.timeIntervalSince(shown)) > 0.001
    }

    private func claim(_ live: RadarModel) -> (Date) -> Date? {
        if demo { return { _ in nil } }   // no network in the demo: nothing to budget
        return { [weak live] now in live?.claimRequestSlot(now: now) }
    }

    /// The Zeitreise starts: the live radar's vehicles are the first snapshot, the plan is made, a metered connection is asked once.
    private func start(live: RadarModel) async {
        began = true
        if !meteredChecked {
            meteredChecked = true
            isMetered = demo ? false : await RadarMeteredPath.isMetered()
        }
        guard isAway else { began = false; return }
        let now = Date()
        let coarse = isMetered && !userChoseFine
        profile = coarse ? .coarse : .fine
        scheduler.allowsAutoExact = !coarse
        timeline.addLive(live.knownEntries(at: now))
        // What the scrubber can reach stays: half an hour back. The snapshots of an earlier Zeitreise still count as fetched for ten
        // minutes, so pruning at "now" would leave the last half hour without its trains.
        timeline.prune(forRangeAt: now)
        if let selected = live.selectedTripID { addCachedDetails(selected) }
        scheduler.begin(now: now, profile: profile, includeNow: !live.holdsAllOfAustria)
        lastReplan = now
        if let target { scheduler.setTarget(target, now: now) }
        if isPlaying { scheduler.setMoving(true, now: now) }
        needsRebuild = true
    }

    /// A long Zeitreise: the range moves on with the clock. The plan gets the points that came into it (one every 20 minutes), and what left
    /// it on the left is dropped from the timeline. Once a minute.
    private func replan(now: Date) {
        lastReplan = now
        scheduler.extendPlan(now: now)
        timeline.prune(forRangeAt: now)
    }

    /// Moves the time: the time-lapse advances the target; the shown time glides after it; on the way back to now the live radar takes over.
    private func advance(elapsed: TimeInterval, now: Date) {
        if isPlaying {
            let step = RadarPlayback.advance(offset: playOffset, elapsed: elapsed, speed: speed)
            playOffset = step.offset
            let newTarget = playBase.addingTimeInterval(playOffset)
            target = newTarget
            scheduler.setTarget(newTarget, now: now)
            if step.reachedEnd { stopPlaying() }
        } else if let current = target, current < now.addingTimeInterval(RadarTimeAxis.minOffset), !returning {
            // The clock moved on past the far left of the scrubber: the target stays on its end.
            let clamped = RadarTimeAxis.base(now: now).addingTimeInterval(RadarTimeAxis.minOffset)
            target = clamped
            scheduler.setTarget(clamped, now: now)
        }
        guard let target else { return }
        if MotionPolicy.isStatic || MotionPolicy.prefersReducedMotion {
            if shown != target { shown = target; needsRebuild = true }
        } else if let current = shown, abs(target.timeIntervalSince(current)) > 0.001 {
            let remaining = target.timeIntervalSince(current)
            let advance = RadarTimeGlide.step(shown: 0, target: remaining, elapsed: elapsed)
            shown = abs(remaining - advance) < 0.001 ? target : current.addingTimeInterval(advance)
            needsRebuild = true
        }
        if returning, let shown, abs(shown.timeIntervalSince(target)) < 1 { leave() }
    }

    private func updateProgress(now: Date) {
        let newProgress = scheduler.progress
        if newProgress.loaded != progress.loaded || newProgress.failed != progress.failed || newProgress.total != progress.total {
            progress = (newProgress.loaded, newProgress.failed, newProgress.total)
        }
        let loading = scheduler.isLoading
        if loading != isLoading { isLoading = loading }
        let refreshing = scheduler.isRefreshingExact
        if refreshing != isRefreshingExact { isRefreshingExact = refreshing }
        let incomplete = scheduler.isIncomplete
        if incomplete != isIncomplete { isIncomplete = incomplete }
        if let target {
            let here = scheduler.snapshotTime(near: target, now: now)
            if here != snapshotHere { snapshotHere = here }
        }
        let message: String? = scheduler.progress.failed > 0 && !scheduler.isLoading
            ? RadarTimeText.missing(scheduler.progress.failed)
            : (scheduler.pausedUntil.map { $0 > now } == true ? lastError.map(LiveMessage.text(for:)) : nil)
        if message != failure { failure = message }
    }

    private func fetch(_ request: RadarTimeRequest, _ service: any RadarService) async {
        let asked = generation
        do {
            let snapshot = try await service.radar(RadarQuery(box: request.box, when: request.time, products: .rail, maxVehicles: RadarTiling.requestCap))
            guard asked == generation else { return }
            let now = Date()
            scheduler.recordAnswer(request, answeredCount: snapshot.answeredCount, now: now)
            timeline.addFrame(snapshot.vehicles, time: request.time, fetchedAt: now,
                              isComplete: RadarTimeScheduler.isComplete(request, answeredCount: snapshot.answeredCount))
            lastError = nil
        } catch is CancellationError {
            guard asked == generation else { return }
            scheduler.recordCancelled(request)
        } catch {
            guard asked == generation else { return }
            lastError = error
            scheduler.recordFailure(request, error: error, now: Date())
            if let until = scheduler.pausedUntil, until > Date(), !demo { live?.pauseRadar(until: until) }
        }
        needsRebuild = true
    }

    // MARK: The pins

    /// The route of the selected train, when the trip sheet loaded one (JourneyDetails): the projection runs along it.
    private func selectedRoute(_ live: RadarModel) -> [String: RadarRoute] {
        guard let id = live.selectedTripID, live.routeTripID == id, live.route.count > 1 else { return [:] }
        if routeCache?.tripID != id || routeCache?.count != live.route.count {
            routeCache = (id, live.route.count, RadarRoute(live.route))
        }
        return routeCache?.route.map { [id: $0] } ?? [:]
    }

    private func rebuild(now: Date) {
        needsRebuild = false
        lastRebuild = now
        guard let live, let shown else { return }
        let routes = selectedRoute(live)
        let box = live.box
        let mask = live.products
        let filter = live.filter
        var built: [RadarPin] = []
        var straight = false
        for pin in timeline.pins(at: shown, routes: routes) {
            guard box.contains(pin.coordinate), filter.matches(pin) else { continue }
            if let line = pin.vehicle.line, line.productClass != 0, line.productClass & mask.rawValue == 0 { continue }
            if pin.path == .straight { straight = true }
            built.append(RadarPin(vehicle: pin.vehicle, coordinate: pin.coordinate, isEstimate: pin.isCalculated, delay: pin.delayState,
                                  delaySeconds: pin.delaySeconds, bearing: pin.bearing))
        }
        pins = built
        pinsByID = Dictionary(built.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The selected train stays a marker of its own, so its trail ends at it and not in a bubble.
        let cell = RadarClustering.cellSize(latitudeSpan: live.spanDegrees, longitudeSpan: box.east - box.west,
                                            widthPoints: Double(live.mapSize.width), heightPoints: Double(live.mapSize.height))
        let selectedID = live.selectedTripID
        func point(_ pin: RadarPin) -> RadarPoint { RadarPoint(tripID: pin.id, coordinate: pin.coordinate, delay: pin.delay) }
        var groups = RadarClustering.group(built.filter { $0.id != selectedID }.map(point), cellDegrees: cell)
        if let selectedID, let pin = pinsByID[selectedID] {
            groups += RadarClustering.group([point(pin)], cellDegrees: cell)
        }
        clusters = groups
        if straight != hasStraightPins { hasStraightPins = straight }
        // The CI scene keeps one train selected so the trail shows (the same tap a user does): the one of this line nearest to a point, so the
        // selection follows the time-lapse and stays in the picture.
        if let featured = demoFeatured, !built.isEmpty {
            let candidates = built.filter { $0.vehicle.line?.name == featured.line }
            if let pin = candidates.min(by: { $0.coordinate.distanceKm(to: featured.near) < $1.coordinate.distanceKm(to: featured.near) }),
               live.selectedTripID != pin.id {
                live.selectedTripID = pin.id
            }
        }
        trail = live.selectedTripID.map { timeline.trail(for: $0, endingAt: shown, route: routes[$0]) } ?? []
        delayReference = timeline.delayDataAge(at: shown, now: now).map { ($0, now) }
        let light = RadarDaylight.sample(at: shown)
        if light != sky { sky = light }
    }
}

// MARK: - Metered connection

/// Is the connection metered: cellular, a hotspot, or Low Data Mode? Asked once when a Zeitreise starts. A Zeitreise loads up to 20 MB
/// (unpacked, docs/RADAR_TIMETRAVEL.md §R12), so a metered connection gets the coarse plan and no snapshot for a resting minute by itself.
enum RadarMeteredPath {
    #if canImport(Network)
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func take() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    static func isMetered() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "klimabilanz.radartime.path", qos: .utility)
            let once = Once()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                if once.take() { continuation.resume(returning: path.isExpensive || path.isConstrained) }
            }
            monitor.start(queue: queue)
            // No answer in half a second: not metered (the plan is then the fine one, the volume is stated in the card). This runs in any
            // case and lets go of the handler, which holds the monitor (and the monitor the handler).
            queue.asyncAfter(deadline: .now() + 0.5) {
                monitor.cancel()
                monitor.pathUpdateHandler = nil
                if once.take() { continuation.resume(returning: false) }
            }
        }
    }
    #else
    static func isMetered() async -> Bool { false }
    #endif
}
