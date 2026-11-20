import XCTest
@testable import KlimaCore

// MARK: uebersicht – goals per Vienna calendar month and „Break-even bis …“ (docs/DASHBOARD_LAYOUT.md §4).
final class GoalsTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func ticket(price: Double = 1300) -> TicketPeriod {
        let start = date(2026, 3, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, fare: Double = 10, km: Double = 50, journey: UUID? = nil, leg: Int = 0) -> TripRecord {
        TripRecord(date: d, fromName: "A", toName: "B", mode: .train, distanceKm: km, fareEUR: fare, journeyID: journey, legIndex: leg)
    }

    let format = GoalFormatter(euro: { "€ \(Int($0.rounded()))" }, kg: { "\(Int($0.rounded())) kg" },
                               day: { d in
                                   let c = Calendar.vienna.dateComponents([.day, .month], from: d)
                                   return "\(c.day!).\(c.month!)."
                               })

    func evaluate(_ goal: Goal, _ trips: [TripRecord], now: Date, price: Double = 1300) -> GoalProgress {
        evaluate(goal, trips, now: now, ticket: ticket(price: price))
    }

    func evaluate(_ goal: Goal, _ trips: [TripRecord], now: Date, ticket t: TicketPeriod) -> GoalProgress {
        let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: now, calendar: cal)
        return GoalEvaluator.evaluate(goal, trips: trips, ticket: t, summary: summary, now: now, calendar: cal)
    }

    /// A ticket year from `start` (00:00) to the day before its anniversary.
    func ticket(from start: Date, price: Double = 1300) -> TicketPeriod {
        TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price, start: start,
                     end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    // MARK: Month boundaries

    func testThirtyOneDayMonthWithSpringDST() {
        // March 2026: 31 days, clocks go forward on Sunday 29 March.
        let goal = Goal(kind: .tripsPerMonth, target: 31)
        let trips = [trip(date(2026, 3, 1, 0, 5)), trip(date(2026, 3, 29, 3, 30)), trip(date(2026, 3, 31, 23, 50)),
                     trip(date(2026, 4, 1, 0, 10)), trip(date(2026, 2, 28, 23, 59))]
        let lastDay = evaluate(goal, trips, now: date(2026, 3, 31, 23, 55))
        XCTAssertEqual(lastDay.actual, 3, "1 March 00:05 and 31 March 23:50 count, 1 April and February do not")
        XCTAssertEqual(lastDay.daysLeft, 1)
        XCTAssertEqual(lastDay.periodKey, "2026-03")
        XCTAssertEqual(lastDay.expectedNow, 30, accuracy: 1e-9, "30 completed days of 31")
        XCTAssertEqual(GoalText.remaining(lastDay, format: format), "noch 28 Fahrten · heute ist der letzte Tag")

        let dstDay = evaluate(goal, trips, now: date(2026, 3, 29, 12))
        XCTAssertEqual(dstDay.daysLeft, 3, "29, 30, 31 – the short day is a whole day")
        XCTAssertEqual(dstDay.expectedNow, 28, accuracy: 1e-9)
        XCTAssertEqual(dstDay.actual, 3, "a trip logged ahead for the 31st counts, like in Statistik's month")
    }

    func testAutumnDSTMonth() {
        // October 2026: 31 days, clocks go back on Sunday 25 October (the 25th has 25 hours).
        let goal = Goal(kind: .valuePerMonth, target: 310)
        let trips = (1...25).map { trip(date(2026, 10, $0, $0 == 25 ? 2 : 8, 30)) }
        let p = evaluate(goal, trips, now: date(2026, 10, 26, 7))
        XCTAssertEqual(p.actual, 250, accuracy: 1e-9)
        XCTAssertEqual(p.expectedNow, 250, accuracy: 1e-9, "25 completed days × € 10")
        XCTAssertEqual(p.state, .onTrack, "exactly on pace")
        XCTAssertEqual(p.daysLeft, 6)
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch € 60 · 6 Tage übrig")
        // The value is the Statistik month bucket's value.
        let bucket = StatsAggregator.months(trips.filter { ticket().contains($0.date) }, in: ticket(), calendar: cal)
            .first { cal.component(.month, from: $0.month) == 10 }!
        XCTAssertEqual(p.actual, bucket.value, accuracy: 1e-9)
    }

    func testFebruary() {
        let goal = Goal(kind: .tripsPerMonth, target: 28)
        let trips = (1...27).map { trip(date(2027, 2, $0)) }
        let p = evaluate(goal, trips, now: date(2027, 2, 28, 9))
        XCTAssertEqual(p.daysLeft, 1, "February 2027 has 28 days")
        XCTAssertEqual(p.expectedNow, 27, accuracy: 1e-9)
        XCTAssertEqual(p.state, .onTrack)
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch 1 Fahrt · heute ist der letzte Tag")
        XCTAssertEqual(p.periodKey, "2027-02")
        // A trip after the ticket's last day does not count (the goal reads the ticket year like Statistik).
        let afterEnd = evaluate(goal, [trip(date(2027, 3, 1, 9))], now: date(2027, 3, 2, 9))
        XCTAssertEqual(afterEnd.actual, 0)
    }

    func testFirstDayWithoutTrips() {
        let goal = Goal(kind: .tripsPerMonth, target: 20)
        let p = evaluate(goal, [], now: date(2026, 11, 1, 7))
        XCTAssertEqual(p.actual, 0)
        XCTAssertEqual(p.progress, 0)
        XCTAssertEqual(p.state, .onTrack, "nothing is expected before the first day is over")
        XCTAssertNil(p.projectedValue, "no projection in the first days")
        XCTAssertNil(GoalText.projection(p, format: format))
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch 20 Fahrten · etwa 5 pro Woche")
        XCTAssertEqual(GoalText.status(p, format: format), "0 von 20 Fahrten")
    }

    func testOvershoot() {
        let goal = Goal(kind: .tripsPerMonth, target: 20)
        let trips = (1...30).map { trip(date(2026, 11, ($0 % 15) + 1, 6 + $0 / 15)) }
        let p = evaluate(goal, trips, now: date(2026, 11, 16, 20))
        XCTAssertEqual(p.progress, 1.5, accuracy: 1e-9)
        XCTAssertEqual(p.ringFraction, 1)
        XCTAssertEqual(p.state, .reached)
        XCTAssertNil(p.projectedValue, "no projection once reached")
        XCTAssertEqual(GoalText.remaining(p, format: format), "10 Fahrten über dem Ziel")
        XCTAssertEqual(GoalText.status(p, format: format), "30 von 20 Fahrten")
        let exact = evaluate(goal, Array(trips.prefix(20)), now: date(2026, 11, 16, 20))
        XCTAssertEqual(GoalText.remaining(exact, format: format), "Genau aufs Ziel")
        let one = evaluate(goal, Array(trips.prefix(21)), now: date(2026, 11, 16, 20))
        XCTAssertEqual(GoalText.remaining(one, format: format), "1 Fahrt über dem Ziel")
        XCTAssertEqual(GoalText.stateLabel(p.state), "Geschafft")
    }

    func testExactlyOnPaceAndBehind() {
        // November: 30 days. On the 11th, ten days are complete: 10 of 30 is on pace, 9 is behind.
        let goal = Goal(kind: .tripsPerMonth, target: 30)
        let ten = (1...10).map { trip(date(2026, 11, $0)) }
        let onPace = evaluate(goal, ten, now: date(2026, 11, 11, 6))
        XCTAssertEqual(onPace.expectedNow, 10, accuracy: 1e-9)
        XCTAssertEqual(onPace.state, .onTrack)
        XCTAssertEqual(evaluate(goal, Array(ten.dropLast()), now: date(2026, 11, 11, 6)).state, .behind)
        // Trips round down the fractional pace: 20 trips by the 17th expect 10,67 → 10 is still on track.
        let goal20 = Goal(kind: .tripsPerMonth, target: 20)
        XCTAssertEqual(evaluate(goal20, ten, now: date(2026, 11, 17, 6)).state, .onTrack)
        XCTAssertEqual(evaluate(goal20, Array(ten.dropLast()), now: date(2026, 11, 17, 6)).state, .behind)
        // Euros do not round.
        let value = Goal(kind: .valuePerMonth, target: 200)
        XCTAssertEqual(evaluate(value, ten, now: date(2026, 11, 17, 6)).state, .behind, "€ 100 < € 106,67")
    }

    func testProjectionFromTheSeventh() {
        let goal = Goal(kind: .tripsPerMonth, target: 20)
        let trips = (1...7).map { trip(date(2026, 11, $0)) }
        XCTAssertNil(evaluate(goal, trips, now: date(2026, 11, 6, 20)).projectedValue)
        let p = evaluate(goal, trips, now: date(2026, 11, 7, 20))
        XCTAssertEqual(p.projectedValue!, 30, accuracy: 1e-9, "7 trips in 7 days → 30 in 30")
        XCTAssertEqual(GoalText.projection(p, format: format), "Prognose: etwa 30 Fahrten bis Monatsende")
    }

    // MARK: review-uebersicht – the days of the month the ticket covers

    func testTicketStartingMidMonthMeasuresThePaceFromItsFirstDay() {
        // A ticket from 15 November: on the 16th, two trips are on pace for 20 in the 16 days it covers this month (before, the
        // 14 days without a ticket counted too and a brand-new holder read „Hinter Plan“ with „Prognose: etwa 4 Fahrten“).
        let t = ticket(from: date(2026, 11, 15, 0))
        let goal = Goal(kind: .tripsPerMonth, target: 20)
        let two = [trip(date(2026, 11, 15, 9)), trip(date(2026, 11, 15, 18))]
        let p = evaluate(goal, two, now: date(2026, 11, 16, 12), ticket: t)
        XCTAssertEqual(p.expectedNow, 20.0 / 16, accuracy: 1e-9, "1 of 16 covered days is complete")
        XCTAssertEqual(p.state, .onTrack)
        XCTAssertEqual(p.daysLeft, 15)
        XCTAssertNil(p.startsOn)
        XCTAssertNil(p.endsOn)
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch 18 Fahrten · etwa 9 pro Woche")
        // From the seventh covered day the projection runs over the covered days, to the end of the month.
        let week = (15...21).map { trip(date(2026, 11, $0)) }
        let later = evaluate(goal, week, now: date(2026, 11, 21, 20), ticket: t)
        XCTAssertEqual(later.projectedValue!, 7.0 / 7 * 16, accuracy: 1e-9)
        XCTAssertEqual(GoalText.projection(later, format: format), "Prognose: etwa 16 Fahrten bis Monatsende")
        // Before the ticket starts nothing is due yet, and the line says from when it counts.
        let before = evaluate(goal, [], now: date(2026, 11, 10, 12), ticket: t)
        XCTAssertEqual(before.state, .onTrack)
        XCTAssertEqual(before.expectedNow, 0)
        XCTAssertEqual(before.daysLeft, 16)
        XCTAssertEqual(before.startsOn, date(2026, 11, 15, 0))
        XCTAssertEqual(GoalText.remaining(before, format: format), "noch 20 Fahrten · zählt ab 15.11.")
    }

    func testTicketEndingMidMonth() {
        // A ticket from 12 March 2026 is valid through 11 March 2027: in March 2027 eleven days count.
        let t = ticket(from: date(2026, 3, 12, 0))
        let goal = Goal(kind: .tripsPerMonth, target: 10)
        let trips = (1...4).map { trip(date(2027, 3, $0)) } + [trip(date(2027, 3, 12, 9))]
        let p = evaluate(goal, trips, now: date(2027, 3, 5, 9), ticket: t)
        XCTAssertEqual(p.actual, 4, "the trip on the 12th lies after the ticket")
        XCTAssertEqual(p.daysLeft, 7, "5th to 11th")
        XCTAssertEqual(p.expectedNow, 10.0 * 4 / 11, accuracy: 1e-9)
        XCTAssertEqual(p.endsOn, date(2027, 3, 11, 0))
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch 6 Fahrten · 7 Tage bis Ticketende")
        let ninth = evaluate(goal, trips, now: date(2027, 3, 9, 20), ticket: t)
        XCTAssertEqual(ninth.projectedValue!, 4.0 / 9 * 11, accuracy: 1e-9)
        XCTAssertEqual(GoalText.projection(ninth, format: format), "Prognose: etwa 5 Fahrten bis Ticketende")
        let lastDay = evaluate(goal, trips, now: date(2027, 3, 11, 9), ticket: t)
        XCTAssertEqual(GoalText.remaining(lastDay, format: format), "noch 6 Fahrten · heute endet dein Ticket")
        // After its last day nothing more can count: not „Hinter Plan · etwa 5 pro Woche“ for 20 days without a ticket.
        let after = evaluate(goal, trips, now: date(2027, 3, 20, 9), ticket: t)
        XCTAssertEqual(after.state, .missed)
        XCTAssertEqual(after.daysLeft, 0)
        XCTAssertNil(after.projectedValue)
        XCTAssertEqual(GoalText.remaining(after, format: format), "Dein Ticket galt bis 11.3. · 6 Fahrten fehlten")
        XCTAssertEqual(GoalText.stateLabel(after.state), "Nicht geschafft")
    }

    func testMonthOutsideTheTicketRests() {
        let goal = Goal(kind: .valuePerMonth, target: 100)
        let expired = evaluate(goal, [trip(date(2027, 5, 2))], now: date(2027, 5, 10), ticket: ticket())
        XCTAssertEqual(expired.state, .paused, "the ticket ended in February – nothing in May can count")
        XCTAssertEqual(expired.actual, 0)
        XCTAssertNil(expired.projectedValue)
        XCTAssertEqual(GoalText.stateLabel(expired.state), "Ruht")
        XCTAssertEqual(GoalText.remaining(expired, format: format), "Dein Ticket gilt in diesem Monat nicht – es zählt nur im Ticketjahr")
        XCTAssertNil(GoalText.projection(expired, format: format))
        let upcoming = evaluate(goal, [], now: date(2026, 11, 20), ticket: ticket(from: date(2026, 12, 1, 0)))
        XCTAssertEqual(upcoming.state, .paused)
        XCTAssertEqual(GoalText.remaining(upcoming, format: format), "Dein Ticket gilt ab 1.12. – dann zählt es")
        var ledger = GoalLedger()
        XCTAssertFalse(ledger.celebrate(expired), "a resting goal never pops")
    }

    func testJourneysCountOnce() {
        let journey = UUID()
        let trips = [trip(date(2026, 11, 3, 7), journey: journey, leg: 0), trip(date(2026, 11, 3, 8), journey: journey, leg: 1),
                     trip(date(2026, 11, 4, 7))]
        let p = evaluate(Goal(kind: .tripsPerMonth, target: 10), trips, now: date(2026, 11, 5))
        XCTAssertEqual(p.actual, 2)
    }

    func testCO2Goal() {
        let goal = Goal(kind: .co2PerMonth, target: 30)
        let trips = [trip(date(2026, 11, 2), km: 100), trip(date(2026, 11, 3), km: 50)]
        let p = evaluate(goal, trips, now: date(2026, 11, 10))
        let expected = EmissionFactors.fallback.savedKg(km: 150, mode: .train)
        XCTAssertEqual(p.actual, expected, accuracy: 1e-9)
        XCTAssertEqual(GoalText.title(goal, format: format), "30 kg CO₂ im Monat")
    }

    func testPlurals() {
        XCTAssertEqual(GoalText.trips(1), "1 Fahrt")
        XCTAssertEqual(GoalText.trips(2), "2 Fahrten")
        XCTAssertEqual(GoalText.title(Goal(kind: .tripsPerMonth, target: 1), format: format), "1 Fahrt im Monat")
        XCTAssertEqual(GoalText.title(Goal(kind: .valuePerMonth, target: 150), format: format), "€ 150 Wert im Monat")
        let goal = Goal(kind: .tripsPerMonth, target: 5)
        let p = evaluate(goal, (1...3).map { trip(date(2026, 11, $0)) }, now: date(2026, 11, 29, 9))
        XCTAssertEqual(GoalText.remaining(p, format: format), "noch 2 Fahrten · 2 Tage übrig")
        let one = evaluate(goal, (1...4).map { trip(date(2026, 11, $0)) }, now: date(2026, 11, 3, 9))
        XCTAssertEqual(GoalText.remaining(one, format: format), "noch 1 Fahrt · etwa 1 pro Woche")
    }

    func testTargetsAreClampedToTheSteppers() {
        XCTAssertEqual(Goal(kind: .tripsPerMonth, target: 0).target, 1)
        XCTAssertEqual(Goal(kind: .tripsPerMonth, target: 500).target, 100)
        XCTAssertEqual(Goal(kind: .valuePerMonth, target: 123).target, 120)
        XCTAssertEqual(Goal(kind: .valuePerMonth, target: 5).target, 10)
        XCTAssertEqual(Goal(kind: .valuePerMonth, target: 9999).target, 2000)
        XCTAssertEqual(Goal(kind: .co2PerMonth, target: 501).target, 500)
        XCTAssertEqual(Goal(kind: .tripsPerMonth, target: .nan).target, 20)
    }

    // MARK: Break-even bis

    func testBreakEvenByWithoutForecast() {
        let goal = Goal(kind: .breakEvenBy, until: date(2026, 12, 31))
        let p = evaluate(goal, [], now: date(2026, 4, 1, 12))
        XCTAssertNil(p.projectedDate, "no trips, no pace, no Prognose")
        XCTAssertNil(GoalText.projection(p, format: format))
        XCTAssertEqual(p.state, .behind, "a month without value is behind the linear pace")
        XCTAssertEqual(p.target, 1300)
        XCTAssertEqual(GoalText.title(goal, format: format), "Break-even bis 31.12.")
        XCTAssertTrue(GoalText.remaining(p, format: format).hasPrefix("noch € 1300 · "))
    }

    func testBreakEvenByFollowsTheForecast() {
        let goal = Goal(kind: .breakEvenBy, until: date(2026, 9, 30))
        let trips = (1...40).map { trip(cal.date(byAdding: .day, value: $0 - 1, to: date(2026, 3, 1))!, fare: 15) }
        let now = date(2026, 4, 10, 20)
        let t = ticket()
        let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: now, calendar: cal)
        let p = GoalEvaluator.evaluate(goal, trips: trips, ticket: t, summary: summary, now: now, calendar: cal)
        XCTAssertEqual(p.projectedDate, summary.forecastBreakEvenDate, "the Bilanz card's Prognose")
        XCTAssertNotNil(p.projectedDate)
        XCTAssertEqual(p.state, cal.startOfDay(for: summary.forecastBreakEvenDate!) <= date(2026, 9, 30, 0) ? .onTrack : .behind)
        XCTAssertTrue(GoalText.projection(p, format: format)!.hasPrefix("Prognose: Break-even am "))
    }

    func testBreakEvenByReachedAndMissed() {
        let goal = Goal(kind: .breakEvenBy, until: date(2026, 6, 30))
        let trips = [trip(date(2026, 5, 1), fare: 700), trip(date(2026, 5, 2), fare: 700)]
        let reached = evaluate(goal, trips, now: date(2026, 5, 3))
        XCTAssertEqual(reached.state, .reached)
        XCTAssertGreaterThan(reached.progress, 1)
        XCTAssertNil(reached.projectedDate)
        XCTAssertEqual(GoalText.remaining(reached, format: format), "Dein Ticket hat sich rentiert")

        let late = [trip(date(2026, 5, 1), fare: 700), trip(date(2026, 7, 2), fare: 700)]
        let missed = evaluate(goal, late, now: date(2026, 7, 3))
        XCTAssertEqual(missed.state, .missed, "paid off after the goal's day")
        XCTAssertEqual(GoalText.stateLabel(missed.state), "Nicht geschafft")
        // review-uebersicht: it said „Der Tag ist vorbei · noch € 0 bis zum Break-even“ for a ticket that had paid off.
        XCTAssertEqual(missed.paidOffOn, date(2026, 7, 2, 0))
        XCTAssertEqual(GoalText.remaining(missed, format: format), "Break-even am 2.7. – nach dem Tag")
        XCTAssertNil(GoalText.projection(missed, format: format))
        // A trip logged ahead past the day pays it off – still not by the day, and nothing is „noch € 0“.
        let ahead = evaluate(goal, late, now: date(2026, 6, 10))
        XCTAssertEqual(ahead.state, .behind)
        XCTAssertEqual(GoalText.remaining(ahead, format: format), "Break-even am 2.7. – nach dem Tag")
        let open = evaluate(goal, [trip(date(2026, 5, 1), fare: 700)], now: date(2026, 7, 3))
        XCTAssertEqual(open.state, .missed)
        XCTAssertEqual(GoalText.remaining(open, format: format), "Der Tag ist vorbei · noch € 600 bis zum Break-even")
    }

    func testBreakEvenForecastAfterTheTicketEndIsNoDate() {
        // Ten trips of € 10 in March: at that pace the break-even would come long after the ticket ended. The Bilanz card says
        // „Fehlt bei Ablauf“; the goal must not say „Prognose: Break-even am …“ for a day the ticket no longer covers.
        let goal = Goal(kind: .breakEvenBy, until: date(2026, 12, 31))
        let trips = (2...11).map { trip(date(2026, 3, $0)) }
        let now = date(2026, 4, 10, 12)
        let summary = SavingsCalculator.summary(ticket: ticket(), trips: trips, now: now, calendar: cal)
        XCTAssertNotNil(summary.forecastBreakEvenDate)
        XCTAssertFalse(summary.forecastReachesBreakEven)
        let p = evaluate(goal, trips, now: now)
        XCTAssertEqual(p.state, .behind)
        XCTAssertNil(p.projectedDate)
        XCTAssertTrue(p.forecastMissesTicketEnd)
        XCTAssertEqual(GoalText.projection(p, format: format), "Prognose: kein Break-even bis zum Ablauf")
    }

    func testBreakEvenDayOutsideTheTicketRests() {
        // A goal kept from the last ticket: its day lies before this ticket's first day.
        let goal = Goal(kind: .breakEvenBy, until: date(2026, 2, 20))
        let p = evaluate(goal, [trip(date(2026, 3, 5))], now: date(2026, 3, 10))
        XCTAssertEqual(p.state, .paused)
        XCTAssertNil(p.projectedDate)
        XCTAssertEqual(GoalText.remaining(p, format: format), "Der Tag liegt außerhalb deines Ticketjahrs")
        // An own share of € 0 is paid off from the first day.
        let free = evaluate(Goal(kind: .breakEvenBy, until: date(2026, 3, 1)), [trip(date(2026, 3, 9))], now: date(2026, 3, 10),
                            price: 0)
        XCTAssertEqual(free.state, .reached)
    }

    func testDateRangeIsInsideTheTicket() {
        let t = ticket()
        let range = GoalEvaluator.dateRange(for: t, now: date(2026, 11, 20, 15), calendar: cal)
        XCTAssertEqual(range.lowerBound, cal.startOfDay(for: date(2026, 11, 20)))
        XCTAssertEqual(range.upperBound, cal.startOfDay(for: t.end))
        let expired = GoalEvaluator.dateRange(for: t, now: date(2027, 5, 1), calendar: cal)
        XCTAssertEqual(expired.lowerBound, expired.upperBound)
    }

    // MARK: Storage and ledger

    func testListCapsAndRoundTrips() {
        var list = GoalList()
        XCTAssertTrue(list.upsert(Goal(kind: .tripsPerMonth, target: 20)))
        XCTAssertTrue(list.upsert(Goal(kind: .valuePerMonth, target: 150)))
        XCTAssertTrue(list.upsert(Goal(kind: .breakEvenBy, until: date(2026, 12, 1))))
        XCTAssertFalse(list.upsert(Goal(kind: .co2PerMonth, target: 30)), "at most three")
        var edited = list.goals[0]
        edited.target = 25
        XCTAssertTrue(list.upsert(edited))
        XCTAssertEqual(list.goals[0].target, 25)
        let decoded = GoalList.decode(list.encoded())
        XCTAssertEqual(decoded, list)
        list.remove(id: edited.id)
        XCTAssertEqual(list.goals.count, 2)
        XCTAssertFalse(GoalList().isFull)
        var noDate = GoalList()
        XCTAssertFalse(noDate.upsert(Goal(kind: .breakEvenBy)), "a date goal needs its day")
    }

    func testListGarbage() {
        for text in ["", "[]", "{}", "{\"goals\":[]}", "{\"version\":3,\"goals\":[]}"] {
            XCTAssertEqual(GoalList.decode(Data(text.utf8)), .empty, text)
        }
        let id = UUID().uuidString
        let mixed = GoalList.decode(Data("""
            {"version":1,"goals":[7,{"id":"\(id)","kind":"tripsPerMonth","target":"zwanzig"},{"kind":"valuePerMonth","target":150},
            {"id":"\(UUID().uuidString)","kind":"weather","target":3},{"id":"\(UUID().uuidString)","kind":"breakEvenBy"}]}
            """.utf8))
        XCTAssertEqual(mixed.goals.count, 1, "only the trips goal has an id and a known kind; the date goal lacks its day")
        XCTAssertEqual(mixed.goals[0].target, 20, "a bad target becomes the suggestion")
    }

    func testLedgerFiresOncePerPeriod() {
        var ledger = GoalLedger()
        let goal = Goal(kind: .tripsPerMonth, target: 2)
        let trips = [trip(date(2026, 11, 2)), trip(date(2026, 11, 3)), trip(date(2026, 12, 2)), trip(date(2026, 12, 3))]
        let behind = evaluate(goal, [trips[0]], now: date(2026, 11, 2, 12))
        XCTAssertFalse(ledger.celebrate(behind), "not reached")
        let november = evaluate(goal, trips, now: date(2026, 11, 4))
        XCTAssertTrue(ledger.celebrate(november))
        XCTAssertFalse(ledger.celebrate(november), "once per period")
        XCTAssertFalse(ledger.celebrate(evaluate(goal, trips, now: date(2026, 11, 20))), "the same month later")
        let december = evaluate(goal, trips, now: date(2026, 12, 4))
        XCTAssertTrue(ledger.celebrate(december), "a new month is a new period")
        let restored = GoalLedger.decode(ledger.encoded())
        var copy = restored
        XCTAssertFalse(copy.celebrate(december), "survives a relaunch")
        XCTAssertTrue(restored.hasCelebrated(november))

        var seen = GoalLedger()
        seen.markSeen(november)
        XCTAssertFalse(seen.celebrate(november), "a goal saved while already met never pops")

        var full = GoalLedger((0..<60).map { "x\($0)" })
        XCTAssertEqual(full.entries.count, GoalLedger.capacity)
        XCTAssertTrue(full.celebrate(december))
        XCTAssertEqual(full.entries.count, GoalLedger.capacity)
        XCTAssertEqual(GoalLedger.decode(Data("garbage".utf8)), GoalLedger())
    }
}
