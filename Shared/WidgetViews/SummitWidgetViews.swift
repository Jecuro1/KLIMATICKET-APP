import SwiftUI
import WidgetKit
import KlimaCore

/// "Gipfel-Fortschritt": the way to the summit (the ticket price) on the lock screen and in StandBy. The small family is
/// the StandBy design: the artwork with the figures, no route and no mist while the luminance is reduced (`isLuminanceReduced`).
struct SummitWidgetView: View {
    var snapshot: WidgetSnapshot?
    var family: WidgetFamily
    var now: Date
    var margins: EdgeInsets = WidLayout.defaultMargins

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            WidEmptyView(family: family, margins: margins)
        }
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
        let paid = WidInsight.isPaidOff(s)
        switch family {
        case .systemSmall:
            ZStack(alignment: .topLeading) {
                WidSummitArt(model: WidSummitModel(snapshot: s, now: now), top: 0.6, bottom: 0.97, scale: 0.82,
                             showsRoute: !isLuminanceReduced, showsFlag: !isLuminanceReduced)
                VStack(alignment: .leading, spacing: 0) {
                    WidEyebrow(text: paid ? "Gipfel erreicht" : "Gipfel", symbol: "mountain.2.fill",
                               tint: paid ? Theme.positive : Theme.accent)
                    WidPercentNumeral(fraction: s.amortizedFraction, size: 50)
                    Text(verbatim: paid ? "+ \(WidFormat.euroWhole(WidFigures.profit(s)))" : "noch \(WidFormat.euroWhole(WidFigures.remaining(s)))")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.widSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(margins)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gipfel-Fortschritt")
            .accessibilityValue(WidInsight.spokenSummary(s, now: now))
        case .accessoryInline:
            Label("\(WidFormat.percent(s.amortizedFraction)) · \(paid ? "Gipfel erreicht" : "noch \(WidFormat.euroWhole(WidFigures.remaining(s)))")",
                  systemImage: "mountain.2.fill")
                .lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label(paid ? "Gipfel erreicht" : "Gipfel", systemImage: "mountain.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: WidFormat.percent(s.amortizedFraction))
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(verbatim: paid ? "+ \(WidFormat.euroWhole(WidFigures.profit(s)))" : "noch \(WidFormat.euroWhole(WidFigures.remaining(s)))")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                WidLinearBar(progress: s.amortizedFraction)
                    .frame(height: 5)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
