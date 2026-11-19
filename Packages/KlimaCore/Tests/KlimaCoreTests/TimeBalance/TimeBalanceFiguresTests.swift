import XCTest
@testable import KlimaCore

/// How durations are shown, and figures on one card that must agree: parts that add up to the shown sum, the gap between
/// two shown figures.
final class TimeBalanceFiguresTests: XCTestCase {
    func testFigurePrecision() {
        XCTAssertEqual(TimeBalanceFigure(minutes: 44.6), TimeBalanceFigure(value: 45, decimals: 0, unit: .minutes))
        XCTAssertEqual(TimeBalanceFigure(minutes: 59.6), TimeBalanceFigure(value: 1, decimals: 0, unit: .hours))
        XCTAssertEqual(TimeBalanceFigure(minutes: 270), TimeBalanceFigure(value: 4.5, decimals: 1, unit: .hours))
        XCTAssertEqual(TimeBalanceFigure(minutes: 597), TimeBalanceFigure(value: 10, decimals: 0, unit: .hours))
        XCTAssertEqual(TimeBalanceFigure(minutes: 4_330), TimeBalanceFigure(value: 72, decimals: 0, unit: .hours))
        XCTAssertEqual(TimeBalanceFigure(minutes: -5).shownMinutes, 0)
        XCTAssertEqual(TimeBalanceFigure(minutes: .nan).shownMinutes, 0)
        XCTAssertEqual(TimeBalanceFigure(minutes: .infinity).shownMinutes, 0)
        XCTAssertEqual(TimeBalanceFigure(minutes: 270).shownMinutes, 270)
    }

    func testPartsAddUpToTheShownSum() {
        // The screenshot case: 25,6 + 46,4 = 72 Std. – each rounded on its own it read 26 + 46 under 72.
        XCTAssertEqual(TimeBalanceRounding.split([25.6 * 60, 46.4 * 60]), [26 * 60, 46 * 60])
        // A part under ten hours under a whole-hour sum takes whole hours too (8,4 + 63,6 = 72, not „8,4“ + „64“).
        XCTAssertEqual(TimeBalanceRounding.split([8.4 * 60, 63.6 * 60]), [8 * 60, 64 * 60])
        // Tenths under a tenths sum: 1,25 + 3,25 = 4,5 Std.
        let tenths = TimeBalanceRounding.split([75, 195])
        XCTAssertEqual(tenths.reduce(0, +), 270)
        XCTAssertEqual(tenths, [78, 192])
        // Minutes under a minute sum.
        XCTAssertEqual(TimeBalanceRounding.split([10.5, 20.4]), [11, 20])
        // A little time under a big sum gets no whole hour – the app says „< 1 Std.“.
        XCTAssertEqual(TimeBalanceRounding.split([20, 71 * 60]), [0, 71 * 60])
    }

    func testSplitSweepAlwaysMatchesTheShownSum() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5_000 {
            let a = Double.random(in: 0...6_000, using: &generator), b = Double.random(in: 0...6_000, using: &generator)
            let parts = TimeBalanceRounding.split([a, b])
            XCTAssertEqual(parts.reduce(0, +), TimeBalanceFigure(minutes: a + b).shownMinutes, accuracy: 1e-9, "\(a) + \(b)")
            for (part, value) in zip(parts, [a, b]) {
                XCTAssertGreaterThanOrEqual(part, 0)
                XCTAssertLessThanOrEqual(abs(part - value), TimeBalanceFigure.stepMinutes(ofShown: TimeBalanceFigure(minutes: a + b).shownMinutes) + 1)
            }
        }
    }

    func testSplitOfNothing() {
        XCTAssertEqual(TimeBalanceRounding.split([0, 0]), [0, 0])
        XCTAssertEqual(TimeBalanceRounding.split([]), [])
        XCTAssertEqual(TimeBalanceRounding.split([.nan, 30]), [0, 30])
    }

    func testGapIsTheDifferenceOfTheShownFigures() {
        // 72 Std. in Bahn & Bus, 79 Std. am Steuer: „7 Std.“, not „7,3 Std.“.
        XCTAssertEqual(TimeBalanceRounding.shownGap(71.9 * 60, 79.2 * 60), 7 * 60)
        // 9,6 Std. against 12 Std.: 2,4 Std.
        XCTAssertEqual(TimeBalanceRounding.shownGap(9.6 * 60, 12.04 * 60), 2.4 * 60, accuracy: 1e-9)
        // 45 Min. against 1,2 Std.: 27 Min.
        XCTAssertEqual(TimeBalanceRounding.shownGap(45, 72), 27)
        // Both show „10 Std.“: the unrounded gap.
        XCTAssertEqual(TimeBalanceRounding.shownGap(10.2 * 60, 10.4 * 60), 0.2 * 60, accuracy: 1e-9)
        // 9,8 Std. against „10 Std.“ (10,2): what is shown, 12 Minuten.
        XCTAssertEqual(TimeBalanceRounding.shownGap(10.2 * 60, 9.8 * 60), 12, accuracy: 1e-9)
        XCTAssertEqual(TimeBalanceRounding.shownGap(.nan, 30), 30)
    }
}
