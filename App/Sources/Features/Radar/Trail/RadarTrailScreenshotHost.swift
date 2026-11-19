import SwiftUI
import MapKit
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
        case .city:   // Wien close up with every mode, „Alle im Ausschnitt“, five minutes
            RadarView(preset: .modesCity)
        case .sheet:   // the trip sheet of REX 92 with the rising delay line
            RadarTrailSheetShot()
        case .ax5:   // the three lines under the status card at the largest text size (on the radar they sit under the AX5 status card)
            RadarTrailNotesShot().dynamicTypeSize(.accessibility5)
        case .sheetAX5:   // the trip sheet's row at the largest text size (in the sheet it sits under the AX5 buttons)
            RadarTrailRowShot().dynamicTypeSize(.accessibility5)
        case .settings:   // the section „Spuren“ as it ends the Darstellung page
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
    private let vehicle: RadarVehicle

    init() {
        let now = Date()
        vehicle = DemoScotty.vehicles(now: now).first { $0.tripID == RadarTrailDemo.followedTrip } ?? DemoScotty.vehicles(now: now)[0]
        RadarTrailDemo.prepareSheet(now: now)   // before the sheet asks for its details
    }

    var body: some View {
        RadarTripSheet(vehicle: vehicle, radar2: parts)
            .task { RadarTrailDemo.fill(parts.trail, now: Date()) }
    }
}

/// The trip sheet's row alone, on the sheet's background.
private struct RadarTrailRowShot: View {
    @State private var parts = Radar2Parts()
    private let vehicle = DemoScotty.vehicles(now: Date()).first { $0.tripID == RadarTrailDemo.followedTrip } ?? DemoScotty.vehicles(now: Date())[0]

    var body: some View {
        NavigationStack {
            ScrollView {
                RadarTrailDelayRow(vehicle: vehicle, trail: parts.trail)
                    .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle("Fahrt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { RadarTrailDemo.fill(parts.trail, now: Date()) }
    }
}

/// The caption, the „zu viele“ note and „Spuren gibt es nur bei „Jetzt““ over the Westbahn, as the radar shows them under its status card.
private struct RadarTrailNotesShot: View {
    private let since = Date().addingTimeInterval(-600)

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: RadarTrailDemo.westbahnCentre.clCoordinate,
                                                        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 1.6))))
            .mapStyle(RadarMapStyle.standard.style)
            .overlay {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        RadarTrailNoteView(note: .caption(since: since))
                        RadarTrailNoteView(note: .limited(.tooWide, since: since))
                        RadarTrailNoteView(note: .onlyNow)
                    }
                    .padding(.horizontal, Theme.Spacing.cardGutter)
                    .padding(.vertical, Theme.Spacing.xl)
                }
            }
    }
}

/// „Spuren“ in the sheet's chrome, as the section that ends the Darstellung page (the CI scene cannot scroll a sheet's form to its end).
private struct RadarTrailSettingsShot: View {
    @State private var parts = Radar2Parts()

    var body: some View {
        NavigationStack {
            Form { RadarTrailSettingsSection(trail: parts.trail) }
                .scrollContentBackground(.hidden)
                .background(Theme.sheetBackground)
                .navigationTitle(RadarModesText.sheetTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
