import SwiftUI
import KlimaCore

// MARK: radarmodes – CI screenshot scenes of Bus, Bim and U-Bahn on the radar (docs/RADAR_MODES.md §10): synthetic city fleets, no network, the
// demo-only fast budget so a city view is fully loaded when it is captured.

struct RadarModesScreenshotHost: View {
    static let screens: Set<String> = ["radarModesCity", "radarModesZoomHint", "radarModesLegend", "radarModesCrowded", "radarModesAX5",
                                       "radarModesDots", "radarModesFilter", "radarModesFilterLines", "radarModesDisplay", "radarModesEmpty"]

    let screen: String

    var body: some View {
        switch screen {
        case "radarModesZoomHint":   // Austria with Bus on: the hint and the chips' zoom badges
            RadarView(preset: .modesZoomHint)
        case "radarModesLegend":
            RadarView(preset: .modesLegend)
        case "radarModesCrowded":   // the Wien view with knots of vehicles: crowded, cut-off and data notes
            RadarView(preset: .modesCrowded)
        case "radarModesAX5":   // chips, counts and notes at the largest text size
            RadarView(preset: .modesCity).dynamicTypeSize(.accessibility5)
        case "radarModesDots":   // „Nur Punkte“, Groß, Gruppen aus
            RadarView(preset: .modesDots)
        case "radarModesFilter":   // „Filter & Darstellung“: Schnellwahl, Verkehrsmittel, Zugart
            RadarView(preset: .modesFilter)
        case "radarModesFilterLines":   // Linie, Betreiber, Verspätung
            RadarView(preset: .modesFilterLines)
        case "radarModesDisplay":   // the Darstellung page with its preview
            RadarView(preset: .modesDisplay)
        case "radarModesEmpty":   // a filter that matches nothing
            RadarView(preset: .modesEmpty)
        default:   // radarModesCity: Wien with all five modes, the counts line
            RadarView(preset: .modesCity)
        }
    }
}
