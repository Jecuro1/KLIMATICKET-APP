import XCTest
@testable import KlimaCore

/// Live verfolgen: the stages (before departure, boarding, riding, transfer, arrived, cancelled) and the notices that
/// belong to them. Pure, fixed clock, Vienna wall clock on 2026-10-12.
final class FollowStageTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { FollowFixture.at(hhmm) }

    private func snapshot(_ hhmm: String, transfer: FollowTransfer? = nil, delayWien: Int = 360, delayLinz: Int = 300,
                          cancelled: Bool = false) -> LiveFollowSnapshot {
        LiveFollow.snapshot(FollowFixture.trip(delayLinz: delayLinz, delayWien: delayWien, cancelled: cancelled),
                            target: FollowFixture.target(transfer: transfer), now: at(hhmm))
    }

    func testBeforeDepartureFarAway() {
        XCTAssertEqual(snapshot("09:00").stage, .beforeDeparture)
        XCTAssertEqual(snapshot("09:19").stage, .beforeDeparture)
    }

    func testBoardingStartsTenMinutesBeforeDeparture() {
        XCTAssertEqual(snapshot("09:20").stage, .boarding, "exactly the boarding window before the departure")
        XCTAssertEqual(snapshot("09:29").stage, .boarding)
    }

    func testRidingAfterDeparture() {
        XCTAssertEqual(snapshot("09:31").stage, .riding)
        XCTAssertEqual(snapshot("11:00").stage, .riding)
    }

    func testArrivedWithoutTransferIsFinished() {
        let s = snapshot("12:10")
        XCTAssertEqual(s.stage, .arrived)
        XCTAssertTrue(s.stage.isFinished)
    }

    func testTransferWhileNextLegIsAhead() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30"), lineName: "RJ 162")
        let s = snapshot("12:10", transfer: transfer)
        XCTAssertEqual(s.stage, .transfer)
        XCTAssertFalse(s.stage.isFinished)
        XCTAssertEqual(s.transfer?.lineName, "RJ 162")
    }

    func testTransferEndsWhenTheNextLegHasLeft() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30"))
        XCTAssertEqual(snapshot("12:31", transfer: transfer).stage, .arrived)
    }

    func testCancelledStage() {
        let s = snapshot("10:00", cancelled: true)
        XCTAssertEqual(s.stage, .cancelled)
        XCTAssertTrue(s.stage.isFinished)
    }

    func testStageFunctionForPhases() {
        XCTAssertEqual(LiveFollow.stage(phase: .upcoming, boardingDeparture: nil, transfer: nil, now: at("09:00")), .beforeDeparture)
        XCTAssertEqual(LiveFollow.stage(phase: .underway, boardingDeparture: nil, transfer: nil, now: at("09:00")), .riding)
    }

    // MARK: Notices of the stages

    func testDepartedFiresOnceWhenTheTrainLeaves() {
        let before = snapshot("09:20")
        let after = snapshot("09:40")
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("09:40")), [.departed(stop: "Salzburg Hbf")])
        XCTAssertEqual(LiveFollow.notices(from: after, to: snapshot("09:41"), now: at("09:41")), [])
    }

    func testArrivingSoonFiresInsideTheTenMinuteWindow() {
        // Wien expected at 12:07 (6 min delay). At 11:57 that is exactly ten minutes away.
        let early = snapshot("11:56")
        XCTAssertEqual(LiveFollow.notices(from: early, to: early, now: at("11:56")), [], "eleven minutes away: not yet")
        let inside = snapshot("11:57")
        XCTAssertEqual(LiveFollow.notices(from: inside, to: inside, now: at("11:57")),
                       [.arrivingSoon(stop: "Wien Hbf", minutes: 10)])
    }

    func testArrivingSoonIsSilentAfterArrival() {
        let arrived = snapshot("12:08")
        XCTAssertEqual(LiveFollow.notices(from: arrived, to: arrived, now: at("12:08")), [])
    }

    func testTightTransferWarnsWhileUnderway() {
        // Arrival 12:07, next leg 12:10: three minutes to spare.
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"))
        let s = snapshot("11:30", transfer: transfer)
        XCTAssertEqual(s.transferBufferSeconds, 180)
        XCTAssertEqual(LiveFollow.notices(from: s, to: s, now: at("11:30")),
                       [.tightTransfer(station: "Wien Hbf", bufferMinutes: 3)])
    }

    func testTightTransferIsSilentWithEnoughTime() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30"))
        let s = snapshot("11:30", transfer: transfer)
        XCTAssertEqual(LiveFollow.notices(from: s, to: s, now: at("11:30")), [])
    }

    func testMissedTransferReportsNegativeBuffer() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:05"))
        let s = snapshot("11:30", transfer: transfer)
        XCTAssertEqual(LiveFollow.notices(from: s, to: s, now: at("11:30")),
                       [.tightTransfer(station: "Wien Hbf", bufferMinutes: -2)])
    }

    func testTightTransferWarnsEvenOnTheFirstAnswer() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"))
        let s = snapshot("11:30", transfer: transfer)
        XCTAssertTrue(LiveFollow.notices(from: nil, to: s, now: at("11:30")).contains(.tightTransfer(station: "Wien Hbf", bufferMinutes: 3)))
    }

    func testDelayThresholdIsConfigurable() {
        let before = snapshot("10:00", delayWien: 60)
        let after = snapshot("10:30", delayWien: 200)
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("10:30")), [], "default threshold is five minutes")
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("10:30"), delayThreshold: 180),
                       [.delay(minutes: 3, stop: "Wien Hbf")])
    }
}
