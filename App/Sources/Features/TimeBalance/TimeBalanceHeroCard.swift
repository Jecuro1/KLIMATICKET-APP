import SwiftUI
import KlimaCore

/// „128 Std. unterwegs“ – the one count-in of the screen, the trips and weekly average under it, and the split of the
/// time into what was recorded and what is estimated.
struct TimeBalanceHeroCard: View {
    let balance: TimeBalance
    let periodTitle: String

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let parts = TimeBalanceText.parts(balance.totalMinutes)
        GlassCard(padding: Theme.Spacing.m + 4, tint: Theme.glacier) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Kicker(text: "Unterwegs · \(periodTitle)")
                    Spacer(minLength: Theme.Spacing.xs)
                    Image(systemName: "hourglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: parts.value) { Format.number($0, decimals: parts.decimals) }
                        .font(.system(size: min(numeralSize, 120), weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(parts.unit)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.opacity)
                }
                .accessibilityHidden(true)
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                StatsGrowOnView(delay: Motion.Stagger.delay(2)) { grow in
                    TimeBalanceSplitBar(recorded: balance.recordedMinutes, estimated: balance.estimatedMinutes, grow: grow)
                        .frame(height: 14)
                }
                .padding(.top, Theme.Spacing.xxs)
                .accessibilityHidden(true)
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimeBalanceText.heroSpoken(balance))
        .accessibilityIdentifier("timeBalance.hero")
    }

    private var subline: String {
        "in Bahn, Bus & Co. · \(TimeBalanceText.trips(balance.tripCount)) · Ø \(TimeBalanceText.short(balance.averageMinutesPerWeek)) pro Woche"
    }

    // MARK: Legend

    @ViewBuilder
    private var legend: some View {
        let total = max(balance.totalMinutes, 1)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            legendRow(marker: TimeBalanceSwatch(style: .recorded), title: "Erfasst",
                      value: balance.recordedMinutes, share: balance.recordedMinutes / total,
                      detail: recordedDetail)
            legendRow(marker: TimeBalanceSwatch(style: .estimated), title: "Geschätzt",
                      value: balance.estimatedMinutes, share: balance.estimatedMinutes / total,
                      detail: balance.estimatedTripCount > 0
                          ? "\(TimeBalanceText.trips(balance.estimatedTripCount)) ohne Dauer – mit Durchschnittstempo gerechnet"
                          : "Jede Fahrt hat eine Dauer")
        }
        .accessibilityHidden(true)
    }

    private var recordedDetail: String {
        if balance.recordedMinutes <= 0 { return "Trag bei einer Fahrt die Dauer ein – dann wird es genauer" }
        var parts: [String] = []
        if balance.enteredMinutes > 0 { parts.append("eingetragen \(TimeBalanceText.short(balance.enteredMinutes))") }
        if balance.timetableMinutes > 0 { parts.append("Abfahrt & Ankunft \(TimeBalanceText.short(balance.timetableMinutes))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func legendRow(marker: TimeBalanceSwatch, title: String, value: Double, share: Double, detail: String) -> some View {
        let figure = "\(TimeBalanceText.short(value)) · \(Format.percent(share))"
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            marker
                .frame(width: 12, height: 12)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                if typeSize.isAccessibilitySize {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(figure).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(figure)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Split bar

/// Recorded (solid route gradient) and estimated (hatched) as one capsule. The hatching carries the meaning together with
/// the legend's words – never colour alone.
struct TimeBalanceSplitBar: View {
    let recorded: Double
    let estimated: Double
    var grow: Double = 1

    var body: some View {
        GeometryReader { geo in
            let total = max(recorded + estimated, 0.0001)
            let width = geo.size.width
            let recordedWidth = width * CGFloat(recorded / total)
            let gap: CGFloat = recorded > 0 && estimated > 0 ? 3 : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.textTertiary.opacity(0.14))
                HStack(spacing: gap) {
                    if recorded > 0 {
                        Capsule()
                            .fill(Theme.routeGradient)
                            .frame(width: max(0, recordedWidth - gap / 2))
                    }
                    if estimated > 0 {
                        TimeBalanceSwatch(style: .estimated, outline: .capsule)
                            .frame(width: max(0, width - recordedWidth - gap / 2))
                    }
                }
                // Grows from the leading edge once (render-only: a mask, no layout per frame).
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * CGFloat(min(max(grow, 0), 1)))
                }
            }
        }
    }
}

/// The marker of a source: solid for recorded, diagonal hatching for estimated.
struct TimeBalanceSwatch: View {
    enum Style { case recorded, estimated }
    enum Outline { case circle, capsule, bar }
    let style: Style
    var outline: Outline = .circle

    var body: some View {
        switch outline {
        case .circle: swatch(Circle())
        case .capsule: swatch(Capsule())
        case .bar: swatch(Rectangle())
        }
    }

    @ViewBuilder
    private func swatch<S: InsettableShape>(_ shape: S) -> some View {
        switch style {
        case .recorded:
            shape.fill(Theme.routeGradient)
        case .estimated:
            shape.fill(Theme.dusk.opacity(0.18))
                .overlay {
                    TimeBalanceHatch(spacing: 5)
                        .stroke(Theme.dusk.opacity(0.75), lineWidth: 1.5)
                        .clipShape(shape)
                }
                .overlay { shape.strokeBorder(Theme.dusk.opacity(0.55), lineWidth: 1) }
        }
    }
}

/// Diagonal lines across the rect (45°), `spacing` points apart.
struct TimeBalanceHatch: Shape {
    var spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(spacing, 2)
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}
