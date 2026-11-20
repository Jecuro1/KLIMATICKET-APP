import SwiftUI
import KlimaCore

// MARK: siri – what Siri shows under its sentence for „Frag KlimaBilanz“ (docs/SIRI_QUESTIONS.md §5), in the widgets' typography: the
// eyebrow with the question, the figure as a thin numeral, the days or months as bars (today's or this month's in the accent) or, for
// a ticket question, the share of the validity or of the ticket price as a bar. The same view sits in „Probier es aus“.

struct AskKlimaSnippet: View {
    var answer: KpiAnswer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch answer.status {
            case .noTable, .noTicket:
                missing
            case .figure, .empty:
                figure
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var figure: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(verbatim: answer.value ?? "–")
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.top, -4)
            if !answer.bars.isEmpty {
                AskKlimaBars(bars: answer.bars, tint: tint)
                    .id(answer.period)
            } else if let progress = answer.progress {
                VStack(alignment: .leading, spacing: 6) {
                    WidLinearBar(progress: progress, fill: answer.question == .daysLeft ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.routeGradient),
                                 track: AnyShapeStyle(Theme.textTertiary.opacity(0.35)))
                        .frame(height: 6)
                    Text(progressCaption(progress))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(answer.label)
        .accessibilityValue(answer.value ?? "")
    }

    @ViewBuilder
    private var header: some View {
        let eyebrow = WidEyebrow(text: answer.question.title, symbol: answer.question.symbol, tint: tint)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                eyebrow
                periodText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                eyebrow
                Spacer(minLength: 6)
                periodText
            }
        }
    }

    @ViewBuilder
    private var periodText: some View {
        if let period = answer.periodLabel {
            // MARK: review-siri – a text style, so it grows with the text size (12 pt stayed 12 pt at AX5)
            Text(period)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
        }
    }

    /// „73 % der Gültigkeit vorbei“ / „92 % des Ticketpreises erreicht“.
    private func progressCaption(_ progress: Double) -> String {
        let percent = WidFormat.percentValue(progress)   // the widgets' and „Ticket-Bilanz“'s rounding: never 100 % before the price
        return answer.question == .daysLeft ? "\(percent) % der Gültigkeit vorbei" : "\(percent) % des Ticketpreises erreicht"
    }

    private var tint: Color {
        switch answer.question {
        case .co2: Theme.positive
        case .net, .breakEven: Theme.summit
        default: Theme.accent
        }
    }

    /// No table yet, or a ticket question without a ticket.
    private var missing: some View {
        HStack(spacing: 12) {
            Image(systemName: answer.status == .noTicket ? "ticket" : "iphone")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(answer.status == .noTicket ? "Noch kein Ticket" : "Noch keine Zahlen")
                    .font(.headline)   // MARK: review-siri – text styles: they grow with the text size
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Öffne KlimaBilanz einmal.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Days of a week or month, months of a year: one bar each, the current one in the accent. Heights scale (a transform, not layout),
/// so a new question lets them grow in place.
struct AskKlimaBars: View {
    var bars: [KpiBar]
    var tint: Color

    private let height: CGFloat = 46

    var body: some View {
        let top = max(bars.map(\.value).max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                let fraction = bar.value > 0 ? max(0.06, bar.value / top) : 0
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Theme.textTertiary.opacity(0.22))
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(bar.isCurrent ? tint : tint.opacity(0.38))
                            .frame(height: height)
                            .scaleEffect(x: 1, y: fraction, anchor: .bottom)
                    }
                    .frame(height: height, alignment: .bottom)
                    // Centred under its own bar: the zero-width frame lets „15“ overhang a 6-pt column without widening it.
                    Text(showsLabel(index) ? bar.label : " ")
                        .font(.system(size: 10, weight: bar.isCurrent ? .bold : .medium))
                        .foregroundStyle(bar.isCurrent ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .motionAnimation(Motion.smooth, value: bars.map(\.value))   // in the app the bars grow when the question changes
        .accessibilityHidden(true)
    }

    private var spacing: CGFloat { bars.count > 14 ? 2 : 5 }

    /// Every label of a week or year; in a month the 1st, every 7th day after it and today.
    private func showsLabel(_ index: Int) -> Bool {
        bars.count <= 14 || index % 7 == 0 || bars[index].isCurrent
    }
}
