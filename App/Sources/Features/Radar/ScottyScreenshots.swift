import SwiftUI
import KlimaCore

// MARK: scotty – CI screenshot hosts for Zug-Radar, Störungen and Live verfolgen (demo data, no network).

struct ScottyScreenshotHost: View {
    static let screens: Set<String> = ["radar", "radarTrip", "radarFilter", "radarSearch", "radarCluster",
                                       "radarAll", "radarAllZoom",   // MARK: radarall
                                       "disruptions", "disruptionDetail", "liveFollow"]

    let screen: String

    var body: some View {
        switch screen {
        case "radar":
            RadarView()
        case "radarFilter":   // MARK: radar – the filter sheet open over the map
            RadarView(preset: .filter)
        case "radarSearch":   // MARK: radar – search with suggestions for "RJX"
            RadarView(preset: .search)
        case "radarCluster":  // MARK: radar – zoomed out: clusters with counts
            RadarView(preset: .cluster)
        case "radarAll":      // MARK: radarall – about 1500 synthetic trains, Austria-wide: clusters with counts
            RadarView(preset: .allTrains)
        case "radarAllZoom":  // MARK: radarall – the same trains zoomed to eastern Austria: single trains and small clusters
            RadarView(preset: .allTrainsZoom)
        case "radarTrip":
            RadarTripSheet(vehicle: DemoScotty.vehicles(now: Date())[0])
        case "disruptions":
            DisruptionsView()
        case "disruptionDetail":
            NavigationStack { DisruptionDetailView(remark: DemoScotty.disruptions(now: Date())[1]) }
        default:
            ScottyFollowShot()
        }
    }
}

/// Starts the demo follow of the first demo run and shows its stop list.
private struct ScottyFollowShot: View {
    @Environment(AppState.self) private var app

    var body: some View {
        LiveFollowDetailSheet(tracker: LiveFollowTracker.shared)
            .task {
                guard LiveFollowTracker.shared.target == nil,
                      let target = DemoScotty.vehicles(now: Date()).first?.followTarget else { return }
                LiveFollowTracker.shared.start(target, live: app.live)
            }
    }
}
