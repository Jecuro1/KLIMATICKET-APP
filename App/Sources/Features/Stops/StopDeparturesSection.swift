import KlimaCore
import SwiftUI

/// „Nächste Abfahrten“ – the seam of the live departures (ENRICH_SPEC §4, WP-L). Until the planner work registers a
/// provider this renders nothing: no empty card, no error. WP-L replaces the body and sets `StopDetailModel.departures`.
struct StopDeparturesSection: View {
    let state: DeparturesState

    var body: some View {
        if StopFeatureFlags.showsDepartures {
            switch state {
            case .unavailable:
                EmptyView()
            case .loading, .live, .empty, .failed:
                EmptyView()   // WP-L
            }
        }
    }
}
