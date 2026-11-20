import Foundation

// MARK: siri – how Siri says a figure (de-AT) and how the snippet writes it. Spoken: „212 Euro 40“, „1 Fahrt“, „3,4 Kilogramm“ –
// never „€ 212,40“, which a voice reads as „212 Komma 40 Euro“. Written: the app's own formats (Look & Feel › Zahlen).

public enum KpiSpoken {
    static let locale = Locale(identifier: "de_AT")

    /// „1.044“, „3,4“ – de-AT digits with `decimals` fraction digits (0 … 2).
    public static func number(_ value: Double, decimals: Int = 0) -> String {
        AppearanceFormat.number(value, decimals: decimals)
    }

    /// Whole when the value rounds to a whole number at `decimals`, else with them: 3,4 · 58 · 2.
    static func compact(_ value: Double, decimals: Int) -> String {
        let factor = pow(10, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        return rounded == rounded.rounded() ? number(rounded) : number(rounded, decimals: decimals)
    }

    // MARK: Spoken

    /// „212 Euro 40“, „186 Euro“, „40 Cent“, „1.044 Euro“ (whole euros from € 1.000, like the app's amounts), „0 Euro“.
    public static func euro(_ value: Double) -> String {
        let cents = Int((abs(value) * 100).rounded())
        let sign = value < 0 && cents > 0 ? "minus " : ""
        if cents >= 100_000 { return sign + "\(number(Double((cents + 50) / 100))) Euro" }
        let euros = cents / 100, rest = cents % 100
        if euros == 0 && rest > 0 { return sign + "\(rest) Cent" }
        if rest == 0 { return sign + "\(number(Double(euros))) Euro" }
        return sign + "\(number(Double(euros))) Euro \(rest)"
    }

    /// „1 Fahrt“, „14 Fahrten“, „keine Fahrt“ is the caller's sentence.
    public static func trips(_ count: Int) -> String { count == 1 ? "1 Fahrt" : "\(number(Double(count))) Fahrten" }

    /// „1 Tag“, „45 Tage“.
    public static func days(_ count: Int) -> String { count == 1 ? "1 Tag" : "\(number(Double(count))) Tage" }

    /// „412 Kilometer“, „3,4 Kilometer“, „1 Kilometer“ (one decimal below 10 km).
    public static func km(_ value: Double) -> String {
        let text = compact(value, decimals: value < 9.95 ? 1 : 0)
        return "\(text) Kilometer"
    }

    /// „3,4 Kilogramm“, „58 Kilogramm“, „1,2 Tonnen“ (from 1.000 kg unless Zahlen says „Immer kg“), „1 Tonne“.
    public static func co2(_ kg: Double, format: FormatPrefs = .standard) -> String {
        if format.co2 == .automatic, kg.rounded() >= 1000 {
            let text = compact(kg / 1000, decimals: 1)
            return text == "1" ? "1 Tonne" : "\(text) Tonnen"
        }
        let text = compact(kg, decimals: kg < 9.95 ? 1 : 0)
        return text == "1" ? "1 Kilogramm" : "\(text) Kilogramm"
    }

    // MARK: Written (the snippet's big figure and the value a Kurzbefehl gets)

    /// „€ 186,40“ / „€ 1.044“ with the amounts of Look & Feel › Zahlen.
    public static func writtenEuro(_ value: Double, format: FormatPrefs = .standard) -> String {
        AppearanceFormat.euro(value, prefs: format)
    }

    /// „412 km“, „3,4 km“.
    public static func writtenKm(_ value: Double) -> String { "\(compact(value, decimals: value < 9.95 ? 1 : 0)) km" }

    /// „58 kg“, „3,4 kg“, „1,2 t“.
    public static func writtenCO2(_ kg: Double, format: FormatPrefs = .standard) -> String {
        if format.co2 == .automatic, kg.rounded() >= 1000 { return "\(compact(kg / 1000, decimals: 1)) t" }
        return "\(compact(kg, decimals: kg < 9.95 ? 1 : 0)) kg"
    }

    // MARK: Dates

    /// Jänner, not Januar (de-AT), independent of the platform's locale data.
    public static let monthNames = ["Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                                    "November", "Dezember"]

    /// „14. Dezember“, with the year when it is not the year of `now` („3. Jänner 2027“).
    public static func date(_ date: Date, now: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = calendar.component(.year, from: now)
        let month = monthNames[max(0, min(11, (c.month ?? 1) - 1))]
        let text = "\(c.day ?? 1). \(month)"
        return c.year == year ? text : "\(text) \(c.year ?? year)"
    }
}
