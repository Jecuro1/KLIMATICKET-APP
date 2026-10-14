import XCTest
@testable import KlimaCore

/// Balance text, weekly recap and time-of-day route suggestion. Every number in a rule text must be a fact line number.
final class BalanceRecapRouteTests: XCTestCase {
    private let calendar = Calendar.vienna

    private func summary(price: Double, value: Double, trips: Int, paidOff: Bool, forecast: Date?, reaches: Bool,
                         endValue: Double, daysRemaining: Int) -> SavingsSummary {
        SavingsSummary(ticketPrice: price, totalValue: value, net: value - price, amortizedFraction: value / price,
                       tripCount: trips, legCount: trips, travelDays: trips, distanceKm: 412.4, co2SavedKg: 91.2,
                       carCostEquivalent: 0, daysElapsed: 100, daysTotal: 365, daysRemaining: daysRemaining,
                       costPerDay: 3.8, valuePerDay: 4.1, averageValuePerTrip: trips > 0 ? value / Double(trips) : 0,
                       effectivePricePerKm: nil, isPaidOff: paidOff, paidOffDate: nil, forecastBreakEvenDate: forecast,
                       forecastEndValue: endValue, forecastReachesBreakEven: reaches)
    }

    func testPhasesUseOnlySummaryFiguresAndTheirRuleTextMatchesFacts() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        let cases: [(SavingsSummary, Bool, BalanceFacts.Phase)] = [
            (summary(price: 1400, value: 1520, trips: 14, paidOff: true, forecast: nil, reaches: true, endValue: 1900, daysRemaining: 80), false, .paidOff),
            (summary(price: 1400, value: 1085, trips: 12, paidOff: false, forecast: date, reaches: true, endValue: 1800, daysRemaining: 60), false, .onTrack),
            (summary(price: 1400, value: 610, trips: 9, paidOff: false, forecast: nil, reaches: false, endValue: 1350, daysRemaining: 40), false, .behind),
            (summary(price: 1400, value: 1120, trips: 20, paidOff: false, forecast: nil, reaches: false, endValue: 1120, daysRemaining: 0), true, .expired),
        ]
        for (s, expired, phase) in cases {
            let facts = BalanceFacts.make(ticketName: "KlimaTicket Österreich 2026", summary: s, isExpired: expired, calendar: calendar)
            XCTAssertEqual(facts.phase, phase)
            // The rule text may use only numbers that the facts list contains (the same check the model text must pass).
            XCTAssertEqual(AssistantNumberGuard.unknown(in: facts.ruleText, facts: facts.lines), [],
                           "rule text uses a number that is not a fact: \(facts.ruleText)")
            XCTAssertFalse(facts.ruleText.isEmpty)
        }
    }

    func testBalanceWordingForBehindAndPaidOff() {
        let behind = BalanceFacts.make(ticketName: "KlimaTicket",
                                       summary: summary(price: 1400, value: 610, trips: 9, paidOff: false, forecast: nil,
                                                        reaches: false, endValue: 1350, daysRemaining: 40),
                                       isExpired: false, calendar: calendar)
        XCTAssertTrue(behind.lines.contains("Fehlt bis zum Preis: € 790"))
        XCTAssertTrue(behind.ruleText.contains("€ 790"))
        XCTAssertTrue(behind.ruleText.contains("noch nicht ganz"))
        let paid = BalanceFacts.make(ticketName: "KlimaTicket",
                                     summary: summary(price: 1400, value: 1520, trips: 1, paidOff: true, forecast: nil,
                                                      reaches: true, endValue: 1900, daysRemaining: 80),
                                     isExpired: false, calendar: calendar)
        XCTAssertTrue(paid.lines.contains("Gewinn bisher: € 120"))
        XCTAssertTrue(paid.ruleText.contains("eine Fahrt") == false, "a paid-off text does not talk about the trip count")
        XCTAssertFalse(paid.lines.contains { $0.hasPrefix("Break-even") })
    }

    func testWeeklyRecapCountsOnlyThisWeekUpToNow() {
        // Wednesday 14.10.2026, 9:00 Vienna. The week starts Monday 12.10.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))!
        let inWeek = TripRecord(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))!,
                                fromName: "Wien", toName: "Graz", mode: .train, distanceKm: 200, fareEUR: 30)
        let laterInWeek = TripRecord(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 18))!,
                                     fromName: "Graz", toName: "Wien", mode: .train, distanceKm: 200, fareEUR: 30, isRoundTrip: false)
        let lastWeek = TripRecord(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8))!,
                                  fromName: "Wien", toName: "Linz", mode: .train, distanceKm: 180, fareEUR: 25)
        let recap = WeeklyRecapFacts.make(trips: [inWeek, laterInWeek, lastWeek], now: now, calendar: calendar)
        XCTAssertEqual(recap.tripsThisWeek, 2)
        XCTAssertEqual(recap.valueThisWeek, 60)
        XCTAssertEqual(recap.ruleText, "Diese Woche: 2 Fahrten, Wert € 60, 400 km. Stand 14.10.")
        XCTAssertEqual(AssistantNumberGuard.unknown(in: recap.ruleText, facts: recap.lines), [],
                       "the trailing dot after the date is a sentence end; the numbers must still be facts")
        let empty = WeeklyRecapFacts.make(trips: [lastWeek], now: now, calendar: calendar)
        XCTAssertTrue(empty.ruleText.hasPrefix("Diese Woche ist noch keine Fahrt erfasst."))
    }

    func testRouteSuggestionNeedsRepeatedTripsNearNow() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour, minute: minute))!
        }
        let regular = RouteStarts(fromID: "wien", toID: "innsbruck", starts: [at(7, 5), at(7, 40), at(6, 50), at(17, 0)])
        let single = RouteStarts(fromID: "graz", toID: "linz", starts: [at(7, 30)])
        let now = at(7, 30)
        let suggestions = RouteTimeSuggestions.suggest([regular, single], now: now, calendar: calendar)
        XCTAssertEqual(suggestions.map { "\($0.fromID)>\($0.toID)" }, ["wien>innsbruck"])
        XCTAssertEqual(suggestions.first?.matching, 3)
        XCTAssertEqual(suggestions.first?.total, 4)
        XCTAssertTrue(RouteTimeSuggestions.suggest([regular], now: at(12, 0), calendar: calendar).isEmpty)
    }

    func testGroupingSkipsIncompleteAndSameStationTrips() {
        let t = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 7))!
        let groups = RouteStarts.group([(from: "a", to: "b", start: t), (from: "a", to: "b", start: t),
                                        (from: nil, to: "b", start: t), (from: "c", to: "c", start: t)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.starts.count, 2)
    }

    func testDemoFactsAreOnTrackAndTheirTextsUseOnlyFacts() {
        let demo = BalanceFacts.demo
        XCTAssertEqual(demo.phase, .onTrack)
        XCTAssertTrue(demo.lines.contains("Fehlt bis zum Preis: € 315"))
        XCTAssertTrue(demo.ruleText.contains("14.11."))
        XCTAssertEqual(AssistantNumberGuard.unknown(in: demo.ruleText, facts: demo.lines), [])
    }

    func testRouteSuggestionTextsUseOnlyFacts() {
        let suggestion = RouteTimeSuggestion(fromID: "a", toID: "b", matching: 3, total: 4)
        let facts = suggestion.facts(fromName: "Wien Hbf", toName: "Innsbruck Hbf")
        XCTAssertEqual(suggestion.ruleText(fromName: "Wien Hbf", toName: "Innsbruck Hbf"),
                       "Du fährst Wien Hbf – Innsbruck Hbf oft um diese Zeit: 3 von 4 Fahrten.")
        XCTAssertEqual(AssistantNumberGuard.unknown(in: suggestion.ruleText(fromName: "Wien Hbf", toName: "Innsbruck Hbf"), facts: facts), [])
        XCTAssertEqual(AssistantNumberGuard.unknown(in: "Du fährst oft um 7 Uhr", facts: facts), ["7"])
    }
}
