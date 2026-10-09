import SwiftUI
import SwiftData
import KlimaCore

// MARK: - Typography, layout & copy helpers

/// Dashboard-local numerals and layout constants (spec §4.1 roles), built on text styles so they follow Dynamic Type.
enum DashStyle {
    /// Spec `statL` (27 Bold Rounded) – Bilanz card values ("21. Dez.", "69"). `.title` = 28 pt.
    static let bigNumber = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    /// Spec `statUnit` (17 Bold Rounded, shown at 70 %) – "Tage" after a big value.
    static let unitNumber = Font.system(.headline, design: .rounded, weight: .bold)
    /// "€" in front of a big value – ≈ 0.63× the figure (spec §4.2).
    static let currencySign = Font.system(.headline, design: .rounded, weight: .semibold)
    /// Spec `statS` (18 Bold Rounded) – mini stats.
    static let statNumber = Font.system(.headline, design: .rounded, weight: .bold).monospacedDigit()
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

/// Big figure with a smaller, softer currency sign ("€ 356", "+ € 156", "≈ € 120") – spacing like `Format.euro`.
struct DashEuroNumeral: View {
    var amount: Double
    var sign: String? = nil
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(symbolText)
                .font(DashStyle.currencySign)
                .foregroundStyle(color.opacity(0.7))
            Text(Format.number(amount))
                .font(DashStyle.bigNumber)
                .foregroundStyle(color)
                .contentTransition(.numericText(value: amount))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var symbolText: String {
        if let sign { return sign + " €" }
        return "€"
    }

    private var accessibilityText: String {
        let euro = Format.euro(amount, decimals: 0)
        switch sign {
        case "≈"?: return "ungefähr " + euro
        case let sign?: return sign + " " + euro
        case nil: return euro
        }
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

    /// From the whole euros the card shows, so "€ 48 · Vorwoche € 23" never reads "+ € 24 vs. Vorwoche".
    var delta: Double { value.rounded() - previousValue.rounded() }
    var isEmpty: Bool { trips == 0 && previousTrips == 0 }

    /// `trips` must be sorted newest first (the dashboard's @Query): the walk stops at the first trip before the previous
    /// week, so it reads a fortnight of trips instead of the whole history on every dashboard update.
    static func make(fromNewestFirst trips: [TripEntity], now: Date = Date()) -> DashWeekStats {
        let cal = Calendar.vienna
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let previousStart = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        var stats = DashWeekStats()
        stats.todayIndex = min(6, max(0, cal.dateComponents([.day], from: weekStart, to: today).day ?? 0))
        for trip in trips {
            let date = trip.date
            guard date >= previousStart else { break }
            guard trip.deletedAt == nil else { continue }
            // Calendar days between local midnights – stays right across the DST switch (23 / 25 h days).
            let offset = cal.dateComponents([.day], from: previousStart, to: cal.startOfDay(for: date)).day ?? -1
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
