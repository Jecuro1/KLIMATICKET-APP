import SwiftUI
import MapKit
import KlimaCore

// MARK: radarcockpit – what the radar view gives the Cockpit-Ansicht (docs/RADAR_COCKPIT.md §4): the launch with the train as the radar knows it, and the
// camera it starts from. The cockpit opens when the trip sheet has closed (a full-screen cover cannot open while a sheet is on its way out).

extension RadarView {
    /// The train as the radar has it: its last answer and when that came in, the details the sheet loaded, and the radar's own map as the camera
    /// the flight starts from.
    func cockpitLaunch(_ run: RadarVehicle, _ details: TripDetails?) -> CockpitLaunch {
        let seen = model.seenAt(of: run.tripID) ?? Date()
        // The radar's map: centred on its box, as far out as its span (about 100 km a degree of latitude).
        let start = CockpitCamera(center: model.box.center, distance: min(max(model.spanDegrees * 111_000 * 1.7, 4_000), 1_500_000))
        return CockpitLaunch(vehicle: model.latestVehicle(run.tripID) ?? run, details: details, seenAt: seen, startCamera: start)
    }

    /// Called when the trip sheet is gone: now the cockpit may open.
    func openPendingCockpit() {
        guard let launch = pendingCockpit else { return }
        pendingCockpit = nil
        cockpit = launch
    }
}

extension RadarModel {
    /// When the radar's latest answer for this train came in.
    func seenAt(of tripID: String) -> Date? { store.entries[tripID]?.seenAt }

    /// The train as the latest answer holds it (its position is the server's, not the estimate of the moment).
    func latestVehicle(_ tripID: String) -> RadarVehicle? { store.entries[tripID]?.vehicle }
}
