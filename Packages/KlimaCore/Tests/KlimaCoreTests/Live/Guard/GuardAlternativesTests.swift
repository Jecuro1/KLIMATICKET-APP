import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: the alternatives search and pick (docs/CONNECTION_GUARD.md §5).
final class GuardAlternativesTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { GuardFixture.at(hhmm) }

    func testQueryFromTheTransferStationAfterArrivalAndWalk() throws {
        let j = GuardFixture.journey()   // 14:31 + walk 3
        let a = GuardFixture.assess(j, now: at("14:00")).assessment
        let q = try XCTUnwrap(GuardAlternatives.query(journey: j, assessment: a, products: .klimaTicket, now: at("14:00")))
        XCTAssertEqual(q.origin, GuardFixture.stPoelten)
        XCTAssertEqual(q.destination, GuardFixture.neustadt)
        XCTAssertEqual(q.date, at("14:34"))
        XCTAssertEqual(q.products, .klimaTicket)
        XCTAssertEqual(q.results, 4)
        XCTAssertEqual(q.via, [])
        XCTAssertFalse(q.includeStopovers)
        XCTAssertFalse(q.includePolyline)
        XCTAssertFalse(q.isArrival)
        // Never before now.
        let late = try XCTUnwrap(GuardAlternatives.query(journey: j, assessment: a, products: .rail, now: at("14:50")))
        XCTAssertEqual(late.date, at("14:50"))
        XCTAssertEqual(late.products, .rail, "the products stored at registration")
    }

    func testCancelledFeederBeforeItLeftSearchesFromTheBoardingStopNow() throws {
        let j = GuardFixture.journey(feederCancelled: true)   // feeder planned 13:30
        let a = GuardFixture.assess(j, now: at("13:10")).assessment
        let q = try XCTUnwrap(GuardAlternatives.query(journey: j, assessment: a, products: .klimaTicket, now: at("13:10")))
        XCTAssertEqual(q.origin, GuardFixture.wien)
        XCTAssertEqual(q.date, at("13:10"))
        // Cancelled after it left: from the transfer station, now.
        let underway = GuardFixture.assess(j, now: at("13:50")).assessment
        let q2 = try XCTUnwrap(GuardAlternatives.query(journey: j, assessment: underway, products: .klimaTicket, now: at("13:50")))
        XCTAssertEqual(q2.origin, GuardFixture.stPoelten)
        XCTAssertEqual(q2.date, at("13:50"))
    }

    private func alt(_ dep: String, _ arr: String, cancelled: Bool = false, changes: Int = 1) -> Journey {
        let leg = Leg(id: dep, kind: .ride, origin: GuardFixture.stPoelten, destination: GuardFixture.neustadt,
                      departure: StopEvent(planned: at(dep)), arrival: StopEvent(planned: at(arr)), line: GuardFixture.rex,
                      tripID: "alt-\(dep)", isCancelled: cancelled)
        return Journey(legs: [leg], changes: changes)
    }

    func testPick() {
        let original = at("15:51")
        let picked = GuardAlternatives.pick([
            alt("14:30", "15:40"),               // before the date
            alt("14:52", "16:10"),
            alt("14:45", "16:10"),               // same arrival, earlier departure first
            alt("14:50", "16:01", cancelled: true),
            alt("15:10", "19:00"),               // more than 3 h after the original arrival
            alt("14:36", "16:30"),
            alt("15:30", "16:40"),
        ], after: at("14:34"), originalArrival: original)
        XCTAssertEqual(picked.map { $0.legs[0].id }, ["14:45", "14:52", "14:36"], "by arrival, then departure; three")
    }

    func testDepartureInTheSameMinuteCounts() {
        let picked = GuardAlternatives.pick([alt("14:34", "15:40")], after: at("14:34").addingTimeInterval(40), originalArrival: nil)
        XCTAssertEqual(picked.count, 1)
    }

    func testDeltaTexts() {
        let original = at("15:50")
        XCTAssertEqual(GuardText.delta(GuardAlternatives.deltaMinutes(alt("14:52", "16:12"), originalArrival: original)), "22 Min später als geplant")
        XCTAssertEqual(GuardText.delta(GuardAlternatives.deltaMinutes(alt("14:52", "15:50"), originalArrival: original)), "wie geplant")
        XCTAssertEqual(GuardText.delta(GuardAlternatives.deltaMinutes(alt("14:52", "15:47"), originalArrival: original)), "3 Min früher als geplant")
        XCTAssertNil(GuardText.delta(GuardAlternatives.deltaMinutes(alt("14:52", "15:47"), originalArrival: nil)))
    }

    func testThreeMinuteLimit() {
        XCTAssertTrue(GuardAlternatives.canSearch(lastSearchAt: nil, now: at("14:00")))
        XCTAssertFalse(GuardAlternatives.canSearch(lastSearchAt: at("14:00"), now: at("14:02")))
        XCTAssertTrue(GuardAlternatives.canSearch(lastSearchAt: at("14:00"), now: at("14:03")))
        XCTAssertEqual(GuardAlternatives.secondsUntilSearch(lastSearchAt: at("14:00"), now: at("14:01")), 120)
        XCTAssertEqual(GuardText.searchLimit(GuardAlternatives.secondsUntilSearch(lastSearchAt: at("14:00"), now: at("14:01"))),
                       "Neue Suche in 2 Min möglich")
        XCTAssertEqual(GuardText.searchLimit(10), "Neue Suche in 1 Min möglich")
    }

    func testFollowTargetOfAnAlternative() throws {
        let target = try XCTUnwrap(GuardAlternatives.followTarget(GuardFixture.journey()))
        XCTAssertEqual(target.tripID, "trip-feeder")
        XCTAssertEqual(target.alightStop, GuardFixture.stPoelten)
        XCTAssertEqual(target.transfer?.walkMinutes, 3)
        XCTAssertEqual(target.transfer?.plannedDeparture, at("14:40"))
        let single = try XCTUnwrap(GuardAlternatives.followTarget(alt("14:52", "16:10")))
        XCTAssertNil(single.transfer)
        XCTAssertEqual(single.tripID, "alt-14:52")
    }
}
