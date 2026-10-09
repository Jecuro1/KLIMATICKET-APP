import Foundation
import CoreLocation
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
/// Battery-friendly (no continuous GPS); works in the background and relaunches the app when needed.
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

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var stationsByID: [String: Station] = [:]
    @ObservationIgnored private var estimator: FareEstimator?

    static let notificationCategory = "TRIP_SUGGESTION"
    static let confirmAction = "TRIP_SUGGESTION_CONFIRM"

    private enum Keys {
        static let enabled = "detection.enabled"
        static let suggestions = "detection.suggestions"
        static let lastExit = "detection.lastExit"
    }

    private struct ExitEvent: Codable {
        var stationID: String
        var date: Date
    }

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
        let event = ExitEvent(stationID: stationID, date: date)
        if let data = try? JSONEncoder().encode(event) { UserDefaults.standard.set(data, forKey: Keys.lastExit) }
    }

    private func didEnter(stationID: String, at date: Date) {
        guard let data = UserDefaults.standard.data(forKey: Keys.lastExit),
              let exit = try? JSONDecoder().decode(ExitEvent.self, from: data),
              exit.stationID != stationID,
              date.timeIntervalSince(exit.date) < 4 * 3600,
              let from = stationsByID[exit.stationID], let to = stationsByID[stationID] else { return }
        UserDefaults.standard.removeObject(forKey: Keys.lastExit)
        let estimate = estimator?.estimate(from: from, to: to, mode: .train)
        guard let estimate, estimate.distanceKm >= 2 else { return }
        let suggestion = TripSuggestion(fromStationID: from.id, toStationID: to.id, fromName: from.name, toName: to.name,
                                        departedAt: exit.date, arrivedAt: date, fareEUR: estimate.fareEUR,
                                        distanceKm: estimate.distanceKm, states: Array(Set([from.state, to.state])).sorted())
        suggestions.insert(suggestion, at: 0)
        persist()
        notify(suggestion)
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
        let id = region.identifier
        Task { @MainActor in self.didExit(stationID: id, at: Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.didEnter(stationID: id, at: Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
}
