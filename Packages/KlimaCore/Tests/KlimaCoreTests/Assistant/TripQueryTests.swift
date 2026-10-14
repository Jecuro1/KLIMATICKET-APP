import XCTest
@testable import KlimaCore

/// Rule-based trip query parser and the validator for model fields. "Heute" is Wednesday, 14.10.2026.
final class TripQueryTests: XCTestCase {
    private let calendar = Calendar.vienna
    private lazy var now: Date = day(2026, 10, 14, hour: 9)

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testNextWeekFridayAndSundayReturn() {
        let draft = TripQueryParser.parse("nächste Woche Freitag nach Innsbruck, Rückfahrt Sonntag", now: now, calendar: calendar)
        XCTAssertEqual(draft.destination, "Innsbruck")
        XCTAssertNil(draft.origin)
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 23))
        XCTAssertNil(draft.outboundHour)
        XCTAssertEqual(draft.returnDay, day(2026, 10, 25), "Rückfahrt Sonntag is the Sunday on or after the outbound day")
        XCTAssertFalse(draft.isArrival)
    }

    func testTomorrowAtSevenFromTo() {
        let draft = TripQueryParser.parse("morgen um 7 von Wien Hbf nach Salzburg", now: now, calendar: calendar)
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 15))
        XCTAssertEqual(draft.outboundHour, 7)
        XCTAssertEqual(draft.outboundMinute, 0)
        XCTAssertEqual(draft.origin, "Wien Hbf")
        XCTAssertEqual(draft.destination, "Salzburg")
    }

    func testArrivalWithBisAndFullWeekdayName() {
        let draft = TripQueryParser.parse("Freitag bis 9 Uhr nach Bregenz", now: now, calendar: calendar)
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 16))
        XCTAssertEqual(draft.outboundHour, 9)
        XCTAssertTrue(draft.isArrival)
        XCTAssertEqual(draft.destination, "Bregenz")
    }

    func testExplicitDayMonthWithoutYearUsesNextOccurrence() {
        let draft = TripQueryParser.parse("nach Graz am 18.10.", now: now, calendar: calendar)
        XCTAssertEqual(draft.destination, "Graz")
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 18))
        let past = TripQueryParser.parse("nach Graz am 02.10.", now: now, calendar: calendar)
        XCTAssertEqual(past.outboundDay, day(2027, 10, 2), "a date already past rolls to next year")
    }

    func testPlacesWithMarkersInEitherOrder() {
        let a = TripQueryParser.parse("Wien nach Graz", now: now, calendar: calendar)
        XCTAssertEqual(a.origin, "Wien")
        XCTAssertEqual(a.destination, "Graz")
        let b = TripQueryParser.parse("nach Salzburg von Wien", now: now, calendar: calendar)
        XCTAssertEqual(b.origin, "Wien")
        XCTAssertEqual(b.destination, "Salzburg")
        let c = TripQueryParser.parse("ab St. Anton am Arlberg nach Innsbruck", now: now, calendar: calendar)
        XCTAssertEqual(c.origin, "St. Anton am Arlberg")
        XCTAssertEqual(c.destination, "Innsbruck")
    }

    func testLonePlaceIsDestinationAndWeekdayAbbreviationNeedsDot() {
        let lone = TripQueryParser.parse("Innsbruck", now: now, calendar: calendar)
        XCTAssertEqual(lone.destination, "Innsbruck")
        XCTAssertNil(lone.outboundDay)
        // "so" as a plain word must not become Sunday; "So." with its dot is an abbreviation.
        XCTAssertNil(TripQueryParser.parse("so schnell wie möglich", now: now, calendar: calendar).outboundDay)
        XCTAssertEqual(TripQueryParser.parse("nach Wien So.", now: now, calendar: calendar).outboundDay, day(2026, 10, 18))
    }

    func testReturnOnlyAndRelativeDays() {
        let back = TripQueryParser.parse("Rückfahrt Sonntag", now: now, calendar: calendar)
        XCTAssertNil(back.outboundDay)
        XCTAssertEqual(back.returnDay, day(2026, 10, 18))
        XCTAssertEqual(TripQueryParser.parse("in 3 Tagen nach Linz", now: now, calendar: calendar).outboundDay, day(2026, 10, 17))
        XCTAssertEqual(TripQueryParser.parse("übermorgen nach Linz", now: now, calendar: calendar).outboundDay, day(2026, 10, 16))
    }

    func testDateLikeWordIsNotATime() {
        let draft = TripQueryParser.parse("ab 18.10. nach Wien", now: now, calendar: calendar)
        XCTAssertNil(draft.outboundHour, "18.10. is a date, not 18:10")
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 18))
    }

    func testValidatorDropsWhatTheSentenceDoesNotSupport() {
        let text = "Freitag nach Innsbruck"
        // The place is not in the sentence, the time is not in the sentence, and the date is in the past.
        let bad = TripQueryFields(origin: "Salzburg Hbf", destination: "Innsbruck", outboundDay: "2026-10-16",
                                  outboundTime: "09:00", returnDay: "", isArrival: true)
        let (draft, rejected) = TripQueryValidator.validate(bad, sourceText: text, now: now, calendar: calendar)
        XCTAssertNil(draft.origin)
        XCTAssertEqual(draft.destination, "Innsbruck")
        XCTAssertNil(draft.outboundHour)
        XCTAssertFalse(draft.isArrival, "no 'bis' or 'Ankunft' in the sentence")
        XCTAssertTrue(rejected.contains("origin"))
        XCTAssertTrue(rejected.contains("outboundTime"))
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 16))
        XCTAssertEqual(draft.source, .model)

        let past = TripQueryFields(outboundDay: "2026-10-01")
        let (pastDraft, pastRejected) = TripQueryValidator.validate(past, sourceText: text, now: now, calendar: calendar)
        XCTAssertNil(pastDraft.outboundDay)
        XCTAssertEqual(pastRejected, ["outboundDay"])
    }

    func testValidatorAcceptsTimeThatIsInTheSentence() {
        let fields = TripQueryFields(destination: "Innsbruck", outboundDay: "2026-10-23", outboundTime: "07:30",
                                     returnDay: "2026-10-25", isArrival: false)
        let (draft, rejected) = TripQueryValidator.validate(fields, sourceText: "Innsbruck um 7:30, Rückfahrt Sonntag",
                                                           now: now, calendar: calendar)
        XCTAssertTrue(rejected.isEmpty)
        XCTAssertEqual(draft.outboundHour, 7)
        XCTAssertEqual(draft.outboundMinute, 30)
        XCTAssertEqual(draft.returnDay, day(2026, 10, 25))
    }
}
