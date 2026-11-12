import XCTest

/// The feature screens behind the Scotty replacement: Fahrplan, Verbindungen, Verbindungsdetail, Zug-Radar (mit Ebenen),
/// Atlas, Meine Routen and Haltestellen-Detail, with the demo year (79 trips) and the demo timetable – never the network.
///
/// The app opens each screen itself after the first frame (`-KBPerfPresent <name>`, `PerfFeature` in
/// App/Sources/Services/Diagnostics/PerfFeatureScreens.swift), so no accessibility identifier is needed in these screens:
/// the tests flick or drag over the window. `PerfFrameMonitor` records what happens under the name of the screen
/// (hitch time ratio of the scroll or pan, first frame and hitches of the presentation, memory).
enum PerfFeatureScreen: String {
    case planner, plannerResults, plannerDetail, radar, radarLayers, atlas, routes, stop

    /// Seconds from the launch until the screen is built, and a map's tiles and pins are in.
    var settle: TimeInterval {
        switch self {
        case .planner: 4
        case .plannerResults, .plannerDetail: 10
        case .radar, .radarLayers, .atlas: 9
        case .routes: 6
        case .stop: 10
        }
    }

    /// Maps pan; everything else scrolls.
    var isMap: Bool { self == .radar || self == .radarLayers || self == .atlas }
}

class FeaturePerfTestCase: PerfTestCase {
    var screen: PerfFeatureScreen { .planner }

    override var present: String? { screen.rawValue }
    override var requiresTabBar: Bool { screen == .planner || screen == .plannerResults || screen == .plannerDetail }
    override var launchSettle: TimeInterval { screen.settle }

    /// Drags over the whole window (the screen has no identifier) while XCTest takes clock and memory. The numbers that
    /// matter come from the app: `PerfFrameMonitor` times the drags as `touch` (a scroll view moving, or – on a map,
    /// where none moves – a pan seen by its window-level observer) and the screen's presentation as a transition. XCTest's
    /// own scroll metrics are not used: they need scroll signposts, which a map or a short list never emits, and on the
    /// simulator they report durations only.
    @MainActor
    func measureFeature(drags: Int = 3) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "Kein Fenster")
        let frame = window.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.minX + frame.width * dx, dy: frame.minY + frame.height * dy))
        }
        // Lists: vertical flicks, down and back; maps: diagonal drags there and back.
        let from = screen.isMap ? point(0.75, 0.55) : point(0.5, 0.78)
        let to = screen.isMap ? point(0.25, 0.4) : point(0.5, 0.22)
        let velocity: XCUIGestureVelocity = screen.isMap ? .default : .fast
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<drags {
                from.press(forDuration: 0.02, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0.3)
            }
            for _ in 0..<drags {
                to.press(forDuration: 0.02, thenDragTo: from, withVelocity: velocity, thenHoldForDuration: 0.3)
            }
        }
    }
}

final class PlannerPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .planner }

    @MainActor
    func testFeaturePlanner() {
        measureFeature()
    }
}

final class PlannerResultsPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .plannerResults }

    @MainActor
    func testFeaturePlannerResults() {
        measureFeature(drags: 4)
    }
}

final class PlannerDetailPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .plannerDetail }

    @MainActor
    func testFeaturePlannerDetail() {
        measureFeature()
    }
}

final class RadarPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .radar }

    @MainActor
    func testFeatureRadar() {
        measureFeature()
    }
}

final class RadarLayersPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .radarLayers }

    @MainActor
    func testFeatureRadarLayers() {
        measureFeature()
    }
}

final class AtlasPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .atlas }

    @MainActor
    func testFeatureAtlas() {
        measureFeature()
    }
}

final class RoutesPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .routes }

    @MainActor
    func testFeatureRoutes() {
        measureFeature()
    }
}

final class StopDetailPerfTests: FeaturePerfTestCase {
    override var screen: PerfFeatureScreen { .stop }

    @MainActor
    func testFeatureStop() {
        measureFeature(drags: 4)
    }
}
