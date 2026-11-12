import XCTest
@testable import KlimaCore

/// Default period and choices of the year story (docs/YEAR_REVIEW.md), around the Dec/Jan boundary and the two DST days
/// of 2026 in Europe/Vienna (29 March: 02:00 → 03:00, 25 October: 03:00 → 02:00).
final class YearReviewPeriodTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8, _ min: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    func ticket(from start: Date, price: Double = 1400, name: String = "KlimaTicket Ö Klassik") -> TicketPeriod {
        TicketPeriod(productID: "oe-klassik", name: name, price: price, start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, fare: Double = 20) -> TripRecord {
        TripRecord(date: d, fromName: "Innsbruck Hbf", toName: "St. Anton am Arlberg", mode: .train, distanceKm: 100, fareEUR: fare)
    }

    // MARK: Seasonal year

    func testSeasonalYearCoversDecemberAndJanuaryOnly() {
        XCTAssertNil(YearReviewPeriods.seasonalYear(now: date(2026, 11, 30, 23, 59, 59)))
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2026, 12, 1, 0, 0, 0)), 2026)
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2026, 12, 31, 23, 59, 59)), 2026)
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2027, 1, 1, 0, 0, 0)), 2026)
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2027, 1, 31, 23, 59, 59)), 2026)
        XCTAssertNil(YearReviewPeriods.seasonalYear(now: date(2027, 2, 1, 0, 0, 0)))
    }

    func testSeasonalYearUsesViennaDayNotUTC() {
        // 30 Nov 23:30 in Vienna is 22:30 UTC – still November. 1 Dec 00:30 in Vienna is 23:30 UTC on 30 Nov – already December.
        XCTAssertNil(YearReviewPeriods.seasonalYear(now: date(2026, 11, 30, 23, 30)))
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2026, 12, 1, 0, 30)), 2026)
        XCTAssertEqual(YearReviewPeriods.seasonalYear(now: date(2027, 1, 31, 23, 30)), 2026)
        XCTAssertNil(YearReviewPeriods.seasonalYear(now: date(2027, 2, 1, 0, 30)))
    }

    // MARK: Default period

    func testDefaultIsTheCalendarYearThatIsEndingOrJustEnded() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let trips = [trip(date(2026, 5, 4)), trip(date(2026, 12, 2))]
        let december = YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: date(2026, 12, 15))
        XCTAssertEqual(december.kind, .calendarYear)
        XCTAssertEqual(december.year, 2026)
        let january = YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: date(2027, 1, 20))
        XCTAssertEqual(january.kind, .calendarYear)
        XCTAssertEqual(january.year, 2026)
    }

    func testDefaultIsTheActiveTicketOutsideTheSeason() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let trips = [trip(date(2026, 5, 4))]
        for now in [date(2026, 11, 30, 23, 59, 59), date(2027, 2, 1, 0, 0, 0), date(2026, 7, 1)] {
            let period = YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: now)
            XCTAssertEqual(period.kind, .ticket, "\(now)")
            XCTAssertEqual(period.ticket, t)
        }
    }

    func testDefaultFallsBackToTheTicketWhenTheSeasonalYearHasNoTrips() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let trips = [trip(date(2026, 5, 4))]   // nothing in 2027
        let period = YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: date(2028, 1, 10))
        XCTAssertEqual(period.kind, .ticket)
    }

    func testDefaultOnTheDSTDays() {
        let t = ticket(from: date(2026, 3, 29, 0))   // starts on the day the clocks go forward
        let trips = [trip(date(2026, 3, 29, 9)), trip(date(2026, 10, 25, 9))]
        XCTAssertEqual(YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: date(2026, 3, 29, 3, 30)).kind, .ticket)
        // 25 Oct 02:30 exists twice – both are October, still the ticket period.
        let firstTwoThirty = ISO8601DateFormatter().date(from: "2026-10-25T00:30:00Z")!   // 02:30 CEST, before the clocks go back
        XCTAssertEqual(YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: firstTwoThirty).kind, .ticket)
        XCTAssertEqual(YearReviewPeriods.defaultPeriod(tickets: [t], trips: trips, now: date(2026, 12, 1, 0, 0, 1)).kind, .calendarYear)
    }

    func testRunningTicketBeatsTheLastEndedOneAndPreferredWins() {
        let old = ticket(from: date(2025, 3, 1, 0))
        let running = ticket(from: date(2026, 3, 1, 0))
        XCTAssertEqual(YearReviewPeriods.currentTicket(in: [old, running], now: date(2026, 6, 1)), running)
        XCTAssertEqual(YearReviewPeriods.currentTicket(in: [old, running], preferred: old, now: date(2026, 6, 1)), old)
        // Nothing running: the one that ended last.
        XCTAssertEqual(YearReviewPeriods.currentTicket(in: [old, running], now: date(2028, 1, 1)), running)
        // Only an upcoming one.
        XCTAssertEqual(YearReviewPeriods.currentTicket(in: [running], now: date(2025, 1, 1)), running)
        XCTAssertNil(YearReviewPeriods.currentTicket(in: [], now: date(2026, 6, 1)))
    }

    func testWithoutTicketsTheNewestYearWithTripsOrTheCurrentYear() {
        let trips = [trip(date(2024, 5, 4)), trip(date(2025, 6, 1))]
        let withTrips = YearReviewPeriods.defaultPeriod(tickets: [], trips: trips, now: date(2026, 7, 1))
        XCTAssertEqual(withTrips.kind, .calendarYear)
        XCTAssertEqual(withTrips.year, 2025)
        let empty = YearReviewPeriods.defaultPeriod(tickets: [], trips: [], now: date(2026, 7, 1))
        XCTAssertEqual(empty.year, 2026)
    }

    // MARK: Choices

    func testChoicesListTheTicketYearThenEveryYearWithTrips() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let trips = [trip(date(2025, 11, 4)), trip(date(2026, 5, 4)), trip(date(2026, 6, 4))]
        let choices = YearReviewPeriods.choices(tickets: [t], trips: trips, now: date(2026, 7, 1))
        XCTAssertEqual(choices.map(\.kind), [.ticket, .calendarYear, .calendarYear])
        XCTAssertEqual(choices.compactMap(\.year), [2026, 2025])
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
    }

    func testChoicesAlwaysContainTheDefault() {
        // No tickets and no trips: the default is the current calendar year, so it is the only choice.
        let none = YearReviewPeriods.choices(tickets: [], trips: [], now: date(2026, 7, 1))
        XCTAssertEqual(none.count, 1)
        XCTAssertEqual(none[0].year, 2026)
    }

    // MARK: Periods

    func testCalendarYearBoundsInVienna() {
        let year = YearReviewPeriods.calendarYear(2026)
        XCTAssertEqual(year.start, date(2026, 1, 1, 0))
        XCTAssertEqual(year.end, date(2026, 12, 31, 23, 59, 59))
        XCTAssertTrue(year.contains(date(2026, 3, 29, 2, 30)))   // the hour that does not exist is still inside
        XCTAssertFalse(year.contains(date(2027, 1, 1, 0)))
        XCTAssertEqual(year.title(), "Kalenderjahr 2026")
        XCTAssertEqual(year.yearLabel(), "2026")
    }

    func testTicketPeriodLabels() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let period = YearReviewPeriods.ticketPeriod(t)
        XCTAssertEqual(period.title(), "Ticket-Jahr 2026/27")
        XCTAssertEqual(period.start, t.start)
        XCTAssertEqual(period.end, t.end)
        let calendarTicket = ticket(from: date(2026, 1, 1, 0))
        XCTAssertEqual(YearReviewPeriods.ticketPeriod(calendarTicket).title(), "Ticket-Jahr 2026")
    }

    // MARK: Accounting

    func testTicketPeriodAccountsAsItself() {
        let t = ticket(from: date(2026, 3, 1, 0))
        let period = YearReviewPeriods.ticketPeriod(t)
        XCTAssertEqual(YearReviewPeriods.accountingPeriod(for: period, tickets: [t], now: date(2026, 9, 1)), t)
    }

    func testCalendarYearCostIsProRataAcrossTwoTickets() {
        // 2025/26 ticket (1 Mar 2025 – 28 Feb 2026) and 2026/27 ticket (1 Mar 2026 – 28 Feb 2027), looked at after the year.
        let first = ticket(from: date(2025, 3, 1, 0), price: 1_200, name: "Alt")
        let second = ticket(from: date(2026, 3, 1, 0), price: 1_400, name: "Neu")
        let year = YearReviewPeriods.calendarYear(2026)
        let accounting = YearReviewPeriods.accountingPeriod(for: year, tickets: [first, second], now: date(2027, 1, 10))
        // Jan + Feb 2026 = 59 of 365 days of the first ticket, 1 Mar – 31 Dec 2026 = 306 of 365 days of the second.
        let expected = 1_200.0 * 59 / 365 + 1_400.0 * 306 / 365
        XCTAssertEqual(accounting.price, expected, accuracy: 0.0001)
        XCTAssertEqual(accounting.name, "Neu")   // the ticket that covered most of the year
        XCTAssertEqual(accounting.start, year.start)
        XCTAssertEqual(accounting.end, year.end)
    }

    func testCalendarYearCostStopsAtToday() {
        let t = ticket(from: date(2026, 1, 1, 0), price: 1_460)   // 365 days → exactly € 4 per day
        let year = YearReviewPeriods.calendarYear(2026)
        let midYear = YearReviewPeriods.accountingPeriod(for: year, tickets: [t], now: date(2026, 4, 10, 15))
        XCTAssertEqual(midYear.price, 4.0 * 100, accuracy: 0.0001)   // 1 Jan … 10 Apr = 100 days
        let before = YearReviewPeriods.accountingPeriod(for: year, tickets: [t], now: date(2025, 12, 20))
        XCTAssertEqual(before.price, 0)
    }

    func testCalendarYearCostAcrossTheSpringDSTDay() {
        // The ticket starts on 29 March 2026 (a 23-hour day): 29 Mar … 31 Dec = 278 days of its 365.
        let t = ticket(from: date(2026, 3, 29, 0), price: 1_400)
        let accounting = YearReviewPeriods.accountingPeriod(for: YearReviewPeriods.calendarYear(2026), tickets: [t], now: date(2027, 1, 5))
        XCTAssertEqual(accounting.price, 1_400.0 * 278 / 365, accuracy: 0.0001)
    }

    func testCalendarYearCostAcrossTheAutumnDSTDay() {
        // 25 Oct 2026 is a 25-hour day. Counting whole calendar days it is still one day.
        let t = ticket(from: date(2026, 10, 25, 0), price: 730)   // 365 days → € 2 per day
        let accounting = YearReviewPeriods.accountingPeriod(for: YearReviewPeriods.calendarYear(2026), tickets: [t], now: date(2027, 1, 5))
        XCTAssertEqual(accounting.price, 2.0 * 68, accuracy: 0.0001)   // 25 Oct … 31 Dec = 7 + 30 + 31 days
    }

    func testCalendarYearWithoutTicketHasNoCost() {
        let accounting = YearReviewPeriods.accountingPeriod(for: YearReviewPeriods.calendarYear(2024), tickets: [ticket(from: date(2026, 3, 1, 0))],
                                                            now: date(2027, 1, 5))
        XCTAssertEqual(accounting.price, 0)
        XCTAssertEqual(accounting.name, "KlimaTicket")
    }
}
