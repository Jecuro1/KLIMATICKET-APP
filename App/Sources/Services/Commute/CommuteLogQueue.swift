import Foundation
import SwiftData
import KlimaCore

// Pendel-Modus (docs/COMMUTE.md §6): „Pendelfahrt erfassen“ from Siri and Shortcuts. Like the quick logs of the widgets the
// request is queued first and turned into a ride by the app through the Repository (one commit, widget refresh, sync) – right
// away when the app's store is open, else at the next activation (RootView). The value comes from the same fare logic as the
// trip editor (`Repository.facts`). The queue lives in the app's own UserDefaults: the intent runs in the app's process.

struct PendingCommuteLog: Codable, Hashable {
    var id = UUID()
    var date: Date
    var direction: CommuteDirection
    var isRoundTrip: Bool
}

enum CommuteLogQueue {
    static let key = "commute.pendingLogs.v1"
    /// A queued log that still cannot be saved after this long (stations gone) is dropped.
    static let maxAge: TimeInterval = 7 * 86_400

    static func enqueue(_ log: PendingCommuteLog) {
        var items = pending()
        items.append(log)
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func pending() -> [PendingCommuteLog] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingCommuteLog].self, from: data)) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func keep(_ items: [PendingCommuteLog]) {
        if items.isEmpty {
            clear()
        } else if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Ingests run one after the other: the scene's activation and the intent can both ask while a station lookup is awaited,
    /// and two overlapping runs would read the same queue and save every ride twice. A finishing run hands its turn to the next
    /// waiter directly (`isIngesting` stays true), so no third caller can slip in between.
    @MainActor private static var isIngesting = false
    @MainActor private static var waiting: [CheckedContinuation<Void, Never>] = []

    /// Turns the queued logs into rides. Returns the rides added. A log whose stations cannot be found yet (the place index
    /// is still loading) stays queued; one older than a week is dropped. On a failed save everything stays queued.
    @MainActor
    @discardableResult
    static func ingest(context: ModelContext, app: AppState, showsToast: Bool = true) async -> [TripEntity] {
        if isIngesting {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            isIngesting = true
        }
        defer {
            if waiting.isEmpty { isIngesting = false } else { waiting.removeFirst().resume() }
        }
        return await ingestQueued(context: context, app: app, showsToast: showsToast)
    }

    @MainActor
    private static func ingestQueued(context: ModelContext, app: AppState, showsToast: Bool) async -> [TripEntity] {
        let items = pending()
        guard !items.isEmpty else { return [] }
        let settings = CommuteSettingsStore.shared.settings
        let repo = Repository(context: context, app: app)
        var inserted: [TripEntity] = []
        var done: [PendingCommuteLog] = []
        var left: [PendingCommuteLog] = []
        for item in items {
            guard let ends = CommuteModel.shared.ends(item.direction), let fromID = ends.from.stationID, let toID = ends.to.stationID,
                  let from = await CommuteModel.station(fromID, app: app), let to = await CommuteModel.station(toID, app: app) else {
                if Date().timeIntervalSince(item.date) < maxAge { left.append(item) } else { done.append(item) }
                continue
            }
            let value = repo.facts(mode: settings.mode, date: item.date, from: from, to: to)
            let trip = TripEntity(date: item.date, fromName: from.name, toName: to.name, fromStationID: from.id, toStationID: to.id,
                                  mode: settings.mode, distanceKm: value.distanceKm, fareEUR: value.fareEUR, isFareManual: false,
                                  isRoundTrip: item.isRoundTrip, travelClass: app.settings.defaultTravelClass, companions: 0,
                                  states: value.states, note: "")
            trip.priceSourceRaw = value.priceSource.rawValue
            inserted.append(trip)
            done.append(item)
        }
        guard !done.isEmpty else { return [] }
        guard repo.addCommuteTrips(inserted) else { return [] }
        // Only what was handled leaves the queue; a log Siri added meanwhile stays.
        let handled = Set(done.map(\.id))
        keep(pending().filter { !handled.contains($0.id) })
        if showsToast, let first = inserted.first {
            let value = inserted.reduce(0) { $0 + $1.fareEUR * ($1.isRoundTrip ? 2 : 1) }
            let route = "\(TripRow.short(first.fromName)) → \(TripRow.short(first.toName))"
            app.showToast("checkmark.circle.fill", inserted.count == 1 ? "Pendelfahrt erfasst" : "\(inserted.count) Pendelfahrten erfasst",
                          "\(route) · + \(Format.euroPrecise(value)) · über Siri")
        }
        return inserted
    }
}
