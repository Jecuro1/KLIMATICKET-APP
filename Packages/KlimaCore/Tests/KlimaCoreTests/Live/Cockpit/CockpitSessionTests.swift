import XCTest
@testable import KlimaCore

final class CockpitSessionTests: XCTestCase {
    typealias F = CockpitFixtures

    private func at(_ seconds: Double) -> Date { F.t0.addingTimeInterval(seconds) }

    func testStartsWaitingAndGoesLiveWithThePosition() {
        var session = CockpitSession(startedAt: F.t0)
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.mode, .follow)
        session.answer(at: at(2), hasPosition: true)
        XCTAssertEqual(session.state, .following)
        XCTAssertEqual(session.lastPositionAt, at(2))
    }

    func testAnAnswerWithoutTheTrainDoesNotMakeItLive() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(2), hasPosition: false)
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(session.lastAnswerAt, at(2))
        XCTAssertNil(session.lastPositionAt)
    }

    func testLostAfterTwoMinutesWithoutAPosition() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(1 + 119), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .following)
        session.tick(now: at(1 + 120), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost)
    }

    func testLostFromWaitingWhenNothingEverComes() {
        var session = CockpitSession(startedAt: F.t0)
        session.tick(now: at(119), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .waiting)
        session.tick(now: at(120), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost)
    }

    func testAPositionBringsItBack() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(200), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost)
        // Answers without the train do not end it ...
        session.answer(at: at(210), hasPosition: false)
        XCTAssertEqual(session.state, .lost)
        // ... a position does.
        session.answer(at: at(220), hasPosition: true)
        XCTAssertEqual(session.state, .following)
        session.tick(now: at(221), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .following)
    }

    func testWhyItIsLost() {
        var session = CockpitSession(startedAt: F.t0)
        XCTAssertNil(session.lostReason(now: at(10)), "not lost yet")
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(200), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.lostReason(now: at(200)), .noAnswers, "the last answer is old: the requests fail")
        session.answer(at: at(195), hasPosition: false)
        XCTAssertEqual(session.lostReason(now: at(200)), .notListed, "answers come, without the train")
        XCTAssertEqual(session.lostReason(now: at(300)), .noAnswers, "and then they stop")
    }

    func testEndsAtTheLastStop() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(2), atLastStop: true, scheduleEnd: at(3))
        XCTAssertEqual(session.state, .ended)
        XCTAssertFalse(session.offersReturn)
    }

    func testEndsWhenTheScheduleIsLongOver() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(299), atLastStop: false, scheduleEnd: at(0))
        XCTAssertNotEqual(session.state, .ended)
        session.tick(now: at(300), atLastStop: false, scheduleEnd: at(0))
        XCTAssertEqual(session.state, .ended)
    }

    func testEndedIsFinal() {
        var session = CockpitSession(startedAt: F.t0)
        session.tick(now: at(1), atLastStop: true, scheduleEnd: nil)
        session.answer(at: at(5), hasPosition: true)
        session.tick(now: at(6), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .ended)
    }

    func testEndedWinsOverLostAndLostOverFree() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.userMovedMap()
        XCTAssertEqual(session.state, .free)
        session.tick(now: at(200), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost, "the banner matters more than how the camera is held")
        XCTAssertTrue(session.offersReturn, "the way back to the train stays")
        session.tick(now: at(201), atLastStop: true, scheduleEnd: nil)
        XCTAssertEqual(session.state, .ended)
    }

    // MARK: Camera mode

    func testUserMoveMakesItFreeAndReturnRestoresTheMode() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.select(.bird)
        XCTAssertEqual(session.mode, .bird)
        session.userMovedMap()
        XCTAssertEqual(session.mode, .free)
        XCTAssertEqual(session.state, .free)
        XCTAssertTrue(session.offersReturn)
        session.returnToTrain()
        XCTAssertEqual(session.mode, .bird)
        XCTAssertEqual(session.state, .following)
        XCTAssertFalse(session.offersReturn)
    }

    func testMovingTheMapTwiceKeepsTheModeToReturnTo() {
        var session = CockpitSession(startedAt: F.t0)
        session.userMovedMap()
        session.userMovedMap()
        session.returnToTrain()
        XCTAssertEqual(session.mode, .follow)
    }

    func testSwitcherChoosingFreeKeepsTheDrivenMode() {
        var session = CockpitSession(startedAt: F.t0, mode: .bird)
        session.select(.free)
        XCTAssertEqual(session.mode, .free)
        session.returnToTrain()
        XCTAssertEqual(session.mode, .bird)
    }

    func testStartMode() {
        XCTAssertEqual(CockpitSession(startedAt: F.t0, mode: .bird).mode, .bird)
        var free = CockpitSession(startedAt: F.t0, mode: .free)
        XCTAssertEqual(free.state, .free)
        free.returnToTrain()
        XCTAssertEqual(free.mode, .follow, "free has no driven mode of its own: back to follow")
    }

    func testAnOlderAnswerDoesNotMoveTheClockBack() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(50), hasPosition: true)
        session.answer(at: at(10), hasPosition: true)
        XCTAssertEqual(session.lastPositionAt, at(50))
        XCTAssertEqual(session.lastAnswerAt, at(50))
    }

    // MARK: Review 2: the two minutes count only while the cockpit asks

    func testTimeInTheBackgroundDoesNotMakeTheTrainLost() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        // Five minutes in the background: nothing was asked. Back in the foreground the clock of "lost" starts again.
        session.pauseLostClock(at: at(301))
        session.tick(now: at(302), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .following, "no request went out: no sign that the train is gone, and no 'Keine Verbindung zu ÖBB'")
        session.tick(now: at(301 + 119), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .following)
        session.tick(now: at(301 + 120), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost, "two minutes of asking without a position")
    }

    func testWhileNotAskingTheTrainIsNeverLost() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        // Low Power Mode: the loop pauses the clock on every step while it does not ask.
        for second in stride(from: 2.0, through: 600, by: 1) {
            session.pauseLostClock(at: at(second))
            session.tick(now: at(second), atLastStop: false, scheduleEnd: nil)
        }
        XCTAssertEqual(session.state, .following)
    }

    func testAPauseDoesNotEndALostState() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.tick(now: at(130), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost)
        session.pauseLostClock(at: at(400))
        session.tick(now: at(401), atLastStop: false, scheduleEnd: nil)
        XCTAssertEqual(session.state, .lost, "only a position brings it back")
        session.answer(at: at(402), hasPosition: true)
        XCTAssertEqual(session.state, .following)
    }

    func testAnAnswerThatKnowsTheTrainIsNoEvidenceThatItLeft() {
        var session = CockpitSession(startedAt: F.t0)
        session.answer(at: at(1), hasPosition: true)
        session.answer(at: at(20), hasPosition: false, listsTrain: true)
        XCTAssertNil(session.lastMissingAt, "JourneyDetails with a position the cockpit did not take")
        XCTAssertEqual(session.lastAnswerAt, at(20))
        session.answer(at: at(40), hasPosition: false)
        XCTAssertEqual(session.lastMissingAt, at(40), "the radar's box without the train")
    }
}
