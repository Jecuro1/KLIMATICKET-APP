import Foundation

/// Austrian German formatting helpers ("€ 1.300", "4.812 km", "14. Dez.").
enum Format {
    static let locale = Locale(identifier: "de_AT")
    /// Dates are shown in Austrian time, matching the Vienna calendar used for all date maths (Calendar.vienna).
    static let timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current

    private static func styled(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var s = style.locale(locale)
        s.timeZone = timeZone
        s.calendar = .vienna
        return s
    }

    static func euro(_ value: Double, decimals: Int? = nil) -> String {
        let digits = decimals ?? (abs(value) >= 1000 || value == value.rounded() ? 0 : 2)
        if euroStyles.indices.contains(digits) { return value.formatted(euroStyles[digits]) }
        return value.formatted(.currency(code: "EUR").locale(locale).precision(.fractionLength(digits)))
    }

    // Built once for 0…2 decimals: count-ins format on every frame, lists on every row.
    private static let euroStyles: [FloatingPointFormatStyle<Double>.Currency] = (0...2).map { digits in
        .currency(code: "EUR").locale(locale).precision(.fractionLength(digits))
    }
    private static let numberStyles: [FloatingPointFormatStyle<Double>] = (0...2).map { digits in
        .number.locale(locale).precision(.fractionLength(digits))
    }

    /// Always two decimals ("€ 23,40").
    static func euroPrecise(_ value: Double) -> String { euro(value, decimals: 2) }

    /// Number without currency, grouped ("1.300").
    static func number(_ value: Double, decimals: Int = 0) -> String {
        if numberStyles.indices.contains(decimals) { return value.formatted(numberStyles[decimals]) }
        return value.formatted(.number.locale(locale).precision(.fractionLength(decimals)))
    }

    static func km(_ value: Double) -> String { "\(number(value, decimals: value < 10 ? 1 : 0)) km" }

    static func kg(_ value: Double) -> String {
        value >= 1000 ? "\(number(value / 1000, decimals: 1)) t" : "\(number(value)) kg"
    }

    /// "75 %". Never shows "100 %" before the goal is actually reached (99,6 % → "99 %").
    static func percent(_ fraction: Double) -> String {
        var value = (fraction * 100).rounded()
        if fraction < 1, value >= 100 { value = 99 }
        return "\(number(value)) %"
    }

    static func date(_ date: Date, _ style: Date.FormatStyle.DateStyle = .abbreviated) -> String {
        date.formatted(styled(Date.FormatStyle(date: style, time: .omitted)))
    }

    // Styles built once – these run for every row, chart label and toast.
    private static let dayMonthStyle = styled(.dateTime.day().month(.abbreviated))
    private static let weekdayDayMonthStyle = styled(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    private static let timeStyle = styled(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    private static let monthYearStyle = styled(.dateTime.month(.wide).year())

    /// "14. Dez."
    static func dayMonth(_ date: Date) -> String {
        date.formatted(dayMonthStyle)
    }

    /// "Fr., 9. Okt."
    static func weekdayDayMonth(_ date: Date) -> String {
        date.formatted(weekdayDayMonthStyle)
    }

    static func time(_ date: Date) -> String {
        date.formatted(timeStyle)
    }

    /// "Heute", "Gestern", or "Fr., 9. Okt."
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.vienna
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return weekdayDayMonth(date)
    }

    /// "Oktober 2026"
    static func monthYear(_ date: Date) -> String {
        date.formatted(monthYearStyle)
    }

    static func days(_ n: Int) -> String { n == 1 ? "1 Tag" : "\(n) Tage" }
}
