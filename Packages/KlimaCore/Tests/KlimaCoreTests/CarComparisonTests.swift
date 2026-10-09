import XCTest
@testable import KlimaCore

final class CarComparisonTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func ticket(price: Double = 1400) -> TicketPeriod {
        let start = date(2026, 1, 1, 0)
        return TicketPeriod(productID: "oe-klassik", name: "KlimaTicket Ö Klassik", price: price,
                            start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal))
    }

    func trip(_ d: Date, km: Double = 100, fare: Double = 22, mode: TransportMode = .train, round: Bool = false) -> TripRecord {
        TripRecord(date: d, fromName: "Innsbruck Hbf", toName: "St. Anton am Arlberg", mode: mode, distanceKm: km,
                   fareEUR: fare, isRoundTrip: round)
    }

    // MARK: Cost per km

    func testCostPerKmPerMode() {
        var profile = CarProfile()
        XCTAssertEqual(profile.costPerKm, 0.50, accuracy: 1e-9)          // amtliches Kilometergeld 2025+
        profile.mode = .fuelOnly
        XCTAssertEqual(profile.costPerKm, 6.5 * 1.65 / 100, accuracy: 1e-9) // € 0,107/km
        profile.mode = .fullCost
        profile.fullCostPerKm = 0.58
        XCTAssertEqual(profile.costPerKm, 0.58, accuracy: 1e-9)
    }

    func testDefaultsMatchOfficialValues() {
        XCTAssertEqual(CarProfile.defaultKilometergeld, 0.50)
        XCTAssertEqual(CarFixedCosts.vignette2026, 106.80)
        XCTAssertEqual(CarProfile.defaultRoadDistanceFactor, 1.15)
        XCTAssertEqual(CarFixedCosts.defaults.total, 950 + 106.80 + 0 + 450, accuracy: 1e-9)
    }

    func testRoadFactorNeverShrinksDistance() {
        var profile = CarProfile()
        XCTAssertEqual(profile.roadKm(railKm: 100), 115, accuracy: 1e-9)
        profile.roadDistanceFactor = 0.5
        XCTAssertEqual(profile.roadKm(railKm: 100), 100, accuracy: 1e-9)
    }

    func testFixedCostsOnlyWhenCarGivenUp() {
        var profile = CarProfile(mode: .fuelOnly)
        XCTAssertEqual(profile.fixedCostsPerYear, 0)
        XCTAssertFalse(profile.mayDoubleCountFixedCosts)
        profile.carGivenUp = true
        XCTAssertEqual(profile.fixedCostsPerYear, CarFixedCosts.defaults.total, accuracy: 1e-9)
        XCTAssertFalse(profile.mayDoubleCountFixedCosts)
        profile.mode = .kilometergeld
        XCTAssertTrue(profile.mayDoubleCountFixedCosts)
    }

    // MARK: Comparison

    func testVariableCostUsesRoadKmAndAllLegs() {
        let trips = [trip(date(2026, 2, 3), km: 100, round: true), trip(date(2026, 2, 10), km: 50)]
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(), now: date(2026, 3, 1))
        XCTAssertEqual(result.railKm, 250, accuracy: 1e-9)
        XCTAssertEqual(result.roadKm, 287.5, accuracy: 1e-9)
        XCTAssertEqual(result.variableCost, 287.5 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.legCount, 3)
        XCTAssertEqual(result.tripCount, 2)
        XCTAssertEqual(result.fixedCostsToDate, 0)
        XCTAssertEqual(result.carCost, result.variableCost, accuracy: 1e-9)
        XCTAssertEqual(result.savings, result.carCost - 1400, accuracy: 1e-9)
        XCTAssertFalse(result.isCheaperThanCar)
    }

    func testIgnoresTripsOutsidePeriodAndInFuture() {
        let trips = [trip(date(2025, 12, 31)), trip(date(2026, 2, 1)), trip(date(2026, 5, 1))]
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(), now: date(2026, 3, 1))
        XCTAssertEqual(result.tripCount, 1)
    }

    func testBreakEvenDateIsFirstDayCarCostReachesTicket() {
        // 3 × 1.000 rail km = 3 × 575 € by car → crosses € 1.400 on the third trip.
        let trips = [trip(date(2026, 1, 10), km: 1000), trip(date(2026, 1, 20), km: 1000), trip(date(2026, 2, 5), km: 1000)]
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(), now: date(2026, 3, 1))
        XCTAssertEqual(result.breakEvenDate, cal.startOfDay(for: date(2026, 2, 5)))
        XCTAssertNil(result.forecastBreakEvenDate)
        XCTAssertTrue(result.isCheaperThanCar)
        XCTAssertEqual(result.savings, 1725 - 1400, accuracy: 1e-6)
    }

    func testFixedCostsAccruePerDayAndCanCauseBreakEven() {
        var profile = CarProfile(mode: .fuelOnly, carGivenUp: true)
        profile.fixedCosts = CarFixedCosts(insurance: 3650, vignette: 0, parking: 0, service: 0)   // € 10 per day
        let now = date(2026, 1, 10, 20)
        let result = CarComparison.compare(ticket: ticket(price: 50), trips: [], profile: profile, now: now)
        XCTAssertEqual(result.fixedCostsToDate, 3650.0 / 365 * 10, accuracy: 1e-6)
        XCTAssertEqual(result.series.count, 11)                 // start (0) + 10 days
        XCTAssertEqual(result.series.first?.value, 0)
        XCTAssertEqual(result.breakEvenDate, cal.startOfDay(for: date(2026, 1, 5)))   // 5 days × € 10 = € 50
    }

    func testSeriesIsMonotonicAndEndsToday() {
        let trips = (0..<20).map { trip(date(2026, 1, 3 + $0 * 2), km: 40, round: true) }
        let now = date(2026, 3, 1, 18)
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(carGivenUp: true), now: now)
        let values = result.series.map(\.value)
        XCTAssertEqual(values, values.sorted())
        XCTAssertTrue(cal.isDate(result.series.last!.date, inSameDayAs: now))
        XCTAssertEqual(result.series.last!.value, result.carCost, accuracy: 1e-6)
        XCTAssertEqual(Set(result.series.map(\.date)).count, result.series.count)
    }

    func testForecastReachesEndAndPredictsBreakEven() {
        // ~ € 23 car cost every 2 days → crosses € 1.400 within the year.
        let trips = (0..<30).map { trip(date(2026, 1, 2 + $0 * 2), km: 20, round: true) }
        let now = date(2026, 3, 1, 12)
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(), now: now)
        XCTAssertNil(result.breakEvenDate)
        XCTAssertEqual(result.forecast.count, 2)
        XCTAssertGreaterThan(result.projectedEndCarCost, result.carCost)
        let forecastDate = try! XCTUnwrap(result.forecastBreakEvenDate)
        XCTAssertGreaterThan(forecastDate, now)
        XCTAssertLessThanOrEqual(forecastDate, ticket().end)
    }

    func testNoForecastAfterPeriodEnd() {
        let result = CarComparison.compare(ticket: ticket(), trips: [trip(date(2026, 6, 1))], profile: CarProfile(),
                                           now: date(2027, 3, 1))
        XCTAssertTrue(result.forecast.isEmpty)
        XCTAssertEqual(result.series.count, 366)          // start + 365 days
    }

    func testFutureTicketHasOnlyStartPoint() {
        let result = CarComparison.compare(ticket: ticket(), trips: [], profile: CarProfile(carGivenUp: true), now: date(2025, 12, 1))
        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.fixedCostsToDate, 0)
        XCTAssertTrue(result.forecast.isEmpty)
    }

    func testZeroTicketCostIsImmediatelyCheaper() {
        let result = CarComparison.compare(ticket: ticket(price: 0), trips: [], profile: CarProfile(), now: date(2026, 2, 1))
        XCTAssertTrue(result.isCheaperThanCar)
        XCTAssertEqual(result.breakEvenDate, cal.startOfDay(for: date(2026, 1, 1)))
    }

    // MARK: CO₂ & time

    func testCO2UsesRoadKmForCarAndModeFactorForTransit() {
        let f = EmissionFactors.fallback
        let trips = [trip(date(2026, 2, 1), km: 100, mode: .train), trip(date(2026, 2, 2), km: 10, mode: .bus)]
        let result = CarComparison.compare(ticket: ticket(), trips: trips, profile: CarProfile(), emissions: f, now: date(2026, 3, 1))
        XCTAssertEqual(result.co2CarKg, f.car * 110 * 1.15 / 1000, accuracy: 1e-9)
        XCTAssertEqual(result.co2TransitKg, (f.train * 100 + f.bus * 10) / 1000, accuracy: 1e-9)
        XCTAssertEqual(result.co2SavedKg, result.co2CarKg - result.co2TransitKg, accuracy: 1e-9)
    }

    func testDrivingHoursBySpeedBand() {
        XCTAssertEqual(CarComparison.averageSpeedKmh(forLegKm: 5), 30)
        XCTAssertEqual(CarComparison.averageSpeedKmh(forLegKm: 30), 50)
        XCTAssertEqual(CarComparison.averageSpeedKmh(forLegKm: 116), 70)
        XCTAssertEqual(CarComparison.averageSpeedKmh(forLegKm: 547), 85)
        XCTAssertEqual(CarComparison.drivingHours(roadKmPerLeg: 0), 0)
        let result = CarComparison.compare(ticket: ticket(), trips: [trip(date(2026, 2, 1), km: 100, round: true)],
                                           profile: CarProfile(), now: date(2026, 3, 1))
        XCTAssertEqual(result.drivingHours, 2 * 115 / 70, accuracy: 1e-9)
    }
}

final class CarInputParserTests: XCTestCase {
    func testAustrianDecimalsAndGrouping() {
        XCTAssertEqual(CarInputParser.decimal("1,65", in: 0.5...3), 1.65)
        XCTAssertEqual(CarInputParser.decimal("1.65", in: 0.5...3), 1.65)
        XCTAssertEqual(CarInputParser.decimal("1.659", in: 0.5...3), 1.659)        // € per litre: decimal
        XCTAssertEqual(CarInputParser.decimal("1.100", in: 0...20_000), 1100)      // de-AT thousands
        XCTAssertEqual(CarInputParser.decimal("0.500", in: 0.05...3), 0.5)         // grouped reading out of range → decimal
        XCTAssertEqual(CarInputParser.decimal("1.100,50", in: 0...20_000), 1100.5)
        XCTAssertEqual(CarInputParser.decimal("€ 106,80", in: 0...1000), 106.8)
        XCTAssertEqual(CarInputParser.decimal("6,5 l", in: 2...25), 6.5)
        XCTAssertEqual(CarInputParser.decimal("150", in: 0.5...3), 3)              // clamped
        XCTAssertNil(CarInputParser.decimal("", in: 0...1))
        XCTAssertNil(CarInputParser.decimal("abc", in: 0...1))
    }
}
