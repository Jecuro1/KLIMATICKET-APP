import XCTest
@testable import KlimaCore

final class CockpitSpeedTests: XCTestCase {
    typealias F = CockpitFixtures

    /// A point `km` east of 14.0 E on the test line.
    private func east(_ km: Double) -> GeoPoint { F.point(14.0 + km / 74.5) }

    func testUnknownBeforeTwoAnswers() {
        var estimator = CockpitSpeedEstimator()
        XCTAssertEqual(estimator.reading(now: F.t0), .unknown)
        estimator.add(coordinate: east(0), at: F.t0)
        XCTAssertEqual(estimator.reading(now: F.t0), .unknown)
    }

    func testTwoAnswersGiveASpeed() throws {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))
        // 700 m in 20 s: 126 km/h.
        let kmh = try XCTUnwrap(estimator.reading(now: F.t0.addingTimeInterval(21)).kmh)
        XCTAssertEqual(kmh, 126, accuracy: 3)
    }

    func testSmoothingMovesTowardsTheNewSpeed() throws {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))                    // 126 km/h
        estimator.add(coordinate: east(0.7 + 0.5), at: F.t0.addingTimeInterval(40))              // 90 km/h
        let kmh = try XCTUnwrap(estimator.reading(now: F.t0.addingTimeInterval(41)).kmh)
        XCTAssertLessThan(kmh, 126)
        XCTAssertGreaterThan(kmh, 90, "smoothed: not the last segment alone")
        for step in 3..<14 {
            estimator.add(coordinate: east(0.7 + 0.5 * Double(step - 1)), at: F.t0.addingTimeInterval(Double(step) * 20))
        }
        XCTAssertEqual(try XCTUnwrap(estimator.reading(now: F.t0.addingTimeInterval(14 * 20 - 19)).kmh), 90, accuracy: 3)
    }

    func testStandingWhenThePositionDoesNotMove() {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(5), at: F.t0)
        estimator.add(coordinate: east(5), at: F.t0.addingTimeInterval(20))
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(25)), .standing)
        XCTAssertNil(estimator.reading(now: F.t0.addingTimeInterval(25)).kmh)
    }

    func testADepartureStartsFreshAfterAStop() throws {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))   // 126
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(40))   // stands
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(41)), .standing)
        estimator.add(coordinate: east(0.7 + 0.2), at: F.t0.addingTimeInterval(60))   // 36 km/h: not averaged with the 126 before the stop
        XCTAssertEqual(try XCTUnwrap(estimator.reading(now: F.t0.addingTimeInterval(61)).kmh), 36, accuracy: 2)
    }

    func testStaleAfterNinetySeconds() {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))
        XCTAssertNotNil(estimator.reading(now: F.t0.addingTimeInterval(20 + 89)).kmh)
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(20 + 91)), .unknown)
    }

    func testALongGapRestartsTheEstimate() {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))
        estimator.add(coordinate: east(30), at: F.t0.addingTimeInterval(20 + 200))   // 200 s later: not one train moving evenly
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(221)), .unknown)
    }

    func testAJumpIsNotASpeed() {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(40), at: F.t0.addingTimeInterval(20))   // 7200 km/h
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(21)), .unknown)
    }

    func testTheSameAnswerTwiceChangesNothing() throws {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0)
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))
        let before = estimator.reading(now: F.t0.addingTimeInterval(21))
        estimator.add(coordinate: east(0.7), at: F.t0.addingTimeInterval(20))
        estimator.add(coordinate: east(0.71), at: F.t0.addingTimeInterval(21))   // 1 s later: below the minimum segment
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(21)), before)
    }

    func testAnOlderAnswerIsIgnored() {
        var estimator = CockpitSpeedEstimator()
        estimator.add(coordinate: east(0), at: F.t0.addingTimeInterval(20))
        estimator.add(coordinate: east(5), at: F.t0)   // arrived late: it is older than what we have
        XCTAssertEqual(estimator.reading(now: F.t0.addingTimeInterval(21)), .unknown)
    }

    func testRouteKilometresBeatTheStraightLineOnACurve() throws {
        var estimator = CockpitSpeedEstimator()
        // Two positions 600 m apart in a straight line, but 700 m apart along the route.
        estimator.add(coordinate: east(0), km: 10.0, at: F.t0)
        estimator.add(coordinate: east(0.6), km: 10.7, at: F.t0.addingTimeInterval(20))
        XCTAssertEqual(try XCTUnwrap(estimator.reading(now: F.t0.addingTimeInterval(21)).kmh), 126, accuracy: 1)
    }
}
