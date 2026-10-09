import XCTest

/// Shared setup of the KlimaBilanz performance tests (UI tests in the simulator, Release build).
///
/// The app runs in perf mode (`-KBPerf YES -KBDemo YES`, `LaunchMode.isPerf`): the normal tab interface with the demo
/// year in an in-memory store, no network, no sync, no permission prompts, no break-even celebration – but with all
/// animations (unlike the screenshot mode). `-KBPerfTrips <n>` adds n synthetic trips.
///
/// The numbers that matter come from the app itself (`PerfFrameMonitor`: hitch ratio per screen, transitions, memory –
/// the simulator reports no hitch metrics to XCTest); these tests drive the app and keep XCTest's own clock / CPU /
/// memory metrics. The screens' scroll views carry accessibility identifiers (`PerfScreen.scrollID`), so no test
/// depends on the layout of a screen.
enum PerfApp {
    @MainActor
    static func make(extraTrips: Int = 0, present: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KBPerf", "YES", "-KBDemo", "YES"]
        if extraTrips > 0 {
            app.launchArguments += ["-KBPerfTrips", "\(extraTrips)"]
        }
        if let present {
            app.launchArguments += ["-KBPerfPresent", present]
        }
        app.launchEnvironment["TZ"] = "Europe/Vienna"
        return app
    }
}

/// A screen with its tab and the identifier of its main scroll view (set in the screen's view code).
enum PerfScreen: String {
    case overview, trips, stats, ticket, gipfelbuch

    var scrollID: String { "perf.scroll.\(rawValue)" }

    /// Tab bar button label (the Gipfelbuch is a sheet, opened via `-KBPerfPresent gipfelbuch`).
    var tab: String? {
        switch self {
        case .overview: "Übersicht"
        case .trips: "Fahrten"
        case .stats: "Statistik"
        case .ticket: "Ticket"
        case .gipfelbuch: nil
        }
    }

    static let tourTabs = ["Fahrten", "Statistik", "Ticket", "Übersicht"]
}

/// XCUIApplication & co. are main-actor isolated; XCTest calls setUp/tests/tearDown on the main thread.
class PerfTestCase: XCTestCase {
    var app: XCUIApplication!

    /// Synthetic trips on top of the demo year (subclasses override).
    var extraTrips: Int { 0 }

    /// `-KBPerfPresent` value for the launch (subclasses override).
    var present: String? { nil }

    /// Iterations per measurement.
    var iterations: Int { 4 }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let trips = extraTrips
        let present = present
        let launched = MainActor.assumeIsolated { () -> XCUIApplication in
            let app = PerfApp.make(extraTrips: trips, present: present)
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90), "Die Tab-Leiste ist nicht erschienen")
            return app
        }
        app = launched
        settle(2)
    }

    override func tearDownWithError() throws {
        let running = app
        app = nil
        MainActor.assumeIsolated { running?.terminate() }
    }

    func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    func selectTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.tabBars.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Tab „\(title)“ fehlt", file: file, line: line)
        button.tap()
        settle(1.5)
    }

    /// Opens `screen` and returns its main scroll view, found by accessibility identifier. Waits up to 90 s: with
    /// +1 500 trips the first build of a tab blocks the main thread for seconds (that is what is measured).
    @MainActor
    func open(_ screen: PerfScreen, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if let tab = screen.tab { selectTab(tab, file: file, line: line) }
        let byID = app.descendants(matching: .any).matching(identifier: screen.scrollID).firstMatch
        XCTAssertTrue(byID.waitForExistence(timeout: 90), "Scrollbereich „\(screen.scrollID)“ fehlt", file: file, line: line)
        dismissOverlays()
        let deadline = Date().addingTimeInterval(20)
        while !byID.isHittable, Date() < deadline { settle(0.5) }
        XCTAssertTrue(byID.isHittable, "Scrollbereich „\(screen.scrollID)“ ist verdeckt", file: file, line: line)
        settle(1)
        return byID
    }

    /// Full-screen moments that would cover the screen (perf mode suppresses them – this is the safety net).
    @MainActor
    func dismissOverlays() {
        let celebration = app.buttons["Weiter so"]
        if celebration.exists, celebration.isHittable { celebration.tap(); settle(1) }
    }

    /// Fast flicks over the scroll view's frame, resolved once – the gestures go to fixed screen coordinates, so no
    /// accessibility query of the (large) hierarchy runs between them. Per iteration `swipes` flicks down (measured),
    /// then the same number back up (not measured), so every iteration starts at the top. The hitch numbers come from
    /// the app's PerfFrameMonitor; XCTest's own scroll metrics only report durations on the simulator.
    @MainActor
    func measureScroll(_ element: XCUIElement, swipes: Int = 2) {
        let frame = element.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * fraction))
        }
        let low = point(0.78)
        let high = point(0.22)
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = iterations
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTOSSignpostMetric.scrollDecelerationMetric],
                options: options) {
            // Every gesture waits until the app is idle again, i.e. until the deceleration has ended.
            for _ in 0..<swipes {
                low.press(forDuration: 0.02, thenDragTo: high, withVelocity: .fast, thenHoldForDuration: 0)
            }
            self.stopMeasuring()
            for _ in 0..<swipes {
                high.press(forDuration: 0.02, thenDragTo: low, withVelocity: .fast, thenHoldForDuration: 0)
            }
        }
    }

    /// Wall clock, CPU and memory of one round through all tabs (transition timings: PerfFrameMonitor).
    @MainActor
    func measureTabTour() {
        let buttons = PerfScreen.tourTabs.map { app.tabBars.buttons[$0] }
        for button in buttons { XCTAssertTrue(button.waitForExistence(timeout: 20)) }
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for button in buttons {
                button.tap()
                self.settle(0.8)
            }
        }
    }
}
