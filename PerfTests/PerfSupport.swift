import XCTest

/// Shared setup of the KlimaBilanz performance tests (UI tests in the simulator, Release build).
///
/// The app runs in perf mode (`-KBPerf YES -KBDemo YES`, `LaunchMode.isPerf`): the normal tab interface with the demo
/// year in an in-memory store, no network, no sync, no permission prompts – but with all animations (unlike the
/// screenshot mode). `-KBPerfTrips <n>` adds n synthetic trips.
enum PerfApp {
    @MainActor
    static func make(extraTrips: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KBPerf", "YES", "-KBDemo", "YES"]
        if extraTrips > 0 {
            app.launchArguments += ["-KBPerfTrips", "\(extraTrips)"]
        }
        app.launchEnvironment["TZ"] = "Europe/Vienna"
        return app
    }

    static let tabs = ["Übersicht", "Fahrten", "Statistik", "Ticket"]
}

/// XCUIApplication & co. are main-actor isolated; XCTest calls setUp/tests/tearDown on the main thread.
class PerfTestCase: XCTestCase {
    var app: XCUIApplication!

    /// Synthetic trips on top of the demo year (subclasses override).
    var extraTrips: Int { 0 }

    /// Iterations per measurement (plus XCTest's own first run).
    var iterations: Int { 5 }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let trips = extraTrips
        let launched = MainActor.assumeIsolated { () -> XCUIApplication in
            let app = PerfApp.make(extraTrips: trips)
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60), "Die Tab-Leiste ist nicht erschienen")
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
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab „\(title)“ fehlt", file: file, line: line)
        button.tap()
        settle(1.5)
    }

    /// The screen's main vertical scroll container: the largest hittable scroll or collection view
    /// (List = collection view, ScrollView = scroll view; small horizontal chip rows are ignored).
    @MainActor
    func mainScrollContainer(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let candidates = app.collectionViews.allElementsBoundByIndex
            + app.scrollViews.allElementsBoundByIndex
            + app.tables.allElementsBoundByIndex
        let usable = candidates.filter { $0.exists && $0.isHittable && $0.frame.height > 300 }
        guard let best = usable.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            XCTFail("Kein scrollbarer Bereich gefunden", file: file, line: line)
            return app
        }
        return best
    }

    /// Hitch metrics of fast flicks: per iteration `swipes` measured flicks down the content, then the same number
    /// back up (not measured) so every iteration starts at the top.
    @MainActor
    func measureScroll(_ element: XCUIElement, swipes: Int = 2) {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = iterations
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTOSSignpostMetric.scrollDecelerationMetric],
                options: options) {
            for _ in 0..<swipes { element.swipeUp(velocity: .fast) }
            self.stopMeasuring()
            for _ in 0..<swipes { element.swipeDown(velocity: .fast) }
        }
    }

    /// Wall clock, CPU and memory of one round through all tabs.
    @MainActor
    func measureTabTour() {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for tab in ["Fahrten", "Statistik", "Ticket", "Übersicht"] {
                self.app.tabBars.buttons[tab].tap()
            }
        }
    }

    /// Scrolls the statistics tab down to the Gipfelbuch row and opens the sheet.
    @MainActor
    func openGipfelbuch(file: StaticString = #filePath, line: UInt = #line) {
        selectTab("Statistik", file: file, line: line)
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gipfelbuch")).firstMatch
        let scroll = mainScrollContainer(file: file, line: line)
        var attempts = 0
        while !(entry.exists && entry.isHittable), attempts < 15 {
            scroll.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(entry.isHittable, "Gipfelbuch-Eintrag nicht gefunden", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.staticTexts["Gipfelbuch"].waitForExistence(timeout: 10), "Gipfelbuch öffnet nicht", file: file, line: line)
        settle(2)
    }
}
