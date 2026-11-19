import XCTest
@testable import KlimaCore

/// „Verspätung, seit du zuschaust“: built from the answers this iPhone got, shown only with enough of them (docs/RADAR_TRAILS.md §5).
final class RadarDelaySeriesTests: XCTestCase {
    private typealias F = TrailFixture

    private func series(_ values: [(seconds: Double, minutes: Int?)], cancelledAt: Double? = nil) -> RadarDelaySeries {
        var samples = values.map { RadarTrailSample(from: F.at($0.seconds), coordinate: F.base, delaySeconds: $0.minutes.map { $0 * 60 }) }
        if let cancelledAt {
            samples.append(RadarTrailSample(from: F.at(cancelledAt), coordinate: F.base, delaySeconds: 600, isCancelled: true))
        }
        return RadarDelaySeries(samples: samples)
    }

    func testTooFewOrTooShortIsNotShowable() {
        XCTAssertFalse(series([(0, 3), (60, 4)]).isShowable, "two moments")
        XCTAssertFalse(series([(0, 3), (50, 4), (100, 5)]).isShowable, "three moments over 100 s")
        XCTAssertTrue(series([(0, 3), (60, 4), (120, 5)]).isShowable, "three moments over two minutes")
    }

    func testEqualNeighboursAreMergedButKeepTheirStretch() {
        let s = series([(0, 2), (20, 2), (40, 2), (60, 2), (80, 5)])
        XCTAssertEqual(s.points, [.init(at: F.at(0), minutes: 2), .init(at: F.at(60), minutes: 2), .init(at: F.at(80), minutes: 5)])
        XCTAssertEqual(s.moments, 5)
    }

    func testAStandCountsItsFirstAndItsLastAnswer() {
        let stand = RadarTrailSample(from: F.at(0), to: F.at(200), coordinate: F.base, delaySeconds: 240)
        let s = RadarDelaySeries(samples: [stand, RadarTrailSample(from: F.at(220), coordinate: F.base, delaySeconds: 240)])
        XCTAssertEqual(s.moments, 3)
        XCTAssertTrue(s.isShowable)
        XCTAssertEqual(s.points.count, 2)
    }

    func testTrendThresholdsAtTwoMinutes() {
        XCTAssertEqual(series([(0, 3), (60, 4), (120, 5)]).trend, .rising)
        XCTAssertEqual(series([(0, 3), (60, 4), (120, 4)]).trend, .steady)
        XCTAssertEqual(series([(0, 6), (60, 5), (120, 4)]).trend, .falling)
        XCTAssertEqual(series([(0, 6), (60, 5), (120, 5)]).trend, .steady)
        XCTAssertEqual(series([(0, 5), (60, 9), (120, 6)]).trend, .steady, "the first and the last value decide, not the peak")
    }

    func testACancelledAnswerEndsTheSeries() {
        let s = series([(0, 3), (60, 3), (120, 4)], cancelledAt: 140)
        XCTAssertTrue(s.endsCancelled)
        XCTAssertEqual(s.last, 4, "the cancellation's own delay is not part of the line")
        let after = RadarDelaySeries(samples: [
            RadarTrailSample(from: F.at(0), coordinate: F.base, delaySeconds: 60, isCancelled: true),
            RadarTrailSample(from: F.at(60), coordinate: F.base, delaySeconds: 60),
        ])
        XCTAssertTrue(after.points.isEmpty)
        XCTAssertTrue(after.endsCancelled)
    }

    func testUnknownDelaysAreSkipped() {
        let s = series([(0, 3), (30, nil), (60, 3), (90, nil), (120, 5)])
        XCTAssertEqual(s.moments, 3)
        XCTAssertEqual(s.points.map(\.minutes), [3, 3, 5])
    }

    func testSecondsBecomeWholeMinutesAsTheMarkersCountThem() {
        let s = RadarDelaySeries(samples: [RadarTrailSample(from: F.at(0), coordinate: F.base, delaySeconds: 299)])
        XCTAssertEqual(s.first, 4)
        XCTAssertEqual(series([(0, 0)]).first, 0)
    }

    func testTheRowTexts() {
        XCTAssertEqual(RadarTrailText.value(series([(0, 3), (60, 4), (120, 5)])), "+3 → +5 Min · steigt")
        XCTAssertEqual(RadarTrailText.value(series([(0, 4), (60, 4), (120, 4)])), "+4 Min · gleich")
        XCTAssertEqual(RadarTrailText.value(series([(0, 6), (60, 4), (120, 2)])), "+6 → +2 Min · sinkt")
        XCTAssertEqual(RadarTrailText.value(series([(0, 0), (60, 2), (120, 5)])), "pünktlich → +5 Min · steigt")
        XCTAssertEqual(RadarTrailText.value(series([(0, 5), (60, 2), (120, 0)])), "+5 Min → pünktlich · sinkt")
        XCTAssertEqual(RadarTrailText.value(series([(0, 3), (60, 4), (120, 4)])), "+3 → +4 Min · etwa gleich")
        XCTAssertEqual(RadarTrailText.value(series([(0, 3), (60, 3), (120, 3)], cancelledAt: 130)), "+3 Min → fällt aus")
        XCTAssertEqual(RadarTrailText.value(series([(0, -1), (60, 0), (120, 2)])), "\u{2212}1 → +2 Min · steigt")
    }
}
