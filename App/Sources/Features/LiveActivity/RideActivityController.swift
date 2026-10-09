import ActivityKit
import Foundation
import Observation
import KlimaCore

// The app's side of the "Unterwegs" Live Activity: a small, generic API to start, update and end rides.
// Callers: the trip editor ("Fahrt jetzt starten"), the "Fahrt starten" App Intent and – later – the ÖBB live planner,
// whose `RideActivityControlling` bridge maps its journey snapshots onto `RideStart` / `RideUpdate` (docs/OEBB_LIVE.md §E10).

/// Everything a new ride shows. Generic on purpose: the trip editor fills route and value, the live planner adds
/// line, expected arrival and status.
struct RideStart {
    var id = UUID()
    var trip: RideTrip
    var startedAt = Date()
    /// Amortisation before → after this ride; nil without a priced ticket covering `startedAt`.
    var payoff: RidePayoff?
    var ticketName: String = ""
    /// The ticket's value so far as fractions of its price (mini summit), see `RideClimb`.
    var climb: [Double] = []
    var lineLabel: String?
    var expectedArrival: Date?
    var status: RideStatusLine?

    var record: RideRecord {
        RideRecord(id: id, trip: trip, startedAt: startedAt, payoff: payoff, lineLabel: lineLabel, ticketName: ticketName)
    }

    var attributes: RideActivityAttributes {
        RideActivityAttributes(record: record, climb: climb)
    }

    var initialState: RideActivityAttributes.ContentState {
        RideActivityAttributes.ContentState(phase: .riding, valueEUR: trip.totalValue, payoff: payoff,
                                            expectedArrival: expectedArrival, status: status)
    }
}

/// A partial update of a running ride (nil = unchanged).
struct RideUpdate {
    var phase: RidePhase?
    var status: RideStatusLine?
    var expectedArrival: Date?
    var progress: Double?
    var valueEUR: Double?
    var payoff: RidePayoff?
    /// Lights up the screen and plays the alert sound (e.g. "Angekommen in Innsbruck").
    var alert: (title: String, body: String)?
}

enum RideActivityError: LocalizedError, Equatable {
    case disabled, unsupported, invalidTrip, tooMany, notInForeground, failed

    init(_ error: Error) {
        guard let error = error as? ActivityAuthorizationError else {
            self = .failed
            return
        }
        switch error {
        case .denied: self = .disabled
        case .unsupported, .unsupportedTarget, .unentitled: self = .unsupported
        case .globalMaximumExceeded, .targetMaximumExceeded: self = .tooMany
        case .visibility: self = .notInForeground
        default: self = .failed
        }
    }

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Live-Aktivitäten sind für KlimaBilanz ausgeschaltet. Du kannst sie in den Einstellungen bei „KlimaBilanz“ einschalten."
        case .unsupported:
            "Live-Aktivitäten werden auf diesem iPhone nicht unterstützt."
        case .invalidTrip:
            "Wähle Start, Ziel und einen Normalpreis, bevor du losfährst."
        case .tooMany:
            "Es laufen schon zu viele Live-Aktivitäten. Beende eine davon und versuch es noch einmal."
        case .notInForeground:
            "Öffne KlimaBilanz, um die Fahrt zu starten."
        case .failed:
            "Die Live-Aktivität konnte nicht gestartet werden. Versuch es bitte noch einmal."
        }
    }
}

@MainActor
@Observable
final class RideActivityController {
    static let shared = RideActivityController()

    /// Rides whose Live Activity is still running (oldest first).
    private(set) var rides: [RideRecord] = []
    /// Live Activities allowed for KlimaBilanz (Einstellungen › KlimaBilanz › Live-Aktivitäten).
    private(set) var areActivitiesEnabled: Bool

    @ObservationIgnored private var observed: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var enablementTask: Task<Void, Never>?

    init() {
        let info = ActivityAuthorizationInfo()
        areActivitiesEnabled = info.areActivitiesEnabled
        reload()
        enablementTask = Task { [weak self] in
            for await enabled in info.activityEnablementUpdates {
                self?.areActivitiesEnabled = enabled
            }
        }
    }

    var isSupported: Bool { areActivitiesEnabled }

    // MARK: API

    /// Starts the Live Activity of a ride and remembers the ride (App Group). Returns the ActivityKit activity id.
    @discardableResult
    func start(ride: RideStart) async throws -> String {
        guard ride.trip.isValid else { throw RideActivityError.invalidTrip }
        areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard areActivitiesEnabled else { throw RideActivityError.disabled }
        let content = ActivityContent(state: ride.initialState, staleDate: RidePolicy.staleDate(for: ride.startedAt), relevanceScore: 60)
        let activity: Activity<RideActivityAttributes>
        do {
            activity = try Activity.request(attributes: ride.attributes, content: content, pushType: nil)
        } catch {
            throw RideActivityError(error)
        }
        var record = ride.record
        record.activityID = activity.id
        RideStore.upsert(record)
        observe(activity)
        reload()
        return activity.id
    }

    /// Updates a running ride (status, arrival, value, phase …); `alert` lights up the screen.
    func update(_ activityID: String, _ update: RideUpdate) async {
        guard let activity = activity(id: activityID) else { return }
        var state = activity.content.state
        if let phase = update.phase { state.phase = phase }
        if let status = update.status { state.status = status }
        if let arrival = update.expectedArrival { state.expectedArrival = arrival }
        if let progress = update.progress { state.progress = min(max(progress, 0), 1) }
        if let value = update.valueEUR { state.valueEUR = value }
        if let payoff = update.payoff { state.payoff = payoff }
        let alert = update.alert.map { alert -> AlertConfiguration in
            let title: LocalizedStringResource = "\(alert.title)"
            let body: LocalizedStringResource = "\(alert.body)"
            return AlertConfiguration(title: title, body: body, sound: .default)
        }
        let staleDate = activity.content.staleDate ?? RidePolicy.staleDate(for: activity.attributes.startedAt)
        await activity.update(ActivityContent(state: state, staleDate: staleDate, relevanceScore: 60), alertConfiguration: alert)
        if var record = RideStore.record(activity.attributes.rideID), record.payoff != state.payoff {
            record.payoff = state.payoff
            RideStore.upsert(record)
        }
    }

    /// Ends a ride: `saving` hands it over to be saved as a trip (short "Gespeichert" confirmation),
    /// otherwise the Live Activity disappears right away.
    func end(_ activityID: String, saving: Bool) async {
        guard let rideID = activity(id: activityID)?.attributes.rideID ?? rides.first(where: { $0.activityID == activityID })?.id else {
            return
        }
        if saving {
            await RideActivityActions.save(rideID: rideID)
        } else {
            await RideActivityActions.discard(rideID: rideID)
        }
        reload()
    }

    // MARK: Lifecycle

    /// On launch / foreground: ends overdue (8 h) and orphaned activities and returns the rides that ended without a
    /// decision (swiped away, ended by the system) – the app asks whether to save them.
    func reconcile(now: Date = Date()) async -> [RideRecord] {
        let records = RideStore.active()
        let activities = Activity<RideActivityAttributes>.activities
        let plan = RideReconciler.plan(
            records: records,
            activities: activities.map { RideReconciler.LiveActivity(activityID: $0.id, rideID: $0.attributes.rideID,
                                                                     status: $0.activityState.rideStatus) },
            now: now)
        for activity in activities where plan.endActivityIDs.contains(activity.id) {
            observed[activity.id]?.cancel()
            observed[activity.id] = nil
            await RideActivityActions.end(activity, phase: .ended, dismissAfter: 0, now: now)
        }
        for activity in activities where plan.running.contains(activity.attributes.rideID) {
            observe(activity)
        }
        reload()
        return plan.needsDecision.compactMap { id in records.first { $0.id == id } }
    }

    /// Re-bases "before → after" of running rides on the ticket's current value (another trip was logged meanwhile).
    func refreshPayoffs(currentValue: Double, ticketPrice: Double) async {
        for record in rides {
            guard let activityID = record.activityID,
                  let fresh = RidePayoff(currentValue: currentValue, ticketPrice: ticketPrice, rideValue: record.trip.totalValue)
            else { continue }
            if let old = record.payoff, abs(old.before - fresh.before) < 0.0005, abs(old.ticketPrice - fresh.ticketPrice) < 0.005 {
                continue
            }
            await update(activityID, RideUpdate(payoff: fresh))
        }
        reload()
    }

    /// Mirrors the App Group store, limited to rides whose activity is still running.
    func reload() {
        let running = Set(Activity<RideActivityAttributes>.activities.filter { $0.activityState.rideStatus.isRunning }.map(\.id))
        rides = RideStore.active()
            .filter { $0.activityID.map(running.contains) ?? false }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// Previews and CI screenshots only: shows rides without a Live Activity behind them.
    func showPreview(rides: [RideRecord]) {
        self.rides = rides
    }

    // MARK: Helpers

    private func activity(id: String) -> Activity<RideActivityAttributes>? {
        Activity<RideActivityAttributes>.activities.first { $0.id == id }
    }

    /// Notices when a ride's activity ends outside the app's own buttons (swiped away, ended by the system).
    private func observe(_ activity: Activity<RideActivityAttributes>) {
        guard observed[activity.id] == nil else { return }
        let id = activity.id
        let rideID = activity.attributes.rideID
        observed[id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                self?.observed[id] = nil
                self?.reload()
                // Still in the store = nobody tapped "Fahrt speichern" / "Beenden": let the app ask.
                if RideStore.record(rideID) != nil { RideStore.notifyChange() }
                break
            }
        }
    }
}
