import Foundation
import SwiftUI
import KlimaCore

// Derived, view-ready values for the statistics screen. Everything is computed from the
// AnalyticsSnapshot (no duplicated business logic – only presentation shaping).

/// Austrian month / weekday names, independent from the device locale ("Jänner").
enum StatsNames {
    static let monthShort = ["Jän", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
    static let monthNarrow = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    static let monthWide = ["Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September",
                            "Oktober", "November", "Dezember"]
    /// Monday-first.
    static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let weekdayWide = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func monthIndex(_ date: Date) -> Int {
        max(0, min(11, Calendar.vienna.component(.month, from: date) - 1))
    }

    static func shortMonth(_ date: Date) -> String { monthShort[monthIndex(date)] }
    static func narrowMonth(_ date: Date) -> String { monthNarrow[monthIndex(date)] }
    static func wideMonth(_ date: Date) -> String { monthWide[monthIndex(date)] }

    /// 1 = Montag … 7 = Sonntag
    static func wideWeekday(_ weekday: Int) -> String { weekdayWide[max(0, min(6, weekday - 1))] }

    static func trips(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(n) Fahrten" }
}

/// One bar of the "Monatsbilanz" chart.
struct StatsMonthBar: Identifiable, Hashable {
    /// "2026-03" – unique even when a ticket period spans 13 calendar months.
    let id: String
    let month: Date
    let actual: Double
    /// Forecast value still to come in this month (current + future months).
    let projected: Double
    let trips: Int
    let isCurrent: Bool
    let isFuture: Bool
    let isBest: Bool

    var label: String { StatsNames.shortMonth(month) }
}

/// One day of the travel calendar heatmap.
struct StatsHeatDay: Identifiable, Hashable {
    enum Kind: Hashable { case outside, past, future }

    let id: Int
    let date: Date
    let trips: Int
    let value: Double
    /// 0 = no trip, 1…4 = brightness level (quartiles of day values).
    let level: Int
    let kind: Kind
    let isToday: Bool
}

struct StatsHeatWeek: Identifiable, Hashable {
    let id: Int
    let days: [StatsHeatDay]
    let monthLabel: String?
}

/// Result of the "Welches Ticket lohnt sich?" comparison.
struct StatsTicketComparison {
    let options: [TicketOption]
    let cheapest: TicketOption?
    let current: TicketOption?
    let maxCost: Double
    let factor: Double

    var isAnnualized: Bool { factor > 1.001 }
}

enum StatsCalc {
    static let averageMonthDays = 30.44
    /// Rough CO₂ per person for a one-way flight Vienna–Paris.
    static let kgPerFlight = 180.0
    /// CO₂ a tree binds per year.
    static let kgPerTreeYear = 22.0

    // MARK: Period

    /// "2026/27" (or "2026" when the period lies within one calendar year).
    static func ticketYearLabel(_ period: TicketPeriod) -> String {
        let cal = Calendar.vienna
        let y1 = cal.component(.year, from: period.start)
        let y2 = cal.component(.year, from: period.end)
        guard y1 != y2 else { return String(y1) }
        return "\(y1)/\(String(format: "%02d", y2 % 100))"
    }

    static func isRunning(_ period: TicketPeriod, now: Date = Date()) -> Bool {
        now >= period.start && now <= period.end
    }

    /// Value per day used for the forecast line (slope of `snapshot.forecast`).
    static func dailyPace(_ snapshot: AnalyticsSnapshot) -> Double {
        guard snapshot.forecast.count >= 2, let a = snapshot.forecast.first, let b = snapshot.forecast.last else { return 0 }
        let days = b.date.timeIntervalSince(a.date) / 86_400
        guard days > 0.5 else { return 0 }
        return max(0, (b.value - a.value) / days)
    }

    // MARK: Savings curve

    /// Cumulative value on `date` (step lookup in the daily series).
    static func value(at date: Date, in series: [CumulativePoint]) -> Double {
        var result = 0.0
        for point in series {
            if point.date <= date { result = point.value } else { break }
        }
        return result
    }

    /// Linear forecast value on `date` (nil before the forecast starts).
    static func forecastValue(at date: Date, in forecast: [CumulativePoint]) -> Double? {
        guard let a = forecast.first, let b = forecast.last, date > a.date else { return nil }
        let total = b.date.timeIntervalSince(a.date)
        guard total > 0 else { return b.value }
        let t = min(1, date.timeIntervalSince(a.date) / total)
        return a.value + (b.value - a.value) * t
    }

    /// Day the summit flag stands on: actual break-even day, or the forecast if it lies within the period.
    static func breakEvenDay(_ snapshot: AnalyticsSnapshot) -> Date? {
        let summary = snapshot.summary
        if summary.isPaidOff, let date = summary.paidOffDate { return Calendar.vienna.startOfDay(for: date) }
        if let date = summary.forecastBreakEvenDate, date <= snapshot.ticket.end { return date }
        return nil
    }

    /// Value collected in the running calendar month.
    static func currentMonthValue(_ snapshot: AnalyticsSnapshot, now: Date = Date()) -> Double? {
        let cal = Calendar.vienna
        guard isRunning(snapshot.ticket, now: now) else { return nil }
        return snapshot.months.first { cal.isDate($0.month, equalTo: now, toGranularity: .month) }?.value
    }

    // MARK: Monthly bars

    static func monthBars(_ snapshot: AnalyticsSnapshot, now: Date = Date()) -> [StatsMonthBar] {
        let cal = Calendar.vienna
        let pace = dailyPace(snapshot)
        let today = cal.startOfDay(for: now)
        let periodStart = cal.startOfDay(for: snapshot.ticket.start)
        let periodEnd = cal.startOfDay(for: snapshot.ticket.end)
        let afterEnd = cal.date(byAdding: .day, value: 1, to: periodEnd) ?? periodEnd
        let running = isRunning(snapshot.ticket, now: now)
        let bestMonth = snapshot.months.filter { $0.value > 0 }.max { $0.value < $1.value }?.month

        return snapshot.months.map { bucket -> StatsMonthBar in
            let comps = cal.dateComponents([.year, .month], from: bucket.month)
            let id = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            let next = cal.date(byAdding: .month, value: 1, to: bucket.month) ?? bucket.month
            let monthEnd = min(next, afterEnd)
            let isCurrent = running && bucket.month <= today && today < next
            let isFuture = running && bucket.month > today
            var projected = 0.0
            if running && pace > 0 {
                if isCurrent {
                    let daysLeft = (cal.dateComponents([.day], from: today, to: monthEnd).day ?? 0) - 1
                    projected = pace * Double(max(0, daysLeft))
                } else if isFuture {
                    let from = max(bucket.month, periodStart)
                    let days = cal.dateComponents([.day], from: from, to: monthEnd).day ?? 0
                    projected = pace * Double(max(0, days))
                }
            }
            return StatsMonthBar(id: id, month: bucket.month, actual: bucket.value, projected: projected, trips: bucket.trips,
                                 isCurrent: isCurrent, isFuture: isFuture, isBest: bucket.month == bestMonth)
        }
    }

    /// Average value per month so far (value per day × 30,44).
    static func averagePerMonth(_ snapshot: AnalyticsSnapshot) -> Double {
        snapshot.summary.valuePerDay * averageMonthDays
    }

    /// Value per month needed to break even within the period (ticket price ÷ 12).
    static func targetPerMonth(_ snapshot: AnalyticsSnapshot) -> Double {
        snapshot.ticket.price / 12
    }

    // MARK: Heatmap

    static func heatmap(_ snapshot: AnalyticsSnapshot, now: Date = Date()) -> [StatsHeatWeek] {
        let cal = Calendar.vienna
        let start = cal.startOfDay(for: snapshot.ticket.start)
        let end = cal.startOfDay(for: snapshot.ticket.end)
        let today = cal.startOfDay(for: now)
        guard let firstMonday = cal.dateInterval(of: .weekOfYear, for: start)?.start, end >= start else { return [] }
        let totalDays = (cal.dateComponents([.day], from: firstMonday, to: end).day ?? 0) + 1
        let weekCount = max(1, Int((Double(totalDays) / 7).rounded(.up)))

        var byDay: [Date: DayActivity] = [:]
        for day in snapshot.days { byDay[day.day] = day }
        let values = snapshot.days.map(\.value).sorted()
        func quantile(_ q: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            return values[min(values.count - 1, Int(Double(values.count - 1) * q))]
        }
        let q1 = quantile(0.25), q2 = quantile(0.5), q3 = quantile(0.75)

        var weeks: [StatsHeatWeek] = []
        weeks.reserveCapacity(weekCount)
        var lastMonth = -1
        for w in 0..<weekCount {
            var days: [StatsHeatDay] = []
            var label: String?
            for d in 0..<7 {
                let index = w * 7 + d
                let date = cal.date(byAdding: .day, value: index, to: firstMonday) ?? firstMonday
                let inPeriod = date >= start && date <= end
                let activity = byDay[date]
                let kind: StatsHeatDay.Kind = !inPeriod ? .outside : (date > today ? .future : .past)
                var level = 0
                if let activity, activity.trips > 0 {
                    if activity.value <= q1 { level = 1 } else if activity.value <= q2 { level = 2 } else if activity.value <= q3 { level = 3 } else { level = 4 }
                }
                if inPeriod {
                    let month = cal.component(.month, from: date)
                    if month != lastMonth {
                        if label == nil { label = StatsNames.monthShort[max(0, min(11, month - 1))] }
                        lastMonth = month
                    }
                }
                days.append(StatsHeatDay(id: index, date: date, trips: activity?.trips ?? 0, value: activity?.value ?? 0,
                                         level: level, kind: kind, isToday: date == today && inPeriod))
            }
            weeks.append(StatsHeatWeek(id: w, days: days, monthLabel: label))
        }
        return weeks
    }

    // MARK: Ticket comparison

    static func ticketComparison(_ snapshot: AnalyticsSnapshot, products: [TicketProduct], variant: TicketVariant) -> StatsTicketComparison {
        let elapsed = Double(max(snapshot.summary.daysElapsed, 1))
        let total = Double(max(snapshot.summary.daysTotal, 1))
        let factor = elapsed / total < 0.25 ? total / elapsed : 1
        let all = TicketComparator.compare(trips: snapshot.trips, products: products, variant: variant,
                                           currentProductID: snapshot.ticket.productID,
                                           periodStart: snapshot.ticket.start,   // MARK: global – prices of that start date
                                           annualizationFactor: factor)
        var shown = Array(all.prefix(4))
        if let current = all.first(where: { $0.isCurrent }), !shown.contains(where: { $0.id == current.id }) {
            shown.append(current)
        }
        if let single = all.first(where: { $0.id == "single" }), !shown.contains(where: { $0.id == single.id }) {
            shown.append(single)
        }
        shown.sort { $0.totalCost < $1.totalCost }
        return StatsTicketComparison(options: shown, cheapest: shown.first, current: shown.first { $0.isCurrent },
                                     maxCost: max(shown.map(\.totalCost).max() ?? 1, 1), factor: factor)
    }

    // MARK: Formatting helpers

    /// "3" / "0,4" – friendly equivalent counts.
    static func friendlyCount(_ value: Double) -> String {
        Format.number(value, decimals: value < 9.95 ? 1 : 0)
    }

    /// "1.234" or "1,2" with unit "kg" / "t".
    static func co2Parts(_ kg: Double) -> (value: String, unit: String) {
        kg >= 1000 ? (Format.number(kg / 1000, decimals: 1), "t") : (Format.number(kg), "kg")
    }
}

/// Single-hue brightness ramp (glacier) for the travel calendar.
enum StatsHeat {
    static func color(level: Int) -> Color {
        switch level {
        case 0: Theme.textTertiary.opacity(0.16)
        case 1: Theme.glacier.opacity(0.30)
        case 2: Theme.glacier.opacity(0.52)
        case 3: Theme.glacier.opacity(0.76)
        default: Theme.glacier
        }
    }
}
