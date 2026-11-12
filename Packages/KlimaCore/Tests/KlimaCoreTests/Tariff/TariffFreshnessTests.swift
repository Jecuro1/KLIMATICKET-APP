import Foundation
import XCTest
@testable import KlimaCore

/// The timetable-change dates and the freshness states around 13 December and 1 January (Vienna time, injected clock).
final class TariffFreshnessTests: XCTestCase {
    private typealias F = TariffFixtures

    // MARK: Timetable change

    func testTimetableChangeIsTheSecondSundayOfDecember() {
        let expected = [2025: "2025-12-14", 2026: "2026-12-13", 2027: "2027-12-12", 2028: "2028-12-10",
                        2029: "2029-12-09", 2030: "2030-12-08"]
        for (year, day) in expected {
            XCTAssertEqual(TimetableChange.isoDay(year: year), day, "\(year)")
        }
    }

    func testTimetableChangeIsASundayInEveryYear() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Europe/Vienna")!
        for year in 1990...2100 {
            let day = TimetableChange.date(year: year, calendar: gregorian)
            XCTAssertEqual(gregorian.component(.weekday, from: day), 1, "Sunday in \(year)")   // 1 = Sunday
            let dom = gregorian.component(.day, from: day)
            XCTAssertTrue((8...14).contains(dom), "second Sunday: day \(dom) in \(year)")
            XCTAssertEqual(gregorian.component(.month, from: day), 12)
        }
    }

    // MARK: Around 13 December (the bundled catalogue, last checked 9 October 2026)

    func testNoNoticeInNovember() throws {
        let catalog = try F.bundledCatalog()
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 11, 12), lastCheck: nil), .current)
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 11, 30, 23, 59)), .current)
    }

    func testNoticeStartsOnTheFirstOfDecemberInVienna() throws {
        let catalog = try F.bundledCatalog()
        let change = F.vienna(2026, 12, 13, 0, 0)
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 12, 1, 0, 0)), .upcomingChange(change))
        // 30 November 23:30 UTC is already 1 December 00:30 in Vienna (UTC+1).
        let utc = ISO8601DateFormatter().date(from: "2026-11-30T23:30:00Z")!
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: utc), .upcomingChange(change))
        // 30 November 22:30 UTC is 23:30 in Vienna: still November.
        let earlier = ISO8601DateFormatter().date(from: "2026-11-30T22:30:00Z")!
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: earlier), .current)
    }

    /// Acceptance: on 2026-12-14 with no newer catalogue the Ticket tab shows banner (a).
    func testNoticeStaysAfterTheChangeUntilTheDataIsUpdated() throws {
        let catalog = try F.bundledCatalog()
        let change = F.vienna(2026, 12, 13, 0, 0)
        for now in [F.vienna(2026, 12, 12), F.vienna(2026, 12, 13), F.vienna(2026, 12, 14), F.vienna(2026, 12, 31, 23, 59)] {
            XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: now), .upcomingChange(change), "\(now)")
        }
    }

    func testANewerCatalogueEndsTheNotice() {
        // Data checked after 1 December: no notice.
        let updated = F.catalog(updatedAt: "2026-12-05")
        XCTAssertEqual(TariffFreshness.state(catalog: updated, now: F.vienna(2026, 12, 14)), .current)
        // Checked on 30 November: still the notice.
        let before = F.catalog(updatedAt: "2026-11-30")
        XCTAssertEqual(TariffFreshness.state(catalog: before, now: F.vienna(2026, 12, 14)), .upcomingChange(F.vienna(2026, 12, 13, 0, 0)))
    }

    func testARelationPackForTheChangeEndsTheNotice() {
        let pack = RelationsPackInfo(url: "relations-pack.bin", sha256: "x", version: 2, validFrom: "2026-12-13", bytes: 1)
        XCTAssertEqual(TariffFreshness.state(catalog: F.catalog(pack: pack), now: F.vienna(2026, 12, 14)), .current)
        let older = RelationsPackInfo(url: "relations-pack.bin", sha256: "x", version: 1, validFrom: "2025-12-14", bytes: 1)
        XCTAssertEqual(TariffFreshness.state(catalog: F.catalog(pack: older), now: F.vienna(2026, 12, 14)),
                       .upcomingChange(F.vienna(2026, 12, 13, 0, 0)))
    }

    func testTheNoticeNamesTheChangeOfThatYear() throws {
        // 2027: Oe prices of 2027 are in the catalogue, the catalogue is from October 2027.
        let catalog = F.catalog(updatedAt: "2027-10-01", oeFrom: "2027-01-01", history: ["2026-01-01"], fareIndex: [("2027-12-12", 1.03)])
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 12, 3)), .upcomingChange(F.vienna(2027, 12, 12, 0, 0)))
    }

    // MARK: Around 1 January

    func testNewYearWithoutAPriceEntryForTheNewYear() throws {
        let catalog = try F.bundledCatalog()
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 12, 31, 23, 59)),
                       .upcomingChange(F.vienna(2026, 12, 13, 0, 0)))
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 1, 1, 0, 0)), .newYear)
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 3, 15)), .newYear)
        // 31 December 23:30 UTC is 1 January 00:30 in Vienna.
        let utc = ISO8601DateFormatter().date(from: "2026-12-31T23:30:00Z")!
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: utc), .newYear)
    }

    func testAnEntryForTheNewYearEndsIt() {
        // Prices valid from 1 January 2027 are in the catalogue (the 2026 price moved into the history).
        let catalog = F.catalog(updatedAt: "2026-12-20", oeFrom: "2027-01-01", history: ["2026-01-01", "2025-08-01"])
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 1, 5)), .current)
        // Also before the day itself: an announced entry for 2027 means the catalogue knows the new prices.
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 12, 20)), .current)
    }

    func testNewYearLooksAtKlimaTicketOeOnly() {
        // A regional product with an entry in 2027 does not count: the national ticket sets the year.
        var catalog = F.catalog()
        catalog.products.append(TicketProduct(id: "k-klassik", family: .regional, states: ["K"], name: "Kärnten", variant: .klassik,
                                              priceEUR: 400, validFrom: "2027-01-01"))
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 2, 1)), .newYear)
    }

    func testNewYearTakesPrecedenceOverTheDecemberNoticeOfALaterYear() throws {
        // December 2027 with 2026 data: "the prices are from 2026" says more than "the timetable change is coming".
        let catalog = try F.bundledCatalog()
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2027, 12, 14)), .newYear)
    }

    // MARK: Stale

    func testStaleWhenTheNewestFareIndexIsOlderThanThirteenMonths() {
        // Oe prices for 2026 exist, so only the fare index (1 February 2025) can make this stale.
        let catalog = F.catalog(fareIndex: [("2024-12-15", 1.02), ("2025-02-01", 1.01)])
        let since = F.vienna(2025, 2, 1, 0, 0)
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 3, 2)), .stale(since: since))
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 3, 1)), .current, "13 months to the day is not over")
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 2, 1)), .current)
    }

    func testStaleFallsBackToTheCatalogueDateWithoutAFareIndex() {
        let catalog = F.catalog(updatedAt: "2025-05-10", fareIndex: nil)
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 6, 11)), .stale(since: F.vienna(2025, 5, 10, 0, 0)))
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 6, 9)), .current)
    }

    func testTheBundledCatalogueIsNotStaleBeforeJanuary2028() throws {
        // Its newest fare-index entry is 2026-12-13; every earlier notice (newYear) comes first from 1 January 2027.
        let catalog = try F.bundledCatalog()
        XCTAssertEqual(TariffFreshness.state(catalog: catalog, now: F.vienna(2026, 10, 1)), .current)
        let reference = try XCTUnwrap(TariffFreshness.staleReference(catalog))
        XCTAssertEqual(reference, "2026-12-13")
    }

    func testTheLastCheckDoesNotChangeTheState() throws {
        let catalog = try F.bundledCatalog()
        let now = F.vienna(2026, 12, 14)
        let states = [nil, F.vienna(2026, 12, 14), F.vienna(2020, 1, 1)].map { TariffFreshness.state(catalog: catalog, now: now, lastCheck: $0) }
        XCTAssertEqual(Set(states).count, 1)
    }

    // MARK: Texts of the row

    func testGermanDatesHaveNoLeadingZeros() {
        XCTAssertEqual(TariffFreshness.germanDate(iso: "2026-01-01"), "1.1.2026")
        XCTAssertEqual(TariffFreshness.germanDate(iso: "2025-12-14"), "14.12.2025")
        XCTAssertEqual(TariffFreshness.germanDate(F.vienna(2026, 11, 12)), "12.11.2026")
        XCTAssertEqual(TariffFreshness.germanDate(iso: "kaputt"), "kaputt")
        XCTAssertEqual(TariffFreshness.germanDayMonth(TimetableChange.date(year: 2026)), "13.12.")
        XCTAssertEqual(TariffFreshness.germanDayMonth(F.vienna(2027, 1, 5)), "5.1.")
    }

    func testSummaryLineReadsTheDatesFromTheCatalogueAndTheCache() throws {
        let catalog = try F.bundledCatalog()
        let now = F.vienna(2026, 11, 12)
        let asOf = TariffFreshness.ticketPricesAsOf(catalog: catalog, now: now)
        XCTAssertEqual(asOf, "2026-01-01")
        XCTAssertEqual(TariffFreshness.summaryLine(fareValidFrom: "2025-12-14", ticketPricesAsOf: asOf, lastCheck: now),
                       "Fahrpreise gültig ab 14.12.2025 · Ticketpreise Stand 1.1.2026 · zuletzt geprüft 12.11.2026")
        XCTAssertEqual(TariffFreshness.summaryLine(fareValidFrom: "2025-12-14", ticketPricesAsOf: asOf, lastCheck: nil),
                       "Fahrpreise gültig ab 14.12.2025 · Ticketpreise Stand 1.1.2026 · noch nicht geprüft")
        XCTAssertEqual(TariffFreshness.summaryLine(fareValidFrom: nil, ticketPricesAsOf: nil, lastCheck: nil), "noch nicht geprüft")
    }

    func testTicketPricesAsOfIgnoresFutureEntries() {
        let catalog = F.catalog(oeFrom: "2027-01-01", history: ["2026-01-01"])
        XCTAssertEqual(TariffFreshness.ticketPricesAsOf(catalog: catalog, now: F.vienna(2026, 12, 20)), "2026-01-01")
        XCTAssertEqual(TariffFreshness.ticketPricesAsOf(catalog: catalog, now: F.vienna(2027, 1, 1, 0, 0)), "2027-01-01")
    }
}
