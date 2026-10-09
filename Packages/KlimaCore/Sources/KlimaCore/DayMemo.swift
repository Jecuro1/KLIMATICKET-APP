import Foundation

/// Calendar lookups per trip, memoised per local day. `startOfDay`, month and weekday math with a named time zone cost
/// a few microseconds each, and the analytics passes ask several times per trip – while a year of trips falls on at
/// most 366 days. The key is the day number in the calendar's time zone (offset taken at that instant, so DST changes
/// are handled); every value still comes from the calendar itself.
struct DayMemo {
    let calendar: Calendar
    private let timeZone: TimeZone
    private var starts: [Int: Date] = [:]
    private var months: [Int: Date] = [:]
    private var weekdays: [Int: Int] = [:]

    init(_ calendar: Calendar) {
        self.calendar = calendar
        timeZone = calendar.timeZone
    }

    /// Local day number of `date` (days since 2001-01-01 in the calendar's time zone); nil for dates beyond any range.
    func dayKey(_ date: Date) -> Int? {
        let local = date.timeIntervalSinceReferenceDate + Double(timeZone.secondsFromGMT(for: date))
        guard local.isFinite, abs(local) < 1e14 else { return nil }
        return Int((local / 86_400).rounded(.down))
    }

    mutating func startOfDay(_ date: Date) -> Date {
        guard let key = dayKey(date) else { return calendar.startOfDay(for: date) }
        if let hit = starts[key] { return hit }
        let start = calendar.startOfDay(for: date)
        starts[key] = start
        return start
    }

    /// First moment of `date`'s month (nil only when the calendar cannot build it).
    mutating func startOfMonth(_ date: Date) -> Date? {
        guard let key = dayKey(date) else { return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) }
        if let hit = months[key] { return hit }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        if let start { months[key] = start }
        return start
    }

    /// Calendar weekday (1 = Sunday … 7 = Saturday).
    mutating func weekday(_ date: Date) -> Int {
        guard let key = dayKey(date) else { return calendar.component(.weekday, from: date) }
        if let hit = weekdays[key] { return hit }
        let weekday = calendar.component(.weekday, from: date)
        weekdays[key] = weekday
        return weekday
    }
}
