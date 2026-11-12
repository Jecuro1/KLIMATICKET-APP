import XCTest
@testable import KlimaCore

/// „Was wäre wenn?“ – assumptions mode. Every expected number is computed by hand from the fixtures in
/// `WhatIfFixtures` (relation prices € 23,50 Tirol, € 67,70 Wien–Salzburg; Ö Klassik € 1.400, Tirol € 590 / € 600).
final class WhatIfCalculatorTests: XCTestCase {
    typealias F = WhatIfFixtures

    // MARK: Break-even (hand-computed)

    /// 10 trips a month St. Anton → Innsbruck: singles 10 × 12 × 23,50 = € 2.820; Tirol € 590 (start before 1.4.2026), Ö € 1.400.
    func testBreakEvenOneRoute() {
        let result = F.calculator().evaluate(F.input([F.tirol(10)]))
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.tripsPerMonth, 10, accuracy: 1e-9)
        XCTAssertEqual(result.single.yearlyCost, 2820, accuracy: 1e-6)
        XCTAssertEqual(F.option(result, "tirol-klassik").ticketPrice, 590)
        XCTAssertEqual(F.option(result, "oe-klassik").yearlyCost, 1400, accuracy: 1e-6)
        XCTAssertEqual(result.options.map(\.id), ["tirol-klassik", "oe-klassik", "single", "wien-klassik"],
                       "Wien covers no trip: 467 + 2.820 comes last; the local Innsbruck ticket and other variants are not compared")
        XCTAssertEqual(result.bestTicket?.id, "tirol-klassik")
        XCTAssertEqual(result.yearlyDelta, 2820 - 590, accuracy: 1e-6)
        XCTAssertTrue(result.ticketIsCheaper)
        // 590 ÷ (12 × 23,50 = 282 per trip a month) = 2,09 → from 3 trips a month; Ö 1.400 ÷ 282 = 4,96 → 5.
        XCTAssertEqual(result.breakEvenTripsPerMonth, 3)
        XCTAssertEqual(F.option(result, "oe-klassik").breakEvenTripsPerMonth, 5)
        XCTAssertNil(result.single.breakEvenTripsPerMonth)
        // Chart: singles climb 235 a month, the ticket is paid at once: they meet after 590 ÷ 235 = 2,51 months.
        XCTAssertEqual(result.crossing ?? -1, 590.0 / 235.0, accuracy: 1e-9)
        XCTAssertEqual(result.crossingMonth, 3)
    }

    /// 4 trips St. Anton → Innsbruck (€ 94 a month) and 2 trips Wien → Salzburg (€ 135,40): singles € 2.752,80 a year.
    func testBreakEvenTwoRoutes() {
        let result = F.calculator().evaluate(F.input([F.tirol(4), F.westbahn(2)]))
        XCTAssertEqual(result.tripsPerMonth, 6, accuracy: 1e-9)
        XCTAssertEqual(result.single.yearlyCost, 2752.8, accuracy: 1e-6)
        // Ö covers both: € 1.400. Tirol covers the first only: 590 + 12 × 135,40 = € 2.214,80.
        XCTAssertEqual(F.option(result, "oe-klassik").yearlyCost, 1400, accuracy: 1e-6)
        XCTAssertEqual(F.option(result, "tirol-klassik").yearlyCost, 2214.8, accuracy: 1e-6)
        XCTAssertEqual(F.option(result, "tirol-klassik").uncoveredYearly, 1624.8, accuracy: 1e-6)
        XCTAssertEqual(result.options.prefix(3).map(\.id), ["oe-klassik", "tirol-klassik", "single"])
        XCTAssertEqual(result.bestTicket?.id, "oe-klassik")
        XCTAssertEqual(result.yearlyDelta, 2752.8 - 1400, accuracy: 1e-6)
        // Ö: 1.400 ÷ 2.752,80 of today's volume = 0,509 × 6 = 3,05 → from 4 trips a month (same mix: 3 would cost 1.376,40).
        XCTAssertEqual(result.breakEvenTripsPerMonth, 4)
        // Tirol: 590 ÷ 1.128 (covered fares a year) × 6 = 3,14 → 4.
        XCTAssertEqual(F.option(result, "tirol-klassik").breakEvenTripsPerMonth, 4)
    }

    /// The same sentence and the same chart: the ticket line crosses the single-ticket line within the year exactly when
    /// the trips per month reach the break-even number (one route: the number does not depend on the volume).
    func testBreakEvenSentenceMatchesChartCrossing() {
        let calc = F.calculator()
        for n in 1...60 {
            let result = calc.evaluate(F.input([F.tirol(n)]))
            XCTAssertEqual(result.breakEvenTripsPerMonth, 3, "n = \(n)")
            XCTAssertEqual(result.crossing != nil, n >= 3, "n = \(n)")
            XCTAssertEqual(result.ticketIsCheaper, n >= 3, "n = \(n)")
            if let crossing = result.crossing, let month = result.crossingMonth {
                XCTAssertEqual(crossing, 590.0 / (23.5 * Double(n)), accuracy: 1e-9)
                XCTAssertEqual(month, Int(crossing.rounded(.up)), "within one month of the interpolated crossing")
            }
        }
    }

    // MARK: Coverage

    func testRegionalProductCoversOnlyItsStates() {
        let result = F.calculator().evaluate(F.input([F.tirol(4), F.westbahn(2)]))
        XCTAssertEqual(F.option(result, "tirol-klassik").coveredShare, 4.0 / 6.0, accuracy: 1e-9)
        XCTAssertEqual(F.option(result, "wien-klassik").coveredShare, 0, "Wien → Salzburg touches S: not all of its states are Wiens")
        XCTAssertEqual(F.option(result, "oe-klassik").coveredShare, 1, accuracy: 1e-9)
        // A product that covers nothing is not part of the display ranking.
        XCTAssertFalse(result.displayOptions().contains { $0.id == "wien-klassik" })
        XCTAssertTrue(result.displayOptions().contains { $0.isSingle })
    }

    func testTripsAbroadAreNotCoveredByKlimaTicketOe() {
        let munich = Station(id: "de:8000261", name: "München Hbf", lat: 48.14, lon: 11.56, state: "X")
        let calc = WhatIfCalculator(catalog: F.catalog(), relations: F.table(), stations: StationIndex(stations: F.stations + [munich]))
        let abroad = WhatIfRoute(fromStationID: F.salzburg.id, toStationID: munich.id, tripsPerMonth: 4)
        let result = calc.evaluate(F.input([abroad]))
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(F.option(result, "oe-klassik").coveredShare, 0)
        XCTAssertNil(result.bestTicket, "no ticket covers the only route")
        XCTAssertEqual(result.yearlyDelta, 0)
    }

    // MARK: Variant

    func testVariantSelection() {
        let calc = F.calculator()
        let jugend = calc.evaluate(F.input([F.tirol(10)], variant: .jugend))
        XCTAssertEqual(Set(jugend.options.map(\.id)), ["single", "oe-jugend", "tirol-jugend"])
        XCTAssertEqual(F.option(jugend, "oe-jugend").ticketPrice, 1050)
        XCTAssertEqual(jugend.bestTicket?.id, "tirol-jugend")
        XCTAssertEqual(F.option(jugend, "tirol-jugend").ticketPrice, 319, "no price history: today's price")

        let senior = calc.evaluate(F.input([F.tirol(10)], variant: .senior))
        XCTAssertEqual(Set(senior.options.map(\.id)), ["single", "oe-senior"])
        XCTAssertEqual(senior.bestTicket?.id, "oe-senior")
        XCTAssertEqual(senior.yearlyDelta, 2820 - 1000, accuracy: 1e-6)

        // The own ticket stays in the comparison whatever the variant.
        var input = F.input([F.tirol(10)], variant: .jugend)
        input.currentProductID = "oe-klassik"
        let withCurrent = calc.evaluate(input)
        XCTAssertTrue(F.option(withCurrent, "oe-klassik").isCurrent)
        XCTAssertFalse(F.option(withCurrent, "oe-jugend").isCurrent)
    }

    // MARK: Start date

    func testStartDateChangesThePrices() {
        let calc = F.calculator()
        func price(_ id: String, _ start: Date) -> Double {
            F.option(calc.evaluate(F.input([F.tirol(10)], start: start)), id).ticketPrice
        }
        XCTAssertEqual(price("oe-klassik", F.date(2025, 7, 1)), 1179.3, accuracy: 1e-9)
        XCTAssertEqual(price("oe-klassik", F.date(2025, 8, 15)), 1300, accuracy: 1e-9)
        XCTAssertEqual(price("oe-klassik", F.date(2026, 2, 1)), 1400, accuracy: 1e-9)
        XCTAssertEqual(price("tirol-klassik", F.date(2026, 3, 31)), 590, accuracy: 1e-9)
        XCTAssertEqual(price("tirol-klassik", F.date(2026, 4, 1)), 600, accuracy: 1e-9)
        // The ranking follows: 590 → 600 changes the delta by exactly 10.
        let early = calc.evaluate(F.input([F.tirol(10)], start: F.date(2026, 3, 31)))
        let late = calc.evaluate(F.input([F.tirol(10)], start: F.date(2026, 4, 1)))
        XCTAssertEqual(early.yearlyDelta - late.yearlyDelta, 10, accuracy: 1e-6)
    }

    /// A price change inside the year (fare index 13.12.2026, + 3,5 %) reaches the months from December on.
    func testFareIndexInsideTheYear() {
        let catalog = F.catalog(fareIndex: [.init(validFrom: "2026-12-13", factor: 1.035)])
        let calc = F.calculator(catalog)
        let result = calc.evaluate(F.input([F.tirol(10)], start: F.date(2026, 11, 1)))
        let monthly = result.routeFares[0].monthlyFare
        XCTAssertEqual(monthly[0], 23.5, accuracy: 1e-9, "November")
        XCTAssertEqual(monthly[1], 24.3, accuracy: 1e-9, "December: 23,50 × 1,035 = 24,32 → 24,30")
        XCTAssertEqual(monthly[11], 24.3, accuracy: 1e-9)
        XCTAssertEqual(result.single.yearlyCost, 10 * (23.5 + 11 * 24.3), accuracy: 1e-6)
        XCTAssertEqual(result.monthStarts.first, F.date(2026, 11, 1, 0))
        XCTAssertEqual(result.monthStarts.count, 13, "12 months = 13 boundaries")
        XCTAssertEqual(result.monthStarts.last, F.date(2027, 11, 1, 0))
    }

    // MARK: Ranking

    func testDeterministicTieBreak() {
        let twins = [F.product("zz-tirol", .regional, ["T"], price: 700), F.product("aa-tirol", .regional, ["T"], price: 700)]
        let forward = F.calculator(F.catalog(extra: twins)).evaluate(F.input([F.tirol(10)]))
        let reversed = F.calculator(F.catalog(extra: twins.reversed())).evaluate(F.input([F.tirol(10)]))
        let ids = forward.options.map(\.id)
        XCTAssertLessThan(ids.firstIndex(of: "aa-tirol")!, ids.firstIndex(of: "zz-tirol")!, "same cost: by id")
        XCTAssertEqual(ids, reversed.options.map(\.id), "the catalogue order does not matter")
        for _ in 0..<5 { XCTAssertEqual(F.calculator(F.catalog(extra: twins)).evaluate(F.input([F.tirol(10)])).options.map(\.id), ids) }
    }

    /// A ticket that costs exactly what the single tickets cost: single tickets come first, there is no „saving“.
    func testTieWithSingleTickets() {
        // 1 trip a month = 12 × 23,50 = € 282 a year.
        let exact = F.product("tie-tirol", .regional, ["T"], price: 282)
        let result = F.calculator(F.catalog(extra: [exact])).evaluate(F.input([F.tirol(1)]))
        XCTAssertEqual(result.options.first?.id, "single")
        XCTAssertEqual(result.bestTicket?.id, "tie-tirol")
        XCTAssertEqual(result.yearlyDelta, 0, accuracy: 1e-9)
        XCTAssertTrue(result.isTie)
        XCTAssertFalse(result.ticketIsCheaper)
    }

    func testYearlyCostGrowsWithTrips() {
        let calc = F.calculator()
        var previous: [String: Double] = [:]
        var previousBest = 0.0
        for n in 0...60 {
            let result = calc.evaluate(F.input([F.tirol(n), F.westbahn(n / 2)]))
            for option in result.options {
                if let before = previous[option.id] { XCTAssertGreaterThanOrEqual(option.yearlyCost, before - 1e-9, "\(option.id) at \(n)") }
                previous[option.id] = option.yearlyCost
            }
            XCTAssertEqual(result.single.yearlyCost, 12 * (Double(n) * 23.5 + Double(n / 2) * 67.7), accuracy: 1e-6)
            if let best = result.bestTicket {
                XCTAssertGreaterThanOrEqual(best.yearlyCost, previousBest - 1e-9)
                previousBest = best.yearlyCost
            }
        }
    }

    // MARK: Series

    func testSeriesAddUpToTheYearlyCost() {
        let result = F.calculator().evaluate(F.input([F.tirol(4), F.westbahn(2)]))
        for option in result.options {
            XCTAssertEqual(option.cumulative.count, 13)
            XCTAssertEqual(option.cumulative[0], option.ticketPrice, accuracy: 1e-9, "the ticket is paid at the start")
            XCTAssertEqual(option.cumulative[12], option.yearlyCost, accuracy: 1e-6)
            XCTAssertEqual(option.cumulative, option.cumulative.sorted(), "never goes down")
        }
    }

    func testExcludedMonthsAreFlat() {
        var input = F.input([F.tirol(10)], start: F.date(2026, 1, 1))
        input.excludedMonths = [7, 8, 0, 13, -3]   // 0, 13 and −3 are not months and are ignored
        let result = F.calculator().evaluate(input)
        XCTAssertEqual(result.single.yearlyCost, 10 * 10 * 23.5, accuracy: 1e-6)
        XCTAssertEqual(result.tripsPerMonth, 100.0 / 12.0, accuracy: 1e-9)
        let single = result.single.cumulative
        XCTAssertEqual(single[6], single[7], accuracy: 1e-9, "July (month 7 of the year starting in January)")
        XCTAssertEqual(single[7], single[8], accuracy: 1e-9, "August")
        XCTAssertGreaterThan(single[6], single[5])
        XCTAssertGreaterThan(single[9], single[8])
    }

    func testRegionFilterKeepsOnlyTripsInsideTheState() {
        var input = F.input([F.tirol(4), F.westbahn(2)])
        input.regionFilter = "T"
        let tirolOnly = F.calculator().evaluate(input)
        XCTAssertEqual(tirolOnly.single.yearlyCost, 4 * 12 * 23.5, accuracy: 1e-6)
        input.regionFilter = "W"
        let wienOnly = F.calculator().evaluate(input)
        XCTAssertEqual(wienOnly.state, .noTrips, "Wien → Salzburg is not inside Wien")
    }

    // MARK: Class

    /// 1. Klasse: single tickets × 1,951 (45,80 per trip), KlimaTicket Ö needs the 1.-Klasse-Upgrade (€ 1.490),
    /// regional tickets do not cover the 1. Klasse.
    func testFirstClass() {
        let result = F.calculator().evaluate(F.input([F.tirol(10, travelClass: .first)]))
        XCTAssertEqual(result.single.yearlyCost, 10 * 12 * 45.8, accuracy: 1e-6)
        let oe = F.option(result, "oe-klassik")
        XCTAssertEqual(oe.upgradePrice, 1490)
        XCTAssertEqual(oe.ticketPrice, 1400 + 1490, accuracy: 1e-9)
        XCTAssertEqual(F.option(result, "tirol-klassik").coveredShare, 0)
        XCTAssertEqual(F.option(result, "tirol-klassik").yearlyCost, 590 + 5496, accuracy: 1e-6)
        XCTAssertEqual(result.bestTicket?.id, "oe-klassik")
        XCTAssertTrue(result.includesFirstClass)
        // 2.890 ÷ 5.496 × 10 = 5,26 → from 6 trips a month.
        XCTAssertEqual(result.breakEvenTripsPerMonth, 6)
        // Second class: no upgrade anywhere.
        let second = F.calculator().evaluate(F.input([F.tirol(10)]))
        XCTAssertFalse(second.includesFirstClass)
        XCTAssertEqual(F.option(second, "oe-klassik").upgradePrice, 0)
    }

    // MARK: Zero, negative, huge, broken

    func testZeroTrips() {
        let calc = F.calculator()
        let none = calc.evaluate(F.input([F.tirol(0)]))
        XCTAssertEqual(none.state, .noTrips)
        XCTAssertNil(none.bestTicket)
        XCTAssertNil(none.breakEvenTripsPerMonth)
        XCTAssertNil(none.crossing)
        XCTAssertEqual(none.yearlyDelta, 0)
        XCTAssertEqual(none.single.yearlyCost, 0)
        XCTAssertEqual(calc.evaluate(F.input([])).state, .needsRoutes)
    }

    func testNegativeAndHugeInputsAreClamped() {
        let calc = F.calculator()
        XCTAssertEqual(calc.evaluate(F.input([F.tirol(-5)])).state, .noTrips)
        XCTAssertEqual(calc.evaluate(F.input([F.tirol(Int.min)])).state, .noTrips)
        let huge = calc.evaluate(F.input([F.tirol(Int.max)]))
        let capped = calc.evaluate(F.input([F.tirol(60)]))
        XCTAssertEqual(huge.single.yearlyCost, capped.single.yearlyCost, accuracy: 1e-9)
        XCTAssertEqual(huge.single.yearlyCost, 60 * 12 * 23.5, accuracy: 1e-6)
        XCTAssertTrue(huge.options.allSatisfy { $0.yearlyCost.isFinite })

        // More than three routes: only the first three count.
        let many = calc.evaluate(F.input([F.tirol(1), F.tirol(2), F.tirol(3), F.tirol(50)]))
        XCTAssertEqual(many.tripsPerMonth, 6, accuracy: 1e-9)
        XCTAssertEqual(many.routeFares.count, 3)

        var input = F.input([F.tirol(1)])
        input.volumeFactor = .nan
        XCTAssertEqual(input.clampedVolume, 1)
        input.volumeFactor = 100
        XCTAssertEqual(input.clampedVolume, 2)
        input.volumeFactor = -3
        XCTAssertEqual(input.clampedVolume, 0.5)
        XCTAssertEqual(WhatIfRoute(fromStationID: "a", toStationID: "b", tripsPerMonth: 1_000_000).clampedTrips, 60)
    }

    func testStationsWithoutAFareDoNotCrash() {
        let calc = F.calculator()
        let unknown = WhatIfRoute(fromStationID: "nowhere", toStationID: F.innsbruck.id, tripsPerMonth: 10)
        let same = WhatIfRoute(fromStationID: F.innsbruck.id, toStationID: F.innsbruck.id, tripsPerMonth: 10)
        let result = calc.evaluate(F.input([unknown, same]))
        XCTAssertEqual(result.state, .needsRoutes)
        XCTAssertEqual(result.routeFares.map(\.status), [.unknownStation, .sameStation])
        XCTAssertNil(result.bestTicket)
        // A priced route next to a broken one still counts.
        let mixed = calc.evaluate(F.input([unknown, F.tirol(10)]))
        XCTAssertEqual(mixed.state, .ready)
        XCTAssertEqual(mixed.single.yearlyCost, 2820, accuracy: 1e-6)
        XCTAssertEqual(mixed.routeFares.map(\.isPriced), [false, true])
    }

    /// A station pair the relation table does not know is priced with the distance model, never left empty.
    func testStationWithoutRelationUsesTheDistanceModel() {
        let result = F.calculator().evaluate(F.input([WhatIfRoute(fromStationID: F.neustadt.id, toStationID: F.salzburg.id, tripsPerMonth: 2)]))
        XCTAssertEqual(result.routeFares[0].method, .distanceTariff)
        XCTAssertGreaterThan(result.routeFares[0].farePerTrip, 30)
    }

    // MARK: Consistency with the model

    /// The analytic yearly totals are the same numbers `TicketComparator` computes for the equivalent list of trips.
    func testAssumptionsEqualComparatorOnSyntheticTrips() {
        let calc = F.calculator()
        let input = F.input([F.tirol(4), F.westbahn(2)])
        let result = calc.evaluate(input)
        var trips: [TripRecord] = []
        for month in 0..<12 {
            let day = F.date(2026, 3, 1)
            let date = F.cal.date(byAdding: .month, value: month, to: day)!
            for _ in 0..<4 { trips.append(TripRecord(date: date, fromName: "a", toName: "b", mode: .train, distanceKm: 100, fareEUR: 23.5, states: ["T"])) }
            for _ in 0..<2 { trips.append(TripRecord(date: date, fromName: "c", toName: "d", mode: .train, distanceKm: 300, fareEUR: 67.7, states: ["S", "W"])) }
        }
        let reference = TicketComparator.compare(trips: trips, products: F.catalog().products, variant: .klassik,
                                                 currentProductID: nil, periodStart: input.startDate)
        XCTAssertEqual(Set(reference.map(\.id)), Set(result.options.map(\.id)))
        for option in reference {
            let mine = F.option(result, option.id)
            XCTAssertEqual(mine.ticketPrice, option.ticketPrice, accuracy: 1e-9, option.id)
            XCTAssertEqual(mine.uncoveredYearly, option.uncoveredCost, accuracy: 1e-6, option.id)
            XCTAssertEqual(mine.yearlyCost, option.totalCost, accuracy: 1e-6, option.id)
        }
    }
}
