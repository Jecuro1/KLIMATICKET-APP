import Foundation
import CoreLocation
import UIKit
import UserNotifications
import KlimaCore

/// A detected trip waiting for confirmation ("Fahrt St. Anton → Innsbruck erfassen?").
struct TripSuggestion: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var fromStationID: String
    var toStationID: String
    var fromName: String
    var toName: String
    var departedAt: Date
    var arrivedAt: Date
    var fareEUR: Double
    var distanceKm: Double
    var states: [String]
}

/// Opt-in automatic trip detection via region monitoring around the user's most used stations (max. 20).
/// Leaving station A and entering station B within 4 hours produces a suggestion + local notification.
/// Battery-friendly (no continuous GPS); works in the background and relaunches the app when needed – the relaunch has
/// no UI, so stations and prices are resolved on demand (`stationResolver`, `estimatorProvider`) when `configure`
/// has not run in this process. A short stop at a monitored station on the way (a train passing through) extends the
/// trip: A → B → C becomes one suggestion A → C instead of two.
@Observable
@MainActor
final class TripDetectionService: NSObject, CLLocationManagerDelegate {
    private(set) var suggestions: [TripSuggestion] = []
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            isEnabled ? requestAndStart() : stopAll()
        }
    }

    /// Station by id (= region identifier) when `configure` has not run in this process (set by AppState).
    @ObservationIgnored var stationResolver: @MainActor (String) async -> Station? = { _ in nil }
    /// Fare estimator for the same case (set by AppState).
    @ObservationIgnored var estimatorProvider: @MainActor () -> FareEstimator? = { nil }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var stationsByID: [String: Station] = [:]
    @ObservationIgnored private var estimator: FareEstimator?
    /// Region events are handled one after another in arrival order (an arrival may wait for station data).
    @ObservationIgnored private var eventQueue: Task<Void, Never>?

    static let notificationCategory = "TRIP_SUGGESTION"
    static let confirmAction = "TRIP_SUGGESTION_CONFIRM"

    private enum Keys {
        static let enabled = "detection.enabled"
        static let suggestions = "detection.suggestions"
        static let lastExit = "detection.lastExit"
        static let lastArrival = "detection.lastArrival"
    }

    /// The last exit from a monitored station. When it ends a short stop at the station a suggestion was just made
    /// for, the `origin…`/`chainedSuggestionID` fields carry that trip on, so the next arrival can extend it.
    private struct ExitEvent: Codable {
        var stationID: String
        var date: Date
        var originID: String? = nil
        var originDate: Date? = nil
        var chainedSuggestionID: UUID? = nil
    }

    /// The last arrival that produced a suggestion (to recognise a stop that is only passed through).
    private struct ArrivalEvent: Codable {
        var stationID: String
        var date: Date
        var suggestionID: UUID
        var originID: String
        var originDate: Date
    }

    private static let maxTripDuration: TimeInterval = 4 * 3600
    /// Leaving a station this soon after arriving counts as passing through (a train stops 1–3 min) …
    private static let passThroughDwell: TimeInterval = 5 * 60
    /// … and the next arrival has to follow within this time to extend the trip.
    private static let chainWindow: TimeInterval = 90 * 60

    override init() {
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
        if let data = UserDefaults.standard.data(forKey: Keys.suggestions),
           let saved = try? JSONDecoder().decode([TripSuggestion].self, from: data) {
            suggestions = saved.filter { Date().timeIntervalSince($0.arrivedAt) < 7 * 86_400 }
        }
        registerNotificationCategory()
    }

    var isAuthorizedAlways: Bool { authorization == .authorizedAlways }
    var isAvailable: Bool { CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }

    /// Updates the monitored stations (call after trips/favourites change and at launch).
    func configure(stations index: StationIndex, frequentStationIDs: [String], estimator: FareEstimator) {
        self.estimator = estimator
        let selected = frequentStationIDs.compactMap(index.station(id:)).prefix(20)
        stationsByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        guard isEnabled, isAuthorizedAlways else { return }
        syncRegions()
    }

    func confirm(_ suggestion: TripSuggestion, repository: Repository) {
        let trip = TripEntity(date: suggestion.departedAt, fromName: suggestion.fromName, toName: suggestion.toName,
                              fromStationID: suggestion.fromStationID, toStationID: suggestion.toStationID, mode: .train,
                              distanceKm: suggestion.distanceKm, fareEUR: suggestion.fareEUR, states: suggestion.states)
        repository.addTrip(trip)
        remove(suggestion.id)
    }

    func dismiss(_ suggestion: TripSuggestion) { remove(suggestion.id) }

    /// Handles the "Erfassen" action of a suggestion notification.
    func handleNotificationResponse(identifier: String, repository: Repository) {
        guard let id = UUID(uuidString: identifier), let s = suggestions.first(where: { $0.id == id }) else { return }
        confirm(s, repository: repository)
    }

    // MARK: Regions

    private func requestAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        case .authorizedAlways: syncRegions()
        default: break
        }
    }

    private func syncRegions() {
        let wanted = Set(stationsByID.keys)
        for region in manager.monitoredRegions where !wanted.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let existing = Set(manager.monitoredRegions.map(\.identifier))
        for (id, station) in stationsByID where !existing.contains(id) {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon),
                                          radius: 250, identifier: id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    private func stopAll() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
    }

    private func didExit(stationID: String, at date: Date) {
        var event = ExitEvent(stationID: stationID, date: date)
        if let arrival = load(ArrivalEvent.self, forKey: Keys.lastArrival), arrival.stationID == stationID,
           date.timeIntervalSince(arrival.date) < Self.passThroughDwell {
            // Possibly only passing through: the next arrival may extend that trip (decided there).
            event.originID = arrival.originID
            event.originDate = arrival.originDate
            event.chainedSuggestionID = arrival.suggestionID
        }
        UserDefaults.standard.removeObject(forKey: Keys.lastArrival)
        store(event, forKey: Keys.lastExit)
    }

    private func didEnter(stationID: String, at date: Date) async {
        guard let exit = load(ExitEvent.self, forKey: Keys.lastExit) else { return }
        guard exit.stationID != stationID else {
            // Back at the station just left: no trip, and no pass-through either.
            if exit.chainedSuggestionID != nil { store(ExitEvent(stationID: exit.stationID, date: exit.date), forKey: Keys.lastExit) }
            return
        }
        guard date.timeIntervalSince(exit.date) < Self.maxTripDuration, let to = await station(stationID) else { return }
        // A short stop at the previous station after a trip that is still waiting for confirmation: extend it.
        var origin: (station: Station, departedAt: Date, replaces: UUID)?
        if let chained = exit.chainedSuggestionID, let originID = exit.originID, originID != stationID,
           date.timeIntervalSince(exit.date) < Self.chainWindow, let first = await station(originID) {
            origin = (first, exit.originDate ?? exit.date, chained)
        }
        let previous = await station(exit.stationID)
        // The user may have confirmed or dismissed the first leg meanwhile – then it stays a trip of its own.
        if let o = origin, !suggestions.contains(where: { $0.id == o.replaces }) { origin = nil }
        guard let from = origin?.station ?? previous else { return }
        UserDefaults.standard.removeObject(forKey: Keys.lastExit)
        let estimate = (estimator ?? estimatorProvider())?.estimate(from: from, to: to, mode: .train)
        guard let estimate, estimate.distanceKm >= 2 else { return }
        let departedAt = origin?.departedAt ?? exit.date
        let suggestion = TripSuggestion(fromStationID: from.id, toStationID: to.id, fromName: from.name, toName: to.name,
                                        departedAt: departedAt, arrivedAt: date, fareEUR: estimate.fareEUR,
                                        distanceKm: estimate.distanceKm, states: Array(Set([from.state, to.state])).sorted())
        if let replaced = origin?.replaces { remove(replaced) }   // A → B becomes A → C
        suggestions.insert(suggestion, at: 0)
        persist()
        notify(suggestion)
        store(ArrivalEvent(stationID: stationID, date: date, suggestionID: suggestion.id, originID: from.id, originDate: departedAt),
              forKey: Keys.lastArrival)
    }

    /// Configured stations first, then the resolver (background relaunch without `configure`).
    private func station(_ id: String) async -> Station? {
        if let station = stationsByID[id] { return station }
        return await stationResolver(id)
    }

    /// Runs region events strictly one after another, each with extra background time: a relaunch for a region event
    /// only gets a few seconds, and resolving a stop may first have to build the place index.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = eventQueue
        eventQueue = Task { @MainActor in
            await previous?.value
            let time = BackgroundTime(name: "TripDetection")
            await work()
            time.end()
        }
    }

    private func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func remove(_ id: UUID) {
        suggestions.removeAll { $0.id == id }
        persist()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(suggestions.prefix(20))) {
            UserDefaults.standard.set(data, forKey: Keys.suggestions)
        }
    }

    private func registerNotificationCategory() {
        let confirm = UNNotificationAction(identifier: Self.confirmAction, title: "Erfassen", options: [])
        let category = UNNotificationCategory(identifier: Self.notificationCategory, actions: [confirm], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func notify(_ s: TripSuggestion) {
        let content = UNMutableNotificationContent()
        content.title = "Fahrt erfassen?"
        content.body = "\(s.fromName) → \(s.toName) · \(Format.euroPrecise(s.fareEUR))"
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategory
        content.threadIdentifier = "suggestions"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: s.id.uuidString, content: content, trigger: nil))
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways, self.isEnabled { self.syncRegions() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier, date = Date()
        Task { @MainActor in self.enqueue { self.didExit(stationID: id, at: date) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier, date = Date()
        Task { @MainActor in self.enqueue { await self.didEnter(stationID: id, at: date) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
}

/// A UIKit background-task assertion: keeps a process that iOS woke for a region event alive until the work is done.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
