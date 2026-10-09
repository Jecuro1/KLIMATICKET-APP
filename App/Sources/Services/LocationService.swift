import Foundation
import CoreLocation
import KlimaCore

/// One-shot "where am I?" for suggesting the nearest station.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Requests permission if needed and returns the current location (or nil after ~8 s).
    func currentLocation() async -> CLLocation? {
        if isDenied { return nil }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 120 { return cached }
        return await withCheckedContinuation { cont in
            continuation?.resume(returning: nil)
            continuation = cont
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                self.finish(nil)
            }
        }
    }

    func nearestStations(in index: StationIndex, limit: Int = 3) async -> [(station: Station, distanceKm: Double)] {
        guard let loc = await currentLocation() else { return [] }
        return index.nearest(to: GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude), limit: limit)
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.continuation != nil { self.manager.requestLocation() }
            } else if status == .denied || status == .restricted {
                self.finish(nil)
            }
        }
    }
}
