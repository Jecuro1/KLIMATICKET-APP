import XCTest
@testable import KlimaCore

final class WorkTaxTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func item(_ d: Date, fare: Double, km: Double = 100, round: Bool = true, category: TripCategory?) -> WorkTaxTrip {
        WorkTaxTrip(date: d, fromName: "St. Anton am Arlberg", toName: "Innsbruck Hauptbahnhof", mode: .train, distanceKm: km,
                    isRoundTrip: round, singleFare: fare, category: category)
    }

    // MARK: Dienstreisen (AK)

    func testBusinessTripsSumSingleTicketsOfBusinessOnly() {
        let trips = [item(date(2026, 3, 2), fare: 23.5, category: .business),
                     item(date(2026, 3, 3), fare: 23.5, category: .commute),
                     item(date(2026, 3, 4), fare: 10, round: false, category: .business),
                     item(date(2026, 3, 5), fare: 50, category: nil)]
        let summary = WorkTax.businessTrips(trips, cap: 600)
        XCTAssertEqual(summary.trips.count, 2)
        XCTAssertEqual(summary.total, 57, accuracy: 1e-9)
        XCTAssertEqual(summary.claimable, 57, accuracy: 1e-9)
        XCTAssertEqual(summary.remainingCap, 543, accuracy: 1e-9)
        XCTAssertFalse(summary.isCapped)
        XCTAssertEqual(summary.totalKm, 300, accuracy: 1e-9)
    }

    func testBusinessTripsAreCappedAtOwnShare() {
        // AK example: € 1.400 ticket − € 800 employer contribution = € 600 cap.
        let trips = (0..<20).map { item(date(2026, 2, 1 + $0), fare: 23.5, category: .business) }   // 20 × 47 € = 940 €
        let summary = WorkTax.businessTrips(trips, cap: 1400 - 800)
        XCTAssertEqual(summary.total, 940, accuracy: 1e-9)
        XCTAssertEqual(summary.claimable, 600, accuracy: 1e-9)
        XCTAssertTrue(summary.isCapped)
        XCTAssertEqual(summary.capUsage, 1)
        XCTAssertEqual(summary.remainingCap, 0)
    }

    func testCapIsAllocatedChronologicallyAcrossCalendarYears() {
        let trips = [item(date(2026, 11, 2), fare: 200, category: .business),     // 400 €
                     item(date(2027, 1, 12), fare: 200, category: .business),     // 400 €
                     item(date(2027, 2, 2), fare: 50, category: .business)]       // 100 €
        let summary = WorkTax.businessTrips(trips, cap: 600)
        XCTAssertTrue(summary.spansSeveralYears)
        XCTAssertEqual(summary.years.map(\.year), [2026, 2027])
        XCTAssertEqual(summary.years[0].claimable, 400, accuracy: 1e-9)
        XCTAssertEqual(summary.years[1].total, 500, accuracy: 1e-9)
        XCTAssertEqual(summary.years[1].claimable, 200, accuracy: 1e-9)
        XCTAssertEqual(summary.years.reduce(0) { $0 + $1.claimable }, summary.claimable, accuracy: 1e-9)
    }

    func testEmployerPaysEverythingMeansNothingToClaim() {
        let summary = WorkTax.businessTrips([item(date(2026, 3, 2), fare: 23.5, category: .business)], cap: 0)
        XCTAssertEqual(summary.claimable, 0)
        XCTAssertEqual(summary.capUsage, 1)
    }

    func testFirstClassFareIsConvertedToSecondClass() {
        XCTAssertEqual(WorkTax.secondClassFare(39.02, travelClass: .first, firstClassFactor: 1.951), 20, accuracy: 0.01)
        XCTAssertEqual(WorkTax.secondClassFare(20, travelClass: .second, firstClassFactor: 1.951), 20)
        XCTAssertEqual(WorkTax.secondClassFare(-3, travelClass: .second, firstClassFactor: 1.951), 0)
    }

    // MARK: Jobticket

    func testJobticketOwnShareAndPayoffViews() {
        let job = WorkTax.jobticket(price: 1400, addOnPrice: 0, employerContribution: 800, tripValue: 1044)
        XCTAssertTrue(job.hasContribution)
        XCTAssertEqual(job.ownShare, 600, accuracy: 1e-9)
        XCTAssertEqual(job.employerFraction, 800.0 / 1400, accuracy: 1e-9)
        XCTAssertEqual(job.amortizationOwnShare!, 1044.0 / 600, accuracy: 1e-9)
        XCTAssertEqual(job.amortizationFullPrice, 1044.0 / 1400, accuracy: 1e-9)
        XCTAssertEqual(job.pendlerpauschaleReduction, 800, accuracy: 1e-9)
    }

    func testJobticketClampsContribution() {
        let job = WorkTax.jobticket(price: 1400, addOnPrice: 90, employerContribution: 2000, tripValue: 100)
        XCTAssertEqual(job.employerContribution, 1490, accuracy: 1e-9)
        XCTAssertEqual(job.ownShare, 0, accuracy: 1e-9)
        XCTAssertNil(job.amortizationOwnShare)
        let none = WorkTax.jobticket(price: 1400, employerContribution: 0, tripValue: 100)
        XCTAssertFalse(none.hasContribution)
        XCTAssertEqual(none.pendlerpauschaleReduction, 0)
    }

    // MARK: Selbständige (WKO)

    func testFlatRateExcludesFamilySurchargeAndIncludesFirstClass() {
        let s = WorkTax.selfEmployed(ticketPrice: 1540, firstClassUpgrade: 0, familySurcharge: 140, trips: [])
        XCTAssertEqual(s.basis, 1400, accuracy: 1e-9)
        XCTAssertEqual(s.flatRateAmount, 700, accuracy: 1e-9)
        XCTAssertEqual(s.recommended, .flatRate)
        let first = WorkTax.selfEmployed(ticketPrice: 1400, firstClassUpgrade: 1490, trips: [])
        XCTAssertEqual(first.flatRateAmount, 1445, accuracy: 1e-9)
    }

    func testLogbookOnlyAboveFiftyPercent() {
        let business = item(date(2026, 3, 2), fare: 23.5, km: 100, category: .business)   // 200 km
        let commute = item(date(2026, 3, 3), fare: 6.7, km: 28, category: .commute)       // 56 km
        let leisure = item(date(2026, 3, 7), fare: 8.6, km: 41, category: .leisure)       // 82 km
        let s = WorkTax.selfEmployed(ticketPrice: 1400, trips: [business, commute, leisure])
        XCTAssertEqual(s.businessKm, 256, accuracy: 1e-9)
        XCTAssertEqual(s.privateKm, 82, accuracy: 1e-9)
        XCTAssertTrue(s.logbookApplies)
        XCTAssertEqual(s.logbookAmount, 1400 * 256 / 338, accuracy: 1e-9)
        XCTAssertEqual(s.recommended, .logbook)
        XCTAssertGreaterThan(s.logbookAdvantage, 0)

        // Without the way to the business premises the share drops below 50 % → only the lump sum.
        let noCommute = WorkTax.selfEmployed(ticketPrice: 1400, trips: [business, commute, leisure], countsCommute: false)
        XCTAssertEqual(noCommute.businessKm, 200, accuracy: 1e-9)
        XCTAssertTrue(noCommute.logbookApplies)           // 200 / 338 = 59 %
        let mostlyPrivate = WorkTax.selfEmployed(ticketPrice: 1400, trips: [commute, leisure, leisure], countsCommute: true)
        XCTAssertFalse(mostlyPrivate.logbookApplies)       // 56 / 220 = 25 %
        XCTAssertEqual(mostlyPrivate.recommended, .flatRate)
        XCTAssertEqual(mostlyPrivate.logbookAdvantage, 0)
    }

    func testEmployeesCountOnlyDienstreisen() {
        XCTAssertTrue(WorkTax.isBusinessUse(.business, role: .employee))
        XCTAssertFalse(WorkTax.isBusinessUse(.commute, role: .employee))
        XCTAssertTrue(WorkTax.isBusinessUse(.commute, role: .selfEmployed))
        XCTAssertFalse(WorkTax.isBusinessUse(.commute, role: .selfEmployed, countsCommute: false))
        XCTAssertFalse(WorkTax.isBusinessUse(nil, role: .selfEmployed))
    }

    func testFamilySurchargeFromCatalog() {
        let products = [
            TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1400,
                          validFrom: "2026-01-01", priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 1300)]),
            TicketProduct(id: "oe-jugend", family: .oe, name: "KlimaTicket Ö Jugend", variant: .jugend, priceEUR: 1050, validFrom: "2026-01-01"),
            TicketProduct(id: "oe-familie-klassik", family: .oe, name: "KlimaTicket Ö Klassik Familie", variant: .familie, priceEUR: 1540,
                          validFrom: "2026-01-01", priceHistory: [.init(validFrom: "2025-08-01", priceEUR: 1430)]),
            TicketProduct(id: "oe-familie-ermaessigt", family: .oe, name: "KlimaTicket Ö Familie ermäßigt", variant: .familie,
                          priceEUR: 1190, validFrom: "2026-01-01"),
        ]
        XCTAssertEqual(WorkTax.familySurcharge(productID: "oe-familie-klassik", start: date(2026, 3, 1), products: products), 140, accuracy: 1e-9)
        XCTAssertEqual(WorkTax.familySurcharge(productID: "oe-familie-klassik", start: date(2025, 9, 1), products: products), 130, accuracy: 1e-9)
        XCTAssertEqual(WorkTax.familySurcharge(productID: "oe-familie-ermaessigt", start: date(2026, 3, 1), products: products), 140, accuracy: 1e-9)
        XCTAssertEqual(WorkTax.familySurcharge(productID: "oe-klassik", start: date(2026, 3, 1), products: products), 0)
        XCTAssertEqual(WorkTax.familySurcharge(productID: "custom", start: date(2026, 3, 1), products: products), 0)
        XCTAssertEqual(WorkTax.baseProductID(forFamilyProductID: "ktn-senior-familie"), "ktn-senior")
    }

    // MARK: Export

    func testBusinessCSVHasTotalsAndAustrianDecimals() {
        let trips = [item(date(2026, 11, 2), fare: 23.5, category: .business), item(date(2027, 1, 12), fare: 23.5, category: .business)]
        let summary = WorkTax.businessTrips(trips, cap: 600)
        let csv = WorkTaxExport.businessTripsCSV(summary, holder: "Lena Hofer", ticketName: "KlimaTicket Ö Klassik")
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Datum;Von;Nach"))
        XCTAssertTrue(csv.contains("02.11.2026;St. Anton am Arlberg;Innsbruck Hauptbahnhof;Zug;ja;200,0;23,50;47,00;"))
        XCTAssertTrue(csv.contains("Summe Einzelfahrscheine (2 Dienstreisen);;;;;;;94,00"))
        XCTAssertTrue(csv.contains("Obergrenze: selbst bezahlter Ticketpreis;;;;;;;600,00"))
        XCTAssertTrue(csv.contains("davon Kalenderjahr 2027;;;;;;;47,00"))
        XCTAssertTrue(csv.contains("Keine Steuerberatung – Angaben ohne Gewähr, Stand 09.10.2026"))
        XCTAssertTrue(csv.contains("\r\n"))
    }

    func testLogbookCSVMarksPurpose() {
        let trips = [item(date(2026, 3, 2, 7), fare: 23.5, category: .business), item(date(2026, 3, 7, 11), fare: 8.6, km: 41, category: .leisure)]
        let summary = WorkTax.selfEmployed(ticketPrice: 1400, trips: trips)
        let csv = WorkTaxExport.logbookCSV(trips: trips, summary: summary, countsCommute: true, holder: "", ticketName: "KlimaTicket Ö Klassik")
        XCTAssertTrue(csv.contains("02.03.2026;07:00;St. Anton am Arlberg;Innsbruck Hauptbahnhof;Zug;ja;200,0;betrieblich;Dienstreise;47,00;"))
        XCTAssertTrue(csv.contains(";privat;Freizeit;17,20;"))
        XCTAssertTrue(csv.contains("Betrieblicher Anteil (%);;;;;;70,9"))
        XCTAssertTrue(csv.contains("50-%-Pauschale (€);;;;;;;;;700,00"))
    }
}
