import SwiftUI
import KlimaCore

/// Hours per week, the last 12 weeks: recorded (solid) under estimated (hatched), weeks outside the chosen period faint,
/// the period's weekly average as a dashed line. Drawn by hand (12 bars) so the hatching matches the hero's split bar;
/// VoiceOver gets the data as an audio graph (`TimeBalanceWeeksDescriptor`).
struct TimeBalanceWeekChartCard: View {
    let balance: TimeBalance

    @State private var selectedWeek: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                StatsCardHeader(kicker: "Pro Woche", title: "Die letzten 12 Wochen") {
                    averagePill
                }
                StatsGrowOnView(delay: Motion.Stagger.delay(5)) { grow in
                    TimeBalanceWeekBars(weeks: balance.weeks, averageHours: averageHours, selected: selectedWeek, grow: grow) { week in
                        withMotion(Motion.snappy) { selectedWeek = selectedWeek == week ? nil : week }
                    }
                    .frame(height: min(chartHeight, 240))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stunden pro Woche, die letzten 12 Wochen")
                .accessibilityValue(TimeBalanceWeeksDescriptor.summary(balance))
                .accessibilityChartDescriptor(TimeBalanceWeeksDescriptor(balance: balance))
                caption
                legend
            }
        }
        .haptic(.selection, trigger: selectedWeek)
        .accessibilityIdentifier("timeBalance.weeks")
    }

    private var averageHours: Double { balance.averageMinutesPerWeek / 60 }

    private var averagePill: some View {
        Text("Ø \(TimeBalanceText.short(balance.averageMinutesPerWeek))")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.surfaceSecondary, in: .capsule)
            .contentTransition(.numericText())
            .accessibilityLabel("Durchschnitt \(TimeBalanceText.spoken(balance.averageMinutesPerWeek)) pro Woche")
    }

    /// The tapped week, or what the faint bars and the dashed line mean. Both lines stay laid out, so the card keeps its height.
    private var caption: some View {
        let week = balance.weeks.first { $0.start == selectedWeek }
        return ZStack(alignment: .topLeading) {
            Text(defaultCaption)
                .foregroundStyle(Theme.textSecondary)
                .opacity(week == nil ? 1 : 0)
            Text(week.map(weekText) ?? " ")
                .foregroundStyle(Theme.textPrimary)
                .opacity(week == nil ? 0 : 1)
        }
        .font(.footnote)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    private var defaultCaption: String {
        var text = "Gestrichelt: dein Schnitt im Zeitraum. Tipp auf eine Woche für Details."
        if balance.weeks.contains(where: { !$0.isInRange }) { text = "Blasse Wochen liegen außerhalb des Zeitraums. " + text }
        return text
    }

    private func weekText(_ week: TimeBalanceWeek) -> String {
        let head = "Woche ab \(Format.weekdayDayMonth(week.start)): \(TimeBalanceText.short(week.minutes))"
        guard week.minutes > 0 else { return head + " – keine Fahrt" }
        return head + " · erfasst \(TimeBalanceText.short(week.recordedMinutes)), geschätzt \(TimeBalanceText.short(week.estimatedMinutes))"
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.m) {
            legendItem(TimeBalanceSwatch(style: .recorded), "Erfasst")
            legendItem(TimeBalanceSwatch(style: .estimated), "Geschätzt")
            HStack(spacing: 5) {
                Rectangle()
                    .fill(Theme.textSecondary)
                    .frame(width: 14, height: 1.5)
                    .mask(HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Rectangle() } })
                Text("Schnitt")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ swatch: TimeBalanceSwatch, _ title: String) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// The 12 bars, the dashed average and the date labels.
private struct TimeBalanceWeekBars: View {
    let weeks: [TimeBalanceWeek]
    let averageHours: Double
    let selected: Date?
    let grow: Double
    let onSelect: (Date) -> Void

    private let labelHeight: CGFloat = 18

    var body: some View {
        let top = max((weeks.map(\.minutes).max() ?? 0) / 60, averageHours, 0.5) * 1.12
        GeometryReader { geo in
            let plot = max(1, geo.size.height - labelHeight)
            ZStack(alignment: .topLeading) {
                // Baseline.
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .offset(y: plot)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                        column(week, index: index, plot: plot, top: top)
                    }
                }
                if averageHours > 0 {
                    dashedLine(width: geo.size.width)
                        .offset(y: plot - plot * CGFloat(averageHours / top))
                        .opacity(grow)
                }
            }
        }
    }

    private func column(_ week: TimeBalanceWeek, index: Int, plot: CGFloat, top: Double) -> some View {
        let recorded = plot * CGFloat(week.recordedMinutes / 60 / top)
        let estimated = plot * CGFloat(week.estimatedMinutes / 60 / top)
        let isSelected = selected == week.start
        let dims = selected != nil && !isSelected
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if estimated > 0.5 {
                    TimeBalanceSwatch(style: .estimated, outline: .bar)
                        .frame(height: estimated)
                }
                if recorded > 0.5 {
                    Rectangle()
                        .fill(Theme.routeGradient)
                        .frame(height: recorded)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 2, bottomTrailingRadius: 2,
                                              topTrailingRadius: 5, style: .continuous))
            .overlay(alignment: .top) {
                if week.isCurrent {
                    Circle()
                        .fill(Theme.dawn)
                        .frame(width: 6, height: 6)
                        .offset(y: -10)
                }
            }
            .scaleEffect(x: 1, y: CGFloat(min(max(grow, 0), 1)), anchor: .bottom)
            .frame(height: plot, alignment: .bottom)
            Text(label(week, index: index))
                .font(.system(size: 10, weight: week.isCurrent ? .bold : .medium))
                .foregroundStyle(week.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 8, height: labelHeight)   // centred under the bar, allowed to overflow its narrow column
        }
        .frame(maxWidth: .infinity)
        .opacity(week.isInRange ? (dims ? 0.45 : 1) : (dims ? 0.2 : 0.35))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(week.start) }
    }

    /// Every third week from the newest backwards, and „jetzt“ under the current one.
    private func label(_ week: TimeBalanceWeek, index: Int) -> String {
        if week.isCurrent { return "jetzt" }
        return (weeks.count - 1 - index) % 3 == 0 ? Format.dayMonth(week.start) : ""
    }

    private func dashedLine(width: CGFloat) -> some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
        }
        .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        .frame(height: 1)
    }
}

/// The weekly hours as data for VoiceOver's audio graph.
struct TimeBalanceWeeksDescriptor: AXChartDescriptorRepresentable {
    let balance: TimeBalance

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = balance.weeks.map { Format.dayMonth($0.start) }
        let top = max((balance.weeks.map(\.minutes).max() ?? 0) / 60, 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Woche ab", categoryOrder: labels)
        let yAxis = AXNumericDataAxisDescriptor(title: "Stunden", range: 0...top, gridlinePositions: []) { value in
            TimeBalanceText.spoken(value * 60)
        }
        var recorded: [AXDataPoint] = []
        var estimated: [AXDataPoint] = []
        for (week, label) in zip(balance.weeks, labels) {
            let r: Double = week.recordedMinutes / 60
            let e: Double = week.estimatedMinutes / 60
            recorded.append(AXDataPoint(x: label, y: r))
            estimated.append(AXDataPoint(x: label, y: e))
        }
        return AXChartDescriptor(title: "Stunden pro Woche", summary: Self.summary(balance), xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [],
                                 series: [AXDataSeriesDescriptor(name: "Erfasst", isContinuous: false, dataPoints: recorded),
                                          AXDataSeriesDescriptor(name: "Geschätzt", isContinuous: false, dataPoints: estimated)])
    }

    static func summary(_ balance: TimeBalance) -> String {
        let busiest = balance.weeks.max { $0.minutes < $1.minutes }
        var text = "Im Schnitt \(TimeBalanceText.spoken(balance.averageMinutesPerWeek)) pro Woche im Zeitraum"
        if let busiest, busiest.minutes > 0 {
            text += ". Am meisten in der Woche ab \(Format.dayMonth(busiest.start)): \(TimeBalanceText.spoken(busiest.minutes))"
        }
        return text + "."
    }
}
