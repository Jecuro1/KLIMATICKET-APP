import Foundation
import ActivityKit
import WidgetKit
import KlimaCore

// "Unterwegs" Live Activity – the parts both targets need: the ActivityKit attributes, the App Group ride store and the
// end-of-ride actions used by the Live Activity buttons (RideActivityIntents.swift). Shared source file: compiled into
// the app (starts, updates and ends rides) and the widget extension (renders them, Widgets/Sources/RideLiveActivity.swift).

/// Static data of a ride's Live Activity plus its live `ContentState`. Kept small: ActivityKit caps both at 4 KB.
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var phase: RidePhase
        /// Value of this ride (both directions for a round trip), EUR.
        var valueEUR: Double
        /// Amortisation before → after this ride; nil without a priced ticket for today.
        var payoff: RidePayoff?
        /// Expected arrival when known (live planner).
        var expectedArrival: Date?
        /// Live line from the planner ("RJX 662 · pünktlich · Gl. 3").
        var status: RideStatusLine?
        /// When the ride was saved or ended (end states).
        var endedAt: Date?

        init(phase: RidePhase = .riding, valueEUR: Double, payoff: RidePayoff?, expectedArrival: Date? = nil,
             status: RideStatusLine? = nil, endedAt: Date? = nil) {
            self.phase = phase
            self.valueEUR = valueEUR
            self.payoff = payoff
            self.expectedArrival = expectedArrival
            self.status = status
            self.endedAt = endedAt
        }
    }

    var rideID: UUID
    var fromName: String
    var toName: String
    var modeRaw: String
    var isRoundTrip: Bool
    /// "RJX 662" when known.
    var lineLabel: String?
    var ticketName: String
    var startedAt: Date
    /// Mini summit: the ticket's cumulative value as fractions of the price (≤ 16 points, the last one = before this ride).
    var climb: [Double]
    /// Via station names in travel order (docs/VIA.md); nil for rides without vias and activities of older builds.  // MARK: via
    var via: [String]? = nil

    /// "über Feldkirch" – shown in the caption while riding without a live line.  // MARK: via
    var viaTitle: String? { RideNames.via(via ?? []) }

    var mode: TransportMode { TransportMode(rawValue: modeRaw) ?? .train }

    /// "St. Anton → Innsbruck Hbf"
    var routeTitle: String { RideNames.route(from: fromName, to: toName, roundTrip: isRoundTrip) }

    /// Elapsed-time range for `Text(timerInterval:)` (counts up from the start, stops at the 8-hour limit).
    var timerRange: ClosedRange<Date> { startedAt...RidePolicy.staleDate(for: startedAt) }
}

extension RideActivityAttributes {
    init(record: RideRecord, climb: [Double]) {
        self.init(rideID: record.id, fromName: record.trip.fromName, toName: record.trip.toName, modeRaw: record.trip.mode.rawValue,
                  isRoundTrip: record.trip.isRoundTrip, lineLabel: record.lineLabel, ticketName: record.ticketName,
                  startedAt: record.startedAt, climb: climb, via: record.trip.via.isEmpty ? nil : record.trip.via.map(\.name))
    }
}

// MARK: - Ride store (App Group)

/// Running rides and rides waiting to be saved, in the App Group defaults (same pattern as `QuickLogQueue`).
/// The app owns the SwiftData store; the Live Activity buttons only hand finished rides over, the app ingests them
/// (`Repository.ingestFinishedRides()`) as soon as it runs – right away when it is already open.
enum RideStore {
    private static let activeKey = "ride.active.v1"
    private static let finishedKey = "ride.finished.v1"

    /// Posted (any thread) whenever a ride starts, is handed over for saving or is discarded.
    static let didChange = Notification.Name("KBRideStoreDidChange")

    private static var defaults: UserDefaults { AppGroup.defaults }

    // Running rides

    static func active() -> [RideRecord] { load(activeKey) }

    static func record(_ id: UUID) -> RideRecord? { active().first { $0.id == id } }

    static func upsert(_ record: RideRecord) {
        var items = active().filter { $0.id != record.id }
        items.append(record)
        save(items, activeKey)
    }

    @discardableResult
    static func remove(_ id: UUID) -> RideRecord? {
        var items = active()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let record = items.remove(at: index)
        save(items, activeKey)
        return record
    }

    // Finished rides (to be saved as trips by the app)

    static func finish(_ record: RideRecord) {
        var items = load(finishedKey).filter { $0.id != record.id }
        items.append(record)
        save(items, finishedKey)
    }

    static func pendingFinished() -> [RideRecord] { load(finishedKey) }

    /// Returns and clears all rides waiting to be saved.
    static func drainFinished() -> [RideRecord] {
        let items = load(finishedKey)
        if !items.isEmpty { defaults.removeObject(forKey: finishedKey) }
        return items
    }

    static func notifyChange() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func load(_ key: String) -> [RideRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RideRecord].self, from: data)) ?? []
    }

    private static func save(_ items: [RideRecord], _ key: String) {
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - End of a ride (Live Activity buttons, app)

enum RideActivityActions {
    /// "Fahrt speichern": hands the ride over to the app, updates the widgets optimistically and leaves a short
    /// "Gespeichert" confirmation on the Lock Screen. Idempotent – a second tap only ends the activity.
    static func save(rideID: UUID, now: Date = Date()) async {
        if let record = RideStore.remove(rideID) {
            RideStore.finish(record)
            applyToWidgetSnapshot(record)
            WidgetCenter.shared.reloadAllTimelines()
        }
        await end(rideID: rideID, phase: .saved, dismissAfter: RidePolicy.savedDismissal, now: now)
        RideStore.notifyChange()
    }

    /// "Beenden": forgets the ride without saving and removes the Live Activity right away.
    static func discard(rideID: UUID, now: Date = Date()) async {
        RideStore.remove(rideID)
        await end(rideID: rideID, phase: .ended, dismissAfter: 0, now: now)
        RideStore.notifyChange()
    }

    /// Ends every activity of the ride with a final state (`dismissAfter` 0 = immediately, nil = system default).
    static func end(rideID: UUID, phase: RidePhase, dismissAfter: TimeInterval?, now: Date = Date()) async {
        for activity in Activity<RideActivityAttributes>.activities where activity.attributes.rideID == rideID {
            await end(activity, phase: phase, dismissAfter: dismissAfter, now: now)
        }
    }

    static func end(_ activity: Activity<RideActivityAttributes>, phase: RidePhase, dismissAfter: TimeInterval?, now: Date = Date()) async {
        var state = activity.content.state
        state.phase = phase
        state.endedAt = now
        let policy: ActivityUIDismissalPolicy
        if let dismissAfter {
            policy = dismissAfter <= 0 ? .immediate : .after(now.addingTimeInterval(dismissAfter))
        } else {
            policy = .default
        }
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy)
    }

    /// Same optimistic update the quick log does, until the app recomputes the snapshot precisely.
    private static func applyToWidgetSnapshot(_ record: RideRecord) {
        guard var snapshot = WidgetSnapshot.load(), record.trip.totalValue > 0 else { return }
        let ride = WidgetSnapshot.Favorite(id: record.id, title: RideNames.route(from: record.trip.fromName, to: record.trip.toName,
                                                                                 roundTrip: record.trip.isRoundTrip),
                                           modeSymbol: record.trip.mode.symbolName, value: record.trip.totalValue,
                                           distanceKm: record.trip.totalDistanceKm, fromName: record.trip.fromName,
                                           toName: record.trip.toName)
        snapshot.apply(favorite: ride, date: record.startedAt)
        snapshot.save()
    }
}

extension ActivityState {
    /// The reconciler's view of an ActivityKit state.
    var rideStatus: RideReconciler.ActivityStatus {
        switch self {
        case .pending: .pending
        case .active: .active
        case .stale: .stale
        case .ended: .ended
        case .dismissed: .dismissed
        @unknown default: .ended
        }
    }
}
