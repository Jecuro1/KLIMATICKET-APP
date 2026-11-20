import XCTest
@testable import KlimaCore

// MARK: siri – what Siri says (docs/SIRI_QUESTIONS.md §4): every question for every period, period names, singular and plural, the
// empty period, the stale note, ticket-only questions, week/month/year boundaries in Vienna time.
final class SiriKpiAnswerTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func day(_ key: String, journeys: Int = 1, value: Double = 10, km: Double = 20, co2: Double = 3) -> KpiDailyTable.Day {
        .init(day: key, journeys: journeys, value: value, km: km, co2: co2)
    }

    /// Ticket 1 Mar 2026 – 28 Feb 2027, € 1.179, € 1.259,40 so far: € 80,40 in the plus.
    func ticket(value: Double = 1_259.40, trips: Int = 212) -> KpiDailyTable.Ticket {
        .init(name: "KlimaTicket Ö Classic", start: date(2026, 3, 1, 0), end: TicketPeriod.standardEnd(for: date(2026, 3, 1, 0)), price: 1_179,
              tripCount: trips, totalValue: value, distanceKm: 8_412.6, co2SavedKg: 1_403.2, paidOffDate: date(2026, 10, 3, 7),
              forecastBreakEvenDate: nil, forecastReachesBreakEven: true)
    }

    func table(_ days: [KpiDailyTable.Day], ticket: KpiDailyTable.Ticket? = nil, at made: Date, format: FormatPrefs = .standard) -> KpiDailyTable {
        KpiDailyTable(generatedAt: made, format: format, ticket: ticket ?? self.ticket(), days: days)
    }

    func testEveryQuestionAndPeriodGivesASentence() {
        let now = date(2026, 11, 20, 9)
        let tables: [KpiDailyTable?] = [
            nil,
            KpiDailyTable(generatedAt: now, ticket: nil, days: []),
            table([], at: now),
            table([day("2026-10-01"), day("2026-11-16", journeys: 3), day("2026-11-20")], at: now),
            table([day("2026-11-19")], at: date(2026, 11, 10)),
            table([day("2026-11-19")], ticket: ticket(value: 0, trips: 0), at: now),
        ]
        for t in tables {
            for question in KpiQuestion.allCases {
                for period in KpiPeriod.allCases {
                    let answer = KpiAnswer.make(question, period: period, table: t, now: now)
                    XCTAssertFalse(answer.sentence.isEmpty)
                    XCTAssertTrue(answer.sentence.hasSuffix("."), answer.sentence)
                    XCTAssertFalse(answer.sentence.contains("€"), "spoken figures: \(answer.sentence)")
                    XCTAssertFalse(answer.sentence.contains("nan") || answer.sentence.contains("inf"), answer.sentence)
                    XCTAssertFalse(answer.shortcutValue.isEmpty)
                    if question.isTicketOnly { XCTAssertEqual(answer.period, .ticketYear) }
                }
            }
        }
    }

    func testNoTableSaysOpenTheApp() {
        let answer = KpiAnswer.make(.trips, period: .thisMonth, table: nil, now: date(2026, 11, 20))
        XCTAssertEqual(answer.status, .noTable)
        XCTAssertTrue(answer.sentence.contains("Öffne KlimaBilanz"))
        XCTAssertNil(answer.value)
    }

    func testPeriodNamesAndValues() {
        let now = date(2026, 11, 20, 9)
        let t = table([day("2026-10-02", journeys: 2, value: 100, km: 300, co2: 40), day("2026-10-30", journeys: 12, value: 86.4, km: 112, co2: 18.2),
                       day("2026-11-16", journeys: 1, value: 3.05, km: 3.4, co2: 0.2), day("2026-01-02", journeys: 5, value: 1_000, km: 10, co2: 1)], at: now)
        XCTAssertEqual(KpiAnswer.make(.value, period: .lastMonth, table: t, now: now).sentence,
                       "Der Wert deiner Fahrten im Oktober: 186 Euro 40. So viel hätten sie einzeln gekostet.")
        XCTAssertEqual(KpiAnswer.make(.value, period: .lastMonth, table: t, now: now).value?.plainSpaces, "€ 186,40")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .lastMonth, table: t, now: now).sentence, "Im Oktober hast du 14 Fahrten erfasst.")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: t, now: now).sentence, "Diese Woche hast du 1 Fahrt erfasst.")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: t, now: now).value, "1 Fahrt")
        XCTAssertEqual(KpiAnswer.make(.distance, period: .thisMonth, table: t, now: now).sentence, "Im November bist du 3,4 Kilometer gefahren.")
        XCTAssertEqual(KpiAnswer.make(.distance, period: .lastMonth, table: t, now: now).value, "412 km")
        XCTAssertEqual(KpiAnswer.make(.co2, period: .lastMonth, table: t, now: now).sentence,
                       "Im Oktober hast du gegenüber dem Auto etwa 58 Kilogramm CO₂ gespart.")
        XCTAssertEqual(KpiAnswer.make(.co2, period: .thisMonth, table: t, now: now).sentence,
                       "Im November hast du gegenüber dem Auto etwa 0,2 Kilogramm CO₂ gespart.")
        XCTAssertEqual(KpiAnswer.make(.value, period: .thisMonth, table: t, now: now).sentence,
                       "Der Wert deiner Fahrten im November: 3 Euro 5. So viel hätten sie einzeln gekostet.")
        XCTAssertEqual(KpiAnswer.make(.value, period: .calendarYear, table: t, now: now).sentence,
                       "Der Wert deiner Fahrten im Jahr 2026: 1.189 Euro. So viel hätten sie einzeln gekostet.")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .calendarYear, table: t, now: now).label, "Fahrten · 2026")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .lastMonth, table: t, now: now).label, "Fahrten · Oktober 2026")
        // The ticket year reads the ticket's own figures (Statistik's summary), not the days.
        XCTAssertEqual(KpiAnswer.make(.trips, period: .ticketYear, table: t, now: now).sentence, "Im Ticketjahr hast du 212 Fahrten erfasst.")
        XCTAssertEqual(KpiAnswer.make(.co2, period: .ticketYear, table: t, now: now).sentence,
                       "Im Ticketjahr hast du gegenüber dem Auto etwa 1,4 Tonnen CO₂ gespart.")
        XCTAssertEqual(KpiAnswer.make(.co2, period: .ticketYear, table: t, now: now).value, "1,4 t")
        XCTAssertEqual(KpiAnswer.make(.distance, period: .ticketYear, table: t, now: now).label, "Kilometer · Ticketjahr 2026/27")
    }

    func testLastMonthInJanuaryNamesTheYear() {
        let now = date(2027, 1, 15)
        let t = table([day("2026-12-24", journeys: 2)], at: now)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .lastMonth, table: t, now: now).sentence, "Im Dezember 2026 hast du 2 Fahrten erfasst.")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisMonth, table: t, now: now).sentence, "Im Jänner hast du keine Fahrt erfasst.")
    }

    func testEmptyPeriod() {
        let now = date(2026, 11, 20, 9)
        let t = table([day("2026-09-01")], at: now)
        let answer = KpiAnswer.make(.value, period: .lastMonth, table: t, now: now)
        XCTAssertEqual(answer.status, .empty)
        XCTAssertEqual(answer.sentence, "Im Oktober hast du keine Fahrt erfasst.")
        XCTAssertEqual(answer.value?.plainSpaces, "€ 0")
        XCTAssertEqual(KpiAnswer.make(.co2, period: .thisWeek, table: t, now: now).sentence, "Diese Woche hast du keine Fahrt erfasst.")
        let none = table([], ticket: ticket(value: 0, trips: 0), at: now)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .ticketYear, table: none, now: now).sentence, "Im Ticketjahr hast du noch keine Fahrt erfasst.")
    }

    func testStaleNote() {
        let made = date(2026, 11, 12, 8)
        let t = table([day("2026-11-10")], at: made)
        let fresh = KpiAnswer.make(.trips, period: .thisMonth, table: t, now: made.addingTimeInterval(23 * 3600))
        XCTAssertFalse(fresh.isStale)
        XCTAssertFalse(fresh.sentence.contains("Stand"))
        let old = KpiAnswer.make(.trips, period: .thisMonth, table: t, now: date(2026, 11, 20))
        XCTAssertTrue(old.isStale)
        XCTAssertEqual(old.sentence, "Im November hast du 1 Fahrt erfasst. Stand 12. November. Öffne die App, um zu aktualisieren.")
    }

    func testWeekStartsOnMondayOrSunday() {
        // Sunday 22 Nov 2026: with Monday as the first day the week is 16 – 22 Nov, with Sunday 22 – 28 Nov.
        let sunday = date(2026, 11, 22, 10)
        let days = [day("2026-11-16", journeys: 1), day("2026-11-21", journeys: 2), day("2026-11-22", journeys: 4)]
        let monday = table(days, at: sunday)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: monday, now: sunday).value, "7 Fahrten")
        let sundayFirst = table(days, at: sunday, format: FormatPrefs(weekStart: .sunday))
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: sundayFirst, now: sunday).value, "4 Fahrten")
        let bars = KpiAnswer.make(.trips, period: .thisWeek, table: monday, now: sunday).bars
        XCTAssertEqual(bars.map(\.label), ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        XCTAssertEqual(bars.map(\.value), [1, 0, 0, 0, 0, 2, 4])
        XCTAssertEqual(bars.last?.isCurrent, true)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: sundayFirst, now: sunday).bars.first?.label, "So")
    }

    func testBoundariesInViennaTime() {
        // 00:30 on 1 Nov in Vienna is still 31 Oct in UTC: „dieser Monat“ is November.
        let now = date(2026, 11, 1, 0, 30)
        let t = table([day("2026-10-31", journeys: 3), day("2026-11-01", journeys: 1)], at: now)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisMonth, table: t, now: now).value, "1 Fahrt")
        XCTAssertEqual(KpiAnswer.make(.trips, period: .lastMonth, table: t, now: now).value, "3 Fahrten")
        // The week of the autumn DST switch (Sunday 25 Oct) has seven days and the switch day in it.
        let dst = date(2026, 10, 25, 23, 30)
        let week = table([day("2026-10-19"), day("2026-10-25", journeys: 2), day("2026-10-26", journeys: 5)], at: dst)
        let answer = KpiAnswer.make(.trips, period: .thisWeek, table: week, now: dst)
        XCTAssertEqual(answer.value, "3 Fahrten")
        XCTAssertEqual(answer.bars.count, 7)
        XCTAssertEqual(answer.bars.map(\.id).last, "2026-10-25")
        // The spring switch (Sunday 29 Mar) likewise.
        let spring = date(2026, 3, 29, 3, 30)
        let springWeek = table([day("2026-03-23"), day("2026-03-29", journeys: 2), day("2026-03-30", journeys: 5)], at: spring)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisWeek, table: springWeek, now: spring).value, "3 Fahrten")
        // A new year: „Kalenderjahr“ starts on 1 Jan in Vienna.
        let newYear = date(2027, 1, 1, 0, 15)
        let year = table([day("2026-12-31", journeys: 4), day("2027-01-01", journeys: 1)], at: newYear)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .calendarYear, table: year, now: newYear).sentence, "Im Jahr 2027 hast du 1 Fahrt erfasst.")
    }

    func testMonthBars() {
        let now = date(2026, 2, 10)
        let t = table([day("2026-02-01", value: 5), day("2026-02-28", value: 7)], at: now)
        let bars = KpiAnswer.make(.value, period: .thisMonth, table: t, now: now).bars
        XCTAssertEqual(bars.count, 28)
        XCTAssertEqual(bars.first?.value, 5)
        XCTAssertEqual(bars.last?.value, 7)
        XCTAssertEqual(bars.filter(\.isCurrent).map(\.label), ["10"])
        let year = KpiAnswer.make(.value, period: .calendarYear, table: t, now: now).bars
        XCTAssertEqual(year.map(\.label), ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"])
        XCTAssertEqual(year[1].value, 12)
        XCTAssertEqual(KpiAnswer.make(.value, period: .ticketYear, table: t, now: now).bars.count, 12, "March 2026 to February 2027")
    }

    func testTicketQuestions() {
        let now = date(2026, 11, 20, 9)
        let t = table([], at: now)
        XCTAssertEqual(KpiAnswer.make(.net, period: .ticketYear, table: t, now: now).sentence, "Dein Ticket hat sich rentiert: Du bist 80 Euro 40 im Plus.")
        XCTAssertEqual(KpiAnswer.make(.net, period: .ticketYear, table: t, now: now).value?.plainSpaces, "€ 80,40")
        XCTAssertEqual(KpiAnswer.make(.net, period: .thisMonth, table: t, now: now).sentence,
                       "Das gibt es nur fürs ganze Ticketjahr. Dein Ticket hat sich rentiert: Du bist 80 Euro 40 im Plus.")
        let minus = table([], ticket: ticket(value: 1_059), at: now)
        XCTAssertEqual(KpiAnswer.make(.net, period: .ticketYear, table: minus, now: now).sentence,
                       "Du bist noch 120 Euro im Minus. So viel fehlt bis zum Break-even.")
        XCTAssertEqual(KpiAnswer.make(.breakEven, period: .ticketYear, table: t, now: now).sentence,
                       "Nichts mehr: Dein Ticket hat sich am 3. Oktober rentiert.")
        var forecast = ticket(value: 1_059)
        forecast.paidOffDate = nil
        forecast.forecastBreakEvenDate = date(2026, 12, 14)
        XCTAssertEqual(KpiAnswer.make(.breakEven, period: .ticketYear, table: table([], ticket: forecast, at: now), now: now).sentence,
                       "Bis zum Break-even fehlen noch 120 Euro. Prognose bei deinem Tempo: am 14. Dezember.")
        forecast.forecastReachesBreakEven = false
        forecast.forecastBreakEvenDate = date(2027, 5, 1)
        XCTAssertEqual(KpiAnswer.make(.breakEven, period: .ticketYear, table: table([], ticket: forecast, at: now), now: now).sentence,
                       "Bis zum Break-even fehlen noch 120 Euro. Bei deinem bisherigen Tempo reicht es laut Prognose nicht bis zum Ablauf.")
        // 20 Nov → 28 Feb: 100 days after today.
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .thisWeek, table: t, now: now).sentence, "Dein Ticket gilt noch 100 Tage, bis 28. Februar 2027.")
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .ticketYear, table: t, now: now).value, "100 Tage")
        let lastDays = table([], at: date(2027, 2, 27, 7))
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .ticketYear, table: lastDays, now: date(2027, 2, 27, 8)).sentence,
                       "Dein Ticket gilt noch 1 Tag, bis 28. Februar.")
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .ticketYear, table: table([], at: date(2027, 2, 28, 21)), now: date(2027, 2, 28, 22)).sentence,
                       "Heute ist der letzte Tag deines Tickets.")
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .ticketYear, table: t, now: date(2027, 3, 1, 8)).sentence,
                       "Dein Ticket ist am 28. Februar abgelaufen. Stand 20. November 2026. Öffne die App, um zu aktualisieren.")
        // 1.179 € / 365 days = 3,23 € a day; the period does not matter for it.
        XCTAssertEqual(KpiAnswer.make(.costPerDay, period: .lastMonth, table: t, now: now).sentence,
                       "Dein Ticket kostet dich 3 Euro 23 pro Tag: 1.179 Euro für 365 Tage.")
        XCTAssertEqual(KpiAnswer.make(.costPerDay, period: .ticketYear, table: t, now: now).value?.plainSpaces, "€ 3,23")
        let noTicket = KpiDailyTable(generatedAt: now, ticket: nil, days: [day("2026-11-19")])
        XCTAssertEqual(KpiAnswer.make(.daysLeft, period: .ticketYear, table: noTicket, now: now).status, .noTicket)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .ticketYear, table: noTicket, now: now).status, .noTicket)
        XCTAssertEqual(KpiAnswer.make(.trips, period: .thisMonth, table: noTicket, now: now).sentence, "Im November hast du 1 Fahrt erfasst.")
    }

    func testProgress() {
        let now = date(2026, 11, 20, 9)
        let t = table([], ticket: ticket(value: 589.5), at: now)
        XCTAssertEqual(KpiAnswer.make(.breakEven, period: .ticketYear, table: t, now: now).progress ?? 0, 0.5, accuracy: 1e-9)
        let elapsed = KpiAnswer.make(.daysLeft, period: .ticketYear, table: t, now: now).progress ?? 0
        XCTAssertEqual(elapsed, 265.0 / 365.0, accuracy: 1e-9)
        XCTAssertNil(KpiAnswer.make(.costPerDay, period: .ticketYear, table: t, now: now).progress)
    }

    func testQuestionTitlesAreTheTileTitles() {
        XCTAssertEqual(KpiQuestion.trips.title, KpiKind.tripCount.title)
        XCTAssertEqual(KpiQuestion.value.title, "Wert deiner Fahrten")
        XCTAssertEqual(KpiQuestion.net.title, "Ersparnis nach Ticketkosten")
        XCTAssertEqual(KpiQuestion.breakEven.title, "Fehlt bis Break-even")
        XCTAssertEqual(Set(KpiQuestion.allCases.map(\.title)).count, KpiQuestion.allCases.count)
    }
}

final class SiriSpokenTests: XCTestCase {
    func testEuro() {
        XCTAssertEqual(KpiSpoken.euro(212.4), "212 Euro 40")
        XCTAssertEqual(KpiSpoken.euro(186), "186 Euro")
        XCTAssertEqual(KpiSpoken.euro(0.4), "40 Cent")
        XCTAssertEqual(KpiSpoken.euro(0), "0 Euro")
        XCTAssertEqual(KpiSpoken.euro(1_044.49), "1.044 Euro")
        XCTAssertEqual(KpiSpoken.euro(999.996), "1.000 Euro")
        XCTAssertEqual(KpiSpoken.euro(3.05), "3 Euro 5")
        XCTAssertEqual(KpiSpoken.euro(-12.5), "minus 12 Euro 50")
    }

    func testCountsAndUnits() {
        XCTAssertEqual(KpiSpoken.trips(1), "1 Fahrt")
        XCTAssertEqual(KpiSpoken.trips(0), "0 Fahrten")
        XCTAssertEqual(KpiSpoken.trips(1_204), "1.204 Fahrten")
        XCTAssertEqual(KpiSpoken.days(1), "1 Tag")
        XCTAssertEqual(KpiSpoken.days(45), "45 Tage")
        XCTAssertEqual(KpiSpoken.km(3.44), "3,4 Kilometer")
        XCTAssertEqual(KpiSpoken.km(1.0), "1 Kilometer")
        XCTAssertEqual(KpiSpoken.km(412.4), "412 Kilometer")
        XCTAssertEqual(KpiSpoken.co2(3.4), "3,4 Kilogramm")
        XCTAssertEqual(KpiSpoken.co2(1.02), "1 Kilogramm")
        XCTAssertEqual(KpiSpoken.co2(58.2), "58 Kilogramm")
        XCTAssertEqual(KpiSpoken.co2(1_403.2), "1,4 Tonnen")
        XCTAssertEqual(KpiSpoken.co2(999.6), "1 Tonne")
        XCTAssertEqual(KpiSpoken.co2(1_403.2, format: FormatPrefs(co2: .kilograms)), "1.403 Kilogramm")
        XCTAssertEqual(KpiSpoken.writtenCO2(3.4), "3,4 kg")
        XCTAssertEqual(KpiSpoken.writtenCO2(2_000), "2 t")
        XCTAssertEqual(KpiSpoken.writtenKm(0.5), "0,5 km")
        XCTAssertEqual(KpiSpoken.writtenEuro(186.4).plainSpaces, "€ 186,40")
        XCTAssertEqual(KpiSpoken.writtenEuro(186.4, format: FormatPrefs(amounts: .whole)).plainSpaces, "€ 186")
    }

    func testDates() {
        let cal = Calendar.vienna
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        XCTAssertEqual(KpiSpoken.date(cal.date(from: DateComponents(year: 2026, month: 1, day: 6))!, now: now), "6. Jänner")
        XCTAssertEqual(KpiSpoken.date(cal.date(from: DateComponents(year: 2027, month: 3, day: 1))!, now: now), "1. März 2027")
    }
}
