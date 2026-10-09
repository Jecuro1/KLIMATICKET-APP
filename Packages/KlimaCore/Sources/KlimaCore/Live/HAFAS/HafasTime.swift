import Foundation

/// HAFAS wall-clock times (SPEC §A3.4): dates are `yyyyMMdd`, times `[dd]HHMMSS` with an optional day offset
/// (`"01004100"` = base + 1 day, 00:41:00) and an optional explicit UTC offset in minutes (`dTZOffset`).
/// Without an offset the time is interpreted in Europe/Vienna. Request dates/times are always Vienna wall clock.
public enum HafasTime {
    static let vienna: Calendar = .vienna

    /// `base` "yyyyMMdd" + `time` "[dd]HHMMSS" (+ `tzOffsetMinutes`) → absolute date; nil when malformed.
    public static func date(base: String, time: String, tzOffsetMinutes: Int?) -> Date? {
        guard let ymd = civil(base), let t = clock(time) else { return nil }
        let days = daysFromCivil(ymd.y, ymd.m, ymd.d) + t.days
        // A UTC offset beyond ±24 h is corrupt input (it would overflow below): interpret the time in Vienna instead.
        if let offset = tzOffsetMinutes, (-maxOffsetMinutes...maxOffsetMinutes).contains(offset) {
            let seconds = days * 86_400 + t.h * 3600 + t.min * 60 + t.s - offset * 60
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        let c = civil(fromDays: days)
        var comps = DateComponents()
        comps.year = c.y
        comps.month = c.m
        comps.day = c.d
        comps.hour = t.h
        comps.minute = t.min
        comps.second = t.s
        return vienna.date(from: comps)
    }

    /// `[dd]HHMMSS` → seconds (`dur`, `durS`, `gis.durS`, `chg.durS`, `chgTime`); nil when absent or malformed.
    public static func duration(_ s: String?) -> Int? {
        guard let s, let t = clock(s) else { return nil }
        return t.days * 86_400 + t.h * 3600 + t.min * 60 + t.s
    }

    /// Vienna calendar day of `date` as `yyyyMMdd`.
    public static func dateString(_ date: Date) -> String {
        let c = vienna.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Vienna wall-clock time of `date` as `HHmmss`.
    public static func timeString(_ date: Date) -> String {
        let c = vienna.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Epoch seconds as HAFAS sends them in `planrtTS` ("1791537771"); "0" / empty → nil.
    static func epoch(_ s: String?) -> Date? {
        guard let s, let v = Int(s), v > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(v))
    }

    // MARK: - Parsing

    private static func digits(_ s: Substring) -> Int? {
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(s)
    }

    private static func civil(_ s: String) -> (y: Int, m: Int, d: Int)? {
        guard s.count == 8 else { return nil }
        let y = s.prefix(4), m = s.dropFirst(4).prefix(2), d = s.suffix(2)
        guard let yy = digits(y), let mm = digits(m), let dd = digits(d), (1...12).contains(mm), (1...31).contains(dd) else { return nil }
        return (yy, mm, dd)
    }

    /// Largest accepted `[dd]` day offset and UTC offset (minutes). HAFAS sends two-digit day offsets and offsets of
    /// ±60/120 min; larger values are corrupt and must not reach the arithmetic (integer overflow traps).
    static let maxDayOffset = 99
    static let maxOffsetMinutes = 24 * 60

    private static func clock(_ s: String) -> (days: Int, h: Int, min: Int, s: Int)? {
        guard s.count >= 6, s.count <= 8 + 2 else { return nil }
        let dayPart = s.dropLast(6)
        let tail = s.suffix(6)
        let days = dayPart.isEmpty ? 0 : digits(dayPart)
        guard let days, days <= maxDayOffset, let h = digits(tail.prefix(2)), let mi = digits(tail.dropFirst(2).prefix(2)),
              let se = digits(tail.suffix(2)), h < 48, mi < 60, se < 61 else { return nil }
        return (days, h, mi, se)
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (H. Hinnant's algorithm).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(fromDays z0: Int) -> (y: Int, m: Int, d: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}
