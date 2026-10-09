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

    /// 0.728 → 73
    static func percentValue(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((max(0, fraction) * 100).rounded())
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
    static func dayCount(from start: Date, to end: Date) -> Int {
        let cal = Calendar.vienna
        return cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
    }

    /// Days left, corrected for snapshots written a few days ago.
    static func daysRemaining(_ s: WidgetSnapshot, now: Date = Date()) -> Int {
        max(0, s.daysRemaining - max(0, dayCount(from: s.generatedAt, to: now)))
    }

    static func isPaidOff(_ s: WidgetSnapshot) -> Bool { s.isPaidOff || s.totalValue >= s.ticketPrice }

    static func forecast(_ s: WidgetSnapshot, now: Date = Date()) -> WidForecastInfo {
        let left = daysRemaining(s, now: now)
        if isPaidOff(s) {
            return WidForecastInfo(kicker: "Im Plus", symbol: "checkmark.seal.fill",
                                   value: "+ \(WidFormat.euroWhole(s.net))", caption: WidFormat.trips(s.tripCount), isPositive: true)
        }
        if let date = s.forecastBreakEvenDate, date <= s.validUntil {
            return WidForecastInfo(kicker: "Break-even", symbol: "flag.fill", value: WidFormat.dayMonth(date),
                                   caption: WidFormat.inDays(dayCount(from: now, to: date)), isPositive: false)
        }
        if left <= 0 {
            return WidForecastInfo(kicker: "Abgelaufen", symbol: "calendar", value: WidFormat.dayMonth(s.validUntil),
                                   caption: "Folgeticket anlegen", isPositive: false)
        }
        return WidForecastInfo(kicker: "Gültig noch", symbol: "calendar", value: WidFormat.days(left),
                               caption: "bis \(WidFormat.dayMonth(s.validUntil))", isPositive: false)
    }

    /// "noch 143 Tage" · "abgelaufen"
    static func validityText(_ s: WidgetSnapshot, now: Date = Date()) -> String {
        let left = daysRemaining(s, now: now)
        return left > 0 ? "noch \(WidFormat.days(left))" : "abgelaufen"
    }

    /// VoiceOver summary for whole-widget elements.
    static func spokenSummary(_ s: WidgetSnapshot) -> String {
        var parts = ["\(WidFormat.percent(s.amortizedFraction)) amortisiert"]
        if isPaidOff(s) {
            parts.append("rentiert, \(WidFormat.euroWhole(s.net)) im Plus")
        } else {
            parts.append("noch \(WidFormat.euroWhole(s.remaining)) bis zum Break-even")
            if let date = s.forecastBreakEvenDate, date <= s.validUntil {
                parts.append("Prognose \(WidFormat.dayMonth(date))")
            }
        }
        return parts.joined(separator: ", ")
    }
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

    init(snapshot s: WidgetSnapshot, yearDays: Double = 365) {
        let price = max(s.ticketPrice, 1)
        let paidOff = WidInsight.isPaidOff(s)
        var values = s.sparkline.filter { $0.isFinite }
        if values.isEmpty { values = [0] }
        if values[0] > 0.5 { values.insert(0, at: 0) }
        if let last = values.last, abs(last - s.totalValue) > 0.5 { values.append(s.totalValue) }
        if values.count == 1 { values.append(values[0]) }

        let maxValue = max(price * 1.12, (values.max() ?? 0) * 1.04, 1)
        // Keep room on the right for the forecast segment towards the summit.
        let elapsedRaw = 1 - Double(s.daysRemaining) / yearDays
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
            let days = date.timeIntervalSince(s.generatedAt) / 86_400
            summit = elapsed + max(days, 0) / yearDays
        } else {
            summit = 0.95
        }
        if !paidOff { summit = max(summit, elapsed + 0.07) }
        summitX = CGFloat(min(max(summit, 0.04), 0.94))
    }

    /// Decorative summit without a route (empty states, quick-log backdrop).
    static let decorative = WidSummitModel(route: [], summitX: 0.74, priceLevel: 0.88, isPaidOff: false)
}
