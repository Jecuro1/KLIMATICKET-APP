import Foundation
import CoreLocation
import KlimaCore

// Aussteige-Wecker: the real location provider (docs/EXIT_ALARM.md §3, §6). Low-power updates while an alarm is armed and the
// trip runs, a circular geofence around the stop, and nothing else. No track is kept: every fix goes straight to the engine.
// It never asks for a permission by itself; the pre-prompt screen of the sheet asks, and then the system does.

final class CLExitAlarmLocation: NSObject, ExitAlarmLocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var handler: ExitAlarmLocationHandler?

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
        let capped = min(radius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                      radius: capped, identifier: regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(regionID: String) {
        for region in manager.monitoredRegions where region.identifier == regionID { manager.stopMonitoring(for: region) }
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
        let id = region.identifier
        Task { @MainActor in self.handler?.locationProvider(didEnterRegion: id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let id = region?.identifier
        Task { @MainActor in
            if let id { self.handler?.locationProvider(regionMonitoringFailed: id) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handler?.locationProviderDidChangeAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix (tunnel, no signal) is no event: the timetable carries the alarm.
    }
}
