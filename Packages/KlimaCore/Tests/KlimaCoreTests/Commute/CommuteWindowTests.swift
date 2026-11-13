import XCTest
@testable import KlimaCore

/// Pendel-Modus: direction by time of day, the live window (45 min before to 30 min after), midnight and daylight saving.
final class CommuteWindowTests: XCTestCase {
    private typealias F = CommuteFixtures
    private let cal = Calendar.vienna
    private let plan = CommutePlan(weekdays: CommutePlan.workdays, outboundMinute: 7 * 60 + 20, returnMinute: 17 * 60 + 12)

    // MARK: Direction

    func testBeforeOnePMIsOutboundFromOnePMOnTheReturn() {
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 12, 59), plan: plan, calendar: cal), .outbound)
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 13, 0), plan: plan, calendar: cal), .inbound)
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 0, 5), plan: plan, calendar: cal), .outbound)
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 23, 55), plan: plan, calendar: cal), .inbound)
    }

    func testALateShiftSplitsAtTheNearerDeparture() {
        let late = CommutePlan(weekdays: CommutePlan.workdays, outboundMinute: 14 * 60, returnMinute: 22 * 60 + 30)
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 15, 0), plan: late, calendar: cal), .outbound)
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 11, 2, 21, 0), plan: late, calendar: cal), .inbound)
    }

    // MARK: Window

    func testTheWindowOpens45MinutesBefore() {
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 2, 6, 34), plan: plan, calendar: cal),
                       .upcoming(CommuteSlot(direction: .outbound, departure: F.at(2026, 11, 2, 7, 20))))
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 2, 6, 35), plan: plan, calendar: cal),
                       .live(CommuteSlot(direction: .outbound, departure: F.at(2026, 11, 2, 7, 20))))
    }

    func testTheWindowStaysOpen30MinutesAfter() {
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 2, 7, 50), plan: plan, calendar: cal),
                       .live(CommuteSlot(direction: .outbound, departure: F.at(2026, 11, 2, 7, 20))))
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 2, 7, 51), plan: plan, calendar: cal),
                       .upcoming(CommuteSlot(direction: .inbound, departure: F.at(2026, 11, 2, 17, 12))))
    }

    func testTheWeekendWaitsForMonday() {
        let saturday = F.at(2026, 11, 7, 10, 0)
        let state = CommuteWindow.state(at: saturday, plan: plan, calendar: cal)
        XCTAssertEqual(state, .upcoming(CommuteSlot(direction: .outbound, departure: F.at(2026, 11, 9, 7, 20))))
        XCTAssertEqual(CommuteWindow.dayText(F.at(2026, 11, 9, 7, 20), now: saturday, calendar: cal), "Mo 07:20")
        XCTAssertEqual(CommuteWindow.dayText(F.at(2026, 11, 7, 17, 12), now: saturday, calendar: cal), "heute 17:12")
        XCTAssertEqual(CommuteWindow.dayText(F.at(2026, 11, 8, 7, 20), now: saturday, calendar: cal), "morgen 07:20")
    }

    func testNoWeekdayIsInactive() {
        let none = CommutePlan(weekdays: [], outboundMinute: 420, returnMinute: 1020)
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 2, 7, 0), plan: none, calendar: cal), .inactive)
    }

    // MARK: Midnight

    func testAWindowAcrossMidnightBelongsToTheDepartureDay() {
        // Mondays only, out at 00:10: the window opens Sunday 23:25.
        let night = CommutePlan(weekdays: [.monday], outboundMinute: 10, returnMinute: 8 * 60)
        let monday0010 = F.at(2026, 11, 9, 0, 10)
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 8, 23, 24), plan: night, calendar: cal),
                       .upcoming(CommuteSlot(direction: .outbound, departure: monday0010)))
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 8, 23, 25), plan: night, calendar: cal),
                       .live(CommuteSlot(direction: .outbound, departure: monday0010)))
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 9, 0, 40), plan: night, calendar: cal),
                       .live(CommuteSlot(direction: .outbound, departure: monday0010)))
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 9, 0, 41), plan: night, calendar: cal),
                       .upcoming(CommuteSlot(direction: .inbound, departure: F.at(2026, 11, 9, 8, 0))))
        XCTAssertEqual(CommuteWindow.dayText(monday0010, now: F.at(2026, 11, 8, 23, 30), calendar: cal), "morgen 00:10")
        // Sunday's own 00:10 does not exist in the plan: Sunday at 00:00 waits for Monday.
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 11, 8, 0, 0), plan: night, calendar: cal),
                       .upcoming(CommuteSlot(direction: .outbound, departure: monday0010)))
    }

    // MARK: Daylight saving

    func testAutumnChangeKeepsTheWallClock() throws {
        // Sunday 25 Oct 2026: 03:00 → 02:00. Every day at 07:20.
        let daily = CommutePlan(weekdays: Set(RouteWeekday.allCases), outboundMinute: 7 * 60 + 20, returnMinute: 17 * 60)
        let saturday = try XCTUnwrap(CommuteWindow.departure(on: F.at(2026, 10, 24), minute: 440, calendar: cal))
        let sunday = try XCTUnwrap(CommuteWindow.departure(on: F.at(2026, 10, 25), minute: 440, calendar: cal))
        XCTAssertEqual(sunday.timeIntervalSince(saturday), 25 * 3600, "the day of the change has 25 hours")
        XCTAssertEqual(CommuteWindow.minuteOfDay(sunday, calendar: cal), 440)
        XCTAssertEqual(CommuteWindow.state(at: F.at(2026, 10, 25, 6, 35), plan: daily, calendar: cal),
                       .live(CommuteSlot(direction: .outbound, departure: sunday)))
        XCTAssertEqual(CommuteWindow.direction(at: F.at(2026, 10, 25, 12, 59), plan: daily, calendar: cal), .outbound)
    }

    func testSpringChangeKeepsTheWallClock() throws {
        // Sunday 29 Mar 2026: 02:00 → 03:00.
        let saturday = try XCTUnwrap(CommuteWindow.departure(on: F.at(2026, 3, 28), minute: 440, calendar: cal))
        let sunday = try XCTUnwrap(CommuteWindow.departure(on: F.at(2026, 3, 29), minute: 440, calendar: cal))
        XCTAssertEqual(sunday.timeIntervalSince(saturday), 23 * 3600, "the day of the change has 23 hours")
        XCTAssertEqual(CommuteWindow.minuteOfDay(sunday, calendar: cal), 440)
    }

    func testANonExistentTimeMovesToTheNextExistingOne() throws {
        // 02:30 does not exist on 29 Mar 2026: the slot still exists, on that day, after the jump.
        let slot = try XCTUnwrap(CommuteWindow.departure(on: F.at(2026, 3, 29), minute: 2 * 60 + 30, calendar: cal))
        XCTAssertTrue(cal.isDate(slot, inSameDayAs: F.at(2026, 3, 29, 12, 0)))
        XCTAssertEqual(cal.component(.hour, from: slot), 3)
    }
}
