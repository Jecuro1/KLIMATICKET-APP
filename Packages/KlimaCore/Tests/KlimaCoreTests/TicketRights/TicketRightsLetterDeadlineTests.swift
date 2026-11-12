import XCTest
@testable import KlimaCore

final class TicketRightsLetterDeadlineTests: XCTestCase {
    private let deadline = LetterDeadline(day: TR.date(2027, 1, 15))

    func testRemindersFiveAndOneDayBeforeAtNineInTheMorning() {
        let reminders = deadline.reminders(now: TR.date(2026, 11, 12))
        XCTAssertEqual(reminders.map(\.daysBefore), [5, 1])
        XCTAssertEqual(reminders[0].fireDate, TR.date(2027, 1, 10, 9))
        XCTAssertEqual(reminders[1].fireDate, TR.date(2027, 1, 14, 9))
    }

    func testPastRemindersAreSkipped() {
        // Four days before the deadline: the 5-day moment is gone, only the 1-day one is left.
        XCTAssertEqual(deadline.reminders(now: TR.date(2027, 1, 11)).map(\.daysBefore), [1])
        // The morning of the 5-day reminder, after 09:00.
        XCTAssertEqual(deadline.reminders(now: TR.date(2027, 1, 10, 9, 30)).map(\.daysBefore), [1])
        XCTAssertEqual(deadline.reminders(now: TR.date(2027, 1, 10, 8, 59)).map(\.daysBefore), [5, 1])
        // After the 1-day moment, on the deadline day and later: none.
        XCTAssertTrue(deadline.reminders(now: TR.date(2027, 1, 14, 10)).isEmpty)
        XCTAssertTrue(deadline.reminders(now: TR.date(2027, 1, 15, 8)).isEmpty)
        XCTAssertTrue(deadline.reminders(now: TR.date(2027, 2, 1)).isEmpty)
    }

    func testStatusCountsDaysByViennaDay() {
        XCTAssertEqual(deadline.status(now: TR.date(2027, 1, 10, 23)), .open(days: 5))
        XCTAssertEqual(deadline.status(now: TR.date(2027, 1, 15, 0, 1)), .today)
        XCTAssertEqual(deadline.status(now: TR.date(2027, 1, 15, 23, 59)), .today)
        XCTAssertEqual(deadline.status(now: TR.date(2027, 1, 16, 0, 1)), .passed(days: 1))
        XCTAssertTrue(deadline.isPassed(now: TR.date(2027, 1, 20)))
        XCTAssertFalse(deadline.isPassed(now: TR.date(2027, 1, 15, 22)))
    }

    func testIdentifiersStartWithLetterAndBelongToTheObjectionAlarms() {
        let id = LetterDeadline.identifier(ticketID: "6F1C0D2A", daysBefore: 5)
        XCTAssertEqual(id, "letter.6F1C0D2A.d5")
        XCTAssertTrue(id.hasPrefix("letter."))
        XCTAssertTrue(id.hasPrefix(LetterDeadline.identifierPrefix(ticketID: "6F1C0D2A")))
        XCTAssertEqual(AlarmIdentifier.kind(of: id), .objectionLetter)
        XCTAssertEqual(AlarmIdentifier.kind(of: LetterDeadline.identifier(ticketID: "6F1C0D2A", daysBefore: 1)), .objectionLetter)
        // Both reminders of one letter are one row on the Alarms screen.
        XCTAssertEqual(AlarmIdentifier.groupKey(of: id), "letter.6F1C0D2A")
        XCTAssertEqual(AlarmIdentifier.groupKey(of: id), AlarmIdentifier.groupKey(of: LetterDeadline.identifier(ticketID: "6F1C0D2A", daysBefore: 1)))
        // The older renewal reminders keep their kinds.
        XCTAssertEqual(AlarmIdentifier.kind(of: "advisor.renewal.6F1C0D2A"), .objectionLetter)
        XCTAssertEqual(AlarmIdentifier.kind(of: "renewal.6F1C0D2A.30"), .ticketRenewal)
    }

    func testReminderCopy() {
        XCTAssertEqual(LetterDeadline.reminderTitle(daysBefore: 1), "Morgen endet deine Widerspruchsfrist")
        XCTAssertEqual(LetterDeadline.reminderTitle(daysBefore: 5), "In 5 Tagen endet deine Widerspruchsfrist")
        let body = deadline.reminderBody(ticketName: "KlimaTicket Ö Klassik")
        XCTAssertTrue(body.contains("15. Jänner 2027"))
        XCTAssertTrue(body.contains("KlimaTicket Ö Klassik"))
        XCTAssertTrue(body.contains("eingeschrieben"))
    }

    func testTheDeadlineIsStoredAsADay() {
        XCTAssertEqual(LetterDeadline(day: TR.date(2027, 1, 15, 17)).day, TR.date(2027, 1, 15, 0))
    }
}
