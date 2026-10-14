import XCTest
@testable import KlimaCore

/// Regression tests from the review of the on-device assistant (docs/LOCAL_AI.md §4): spelled-out numbers, overflow and
/// leading zeros in the number guard, non-finite values, dotted dates with a year, model dates only when the sentence
/// names a day, and arrival words as words. "Heute" is Wednesday, 14.10.2026.
final class AssistantReviewTests: XCTestCase {
    private let calendar = Calendar.vienna
    private lazy var now: Date = day(2026, 10, 14, hour: 9)

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: Number guard

    func testSpelledOutNumbersAreCheckedLikeDigits() {
        let facts = ["Fahrten: 12", "Wert bisher: € 1.085"]
        XCTAssertEqual(AssistantNumberGuard.unknown(in: "Du hast zwei Fahrten gemacht.", facts: facts), ["2"])
        XCTAssertFalse(AssistantNumberGuard.accepts("Es sind zwölf Fahrten.", facts: ["Fahrten: 2"]))
        XCTAssertTrue(AssistantNumberGuard.accepts("Es sind zwölf Fahrten.", facts: facts))
        // The article "eine" is not a number and must not make a text fail.
        XCTAssertTrue(AssistantNumberGuard.accepts("Eine gute Nachricht für dich.", facts: facts))
    }

    func testOverflowAndLeadingZerosKeepTheirValue() {
        let huge = "99999999999999999999999"
        XCTAssertEqual(AssistantNumberGuard.tokens(in: huge), [huge])
        XCTAssertFalse(AssistantNumberGuard.accepts("Rund \(huge) Euro.", facts: ["Wert: 0"]))
        XCTAssertEqual(AssistantNumberGuard.tokens(in: "007 und 0,50"), ["7", "0.5"])
    }

    func testNonFiniteAndHugeValuesShowADashInsteadOfTrapping() {
        XCTAssertEqual(AssistantFormat.euro(.nan), "€ –")
        XCTAssertEqual(AssistantFormat.euro(.infinity), "€ –")
        XCTAssertEqual(AssistantFormat.kilometres(.nan), "– km")
        XCTAssertEqual(AssistantFormat.wholeNumber(.nan), "–")
        XCTAssertEqual(AssistantFormat.wholeNumber(1e300), "–")
        XCTAssertEqual(AssistantFormat.wholeNumber(-12.6), "-13")
    }

    func testRouteWordingMustNameBothPlaces() {
        XCTAssertTrue(AssistantNameGuard.mentionsAll("Du fährst Wien oft um diese Zeit nach Innsbruck.",
                                                     names: ["Wien Hbf", "Innsbruck Hbf"]))
        XCTAssertFalse(AssistantNameGuard.mentionsAll("Du fährst oft nach Graz.", names: ["Wien Hbf", "Innsbruck Hbf"]))
    }

    // MARK: Trip query dates and times

    func testDottedDateWithYearIsRecognised() {
        let draft = TripQueryParser.parse("am 18.10.2026 um 7 nach Innsbruck", now: now, calendar: calendar)
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 18))
        XCTAssertEqual(draft.outboundHour, 7)
        XCTAssertNil(draft.origin, "the date must not end up in the origin")
        XCTAssertEqual(draft.destination, "Innsbruck")
    }

    func testInNDaysIsLimitedToAYear() {
        XCTAssertNil(TripQueryParser.parse("in 400 Tagen nach Wien", now: now, calendar: calendar).outboundDay)
        XCTAssertEqual(TripQueryParser.parse("in 3 Tagen nach Wien", now: now, calendar: calendar).outboundDay, day(2026, 10, 17))
    }

    func testNamesDayRecognisesHowPeopleWriteDays() {
        XCTAssertTrue(TripQueryParser.namesDay("Freitag nach Innsbruck", now: now, calendar: calendar))
        XCTAssertTrue(TripQueryParser.namesDay("morgen früh", now: now, calendar: calendar))
        XCTAssertTrue(TripQueryParser.namesDay("in 3 Tagen", now: now, calendar: calendar))
        XCTAssertTrue(TripQueryParser.namesDay("am 18.10.2026", now: now, calendar: calendar))
        XCTAssertFalse(TripQueryParser.namesDay("nach Innsbruck um 7:30", now: now, calendar: calendar))
        XCTAssertFalse(TripQueryParser.namesDay("So nach Innsbruck", now: now, calendar: calendar),
                       "'So' without a dot is a word, not Sunday")
    }

    // MARK: Validator: model fields

    func testModelDayIsDroppedWhenTheSentenceNamesNoDay() {
        let fields = TripQueryFields(destination: "Innsbruck", outboundDay: "2026-10-20")
        let (draft, rejected) = TripQueryValidator.validate(fields, sourceText: "nach Innsbruck", now: now, calendar: calendar)
        XCTAssertNil(draft.outboundDay, "the model may not pick a day the sentence does not name")
        XCTAssertEqual(rejected, ["outboundDay"])
        XCTAssertEqual(draft.destination, "Innsbruck")
    }

    func testModelDayIsKeptWhenTheSentenceNamesADay() {
        let fields = TripQueryFields(destination: "Innsbruck", outboundDay: "2026-10-20")
        let (draft, rejected) = TripQueryValidator.validate(fields, sourceText: "Dienstag nach Innsbruck", now: now, calendar: calendar)
        XCTAssertEqual(draft.outboundDay, day(2026, 10, 20))
        XCTAssertTrue(rejected.isEmpty)
    }

    func testModelTimeMayBeSpelledOutInTheSentence() {
        let fields = TripQueryFields(destination: "Innsbruck", outboundTime: "07:00")
        let (draft, rejected) = TripQueryValidator.validate(fields, sourceText: "um sieben nach Innsbruck", now: now, calendar: calendar)
        XCTAssertEqual(draft.outboundHour, 7)
        XCTAssertTrue(rejected.isEmpty)
    }

    func testArrivalNeedsAWordNotASubstring() {
        let fields = TripQueryFields(destination: "Innsbruck", isArrival: true)
        let (draft, _) = TripQueryValidator.validate(fields, sourceText: "Bisher nach Innsbruck", now: now, calendar: calendar)
        XCTAssertFalse(draft.isArrival, "'bisher' contains 'bis' but is not an arrival word")
        let (arrival, _) = TripQueryValidator.validate(fields, sourceText: "bis Innsbruck", now: now, calendar: calendar)
        XCTAssertTrue(arrival.isArrival)
    }
}
