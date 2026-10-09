import Foundation

/// Austrian German formatting helpers ("€ 1.300", "4.812 km", "14. Dez.").
enum Format {
    static let locale = Locale(identifier: "de_AT")

    static func euro(_ value: Double, decimals: Int? = nil) -> String {
        let digits = decimals ?? (abs(value) >= 1000 || value == value.rounded() ? 0 : 2)
        return value.formatted(.currency(code: "EUR").locale(locale).precision(.fractionLength(digits)))
    }

    /// Always two decimals ("€ 23,40").
    static func euroPrecise(_ value: Double) -> String { euro(value, decimals: 2) }

    /// Number without currency, grouped ("1.300").
    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(decimals)))
    }

    static func km(_ value: Double) -> String { "\(number(value, decimals: value < 10 ? 1 : 0)) km" }

    static func kg(_ value: Double) -> String {
        value >= 1000 ? "\(number(value / 1000, decimals: 1)) t" : "\(number(value)) kg"
    }

    static func percent(_ fraction: Double) -> String { "\(number(fraction * 100)) %" }

    static func date(_ date: Date, _ style: Date.FormatStyle.DateStyle = .abbreviated) -> String {
        date.formatted(Date.FormatStyle(date: style, time: .omitted).locale(locale))
    }

    /// "14. Dez."
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "Fr., 9. Okt."
    static func weekdayDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// "Heute", "Gestern", or "Fr., 9. Okt."
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return weekdayDayMonth(date)
    }

    /// "Oktober 2026"
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 Tag" : "\(n) Tage" }
}
