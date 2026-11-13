import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: the one minute formula of a change (docs/CONNECTION_GUARD.md §2). Detail, card and notice call it.
final class TransferBufferTests: XCTestCase {
    private let t0 = GuardFixture.at("14:00")

    private func minutes(_ seconds: TimeInterval, walk: Int = 0) -> Int {
        TransferBuffer.minutes(arrival: t0, departure: t0.addingTimeInterval(seconds), walkMinutes: walk)
    }

    func testRoundingIsHalfToEvenLikeTheDetail() {
        XCTAssertEqual(minutes(4 * 60 + 40), 5, "4 min 40 s is five, not four")
        XCTAssertEqual(minutes(-30), 0)
        XCTAssertEqual(minutes(-90), -2, "nearest even, as minutesBetween")
        XCTAssertEqual(minutes(150), 2, "2.5 → 2")
        XCTAssertEqual(minutes(210), 4, "3.5 → 4")
        XCTAssertEqual(minutes(9 * 60), 9)
    }

    func testWalkIsSubtractedAfterRounding() {
        XCTAssertEqual(minutes(5 * 60 + 30, walk: 3), 3, "round(5.5) − 3, not round(2.5)")
        XCTAssertEqual(minutes(60, walk: 3), -2)
    }

    func testEqualsTheDetailForEveryRecordedChange() throws {
        var checked = 0
        for (name, journey) in try GuardFixture.plannerJourneysWithChanges() {
            let rides = journey.legs.indices.filter { journey.legs[$0].kind == .ride }
            for (a, b) in zip(rides, rides.dropFirst()) {
                guard let detail = JourneyPresentation.transfer(journey, from: a, to: b),
                      let arrival = journey.legs[a].arrival.effective, let departure = journey.legs[b].departure.effective else { continue }
                let walk = ConnectionGuard.walk(journey, feeder: a, connection: b).minutes
                XCTAssertEqual(TransferBuffer.minutes(arrival: arrival, departure: departure, walkMinutes: walk), detail.bufferMinutes, name)
                XCTAssertEqual(walk, detail.walkMinutes, name)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10)
    }
}
