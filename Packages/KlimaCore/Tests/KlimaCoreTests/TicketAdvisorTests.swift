import XCTest
@testable import KlimaCore

final class TicketAdvisorTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// 9 Oct 2026, noon – inside validity month 8 of a ticket that started on 1 March 2026.
    var now: Date { date(2026, 10, 9, 12) }

    func catalog(fareIndex: [TariffCatalog.FareIndexPoint]? = [.init(validFrom: "2026-12-13", factor: 1.035)],
                 extra: [TicketProduct] = []) -> TariffCatalog {
        let products: [TicketProduct] = [
            TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1400,
                          validFrom: "2026-01-01", priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 1300)]),
            TicketProduct(id: "oe-jugend", family: .oe, name: "KlimaTicket Ö Jugend", variant: .jugend, priceEUR: 1050,
                          validFrom: "2026-01-01", priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 975)]),
            TicketProduct(id: "oe-familie-klassik", family: .oe, name: "KlimaTicket Ö Klassik Familie", variant: .familie,
                          priceEUR: 1540, validFrom: "2026-01-01", priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 1430)]),
            TicketProduct(id: "oe-familie-ermaessigt", family: .oe, name: "KlimaTicket Ö Jugend/Senior/Spezial Familie",
                          variant: .familie, priceEUR: 1190, validFrom: "2026-01-01"),
            TicketProduct(id: "ooe-regional-klassik", family: .regional, states: ["OÖ"], name: "KlimaTicket OÖ Regional",
                          variant: .klassik, priceEUR: 467, validFrom: "2026-01-01"),
            TicketProduct(id: "tirol-klassik", family: .regional, states: ["T"], name: "KlimaTicket Tirol", variant: .klassik,
                          priceEUR: 625.6, validFrom: "2026-04-01"),
            TicketProduct(id: "wien-klassik", family: .regional, states: ["W"], name: "Jahreskarte WIEN", variant: .klassik,
                          priceEUR: 467, validFrom: "2026-01-01"),
            TicketProduct(id: "ktn-klassik", family: .regional, states: ["K"], name: "Kärnten Ticket Classic", variant: .klassik,
                          priceEUR: 449, validFrom: "2026-01-01"),
            TicketProduct(id: "ktn-klassik-familie", family: .regional, states: ["K"], name: "Kärnten Ticket Classic + Familie",
                          variant: .familie, priceEUR: 569, validFrom: "2026-01-01"),
        ] + extra
        return TariffCatalog(version: 1, updatedAt: "2026-10-09", products: products, fareModel: .fallback, cityFares: [],
                             kilometergeldEUR: 0.5, carFullCostPerKmEUR: 0.8, emissions: .fallback, fareIndex: fareIndex)
    }

    func ticket(productID: String = "oe-klassik", family: TicketFamily = .oe, variant: TicketVariant = .klassik,
                price: Double = 1400, start: Date? = nil, monthly: Bool = false, autoRenews: Bool = false,
                employer: Double = 0, addOnPrice: Double = 0, addOns: [String] = []) -> AdvisorTicket {
        let s = start ?? date(2026, 3, 1)
        return AdvisorTicket(productID: productID, name: "Test", family: family, variant: variant, price: price, start: s,
                             end: TicketPeriod.standardEnd(for: s, calendar: cal), isMonthlyPayment: monthly,
                             autoRenews: autoRenews, employerContribution: employer, addOnPrice: addOnPrice, addOns: addOns)
    }

    func trip(_ d: Date, fare: Double, mode: TransportMode = .train, round: Bool = false, companions: Int = 0,
              travelClass: TravelClass = .second, category: TripCategory? = nil, surcharge: Double? = nil) -> AdvisorTrip {
        AdvisorTrip(record: TripRecord(date: d, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hbf", mode: mode,
                                       distanceKm: 100, fareEUR: fare, isRoundTrip: round, companions: companions,
                                       states: ["T"], category: category),
                    travelClass: travelClass, firstClassSurcharge: surcharge)
    }

    /// One trip every `step` days from the ticket start until `until`.
    func regularTrips(from start: Date, until end: Date, every step: Int, fare: Double, round: Bool = true,
                      companions: Int = 0, category: TripCategory? = nil) -> [AdvisorTrip] {
        var result: [AdvisorTrip] = []
        var day = cal.date(bySettingHour: 8, minute: 0, second: 0, of: start)!
        while day <= end {
            result.append(trip(day, fare: fare, round: round, companions: companions, category: category))
            day = cal.date(byAdding: .day, value: step, to: day)!
        }
        return result
    }

    // MARK: Validity months

    func testValidityMonthsStartOnTheSameCalendarDay() {
        let start = date(2026, 3, 1)
        let months = AdvisorValidityMonths(start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal), calendar: cal)
        XCTAssertEqual(months.monthCount, 12)
        XCTAssertEqual(months.start(ofMonth: 7), date(2026, 9, 1))
        XCTAssertEqual(months.month(containing: now), 8)
        XCTAssertEqual(months.lastDay(ofMonth: 8), date(2026, 10, 31))
        XCTAssertEqual(months.lastDay(ofMonth: 12), date(2027, 2, 28))
        XCTAssertEqual(months.month(containing: date(2026, 2, 28)), 0)
        XCTAssertEqual(months.month(containing: date(2027, 2, 28, 23)), 12)
    }

    func testValidityMonthsDoNotDriftAfterShortMonths() {
        let start = date(2026, 1, 31)
        let months = AdvisorValidityMonths(start: start, end: TicketPeriod.standardEnd(for: start, calendar: cal), calendar: cal)
        XCTAssertEqual(months.start(ofMonth: 2), date(2026, 2, 28))
        XCTAssertEqual(months.start(ofMonth: 3), date(2026, 3, 31))
        XCTAssertEqual(months.lastDay(ofMonth: 2), date(2026, 3, 30))
        XCTAssertEqual(months.monthCount, 12)
    }

    // MARK: Cancellation

    func testFeeIsOneMonthlyAmountRoundedAsInTheAGB() {
        let c = catalog()
        let classic = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: c, now: now, calendar: cal).cancellation
        XCTAssertEqual(classic.fee, 116.70, accuracy: 0.001)
        XCTAssertEqual(classic.monthlyAmount, 116.67, accuracy: 0.001)
        let family = TicketAdvisor.advise(ticket: ticket(productID: "oe-familie-klassik", variant: .familie, price: 1540),
                                          trips: [], catalog: c, now: now, calendar: cal).cancellation
        XCTAssertEqual(family.fee, 128.30, accuracy: 0.001)
        let reducedFamily = TicketAdvisor.advise(ticket: ticket(productID: "oe-familie-ermaessigt", variant: .familie, price: 1190),
                                                 trips: [], catalog: c, now: now, calendar: cal).cancellation
        XCTAssertEqual(reducedFamily.fee, 99.20, accuracy: 0.001)
        let reduced = TicketAdvisor.advise(ticket: ticket(productID: "oe-jugend", variant: .jugend, price: 1050),
                                           trips: [], catalog: c, now: now, calendar: cal).cancellation
        XCTAssertEqual(reduced.fee, 87.50, accuracy: 0.001)
    }

    func testSinglePaymentRefundInMonthEight() {
        let advice = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: catalog(), now: now, calendar: cal).cancellation
        XCTAssertEqual(advice.policy, .klimaTicketOe)
        XCTAssertEqual(advice.currentMonth, 8)
        let today = try! XCTUnwrap(advice.today)
        XCTAssertEqual(today.unstartedMonths, 4)
        XCTAssertEqual(today.refundGross, 466.68, accuracy: 0.001)
        XCTAssertEqual(today.refund, 466.68 - 116.70, accuracy: 0.001)
        XCTAssertEqual(today.totalCost, 1400 - today.refund, accuracy: 0.001)
        // Same money back until the last day of the validity month …
        let end = try! XCTUnwrap(advice.endOfMonth)
        XCTAssertEqual(end.date, date(2026, 10, 31))
        XCTAssertEqual(end.refund, today.refund, accuracy: 0.001)
        // … one monthly amount less from the first day of the next one.
        let next = try! XCTUnwrap(advice.nextMonth)
        XCTAssertEqual(next.date, date(2026, 11, 1))
        XCTAssertEqual(next.month, 9)
        XCTAssertEqual(today.refund - next.refund, 116.67, accuracy: 0.001)
        // Without trips nothing is lost → cancelling is worth a thought.
        XCTAssertEqual(advice.verdict, .consider)
    }

    func testMonthlyPaymentStopsInstalmentsInsteadOfRefund() {
        let advice = TicketAdvisor.advise(ticket: ticket(monthly: true), trips: [], catalog: catalog(), now: now, calendar: cal).cancellation
        let q = try! XCTUnwrap(advice.endOfMonth)
        XCTAssertEqual(q.refund, 0)
        XCTAssertEqual(q.saving, 4 * 116.67 - 116.70, accuracy: 0.001)
        // Paid 8 instalments + the fee = the same total as with single payment.
        XCTAssertEqual(q.totalCost, 1400 - q.saving, accuracy: 0.001)
        let single = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: catalog(), now: now, calendar: cal).cancellation
        XCTAssertEqual(q.totalCost, try! XCTUnwrap(single.endOfMonth).totalCost, accuracy: 0.001)
    }

    func testNotPossibleBeforeTheSeventhMonth() {
        let early = date(2026, 7, 20, 12) // month 5
        let advice = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: catalog(), now: early, calendar: cal).cancellation
        XCTAssertEqual(advice.verdict, .notYet)
        XCTAssertNil(advice.today)
        XCTAssertEqual(advice.possibleFrom, date(2026, 9, 1))
        let first = try! XCTUnwrap(advice.firstPossible)
        XCTAssertEqual(first.month, 7)
        XCTAssertEqual(first.refund, 5 * 116.67 - 116.70, accuracy: 0.001)
        // Extraordinary reasons work at any time and without the fee.
        let extra = try! XCTUnwrap(advice.extraordinary)
        XCTAssertEqual(extra.fee, 0)
        XCTAssertEqual(extra.refund, 7 * 116.67, accuracy: 0.001)
    }

    func testLastMonthsAreNotWorthwhile() {
        let late = date(2027, 1, 10, 12) // month 11
        let advice = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: catalog(), now: late, calendar: cal).cancellation
        XCTAssertEqual(advice.currentMonth, 11)
        XCTAssertEqual(advice.verdict, .notWorthwhile)
        XCTAssertEqual(advice.endOfMonth?.refund, 0)
    }

    func testKeepWhenProjectedTripsAreWorthMoreThanTheRefund() {
        let t = ticket()
        let trips = regularTrips(from: t.start, until: now, every: 3, fare: 8) // ≈ € 5,33 per day
        let advice = TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal)
        let c = advice.cancellation
        XCTAssertEqual(c.verdict, .keep)
        let end = try! XCTUnwrap(c.endOfMonth)
        // Lost value = pace × days from the last day of the month to expiry.
        XCTAssertEqual(end.lostTripValue, advice.dailyPace * 120, accuracy: 0.01)
        XCTAssertGreaterThan(end.lostTripValue, end.saving)
        XCTAssertGreaterThan(try! XCTUnwrap(c.today).lostTripValue, end.lostTripValue)
        // Timeline: 12 months, the first six not allowed, month 8 current.
        XCTAssertEqual(c.months.count, 12)
        XCTAssertEqual(c.months.filter { !$0.isAllowed }.count, 6)
        XCTAssertEqual(c.months.first { $0.isCurrent }?.index, 8)
        XCTAssertTrue(c.months[6].isPast)
    }

    func testKennenlernAktionIsFeeFreeFromTheSecondMonth() {
        let start = date(2026, 5, 15)
        let t = ticket(start: start)
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: t, calendar: cal), .kennenlern)
        let c = TicketAdvisor.advise(ticket: t, trips: [], catalog: catalog(), now: date(2026, 6, 20, 12), calendar: cal).cancellation
        XCTAssertEqual(c.possibleFromMonth, 2)
        XCTAssertEqual(c.fee, 0)
        XCTAssertEqual(c.currentMonth, 2)
        XCTAssertEqual(try! XCTUnwrap(c.today).refund, 10 * 116.67, accuracy: 0.001)
        // A start outside the promotion window is a regular ticket.
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: ticket(start: date(2026, 7, 1)), calendar: cal), .klimaTicketOe)
    }

    func testBeforeStartAndExpired() {
        let future = ticket(start: date(2026, 11, 1))
        XCTAssertEqual(TicketAdvisor.advise(ticket: future, trips: [], catalog: catalog(), now: now, calendar: cal).cancellation.verdict,
                       .beforeStart)
        let old = ticket(price: 1300, start: date(2025, 5, 1))
        XCTAssertEqual(TicketAdvisor.advise(ticket: old, trips: [], catalog: catalog(), now: now, calendar: cal).cancellation.verdict,
                       .expired)
    }

    func testRegionalPolicies() {
        let ooe = ticket(productID: "ooe-regional-klassik", family: .regional, price: 467)
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: ooe, calendar: cal), .ooevv)
        let ooeAdvice = TicketAdvisor.advise(ticket: ooe, trips: [], catalog: catalog(), now: now, calendar: cal).cancellation
        XCTAssertEqual(ooeAdvice.fee, 38.90, accuracy: 0.001)
        XCTAssertNotNil(ooeAdvice.endOfMonth)

        let tirol = ticket(productID: "tirol-klassik", family: .regional, price: 625.6)
        let tirolAdvice = TicketAdvisor.advise(ticket: tirol, trips: [], catalog: catalog(), now: now, calendar: cal).cancellation
        guard case .regional(let note) = tirolAdvice.policy else { return XCTFail("expected a regional note") }
        XCTAssertTrue(note.contains("VVT"))
        XCTAssertEqual(tirolAdvice.verdict, .unsupported)
        XCTAssertTrue(tirolAdvice.months.isEmpty)

        let custom = ticket(productID: "custom", family: .custom, price: 500)
        XCTAssertEqual(TicketAdvisor.cancellationPolicy(for: custom, calendar: cal), .custom)
    }

    // MARK: Renewal

    func testRenewalProjectionAndPriceStatus() {
        let t = ticket(autoRenews: true)
        let trips = regularTrips(from: t.start, until: now, every: 3, fare: 10) // ≈ € 6,67 per day → ≈ € 2.400 a year
        let advice = TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal)
        let r = advice.renewal
        XCTAssertEqual(r.renewalStart, date(2027, 3, 1))
        XCTAssertEqual(r.nextPrice, 1400)
        XCTAssertEqual(r.priceStatus, .latestKnown)
        XCTAssertEqual(r.priceChange, 0)
        XCTAssertEqual(r.fareGrowth, 1.035, accuracy: 0.0001)
        XCTAssertEqual(r.projectedValueAtExpiry, advice.summary.forecastEndValue, accuracy: 0.001)
        XCTAssertEqual(r.projectedNetAtExpiry, r.projectedValueAtExpiry - 1400, accuracy: 0.001)
        // 2027/28 has 366 days (29 Feb 2028), the current year 365.
        XCTAssertEqual(r.projectedNextYearValue, r.projectedValueAtExpiry * 1.035 * 366 / 365, accuracy: 0.01)
        XCTAssertEqual(r.verdict, .renew)
        XCTAssertEqual(r.nextYearLabel, "2027/28")
        XCTAssertNotNil(r.nextYearBreakEvenDate)
        XCTAssertNotNil(r.nextYearBreakEvenTrips)
        // Letter ~2 months, reminder 9 weeks (63 days) before expiry at 09:00.
        XCTAssertEqual(r.letterDate, date(2026, 12, 28))
        XCTAssertEqual(r.reminderDate, date(2026, 12, 27, 9))
        XCTAssertTrue(r.autoRenews)
    }

    func testAnnouncedPriceIsUsedForTheRenewalStart() {
        let raised = TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1490,
                                   validFrom: "2027-01-01",
                                   priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 1300), .init(validFrom: "2026-01-01", priceEUR: 1400)])
        var c = catalog()
        c.products.removeAll { $0.id == "oe-klassik" }
        c.products.append(raised)
        let r = TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: c, now: now, calendar: cal).renewal
        XCTAssertEqual(r.nextPrice, 1490)
        XCTAssertEqual(r.priceStatus, .announced(date(2027, 1, 1)))
        XCTAssertEqual(r.priceChange, 90)
    }

    func testRenewalVerdicts() {
        let t = ticket()
        let light = regularTrips(from: t.start, until: now, every: 7, fare: 10) // ≈ € 1.040 a year
        XCTAssertEqual(TicketAdvisor.advise(ticket: t, trips: light, catalog: catalog(), now: now, calendar: cal).renewal.verdict,
                       .reconsider)
        let few = [trip(date(2026, 3, 5, 8), fare: 20), trip(date(2026, 4, 5, 8), fare: 20)]
        XCTAssertEqual(TicketAdvisor.advise(ticket: t, trips: few, catalog: catalog(), now: now, calendar: cal).renewal.verdict,
                       .tooEarly)
        // An employer paying the whole price makes renewing a no-brainer.
        let paid = ticket(employer: 1400)
        XCTAssertEqual(TicketAdvisor.advise(ticket: paid, trips: light, catalog: catalog(), now: now, calendar: cal).renewal.verdict,
                       .renew)
    }

    func testRenewalForATicketBoughtAtTheOldPrice() {
        let t = ticket(price: 1300, start: date(2025, 12, 1))
        let r = TicketAdvisor.advise(ticket: t, trips: [], catalog: catalog(), now: now, calendar: cal).renewal
        XCTAssertEqual(r.nextPrice, 1400)
        XCTAssertEqual(r.priceChange, 100)
        XCTAssertEqual(r.renewalStart, date(2026, 12, 1))
    }

    func testViennaAnnualPassDeadlineIsOneMonthBeforeExpiry() {
        let t = ticket(productID: "wien-klassik", family: .regional, price: 467, autoRenews: true)
        let r = TicketAdvisor.advise(ticket: t, trips: [], catalog: catalog(), now: now, calendar: cal).renewal
        XCTAssertEqual(r.cancellationDeadline, date(2027, 1, 28))
        XCTAssertNil(r.letterDate)
        XCTAssertEqual(r.reminderDate, date(2027, 1, 14, 9))
    }

    // MARK: First class

    func testFirstClassSurchargeFromTariffFactor() {
        let t = ticket()
        let trips = [trip(date(2026, 4, 1, 8), fare: 20, round: true), trip(date(2026, 4, 2, 8), fare: 10),
                     trip(date(2026, 4, 3, 8), fare: 3.2, mode: .metro)]
        let advice = TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal)
        let f = try! XCTUnwrap(advice.firstClass)
        let factor = FareModel.fallback.firstClassFactor
        XCTAssertEqual(f.trainTrips, 2)
        XCTAssertEqual(f.trainLegs, 3)
        XCTAssertEqual(f.surchargeSoFar, (20 * 2 + 10) * (factor - 1), accuracy: 0.001)
        XCTAssertEqual(f.upgradePrice, 1490)
        XCTAssertEqual(f.vorteilsaboPrice, 100)
        XCTAssertFalse(f.hasUpgrade)
        XCTAssertEqual(f.verdict, .notWorthIt)
        XCTAssertGreaterThanOrEqual(f.projectedSurcharge, f.surchargeSoFar)
        XCTAssertEqual(f.legsNeeded, Int((1490 / f.averageSurchargePerLeg).rounded(.up)))
        // Vorteilsabo: € 100 + 70 % of the class changes beyond the two free ones.
        let free = 20 * (factor - 1) * 2
        XCTAssertEqual(f.vorteilsaboCost, 100 + 0.7 * max(0, f.projectedSurcharge - free), accuracy: 0.01)
    }

    func testFirstClassUsesEstimatorSurchargeAndFirstClassFares() {
        let t = ticket(addOnPrice: 1490, addOns: ["firstClass"])
        let factor = FareModel.fallback.firstClassFactor
        let trips = [trip(date(2026, 4, 1, 8), fare: 39.02, travelClass: .first),        // stored 1st-class fare → 20 in 2nd
                     trip(date(2026, 4, 2, 8), fare: 20, surcharge: 25)]                  // estimator value wins
        let f = try! XCTUnwrap(TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal).firstClass)
        XCTAssertTrue(f.hasUpgrade)
        // Upgrade holders who mark 1st class: only those trips count.
        XCTAssertTrue(f.countsOnlyFirstClassTrips)
        XCTAssertEqual(f.trainTrips, 1)
        XCTAssertEqual(f.surchargeSoFar, 39.02 / factor * (factor - 1), accuracy: 0.001)
        XCTAssertEqual(f.verdict, .notPaidOff)

        let estimated = TicketAdvisor.surcharge(of: trips[1], factor: factor)
        XCTAssertEqual(estimated, 25)
    }

    func testFirstClassPricesPerCategoryAndRegionalTicketsHaveNoUpgrade() {
        XCTAssertEqual(TicketAddOn.firstClass.listPrice(productID: "oe-klassik", variant: .klassik), 1490)
        XCTAssertEqual(TicketAddOn.firstClass.listPrice(productID: "oe-familie-klassik", variant: .familie), 1645)
        XCTAssertEqual(TicketAddOn.firstClass.listPrice(productID: "oe-senior", variant: .senior), 1130)
        XCTAssertEqual(TicketAddOn.firstClass.listPrice(productID: "oe-familie-ermaessigt", variant: .familie), 1285)
        XCTAssertEqual(TicketAddOn.vorteilsabo.listPrice(productID: "oe-jugend", variant: .jugend), 90)
        XCTAssertEqual(TicketAddOn.vorteilsabo.listPrice(productID: "oe-klassik", variant: .klassik), 100)
        XCTAssertEqual(TicketAddOn.business.listPrice(productID: "oe-klassik", variant: .klassik), 290)
        XCTAssertEqual(TicketAddOn.listTotal([.firstClass, .business], productID: "oe-klassik", variant: .klassik), 1780)
        XCTAssertEqual(TicketAddOn.parse(["firstClass", "bogus", " vorteilsabo"]), [.firstClass, .vorteilsabo])

        let tirol = ticket(productID: "tirol-klassik", family: .regional, price: 625.6)
        XCTAssertNil(TicketAdvisor.advise(ticket: tirol, trips: [], catalog: catalog(), now: now, calendar: cal).firstClass)
    }

    func testFirstClassWorthItForHeavyLongDistanceTravel() {
        let t = ticket()
        let trips = regularTrips(from: t.start, until: now, every: 2, fare: 30) // many long trips
        let f = try! XCTUnwrap(TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal).firstClass)
        XCTAssertEqual(f.verdict, .worthIt)
        XCTAssertEqual(f.cheapestOption, .upgrade)
    }

    func testAdvisorTripMakeUsesTheEstimator() {
        let a = Station(id: "a", name: "Innsbruck Hbf", lat: 47.2632, lon: 11.4009, state: "T")
        let b = Station(id: "b", name: "Salzburg Hbf", lat: 47.8129, lon: 13.0455, state: "S")
        let stations = StationIndex(stations: [a, b])
        let estimator = FareEstimator(catalog: catalog(fareIndex: nil))
        let record = TripRecord(date: date(2026, 4, 1, 8), fromName: a.name, toName: b.name, fromStationID: "a", toStationID: "b",
                                mode: .train, distanceKm: 180, fareEUR: 40)
        let made = AdvisorTrip.make(record, travelClass: .second, estimator: estimator, stations: stations)
        let first = estimator.estimate(from: a, to: b, mode: .train, travelClass: .first, date: record.date).fareEUR
        let second = estimator.estimate(from: a, to: b, mode: .train, travelClass: .second, date: record.date).fareEUR
        XCTAssertEqual(try! XCTUnwrap(made.firstClassSurcharge), first - second, accuracy: 0.001)
        // Buses and unknown stations fall back to the tariff factor.
        var bus = record
        bus.mode = .bus
        XCTAssertNil(AdvisorTrip.make(bus, travelClass: .second, estimator: estimator, stations: stations).firstClassSurcharge)
        var unknown = record
        unknown.toStationID = nil
        XCTAssertNil(AdvisorTrip.make(unknown, travelClass: .second, estimator: estimator, stations: stations).firstClassSurcharge)
    }

    // MARK: Family

    func testFamilyBalanceValuesChildrenAtHalfFare() {
        let t = ticket(productID: "oe-familie-klassik", variant: .familie, price: 1540)
        let trips = [trip(date(2026, 4, 4, 9), fare: 20, round: true, companions: 2),
                     trip(date(2026, 5, 9, 9), fare: 10, companions: 6),       // only 4 children are covered
                     trip(date(2026, 6, 1, 9), fare: 30)]
        let f = try! XCTUnwrap(TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal).family)
        XCTAssertTrue(f.isFamilyTicket)
        XCTAssertEqual(f.surcharge, 140, accuracy: 0.001)
        XCTAssertEqual(f.tripsWithChildren, 2)
        XCTAssertEqual(f.childJourneys, 2 * 2 + 4)
        XCTAssertEqual(f.childValueSoFar, 2 * 2 * 10 + 4 * 5, accuracy: 0.001)
        XCTAssertEqual(f.averageChildren, 3, accuracy: 0.001)
        XCTAssertEqual(f.verdict, .notPaidOff)
    }

    func testFamilySurchargeFromCatalogue() {
        let c = catalog()
        XCTAssertEqual(TicketAdvisor.familySurcharge(productID: "oe-klassik", variant: .klassik, start: date(2026, 3, 1), catalog: c), 140)
        XCTAssertEqual(TicketAdvisor.familySurcharge(productID: "oe-familie-klassik", variant: .familie, start: date(2025, 9, 1),
                                                     catalog: c), 130)
        XCTAssertEqual(TicketAdvisor.familySurcharge(productID: "oe-familie-ermaessigt", variant: .familie, start: date(2026, 3, 1),
                                                     catalog: c), 140)
        XCTAssertEqual(TicketAdvisor.familySurcharge(productID: "ktn-klassik", variant: .klassik, start: date(2026, 3, 1), catalog: c), 120)
        XCTAssertNil(TicketAdvisor.familySurcharge(productID: "tirol-klassik", variant: .klassik, start: date(2026, 4, 1), catalog: c))
    }

    func testSwitchingToFamilyAndNoFamilySectionWithoutCompanions() {
        let t = ticket()
        let trips = regularTrips(from: t.start, until: now, every: 10, fare: 20, companions: 2)
        let f = try! XCTUnwrap(TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal).family)
        XCTAssertFalse(f.isFamilyTicket)
        XCTAssertEqual(f.verdict, .worthSwitching)
        XCTAssertGreaterThan(f.projectedChildValue, f.childValueSoFar)
        let alone = regularTrips(from: t.start, until: now, every: 10, fare: 20)
        XCTAssertNil(TicketAdvisor.advise(ticket: t, trips: alone, catalog: catalog(), now: now, calendar: cal).family)
        let familyTicket = ticket(productID: "oe-familie-klassik", variant: .familie, price: 1540)
        XCTAssertEqual(TicketAdvisor.advise(ticket: familyTicket, trips: alone, catalog: catalog(), now: now, calendar: cal).family?.verdict,
                       .noChildTrips)
    }

    // MARK: Jobticket

    func testJobticketMeasuresPayoffAgainstOwnShare() {
        let t = ticket(employer: 800)
        let trips = regularTrips(from: t.start, until: now, every: 4, fare: 10, category: .business)
        let advice = TicketAdvisor.advise(ticket: t, trips: trips, catalog: catalog(), now: now, calendar: cal)
        let j = advice.jobticket
        XCTAssertTrue(j.hasContribution)
        XCTAssertEqual(j.ownShare, 600)
        XCTAssertEqual(j.fullPrice, 1400)
        XCTAssertEqual(j.ownShareFraction, 600.0 / 1400.0, accuracy: 0.0001)
        XCTAssertEqual(advice.summary.ticketPrice, 600)
        XCTAssertTrue(j.isOwnSharePaidOff)
        XCTAssertFalse(j.isFullPricePaidOff)
        let own = try! XCTUnwrap(j.ownBreakEven)
        if let full = j.fullBreakEven { XCTAssertGreaterThan(full, own) }
        // AK: business trips with the own ticket are deductible up to the own share.
        XCTAssertEqual(j.businessTripValue, advice.summary.totalValue, accuracy: 0.001)
        XCTAssertEqual(j.deductibleBusinessValue, 600, accuracy: 0.001)
        // The refund is based on the ticket price paid to KlimaTicket, not the own share.
        XCTAssertEqual(advice.cancellation.price, 1400)
    }

    func testOwnShareIncludesAddOnsAndNeverGoesNegative() {
        XCTAssertEqual(ticket(employer: 200, addOnPrice: 100, addOns: ["vorteilsabo"]).ownShare, 1300)
        XCTAssertEqual(ticket(employer: 5000).ownShare, 0)
        let j = TicketAdvisor.advise(ticket: ticket(employer: 5000), trips: [], catalog: catalog(), now: now, calendar: cal).jobticket
        XCTAssertEqual(j.contribution, 1400)
        XCTAssertFalse(TicketAdvisor.advise(ticket: ticket(), trips: [], catalog: catalog(), now: now, calendar: cal).jobticket.hasContribution)
    }

    // MARK: Euro input

    func testEuroAmountParsing() {
        XCTAssertEqual(AdvisorEuro.parse("1.234,50"), 1234.5)
        XCTAssertEqual(AdvisorEuro.parse("800"), 800)
        XCTAssertEqual(AdvisorEuro.parse("€ 1 234,50"), 1234.5)
        XCTAssertEqual(AdvisorEuro.parse("1\u{00A0}234,5"), 1234.5)
        XCTAssertEqual(AdvisorEuro.parse("1.490,-"), 1490)
        XCTAssertEqual(AdvisorEuro.parse("1,50"), 1.5)
        XCTAssertEqual(AdvisorEuro.parse("0,99"), 0.99)
        XCTAssertEqual(AdvisorEuro.parse(",5"), 0.5)
        XCTAssertEqual(AdvisorEuro.parse("23.5"), 23.5)
        XCTAssertEqual(AdvisorEuro.parse("23.50"), 23.5)
        XCTAssertEqual(AdvisorEuro.parse("1.234"), 1234)
        XCTAssertEqual(AdvisorEuro.parse("1.234.567"), 1_234_567)
        XCTAssertEqual(AdvisorEuro.parse("1,234.50"), 1234.5)
        XCTAssertEqual(AdvisorEuro.parse("1.234,567"), 1234.57)
        XCTAssertEqual(AdvisorEuro.parse(" 800 € "), 800)
        XCTAssertNil(AdvisorEuro.parse(""))
        XCTAssertNil(AdvisorEuro.parse("abc"))
        XCTAssertNil(AdvisorEuro.parse("-5"))
        XCTAssertNil(AdvisorEuro.parse(","))
        XCTAssertNil(AdvisorEuro.parse("1,2,3.4,5"))
    }

    func testEuroAmountEditString() {
        XCTAssertEqual(AdvisorEuro.editString(1234.5), "1.234,50")
        XCTAssertEqual(AdvisorEuro.editString(800), "800")
        XCTAssertEqual(AdvisorEuro.editString(1_234_567.89), "1.234.567,89")
        XCTAssertEqual(AdvisorEuro.editString(0.05), "0,05")
        XCTAssertEqual(AdvisorEuro.editString(0), "")
        for value in [0.5, 12.3, 999.99, 1490, 20_000.01] {
            XCTAssertEqual(AdvisorEuro.parse(AdvisorEuro.editString(value)), value, "round trip \(value)")
        }
    }

    func testYearLabel() {
        XCTAssertEqual(TicketAdvisor.yearLabel(start: date(2027, 3, 1), end: date(2028, 2, 29), calendar: cal), "2027/28")
        XCTAssertEqual(TicketAdvisor.yearLabel(start: date(2027, 1, 1), end: date(2027, 12, 31), calendar: cal), "2027")
    }
}
