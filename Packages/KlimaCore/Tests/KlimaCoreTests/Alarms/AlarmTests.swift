import XCTest
@testable import KlimaCore

/// Alarme einsehen: identifier contract, triggers, pausing, sorting and the pending-notification budget.
final class AlarmTests: XCTestCase {
    private let vienna: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        vienna.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date.distantPast
    }

    func testIdentifiersMapToTheirKinds() {
        XCTAssertEqual(AlarmIdentifier.kind(of: "livefollow-trip-1"), .liveFollow)
        XCTAssertEqual(AlarmIdentifier.kind(of: "planner.reminder.journey-9"), .departure)
        XCTAssertEqual(AlarmIdentifier.kind(of: "route.6F1C0D2A.4"), .routeReminder)
        XCTAssertEqual(AlarmIdentifier.kind(of: "renewal.6F1C0D2A.30"), .ticketRenewal)
        XCTAssertEqual(AlarmIdentifier.kind(of: "advisor.renewal.6F1C0D2A"), .objectionLetter)
        XCTAssertEqual(AlarmIdentifier.kind(of: "perk.passengerRights.6F1C0D2A"), .passengerRights)
        XCTAssertEqual(AlarmIdentifier.kind(of: "weekly.summary"), .weeklySummary)
        XCTAssertEqual(AlarmIdentifier.kind(of: "breakeven.KlimaTicket Ö"), .other)
        XCTAssertEqual(AlarmIdentifier.kind(of: "weekly.summary.extra"), .other)
    }

    func testRouteReminderIdentifierRoundTrips() {
        let identifier = AlarmIdentifier.routeReminder(routeID: "6F1C0D2A", weekday: .friday)
        XCTAssertEqual(identifier, "route.6F1C0D2A.4")
        XCTAssertTrue(identifier.hasPrefix(AlarmIdentifier.routeReminderPrefix(routeID: "6F1C0D2A")))
        XCTAssertEqual(AlarmIdentifier.routeID(of: identifier), "6F1C0D2A")
    }

    func testGroupKeysCollectTheReminderOfOneRouteOrTicket() {
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "route.6F1C0D2A.0"), "route.6F1C0D2A")
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "route.6F1C0D2A.4"), AlarmIdentifier.groupKey(of: "route.6F1C0D2A.1"))
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "renewal.6F1C0D2A.30"), "renewal.6F1C0D2A")
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "renewal.6F1C0D2A.0"), AlarmIdentifier.groupKey(of: "renewal.6F1C0D2A.7"))
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "planner.reminder.journey-9"), "planner.reminder.journey-9")
        XCTAssertEqual(AlarmIdentifier.groupKey(of: "weekly.summary"), "weekly.summary")
    }

    func testRouteIDIsNilForOtherIdentifiers() {
        XCTAssertNil(AlarmIdentifier.routeID(of: "route.6F1C0D2A"))
        XCTAssertNil(AlarmIdentifier.routeID(of: "renewal.6F1C0D2A.4"))
        XCTAssertNil(AlarmIdentifier.routeID(of: "route..4"))
    }

    func testSortingPutsOnAlarmsFirstByMoment() {
        let soon = AlarmItem(id: "b", kind: .departure, title: "", detail: "", nextDate: at(2026, 10, 14, 9, 0), isOn: true)
        let sooner = AlarmItem(id: "a", kind: .weeklySummary, title: "", detail: "", nextDate: at(2026, 10, 14, 8, 0), isOn: true)
        let undated = AlarmItem(id: "c", kind: .other, title: "", detail: "", nextDate: nil, isOn: true)
        let pausedRoute = AlarmItem(id: "route.x", kind: .routeReminder, title: "", detail: "", nextDate: nil, isOn: false)
        let pausedPassport = AlarmItem(id: "perk.x", kind: .passengerRights, title: "", detail: "", nextDate: nil, isOn: false)
        let sorted = AlarmSorting.sorted([pausedPassport, undated, soon, pausedRoute, sooner]).map(\.id)
        XCTAssertEqual(sorted, ["a", "b", "c", "route.x", "perk.x"])
    }

    func testOneOffTriggerFiresOnlyInTheFuture() {
        let moment = at(2026, 10, 20, 7, 0)
        XCTAssertEqual(AlarmTrigger.once(moment).nextDate(after: at(2026, 10, 14, 9, 0), calendar: vienna), moment)
        XCTAssertNil(AlarmTrigger.once(moment).nextDate(after: at(2026, 10, 21, 9, 0), calendar: vienna))
    }

    func testCalendarTriggerNextMatch() {
        let weekly = DateComponents(hour: 18, minute: 0, weekday: 1)   // Sunday 18:00
        let trigger = AlarmTrigger.calendar(weekly, repeats: true)
        // Wednesday 2026-10-14: the next Sunday is 2026-10-18.
        XCTAssertEqual(trigger.nextDate(after: at(2026, 10, 14, 9, 0), calendar: vienna), at(2026, 10, 18, 18, 0))
    }

    func testPausedAlarmResumesOnlyWhileItStillFires() throws {
        let trigger = AlarmTrigger.once(at(2026, 10, 20, 7, 0))
        let paused = PausedAlarm(id: "planner.reminder.j", kind: .departure, title: "Abfahrt in 10 Min", body: "RJ 66",
                                 trigger: trigger, pausedAt: at(2026, 10, 14, 9, 0))
        XCTAssertTrue(paused.canResume(now: at(2026, 10, 14, 9, 0), calendar: vienna))
        XCTAssertFalse(paused.canResume(now: at(2026, 10, 21, 9, 0), calendar: vienna))

        let encoded = try JSONEncoder().encode(paused)
        XCTAssertEqual(try JSONDecoder().decode(PausedAlarm.self, from: encoded), paused)
    }

    func testCalendarTriggerSurvivesEncoding() throws {
        let trigger = AlarmTrigger.calendar(DateComponents(hour: 7, minute: 20, weekday: 2), repeats: true)
        let encoded = try JSONEncoder().encode(trigger)
        XCTAssertEqual(try JSONDecoder().decode(AlarmTrigger.self, from: encoded), trigger)
    }

    func testPendingBudgetLevels() {
        XCTAssertEqual(PendingNoticeBudget.level(pending: 0), .ok)
        XCTAssertEqual(PendingNoticeBudget.level(pending: 47), .ok)
        XCTAssertEqual(PendingNoticeBudget.level(pending: 48), .nearLimit)
        XCTAssertEqual(PendingNoticeBudget.level(pending: 63), .nearLimit)
        XCTAssertEqual(PendingNoticeBudget.level(pending: 64), .full)
        XCTAssertEqual(PendingNoticeBudget.level(pending: 70), .full)
    }
}
