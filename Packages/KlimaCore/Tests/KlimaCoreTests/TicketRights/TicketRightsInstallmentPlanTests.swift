import XCTest
@testable import KlimaCore

final class TicketRightsInstallmentPlanTests: XCTestCase {
    private let start = TR.date(2026, 3, 1, 0)

    private func plan(price: Double = 1400, start: Date? = nil, now: Date) -> InstallmentPlan {
        InstallmentPlan.make(price: price, start: start ?? self.start, now: now)!
    }

    func testTwelveInstallmentsThatAddUpToThePriceExactly() {
        for price in [1400.0, 1050, 1540, 1190, 1300, 999.99, 467, 1234.56] {
            let p = plan(price: price, now: TR.date(2026, 10, 9))
            XCTAssertEqual(p.items.count, 12, "\(price)")
            XCTAssertEqual(p.items.map(\.amountCents).reduce(0, +), Int((price * 100).rounded()), "sum for \(price)")
            XCTAssertEqual(p.items.map(\.number), Array(1...12))
            XCTAssertEqual(p.paidCents + p.openCents, p.priceCents, "paid + open = price for \(price)")
            XCTAssertEqual(p.paidAmount + p.openAmount, price, accuracy: 0.0001)
        }
    }

    func testAKlassikInstallmentIs116Euro67AndTheLastTakesTheRounding() {
        let p = plan(now: TR.date(2026, 10, 9))
        XCTAssertEqual(p.items[0].amountCents, 11667)
        XCTAssertEqual(p.items[10].amountCents, 11667)
        XCTAssertEqual(p.items[11].amountCents, 140_000 - 11 * 11667)
        XCTAssertEqual(p.typicalAmount, 116.67, accuracy: 0.0001)
        XCTAssertTrue(p.lastDiffers)
        XCTAssertFalse(plan(price: 1050, now: TR.date(2026, 10, 9)).lastDiffers, "1.050 / 12 = 87,50 exactly")
    }

    func testTheFirstTwoInstallmentsComeWithTheOrderInMonthOne() {
        let p = plan(now: TR.date(2026, 3, 1))
        XCTAssertEqual(p.items[0].timing, .withOrder)
        XCTAssertEqual(p.items[1].timing, .withOrder)
        XCTAssertEqual(p.items[0].month, TR.date(2026, 3, 1, 0))
        XCTAssertEqual(p.items[1].month, TR.date(2026, 3, 1, 0), "both in month one")
        XCTAssertEqual(p.items[0].state, .paid)
        XCTAssertEqual(p.items[1].state, .paid)
        XCTAssertNil(p.items[0].windowEnd)
        for item in p.items.dropFirst(2) { XCTAssertEqual(item.timing, .aroundMonthStart) }
        XCTAssertEqual(p.items.filter { $0.timing == .withOrder }.count, InstallmentPlan.upfrontCount)
        XCTAssertEqual(p.items.count, InstallmentPlan.count)
    }

    func testTheTwoOrderInstallmentsAreAlreadyPaidBeforeTheTicketStarts() {
        let p = plan(now: TR.date(2026, 2, 10))
        XCTAssertEqual(p.paidCount, 2)
        XCTAssertEqual(p.paidCents, 2 * 11667)
        XCTAssertEqual(p.next?.number, 3)
    }

    func testDebitsFollowTheMonthStartsOfTheValidityMonths() {
        let p = plan(now: TR.date(2026, 10, 9))
        // Validity month n begins on the 1st of March + (n-1) months.
        XCTAssertEqual(p.items[2].month, TR.date(2026, 5, 1, 0))
        XCTAssertEqual(p.items[7].month, TR.date(2026, 10, 1, 0))
        XCTAssertEqual(p.items[11].month, TR.date(2027, 2, 1, 0))
    }

    func testPaidSoFarCountsADebitOnceItsFiveWorkingDaysAreOver() {
        // 1 May 2026 is a Friday: working days 1, 4, 5, 6, 7 May -> the window ends at the start of 8 May.
        let may = plan(now: TR.date(2026, 5, 7, 23))
        XCTAssertEqual(may.items[2].windowEnd, TR.date(2026, 5, 8, 0))
        XCTAssertEqual(may.items[2].state, .booking)
        XCTAssertEqual(may.paidCount, 2)
        XCTAssertEqual(plan(now: TR.date(2026, 5, 8, 0)).items[2].state, .paid)
        XCTAssertEqual(plan(now: TR.date(2026, 5, 8, 0)).paidCount, 3)
        XCTAssertEqual(plan(now: TR.date(2026, 4, 20)).items[2].state, .upcoming)
    }

    func testTheNextInstallmentAndOpenAmount() {
        let p = plan(now: TR.date(2026, 10, 9))
        // March (1, 2 with the order), then May … October are over by 9 October: validity months 3…8 -> 8 installments.
        XCTAssertEqual(p.paidCount, 8)
        XCTAssertEqual(p.next?.number, 9)
        XCTAssertEqual(p.next?.month, TR.date(2026, 11, 1, 0))
        XCTAssertEqual(p.paidCents, 8 * 11667)
        XCTAssertEqual(p.openCount, 4)
        XCTAssertEqual(p.openCents, 140_000 - 8 * 11667)
        XCTAssertFalse(p.isComplete)
    }

    func testAllPaidAfterTheLastWindow() {
        let p = plan(now: TR.date(2027, 2, 20))
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.paidCents, 140_000)
        XCTAssertEqual(p.openCents, 0)
        XCTAssertNil(p.next)
    }

    func testThePaidAmountOfThe12thInstallmentCompletesThePrice() {
        let before = plan(now: TR.date(2027, 2, 2)) // window of February still open
        XCTAssertEqual(before.paidCount, 11)
        XCTAssertEqual(before.openCents, before.items[11].amountCents)
    }

    func testAValidityStartLateInTheMonthStillBooksAtTheMonthStart() {
        // Validity from 20 January: validity month 3 begins on 20 March, its debit lies in the first five working days of March.
        let p = plan(start: TR.date(2026, 1, 20, 0), now: TR.date(2026, 3, 10))
        XCTAssertEqual(p.items[2].month, TR.date(2026, 3, 1, 0))
        XCTAssertEqual(p.items[2].state, .paid)
        XCTAssertEqual(p.items[3].month, TR.date(2026, 4, 1, 0))
    }

    func testEndOfMonthStartsDoNotDrift() {
        // 31 January: month 2 begins on 28 February (clamped), month 3 on 31 March.
        let p = plan(start: TR.date(2026, 1, 31, 0), now: TR.date(2026, 1, 31))
        XCTAssertEqual(p.items[1].month, TR.date(2026, 1, 1, 0), "paid with the order, month of the start")
        XCTAssertEqual(p.items[2].month, TR.date(2026, 3, 1, 0))
        XCTAssertEqual(p.items[3].month, TR.date(2026, 4, 1, 0))
    }

    func testNoPlanWithoutAPrice() {
        XCTAssertNil(InstallmentPlan.make(price: 0, start: start))
        XCTAssertNil(InstallmentPlan.make(price: -5, start: start))
        XCTAssertNil(InstallmentPlan.make(price: .nan, start: start), "a broken price must not crash")
        XCTAssertNil(InstallmentPlan.make(price: .infinity, start: start))
    }

    func testWorkingDaysSkipWeekends() {
        // 1 August 2026 is a Saturday: working days 3, 4, 5, 6, 7 August -> ends at the start of 8 August.
        let end = InstallmentPlan.windowEnd(inMonthOf: TR.date(2026, 8, 1, 0), calendar: TR.cal)
        XCTAssertEqual(end, TR.date(2026, 8, 8, 0))
    }

    func testBalanceComparesCashWithValue() {
        let p = plan(now: TR.date(2026, 10, 9))
        let behind = p.balance(tripValue: 500)
        XCTAssertFalse(behind.coversPayments)
        XCTAssertEqual(behind.difference, p.paidAmount - 500, accuracy: 0.0001)
        XCTAssertTrue(p.balance(tripValue: 1050).coversPayments)
        XCTAssertTrue(p.balance(tripValue: p.paidAmount).coversPayments)
        XCTAssertEqual(p.balance(tripValue: -3).value, 0)
        // „genau“ only to the cent: 7 cent more is more, not exact.
        XCTAssertTrue(p.balance(tripValue: p.paidAmount).isExact)
        XCTAssertFalse(p.balance(tripValue: p.paidAmount + 0.07).isExact)
        XCTAssertTrue(p.balance(tripValue: p.paidAmount + 0.07).coversPayments)
    }
}
