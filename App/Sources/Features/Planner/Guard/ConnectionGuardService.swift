import Foundation
import UIKit
import KlimaCore

// MARK: anschluss – the Anschluss-Wächter (docs/CONNECTION_GUARD.md). „Erwische ich meinen Anschluss?“ while the user rides:
// registered on „Live verfolgen“ of a connection with a change, it re-checks the connection with one Reconstruction every
// 120 s (60 s when worse than „Sicher“), merges the follow's fresher JourneyDetails of the feeder, and says „Sicher“, „Wird
// knapper“, „Wackelt“, „Wahrscheinlich verpasst“, „Verpasst“, „Fällt aus“, „Nach Fahrplan“ or „Umstieg vorbei“. Foreground
// only: nothing is asked while the app is in the background, in Low Power Mode (only „Jetzt prüfen“), without live data or
// with „Wächter aus“. Every request goes through `HafasClient` (the app's throttle, 40 a minute) – never the radar budget.
// The decisions live in KlimaCore (`GuardEngine`, `GuardPlan`); this type adds the clock, the network and the observation.

@MainActor
@Observable
final class ConnectionGuardService {
    static let shared = ConnectionGuardService()

    /// The network, injectable (demo and screenshot scenes script it; nothing else may reach the network).
    struct Services {
        /// Reconstruction of the followed connection (`includeStopovers: false`, no polyline); nil without live data.
        var refresh: ((String) async throws -> Journey)?
        /// JourneyDetails of the connecting trip (fallback after two failed Reconstructions).
        var trip: ((String) async throws -> TripDetails)?
        /// TripSearch for the alternatives.
        var journeys: ((JourneyQuery) async throws -> JourneyPage)?
        /// Why nothing can be asked (consent, switch, kill switch, Offline-Modus, offline).
        var unavailable: LiveDataService.Unavailable?

        static let none = Services(unavailable: .switchedOff)

        /// The live timetable, read at the moment of each request (the consent gate decides every time).
        @MainActor static func live(_ live: LiveDataService) -> Services {
            if live.isDemo { return Services(refresh: nil, trip: nil, journeys: nil, unavailable: nil) }
            guard live.timetable != nil else { return Services(unavailable: live.timetableUnavailable ?? .offline) }
            return Services(
                refresh: { [weak live] token in
                    guard let service = await live?.timetable else { throw LiveError.disabled(.oebbHafas) }
                    return try await service.refresh(token, includeStopovers: false, includePolyline: false)
                },
                trip: { [weak live] id in
                    guard let service = await live?.timetable else { throw LiveError.disabled(.oebbHafas) }
                    return try await service.trip(id, includePolyline: false)
                },
                journeys: { [weak live] query in
                    guard let service = await live?.timetable else { throw LiveError.disabled(.oebbHafas) }
                    return try await service.journeys(query)
                },
                unavailable: nil)
        }
    }

    /// The alternatives sheet's content.
    enum Alternatives: Equatable {
        case idle
        case loading(JourneyQuery)
        case loaded([Journey], query: JourneyQuery)
        case failed(String, query: JourneyQuery?)
    }

    // MARK: What the views read

    private(set) var engine: GuardEngine?
    /// When the loop asks next (nil while it does not ask on its own).
    private(set) var nextCheckAt: Date?
    private(set) var alternatives: Alternatives = .idle
    /// The state just entered „Wahrscheinlich verpasst“, „Verpasst“ or „Fällt aus“: the card opens the alternatives once.
    private(set) var wantsAlternatives = false
    /// Bumps when the state turns to „Wackelt“ (the card's single pulse).
    private(set) var shakyPulse = 0
    /// A short line under „Jetzt prüfen“ („Gerade geprüft · wieder in 12 s“).
    private(set) var manualNote: String?
    /// Set by `isActive` notifications; the loop runs only while true.
    private(set) var appActive: Bool

    var assessment: GuardAssessment? { engine?.assessment }

    /// The guard of this follow, if any.
    func watches(tripID: String) -> Bool { engine?.record.followTripID == tripID }

    // MARK: Inside

    @ObservationIgnored var clock: () -> Date = { Date() }
    @ObservationIgnored private var servicesProvider: () -> Services = { .none }
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var returnedToForeground = false
    @ObservationIgnored private var pendingAutoSearch = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Screenshot scenes: no loop, no toast, the status as scripted.
    @ObservationIgnored private(set) var isScripted = false
    @ObservationIgnored private var scriptedStatus: GuardStatus?

    private init() {
        appActive = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resignedActive() }
        })
    }

    /// Toasts go through the app state (the views attach it; `PlannerIntentHost.app` otherwise).
    func attach(app: AppState) { self.app = app }

    // MARK: Register, restore, end

    /// „Live verfolgen“ of a connection with a change (ConnectionDetailView): the guard watches the change after the first ride.
    /// Needs two ride legs, a Reconstruction handle and the follow of the first ride; otherwise nothing happens.
    func register(journey: Journey, followTripID: String, feederRide: Int = 0, products: ProductMask, klimaTicketOnly: Bool,
                  live: LiveDataService) {
        let now = clock()
        guard ConnectionGuard.canWatch(journey, followTripID: followTripID, feederRide: feederRide),
              LiveFollowTracker.shared.target?.tripID == followTripID else { return }
        let record = GuardRecord(followTripID: followTripID, journey: journey, journeyAt: now, feederRide: feederRide,
                                 products: products, klimaTicketOnly: klimaTicketOnly, createdAt: now)
        if live.isDemo {
            let demoJourney = journey
            install(record, services: { GuardDemo.liveDemoServices(journey: demoJourney) })
        } else {
            install(record, services: { [weak live] in live.map(Services.live) ?? .none })
        }
        GuardRecordStore.save(record)
        startLoopIfActive()
    }

    /// The follow restored after a relaunch or in a background refresh: the record comes back, nothing is asked here. The loop
    /// starts only when the app is active (a background refresh never asks the guard's questions).
    func restore(followTripID: String, live: LiveDataService) {
        guard engine?.record.followTripID != followTripID else { return }
        guard let record = GuardRecordStore.load() else { return }
        guard record.followTripID == followTripID, !record.isExpired(now: clock()) else {
            GuardRecordStore.save(nil)
            return
        }
        install(record, services: { [weak live] in live.map(Services.live) ?? .none })
        if engine?.hasEnded(now: clock()) ?? true {
            finish()
            return
        }
        startLoopIfActive()
    }

    /// A follow (re)started: the guard stays only for the same trip with a change at the same station.
    func followChanged(to target: LiveFollowTarget) {
        guard let record = engine?.record, !record.belongs(to: target) else { return }
        drop()
    }

    /// The follow stopped: the guard and its record go.
    func followEnded() {
        drop()
    }

    /// The follow's JourneyDetails answer of the feeder (no request; recomputes; silent in the background).
    func followUpdated(target: LiveFollowTarget, snapshot: LiveFollowSnapshot, at: Date) {
        // Scripted scenes keep their numbers (the demo run's clock drifts with every answer).
        guard var current = engine, current.record.followTripID == target.tripID, !isScripted else { return }
        let change = current.followUpdated(snapshot, at: at, now: clock())
        engine = current
        handle(change)
    }

    // MARK: Card actions

    /// „Jetzt prüfen“: at most every 20 s, also in Low Power Mode.
    func checkNow() {
        guard let current = engine else { return }
        let now = clock()
        switch current.manualDecision(conditions: conditions(now: now), now: now) {
        case .ask(let kind):
            manualNote = nil
            Task { await perform(kind, manual: true) }
        case .tooSoon(let seconds):
            manualNote = GuardText.checkTooSoon(seconds)
        case .unavailable:
            manualNote = nil
        }
    }

    /// „Wächter aus“ / „Wächter an“ for this follow.
    func setSwitchedOff(_ off: Bool) {
        guard var current = engine else { return }
        current.setSwitchedOff(off)
        engine = current
        if !isScripted { GuardRecordStore.save(current.record) }
        if !off {
            returnedToForeground = true
            startLoopIfActive()
        }
    }

    /// „Alternativen ansehen“ (or the automatic search): one TripSearch, at most one per three minutes per guard.
    func searchAlternatives() {
        guard var current = engine else { return }
        let now = clock()
        guard let query = current.alternativesQuery(now: now) else { return }   // the last result is kept for three minutes
        let services = servicesProvider()
        guard let journeys = services.journeys else {
            alternatives = .failed(services.unavailable == .offline ? "Ohne Internet keine Suche." : "Für die Suche braucht es Live-Daten.",
                                   query: query)
            return
        }
        current.alternativesSearched(at: now)
        engine = current
        alternatives = .loading(query)
        let mine = generation
        let originalArrival = current.record.journey.arrival?.planned
        Task {
            do {
                let page = try await journeys(query)
                guard mine == self.generation else { return }
                self.alternatives = .loaded(GuardAlternatives.pick(page.journeys, after: query.date, originalArrival: originalArrival),
                                            query: query)
            } catch {
                guard mine == self.generation else { return }
                self.alternatives = .failed(GuardText.alternativesFailed, query: query)
            }
        }
    }

    /// „REX 41 weiter verfolgen“ after „Umstieg vorbei“: the connecting ride becomes the follow; a change after it gets a guard.
    func continueFollow(live: LiveDataService) -> LiveFollowTarget? {
        guard let current = engine, let next = current.continuation else { return nil }
        let record = current.record
        LiveFollowTracker.shared.start(next.target, live: live)
        if let ride = next.nextFeederRide {
            register(journey: record.journey, followTripID: next.target.tripID, feederRide: ride, products: record.products,
                     klimaTicketOnly: record.klimaTicketOnly, live: live)
        }
        return next.target
    }

    /// The card showed the automatic alternatives.
    func alternativesShown() { wantsAlternatives = false }

    /// The card's status line.
    func status(now: Date) -> GuardStatus? {
        if let scriptedStatus { return scriptedStatus }
        guard let current = engine else { return nil }
        let last = current.requests.lastAnswerAt
        if current.hasEnded(now: now) { return .ended(lastAt: last) }
        if current.record.switchedOff { return .switchedOff }
        if current.requests.inFlight { return .checking(lastAt: last) }
        if let reason = servicesProvider().unavailable {
            return reason == .offline ? .offline(lastAt: last) : .liveOff
        }
        if current.requests.consecutiveFailures > 0 { return .failed(lastAt: last, retry: appActive ? nextCheckAt : nil) }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return .lowPower(lastAt: last) }
        if let window = current.window, now < window.start { return .beforeWindow(lastAt: last, start: window.start) }
        guard let last else { return .checking(lastAt: nil) }
        return .updated(at: last, next: appActive ? nextCheckAt : nil)
    }

    // MARK: The loop

    private func becameActive() {
        appActive = true
        returnedToForeground = true
        startLoopIfActive()
        if pendingAutoSearch {
            pendingAutoSearch = false
            searchAlternatives()
        }
    }

    private func resignedActive() {
        appActive = false
        loop?.cancel()
        loop = nil
        nextCheckAt = nil
    }

    private func startLoopIfActive() {
        guard loop == nil, appActive, engine != nil, !isScripted else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled, var current = engine {
            let now = clock()
            let change = current.reassess(now: now)
            engine = current
            handle(change)
            if current.hasEnded(now: now) {
                finish()
                return
            }
            let returned = returnedToForeground
            returnedToForeground = false
            switch current.decision(conditions: conditions(now: now), returnedToForeground: returned, now: now) {
            case .ask(let kind):
                await perform(kind, manual: false)
                continue
            case .wait(let due):
                nextCheckAt = due
                await sleep(until: due, now: now)
            case .idle(.beforeWindow(let start)):
                nextCheckAt = start
                await sleep(until: start, now: now)
            case .idle:
                nextCheckAt = nil
                await sleep(until: now.addingTimeInterval(15), now: now)
            }
        }
    }

    /// Sleeps until `date`, but at most 15 s: time moves the state too („Verpasst“ at the departure, „Umstieg vorbei“).
    private func sleep(until date: Date, now: Date) async {
        let seconds = min(max(date.timeIntervalSince(now), 1), 15)
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func conditions(now: Date) -> GuardConditions {
        GuardConditions(followsFeeder: engine.map { LiveFollowTracker.shared.target?.tripID == $0.record.followTripID } ?? false,
                        appActive: appActive, liveAvailable: servicesProvider().unavailable == nil,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, switchedOff: engine?.record.switchedOff ?? false)
    }

    /// One request. The answer counts only for the guard that asked (a guard replaced meanwhile drops it).
    private func perform(_ kind: GuardRequestKind, manual: Bool) async {
        guard var current = engine else { return }
        let services = servicesProvider()
        let mine = generation
        let sentAt = clock()
        current.begin()
        engine = current
        nextCheckAt = nil
        do {
            switch kind {
            case .reconstruction:
                guard let refresh = services.refresh, let token = current.record.journey.refreshToken else {
                    throw LiveError.disabled(.oebbHafas)
                }
                let journey = try await refresh(token)
                guard mine == generation, var latest = engine else { return }
                let change = latest.applyReconstruction(journey, sentAt: sentAt, manual: manual, now: clock())
                engine = latest
                GuardRecordStore.save(latest.record)
                handle(change)
            case .connectionTrip:
                guard let trip = services.trip, let id = current.connectionTripID else { throw LiveError.disabled(.oebbHafas) }
                let details = try await trip(id)
                guard mine == generation, var latest = engine else { return }
                let change = latest.applyConnectionTrip(details, sentAt: sentAt, manual: manual, now: clock())
                engine = latest
                handle(change)
            }
            pushTransferEstimate()
        } catch {
            guard mine == generation, var latest = engine else { return }
            if error is CancellationError {
                latest.abandon()
            } else {
                latest.applyFailure(kind: kind, countsForFallback: Self.countsForFallback(error), sentAt: sentAt, manual: manual)
            }
            engine = latest
        }
    }

    /// The Auskunft's own failures count towards the fallback; offline, live data off, throttle and timeouts do not.
    static func countsForFallback(_ error: Error) -> Bool {
        guard let live = error as? LiveError else { return false }
        switch live {
        case .hafas, .decoding, .noConnection, .http: return true
        case .disabled, .offline, .timeout, .network, .blocked, .rateLimited, .circuitOpen, .sessionExpired, .noPrice: return false
        }
    }

    /// The follow's „Anschluss knapp“ notice counts with the same expected departure and walk (§4.6).
    private func pushTransferEstimate() {
        guard let current = engine, let estimate = current.transferEstimate,
              LiveFollowTracker.shared.target?.tripID == current.record.followTripID else { return }
        LiveFollowTracker.shared.updateTransferEstimate(expectedDeparture: estimate.expectedDeparture, observedAt: estimate.observedAt,
                                                        walkMinutes: estimate.walkMinutes)
    }

    /// Toast and haptic once per worsening (foreground only), the automatic alternatives, the end.
    private func handle(_ change: GuardChange) {
        guard let current = engine else { return }
        if change.current == .shaky, change.previous != .shaky, change.previous != nil { shakyPulse += 1 }
        if change.searchAlternatives {
            wantsAlternatives = true
            if appActive, !isScripted { searchAlternatives() } else if !isScripted { pendingAutoSearch = true }
        }
        if let state = change.current, !state.searchesAlternatives { wantsAlternatives = false }
        if change.worsened, appActive, !isScripted, !LaunchMode.isSandboxed, let a = current.assessment { toast(a) }
        if current.hasEnded(now: clock()), !isScripted { finish() }
    }

    private func toast(_ a: GuardAssessment) {
        guard let app = app ?? PlannerIntentHost.app, let title = GuardText.toast(a) else { return }
        let subtitle = GuardText.headline(a).full
        if a.state.searchesAlternatives {
            app.showToast("arrow.triangle.swap", title, subtitle, actionTitle: "Alternativen", haptic: .warning) {
                LiveFollowTracker.shared.requestDetail()
            }
        } else {
            app.showToast("arrow.triangle.swap", title, subtitle, actionTitle: "Ansehen", haptic: .warning) {
                LiveFollowTracker.shared.requestDetail()
            }
        }
    }

    // MARK: Lifecycle of one guard

    private func install(_ record: GuardRecord, services: @escaping () -> Services) {
        loop?.cancel()
        loop = nil
        generation += 1
        servicesProvider = services
        var fresh = GuardEngine(record: record)
        _ = fresh.reassess(now: clock())
        engine = fresh
        alternatives = .idle
        wantsAlternatives = false
        pendingAutoSearch = false
        manualNote = nil
        nextCheckAt = nil
        isScripted = false
        scriptedStatus = nil
    }

    /// The guard is over („Umstieg vorbei“ or the window has passed): no more requests, the record goes; the card keeps the
    /// last state until the follow stops.
    private func finish() {
        loop?.cancel()
        loop = nil
        nextCheckAt = nil
        GuardRecordStore.save(nil)
    }

    private func drop() {
        loop?.cancel()
        loop = nil
        generation += 1
        engine = nil
        alternatives = .idle
        wantsAlternatives = false
        pendingAutoSearch = false
        manualNote = nil
        nextCheckAt = nil
        isScripted = false
        scriptedStatus = nil
        GuardRecordStore.save(nil)
    }

    // MARK: Screenshot scenes (GuardDemo)

    /// Installs a scripted guard: answers applied at their times, no loop, no file, no toast.
    func installScripted(record: GuardRecord, answers: [(journey: Journey, at: Date)], status: GuardStatus?, services: Services,
                         alternatives: Alternatives = .idle, searchedAt: Date? = nil) {
        drop()
        servicesProvider = { services }
        var scripted = GuardEngine(record: record)
        _ = scripted.reassess(now: record.journeyAt)
        for answer in answers {
            scripted.begin()
            _ = scripted.applyReconstruction(answer.journey, sentAt: answer.at, now: answer.at)
        }
        _ = scripted.reassess(now: clock())
        if let searchedAt { scripted.alternativesSearched(at: searchedAt) }
        engine = scripted
        isScripted = true
        scriptedStatus = status
        self.alternatives = alternatives
        wantsAlternatives = false
    }

    /// Screenshot scenes: the card opens the alternatives as in the real flow.
    func requestScriptedAlternatives() { wantsAlternatives = true }
}

// MARK: anschluss – the planner's search settings at registration (the alternatives are searched with them)
extension PlannerModel {
    var guardProducts: ProductMask { options.effectiveProducts(klimaTicketOnly: isKlimaTicketOnly) }

    /// „Im Fahrplan öffnen“ of an alternative: the Fahrplan from the live places, at that time.
    func openGuardSearch(from: Location, to: Location, at: Date?) {
        mode = .connections
        path = []
        origin = .live(from)
        destination = .live(to)
        vias = []
        when = at
        isArrival = false
        startSearch()
    }
}
