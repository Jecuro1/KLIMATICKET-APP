import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – CI screenshot scenes of „Spuren“ (docs/RADAR_TRAILS.md §9): synthetic trains and city fleets with ten synthetic minutes
// before the scene (`RadarTrailDemo`), no network, no permission prompt. The scene is set before the radar is built, so its model starts with the
// scene's setting.

struct RadarTrailScreenshotHost: View {
    static let screens = Set(RadarTrailScene.allCases.map(\.rawValue))

    let screen: String
    @Environment(AppState.self) private var app

    init(screen: String) {
        self.screen = screen
        RadarTrailDemo.scene = RadarTrailScene(rawValue: screen)
    }

    private var scene: RadarTrailScene { RadarTrailScene(rawValue: screen) ?? .westbahn }

    var body: some View {
        switch scene {
        case .westbahn, .tooMany:   // RJX 66 selected, REX 92 followed, both with trails; „Alle“ on a wide map: the note
            RadarView().task { followDemoTrain() }
        case .ax5:   // the caption at the largest text size
            RadarView().dynamicTypeSize(.accessibility5).task { followDemoTrain() }
        case .city:   // Wien close up with every mode, „Alle im Ausschnitt“, five minutes
            RadarView(preset: .modesCity)
        case .sheet:   // the trip sheet of REX 92 with the rising delay line
            RadarTrailSheetShot()
        case .sheetAX5:
            RadarTrailSheetShot().dynamicTypeSize(.accessibility5)
        case .settings:   // „Spuren“ at the end of the Darstellung page
            RadarTrailSettingsShot()
        }
    }

    /// The demo follow of REX 92 (the existing demo follow is RJX 66, the selected train: two different trails). No prompt in sandboxed launches.
    private func followDemoTrain() {
        guard LiveFollowTracker.shared.target?.tripID != RadarTrailDemo.followedTrip,
              let target = DemoScotty.vehicles(now: Date()).first(where: { $0.tripID == RadarTrailDemo.followedTrip })?.followTarget else { return }
        LiveFollowTracker.shared.start(target, live: app.live)
    }
}

/// The trip sheet over its own parts, filled with the demo history and one answer now.
private struct RadarTrailSheetShot: View {
    @State private var parts = Radar2Parts()
    private let vehicle = DemoScotty.vehicles(now: Date()).first { $0.tripID == RadarTrailDemo.followedTrip } ?? DemoScotty.vehicles(now: Date())[0]

    var body: some View {
        RadarTripSheet(vehicle: vehicle, radar2: parts)
            .task { RadarTrailDemo.fill(parts.trail, now: Date()) }
    }
}

/// „Filter & Darstellung“ on its Darstellung page, scrolled to its end where „Spuren“ sits.
private struct RadarTrailSettingsShot: View {
    @State private var parts = Radar2Parts()
    @State private var filter = RadarFilter()
    @State private var modes = RadarModeSelection.default
    @State private var display = RadarDisplay.standard

    var body: some View {
        RadarFilterSheet(filter: $filter, modes: $modes, display: $display, vehicles: [],
                         counts: RadarModeCounts(productClasses: [], shownModes: modes.ordered), parts: parts, page: .display)
            .defaultScrollAnchor(.bottom)
    }
}
