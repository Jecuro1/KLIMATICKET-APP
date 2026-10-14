import Foundation
import KlimaCore

// Live verfolgen (docs/OEBB_LIVE.md §R3, §R8). Owns the one active follow. While the app runs it polls `JourneyDetails`
// for the trip; a background refresh (Services/Live/FollowBackgroundRefresh.swift) does the same for the saved follow when
// iOS grants one. Every answer goes through the same steps:
//   1. the pure state machine (KlimaCore) derives the snapshot, the stage and the candidate notices;
//   2. the ledger drops notices that were delivered before; the switches and quiet hours decide what is shown;
//   3. the Live Activity is started or updated; the record is saved for the next launch or refresh.
// Nothing is requested unless the user switched Live-Mitteilungen on (notices, Live Activity, background refresh) and
// granted live data (the fetch itself is gated by LiveDataService, as before).

/// Owns the one active follow.
@MainActor
@Observable
final class LiveFollowTracker {
    static let shared = LiveFollowTracker()

    enum Status: Equatable {
        case following
        /// The last answer failed; the last known state stays on screen.
        case paused(String)
        /// Arrived or cancelled: polling stops, the card stays until dismissed.
        case finished
    }

    private(set) var target: LiveFollowTarget?
    private(set) var snapshot: LiveFollowSnapshot?
    private(set) var status: Status = .following
    private(set) var updatedAt: Date?
    private(set) var lastNotice: LiveFollowNotice?
    /// Counts up when a notification asks for the details: the card opens its stop list.
    private(set) var detailRequest = 0

    /// The stage of the last answer.
    var stage: FollowStage? { snapshot?.stage }
    /// A Live Activity of this follow is running.
    var hasLiveActivity: Bool { activityID != nil }

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var fetch: ((String) async throws -> TripDetails)?
    @ObservationIgnored private var ledger = FollowNoticeLedger()
    @ObservationIgnored private var activityID: String?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var isDemoRun = false

    /// A follow older than this without an arrival time is dropped on restore.
    private static let maxRestoreAge: TimeInterval = 6 * 60 * 60

    // MARK: Start and stop

    /// Starts following `target`, replacing any previous follow (its Live Activity ends).
    func start(_ target: LiveFollowTarget, live: LiveDataService) {
        loop?.cancel()
        endActivityNow()
        self.target = target
        snapshot = nil
        lastNotice = nil
        updatedAt = nil
        status = .following
        ledger = FollowNoticeLedger()
        startedAt = Date()
        isDemoRun = live.isDemo
        fetch = makeFetch(live)
        WidgetCacheSync.liveFollowDidChange(active: true)   // MARK: widgets – the Live-verfolgen control
        // Screenshot and perf runs must not show the system permission prompt over the scene. The prompt only appears
        // when the user has switched Live-Mitteilungen on and granted live data (§2: nothing is asked before the consent).
        if FollowNoticeStore.load().isEnabled, live.consent == .granted, !LaunchMode.isSandboxed {
            LiveFollowNotifications.requestAuthorization()
        }
        persist()
        loop = Task { [weak self] in await self?.run() }
    }

    /// Ends the follow: polling stops, the Live Activity disappears, the saved record and the background request go.
    func stop() {
        loop?.cancel()
        loop = nil
        endActivityNow()
        target = nil
        snapshot = nil
        lastNotice = nil
        fetch = nil
        ledger = FollowNoticeLedger()
        FollowRecordStore.save(nil)
        FollowBackgroundRefresh.cancel()
        WidgetCacheSync.liveFollowDidChange(active: false)   // MARK: widgets – the Live-verfolgen control
    }

    /// Opens the card's stop list (a notification's "Details öffnen").
    func requestDetail() {
        detailRequest += 1
    }

    /// Brings back the follow saved before the app closed, when live data is granted and the follow is not over. A
    /// restored follow resumes polling unless `resume` is false (background refresh: one answer, then done).
    func restoreIfNeeded(live: LiveDataService, resume: Bool = true) {
        guard target == nil, live.isDemo == false, live.consent == .granted, let record = FollowRecordStore.load() else { return }
        let finished = record.snapshot?.stage.isFinished ?? false
        let arrival = record.target.plannedArrival ?? record.startedAt.addingTimeInterval(Self.maxRestoreAge)
        guard !finished, arrival.addingTimeInterval(2 * 60 * 60) > Date() else {
            FollowRecordStore.save(nil)
            return
        }
        target = record.target
        snapshot = record.snapshot
        ledger = record.ledger
        activityID = record.activityID
        startedAt = record.startedAt
        updatedAt = record.snapshot?.updatedAt
        fetch = makeFetch(live)
        if resume, loop == nil { loop = Task { [weak self] in await self?.run() } }
    }

    /// The background refresh (BGAppRefreshTask): restores the saved follow and makes one answer. Returns false when there
    /// is nothing to do: no follow, switches off, live data not granted, or the follow is over.
    func refreshInBackground(live: LiveDataService) async -> Bool {
        guard FollowNoticeStore.load().isEnabled else { return false }
        restoreIfNeeded(live: live, resume: false)
        guard target != nil, !(snapshot?.stage.isFinished ?? false), fetch != nil else { return false }
        await pollOnce()
        return true
    }

    // MARK: Polling

    private func run() async {
        while !Task.isCancelled, target != nil {
            await pollOnce()
            if status == .finished || Task.isCancelled { break }
            let interval = FollowRefreshPlan.pollInterval(stage: snapshot?.stage ?? .beforeDeparture,
                                                          plannedDeparture: target?.plannedDeparture, now: Date())
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// One answer: notices, snapshot, Live Activity, record, next background request.
    func pollOnce() async {
        guard let target, let fetch else { return }
        do {
            let trip = try await fetch(target.tripID)
            // The follow was stopped or replaced while the request was in flight: this answer must not start or update a Live
            // Activity, nor write a snapshot into the follow that replaced it.
            guard !Task.isCancelled, self.target?.tripID == target.tripID else { return }
            let now = Date()
            let next = LiveFollow.snapshot(trip, target: target, now: now)
            let settings = FollowNoticeStore.load()
            let candidates = LiveFollow.notices(from: snapshot, to: next, now: now, delayThreshold: settings.delayThresholdSeconds)
            for notice in candidates {
                // Claimed even when quiet hours or a switch hold it back: a notice is never delivered late.
                guard ledger.claim(notice), settings.allows(notice, at: now) else { continue }
                lastNotice = notice
                LiveFollowNotifications.post(notice, lineName: target.lineName, id: target.tripID)
            }
            snapshot = next
            updatedAt = now
            status = next.stage.isFinished ? .finished : .following
            await syncActivity(target: target, snapshot: next, now: now, settings: settings)
            persist()
            if settings.isEnabled, let next = FollowRefreshPlan.earliestBackgroundRefresh(
                stage: next.stage, plannedDeparture: target.plannedDeparture, now: now) {
                FollowBackgroundRefresh.schedule(at: next)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.target?.tripID == target.tripID else { return }
            status = .paused(LiveMessage.text(for: error))
            // Live data switched off or withdrawn: nothing was asked, so no background request is booked for it.
            if case .disabled? = error as? LiveError { return }
            // A failed background answer must not end the chain of background requests: the next one is asked for as usual.
            if FollowNoticeStore.load().isEnabled, let next = FollowRefreshPlan.earliestBackgroundRefresh(
                stage: snapshot?.stage ?? .beforeDeparture, plannedDeparture: target.plannedDeparture, now: Date()) {
                FollowBackgroundRefresh.schedule(at: next)
            }
        }
    }

    // MARK: Live Activity and record

    private func syncActivity(target: LiveFollowTarget, snapshot: LiveFollowSnapshot, now: Date, settings: FollowNoticeSettings) async {
        // Demo runs and switches that are off never start or keep a Live Activity.
        guard !isDemoRun, !LaunchMode.isSandboxed else { return }
        let controller = FollowActivityController.shared
        let state = FollowLiveState.make(from: snapshot, now: now)
        let staleDate = FollowRefreshPlan.staleDate(arrival: snapshot.arrivalEstimate, now: now)

        if !settings.isEnabled {
            endActivityNow()
            return
        }
        if let id = activityID {
            if snapshot.stage.isFinished {
                // Arrival stays visible for five minutes, a cancelled run disappears at once.
                await controller.end(id: id, final: state, staleDate: staleDate,
                                     dismissAfter: snapshot.stage == .arrived ? 5 * 60 : 0)
                activityID = nil
            } else {
                let stillThere = await controller.update(id: id, state: state, staleDate: staleDate)
                if !stillThere { activityID = nil }   // the user removed it from the Lock Screen
            }
        } else if !snapshot.stage.isFinished,
                  let id = controller.start(target: target, state: state, staleDate: staleDate, startedAt: startedAt) {
            activityID = id
        }
    }

    /// Ends the Live Activity at once (stop, replaced follow, switch off).
    private func endActivityNow() {
        guard let id = activityID else { return }
        activityID = nil
        Task { await FollowActivityController.shared.end(id: id, final: nil, staleDate: Date(), dismissAfter: 0) }
    }

    private func persist() {
        guard let target else {
            FollowRecordStore.save(nil)
            return
        }
        FollowRecordStore.save(FollowRecord(target: target, snapshot: snapshot, ledger: ledger, activityID: activityID,
                                            startedAt: startedAt))
    }

    private func makeFetch(_ live: LiveDataService) -> (String) async throws -> TripDetails {
        if live.isDemo {
            return { id in
                guard let trip = DemoFollow.trip(id, now: Date()) else { throw LiveError.noConnection }
                return trip
            }
        }
        return { [weak live] id in
            guard let service = live?.timetable else { throw LiveError.disabled(.oebbHafas) }
            return try await service.trip(id, includePolyline: false)
        }
    }
}
