import XCTest

/// Launch time of the app in perf mode (demo year, in-memory store). XCTest's launch metric reports nothing on the
/// simulator; the app records every launch itself (first frame since process start / App.init, LaunchTrace marks,
/// the first 4 s of frames) – these launches feed scripts/perf_summary.py.
final class LaunchPerfTests: XCTestCase {
    @MainActor
    func testLaunch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 4
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            let app = PerfApp.make()
            app.launch()
            // Give the app its launch window (PerfFrameMonitor measures 4 s of frames after the first one).
            Thread.sleep(forTimeInterval: 5)
        }
    }
}

/// Scroll hitches per screen with the regular demo year (79 trips).
final class ScrollPerfTests: PerfTestCase {
    @MainActor
    func testScrollOverview() {
        measureScroll(open(.overview))
    }

    @MainActor
    func testScrollTrips() {
        measureScroll(open(.trips), swipes: 3)
    }

    @MainActor
    func testScrollStatistics() {
        measureScroll(open(.stats))
    }

    @MainActor
    func testScrollTicket() {
        measureScroll(open(.ticket))
    }

    @MainActor
    func testTabSwitching() {
        measureTabTour()
    }
}

/// The Gipfelbuch sheet, opened by the app itself after launch (`-KBPerfPresent gipfelbuch`) – no hunting for its
/// entry point through the statistics.
final class GipfelbuchPerfTests: PerfTestCase {
    override var present: String? { "gipfelbuch" }

    @MainActor
    func testScrollGipfelbuch() {
        measureScroll(open(.gipfelbuch))
    }
}

/// The same screens with a heavy commuter's history (demo year + 1 500 trips) – shows how the screens scale.
final class HeavyDataPerfTests: PerfTestCase {
    override var extraTrips: Int { 1_500 }

    @MainActor
    func testScrollOverviewHeavy() {
        measureScroll(open(.overview))
    }

    @MainActor
    func testScrollTripsHeavy() {
        measureScroll(open(.trips), swipes: 3)
    }

    @MainActor
    func testScrollStatisticsHeavy() {
        measureScroll(open(.stats))
    }

    @MainActor
    func testScrollTicketHeavy() {
        measureScroll(open(.ticket))
    }

    @MainActor
    func testTabSwitchingHeavy() {
        measureTabTour()
    }
}
