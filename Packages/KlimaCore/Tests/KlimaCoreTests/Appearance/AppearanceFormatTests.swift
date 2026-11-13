import XCTest
@testable import KlimaCore

/// Zahlen (docs/THEMES.md §6): amounts, CO₂ unit and week start, with the example lines the screen shows.
final class AppearanceFormatTests: XCTestCase {
    private func euro(_ value: Double, _ amounts: FormatPrefs.Amounts) -> String {
        AppearanceFormat.euro(value, prefs: FormatPrefs(amounts: amounts)).plainSpaces
    }

    func testAmounts() {
        XCTAssertEqual(euro(1300, .automatic), "€ 1.300")
        XCTAssertEqual(euro(1300, .whole), "€ 1.300")
        XCTAssertEqual(euro(1300, .cents), "€ 1.300,00")
        XCTAssertEqual(euro(23.4, .automatic), "€ 23,40")
        XCTAssertEqual(euro(23.4, .cents), "€ 23,40")
        XCTAssertEqual(euro(23.4, .whole), "€ 23")
        XCTAssertEqual(euro(24, .automatic), "€ 24", "whole amounts never get ,00 automatically")
        XCTAssertEqual(euro(1234.56, .automatic), "€ 1.235", "from € 1.000 no cents automatically")
        XCTAssertEqual(euro(1234.56, .cents), "€ 1.234,56")
    }

    func testNegativeAmounts() {
        XCTAssertEqual(euro(-23.4, .automatic), "-€ 23,40")
        XCTAssertEqual(euro(-23.4, .whole), "-€ 23")
        XCTAssertEqual(euro(-1300, .automatic), "-€ 1.300")
        XCTAssertEqual(euro(-1300, .cents), "-€ 1.300,00")
        XCTAssertEqual(FormatPrefs(amounts: .automatic).euroFractionDigits(for: -1500.5), 0, "the threshold uses the absolute value")
    }

    func testFractionDigits() {
        let auto = FormatPrefs.standard
        XCTAssertEqual(auto.euroFractionDigits(for: 23.4), 2)
        XCTAssertEqual(auto.euroFractionDigits(for: 23), 0)
        XCTAssertEqual(auto.euroFractionDigits(for: 999.99), 2)
        XCTAssertEqual(auto.euroFractionDigits(for: 1000), 0)
        XCTAssertEqual(FormatPrefs(amounts: .whole).euroFractionDigits(for: 23.4), 0)
        XCTAssertEqual(FormatPrefs(amounts: .cents).euroFractionDigits(for: 1300), 2)
    }

    func testCO2() {
        let auto = FormatPrefs.standard, kg = FormatPrefs(co2: .kilograms)
        XCTAssertEqual(AppearanceFormat.co2(999.4, prefs: auto).plainSpaces, "999 kg")
        XCTAssertEqual(AppearanceFormat.co2(999.9, prefs: auto).plainSpaces, "1,0 t", "decided on the shown kilograms – never \"1.000 kg\"")
        XCTAssertEqual(AppearanceFormat.co2(1000, prefs: auto).plainSpaces, "1,0 t")
        XCTAssertEqual(AppearanceFormat.co2(1240, prefs: auto).plainSpaces, "1,2 t")
        XCTAssertEqual(AppearanceFormat.co2(999.9, prefs: kg).plainSpaces, "1.000 kg")
        XCTAssertEqual(AppearanceFormat.co2(1000, prefs: kg).plainSpaces, "1.000 kg")
        XCTAssertEqual(AppearanceFormat.co2(1240, prefs: kg).plainSpaces, "1.240 kg")
        XCTAssertEqual(AppearanceFormat.co2(0, prefs: auto).plainSpaces, "0 kg")
    }

    /// 25 October 2026 is a Sunday, 26 October a Monday (Vienna; the night of the switch back to winter time).
    func testWeekStart() {
        let cal = Calendar.vienna
        let sunday = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 8))!
        XCTAssertEqual(cal.component(.weekday, from: sunday), 1)
        XCTAssertEqual(cal.component(.weekday, from: monday), 2)

        let mon = FormatPrefs.WeekStart.monday, sun = FormatPrefs.WeekStart.sunday
        XCTAssertEqual(mon.columnIndex(of: sunday, in: cal), 6)
        XCTAssertEqual(mon.columnIndex(of: monday, in: cal), 0)
        XCTAssertEqual(sun.columnIndex(of: sunday, in: cal), 0)
        XCTAssertEqual(sun.columnIndex(of: monday, in: cal), 1)

        // The week that holds each day: Montag 19.–25.10. and 26.10.–1.11.; Sonntag 25.–31.10.
        XCTAssertEqual(cal.dateComponents([.month, .day], from: mon.startOfWeek(containing: sunday, in: cal)), DateComponents(month: 10, day: 19))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: mon.startOfWeek(containing: monday, in: cal)), DateComponents(month: 10, day: 26))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: sun.startOfWeek(containing: sunday, in: cal)), DateComponents(month: 10, day: 25))
        XCTAssertEqual(cal.dateComponents([.month, .day], from: sun.startOfWeek(containing: monday, in: cal)), DateComponents(month: 10, day: 25))

        // The calendar a screen uses agrees with the column index (`dateInterval(of: .weekOfYear)`).
        for start in FormatPrefs.WeekStart.allCases {
            let weekCal = start.calendar(from: cal)
            XCTAssertEqual(weekCal.timeZone, cal.timeZone)
            for day in [sunday, monday] {
                XCTAssertEqual(weekCal.dateInterval(of: .weekOfYear, for: day)?.start, start.startOfWeek(containing: day, in: cal), "\(start)")
            }
        }
        XCTAssertEqual(mon.mondayFirstOrder, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(sun.mondayFirstOrder, [6, 0, 1, 2, 3, 4, 5])
    }

    func testExampleLines() {
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.Amounts.automatic).plainSpaces, "€ 1.300 · € 23,40")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.Amounts.whole).plainSpaces, "€ 23,40 → € 23")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.Amounts.cents).plainSpaces, "€ 1.300 → € 1.300,00")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.WeekStart.monday), "Mo Di Mi Do Fr Sa So")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.WeekStart.sunday), "So Mo Di Mi Do Fr Sa")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.CO2Unit.automatic).plainSpaces, "980 kg · 1,2 t")
        XCTAssertEqual(AppearanceFormat.example(FormatPrefs.CO2Unit.kilograms).plainSpaces, "1,2 t → 1.240 kg")
    }
}
