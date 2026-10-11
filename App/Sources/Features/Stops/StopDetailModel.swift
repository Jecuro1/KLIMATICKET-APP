import Foundation
import KlimaCore
import Observation

/// What the departures section shows (ENRICH_SPEC §4.4). Live data comes from the planner work (WP-L): until a
/// `StopDepartureProviding` is registered the state stays `.unavailable` and the section is hidden.
enum DeparturesState {
    case unavailable
    case loading
    case live(StopDepartures)
    case empty
    case failed
}

/// Feature flags of the stop detail.
enum StopFeatureFlags {
    /// The „Nächste Abfahrten“ section (WP-L). Off: `StopDeparturesSection` renders nothing.
    static let showsDepartures = false
}

/// State of one stop detail: loads `StopDetails` from the place index (built in the background at launch).
@MainActor
@Observable
final class StopDetailModel {
    enum Phase { case loading, loaded, missing }

    let placeID: String
    private(set) var phase: Phase = .loading
    private(set) var details: StopDetails?
    private(set) var index: PlaceIndex?
    var departures: DeparturesState = .unavailable

    init(placeID: String) {
        self.placeID = placeID
        if let index = PlaceIndexLoader.shared.current { apply(index) }
    }

    func load() async {
        guard details == nil else { return }
        guard let index = try? await PlaceIndexLoader.shared.load() else {
            phase = .missing
            return
        }
        apply(index)
    }

    private func apply(_ index: PlaceIndex) {
        self.index = index
        details = index.details(for: placeID)
        phase = details == nil ? .missing : .loaded
    }

    /// Ids a stored trip may use for this stop (the place id and the ids of the previous station list).
    var tripStationIDs: Set<String> {
        guard let place = details?.place else { return [placeID] }
        return Set([place.id, place.stationID, placeID] + place.legacyStationIDs)
    }
}
