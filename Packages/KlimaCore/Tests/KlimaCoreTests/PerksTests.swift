import XCTest
@testable import KlimaCore

final class PerksTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    let catalog = PerkCatalog(version: 1, asOf: "2026-10-09", source: "https://www.klimaticket.at/eins-fuer-mehr/", partners: [
        PerkPartner(id: "cat", name: "City Airport Train (CAT)", category: .mobility, benefit: "−50 % auf das CAT-Ticket",
                    typicalSavingEUR: 7, region: "W", url: "https://www.cityairporttrain.com/de/home", featured: true),
        PerkPartner(id: "technisches-museum", name: "Technisches Museum Wien", category: .museums, benefit: "−20 % auf den Eintritt",
                    typicalSavingEUR: 3.4, region: "W", url: "https://www.technischesmuseum.at/"),
        PerkPartner(id: "rail-drive", name: "Rail & Drive (ÖBB)", category: .mobility, benefit: "€ 19,90 Fahrtguthaben",
                    typicalSavingEUR: 19.9, region: "AT", url: "https://www.railanddrive.at/de"),
        PerkPartner(id: "sommer-bergbahnen", name: "Beste Österreichische Sommer-Bergbahnen", category: .leisure,
                    benefit: "−10 % an den Kassen", typicalSavingEUR: 3, region: "AT", url: "https://www.sommer-bergbahnen.at/",
                    featured: true),
        PerkPartner(id: "kino", name: "Nonstop-Kino", category: .leisure, benefit: "1. Monat gratis", typicalSavingEUR: 12,
                    region: "W,ST,OÖ,S,T,K,NÖ", url: "https://nonstopkino.at/"),
    ])

    // MARK: Catalogue

    func testDecodeAppliesDefaults() throws {
        let json = """
        {"version": 2, "asOf": "2026-10-09", "source": "https://www.klimaticket.at/eins-fuer-mehr/",
         "partners": [{"id": "x", "name": "X", "category": "museums", "benefit": "−20 %"}]}
        """
        let decoded = try PerkCatalog.decode(Data(json.utf8))
        XCTAssertEqual(decoded.version, 2)
        let partner = try XCTUnwrap(decoded.partner(id: "x"))
        XCTAssertEqual(partner.region, "AT")
        XCTAssertTrue(partner.isNationwide)
        XCTAssertFalse(partner.featured)
        XCTAssertEqual(partner.typicalSavingEUR, 0)
        XCTAssertEqual(partner.symbolName, PerkCategory.museums.symbolName)
    }

    func testDecodeRejectsUnknownCategory() {
        let json = """
        {"version": 1, "asOf": "", "source": "", "partners": [{"id": "x", "name": "X", "category": "casino", "benefit": "?"}]}
        """
        XCTAssertThrowsError(try PerkCatalog.decode(Data(json.utf8)))
    }

    /// The bundled catalogue must stay valid: unique ids, known categories, plausible savings, absolute URLs.
    func testBundledCatalogueIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/benefits.json")
        let bundled = try PerkCatalog.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(bundled.partners.count, 30)
        XCTAssertEqual(Set(bundled.partners.map(\.id)).count, bundled.partners.count, "duplicate partner ids")
        XCTAssertNil(bundled.partner(id: PerkCatalog.customID), "'custom' is reserved")
        XCTAssertTrue(bundled.source.hasPrefix("https://www.klimaticket.at/"))
        XCTAssertFalse(bundled.featured.isEmpty)
        let states = Set(FederalState.allCases.map(\.rawValue)).union(["AT"])
        for partner in bundled.partners {
            XCTAssertNotEqual(partner.category, .custom, partner.id)
            XCTAssertGreaterThan(partner.typicalSavingEUR, 0, partner.id)
            XCTAssertLessThan(partner.typicalSavingEUR, 500, partner.id)
            XCTAssertTrue(partner.url.hasPrefix("http"), partner.id)
            XCTAssertNotNil(URL(string: partner.url), partner.id)
            XCTAssertFalse(partner.benefit.isEmpty, partner.id)
            for code in partner.regionCodes { XCTAssertTrue(states.contains(code), "\(partner.id): \(code)") }
        }
        for category in PerkCategory.catalogCases {
            XCTAssertFalse(bundled.search("", category: category).isEmpty, "no partner in \(category)")
        }
    }

    func testRegionNames() {
        XCTAssertEqual(catalog.partner(id: "cat")?.regionName, "Wien")
        XCTAssertEqual(catalog.partner(id: "rail-drive")?.regionName, "Ganz Österreich")
        XCTAssertEqual(catalog.partner(id: "kino")?.regionName, "7 Bundesländer")
        XCTAssertTrue(catalog.partner(id: "kino")?.regionLongName.contains("Kärnten") ?? false)
        let multi = PerkPartner(id: "m", name: "M", category: .foodStay, benefit: "1 + 1", typicalSavingEUR: 1, region: "W, OÖ,S", url: "")
        XCTAssertEqual(multi.regionName, "Wien · Oberösterreich · Salzburg")
    }

    func testSearchIsCaseDiacriticAndUmlautTolerant() {
        XCTAssertEqual(catalog.search("museum").map(\.id), ["technisches-museum"])
        XCTAssertEqual(catalog.search("OEBB").map(\.id), ["rail-drive"])
        XCTAssertEqual(catalog.search("öbb").map(\.id), ["rail-drive"])
        XCTAssertEqual(catalog.search("osterreichische").map(\.id), ["sommer-bergbahnen"])
        XCTAssertEqual(catalog.search("oesterreichische").map(\.id), ["sommer-bergbahnen"])
        // All words must match, in any field (name + region).
        XCTAssertEqual(catalog.search("cat wien").map(\.id), ["cat"])
        XCTAssertTrue(catalog.search("cat graz").isEmpty)
        // Region search uses the long state names.
        XCTAssertEqual(catalog.search("kärnten").map(\.id), ["kino"])
        // "-50" matches the typographic minus in "−50 %".
        XCTAssertEqual(catalog.search("-50").map(\.id), ["cat"])
    }

    func testSearchWithCategoryAndEmptyQuery() {
        XCTAssertEqual(catalog.search("", category: .leisure).map(\.id), ["sommer-bergbahnen", "kino"])
        XCTAssertEqual(catalog.search("   ").count, catalog.partners.count)
        XCTAssertTrue(catalog.search("museum", category: .mobility).isEmpty)
        XCTAssertEqual(catalog.featured.map(\.id), ["cat", "sommer-bergbahnen"])
    }

    // MARK: Totals

    func testSummaryCountsOnlyThePeriodAndGroupsByCategoryAndMonth() {
        let start = date(2026, 3, 1, 0)
        let end = TicketPeriod.standardEnd(for: start, calendar: cal)
        let usages = [
            PerkUsage(date: date(2026, 2, 28), partnerID: "cat", savedEUR: 7),           // before the ticket year
            PerkUsage(date: date(2026, 3, 1, 9), partnerID: "cat", savedEUR: 7.45),
            PerkUsage(date: date(2026, 3, 20), partnerID: "technisches-museum", savedEUR: 3.4),
            PerkUsage(date: date(2026, 7, 4), partnerID: "sommer-bergbahnen", savedEUR: 3),
            PerkUsage(date: date(2026, 7, 5), partnerID: "cat", savedEUR: 7),
            PerkUsage(date: date(2026, 8, 1), partnerID: PerkCatalog.customID, savedEUR: 12.5),
            PerkUsage(date: date(2026, 9, 1), partnerID: "gone-partner", savedEUR: 1),     // unknown id → custom
            PerkUsage(date: date(2026, 9, 2), partnerID: "cat", savedEUR: -5),              // ignored amount, still counted
            PerkUsage(date: date(2027, 3, 1, 9), partnerID: "cat", savedEUR: 7),            // after the ticket year
        ]
        let summary = PerkSummary.make(usages: usages, from: start, to: end, catalog: catalog, calendar: cal)
        XCTAssertEqual(summary.count, 7)
        XCTAssertEqual(summary.total, 34.35, accuracy: 0.001)
        XCTAssertEqual(summary.byCategory.map(\.category), [.mobility, .custom, .museums, .leisure])
        XCTAssertEqual(summary.byCategory.first?.total ?? 0, 14.45, accuracy: 0.001)
        XCTAssertEqual(summary.byCategory.first?.count, 3)
        XCTAssertEqual(summary.byCategory.first { $0.category == .custom }?.total ?? 0, 13.5, accuracy: 0.001)
        XCTAssertEqual(summary.byMonth.count, 4)
        XCTAssertEqual(summary.byMonth.first?.month, date(2026, 3, 1, 0))
        XCTAssertEqual(summary.byMonth.first?.total ?? 0, 10.85, accuracy: 0.001)
        XCTAssertEqual(summary.topPartnerID, "cat")
        XCTAssertFalse(summary.isEmpty)
    }

    func testEmptySummary() {
        let summary = PerkSummary.make(usages: [], from: date(2026, 1, 1), to: date(2026, 12, 31), catalog: catalog)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.total, 0)
        XCTAssertNil(summary.topPartnerID)
        XCTAssertTrue(summary.byCategory.isEmpty)
    }

    // MARK: Passenger rights

    func testSchemeByFamily() {
        XCTAssertEqual(PerkRightsScheme.forFamily(.oe), .klimaTicketOe)
        XCTAssertEqual(PerkRightsScheme.forFamily(.regional), .regional)
        XCTAssertEqual(PerkRightsScheme.forFamily(.custom), .unknown)
        XCTAssertEqual(PerkRightsScheme.klimaTicketOe.threshold, 0.93)
        XCTAssertEqual(PerkRightsScheme.regional.threshold, 0.95)
    }

    func testOePublishedValueAtReferencePrice() {
        let e = PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 1_179.30, badMonths: 2)
        XCTAssertEqual(e.monthlyLow, 4.35)
        XCTAssertEqual(e.monthlyHigh, 4.35)
        XCTAssertFalse(e.isRange)
        XCTAssertEqual(e.expectedLow, 8.70, accuracy: 0.001)
        XCTAssertEqual(e.yearlyMaxHigh, 52.20, accuracy: 0.001)
        XCTAssertFalse(e.mayFallBelowMinimum)
    }

    func testOeRangeScalesWithTicketPrice() {
        let e = PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 1_400, badMonths: 3)
        XCTAssertEqual(e.monthlyLow, 4.35)
        XCTAssertEqual(e.monthlyHigh, 5.16, accuracy: 0.001)   // 4,35 × 1.400 / 1.179,30
        XCTAssertTrue(e.isRange)
        XCTAssertEqual(e.expectedLow, 13.05, accuracy: 0.001)
        XCTAssertEqual(e.expectedHigh, 15.48, accuracy: 0.001)
        XCTAssertEqual(e.yearlyMaxLow, 52.20, accuracy: 0.001)
        XCTAssertEqual(e.yearlyMaxHigh, 61.92, accuracy: 0.001)
        // The yearly cap equals 10 % of the implied compensation basis.
        XCTAssertEqual(e.yearlyMaxHigh, 0.1 * (e.monthlyHigh * 12 / 0.1), accuracy: 0.01)
    }

    func testReducedTicketCanFallBelowMinimumPayout() {
        let e = PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 884.20, badMonths: 1)
        XCTAssertEqual(e.monthlyLow, 3.26, accuracy: 0.001)
        XCTAssertEqual(e.monthlyHigh, 4.35)
        XCTAssertTrue(e.mayFallBelowMinimum)
        let two = PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 884.20, badMonths: 2)
        XCTAssertFalse(two.mayFallBelowMinimum)
    }

    func testFirstClassUpgradeAddsItsOwnBasis() {
        let e = PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 1_179.30, badMonths: 1,
                                             firstClassUpgradePrice: 1_490)
        XCTAssertEqual(e.upgradeMonthly, 12.42, accuracy: 0.001)
        XCTAssertEqual(e.expectedLow, 16.77, accuracy: 0.001)
        let regional = PerkPassengerRights.estimate(scheme: .regional, ticketPrice: 500, firstClassUpgradePrice: 1_490)
        XCTAssertEqual(regional.upgradeMonthly, 0)
    }

    func testRegionalAndUnknownSchemes() {
        let regional = PerkPassengerRights.estimate(scheme: .regional, ticketPrice: 600, badMonths: 4)
        XCTAssertEqual(regional.monthlyLow, 0)
        XCTAssertEqual(regional.monthlyHigh, 5)
        XCTAssertEqual(regional.expectedHigh, 20)
        XCTAssertEqual(regional.yearlyMaxHigh, 60)
        let unknown = PerkPassengerRights.estimate(scheme: .unknown, ticketPrice: 600, badMonths: 4)
        XCTAssertEqual(unknown.expectedHigh, 0)
        XCTAssertFalse(unknown.mayFallBelowMinimum)
        XCTAssertFalse(regional.mayFallBelowMinimum)
    }

    func testBadMonthsAreClamped() {
        XCTAssertEqual(PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 1_400, badMonths: 20).badMonths, 12)
        XCTAssertEqual(PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: 1_400, badMonths: -3).badMonths, 0)
        XCTAssertEqual(PerkPassengerRights.estimate(scheme: .klimaTicketOe, ticketPrice: .nan).monthlyLow, 4.35)
    }

    func testValidityMonthsFollowTheStartDay() {
        let start = date(2026, 1, 31, 0)
        let end = TicketPeriod.standardEnd(for: start, calendar: cal)
        let months = PerkPassengerRights.validityMonths(start: start, end: end, calendar: cal)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].start, date(2026, 1, 31, 0))
        // Calendar clamps the 31st to the end of February.
        XCTAssertEqual(months[1].start, date(2026, 2, 28, 0))
        XCTAssertEqual(months.last?.end, end)
        XCTAssertEqual(PerkPassengerRights.monthIndex(of: date(2026, 2, 10), in: months), 0)
        XCTAssertEqual(PerkPassengerRights.monthIndex(of: date(2026, 3, 5), in: months), 1)
        XCTAssertNil(PerkPassengerRights.monthIndex(of: date(2027, 2, 5), in: months))
        for (a, b) in zip(months, months.dropFirst()) {
            XCTAssertEqual(b.start.timeIntervalSince(a.end), 1, accuracy: 0.001)
        }
    }

    func testValidityMonthsOfShortOrInvalidPeriods() {
        let start = date(2026, 5, 10, 0)
        XCTAssertTrue(PerkPassengerRights.validityMonths(start: start, end: start, calendar: cal).isEmpty)
        let short = PerkPassengerRights.validityMonths(start: start, end: date(2026, 6, 20, 23), calendar: cal)
        XCTAssertEqual(short.count, 2)
        XCTAssertEqual(short.last?.end, date(2026, 6, 20, 23))
    }

    func testReminderAndPayoutDates() {
        let start = date(2026, 5, 19, 0)
        let end = TicketPeriod.standardEnd(for: start, calendar: cal)       // 18.5.2027 23:59:59
        XCTAssertEqual(PerkPassengerRights.payoutFrom(expiry: end, calendar: cal), date(2027, 5, 19, 0))
        XCTAssertEqual(PerkPassengerRights.reminderDate(expiry: end, calendar: cal), date(2027, 5, 21, 9))
    }
}
