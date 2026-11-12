import XCTest
@testable import KlimaCore

/// The sparkline's memory (docs/RADAR_HEATMAP.md §6): in memory only, one point per half minute, a trend only with a stretch of time.
final class HeatHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)

    private func summary(onTime: Int, late: Int) -> HeatSummary {
        var s = HeatSummary()
        s.onTime = onTime
        s.delayed = late
        s.total = onTime + late
        return s
    }

    func testOnePointAtMostEveryThirtySeconds() {
        var history = HeatHistory()
        history.record(summary(onTime: 80, late: 20), at: t0)
        history.record(summary(onTime: 80, late: 20), at: t0.addingTimeInterval(20))
        XCTAssertEqual(history.points.count, 1)
        history.record(summary(onTime: 80, late: 20), at: t0.addingTimeInterval(30))
        XCTAssertEqual(history.points.count, 2)
    }

    func testNothingIsRecordedWithoutEnoughRealtimeData() {
        var history = HeatHistory()
        history.record(HeatSummary(), at: t0)
        var few = HeatSummary()
        few.onTime = HeatHistory.minimumBase - 1
        history.record(few, at: t0.addingTimeInterval(60))
        XCTAssertTrue(history.points.isEmpty)
        var onlyNoData = HeatSummary()
        onlyNoData.noRealtime = 400
        history.record(onlyNoData, at: t0.addingTimeInterval(120))
        XCTAssertTrue(history.points.isEmpty, "trains without realtime data say nothing about punctuality")
    }

    func testTheClockGoingBackIgnoresThePoint() {
        var history = HeatHistory()
        history.record(summary(onTime: 80, late: 20), at: t0)
        history.record(summary(onTime: 50, late: 50), at: t0.addingTimeInterval(-600))
        XCTAssertEqual(history.points.count, 1)
    }

    func testTheNewestPointsAreKept() {
        var history = HeatHistory()
        for index in 0..<(HeatHistory.capacity + 30) {
            history.record(summary(onTime: 80, late: 20), at: t0.addingTimeInterval(Double(index) * 30))
        }
        XCTAssertEqual(history.points.count, HeatHistory.capacity)
        XCTAssertEqual(history.points.last?.at, t0.addingTimeInterval(Double(HeatHistory.capacity + 29) * 30))
    }

    func testATrendNeedsThreePointsOverAMinute() {
        var history = HeatHistory()
        XCTAssertFalse(history.hasTrend)
        XCTAssertNil(history.caption)
        history.record(summary(onTime: 80, late: 20), at: t0)
        history.record(summary(onTime: 85, late: 15), at: t0.addingTimeInterval(30))
        history.record(summary(onTime: 90, late: 10), at: t0.addingTimeInterval(60))
        XCTAssertTrue(history.hasTrend)
        XCTAssertEqual(history.span, 60)
        XCTAssertEqual(history.caption, "Seit 1 Min: 80 % → 90 %")
        history.record(summary(onTime: 90, late: 10), at: t0.addingTimeInterval(360))
        XCTAssertEqual(history.caption, "Seit 6 Min: 80 % → 90 %")
    }

    func testTheCaptionNeverSaysAHundredWhileATrainIsLate() {
        var history = HeatHistory()
        for index in 0..<3 { history.record(summary(onTime: 999, late: 1), at: t0.addingTimeInterval(Double(index) * 30)) }
        XCTAssertEqual(history.caption, "Seit 1 Min unverändert bei 99 %")
    }

    func testResetEmptiesTheSession() {
        var history = HeatHistory()
        history.record(summary(onTime: 80, late: 20), at: t0)
        history.reset()
        XCTAssertTrue(history.points.isEmpty)
        XCTAssertEqual(history.span, 0)
    }
}
