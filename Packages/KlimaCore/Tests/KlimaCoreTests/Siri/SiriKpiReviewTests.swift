import XCTest
@testable import KlimaCore

// MARK: review-siri – what the review of „Fragen an KlimaBilanz“ fixed (docs/SIRI_QUESTIONS.md §4): the ticket year's bars hold only
// the ticket's own days and add up to its figure, Fahrten still queued by a widget or Siri are named, and a ticket that has not
// started yet counts its days to the end.
final class SiriKpiReviewTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func trip(_ date: Date, km: Double = 50, fare: Double = 20, journey: UUID? = nil, leg: Int = 0) -> TripRecord {
        TripRecord(date: date, fromName: "A", toName: "B", mode: .train, distanceKm: km, fareEUR: fare, isRoundTrip: false,
                   journeyID: journey, legIndex: leg)
    }

    /// A ticket from 15 March 2026 (mid-month, so its first and last month are shared with the tickets before and after).
    var period: TicketPeriod {
        TicketPeriod(productID: "oe", name: "KlimaTicket Ö Classic", price: 1_179, start: date(2026, 3, 15, 0),
                     end: TicketPeriod.standardEnd(for: date(2026, 3, 15, 0)))
    }

    func built(_ trips: [TripRecord], now: Date) -> (table: KpiDailyTable, summary: SavingsSummary) {
        let summary = SavingsCalculator.summary(ticket: period, trips: trips, now: now)
        return (KpiTableBuilder.make(ticket: (period, summary), trips: trips, now: now, emissions: .fallback), summary)
    }

    // MARK: Ticket year bars

    func testTicketYearBarsHoldOnlyTheTicketsDaysAndAddUpToTheFigure() {
        let now = date(2027, 3, 10, 9)
        let trips = [
            trip(date(2026, 3, 2), fare: 40),          // the ticket before: same month, not this ticket year
            trip(date(2026, 3, 14, 23, 50), fare: 30), // the evening before the start
            trip(date(2026, 3, 15, 0, 10), fare: 10),  // the first minutes of the ticket
            trip(date(2026, 3, 31), fare: 5),
            trip(date(2026, 11, 20), fare: 12.5),
            trip(date(2027, 3, 14, 22), fare: 7),      // the last evening of the ticket
            trip(date(2027, 3, 15, 8), fare: 99),      // logged ahead into the next ticket: same month, not this one
        ]
        let (table, summary) = built(trips, now: now)
        for question in [KpiQuestion.trips, .value, .distance, .co2] {
            let answer = KpiAnswer.make(question, period: .ticketYear, table: table, now: now)
            XCTAssertEqual(answer.bars.count, 13, "March 2026 to March 2027")
            let total = answer.bars.reduce(0) { $0 + $1.value }
            switch question {
            case .trips: XCTAssertEqual(total, Double(summary.tripCount), accuracy: 1e-9)
            case .value: XCTAssertEqual(total, summary.totalValue, accuracy: 1e-9)
            case .distance: XCTAssertEqual(total, summary.distanceKm, accuracy: 1e-9)
            default: XCTAssertEqual(total, summary.co2SavedKg, accuracy: 1e-9)
            }
        }
        let value = KpiAnswer.make(.value, period: .ticketYear, table: table, now: now).bars
        XCTAssertEqual(value.first?.value ?? 0, 15, accuracy: 1e-9, "15–31 March only: 10 + 5")
        XCTAssertEqual(value.last?.value ?? 0, 7, accuracy: 1e-9, "1–14 March 2027 only")
        // Statistik's months of the ticket year say the same.
        let statistik = StatsAggregator.months(trips, in: period)
        XCTAssertEqual(statistik.map(\.value), value.map(\.value))
        // The calendar months stay whole: March 2026 of the calendar year holds all of its Fahrten.
        XCTAssertEqual(KpiAnswer.make(.value, period: .calendarYear, table: built(trips, now: date(2026, 4, 2)).table, now: date(2026, 4, 2)).bars[2].value,
                       85, accuracy: 1e-9)
    }

    func testTicketYearBeforeTheTablesDaysHasNoBars() {
        // An old ticket year (the app's newest ticket ended long ago): its start lies before the table's 400 days.
        let now = date(2027, 6, 1, 9)
        let (table, _) = built([trip(date(2026, 5, 3)), trip(date(2026, 9, 9))], now: now)
        XCTAssertLessThan(KpiDailyTable.dayKey(period.start), table.firstCoveredDay())
        let answer = KpiAnswer.make(.value, period: .ticketYear, table: table, now: now)
        XCTAssertTrue(answer.bars.isEmpty, "early months would read empty")
        XCTAssertEqual(answer.status, .figure, "the figure itself is the summary's")
        // Inside the window the bars stay.
        XCTAssertFalse(KpiAnswer.make(.value, period: .ticketYear, table: built([trip(date(2026, 5, 3))], now: date(2026, 11, 20)).table,
                                      now: date(2026, 11, 20)).bars.isEmpty)
    }

    func testFirstCoveredDay() {
        let table = KpiDailyTable(generatedAt: date(2026, 11, 20, 23, 30), ticket: nil, days: [])
        // 400 days up to and including 20 November 2026.
        XCTAssertEqual(table.firstCoveredDay(), "2025-10-17")
        let built = KpiTableBuilder.days([trip(date(2025, 10, 16, 23)), trip(date(2025, 10, 17, 0, 5))], now: date(2026, 11, 20, 23, 30),
                                         emissions: .fallback)
        XCTAssertEqual(built.map(\.day), ["2025-10-17"], "the builder keeps exactly the covered days")
    }

    // MARK: Queued Fahrten

    func testQueuedTripsOfThePeriodAreNamed() {
        let now = date(2026, 11, 20, 9)
        let (table, _) = built([trip(date(2026, 11, 16))], now: now)
        let one = KpiAnswer.make(.trips, period: .thisWeek, table: table, now: now, pending: [date(2026, 11, 20, 8)])
        XCTAssertEqual(one.sentence.plainSpaces,
                       "Diese Woche hast du 1 Fahrt erfasst. Noch nicht dabei: 1 Fahrt aus Widget oder Siri – sie zählt, sobald du KlimaBilanz öffnest.")
        XCTAssertEqual(one.value?.plainSpaces, "1 Fahrt", "the figure stays what the app has saved")
        let three = KpiAnswer.make(.value, period: .thisMonth, table: table, now: now,
                                   pending: [date(2026, 11, 18), date(2026, 11, 19), date(2026, 11, 20, 7), date(2026, 10, 30)])
        XCTAssertTrue(three.sentence.plainSpaces.hasSuffix("Noch nicht dabei: 3 Fahrten aus Widget oder Siri – sie zählen, sobald du KlimaBilanz öffnest."),
                      three.sentence)
        // Outside the period: nothing said.
        XCTAssertFalse(KpiAnswer.make(.trips, period: .lastMonth, table: table, now: now, pending: [date(2026, 11, 20, 8)]).sentence.contains("Noch nicht"))
        // An empty period with a queued Fahrt.
        XCTAssertEqual(KpiAnswer.make(.distance, period: .thisWeek, table: built([], now: now).table, now: now, pending: [now]).sentence.plainSpaces,
                       "Diese Woche hast du keine Fahrt erfasst. Noch nicht dabei: 1 Fahrt aus Widget oder Siri – sie zählt, sobald du KlimaBilanz öffnest.")
    }

    func testQueuedTripsAndTheTicketQuestions() {
        let now = date(2026, 11, 20, 9)
        let (table, _) = built([trip(date(2026, 11, 16))], now: now)
        let queued = [date(2026, 11, 20, 8)]
        XCTAssertTrue(KpiAnswer.make(.breakEven, period: .ticketYear, table: table, now: now, pending: queued).sentence.contains("Noch nicht dabei: 1"))
        XCTAssertTrue(KpiAnswer.make(.net, period: .thisMonth, table: table, now: now, pending: queued).sentence.contains("Noch nicht dabei: 1"))
        XCTAssertTrue(KpiAnswer.make(.trips, period: .ticketYear, table: table, now: now, pending: queued).sentence.contains("Noch nicht dabei: 1"))
        // A date and a price per day do not change with a Fahrt.
        XCTAssertFalse(KpiAnswer.make(.daysLeft, period: .ticketYear, table: table, now: now, pending: queued).sentence.contains("Noch nicht"))
        XCTAssertFalse(KpiAnswer.make(.costPerDay, period: .ticketYear, table: table, now: now, pending: queued).sentence.contains("Noch nicht"))
        // Before the ticket year, or without a ticket: nothing to add to.
        XCTAssertFalse(KpiAnswer.make(.trips, period: .ticketYear, table: table, now: now, pending: [date(2026, 3, 1)]).sentence.contains("Noch nicht"))
        let noTicket = KpiDailyTable(generatedAt: now, ticket: nil, days: [])
        XCTAssertEqual(KpiAnswer.make(.net, period: .ticketYear, table: noTicket, now: now, pending: queued).sentence, KpiAnswer.noTicketSentence)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: nil, now: now, pending: queued).sentence, KpiAnswer.openAppSentence)
        // The stale note stays last.
        let stale = KpiAnswer.make(.trips, period: .thisMonth, table: built([], now: date(2026, 11, 10)).table, now: now, pending: queued)
        XCTAssertTrue(stale.sentence.plainSpaces.hasSuffix("Stand 10. November. Öffne die App, um zu aktualisieren."), stale.sentence)
        XCTAssertTrue(stale.sentence.contains("Noch nicht dabei"))
    }

    func testEveryCombinationWithQueuedTripsStillGivesASentence() {
        let now = date(2026, 11, 20, 9)
        let (table, _) = built([trip(date(2026, 11, 16)), trip(date(2026, 4, 1))], now: now)
        for question in KpiQuestion.allCases {
            for period in KpiPeriod.allCases {
                let sentence = KpiAnswer.make(question, period: period, table: table, now: now, pending: [now, date(2026, 1, 2)]).sentence
                XCTAssertTrue(sentence.hasSuffix("."), sentence)
                XCTAssertFalse(sentence.contains("€"), sentence)
            }
        }
    }

    // MARK: Before the ticket starts

    func testDaysLeftBeforeTheTicketStartsCountToItsEnd() {
        let start = date(2026, 12, 1, 0)
        let future = TicketPeriod(productID: "oe", name: "KlimaTicket Ö Classic", price: 1_179, start: start, end: TicketPeriod.standardEnd(for: start))
        let now = date(2026, 11, 20, 9)
        let summary = SavingsCalculator.summary(ticket: future, trips: [], now: now)
        let table = KpiTableBuilder.make(ticket: (future, summary), trips: [], now: now, emissions: .fallback)
        let answer = KpiAnswer.make(.daysLeft, period: .ticketYear, table: table, now: now)
        XCTAssertEqual(answer.sentence.plainSpaces, "Dein Ticket beginnt am 1. Dezember und gilt bis 30. November 2027.")
        // 20 Nov 2026 → 30 Nov 2027: 375 days after today (it said 365, the period's length).
        XCTAssertEqual(answer.value?.plainSpaces, "375 Tage")
        XCTAssertEqual(answer.progress, 0)
    }
}
