import XCTest
@testable import KlimaCore

final class CategoryStatsTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func ticket(price: Double = 1400) -> TicketPeriod {
        let start = date(2026, 3, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, fare: Double, round: Bool = false, category: TripCategory? = nil, induced: Bool = false,
              from: String = "St. Anton am Arlberg", to: String = "Innsbruck Hbf") -> TripRecord {
        TripRecord(date: d, fromName: from, toName: to, mode: .train, distanceKm: 100, fareEUR: fare, isRoundTrip: round,
                   category: category, isInduced: induced)
    }

    // MARK: Buckets

    func testBucketsSumUpAndSortByValueWithUncategorisedLast() {
        let trips = [
            trip(date(2026, 3, 2), fare: 23.5, round: true, category: .commute),      // 47
            trip(date(2026, 3, 3), fare: 23.5, round: true, category: .commute),      // 47
            trip(date(2026, 3, 7), fare: 18.8, category: .leisure, induced: true),    // 18.8
            trip(date(2026, 3, 8), fare: 99, category: nil),                           // 99 – biggest, but uncategorised
            trip(date(2026, 3, 9), fare: 18.8, category: .business),                   // 18.8 – ties leisure by value
        ]
        let buckets = CategoryStats.buckets(trips)
        XCTAssertEqual(buckets.map(\.category), [.commute, .business, .leisure, nil])
        XCTAssertTrue(buckets.last!.isUncategorized)
        XCTAssertEqual(buckets.last!.id, CategoryBucket.uncategorizedID)

        let commute = buckets[0]
        XCTAssertEqual(commute.trips, 2)
        XCTAssertEqual(commute.legs, 4)
        XCTAssertEqual(commute.value, 94, accuracy: 0.001)
        XCTAssertEqual(commute.distanceKm, 400, accuracy: 0.001)

        let leisure = buckets[2]
        XCTAssertEqual(leisure.inducedTrips, 1)
        XCTAssertEqual(leisure.inducedValue, 18.8, accuracy: 0.001)

        let total = trips.reduce(0) { $0 + $1.totalValue }
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.value }, total, accuracy: 0.001)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.valueShare }, 1, accuracy: 0.0001)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.tripShare }, 1, accuracy: 0.0001)
        XCTAssertEqual(commute.tripShare, 0.4, accuracy: 0.0001)
    }

    func testBucketsEmptyAndZeroValue() {
        XCTAssertTrue(CategoryStats.buckets([]).isEmpty)
        let free = CategoryStats.buckets([trip(date(2026, 3, 2), fare: 0, category: .errand)])
        XCTAssertEqual(free.count, 1)
        XCTAssertEqual(free[0].valueShare, 0)
        XCTAssertEqual(free[0].tripShare, 1)
    }

    // MARK: Honest balance

    func testHonestBalanceSplitsRealSavingsAndExtraValue() {
        let t = ticket(price: 1000)
        let trips = [
            trip(date(2026, 3, 2), fare: 300, round: true, category: .commute),           // 600 real
            trip(date(2026, 4, 4), fare: 100, category: .leisure, induced: true),         // 100 extra
            trip(date(2026, 4, 5), fare: 350, category: .holiday),                         // 350 real
            trip(date(2025, 12, 1), fare: 999, induced: true),                             // outside the period
        ]
        let balance = CategoryStats.honestBalance(ticket: t, trips: trips)
        XCTAssertEqual(balance.tripCount, 3)
        XCTAssertEqual(balance.inducedTripCount, 1)
        XCTAssertEqual(balance.realTripCount, 2)
        XCTAssertEqual(balance.totalValue, 1050, accuracy: 0.001)
        XCTAssertEqual(balance.realSavings, 950, accuracy: 0.001)
        XCTAssertEqual(balance.extraValue, 100, accuracy: 0.001)
        XCTAssertEqual(balance.amortizedFraction, 1.05, accuracy: 0.0001)
        XCTAssertEqual(balance.honestFraction, 0.95, accuracy: 0.0001)
        XCTAssertEqual(balance.extraFraction, 0.10, accuracy: 0.0001)
        XCTAssertTrue(balance.isPaidOff)
        XCTAssertFalse(balance.isHonestlyPaidOff)
        XCTAssertEqual(balance.remainingHonest, 50, accuracy: 0.001)
        XCTAssertEqual(balance.honestNet, -50, accuracy: 0.001)
        XCTAssertEqual(balance.inducedTripShare, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(balance.inducedValueShare, 100.0 / 1050.0, accuracy: 0.0001)
        XCTAssertTrue(balance.hasInducedTrips)
    }

    func testHonestBalanceMatchesNormalPayoffWithoutInducedTrips() {
        let t = ticket()
        let trips = (0..<30).map { trip(cal.date(byAdding: .day, value: $0, to: t.start)!.addingTimeInterval(8 * 3600), fare: 23.5, round: true) }
        let balance = CategoryStats.honestBalance(ticket: t, trips: trips)
        let summary = SavingsCalculator.summary(ticket: t, trips: trips, now: date(2026, 4, 15))
        XCTAssertFalse(balance.hasInducedTrips)
        XCTAssertEqual(balance.honestFraction, balance.amortizedFraction, accuracy: 0.0001)
        XCTAssertEqual(balance.amortizedFraction, summary.amortizedFraction, accuracy: 0.0001)
        XCTAssertEqual(balance.totalValue, summary.totalValue, accuracy: 0.001)
        XCTAssertEqual(balance.inducedTripShare, 0)
    }

    func testHonestBalanceWithoutTripsOrPrice() {
        let empty = CategoryStats.honestBalance(ticket: ticket(), trips: [])
        XCTAssertEqual(empty.honestFraction, 0)
        XCTAssertEqual(empty.inducedValueShare, 0)
        XCTAssertFalse(empty.isPaidOff)
        let free = CategoryStats.honestBalance(ticket: ticket(price: 0), trips: [trip(date(2026, 3, 2), fare: 10)])
        XCTAssertFalse(free.isHonestlyPaidOff, "a free ticket (e.g. fully paid by the employer) never shows a summit")
        XCTAssertTrue(free.honestFraction.isFinite)
    }

    func testResearchShareIsEightPercent() {
        XCTAssertEqual(HonestBalance.researchInducedShare, 0.08)
    }

    // MARK: Work share

    func testWorkRelatedShare() {
        XCTAssertNil(CategoryStats.workRelatedValueShare([trip(date(2026, 3, 2), fare: 10)]))
        let trips = [
            trip(date(2026, 3, 2), fare: 30, category: .commute),
            trip(date(2026, 3, 3), fare: 10, category: .business),
            trip(date(2026, 3, 4), fare: 40, category: .leisure),
            trip(date(2026, 3, 5), fare: 20),
        ]
        XCTAssertEqual(CategoryStats.workRelatedValueShare(trips)!, 0.4, accuracy: 0.0001)
    }

    // MARK: Route suggestion

    func testSuggestionUsesMostRecentCategorisedTripOnTheSameRouteInEitherDirection() {
        let older = trip(date(2026, 3, 2), fare: 23.5, category: .business)
        let newer = trip(date(2026, 3, 9), fare: 23.5, category: .commute, from: "Innsbruck Hbf", to: "St. Anton am Arlberg")
        let newestUncategorised = trip(date(2026, 3, 10), fare: 23.5)
        let otherRoute = trip(date(2026, 3, 11), fare: 8.6, category: .visit, to: "Bludenz")
        let trips = [older, otherRoute, newer, newestUncategorised]

        XCTAssertEqual(CategoryStats.suggestedCategory(fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf", in: trips), .commute)
        XCTAssertEqual(CategoryStats.suggestedCategory(fromName: "innsbruck hbf ", toName: "St. Anton am Arlberg", in: trips), .commute)
        XCTAssertEqual(CategoryStats.suggestedCategory(fromName: "St. Anton am Arlberg", toName: "Bludenz", in: trips), .visit)
        // Editing the newest categorised trip falls back to the previous one.
        XCTAssertEqual(CategoryStats.suggestedCategory(fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf", in: trips,
                                                       excludingID: newer.id), .business)
        XCTAssertNil(CategoryStats.suggestedCategory(fromName: "Wien Hbf", toName: "Linz Hbf", in: trips))
        XCTAssertNil(CategoryStats.suggestedCategory(fromName: "", toName: "Innsbruck Hbf", in: trips))
    }
}
