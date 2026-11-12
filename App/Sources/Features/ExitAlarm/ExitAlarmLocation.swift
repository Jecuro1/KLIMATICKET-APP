import Foundation
import CoreLocation
import KlimaCore

// Aussteige-Wecker: the real location provider (docs/EXIT_ALARM.md §3, §6). Low-power updates while an alarm is armed and the
// trip runs, a circular geofence around the stop, and nothing else. No track is kept: every fix goes straight to the engine.
// It never asks for a permission by itself; the pre-prompt screen of the sheet asks, and then the system does.

final class CLExitAlarmLocation: NSObject, ExitAlarmLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// The engine owns this provider, so the way back is weak: no retain cycle between the two.
    weak var handler: ExitAlarmLocationHandler?
    /// The circles of the app are shared with the trip detection: ours carry this prefix and nobody else touches them.
    static let regionPrefix = "exitalarm."

    override init() {
        super.init()
        manager.delegate = self
        // Kilometres, not metres: a 100 m accuracy and a 100 m distance filter keep the radio quiet. The speed is smoothed.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.activityType = .otherNavigation   // trains and boats
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: ExitAlarmLocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }

    var isRegionMonitoringAvailable: Bool { CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }

    func startUpdates() {
        // The background mode is declared in Info.plist (UIBackgroundModes: location). Without it iOS would raise an exception.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true   // the blue pill: the user sees that the location is in use
        }
        manager.startUpdatingLocation()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    func startMonitoring(regionID: String, center: GeoPoint, radius: Double) {
        let identifier = Self.regionPrefix + regionID
        let capped = min(radius, manager.maximumRegionMonitoringDistance)
        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        // iOS keeps the circles across launches. Setting the same circle again after a relaunch for its entry could reset its
        // state and swallow the pending event, so an identical circle is left alone.
        if let known = manager.monitoredRegions.first(where: { $0.identifier == identifier }) as? CLCircularRegion,
           abs(known.radius - capped) < 1, abs(known.center.latitude - coordinate.latitude) < 1e-6,
           abs(known.center.longitude - coordinate.longitude) < 1e-6 {
            return
        }
        let region = CLCircularRegion(center: coordinate, radius: capped, identifier: identifier)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(regionID: String) {
        // The bare id is how an earlier build named its circles: stop those too, so none is left behind.
        for region in manager.monitoredRegions where region.identifier == Self.regionPrefix + regionID || region.identifier == regionID {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { location in
            LocationFix(time: location.timestamp,
                        coordinate: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                        speed: location.speed >= 0 ? location.speed : nil,
                        horizontalAccuracy: location.horizontalAccuracy)
        }
        Task { @MainActor in
            for fix in fixes { self.handler?.locationProvider(didUpdate: fix) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // The trip detection's circles come through here too (every manager of the app hears every circle): not ours, not handled.
        guard region.identifier.hasPrefix(Self.regionPrefix) else { return }
        let id = String(region.identifier.dropFirst(Self.regionPrefix.count))
        Task { @MainActor in self.handler?.locationProvider(didEnterRegion: id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier, identifier.hasPrefix(Self.regionPrefix) else { return }
        let id = String(identifier.dropFirst(Self.regionPrefix.count))
        Task { @MainActor in self.handler?.locationProvider(regionMonitoringFailed: id) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handler?.locationProviderDidChangeAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix (tunnel, no signal) is no event: the timetable carries the alarm.
    }
}
