import SwiftUI
import KlimaCore

// MARK: scotty – CI screenshot hosts for Zug-Radar, Störungen and Live verfolgen (demo data, no network).

struct ScottyScreenshotHost: View {
    static let screens: Set<String> = ["radar", "radarTrip", "disruptions", "disruptionDetail", "liveFollow"]

    let screen: String

    var body: some View {
        switch screen {
        case "radar":
            RadarView()
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
