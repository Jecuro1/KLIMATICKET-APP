import Foundation

// MARK: themes – „Zahlen“ in Look & Feel (docs/THEMES.md §6): amounts, week start, CO₂ unit. km and € only – no other
// unit systems.

public struct FormatPrefs: Codable, Equatable, Hashable, Sendable {
    /// How amounts without a fixed precision are shown (`Format.euro(x)`; a caller that asks for 0 or 2 decimals keeps them).
    public enum Amounts: String, CaseIterable, Codable, Sendable, Identifiable {
        /// Cent below € 1.000 when there are cents ("€ 23,40", "€ 1.300") – the app's format before this option.
        case automatic = "auto"
        /// Whole euros ("€ 23").
        case whole = "ganz"
        /// Always with cents ("€ 1.300,00").
        case cents = "cent"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .automatic: "Automatisch"
            case .whole: "Ganze Euro"
            case .cents: "Immer mit Cent"
            }
        }
    }

    public enum WeekStart: String, CaseIterable, Codable, Sendable, Identifiable {
        case monday, sunday

        public var id: String { rawValue }

        public var title: String { self == .monday ? "Montag" : "Sonntag" }

        /// `Calendar.firstWeekday` (1 = Sunday, 2 = Monday).
        public var firstWeekday: Int { self == .monday ? 2 : 1 }

        /// Display order of Monday-first indices (0 = Monday … 6 = Sunday): Montag → 0…6, Sonntag → 6, 0…5.
        public var mondayFirstOrder: [Int] { self == .monday ? Array(0...6) : [6, 0, 1, 2, 3, 4, 5] }

        /// `calendar` with this week start (time zone, locale and minimum days stay).
        public func calendar(from calendar: Calendar) -> Calendar {
            var copy = calendar
            copy.firstWeekday = firstWeekday
            return copy
        }

        /// 0-based column of `date` in a week that starts on this day.
        public func columnIndex(of date: Date, in calendar: Calendar) -> Int {
            let weekday = calendar.component(.weekday, from: date)   // 1 = Sunday … 7 = Saturday
            return (weekday - firstWeekday + 7) % 7
        }

        /// The first day of the week that holds `date` (local midnight).
        public func startOfWeek(containing date: Date, in calendar: Calendar) -> Date {
            let day = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: -columnIndex(of: day, in: calendar), to: day) ?? day
        }
    }

    public enum CO2Unit: String, CaseIterable, Codable, Sendable, Identifiable {
        /// kg below 1.000 kg, tonnes from there ("980 kg", "1,2 t") – the app's format before this option.
        case automatic = "auto"
        /// Always kilograms ("1.240 kg").
        case kilograms = "kg"

        public var id: String { rawValue }

        public var title: String { self == .automatic ? "Automatisch" : "Immer kg" }
    }

    public var amounts: Amounts
    public var weekStart: WeekStart
    public var co2: CO2Unit

    public init(amounts: Amounts = .automatic, weekStart: WeekStart = .monday, co2: CO2Unit = .automatic) {
        self.amounts = amounts
        self.weekStart = weekStart
        self.co2 = co2
    }

    public static let standard = FormatPrefs()

    /// Decimals for an amount without a fixed precision.
    public func euroFractionDigits(for value: Double) -> Int {
        switch amounts {
        case .automatic: (abs(value) >= 1000 || value == value.rounded()) ? 0 : 2
        case .whole: 0
        case .cents: 2
        }
    }

    /// Value, decimals and unit of a CO₂ amount in kg. Automatic decides on the shown (rounded) kilograms, so 999,9 kg
    /// reads "1,0 t" and never "1.000 kg".
    public func co2Parts(kg: Double) -> (value: Double, decimals: Int, unit: String) {
        if co2 == .automatic, abs(kg.rounded()) >= 1000 { return (kg / 1000, 1, "t") }
        return (kg, 0, "kg")
    }

    // Tolerant decoding: a missing or unknown value becomes the default, never a failure.
    private enum CodingKeys: String, CodingKey { case amounts, weekStart, co2 }

    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        amounts = Self.decoded(c, .amounts) ?? .automatic
        weekStart = Self.decoded(c, .weekStart) ?? .monday
        co2 = Self.decoded(c, .co2) ?? .automatic
    }

    private static func decoded<T: Decodable>(_ container: KeyedDecodingContainer<CodingKeys>?, _ key: CodingKeys) -> T? {
        guard let container else { return nil }
        return try? container.decodeIfPresent(T.self, forKey: key)
    }
}

/// de-AT formatting for the examples and the tests (the app's `Format` uses the same styles).
public enum AppearanceFormat {
    public static let locale = Locale(identifier: "de_AT")

    private static let euroStyles: [FloatingPointFormatStyle<Double>.Currency] = (0...2).map { digits in
        .currency(code: "EUR").locale(locale).precision(.fractionLength(digits))
    }
    private static let numberStyles: [FloatingPointFormatStyle<Double>] = (0...2).map { digits in
        .number.locale(locale).precision(.fractionLength(digits))
    }

    /// "€ 1.300" / "€ 23,40" for an amount without a fixed precision.
    public static func euro(_ value: Double, prefs: FormatPrefs) -> String {
        euro(value, digits: prefs.euroFractionDigits(for: value))
    }

    public static func euro(_ value: Double, digits: Int) -> String {
        let d = max(0, min(2, digits))
        return value.formatted(euroStyles[d])
    }

    public static func number(_ value: Double, decimals: Int) -> String {
        let d = max(0, min(2, decimals))
        return value.formatted(numberStyles[d])
    }

    /// "980 kg", "1,2 t", "1.240 kg".
    public static func co2(_ kg: Double, prefs: FormatPrefs) -> String {
        let parts = prefs.co2Parts(kg: kg)
        return "\(number(parts.value, decimals: parts.decimals)) \(parts.unit)"
    }

    public static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// The example line under each option: what it shows, or what it changes compared to Automatisch.
    public static func example(_ amounts: FormatPrefs.Amounts) -> String {
        let prefs = FormatPrefs(amounts: amounts)
        switch amounts {
        case .automatic: return "\(euro(1300, prefs: prefs)) · \(euro(23.4, prefs: prefs))"
        case .whole: return "\(euro(23.4, prefs: .standard)) → \(euro(23.4, prefs: prefs))"
        case .cents: return "\(euro(1300, prefs: .standard)) → \(euro(1300, prefs: prefs))"
        }
    }

    public static func example(_ weekStart: FormatPrefs.WeekStart) -> String {
        weekStart.mondayFirstOrder.map { weekdayShort[$0] }.joined(separator: " ")
    }

    public static func example(_ unit: FormatPrefs.CO2Unit) -> String {
        let prefs = FormatPrefs(co2: unit)
        switch unit {
        case .automatic: return "\(co2(980, prefs: prefs)) · \(co2(1240, prefs: prefs))"
        case .kilograms: return "\(co2(1240, prefs: .standard)) → \(co2(1240, prefs: prefs))"
        }
    }
}
