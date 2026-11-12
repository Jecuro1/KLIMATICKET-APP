import XCTest
@testable import KlimaCore

/// „Was wäre wenn?“ – real-data mode: the logged trips, with the slider, the toggles and the same totals as
/// `TicketComparator` (the Ticket-Vergleich in Statistik) when nothing is changed.
final class WhatIfHistoryTests: XCTestCase {
    typealias F = WhatIfFixtures

    /// A sample year like the demo data: 80 trips on the demo routes (some round trips, one without states), one every
    /// third day from 2 March 2026 – including July and August.
    static func demoYear() -> [TripRecord] {
        let routes: [(String, String, Double, Double, Set<String>)] = [
            ("St. Anton am Arlberg", "Innsbruck Hauptbahnhof", 101, 23.5, ["T"]),
            ("St. Anton am Arlberg", "Landeck-Zams", 28, 6.7, ["T"]),
            ("St. Anton am Arlberg", "Bludenz", 41, 8.6, ["T", "V"]),
            ("Langen am Arlberg", "Bregenz", 88, 18.8, ["V"]),
            ("Innsbruck Hauptbahnhof", "Wien Hauptbahnhof", 476, 92.8, ["NÖ", "OÖ", "S", "T", "W"]),
            ("Innsbruck Hauptbahnhof", "Salzburg Hauptbahnhof", 189, 55.2, ["S", "T"]),
            ("Wien Hauptbahnhof", "Wien Praterstern", 4.5, 3.2, ["W"]),
            ("St. Anton am Arlberg", "Lech", 19, 5.8, ["T", "V"]),
            ("Graz Hauptbahnhof", "Klagenfurt Hauptbahnhof", 128, 32.0, ["K", "ST"]),
        ]
        var seed: UInt64 = 42
        var trips: [TripRecord] = []
        for i in 0..<79 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let route = routes[Int(seed >> 33) % routes.count]
            let date = F.cal.date(byAdding: .day, value: 3 * i, to: F.date(2026, 3, 2, 8))!
            trips.append(TripRecord(date: date, fromName: route.0, toName: route.1, mode: .train, distanceKm: route.2,
                                    fareEUR: route.3, isRoundTrip: (seed >> 20) & 1 == 0, states: route.4))
        }
        // A trip whose states are unknown: only KlimaTicket Ö counts it as covered (like TicketComparator).
        trips.append(TripRecord(date: F.date(2026, 10, 1, 8), fromName: "Irgendwo", toName: "Nirgendwo", mode: .bus, distanceKm: 10,
                                fareEUR: 4.2, states: []))
        return trips
    }

    static let periodStart = F.date(2026, 3, 1)

    func input(_ edit: (inout WhatIfInput) -> Void = { _ in }) -> WhatIfInput {
        var input = WhatIfInput(variant: .klassik, startDate: Self.periodStart, currentProductID: "oe-klassik")
        edit(&input)
        return input
    }

    func assertEqualToComparator(_ result: WhatIfResult, trips: [TripRecord], factor: Double, file: StaticString = #filePath,
                                 line: UInt = #line) {
        let reference = TicketComparator.compare(trips: trips, products: F.catalog().products, variant: .klassik,
                                                 currentProductID: "oe-klassik", periodStart: Self.periodStart,
                                                 annualizationFactor: factor)
        XCTAssertEqual(Set(reference.map(\.id)), Set(result.options.map(\.id)), file: file, line: line)
        for option in reference {
            let mine = F.option(result, option.id, file: file, line: line)
            XCTAssertEqual(mine.ticketPrice, option.ticketPrice, accuracy: 1e-9, option.id, file: file, line: line)
            XCTAssertEqual(mine.uncoveredYearly, option.uncoveredCost, accuracy: 1e-6, option.id, file: file, line: line)
            XCTAssertEqual(mine.yearlyCost, option.totalCost, accuracy: 1e-6, option.id, file: file, line: line)
        }
        XCTAssertEqual(result.options.map(\.id), reference.map(\.id), "same ranking (no ties in this data)", file: file, line: line)
    }

    // MARK: The same numbers as Statistik

    func testFactorOneEqualsTicketComparatorForTheDemoYear() {
        let trips = Self.demoYear()
        XCTAssertEqual(trips.count, 80)
        let result = F.calculator().evaluate(input(), history: WhatIfHistory(trips: trips))
        XCTAssertEqual(result.state, .ready)
        assertEqualToComparator(result, trips: trips, factor: 1)
        XCTAssertGreaterThan(result.single.yearlyCost, 0)
        XCTAssertTrue(F.option(result, "oe-klassik").isCurrent)
    }

    func testAnnualizationFactorIsTheComparatorsFactor() {
        let trips = Self.demoYear()
        for factor in [1.0, 1.7, 4.0, 12.2] {
            let result = F.calculator().evaluate(input(), history: WhatIfHistory(trips: trips, annualizationFactor: factor))
            assertEqualToComparator(result, trips: trips, factor: factor)
        }
    }

    // MARK: Slider

    /// The comparator clamps a factor below 1 to 1: the slider's ×0,5 prices the trips themselves.
    func testVolumeSliderScalesTheFares() {
        let trips = Self.demoYear()
        let calc = F.calculator()
        let base = calc.evaluate(input(), history: WhatIfHistory(trips: trips))
        for volume in [0.5, 0.75, 1.5, 2.0] {
            let scaled = calc.evaluate(input { $0.volumeFactor = volume }, history: WhatIfHistory(trips: trips))
            for option in base.options {
                let mine = F.option(scaled, option.id)
                XCTAssertEqual(mine.uncoveredYearly, option.uncoveredYearly * volume, accuracy: 1e-6, "\(option.id) ×\(volume)")
                XCTAssertEqual(mine.ticketPrice, option.ticketPrice, accuracy: 1e-9, "the ticket price does not scale")
            }
            XCTAssertEqual(scaled.tripsPerMonth, base.tripsPerMonth * volume, accuracy: 1e-9)
            // ×2 and ×0,5 against the comparator for the same trips (×2 through its own annualisation factor).
            if volume == 2 { assertEqualToComparator(scaled, trips: trips, factor: 2) }
        }
        // More trips never make singles cheaper; the break-even in trips per month does not move with the slider.
        let half = calc.evaluate(input { $0.volumeFactor = 0.5 }, history: WhatIfHistory(trips: trips))
        let double = calc.evaluate(input { $0.volumeFactor = 2 }, history: WhatIfHistory(trips: trips))
        XCTAssertLessThan(half.single.yearlyCost, base.single.yearlyCost)
        XCTAssertLessThan(base.single.yearlyCost, double.single.yearlyCost)
        XCTAssertEqual(half.breakEvenTripsPerMonth, double.breakEvenTripsPerMonth)
        XCTAssertEqual(base.breakEvenTripsPerMonth, double.breakEvenTripsPerMonth)
    }

    // MARK: Toggles

    func testJulyAndAugustWithoutTrips() {
        let trips = Self.demoYear()
        let calc = F.calculator()
        let result = calc.evaluate(input { $0.excludedMonths = [7, 8] }, history: WhatIfHistory(trips: trips))
        let kept = trips.filter { ![7, 8].contains(F.cal.component(.month, from: $0.date)) }
        XCTAssertLessThan(kept.count, trips.count)
        assertEqualToComparator(result, trips: kept, factor: 1)
        // Spread over the ten months that have trips: July and August stay flat in the chart.
        let single = result.single.cumulative
        XCTAssertEqual(single[4], single[6], accuracy: 1e-9, "the year starts in March: July is month 5 (index 4→5), August month 6 (5→6)")
        XCTAssertEqual(single[12], result.single.yearlyCost, accuracy: 1e-6)
    }

    func testOnlyOneFederalState() {
        let trips = Self.demoYear()
        let calc = F.calculator()
        let result = calc.evaluate(input { $0.regionFilter = "T" }, history: WhatIfHistory(trips: trips))
        let kept = trips.filter { !$0.states.isEmpty && $0.states.isSubset(of: ["T"]) }
        XCTAssertGreaterThan(kept.count, 0)
        XCTAssertLessThan(kept.count, trips.count)
        assertEqualToComparator(result, trips: kept, factor: 1)
        // Inside Tirol alone the regional ticket covers every remaining trip.
        XCTAssertEqual(F.option(result, "tirol-klassik").coveredShare, 1, accuracy: 1e-9)
    }

    func testFirstClassPricesEveryTripUpAndNeedsTheUpgrade() {
        let trips = Self.demoYear()
        let calc = F.calculator()
        let second = calc.evaluate(input(), history: WhatIfHistory(trips: trips))
        let first = calc.evaluate(input { $0.useFirstClass = true }, history: WhatIfHistory(trips: trips))
        XCTAssertEqual(first.single.yearlyCost, second.single.yearlyCost * 1.951, accuracy: 1e-6)
        XCTAssertEqual(F.option(first, "oe-klassik").ticketPrice, 1400 + 1490, accuracy: 1e-9)
        XCTAssertEqual(F.option(first, "oe-klassik").uncoveredYearly, 0, accuracy: 1e-9)
        XCTAssertEqual(F.option(first, "tirol-klassik").coveredShare, 0, "regional tickets are 2. Klasse only")
        XCTAssertTrue(first.includesFirstClass)
        // A trip that was already 1. Klasse is not priced up a second time.
        let ids = Set(trips.prefix(10).map(\.id))
        let mixed = calc.evaluate(input { $0.useFirstClass = true }, history: WhatIfHistory(trips: trips, firstClassTripIDs: ids))
        XCTAssertLessThan(mixed.single.yearlyCost, first.single.yearlyCost)
        XCTAssertGreaterThan(mixed.single.yearlyCost, second.single.yearlyCost)
    }

    func testNoTripsLeft() {
        let trips = Self.demoYear()
        let calc = F.calculator()
        XCTAssertEqual(calc.evaluate(input(), history: WhatIfHistory(trips: [])).state, .noTrips)
        XCTAssertEqual(calc.evaluate(input { $0.excludedMonths = Set(1...12) }, history: WhatIfHistory(trips: trips)).state, .noTrips)
        XCTAssertEqual(calc.evaluate(input { $0.regionFilter = "B" }, history: WhatIfHistory(trips: trips)).state, .noTrips)
        XCTAssertFalse(WhatIfHistory(trips: Array(trips.prefix(4))).isRichEnough)
        XCTAssertTrue(WhatIfHistory(trips: Array(trips.prefix(5))).isRichEnough)
    }

    func testBrokenHistoryValuesAreIgnored() {
        let good = TripRecord(date: F.date(2026, 5, 4), fromName: "a", toName: "b", mode: .train, distanceKm: 1, fareEUR: 10, states: ["T"])
        let nan = TripRecord(date: F.date(2026, 5, 5), fromName: "a", toName: "b", mode: .train, distanceKm: 1, fareEUR: .nan, states: ["T"])
        let negative = TripRecord(date: F.date(2026, 5, 6), fromName: "a", toName: "b", mode: .train, distanceKm: 1, fareEUR: -50, states: ["T"])
        let result = F.calculator().evaluate(input { $0.volumeFactor = .infinity },
                                             history: WhatIfHistory(trips: [good, nan, negative], annualizationFactor: .nan))
        // Only the good trip counts (NaN and negative fares are dropped); a volume of ∞ and an annualisation of NaN count as ×1.
        XCTAssertEqual(result.single.yearlyCost, 10, accuracy: 1e-9)
        XCTAssertTrue(result.options.allSatisfy { $0.yearlyCost.isFinite })
    }

    // MARK: Baseline

    /// The screen says „pro Jahr“: any window shorter than a year is projected to a year (the demo's 225 days are × 1,62), so
    /// 225 days of trips are not set against a full year's ticket price.
    func testBaselineProjectsEveryWindowUnderAYear() {
        let now = F.date(2026, 11, 12)
        func baseline(daysAgo: Int) -> WhatIfBaseline {
            WhatIfBaseline.make(now: now, firstActivity: F.cal.date(byAdding: .day, value: -daysAgo, to: now))
        }
        // The demo: ticket started 225 days ago.
        let demo = baseline(daysAgo: 224)
        XCTAssertEqual(demo.observedDays, 225)
        XCTAssertEqual(demo.annualizationFactor, 365.0 / 225.0, accuracy: 1e-9)
        XCTAssertTrue(demo.isAnnualized)
        // A ticket from 60 days ago: × 365 ÷ 60.
        let young = baseline(daysAgo: 59)
        XCTAssertEqual(young.observedDays, 60)
        XCTAssertEqual(young.annualizationFactor, 365.0 / 60.0, accuracy: 1e-9)
        // Three days of data are treated as a month, not as × 122.
        let tiny = baseline(daysAgo: 2)
        XCTAssertEqual(tiny.observedDays, 3)
        XCTAssertEqual(tiny.annualizationFactor, 365.0 / 30.0, accuracy: 1e-9)
        // More than a year of history: the last 12 months, no scaling. Unknown start: the same.
        let old = WhatIfBaseline.make(now: now, firstActivity: F.date(2020, 1, 1))
        XCTAssertEqual(old.observedDays, 365)
        XCTAssertEqual(old.annualizationFactor, 1)
        XCTAssertFalse(old.isAnnualized)
        XCTAssertEqual(WhatIfBaseline.make(now: now, firstActivity: nil).annualizationFactor, 1)
        XCTAssertEqual(F.cal.component(.year, from: old.windowStart), 2025)
        // Nearly a year (348 days and more) is a year: „× 1,02“ is noise. 347 days are scaled by × 1,05.
        XCTAssertEqual(baseline(daysAgo: 347).annualizationFactor, 1)
        XCTAssertEqual(baseline(daysAgo: 346).annualizationFactor, 365.0 / 347.0, accuracy: 1e-9)
        // Three months are scaled too (Statistik leaves 92 days alone; its card says „bisher“, this screen says „pro Jahr“).
        XCTAssertEqual(baseline(daysAgo: 91).annualizationFactor, 365.0 / 92.0, accuracy: 1e-9)
        // The factor never falls below 1 and never exceeds the cap.
        for days in stride(from: 0, through: 500, by: 7) {
            let factor = baseline(daysAgo: days).annualizationFactor
            XCTAssertGreaterThanOrEqual(factor, 1)
            XCTAssertLessThanOrEqual(factor, 365.0 / 30.0 + 1e-9)
        }
    }

    /// 79 trips in 225 days are about 8,2 a month on a straight average, not 79 ÷ 12 = 6,6: the volume line and the yearly
    /// figures follow the projection, and the break-even (a property of the ticket and the mix) does not change.
    func testProjectedWindowScalesVolumeAndYearlyCostButNotBreakEven() {
        let trips = Self.demoYear()
        let legs = trips.reduce(0) { $0 + $1.legs }
        let factor = 365.0 / 225.0
        let calc = F.calculator()
        let plain = calc.evaluate(input(), history: WhatIfHistory(trips: trips))
        let projected = calc.evaluate(input(), history: WhatIfHistory(trips: trips, annualizationFactor: factor))
        XCTAssertEqual(plain.tripsPerMonth, Double(legs) / 12, accuracy: 1e-9)
        XCTAssertEqual(projected.tripsPerMonth, Double(legs) * factor / 12, accuracy: 1e-9)
        XCTAssertEqual(projected.single.yearlyCost, plain.single.yearlyCost * factor, accuracy: 1e-6)
        for id in ["oe-klassik", "tirol-klassik"] {
            XCTAssertEqual(F.option(projected, id).breakEvenTripsPerMonth, F.option(plain, id).breakEvenTripsPerMonth, id)
            XCTAssertEqual(F.option(projected, id).ticketPrice, F.option(plain, id).ticketPrice, accuracy: 1e-9, id)
        }
    }

    /// The exact break-even sits at most one below the rounded-up number, and a ticket that is already cheaper at the
    /// user's own volume has an exact break-even at or below that volume.
    func testExactBreakEvenBelongsToTheRoundedOne() {
        let trips = Self.demoYear()
        let result = F.calculator().evaluate(input { $0.volumeFactor = 1.35 }, history: WhatIfHistory(trips: trips, annualizationFactor: 1.62))
        for option in result.options where !option.isSingle {
            guard let whole = option.breakEvenTripsPerMonth, let exact = option.breakEvenExact else { continue }
            XCTAssertLessThanOrEqual(exact, Double(whole) + 1e-9, option.id)
            XCTAssertGreaterThan(exact, Double(whole) - 1 - 1e-9, option.id)
            if option.yearlyCost < result.single.yearlyCost - 0.005 {
                XCTAssertLessThanOrEqual(exact, result.tripsPerMonth + 1e-6, "\(option.id): cheaper ⇒ the volume is past the break-even")
            }
        }
    }

    /// A hand-edited fare that is finite but absurd must not trap the cent conversion of the ranking.
    func testAbsurdFaresDoNotTrap() {
        let trips = [TripRecord(date: F.date(2026, 5, 4), fromName: "a", toName: "b", mode: .train, distanceKm: 1, fareEUR: 1e30, states: ["T"]),
                     TripRecord(date: F.date(2026, 5, 5), fromName: "a", toName: "b", mode: .train, distanceKm: 1, fareEUR: 12, states: ["T"])]
        let result = F.calculator().evaluate(input(), history: WhatIfHistory(trips: trips))
        XCTAssertTrue(result.options.allSatisfy { !$0.yearlyCost.isNaN })
        XCTAssertEqual(result.options.first?.isSingle, false, "a ticket is cheaper than 1e30 euros of single tickets")
    }
}
