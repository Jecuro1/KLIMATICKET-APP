import SwiftUI
import MapKit
import KlimaCore

// MARK: radar2-mine – stub of „Meine Fahrzeuge“ on the radar view (specs/radar2/radarmine.md). Draws nothing until the radarmine track
// replaces these bodies.

extension RadarView {
    @MapContentBuilder var mineMapContent: some MapContent {
        ForEach([RadarPin](), id: \.id) { pin in
            MapCircle(center: pin.coordinate.clCoordinate, radius: 1)
        }
    }

    var mineTopBarChip: some View { EmptyView() }
    var minePanel: some View { EmptyView() }
    var minePanelIsOpen: Bool { false }
    func mineDecoration(_ pin: RadarPin) -> RadarMarkerDecoration { .plain }
}

/// „Linie merken“ in the trip sheet.
struct RadarMineTripRow: View {
    let vehicle: RadarVehicle
    let mine: RadarMineModel

    var body: some View { EmptyView() }
}
