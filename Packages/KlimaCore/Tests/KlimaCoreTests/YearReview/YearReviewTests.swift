import XCTest
@testable import KlimaCore

/// The pages of the year story: skip rules, and that every figure equals what Statistik's calculators say.
final class YearReviewTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func ticket(price: Double = 1400, start: Date? = nil) -> TicketPeriod {
        let start = start ?? date(2026, 3, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, fare: Double = 20, km: Double = 100, from: String = "Innsbruck Hbf", to: String = "St. Anton am Arlberg",
              round: Bool = false, states: Set<String> = ["T"], category: TripCategory? = nil, induced: Bool = false,
              mode: TransportMode = .train, journey: UUID? = nil, leg: Int = 0) -> TripRecord {
        TripRecord(date: d, fromName: from, toName: to, mode: mode, distanceKm: km, fareEUR: fare, isRoundTrip: round, states: states,
                   category: category, isInduced: induced, journeyID: journey, legIndex: leg)
    }

    func review(_ trips: [TripRecord], ticket t: TicketPeriod? = nil, car: Bool = false, now: Date? = nil,
                stations: ((String) -> Station?)? = nil) -> YearReview {
        let t = t ?? ticket()
        let now = now ?? date(2026, 9, 1)
        let period = YearReviewPeriods.ticketPeriod(t)
        let carResult = car ? CarComparison.compare(ticket: t, trips: trips, profile: CarProfile(), now: now) : nil
        return YearReview.make(trips: trips, tickets: [t], car: carResult, period: period, now: now, stations: stations)
    }

    func kinds(_ review: YearReview) -> [YearReviewPageKind] { review.pages.map(\.kind) }

    // MARK: Skip rules

    func testNoTripsNoPages() {
        let r = review([])
        XCTAssertTrue(r.isEmpty)
        XCTAssertEqual(kinds(r), [])
        // A trip outside the period does not count either.
        let outside = review([trip(date(2025, 6, 1))])
        XCTAssertTrue(outside.isEmpty)
    }

    func testOneTripKeepsOnlyThePagesThatSaySomething() {
        let r = review([trip(date(2026, 4, 2), fare: 23.5, km: 101)])
        XCTAssertEqual(kinds(r), [.intro, .savings, .distance, .onTheRoad, .finale])
        XCTAssertEqual(r.intro?.tripCount, 1)
        XCTAssertNil(r.favoriteRoute, "one ride is no favourite")
        XCTAssertNil(r.rhythm, "one ride is no rhythm")
        XCTAssertNil(r.climate, "no car comparison, no climate page")
        // Everything that is shown is a finite, sensible number.
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertEqual(savings.totalValue, 23.5, accuracy: 0.001)
        XCTAssertEqual(savings.tripCount, 1)
        XCTAssertFalse(savings.isPaidOff)
        XCTAssertEqual(savings.remaining, 1400 - 23.5, accuracy: 0.001)
        XCTAssertNil(savings.breakEvenDate)
        XCTAssertEqual(r.onTheRoad?.states, [.tirol])
        XCTAssertEqual(r.onTheRoad?.longestTrip?.distanceKm, 101)
    }

    func testOneTripWithCarComparisonAddsTheClimatePage() {
        let r = review([trip(date(2026, 4, 2), fare: 23.5, km: 101)], car: true)
        XCTAssertEqual(kinds(r), [.intro, .savings, .distance, .onTheRoad, .climate, .finale])
        XCTAssertGreaterThan(r.climate?.co2SavedKg ?? 0, 0)
        XCTAssertEqual(r.finale?.co2SavedKg, r.climate?.co2SavedKg)
    }

    func testThreeDifferentTripsAddTheRhythmButNoFavourite() {
        let trips = [
            trip(date(2026, 4, 2), from: "Innsbruck Hbf", to: "St. Anton am Arlberg"),
            trip(date(2026, 4, 3), from: "Graz Hbf", to: "Klagenfurt Hbf", states: ["K", "ST"]),
            trip(date(2026, 5, 9), from: "Wien Hbf", to: "Salzburg Hbf", states: ["W", "NÖ", "OÖ", "S"]),
        ]
        let r = review(trips, car: true)
        XCTAssertEqual(kinds(r), [.intro, .savings, .distance, .rhythm, .onTheRoad, .climate, .finale])
        XCTAssertNil(r.favoriteRoute)
        XCTAssertEqual(r.rhythm?.travelDays, 3)
        XCTAssertEqual(r.rhythm?.longestStreakDays, 2)
        XCTAssertEqual(r.onTheRoad?.stateCount, 7)
    }

    func testARepeatedRouteBecomesTheFavourite() {
        let trips = [
            trip(date(2026, 4, 2)),
            trip(date(2026, 4, 3), from: "Graz Hbf", to: "Klagenfurt Hbf"),
            trip(date(2026, 4, 9), from: "St. Anton am Arlberg", to: "Innsbruck Hbf"),   // the same route backwards
        ]
        let r = review(trips)
        let favourite = try! XCTUnwrap(r.favoriteRoute)
        XCTAssertEqual(favourite.top.trips, 2)
        XCTAssertEqual(favourite.runnersUp.count, 1)
        XCTAssertEqual(favourite.runnersUp.first?.trips, 1)
    }

    func testARoundTripCountsOnce() {
        // Two logged round trips on one route: 2 trips (4 legs) – like Statistik › Top-Strecken.
        let trips = [trip(date(2026, 4, 2), round: true), trip(date(2026, 4, 3), round: true), trip(date(2026, 4, 4), from: "Wien Hbf", to: "Graz Hbf")]
        let r = review(trips)
        XCTAssertEqual(r.favoriteRoute?.top.trips, 2)
        XCTAssertEqual(r.favoriteRoute?.top.legs, 4)
        XCTAssertEqual(r.intro?.tripCount, 3)
    }

    func testNoDistancePageWithoutKilometres() {
        let r = review([trip(date(2026, 4, 2), km: 0)])
        XCTAssertFalse(kinds(r).contains(.distance))
    }

    func testPurposePageNeedsThreeCategorisedTrips() {
        var trips = [trip(date(2026, 4, 2), category: .commute), trip(date(2026, 4, 3), category: .leisure), trip(date(2026, 4, 4))]
        XCTAssertNil(review(trips).purpose)
        trips.append(trip(date(2026, 4, 5), category: .commute))
        let r = review(trips)
        let purpose = try! XCTUnwrap(r.purpose)
        XCTAssertEqual(purpose.categorisedTrips, 3)
        XCTAssertEqual(purpose.buckets.map(\.category), [.commute, .leisure])
        XCTAssertFalse(purpose.buckets.contains(where: \.isUncategorized))
    }

    func testPurposeIsRankedByTripsNotByValue() {
        let trips = [
            trip(date(2026, 4, 2), fare: 90, category: .holiday),
            trip(date(2026, 4, 3), fare: 5, category: .leisure), trip(date(2026, 4, 4), fare: 5, category: .leisure),
            trip(date(2026, 4, 5), fare: 5, category: .leisure),
            trip(date(2026, 4, 6), fare: 20, category: .commute), trip(date(2026, 4, 7), fare: 20, category: .commute),
        ]
        let purpose = try! XCTUnwrap(review(trips).purpose)
        XCTAssertEqual(purpose.buckets.map(\.category), [.leisure, .commute, .holiday])
        XCTAssertEqual(purpose.buckets.map(\.trips), [3, 2, 1])
    }

    func testPagesAreInReadingOrder() {
        let trips = (0..<8).map { trip(date(2026, 4, 2 + $0), category: .commute) }
        let r = review(trips, car: true)
        XCTAssertEqual(kinds(r), [.intro, .savings, .distance, .favoriteRoute, .rhythm, .onTheRoad, .purpose, .climate, .finale])
        XCTAssertEqual(Set(r.pages.map(\.id)).count, r.pages.count)
    }

    // MARK: Numbers = Statistik

    func fixtureTrips() -> [TripRecord] {
        let journey = UUID()
        return [
            trip(date(2026, 3, 2), fare: 23.5, km: 101, round: true, category: .commute),
            trip(date(2026, 3, 3), fare: 23.5, km: 101, round: true, category: .commute),
            trip(date(2026, 3, 4), fare: 23.5, km: 101, round: true, category: .commute),
            trip(date(2026, 4, 11), fare: 55.2, km: 189, from: "Innsbruck Hbf", to: "Salzburg Hbf", states: ["T", "S"], category: .leisure),
            trip(date(2026, 4, 12), fare: 92.8, km: 476, from: "Innsbruck Hbf", to: "Wien Hbf", states: ["T", "S", "OÖ", "NÖ", "W"], category: .holiday),
            trip(date(2026, 5, 20), fare: 18.8, km: 88, from: "Langen am Arlberg", to: "Bregenz", states: ["V"], induced: true),
            // A journey of two legs counts as one trip.
            trip(date(2026, 6, 6), fare: 5.8, km: 19, from: "St. Anton am Arlberg", to: "Lech", states: ["T", "V"], mode: .bus, journey: journey, leg: 0),
            trip(date(2026, 6, 6), fare: 8.6, km: 41, from: "Lech", to: "Bludenz", states: ["V"], mode: .train, journey: journey, leg: 1),
            trip(date(2026, 8, 15), fare: 32, km: 128, from: "Graz Hbf", to: "Klagenfurt Hbf", states: ["K", "ST"]),
            trip(date(2025, 12, 24), fare: 99, km: 300, from: "Wien Hbf", to: "Linz Hbf"),   // before the ticket
        ]
    }

    func testFiguresEqualStatistik() {
        let t = ticket()
        let trips = fixtureTrips()
        let now = date(2026, 9, 1)
        let carResult = CarComparison.compare(ticket: t, trips: trips, profile: CarProfile(), now: now)
        let r = YearReview.make(trips: trips, tickets: [t], car: carResult, period: YearReviewPeriods.ticketPeriod(t), now: now)

        let inPeriod = trips.filter { t.contains($0.date) }
        let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: now)
        let honest = CategoryStats.honestBalance(ticket: t, trips: trips)
        let records = StatsAggregator.records(inPeriod, now: now)

        XCTAssertEqual(r.intro?.tripCount, summary.tripCount)
        XCTAssertEqual(r.intro?.tripCount, 8, "9 entries in the period, a two-leg journey counts once")
        XCTAssertEqual(r.intro?.travelDays, summary.travelDays)
        XCTAssertEqual(r.intro?.ticketName, "KlimaTicket Ö Klassik")

        let savings = try! XCTUnwrap(r.savings)
        XCTAssertEqual(savings.totalValue, summary.totalValue, accuracy: 1e-9)
        XCTAssertEqual(savings.ticketCost, summary.ticketPrice)
        // The headline is the one of Statistik's hero and the Jahresbericht (all trips) …
        XCTAssertEqual(savings.net, summary.net, accuracy: 1e-9)
        XCTAssertEqual(savings.remaining, summary.remainingToBreakEven, accuracy: 1e-9)
        XCTAssertEqual(savings.isPaidOff, summary.isPaidOff)
        XCTAssertEqual(savings.breakEvenDate, summary.paidOffDate)
        // … and the honest balance stays a separate line with Statistik's "Ehrliche Bilanz" numbers.
        XCTAssertEqual(savings.realValue, honest.realSavings, accuracy: 1e-9)
        XCTAssertEqual(savings.extraValue, honest.extraValue, accuracy: 1e-9)
        XCTAssertEqual(savings.inducedTripCount, honest.inducedTripCount)
        XCTAssertEqual(savings.honestNet, honest.honestNet, accuracy: 1e-9)
        XCTAssertEqual(savings.honestRemaining, honest.remainingHonest, accuracy: 1e-9)
        XCTAssertTrue(savings.hasInducedTrips)

        let distance = try! XCTUnwrap(r.distance)
        XCTAssertEqual(distance.km, summary.distanceKm, accuracy: 1e-9)
        XCTAssertEqual(distance.legCount, summary.legCount)

        XCTAssertEqual(r.favoriteRoute?.top, StatsAggregator.topRoutes(inPeriod, limit: 3).first)
        XCTAssertEqual(r.favoriteRoute?.runnersUp, Array(StatsAggregator.topRoutes(inPeriod, limit: 3).dropFirst()))

        let rhythm = try! XCTUnwrap(r.rhythm)
        XCTAssertEqual(rhythm.months, StatsAggregator.months(inPeriod, in: t))
        XCTAssertEqual(rhythm.bestMonth, records.bestMonth)
        XCTAssertEqual(rhythm.longestStreakDays, records.longestStreakDays)
        XCTAssertEqual(rhythm.weekdays, StatsAggregator.weekdays(inPeriod))

        let road = try! XCTUnwrap(r.onTheRoad)
        XCTAssertEqual(Set(road.states.map(\.rawValue)), records.statesVisited)
        XCTAssertEqual(road.longestTrip, records.longestTrip)
        XCTAssertEqual(road.mostValuableTrip, records.mostValuableTrip)
        XCTAssertEqual(road.uniqueStations, records.uniqueStations)

        let climate = try! XCTUnwrap(r.climate)
        XCTAssertEqual(climate.co2SavedKg, carResult.co2SavedKg, accuracy: 1e-9)
        XCTAssertEqual(climate.co2CarKg, carResult.co2CarKg, accuracy: 1e-9)
        XCTAssertEqual(climate.co2TransitKg, carResult.co2TransitKg, accuracy: 1e-9)

        let finale = try! XCTUnwrap(r.finale)
        XCTAssertEqual(finale.tripCount, summary.tripCount)
        XCTAssertEqual(finale.distanceKm, summary.distanceKm, accuracy: 1e-9)
        XCTAssertEqual(finale.totalValue, summary.totalValue, accuracy: 1e-9)
    }

    func testTheRecordsNameTheLongestAndTheMostValuableJourney() {
        let r = review(fixtureTrips())
        XCTAssertEqual(r.onTheRoad?.mostValuableTrip?.toName, "Wien Hbf")
        XCTAssertEqual(r.onTheRoad?.longestTrip?.toName, "Wien Hbf")
    }

    // MARK: Induced trips

    func testInducedTripsStayASeparateLine() {
        let t = ticket(price: 100)
        let trips = [
            trip(date(2026, 3, 5), fare: 60),
            trip(date(2026, 3, 6), fare: 50, induced: true),
            trip(date(2026, 3, 7), fare: 50),
        ]
        let r = review(trips, ticket: t)
        let savings = try! XCTUnwrap(r.savings)
        let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: date(2026, 9, 1))
        // Headline: all trips, like the Übersicht hero and the Jahresbericht.
        XCTAssertEqual(savings.totalValue, 160, accuracy: 1e-9)
        XCTAssertEqual(savings.net, 60, accuracy: 1e-9)
        XCTAssertEqual(savings.net, summary.net, accuracy: 1e-9)
        XCTAssertTrue(savings.isPaidOff)
        XCTAssertEqual(savings.breakEvenDate, date(2026, 3, 6), "the day the value of all trips reached the price")
        XCTAssertEqual(savings.breakEvenDate, summary.paidOffDate)
        // Separate line: the induced trips are extra value, not saved money (Statistik's "Ehrliche Bilanz").
        XCTAssertEqual(savings.realValue, 110, accuracy: 1e-9)
        XCTAssertEqual(savings.extraValue, 50, accuracy: 1e-9)
        XCTAssertEqual(savings.inducedTripCount, 1)
        XCTAssertTrue(savings.hasInducedTrips)
        XCTAssertEqual(savings.honestNet, 10, accuracy: 1e-9)
        XCTAssertTrue(savings.isHonestlyPaidOff)
        let honest = CategoryStats.honestBalance(ticket: t, trips: trips)
        XCTAssertEqual(savings.honestNet, honest.honestNet, accuracy: 1e-9)
        XCTAssertEqual(savings.realValue + savings.extraValue, savings.totalValue, accuracy: 1e-9)
    }

    func testInducedTripsCanMeanThatTheHonestBalanceIsNotPaidOffYet() {
        let r = review([trip(date(2026, 3, 5), fare: 80, induced: true), trip(date(2026, 3, 6), fare: 30)], ticket: ticket(price: 100))
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertTrue(savings.isPaidOff, "110 of 100 with all trips")
        XCTAssertFalse(savings.isHonestlyPaidOff, "30 of 100 without the induced trip")
        XCTAssertEqual(savings.honestRemaining, 70, accuracy: 1e-9)
        XCTAssertEqual(savings.remaining, 0)
    }

    func testAllInducedMeansNothingSavedYet() {
        let r = review([trip(date(2026, 3, 5), fare: 80, induced: true)], ticket: ticket(price: 100))
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertEqual(savings.realValue, 0)
        XCTAssertEqual(savings.extraValue, 80, accuracy: 1e-9)
        XCTAssertEqual(savings.remaining, 20, accuracy: 1e-9)
        XCTAssertEqual(savings.honestRemaining, 100, accuracy: 1e-9)
        XCTAssertNil(savings.breakEvenDate)
    }

    // MARK: Break-even

    func testBreakEvenOnlyCountsWhenItHappenedInThePeriod() {
        let first = ticket(price: 100, start: date(2025, 3, 1, 0))
        let second = ticket(price: 100, start: date(2026, 3, 1, 0))
        let trips = [trip(date(2025, 4, 1), fare: 120), trip(date(2026, 4, 1), fare: 60), trip(date(2026, 11, 20), fare: 60)]
        let now = date(2026, 12, 20)
        // The calendar year 2026: the 2025/26 ticket paid off in April 2025 (before), the 2026/27 ticket on 20 Nov 2026.
        let year = YearReview.make(trips: trips, tickets: [first, second], car: nil, period: YearReviewPeriods.calendarYear(2026), now: now)
        XCTAssertEqual(year.savings?.breakEvenDate, date(2026, 11, 20))
        // The earlier ticket year: April 2025.
        let ticketYear = YearReview.make(trips: trips, tickets: [first, second], car: nil, period: YearReviewPeriods.ticketPeriod(first), now: now)
        XCTAssertEqual(ticketYear.savings?.breakEvenDate, date(2025, 4, 1))
        XCTAssertTrue(ticketYear.savings?.isPaidOff ?? false)
    }

    func testAFreeTicketNeverPaysOff() {
        let r = review([trip(date(2026, 4, 1), fare: 50)], ticket: ticket(price: 0))
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertFalse(savings.hasTicketCost)
        XCTAssertFalse(savings.isPaidOff)
        XCTAssertNil(savings.breakEvenDate)
        XCTAssertEqual(savings.totalValue, 50, accuracy: 1e-9)
    }

    // MARK: Calendar year

    func testCalendarYearFiguresUseTheProRataCost() {
        let t = ticket(price: 1_460, start: date(2026, 1, 1, 0))   // € 4 per day
        let trips = [trip(date(2026, 2, 1), fare: 100), trip(date(2026, 3, 1), fare: 100), trip(date(2025, 12, 31), fare: 500)]
        let r = YearReview.make(trips: trips, tickets: [t], car: nil, period: YearReviewPeriods.calendarYear(2026), now: date(2027, 1, 3))
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertEqual(savings.ticketCost, 1_460, accuracy: 1e-6)
        XCTAssertEqual(savings.totalValue, 200, accuracy: 1e-9)
        XCTAssertTrue(savings.costIsPartial)
        XCTAssertEqual(r.intro?.tripCount, 2, "the trip of 2025 is not part of 2026")
        XCTAssertEqual(r.accounting.price, 1_460, accuracy: 1e-6)
        XCTAssertEqual(r.period.kind, .calendarYear)
    }

    func testCalendarYearWithoutATicketClaimsNoSaving() {
        let r = YearReview.make(trips: [trip(date(2026, 2, 1), fare: 100)], tickets: [], car: nil,
                                period: YearReviewPeriods.calendarYear(2026), now: date(2027, 1, 3))
        let savings = try! XCTUnwrap(r.savings)
        XCTAssertFalse(savings.hasTicketCost)
        XCTAssertEqual(savings.totalValue, 100, accuracy: 1e-9)
        XCTAssertFalse(r.finale?.hasTicketCost ?? true)
        XCTAssertNil(r.intro?.ticketName)
    }

    // MARK: Top route tie-break

    func testTopRouteTieBreakMoreTripsThenValueThenName() {
        // Route A: 2 trips, € 40 each. Route B: 2 trips, € 40 each → same trips and value: the name decides.
        let a = (0..<2).map { trip(date(2026, 4, 1 + $0), fare: 40, from: "Zell am See", to: "Salzburg Hbf") }
        let b = (0..<2).map { trip(date(2026, 4, 5 + $0), fare: 40, from: "Graz Hbf", to: "Klagenfurt Hbf") }
        let tie = review(a + b)
        XCTAssertEqual(tie.favoriteRoute?.top.fromName, "Graz Hbf", "equal trips and value: alphabetical route key")
        // Reversing the input order must not change the winner.
        XCTAssertEqual(review(b + a).favoriteRoute?.top.fromName, "Graz Hbf")

        // More value wins at equal trips.
        let pricier = (0..<2).map { trip(date(2026, 4, 9 + $0), fare: 41, from: "Zell am See", to: "Salzburg Hbf") }
        XCTAssertEqual(review(pricier + b).favoriteRoute?.top.fromName, "Zell am See")

        // More trips wins even against more value.
        let moreTrips = (0..<3).map { trip(date(2026, 4, 12 + $0), fare: 10, from: "Wels Hbf", to: "Linz Hbf") }
        XCTAssertEqual(review(pricier + moreTrips).favoriteRoute?.top.fromName, "Wels Hbf")
    }

    // MARK: Rhythm

    func testBusiestWeekdayTieBreak() {
        // 2026-04-06 is a Monday, 2026-04-07 a Tuesday: one trip each plus a third on another Monday.
        let trips = [trip(date(2026, 4, 6)), trip(date(2026, 4, 7)), trip(date(2026, 4, 13))]
        XCTAssertEqual(review(trips).rhythm?.busiestWeekday?.weekday, 1, "Monday has two trips")
        // One trip each on Tuesday, Wednesday, Thursday: equal trips and value → the earlier weekday.
        let even = [trip(date(2026, 4, 7)), trip(date(2026, 4, 8)), trip(date(2026, 4, 9))]
        XCTAssertEqual(review(even).rhythm?.busiestWeekday?.weekday, 2)
    }

    func testBestMonthIsTheMonthWithTheMostValue() {
        let trips = [trip(date(2026, 4, 6), fare: 10), trip(date(2026, 5, 7), fare: 90), trip(date(2026, 5, 8), fare: 10), trip(date(2026, 6, 9), fare: 50)]
        let best = review(trips).rhythm?.bestMonth
        XCTAssertEqual(cal.component(.month, from: best!.month), 5)
        XCTAssertEqual(best?.value ?? 0, 100, accuracy: 1e-9)
    }

    // MARK: Reference distance

    func testPagesStayWithoutStationsAndHaveNoReference() {
        let r = review([trip(date(2026, 4, 2))])
        XCTAssertNotNil(r.distance)
        XCTAssertNil(r.distance?.reference)
    }

    func testNoNaNAnywhere() {
        let r = review([trip(date(2026, 4, 2), fare: 0, km: 0)], ticket: ticket(price: 0))
        for page in r.pages {
            switch page {
            case .savings(let s):
                XCTAssertTrue(s.net.isFinite && s.remaining.isFinite && s.totalValue.isFinite)
            case .finale(let f):
                XCTAssertTrue(f.net.isFinite && f.distanceKm.isFinite)
            default:
                break
            }
        }
    }
}
