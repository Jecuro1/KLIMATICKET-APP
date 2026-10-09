import SwiftUI
import Charts
import KlimaCore

/// "Monatsbilanz": value per month across the whole ticket year – best month in dawn→dusk, the running
/// month partially filled, dashed forecast bars for the months ahead, "Ø" and "Soll" reference lines.
/// Touch and drag across the bars: the month under the finger stays lit with a callout (value, trips, forecast).
struct StatsMonthlyCard: View {
    let snapshot: AnalyticsSnapshot
    let grow: Double

    @Environment(AppState.self) private var app
    /// Month under the finger. Changes only when the finger crosses into another bar (≤ 13 per drag), never per frame.
    @State private var selectedID: String?

    private static let barRatio: Double = 0.62

    var body: some View {
        let bars = StatsCalc.monthBars(snapshot)
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header(bars)
                chart(bars)
                    .frame(height: 176)
                    .padding(.top, Theme.Spacing.xs)
                legend(bars)
            }
        }
    }

    // MARK: Header

    private func header(_ bars: [StatsMonthBar]) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Kicker(text: "Monatsbilanz")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Ø \(Format.euro(StatsCalc.averagePerMonth(snapshot), decimals: 0))")
                        .font(Theme.Typography.numberLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .numericValue(StatsCalc.averagePerMonth(snapshot).rounded())
                    Text("pro Monat")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Spacing.xs)
            if let best = bars.first(where: { $0.isBest }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BESTMONAT")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                    Text(StatsNames.wideMonth(best.month))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(Format.euro(best.actual, decimals: 0))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.summitText)
                }
                .multilineTextAlignment(.trailing)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Chart

    private func maxY(_ bars: [StatsMonthBar]) -> Double {
        let top = bars.map { $0.actual + $0.projected }.max() ?? 0
        return max(top, StatsCalc.averagePerMonth(snapshot), StatsCalc.targetPerMonth(snapshot), 10) * 1.22
    }

    private func chart(_ bars: [StatsMonthBar]) -> some View {
        Chart {
            ForEach(bars) { bar in
                barMarks(bar)
            }
            referenceRules
        }
        .chartYScale(domain: 0...maxY(bars))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let bar = bars.first(where: { $0.id == id }) {
                        Text(bar.label)
                            .font(.caption2.weight(bar.isCurrent ? .bold : .medium))
                            .foregroundStyle(bar.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: selectionBinding)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    forecastOutlines(proxy: proxy, frame: geo[anchor], bars: bars)
                }
            }
            .allowsHitTesting(false)
        }
        .motionAnimation(Motion.snappy, value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID) { _, new in
            new != nil && app.settings.hapticsEnabled && !MotionPolicy.isStatic
        }
        .accessibilityLabel("Monatsbilanz")
    }

    /// Writes only when the finger enters another bar – Charts reports the category on every touch-move frame.
    private var selectionBinding: Binding<String?> {
        Binding(get: { selectedID }, set: { new in
            guard new != selectedID else { return }
            if selectedID == nil, new != nil { KBTips.used(KBTips.ChartScrub()) }
            selectedID = new
        })
    }

    /// Actual value (stacked below) + forecast still to come (stacked on top) for one month.
    /// Kept out of the `Chart { }` closure so the type checker sees small expressions.
    @ChartContentBuilder
    private func barMarks(_ bar: StatsMonthBar) -> some ChartContent {
        let isSelected = selectedID == bar.id
        BarMark(x: .value("Monat", bar.id), y: .value("Wert", bar.actual * grow), width: .ratio(Self.barRatio))
            .cornerRadius(5)
            .foregroundStyle(style(for: bar))
            .opacity(selectedID == nil || isSelected ? 1 : 0.35)
            .annotation(position: .top, spacing: 3, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                if isSelected {
                    callout(bar)
                } else if bar.isBest {
                    bestLabel(bar)
                        .opacity(selectedID == nil ? 1 : 0)
                }
            }
            .accessibilityLabel(StatsNames.wideMonth(bar.month))
            .accessibilityValue(accessibilityValue(for: bar))
        if bar.projected > 0 {
            BarMark(x: .value("Monat", bar.id), y: .value("Wert", bar.projected * grow), width: .ratio(Self.barRatio))
                .cornerRadius(5)
                .foregroundStyle(Theme.glacier.opacity(0.10))
                .opacity(selectedID == nil || isSelected ? 1 : 0.35)
                .accessibilityLabel("\(StatsNames.wideMonth(bar.month)), Prognose")
                .accessibilityValue(Format.euro(bar.projected, decimals: 0))
        }
    }

    /// Callout over the bar under the finger: month, value, trips – and what is still expected this month.
    private func callout(_ bar: StatsMonthBar) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(StatsNames.wideMonth(bar.month).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            Text(Format.euro(bar.actual, decimals: 0))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(calloutDetail(bar))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(bar.projected > 0 ? Theme.accentText : Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .statsCalloutSurface()
        .fixedSize()
        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }

    private func calloutDetail(_ bar: StatsMonthBar) -> String {
        if bar.projected > 0 {
            return bar.isFuture ? "Prognose \(Format.euro(bar.projected, decimals: 0))"
                                : "\(StatsNames.trips(bar.trips)) · + \(Format.euro(bar.projected, decimals: 0)) erwartet"
        }
        return StatsNames.trips(bar.trips)
    }

    private func bestLabel(_ bar: StatsMonthBar) -> some View {
        Text(Format.euro(bar.actual, decimals: 0))
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.summitText)
            .fixedSize()
            .opacity(grow)
    }

    @ChartContentBuilder
    private var referenceRules: some ChartContent {
        let average = StatsCalc.averagePerMonth(snapshot)
        let target = StatsCalc.targetPerMonth(snapshot)
        RuleMark(y: .value("Durchschnitt", average))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Theme.textSecondary)
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                ruleLabel("Ø \(Format.euro(average, decimals: 0))", color: Theme.textSecondary)
            }
            .accessibilityLabel("Durchschnitt pro Monat")
            .accessibilityValue(Format.euro(average, decimals: 0))
        RuleMark(y: .value("Soll", target))
            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .foregroundStyle(Theme.summit.opacity(0.9))
            .annotation(position: .top, alignment: .trailing, spacing: 2) {
                ruleLabel("Soll \(Format.euro(target, decimals: 0))", color: Theme.summitText)
            }
            .accessibilityLabel("Soll pro Monat für den Break-even")
            .accessibilityValue(Format.euro(target, decimals: 0))
    }

    private func ruleLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.sheetBackground.opacity(0.72), in: .capsule)
            .fixedSize()
    }

    private func style(for bar: StatsMonthBar) -> AnyShapeStyle {
        if bar.isBest {
            return AnyShapeStyle(LinearGradient(colors: [Theme.dawn, Theme.dusk], startPoint: .top, endPoint: .bottom))
        }
        if bar.isCurrent {
            return AnyShapeStyle(LinearGradient(colors: [Theme.glacier, Theme.dusk.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(LinearGradient(colors: [Theme.glacier.opacity(0.85), Theme.glacier.opacity(0.42)],
                                            startPoint: .top, endPoint: .bottom))
    }

    /// Dashed outlines around the forecast part of the running and coming months.
    @ViewBuilder
    private func forecastOutlines(proxy: ChartProxy, frame: CGRect, bars: [StatsMonthBar]) -> some View {
        let band = bandWidth(proxy: proxy, frame: frame, bars: bars)
        let width = band * CGFloat(Self.barRatio)
        ForEach(bars.filter { $0.projected > 0 }) { bar in
            if let x = proxy.position(forX: bar.id),
               let top = proxy.position(forY: (bar.actual + bar.projected) * grow),
               let bottom = proxy.position(forY: bar.actual * grow), bottom - top > 1 {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.glacier.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: width, height: bottom - top)
                    .position(x: frame.minX + x, y: frame.minY + (top + bottom) / 2)
            }
        }
    }

    private func bandWidth(proxy: ChartProxy, frame: CGRect, bars: [StatsMonthBar]) -> CGFloat {
        if bars.count >= 2, let a = proxy.position(forX: bars[0].id), let b = proxy.position(forX: bars[1].id) {
            return abs(b - a)
        }
        return frame.width / CGFloat(max(bars.count, 1))
    }

    // MARK: Legend

    private func legend(_ bars: [StatsMonthBar]) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            legendSwatch(AnyShapeStyle(LinearGradient(colors: [Theme.glacier, Theme.glacier.opacity(0.5)],
                                                      startPoint: .top, endPoint: .bottom)), label: "Wert", dashed: false)
            if bars.contains(where: { $0.projected > 0 }) {
                legendSwatch(AnyShapeStyle(Theme.glacier.opacity(0.10)), label: "Prognose", dashed: true)
            }
            StatsLegendItem(label: "Schnitt", style: AnyShapeStyle(Theme.textSecondary), dashed: true)
            StatsLegendItem(label: "Soll", style: AnyShapeStyle(Theme.summit), dashed: true)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func legendSwatch(_ fill: AnyShapeStyle, label: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(fill)
                .overlay {
                    if dashed {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Theme.glacier.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .frame(width: 9, height: 12)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: Accessibility

    private func accessibilityValue(for bar: StatsMonthBar) -> String {
        var text = "\(Format.euro(bar.actual, decimals: 0)), \(StatsNames.trips(bar.trips))"
        if bar.isBest { text += ", Bestmonat" }
        if bar.isCurrent { text += ", laufender Monat" }
        return text
    }
}
