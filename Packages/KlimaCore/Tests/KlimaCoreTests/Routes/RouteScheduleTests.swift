import XCTest
@testable import KlimaCore

/// Gespeicherte Routen: weekday pattern, stored form, reminder slots and the next departure (Vienna time).
final class RouteScheduleTests: XCTestCase {
    private let vienna: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        vienna.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date.distantPast
    }

    private let workdays: Set<RouteWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    func testStoredFormRoundTrips() {
        let schedule = RouteSchedule(weekdays: workdays, hour: 7, minute: 30, leadMinutes: 10)
        XCTAssertEqual(schedule.raw, "0,1,2,3,4;07:30;10")
        XCTAssertEqual(RouteSchedule(raw: schedule.raw), schedule)
    }

    func testMalformedStoredFormIsRejected() {
        XCTAssertNil(RouteSchedule(raw: ""))
        XCTAssertNil(RouteSchedule(raw: "0,1;25:00;10"))     // hour out of range
        XCTAssertNil(RouteSchedule(raw: "0;07:30;7"))         // lead time not offered
        XCTAssertNil(RouteSchedule(raw: "9;07:30;10"))        // no such weekday
        XCTAssertNil(RouteSchedule(raw: "0;0730;10"))         // no clock time
    }

    func testInitClampsTimeAndFallsBackToDefaultLead() {
        let schedule = RouteSchedule(weekdays: [.sunday], hour: 40, minute: -3, leadMinutes: 12)
        XCTAssertEqual(schedule.hour, 23)
        XCTAssertEqual(schedule.minute, 0)
        XCTAssertEqual(schedule.leadMinutes, 10)
    }

    func testSummaryWords() {
        XCTAssertEqual(RouteSchedule(weekdays: workdays, hour: 7, minute: 30).summary, "Mo–Fr · 07:30")
        XCTAssertEqual(RouteSchedule(weekdays: [.saturday, .sunday], hour: 9, minute: 5).summary, "Sa–So · 09:05")
        XCTAssertEqual(RouteSchedule(weekdays: Set(RouteWeekday.allCases), hour: 6, minute: 45).summary, "Täglich · 06:45")
        XCTAssertEqual(RouteSchedule(weekdays: [.friday, .monday, .wednesday], hour: 8, minute: 0).summary, "Mo, Mi, Fr · 08:00")
        XCTAssertEqual(RouteSchedule(weekdays: [], hour: 8, minute: 0).summary, "Kein Zeitplan")
    }

    func testReminderSlotsShiftByTheLeadTime() {
        let slots = RouteSchedule(weekdays: [.monday, .friday], hour: 7, minute: 30, leadMinutes: 10).reminderSlots
        XCTAssertEqual(slots, [ReminderSlot(weekday: .monday, hour: 7, minute: 20), ReminderSlot(weekday: .friday, hour: 7, minute: 20)])
    }

    func testReminderSlotWrapsToThePreviousDay() {
        let slots = RouteSchedule(weekdays: [.monday], hour: 0, minute: 5, leadMinutes: 10).reminderSlots
        XCTAssertEqual(slots, [ReminderSlot(weekday: .sunday, hour: 23, minute: 55)])
    }

    func testNextDepartureIsTodayWhenStillAhead() {
        let schedule = RouteSchedule(weekdays: workdays, hour: 7, minute: 30)
        // Monday 2026-10-12, 07:00 Vienna.
        XCTAssertEqual(schedule.nextDeparture(after: at(2026, 10, 12, 7, 0), calendar: vienna), at(2026, 10, 12, 7, 30))
    }

    func testNextDepartureSkipsToTheNextMatchingDay() {
        let schedule = RouteSchedule(weekdays: workdays, hour: 7, minute: 30)
        // Monday 08:00 is past the departure: Tuesday.
        XCTAssertEqual(schedule.nextDeparture(after: at(2026, 10, 12, 8, 0), calendar: vienna), at(2026, 10, 13, 7, 30))
        // Friday evening: the weekend has no match, so Monday.
        XCTAssertEqual(schedule.nextDeparture(after: at(2026, 10, 16, 20, 0), calendar: vienna), at(2026, 10, 19, 7, 30))
    }

    func testNextDepartureOnWeekendOnly() {
        let schedule = RouteSchedule(weekdays: [.saturday, .sunday], hour: 9, minute: 0)
        // Friday 2026-10-16, 12:00: Saturday 09:00.
        XCTAssertEqual(schedule.nextDeparture(after: at(2026, 10, 16, 12, 0), calendar: vienna), at(2026, 10, 17, 9, 0))
    }

    func testNextDepartureNeedsAWeekday() {
        XCTAssertNil(RouteSchedule(weekdays: [], hour: 7, minute: 30).nextDeparture(after: at(2026, 10, 12, 7, 0), calendar: vienna))
    }

    func testNextReminderIsLeadBeforeTheNextDeparture() {
        let schedule = RouteSchedule(weekdays: workdays, hour: 7, minute: 30, leadMinutes: 10)
        // Monday 07:25 is inside the lead of today's departure, so the next reminder is Tuesday 07:20.
        XCTAssertEqual(schedule.nextReminder(after: at(2026, 10, 12, 7, 25), calendar: vienna), at(2026, 10, 13, 7, 20))
        // Monday 06:00: today's reminder at 07:20 still lies ahead.
        XCTAssertEqual(schedule.nextReminder(after: at(2026, 10, 12, 6, 0), calendar: vienna), at(2026, 10, 12, 7, 20))
    }

    func testWeekdayNumbersMatchTheCalendar() {
        XCTAssertEqual(RouteWeekday.monday.calendarWeekday, 2)
        XCTAssertEqual(RouteWeekday.sunday.calendarWeekday, 1)
        XCTAssertEqual(RouteWeekday(calendarWeekday: 7), .saturday)
        XCTAssertNil(RouteWeekday(calendarWeekday: 8))
    }
}
