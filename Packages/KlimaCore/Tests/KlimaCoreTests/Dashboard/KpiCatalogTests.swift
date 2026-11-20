import XCTest
@testable import KlimaCore

// MARK: uebersicht – the KPI tiles read what Statistik reads (docs/DASHBOARD_LAYOUT.md §3): the same trips give the same numbers as the
// pipeline of Analytics.make (SavingsCalculator.summary, StatsAggregator.records, StatsAggregator.topRoutes).
final class KpiCatalogTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func ticket(price: Double = 1300) -> TicketPeriod {
        let start = date(2026, 3, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    /// A fixed ticket year: commutes, a weekend trip, a three-leg journey and one trip outside the period.
    func goldenTrips() -> [TripRecord] {
        var trips: [TripRecord] = []
        for day in [2, 3, 4, 5, 6, 9, 10, 11, 23, 24] {
            trips.append(TripRecord(date: date(2026, 3, day), fromName: "Innsbruck Hbf", toName: "Wörgl Hbf", mode: .train,
                                    distanceKm: 56, fareEUR: 13.4, isRoundTrip: true, states: ["T"]))
        }
        trips.append(TripRecord(date: date(2026, 4, 18, 10), fromName: "Innsbruck Hbf", toName: "St. Anton am Arlberg", mode: .train,
                                distanceKm: 101, fareEUR: 23.5, states: ["T"]))
        let journey = UUID()
        trips.append(TripRecord(date: date(2026, 5, 2, 7), fromName: "Innsbruck Hbf", toName: "Salzburg Hbf", mode: .train,
                                distanceKm: 185, fareEUR: 42.9, states: ["T", "S"], journeyID: journey, legIndex: 0))
        trips.append(TripRecord(date: date(2026, 5, 2, 9), fromName: "Salzburg Hbf", toName: "Mirabellplatz", mode: .bus,
                                distanceKm: 2, fareEUR: 2.5, states: ["S"], journeyID: journey, legIndex: 1))
        trips.append(TripRecord(date: date(2026, 5, 2, 9), fromName: "Mirabellplatz", toName: "Hellbrunn", mode: .bus,
                                distanceKm: 6, fareEUR: 2.5, states: ["S"], journeyID: journey, legIndex: 2))
        trips.append(TripRecord(date: date(2026, 2, 27), fromName: "Wien Hbf", toName: "Graz Hbf", mode: .train,
                                distanceKm: 211, fareEUR: 48, states: ["W", "St"]))
        return trips
    }

    func input(now: Date, price: Double = 1300, week: Int? = 3) -> (KpiInput, SavingsSummary, TravelRecords, [RouteStat]) {
        let t = ticket(price: price)
        let records = goldenTrips().filter { t.contains($0.date) }
        let summary = SavingsCalculator.summary(ticket: t, trips: goldenTrips(), now: now, calendar: cal)
        let stats = StatsAggregator.records(records, now: now, calendar: cal)
        let routes = StatsAggregator.topRoutes(records, limit: 5)
        return (KpiInput(summary: summary, longestStreakDays: stats.longestStreakDays, topRoute: routes.first, tripsThisWeek: week,
                         ticketYear: "2026/27"), summary, stats, routes)
    }

    func testCatalogHasAtMostSixteenKinds() {
        XCTAssertLessThanOrEqual(KpiKind.allCases.count, 16)
        XCTAssertEqual(Set(KpiKind.allCases.map(\.title)).count, KpiKind.allCases.count, "titles are unique")
        for kind in KpiKind.allCases {
            XCTAssertFalse(kind.explanation.isEmpty)
            XCTAssertFalse(kind.symbol.isEmpty)
        }
    }

    func testGoldenValuesEqualTheSummary() {
        let (input, s, stats, routes) = input(now: date(2026, 6, 1, 12))
        // The fixture's own totals, worked out by hand: 10 commutes × 2 × 13,40 + 23,50 + 42,90 + 2,50 + 2,50.
        let fixtureValue: Double = 339.4
        XCTAssertEqual(s.totalValue, fixtureValue, accuracy: 0.001)
        XCTAssertEqual(s.tripCount, 12, "the three legs count once")
        XCTAssertEqual(s.travelDays, 12)
        let km: Double = 10 * 112 + 101 + 185 + 2 + 6
        XCTAssertEqual(s.distanceKm, km, accuracy: 0.001)

        func value(_ kind: KpiKind) -> Double? { KpiCatalog.reading(kind, input: input).value }
        XCTAssertEqual(value(.totalValue), s.totalValue)
        XCTAssertEqual(value(.net), s.net)
        XCTAssertEqual(value(.net)!, 339.4 - 1300, accuracy: 0.001)
        XCTAssertEqual(value(.tripCount), Double(s.tripCount))
        XCTAssertEqual(value(.travelDays), Double(s.travelDays))
        XCTAssertEqual(value(.distance), s.distanceKm)
        XCTAssertEqual(value(.co2), s.co2SavedKg)
        XCTAssertEqual(value(.averageValue), s.averageValuePerTrip)
        XCTAssertEqual(value(.averageValue)!, 339.4 / 12, accuracy: 0.001)
        XCTAssertEqual(value(.costPerDay), s.costPerDay)
        XCTAssertEqual(value(.costPerDay)!, 1300 / 365, accuracy: 0.001)
        XCTAssertEqual(value(.valuePerDay), s.valuePerDay)
        XCTAssertEqual(value(.pricePerKm), s.effectivePricePerKm)
        XCTAssertEqual(value(.carComparison), s.carCostEquivalent)
        XCTAssertEqual(value(.daysRemaining), Double(s.daysRemaining))
        XCTAssertEqual(value(.forecastEndValue), s.forecastEndValue)
        XCTAssertEqual(value(.tripsThisWeek), 3)
        XCTAssertEqual(value(.longestStreak), Double(stats.longestStreakDays))
        XCTAssertEqual(value(.longestStreak), 5, "2–6 March")

        let route = KpiCatalog.reading(.favoriteRoute, input: input)
        XCTAssertEqual(route.text, "\(routes[0].fromName) ↔ \(routes[0].toName)")
        XCTAssertEqual(route.count, 10)
        XCTAssertNil(route.value)
        XCTAssertFalse(route.isEmpty)
    }

    func testEmptyTicketYearSaysNothingInsteadOfZeroAverages() {
        let t = ticket()
        let now = date(2026, 3, 1, 9)
        let summary = SavingsCalculator.summary(ticket: t, trips: [], now: now, calendar: cal)
        let input = KpiInput(summary: summary, longestStreakDays: 0, topRoute: nil, tripsThisWeek: nil, ticketYear: "2026/27")
        XCTAssertNil(KpiCatalog.reading(.averageValue, input: input).value, "no trip, no average")
        XCTAssertNil(KpiCatalog.reading(.pricePerKm, input: input).value, "no km, no price per km")
        XCTAssertNil(KpiCatalog.reading(.forecastEndValue, input: input).value, "no pace, no forecast")
        XCTAssertNil(KpiCatalog.reading(.tripsThisWeek, input: input).value)
        XCTAssertTrue(KpiCatalog.reading(.favoriteRoute, input: input).isEmpty)
        XCTAssertEqual(KpiCatalog.reading(.tripCount, input: input).value, 0)
        XCTAssertFalse(input.hasForecast)
        XCTAssertFalse(KpiCatalog.offered(for: input).contains(.forecastEndValue))
    }

    func testForecastOnlyWhileTheTicketRuns() {
        let running = input(now: date(2026, 6, 1, 12)).0
        XCTAssertTrue(running.hasForecast)
        XCTAssertTrue(KpiCatalog.offered(for: running).contains(.forecastEndValue))
        let expired = input(now: date(2027, 3, 10, 12)).0
        XCTAssertFalse(expired.hasForecast)
        XCTAssertNil(KpiCatalog.reading(.forecastEndValue, input: expired).value)
        XCTAssertEqual(KpiCatalog.reading(.forecastEndValue, input: running).subtitle, "Prognose · zum Ablauf")
    }

    func testPaidOffNetIsPositive() {
        let (input, s, _, _) = input(now: date(2026, 6, 1, 12), price: 200)
        XCTAssertTrue(s.isPaidOff)
        XCTAssertEqual(KpiCatalog.reading(.net, input: input).value!, 139.4, accuracy: 0.001)
    }

    func testSubtitles() {
        let input = input(now: date(2026, 6, 1, 12)).0
        XCTAssertEqual(KpiCatalog.reading(.tripCount, input: input).subtitle, "Ticketjahr 2026/27")
        XCTAssertEqual(KpiCatalog.reading(.tripsThisWeek, input: input).subtitle, "diese Woche")
        XCTAssertEqual(KpiCatalog.reading(.daysRemaining, input: input).subtitle, "Gültigkeit")
    }

    func testSelectionCapsDeduplicatesAndRoundTrips() {
        var selection = KpiSelection([.net, .net, .co2, .tripCount, .distance, .travelDays])
        XCTAssertEqual(selection.kinds, [.net, .co2, .tripCount, .distance])
        XCTAssertTrue(selection.isFull)
        XCTAssertFalse(selection.toggle(.travelDays), "a fifth tile does not fit")
        XCTAssertTrue(selection.toggle(.co2))
        XCTAssertEqual(selection.kinds, [.net, .tripCount, .distance])
        XCTAssertTrue(selection.toggle(.travelDays))
        selection.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(selection.kinds, [.travelDays, .net, .tripCount, .distance])
        XCTAssertEqual(KpiSelection.decode(selection.encoded()), selection)
        XCTAssertEqual(KpiCatalog.readings(selection.kinds, input: input(now: date(2026, 6, 1)).0).map(\.kind), selection.kinds)
    }

    func testSelectionGarbageGivesEmpty() {
        for text in ["", "[]", "{", "{\"kinds\":[\"net\"]}", "{\"version\":2,\"kinds\":[\"net\"]}", "{\"version\":1,\"kinds\":\"net\"}"] {
            XCTAssertEqual(KpiSelection.decode(Data(text.utf8)), .empty, text)
        }
        let mixed = KpiSelection.decode(Data(#"{"version":1,"kinds":["net",7,"weather","co2"]}"#.utf8))
        XCTAssertEqual(mixed.kinds, [.net, .co2])
        XCTAssertEqual(KpiCatalog.defaultTiles.count, KpiCatalog.maxTiles)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(KpiKind.allCases.map(\.rawValue), [
            "totalValue", "net", "tripCount", "travelDays", "distance", "co2", "averageValue", "costPerDay", "valuePerDay",
            "pricePerKm", "carComparison", "daysRemaining", "forecastEndValue", "tripsThisWeek", "longestStreak", "favoriteRoute",
        ])
    }
}
