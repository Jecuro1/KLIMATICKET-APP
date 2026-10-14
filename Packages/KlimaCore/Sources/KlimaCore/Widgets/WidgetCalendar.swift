import Foundation

/// The 12-week trip heatmap for the widgets: 12 week columns of 7 days (Monday on top), the current week last. The app
/// stores the trip count per cell, oldest first; the widget derives the shades from it. Pure functions, unit-tested.
public enum WidgetHeatmap {
    public static let weeks = 12
    public static let cellCount = weeks * 7

    /// First day of the grid for `day`: the Monday of its week, eleven weeks earlier.
    public static func windowStart(for day: Date, calendar: Calendar = .vienna) -> Date {
        let startOfDay = calendar.startOfDay(for: day)
        // Monday = 0 … Sunday = 6, independent of the calendar's firstWeekday.
        let weekdayIndex = (calendar.component(.weekday, from: startOfDay) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -weekdayIndex, to: startOfDay) ?? startOfDay
        return calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: monday) ?? monday
    }

    /// Grid index of `today` (0 … cellCount-1); cells after it are the future of the current week.
    public static func todayIndex(_ today: Date, calendar: Calendar = .vienna) -> Int {
        dayCount(from: windowStart(for: today, calendar: calendar), to: today, calendar: calendar)
    }

    /// Trips per day of the grid of `today`, oldest cell first. Trips outside the grid are ignored; future cells stay 0.
    public static func counts(tripDates: [Date], today: Date, calendar: Calendar = .vienna) -> [Int] {
        let start = windowStart(for: today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        var counts = Array(repeating: 0, count: cellCount)
        for date in tripDates {
            let day = calendar.startOfDay(for: date)
            guard day >= start, day <= todayStart else { continue }
            let offset = dayCount(from: start, to: day, calendar: calendar)
            if offset >= 0, offset < cellCount { counts[offset] += 1 }
        }
        return counts
    }

    /// Shades 0 … 4 for trip counts: 0 is a day without a trip; 1 … 4 split the busiest day into quarters.
    public static func levels(_ counts: [Int]) -> [UInt8] {
        let peak = counts.max() ?? 0
        return counts.map { count in
            guard count > 0, peak > 0 else { return 0 }
            let ratio = Double(count) / Double(peak)
            switch ratio {
            case ...0.25: return 1
            case ...0.5: return 2
            case ...0.75: return 3
            default: return 4
            }
        }
    }

    /// The value to draw for grid cell `index` on the grid of `today`, when `stored` was made on `storedDay`. Cells the
    /// stored grid does not cover (a later week) read as `fallback`.
    public static func cell<T>(_ index: Int, stored: [T], fallback: T, storedDay: Date, today: Date,
                               calendar: Calendar = .vienna) -> T {
        guard index >= 0, index < cellCount else { return fallback }
        let storedStart = windowStart(for: storedDay, calendar: calendar)
        let shift = dayCount(from: storedStart, to: windowStart(for: today, calendar: calendar), calendar: calendar)
        let position = index + shift
        guard position >= 0, position < stored.count else { return fallback }
        return stored[position]
    }

    static func dayCount(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// The year teaser (Jahresrückblick): shown in December and in the last days of the ticket, otherwise the widget shows
/// the countdown.
public enum WidgetYearReview {
    public static func isVisible(now: Date, validUntil: Date, calendar: Calendar = .vienna, lastDays: Int = 30) -> Bool {
        if calendar.component(.month, from: now) == 12 { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: validUntil)).day ?? 0
        return days <= lastDays
    }
}
