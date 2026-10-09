import SwiftUI
import WidgetKit
import KlimaCore

// Shared by the app (widget gallery) and the widget extension.
// The app's `Format` / DesignSystem live in the app target only, so the widget views carry their own small helpers.

// MARK: - Formatting (de-AT, mirrors `Format`)

enum WidFormat {
    static let locale = Locale(identifier: "de_AT")

    /// "€ 1.400" · "€ 23,50"
    static func euro(_ value: Double, decimals: Int? = nil) -> String {
        let digits = decimals ?? (abs(value) >= 1000 || value == value.rounded() ? 0 : 2)
        return value.formatted(.currency(code: "EUR").locale(locale).precision(.fractionLength(digits)))
    }

    /// Always two decimals ("€ 22,80").
    static func euroPrecise(_ value: Double) -> String { euro(value, decimals: 2) }

    /// Whole euros ("€ 354").
    static func euroWhole(_ value: Double) -> String { euro(value, decimals: 0) }

    static func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(decimals)))
    }

    static func km(_ value: Double) -> String { "\(number(value, decimals: value < 10 ? 1 : 0)) km" }

    static func kg(_ value: Double) -> String {
        value >= 1000 ? "\(number(value / 1000, decimals: 1)) t" : "\(number(value)) kg"
    }

    /// 0.728 → 73. Same rule as the app (`SummitFigures.percent`): never "100 %" before the break-even (99,6 % → 99)
    /// and never rounded up past it afterwards (149,7 % → 149).
    static func percentValue(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        let raw = min(max(0, fraction) * 100, 1_000_000)
        return Int(fraction < 1 ? min(99, raw.rounded()) : raw.rounded(.down))
    }

    /// 0.728 → "73 %"
    static func percent(_ fraction: Double) -> String { "\(percentValue(fraction)) %" }

    /// "14. Dez."
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "1 Tag" · "143 Tage"
    static func days(_ n: Int) -> String { n == 1 ? "1 Tag" : "\(n) Tage" }

    /// "heute" · "morgen" · "in 66 Tagen"
    static func inDays(_ n: Int) -> String {
        if n <= 0 { return "heute" }
        if n == 1 { return "morgen" }
        return "in \(n) Tagen"
    }

    /// "1 Fahrt" · "87 Fahrten"
    static func trips(_ n: Int) -> String { n == 1 ? "1 Fahrt" : "\(number(Double(n))) Fahrten" }
}

// MARK: - Layout

enum WidLayout {
    /// iPhone default widget content margins.
    static let defaultMargins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    /// Continuous corner radius used for previews in the app.
    static let cornerRadius: CGFloat = Theme.Radius.formGroup

    /// The system margins when the host reports them, otherwise the iPhone default.
    static func resolved(_ margins: EdgeInsets) -> EdgeInsets {
        margins.top + margins.leading + margins.bottom + margins.trailing > 1 ? margins : defaultMargins
    }

    /// Reference sizes (6.1"/6.3" iPhone) used by the in-app gallery.
    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        case .accessoryCircular: CGSize(width: 72, height: 72)
        case .accessoryRectangular: CGSize(width: 160, height: 72)
        case .accessoryInline: CGSize(width: 240, height: 22)
        default: CGSize(width: 364, height: 170)
        }
    }
}

extension WidgetFamily {
    /// Lock-screen style families (vibrant rendering, no container background).
    var widIsAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}

// MARK: - Ink

/// Secondary text on the widget skies. `Theme.textSecondary` is translucent and drops below 4.5:1 where it sits
/// on the summit glow (3.9:1 for "in 73 Tagen"); widgets are read at a glance, so in full colour they use an
/// opaque ink (≥ 4.8:1 on every part of both skies). In the accented / clear / vibrant styles the system recolours
/// everything, and the translucent theme ink keeps the primary/secondary hierarchy there.
struct WidSecondaryInk: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        guard environment.widgetRenderingMode == .fullColor else { return Theme.textSecondary }
        return environment.colorScheme == .dark ? Self.dark : Self.light
    }

    private static let light = Color(hex: "#3E4A5C")
    private static let dark = Color(hex: "#C9D2E0")
}

extension ShapeStyle where Self == WidSecondaryInk {
    /// Secondary widget text (see `WidSecondaryInk`).
    static var widSecondary: WidSecondaryInk { WidSecondaryInk() }
}

// MARK: - Deep links

enum WidDeepLink {
    /// klimabilanz://tab/overview
    static let overview = URL(string: "klimabilanz://tab/overview")!
    /// klimabilanz://add – opens the add-trip sheet.
    static let addTrip = URL(string: "klimabilanz://add")!
}

// MARK: - Transport modes

enum WidMode {
    /// Maps the snapshot's SF Symbol back to the transport mode (for its landscape colour).
    static func mode(forSymbol symbol: String) -> TransportMode? {
        TransportMode.allCases.first { $0.symbolName == symbol }
    }

    static func color(forSymbol symbol: String) -> Color {
        mode(forSymbol: symbol).map { Theme.modeColor($0) } ?? Theme.accent
    }
}

// MARK: - Derived wording

/// Right-hand "forecast" block: break-even date, profit, or days left.
struct WidForecastInfo {
    var kicker: String
    var symbol: String
    var value: String
    var caption: String
    var isPositive: Bool
}

enum WidInsight {
    /// The ticket's calendar (validity, day counts). `Calendar.vienna` builds a new calendar on every access.
    static let calendar = Calendar.vienna

    /// Whole calendar days from `start` to `end` (Vienna days, so DST changes never make it 0 or 2).
    static func dayCount(from start: Date, to end: Date) -> Int {
        let cal = calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
    }

    /// Days left, corrected for snapshots written a few days ago.
    static func daysRemaining(_ s: WidgetSnapshot, now: Date = Date()) -> Int {
        max(0, s.daysRemaining - max(0, dayCount(from: s.generatedAt, to: now)))
    }

    static func isPaidOff(_ s: WidgetSnapshot) -> Bool { s.isPaidOff || s.totalValue >= s.ticketPrice }

    /// Past the ticket's end (`validUntil` is its last day at 23:59:59). Not `daysRemaining == 0`: that is the last
    /// day, still valid – the app reads it as "letzter Tag" (KlimaCore counts the days *after* today).
    static func isExpired(_ s: WidgetSnapshot, now: Date = Date()) -> Bool { now > s.validUntil }

    /// The break-even forecast while it still lies ahead and inside the validity (a date the app computed days ago
    /// may have passed without the trips that would have reached it).
    static func upcomingBreakEven(_ s: WidgetSnapshot, now: Date = Date()) -> Date? {
        guard let date = s.forecastBreakEvenDate, date <= s.validUntil, dayCount(from: now, to: date) >= 0 else { return nil }
        return date
    }

    static func forecast(_ s: WidgetSnapshot, now: Date = Date()) -> WidForecastInfo {
        let left = daysRemaining(s, now: now)
        if isPaidOff(s) {
            return WidForecastInfo(kicker: "Im Plus", symbol: "checkmark.seal.fill",
                                   value: "+ \(WidFormat.euroWhole(WidFigures.profit(s)))", caption: WidFormat.trips(s.tripCount),
                                   isPositive: true)
        }
        if let date = upcomingBreakEven(s, now: now) {
            return WidForecastInfo(kicker: "Break-even", symbol: "flag.fill", value: WidFormat.dayMonth(date),
                                   caption: WidFormat.inDays(dayCount(from: now, to: date)), isPositive: false)
        }
        if isExpired(s, now: now) {
            return WidForecastInfo(kicker: "Abgelaufen", symbol: "calendar", value: WidFormat.dayMonth(s.validUntil),
                                   caption: "Folgeticket anlegen", isPositive: false)
        }
        return WidForecastInfo(kicker: "Gültig noch", symbol: "calendar", value: left > 0 ? WidFormat.days(left) : "heute",
                               caption: "bis \(WidFormat.dayMonth(s.validUntil))", isPositive: false)
    }

    /// "noch 143 Tage" · "letzter Tag" · "abgelaufen"
    static func validityText(_ s: WidgetSnapshot, now: Date = Date()) -> String {
        let left = daysRemaining(s, now: now)
        if left > 0 { return "noch \(WidFormat.days(left))" }
        return isExpired(s, now: now) ? "abgelaufen" : "letzter Tag"
    }

    /// VoiceOver summary for whole-widget elements.
    static func spokenSummary(_ s: WidgetSnapshot, now: Date = Date()) -> String {
        var parts = ["\(WidFormat.percent(s.amortizedFraction)) amortisiert"]
        if isPaidOff(s) {
            parts.append("rentiert, \(WidFormat.euroWhole(WidFigures.profit(s))) im Plus")
        } else {
            parts.append("noch \(WidFormat.euroWhole(WidFigures.remaining(s))) bis zum Break-even")
            if let date = upcomingBreakEven(s, now: now) {
                parts.append("Prognose \(WidFormat.dayMonth(date))")
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// Whole-euro figures, rounded the way the app rounds them (`SummitFigures`): "€ 1.044 von € 1.400" and "noch € 356"
/// always add up, and nothing reads "€ 1.400 von € 1.400" or "noch € 0" before the break-even is actually reached.
enum WidFigures {
    static func total(_ s: WidgetSnapshot) -> Double {
        let total = max(0, s.totalValue.rounded())
        let summit = s.ticketPrice.rounded()
        if !WidInsight.isPaidOff(s), summit >= 1, total >= summit { return summit - 1 }
        return total
    }

    static func remaining(_ s: WidgetSnapshot) -> Double {
        guard !WidInsight.isPaidOff(s) else { return 0 }
        return max(0, s.ticketPrice.rounded() - total(s))
    }

    /// The ticket price as the figures above count it ("von € 1.400", the summit label) – `rounded()`, like `total`
    /// and `remaining`; the currency format alone would round x,50 to even and break "1.044 + 356".
    static func price(_ s: WidgetSnapshot) -> Double { s.ticketPrice.rounded() }

    static func profit(_ s: WidgetSnapshot) -> Double {
        max(0, s.totalValue.rounded() - s.ticketPrice.rounded())
    }
}

extension EnvironmentValues {
    /// The moment a widget timeline entry stands for (WidgetKit renders future entries ahead of time); nil = now.
    @Entry var widNow: Date? = nil
}

// MARK: - Summit geometry

/// Normalised geometry of the "Weg zum Gipfel" artwork (x = share of the ticket year, y = share of the value range).
struct WidSummitModel {
    /// Cumulative value route from ticket start to today.
    var route: [CGPoint]
    /// Summit position along x (break-even day: actual, forecast or near the end).
    var summitX: CGFloat
    /// Height of the ticket price (= summit) in the value range.
    var priceLevel: CGFloat
    var isPaidOff: Bool

    var today: CGPoint? { route.last }

    init(route: [CGPoint], summitX: CGFloat, priceLevel: CGFloat, isPaidOff: Bool) {
        self.route = route
        self.summitX = summitX
        self.priceLevel = priceLevel
        self.isPaidOff = isPaidOff
    }

    init(snapshot s: WidgetSnapshot, now: Date = Date(), yearDays: Double = 365) {
        let price = max(s.ticketPrice, 1)
        let paidOff = WidInsight.isPaidOff(s)
        var values = s.sparkline.filter { $0.isFinite }
        if values.isEmpty { values = [0] }
        if values[0] > 0.5 { values.insert(0, at: 0) }
        if let last = values.last, abs(last - s.totalValue) > 0.5 { values.append(s.totalValue) }
        if values.count == 1 { values.append(values[0]) }

        let maxValue = max(price * 1.12, (values.max() ?? 0) * 1.04, 1)
        // Keep room on the right for the forecast segment towards the summit. Days left as of `now`: a snapshot the
        // app wrote days ago would otherwise put today's climber where it stood back then.
        let elapsedRaw = 1 - Double(WidInsight.daysRemaining(s, now: now)) / yearDays
        let elapsed = min(max(elapsedRaw, 0.08), paidOff ? 0.95 : 0.86)
        let steps = Double(values.count - 1)
        route = values.enumerated().map { index, value in
            CGPoint(x: elapsed * Double(index) / steps, y: value / maxValue)
        }
        priceLevel = CGFloat(price / maxValue)
        isPaidOff = paidOff

        var summit: Double
        if paidOff, let index = values.firstIndex(where: { $0 >= price }) {
            if index > 0 {
                let v0 = values[index - 1], v1 = values[index]
                let t = v1 > v0 ? (price - v0) / (v1 - v0) : 1
                summit = elapsed * (Double(index - 1) + t) / steps
            } else {
                summit = 0.02
            }
        } else if let date = s.forecastBreakEvenDate {
            summit = elapsed + Double(max(WidInsight.dayCount(from: now, to: date), 0)) / yearDays
        } else {
            summit = 0.95
        }
        if !paidOff { summit = max(summit, elapsed + 0.07) }
        summitX = CGFloat(min(max(summit, 0.04), 0.94))
    }

    /// Decorative summit without a route (empty states, quick-log backdrop).
    static let decorative = WidSummitModel(route: [], summitX: 0.74, priceLevel: 0.88, isPaidOff: false)
}
