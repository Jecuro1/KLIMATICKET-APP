import Foundation

/// Der Fahrplanwechsel: the ÖBB timetable year starts on the Sunday after the second Saturday of December (2025-12-14,
/// 2026-12-13, 2027-12-12, … and 2024-12-15, 2030-12-15 – the day lies between the 9th and the 15th, so it is the third
/// Sunday when 1 December is itself a Sunday), and the ÖBB Standard-Ticket prices (the "Relationspreise") change with it.
/// The app warns around this date, because the tables it knows were valid until then (docs/TARIFF_FRESHNESS.md).
///
/// Pure calendar arithmetic on the Gregorian calendar – independent of the device calendar and time zone.
public enum TimetableChange {
    /// Day of the month (9…15) of the Sunday after the second Saturday of December in `year`.
    public static func dayOfMonth(year: Int) -> Int {
        let firstOfDecember = weekday(year: year, month: 12, day: 1)   // 0 = Sunday … 6 = Saturday
        let firstSaturday = 1 + (6 - firstOfDecember + 7) % 7
        return firstSaturday + 7 + 1
    }

    /// "2026-12-13".
    public static func isoDay(year: Int) -> String {
        String(format: "%04d-12-%02d", year, dayOfMonth(year: year))
    }

    /// Start of the day of the change in `calendar` (Vienna by default).
    public static func date(year: Int, calendar: Calendar = .vienna) -> Date {
        calendar.date(from: DateComponents(year: year, month: 12, day: dayOfMonth(year: year))) ?? Date.distantFuture
    }

    /// First day of the notice window before the change: 1 December ("2026-12-01").
    public static func noticeStartISODay(year: Int) -> String {
        String(format: "%04d-12-01", year)
    }

    /// Day of the week for a Gregorian date, 0 = Sunday … 6 = Saturday (Sakamoto's method).
    static func weekday(year: Int, month: Int, day: Int) -> Int {
        let table = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = month < 3 ? year - 1 : year
        return (y + y / 4 - y / 100 + y / 400 + table[month - 1] + day) % 7
    }
}
