import SwiftUI
import KlimaCore

/// Dashboard hero (spec §8.1 / §8.2): huge thin "75 %" numeral, the verdict in words ("Noch € 356 bis zum Break-even"),
/// the sub line "≈ 27 Fahrten · € 1.044 von € 1.400 amortisiert" and the `SummitChart` ("Gipfelkurs").
/// Switches to profit copy ("Rentiert seit 14. Dez. · + € 156") once the ticket has paid off.
struct AmortizationHero: View {
    var snapshot: AnalyticsSnapshot
    var chartHeight: CGFloat = 250

    @State private var shownPercent: Double = 0
    /// Spec `heroNumeral`: rounded thin, scales with Dynamic Type (clamped below).
    @ScaledMetric(relativeTo: .largeTitle) private var numeralMetric: CGFloat = 104
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summary: SavingsSummary { snapshot.summary }
    /// Read when the body runs – a stored `now = Date()` would differ on every parent update and defeat SwiftUI's diffing.
    private var now: Date { Date() }
    private var percent: Double { SummitFigures.percent(summary.amortizedFraction) }
    private var numeralSize: CGFloat { min(max(numeralMetric, 96), 140) }

    /// Ultralight like Apple Weather, but sturdier for Bold Text / Increase Contrast and glare in light mode.
    private var numeralWeight: Font.Weight {
        if legibilityWeight == .bold || contrast == .increased { return .regular }
        return colorScheme == .light ? .light : .thin
    }

    var body: some View {
        VStack(spacing: 0) {
            numeral
            verdict
                .padding(.top, 6)
                .padding(.horizontal, Theme.Spacing.screen)
            SummitChart(series: snapshot.series, forecast: snapshot.forecast, start: snapshot.ticket.start,
                        end: snapshot.ticket.end, price: snapshot.ticket.price,
                        breakEvenDate: summary.forecastBreakEvenDate, isPaidOff: summary.isPaidOff,
                        showsLabels: dynamicTypeSize < .accessibility3)
                .frame(height: chartHeight)
                // The mountain tucks a few points under the sub line (spec §5.1 heroStack).
                .padding(.top, -4)
        }
        .onAppear {
            guard shownPercent != percent else { return }
            if reduceMotion || LaunchMode.isScreenshot {
                shownPercent = percent
            } else {
                withAnimation(.spring(duration: 1.2, bounce: 0.1)) { shownPercent = percent }
            }
        }
        .onChange(of: percent) { _, new in
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.15)) { shownPercent = new }
        }
    }

    // MARK: Numeral

    /// "75" + raised "%" in one Text (shared baseline, no layout gaps). The frame is trimmed to the digits' cap height –
    /// a 104 pt line box otherwise adds ~50 pt of empty ascender/descender space to the first screen.
    private var numeral: some View {
        let size = numeralSize
        let digits = Text(Format.number(shownPercent))
            .font(.system(size: size, weight: numeralWeight, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
        let sign = Text("%")
            .font(.system(size: size * 0.385, weight: numeralWeight == .regular ? .regular : .light, design: .rounded))
            .foregroundStyle(Theme.textPrimary.opacity(0.85))
            .baselineOffset(size * 0.31)
        return Text("\(digits)\(sign)")
            .monospacedDigit()
            .contentTransition(.numericText(value: shownPercent))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.top, -size * 0.16)
            .padding(.bottom, -size * 0.18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Amortisiert")
            .accessibilityValue(Format.percent(summary.amortizedFraction))
    }

    // MARK: Verdict

    private enum Phase { case empty, climbing, behind, profit, endedProfit, endedShort }

    private var phase: Phase {
        let expired = now > snapshot.ticket.end
        if summary.isPaidOff { return expired ? .endedProfit : .profit }
        if expired { return .endedShort }
        if summary.tripCount == 0 { return .empty }
        return summary.forecastReachesBreakEven ? .climbing : .behind
    }

    private var verdict: some View {
        VStack(spacing: 1) {
            verdictLine
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(subline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Self.skyText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var verdictLine: Text {
        let remaining = Text(SummitFigures.euro(summary.shownRemainingEuro))
            .font(Self.amountFont)
            .foregroundStyle(Self.amountGradient)
        let profit = Text("+ " + SummitFigures.euro(summary.shownProfitEuro))
            .font(Self.amountFont)
            .foregroundStyle(Theme.positiveText)
        switch phase {
        case .empty:
            return Text("Erfasse deine erste Fahrt")
        case .climbing:
            return Text("Noch \(remaining) bis zum Break-even")
        case .behind:
            return Text("Noch \(remaining) · wird knapp")
        case .profit:
            if let date = summary.paidOffDate {
                return Text("Rentiert seit \(Format.dayMonth(date)) · \(profit)")
            }
            return Text("Rentiert · \(profit)")
        case .endedProfit:
            return Text("Ticketjahr beendet · \(profit)")
        case .endedShort:
            return Text("Ticketjahr beendet · \(remaining) gefehlt")
        }
    }

    private var subline: String {
        let ofPrice = "\(SummitFigures.euro(summary.shownTotalEuro)) von \(SummitFigures.euro(summary.ticketPrice))"
        switch phase {
        case .empty:
            return "Dein Gipfel: \(SummitFigures.euro(summary.ticketPrice)) – ab dann fährst du gratis"
        case .climbing, .behind:
            if let n = snapshot.tripsToBreakEven, n > 0 {
                let trips = n == 1 ? "1 Fahrt" : Format.number(Double(n)) + " Fahrten"
                return "≈ \(trips) · \(ofPrice) amortisiert"
            }
            return "\(ofPrice) amortisiert"
        case .profit:
            return "Ab jetzt fährst du gratis · \(ofPrice)"
        case .endedProfit, .endedShort:
            return "\(ofPrice) amortisiert"
        }
    }

    /// Spec `verdictAmount`: 21 pt bold rounded.
    private static let amountFont = Font.system(.title3, design: .rounded, weight: .bold)
    /// Spec `verdictAmount` gradient (text-safe in light: #1F66B8 → #5A4FC4; dark: glacier → dusk → dawn).
    private static let amountGradient = LinearGradient(
        colors: [Color(light: "#1F66B8", dark: "#7CC4FF"), Color(light: "#3D5BBF", dark: "#A99FFF"),
                 Color(light: "#5A4FC4", dark: "#FFAD85")],
        startPoint: .leading, endPoint: .trailing)
    /// Secondary copy right on the sky / sun glow: stronger than ink2 so it keeps ≥ 4.5 : 1 over the dawn glow.
    private static let skyText = Color(light: "#0C1A2BBF", dark: "#E8F1FCD6")
}

// MARK: - Whole-euro summary figures

/// Whole euros for summaries (spec §1.2) – derived from the same rounded figures everywhere, so
/// "€ 1.044 von € 1.400" and "Noch € 356" always add up, and the hero, the Bilanz card and the summit pill agree.
/// Never shows "€ 1.400 von € 1.400" (or "Noch € 0") before the break-even is actually reached.
enum SummitFigures {
    static func shownTotal(value: Double, price: Double, isPaidOff: Bool) -> Double {
        let total = max(0, value.rounded())
        let summit = price.rounded()
        if !isPaidOff, summit >= 1, total >= summit { return summit - 1 }
        return total
    }

    static func shownRemaining(value: Double, price: Double, isPaidOff: Bool) -> Double {
        guard !isPaidOff else { return 0 }
        return max(0, price.rounded() - shownTotal(value: value, price: price, isPaidOff: false))
    }

    static func shownProfit(value: Double, price: Double) -> Double {
        max(0, value.rounded() - price.rounded())
    }

    /// "€ 356"
    static func euro(_ value: Double) -> String { Format.euro(value, decimals: 0) }

    /// Spec §4.3: never "100 %" before break-even, and no rounding up past it afterwards.
    static func percent(_ fraction: Double) -> Double {
        let raw = max(0, fraction) * 100
        return fraction < 1 ? min(99, raw.rounded()) : floor(raw)
    }
}

extension SavingsSummary {
    /// "€ 1.044" in "€ 1.044 von € 1.400".
    var shownTotalEuro: Double { SummitFigures.shownTotal(value: totalValue, price: ticketPrice, isPaidOff: isPaidOff) }
    /// "€ 356" in "Noch € 356 bis zum Break-even" – always price − shown total.
    var shownRemainingEuro: Double { SummitFigures.shownRemaining(value: totalValue, price: ticketPrice, isPaidOff: isPaidOff) }
    /// "+ € 156" once paid off.
    var shownProfitEuro: Double { SummitFigures.shownProfit(value: totalValue, price: ticketPrice) }
}
