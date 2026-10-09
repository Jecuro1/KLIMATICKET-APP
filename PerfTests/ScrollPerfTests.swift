import XCTest

/// Launch time of the app in perf mode (demo year, in-memory store).
final class LaunchPerfTests: XCTestCase {
    @MainActor
    func testLaunch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            PerfApp.make().launch()
        }
    }
}

/// Scroll hitches per screen with the regular demo year (79 trips).
final class ScrollPerfTests: PerfTestCase {
    @MainActor
    func testScrollOverview() {
        selectTab("Übersicht")
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testScrollTrips() {
        selectTab("Fahrten")
        measureScroll(mainScrollContainer(), swipes: 3)
    }

    @MainActor
    func testScrollStatistics() {
        selectTab("Statistik")
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testScrollTicket() {
        selectTab("Ticket")
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testScrollGipfelbuch() {
        openGipfelbuch()
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testTabSwitching() {
        measureTabTour()
    }
}

/// The same screens with a heavy commuter's history (demo year + 1 500 trips) – shows how the screens scale.
final class HeavyDataPerfTests: PerfTestCase {
    override var extraTrips: Int { 1_500 }

    @MainActor
    func testScrollOverviewHeavy() {
        selectTab("Übersicht")
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testScrollTripsHeavy() {
        selectTab("Fahrten")
        measureScroll(mainScrollContainer(), swipes: 3)
    }

    @MainActor
    func testScrollStatisticsHeavy() {
        selectTab("Statistik")
        measureScroll(mainScrollContainer())
    }

    @MainActor
    func testTabSwitchingHeavy() {
        measureTabTour()
    }
}
