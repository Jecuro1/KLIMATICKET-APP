import SwiftUI
import KlimaCore

/// Dashboard hero: huge thin "73 %" numeral, "€ 946 von € 1.400 amortisiert" and the summit chart.
/// When paid off it switches to "+ € 412 im Plus" with a seal.
struct AmortizationHero: View {
    var snapshot: AnalyticsSnapshot
    var chartHeight: CGFloat = 250

    @State private var shownPercent: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    /// Ultralight like Apple Weather, but sturdier for Bold Text / Increase Contrast and glare in light mode.
    private var numeralWeight: Font.Weight {
        if legibilityWeight == .bold || contrast == .increased { return .regular }
        return colorScheme == .light ? .light : .thin
    }

    private var summary: SavingsSummary { snapshot.summary }
    private var percent: Double { (summary.amortizedFraction * 100).rounded() }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            numeral
            caption
            SummitChart(series: snapshot.series, forecast: snapshot.forecast, start: snapshot.ticket.start,
                        end: snapshot.ticket.end, price: snapshot.ticket.price,
                        breakEvenDate: summary.forecastBreakEvenDate, isPaidOff: summary.isPaidOff)
                .frame(height: chartHeight)
                .padding(.top, Theme.Spacing.s)
        }
        .onAppear {
            if reduceMotion || LaunchMode.isScreenshot {
                shownPercent = percent
            } else {
                withAnimation(.spring(duration: 1.2, bounce: 0.1)) { shownPercent = percent }
            }
        }
        .onChange(of: percent) { _, new in
            withAnimation(.spring(duration: 0.8)) { shownPercent = new }
        }
    }

    private var numeral: some View {
        HStack(alignment: .top, spacing: 2) {
            Text(Format.number(shownPercent))
                .font(.system(size: 96, weight: numeralWeight, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(value: shownPercent))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("%")
                .font(.system(size: 40, weight: .light, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amortisiert")
        .accessibilityValue(Format.percent(summary.amortizedFraction))
    }

    /// Verdict in words + the numbers behind it.
    @ViewBuilder
    private var caption: some View {
        VStack(spacing: 4) {
            if summary.isPaidOff {
                Label {
                    Text(summary.paidOffDate.map { "Rentiert seit \(Format.dayMonth($0))" } ?? "Rentiert")
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                Text("\(Text("+ \(Format.euro(summary.net))").foregroundStyle(Theme.positiveText).fontWeight(.semibold)) gespart · \(Format.euro(summary.totalValue)) Wert")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Noch \(Text(Format.euro(summary.remainingToBreakEven)).foregroundStyle(Theme.accentText).fontWeight(.bold)) bis zum Break-even")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Format.euro(summary.totalValue)) von \(Format.euro(summary.ticketPrice)) amortisiert")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
