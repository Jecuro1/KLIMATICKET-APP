import SwiftUI
import SwiftData
import Observation
import KlimaCore

/// Feature screens of the performance runs: `-KBPerfPresent <name>` (the XCUITests, `PerfTests/FeaturePerfTests.swift`)
/// and `-KBPerfTour <name>` (the profiler, scripts/perf_profile.sh) open them through `PerfTour`. Perf mode only: demo
/// data, in-memory store, no network (the timetable is the demo timetable, `LaunchMode.isSandboxed`).
///
/// No accessibility identifiers are needed in the screens: the app presents them itself, the tests flick over the window,
/// and `PerfFrameMonitor` names what it measures after `PerfFeature.title` (breadcrumb + transition).
enum PerfFeature: String, CaseIterable {
    /// The Fahrplan tab (search form, „Deine Strecken“, „In der Nähe“).
    case planner
    /// A search Innsbruck → Lech, pushed on the Fahrplan stack: the result list.
    case plannerResults
    /// A search Innsbruck → Bregenz via Landeck-Zams and Feldkirch: the detail of the first connection.
    case plannerDetail
    /// Zug-Radar with the demo vehicles.
    case radar
    /// The same map with every layer on (stations, routes, disruptions) – the most annotations the map shows.
    case radarLayers
    /// Zug-Radar with about 1500 synthetic vehicles, Austria-wide (docs/OEBB_LIVE.md §R11): the markers are clusters, a
    /// thousand vehicles still make fewer than 130 annotations.
    case radarAll
    /// MARK: radarheat – the Pünktlichkeit layer (docs/RADAR_HEATMAP.md): about 900 synthetic trains, the heat cells as map overlays (at most 900),
    /// trains as dots, the summary panel.
    case radarHeat
    /// The Atlas (map of the trips) with the excursion demo year.
    case atlas
    /// „Meine Routen“.
    case routes
    /// Haltestellen-Detail of Innsbruck Hbf (lines, facilities, departures).
    case stop

    /// The name in the perf report: tab title, or the name `Diagnostics.sheet` / `Diagnostics.screen` records.
    var title: String {
        switch self {
        case .planner: AppTab.planner.title
        case .plannerResults: "Verbindungen"
        case .plannerDetail: "Verbindungsdetail"
        case .radar: "Zug-Radar"
        case .radarLayers: "Karte mit Ebenen"
        case .radarAll: "Zug-Radar, alle Züge"
        case .radarHeat: "Zug-Radar, Pünktlichkeit"
        case .atlas: "Atlas"
        case .routes: "Meine Routen"
        case .stop: "Haltestelle"
        }
    }

    /// Shown as a full-screen cover over the tabs (`PerfPresentHost`); the planner screens live inside the Fahrplan tab.
    var isCover: Bool {
        switch self {
        case .planner, .plannerResults, .plannerDetail: false
        case .radar, .radarLayers, .radarAll, .radarHeat, .atlas, .routes, .stop: true
        }
    }
}

/// Presents the feature screens. `present` returns when the screen is up (the tour measures its phases after it).
@MainActor
@Observable
final class PerfPresenter {
    static let shared = PerfPresenter()

    /// The screen the full-screen cover shows (`PerfPresentHost`).
    var cover: PerfFeature?

    static func present(_ feature: PerfFeature, app: AppState) async {
        switch feature {
        case .planner:
            app.selectedTab = .planner   // a tab switch: PerfFrameMonitor times it like any other tab
        case .plannerResults, .plannerDetail:
            await presentConnections(feature, app: app)
        case .radar, .radarLayers, .radarAll, .radarHeat, .atlas, .routes, .stop:
            PerfFrameMonitor.shared.beginPresentation(feature.title)
            Diagnostics.sheet(feature.title, presented: true)
            shared.cover = feature
        }
    }

    /// The search of the `plannerResults` / `plannerDetail` screenshots, driven through `PlannerModel` like they do.
    private static func presentConnections(_ feature: PerfFeature, app: AppState) async {
        let model = app.planner
        let stations = app.stations
        app.selectedTab = .planner
        try? await Task.sleep(for: .seconds(1.5))   // the tab's own first frames are not part of this screen
        if let innsbruck = stations.station(named: "Innsbruck Hbf") { model.origin = .station(innsbruck) }
        if feature == .plannerDetail {
            if let bregenz = stations.station(named: "Bregenz") { model.destination = .station(bregenz) }
            model.vias = ["Landeck-Zams", "Feldkirch"].compactMap { stations.station(named: $0).map { .station($0) } }
        } else if let lech = DemoPlaces.named("Lech") {
            model.destination = .live(lech)
        }
        PerfFrameMonitor.shared.beginPresentation(PerfFeature.plannerResults.title)
        Diagnostics.screen(PerfFeature.plannerResults.title, visible: true)
        model.startSearch()   // pushes the result list
        for _ in 0..<60 where model.phase != .loaded { try? await Task.sleep(for: .milliseconds(100)) }
        guard feature == .plannerDetail, let id = model.rows.first?.id else { return }
        try? await Task.sleep(for: .seconds(1.5))
        PerfFrameMonitor.shared.beginPresentation(feature.title)
        Diagnostics.screen(feature.title, visible: true)
        model.path = [.results, .detail(id)]
    }
}

extension View {
    /// `-KBPerfPresent` / `-KBPerfTour` covers (perf mode only; any other launch gets the view back unchanged).
    @ViewBuilder
    func perfPresentHost() -> some View {
        if LaunchMode.isPerf {
            modifier(PerfPresentHost())
        } else {
            self
        }
    }
}

private struct PerfPresentHost: ViewModifier {
    @State private var presenter = PerfPresenter.shared

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter
        content
            .fullScreenCover(item: $presenter.cover) { feature in
                PerfFeatureCover(feature: feature)
            }
    }
}

extension PerfFeature: Identifiable {
    var id: String { rawValue }
}

/// What a cover shows. The screens are the real ones, in the same containers the app puts them in.
private struct PerfFeatureCover: View {
    let feature: PerfFeature

    var body: some View {
        switch feature {
        case .radar:
            RadarView()
        case .radarLayers:
            RadarView(preset: .layers)
        case .radarAll:
            RadarView(preset: .allTrains)
        case .radarHeat:
            RadarView(preset: .heat)
        case .atlas:
            AtlasScreenshotScene(screen: "map")   // seeds the excursion demo year, then NavigationStack { AtlasView() }
        case .routes:
            SavedRoutesView()
        case .stop:
            PerfStopHost()
        case .planner, .plannerResults, .plannerDetail:
            EmptyView()
        }
    }
}

/// Innsbruck Hbf: the stop with the most lines and facilities in the data (docs/PLACES.md); waits for the place index.
private struct PerfStopHost: View {
    @State private var placeID: String?

    var body: some View {
        NavigationStack {
            if let placeID {
                StopDetailView(placeID: placeID)
            } else {
                ProgressView()
            }
        }
        .task {
            _ = try? await PlaceIndexLoader.shared.load()
            placeID = "at:47:1187"
        }
    }
}
