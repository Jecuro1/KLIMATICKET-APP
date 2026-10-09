import SwiftUI
import KlimaCore

/// Dashboard hero: huge thin "73 %" numeral, "€ 946 von € 1.400 amortisiert" and the summit chart.
/// When paid off it switches to "+ € 412 im Plus" with a seal.
struct AmortizationHero: View {
    var snapshot: AnalyticsSnapshot
    var chartHeight: CGFloat = 250

    @State private var shownPercent: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .font(Theme.Typography.hero)
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

    @ViewBuilder
    private var caption: some View {
        if summary.isPaidOff {
            Label {
                Text("Rentiert · \(Format.euro(summary.net)) im Plus")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        } else {
            Text("\(Text(Format.euro(summary.totalValue)).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)) von \(Format.euro(summary.ticketPrice)) amortisiert")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
