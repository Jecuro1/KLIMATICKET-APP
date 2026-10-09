import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Typography, layout & copy helpers

/// Dashboard-local numerals and layout constants. The numerals mirror the Theme number tokens
/// (34 / 22 / 20 / 15 pt Bold Rounded, monospaced digits) but are built on text styles so they follow Dynamic Type.
enum DashStyle {
    /// ≈ `Theme.Typography.numberLarge` (34 pt) – card headline figures.
    static let bigNumber = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    /// ≈ 22 pt – currency sign next to a big figure.
    static let mediumNumber = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    /// ≈ 20 pt – mini stats.
    static let statNumber = Font.system(.title3, design: .rounded, weight: .bold).monospacedDigit()
    /// ≈ 15 pt – prices in chips.
    static let smallNumber = Font.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit()

    /// Section spacing (DESIGN.md §3: 18–24) and card spacing (10–12) on the 4 pt grid.
    static let sectionSpacing: CGFloat = Theme.Spacing.l + Theme.Spacing.xxs
    static let cardSpacing: CGFloat = Theme.Spacing.s
    /// Section headers sit on the 20 pt text margin while cards use the 16 pt gutter.
    static let headerInset: CGFloat = Theme.Spacing.screen - Theme.Spacing.cardGutter

    static let weekdays: [String] = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// Calendar days between two dates (Vienna time, start of day to start of day).
    static func dayCount(from start: Date, to end: Date) -> Int {
        let cal = Calendar.vienna
        return cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
    }

    /// "heute" · "morgen" · "in 66 Tagen"
    static func inDays(_ n: Int) -> String {
        if n <= 0 { return "heute" }
        if n == 1 { return "morgen" }
        return "in \(n) Tagen"
    }

    /// "1 Fahrt" · "15 Fahrten"
    static func trips(_ n: Int) -> String {
        n == 1 ? "1 Fahrt" : "\(Format.number(Double(n))) Fahrten"
    }

    /// "+ € 370" · "– € 120"
    static func signedEuro(_ value: Double) -> String {
        let sign = value < 0 ? "–" : "+"
        return sign + " " + Format.euro(abs(value), decimals: 0)
    }

    /// "Freitag, 9. Oktober" (de-AT, "Jänner").
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Format.locale))
    }
}

// MARK: - Entrance motion

/// Staggered rise-in for dashboard sections. Settles within ~1.1 s; opacity only with Reduce Motion;
/// already in its end state in screenshot mode (the caller starts with `visible == true`).
struct DashEntrance: ViewModifier {
    var index: Int
    var visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .animation(entranceAnimation, value: visible)
    }

    private var entranceAnimation: Animation {
        if reduceMotion { return .easeOut(duration: 0.25) }
        return .spring(duration: 0.6, bounce: 0.12).delay(Double(index) * 0.06)
    }
}

extension View {
    func dashEntrance(_ index: Int, visible: Bool) -> some View {
        modifier(DashEntrance(index: index, visible: visible))
    }
}

// MARK: - Button styles

/// Gentle press-down scale for card-like buttons.
struct DashPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Row highlight for list-like rows inside a card.
struct DashRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.surfaceSecondary.opacity(configuration.isPressed ? 1 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small components

/// Neutral outline capsule with the line category ("S", "U", "Bus", "Bim") – only when it is known
/// (a train without a category gets no badge, DESIGN.md §4).
struct DashModeBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay { Capsule().strokeBorder(Theme.textTertiary, lineWidth: 1) }
            .accessibilityHidden(true)
    }

    static func label(for mode: TransportMode) -> String? {
        switch mode {
        case .sBahn: return "S"
        case .metro: return "U"
        case .bus: return "Bus"
        case .tram: return "Bim"
        default: return nil
        }
    }
}

/// Tinted status capsule inside cards ("Schneller als nötig · + € 370 vor Plan").
struct DashPill: View {
    var symbol: String
    var text: String
    /// Text-safe colour for the label (positiveText / summitText / accentText).
    var foreground: Color
    /// Accent used as a faint fill.
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Big figure with a smaller currency sign ("€ 354", "+ € 412").
struct DashEuroNumeral: View {
    var amount: Double
    var sign: String? = nil
    var color: Color = Theme.textPrimary
    var symbolColor: Color = Theme.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(symbolText)
                .font(DashStyle.mediumNumber)
                .foregroundStyle(symbolColor)
            Text(Format.number(amount))
                .font(DashStyle.bigNumber)
                .foregroundStyle(color)
                .contentTransition(.numericText(value: amount))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var symbolText: String {
        if let sign { return sign + " €" }
        return "€"
    }

    private var accessibilityText: String {
        if let sign { return sign + " " + Format.euro(amount, decimals: 0) }
        return Format.euro(amount, decimals: 0)
    }
}

// MARK: - Weekly insight model

/// Trips & value of the current week (Mon–Sun, Vienna) against the previous week.
struct DashWeekStats: Equatable {
    var trips: Int = 0
    var value: Double = 0
    var previousTrips: Int = 0
    var previousValue: Double = 0
    /// Value per weekday, Monday first.
    var dayValues: [Double] = Array(repeating: 0, count: 7)
    var previousDayValues: [Double] = Array(repeating: 0, count: 7)
    /// 0 = Monday … 6 = Sunday.
    var todayIndex: Int = 0

    var delta: Double { value - previousValue }
    var isEmpty: Bool { trips == 0 && previousTrips == 0 }

    /// `trips` may be in any order; only the last 14 days are considered.
    static func make(from trips: [TripEntity], now: Date = Date()) -> DashWeekStats {
        let cal = Calendar.vienna
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let previousStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        var stats = DashWeekStats()
        stats.todayIndex = min(6, max(0, cal.dateComponents([.day], from: weekStart, to: today).day ?? 0))
        for trip in trips where trip.deletedAt == nil && trip.date >= previousStart {
            let offset = cal.dateComponents([.day], from: previousStart, to: cal.startOfDay(for: trip.date)).day ?? -1
            if offset >= 7 && offset < 14 {
                stats.trips += 1
                stats.value += trip.totalValue
                stats.dayValues[offset - 7] += trip.totalValue
            } else if offset >= 0 && offset < 7 {
                stats.previousTrips += 1
                stats.previousValue += trip.totalValue
                stats.previousDayValues[offset] += trip.totalValue
            }
        }
        return stats
    }
}
