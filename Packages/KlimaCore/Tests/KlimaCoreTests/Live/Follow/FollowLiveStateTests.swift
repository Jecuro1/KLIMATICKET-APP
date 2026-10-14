import XCTest
@testable import KlimaCore

/// Live verfolgen: the Live Activity state, the refresh plan and the persisted models (pure, fixed clock).
final class FollowLiveStateTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { FollowFixture.at(hhmm) }

    private func state(_ hhmm: String, transfer: FollowTransfer? = nil, cancelled: Bool = false) -> FollowLiveState {
        let s = LiveFollow.snapshot(FollowFixture.trip(cancelled: cancelled), target: FollowFixture.target(transfer: transfer), now: at(hhmm))
        return FollowLiveState.make(from: s, now: at(hhmm))
    }

    func testBeforeDepartureShowsBoardingStopAndPlatform() {
        let s = state("09:00")
        XCTAssertEqual(s.stage, .beforeDeparture)
        XCTAssertEqual(s.nextStopName, "Salzburg Hbf")
        XCTAssertEqual(s.nextStopTime, at("09:30"))
        XCTAssertEqual(s.platform, "5")
        XCTAssertEqual(s.progress, 0)
        XCTAssertEqual(s.delayMinutes, 6, "delay at the alighting stop, rounded to minutes")
    }

    func testRidingShowsNextStopAndProgress() {
        // Linz departs 10:47 with a five minute delay: at 10:50 the train has only reached Salzburg.
        XCTAssertEqual(state("10:50").progress, 0)
        let s = state("10:53")
        XCTAssertEqual(s.stage, .riding)
        XCTAssertEqual(s.nextStopName, "Wien Hbf")
        XCTAssertEqual(s.nextStopTime, at("12:07"), "realtime arrival at Wien")
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.0001, "one of two stop intervals passed")
        XCTAssertEqual(s.platform, "11", "the alighting platform while riding")
    }

    func testArrivedIsFullProgressWithoutNextStop() {
        let s = state("12:10")
        XCTAssertEqual(s.stage, .arrived)
        XCTAssertEqual(s.progress, 1)
        XCTAssertNil(s.nextStopName)
    }

    func testTransferCarriesTheNextLeg() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30"), lineName: "RJ 162")
        let s = state("12:10", transfer: transfer)
        XCTAssertEqual(s.stage, .transfer)
        XCTAssertEqual(s.transferStation, "Wien Hbf")
        XCTAssertEqual(s.transferDeparture, at("12:30"))
    }

    func testCancelledHasNoNextStop() {
        let s = state("10:00", cancelled: true)
        XCTAssertEqual(s.stage, .cancelled)
        XCTAssertNil(s.nextStopName)
    }

    func testProgressIsClamped() {
        XCTAssertEqual(FollowLiveState(stage: .riding, progress: 3).progress, 1)
        XCTAssertEqual(FollowLiveState(stage: .riding, progress: -1).progress, 0)
    }

    func testRefreshIntervalsFollowTheStage() {
        XCTAssertEqual(FollowRefreshPlan.pollInterval(stage: .riding, plannedDeparture: nil, now: at("10:00")), 60)
        XCTAssertEqual(FollowRefreshPlan.pollInterval(stage: .beforeDeparture, plannedDeparture: at("09:30"), now: at("08:00")), 600)
        XCTAssertEqual(FollowRefreshPlan.pollInterval(stage: .beforeDeparture, plannedDeparture: at("09:30"), now: at("09:10")), 120)
        XCTAssertEqual(FollowRefreshPlan.pollInterval(stage: .arrived, plannedDeparture: nil, now: at("12:10")), 600)
    }

    func testBackgroundRefreshIsARequestAndEndsWithTheFollow() {
        let now = at("10:00")
        XCTAssertEqual(FollowRefreshPlan.earliestBackgroundRefresh(stage: .riding, plannedDeparture: nil, now: now),
                       now.addingTimeInterval(15 * 60))
        XCTAssertEqual(FollowRefreshPlan.earliestBackgroundRefresh(stage: .beforeDeparture, plannedDeparture: at("12:00"), now: now),
                       now.addingTimeInterval(60 * 60))
        XCTAssertEqual(FollowRefreshPlan.earliestBackgroundRefresh(stage: .beforeDeparture, plannedDeparture: at("10:20"), now: now),
                       now.addingTimeInterval(20 * 60))
        XCTAssertNil(FollowRefreshPlan.earliestBackgroundRefresh(stage: .arrived, plannedDeparture: nil, now: now))
        XCTAssertNil(FollowRefreshPlan.earliestBackgroundRefresh(stage: .cancelled, plannedDeparture: nil, now: now))
    }

    func testStaleDateAfterArrivalOrThirtyMinutes() {
        XCTAssertEqual(FollowRefreshPlan.staleDate(arrival: at("12:01"), now: at("10:00")), at("12:11"))
        XCTAssertEqual(FollowRefreshPlan.staleDate(arrival: nil, now: at("10:00")), at("10:30"))
    }

    func testLiveStateRoundTripsThroughCodable() throws {
        let s = state("10:53", transfer: FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30")))
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(FollowLiveState.self, from: data), s)
    }

    func testSnapshotAndTargetRoundTripForPersistence() throws {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:30"), lineName: "RJ 162")
        let target = FollowFixture.target(transfer: transfer)
        let snapshot = LiveFollow.snapshot(FollowFixture.trip(), target: target, now: at("10:00"))
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(LiveFollowTarget.self, from: JSONEncoder().encode(target)), target)
        XCTAssertEqual(try decoder.decode(LiveFollowSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testTargetWithoutTransferStillDecodes() throws {
        // A target stored by an earlier build has no transfer key.
        let target = FollowFixture.target()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "transfer")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(LiveFollowTarget.self, from: data).transfer)
    }
}
