import SwiftUI
import MapKit
import KlimaCore

// MARK: radar2-trail – stub of „Spuren“ on the radar view (specs/radar2/radartrail.md). Draws nothing until the radartrail track replaces
// these bodies.

extension RadarView {
    @MapContentBuilder var trailMapContent: some MapContent {
        ForEach([RadarPin](), id: \.id) { pin in
            MapCircle(center: pin.coordinate.clCoordinate, radius: 1)
        }
    }

    var trailStatusNote: some View { EmptyView() }
}

/// The delay sparkline in the trip sheet.
struct RadarTrailDelayRow: View {
    let vehicle: RadarVehicle
    let trail: RadarTrailModel

    var body: some View { EmptyView() }
}

/// „Spuren“ at the end of the filter sheet's „Darstellung“ page.
struct RadarTrailSettingsSection: View {
    let trail: RadarTrailModel

    var body: some View { EmptyView() }
}
