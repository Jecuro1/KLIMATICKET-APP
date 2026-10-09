import SwiftUI
import Charts
import KlimaCore

/// Hero chart "Ersparnis-Verlauf": cumulative value climbing towards the ticket price ("Gipfellinie"),
/// hatched profit zone above it, dotted forecast, break-even flag, today marker and scrubbing callout.
struct StatsSavingsCard: View {
    let snapshot: AnalyticsSnapshot
    /// 0…1 entrance progress (values grow from the baseline).
    let grow: Double

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 46
    /// Scrub position – read only by the overlay layer, so scrubbing never rebuilds this card or its chart.
    @State private var scrub = StatsChartScrub()

    private var summary: SavingsSummary { snapshot.summary }
    private var price: Double { snapshot.ticket.price }
    private var periodStart: Date { Calendar.vienna.startOfDay(for: snapshot.ticket.start) }
    private var periodEnd: Date { max(snapshot.ticket.end, periodStart.addingTimeInterval(86_400)) }
    private var isRunning: Bool { StatsCalc.isRunning(snapshot.ticket) }

    var body: some View {
        GlassCard(padding: Theme.Spacing.m + 2) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                header
                chart
                    .frame(height: 230)
                    .padding(.top, Theme.Spacing.xs)
                legend
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                Kicker(text: "Ersparnis-Verlauf")
                Spacer(minLength: Theme.Spacing.xs)
                monthPill
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("€")
                    .font(.system(size: numeralSize * 0.55, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                // Whole euros from the same rounding as the dashboard hero ("€ 1.044 von € 1.400", never
                // "€ 1.400 von € 1.400" before the break-even).
                Text(Format.number(summary.shownTotalEuro))
                    .font(.system(size: numeralSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: summary.shownTotalEuro))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("von \(SummitFigures.euro(price))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Kumulierter Wert")
            .accessibilityValue("\(SummitFigures.euro(summary.shownTotalEuro)) von \(SummitFigures.euro(price))")
            verdict
        }
    }

    @ViewBuilder
    private var monthPill: some View {
        if let value = StatsCalc.currentMonthValue(snapshot), value > 0 {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                Text("+ \(Format.euro(value, decimals: 0)) im \(StatsNames.wideMonth(Date()))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.positiveText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.positive.opacity(0.14), in: .capsule)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var verdict: some View {
        if summary.isPaidOff {
            Label {
                Text(paidOffText)
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.positiveText)
        } else if let date = summary.forecastBreakEvenDate, summary.forecastReachesBreakEven {
            Label {
                Text("Break-even voraussichtlich am \(Format.dayMonth(date))")
            } icon: {
                Image(systemName: "flag.fill").foregroundStyle(Theme.summit)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        } else if isRunning, summary.tripCount > 0 {
            Label {
                Text("Bei deinem Tempo: \(Format.euro(summary.forecastEndValue, decimals: 0)) bis Ablauf")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.summit)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.summitText)
        } else if summary.tripCount > 0, Date() > snapshot.ticket.end {
            // Expired without reaching the summit.
            Label {
                Text("Ticketjahr beendet · \(SummitFigures.euro(summary.shownRemainingEuro)) bis zum Break-even gefehlt")
            } icon: {
                Image(systemName: "flag.slash").foregroundStyle(Theme.summit)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.s) {
            StatsLegendItem(label: "Wert", style: AnyShapeStyle(lineGradient))
            if !chartForecast.isEmpty {
                StatsLegendItem(label: "Prognose", style: AnyShapeStyle(Theme.dusk), dashed: true)
            }
            StatsLegendItem(label: "Ticketpreis", style: AnyShapeStyle(Theme.summit), dashed: true)
            if showsProfitWedge {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Theme.positive.opacity(0.45))
                        .frame(width: 12, height: 10)
                    Text("Gewinn")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }

    private var showsProfitWedge: Bool {
        summary.isPaidOff || (snapshot.forecast.count > 1 && (snapshot.forecast.last?.value ?? 0) > price)
    }

    private var paidOffText: String {
        let profit = "+ \(SummitFigures.euro(summary.shownProfitEuro))"
        if let date = summary.paidOffDate { return "Rentiert seit \(Format.dayMonth(date)) · \(profit)" }
        return "Rentiert · \(profit)"
    }

    // MARK: Chart

    private var maxY: Double {
        let seriesMax = snapshot.series.map(\.value).max() ?? 0
        let forecastMax = snapshot.forecast.map(\.value).max() ?? 0
        return max(price * 1.38, seriesMax * 1.15, forecastMax * 1.15, 10)
    }

    /// The daily series with unique dates. A trip on the first ticket day repeats the start date
    /// ((start, 0) and (start, value)) – duplicate x values break `.monotone` interpolation and ForEach identity.
    private var chartSeries: [CumulativePoint] {
        var result: [CumulativePoint] = []
        result.reserveCapacity(snapshot.series.count)
        for point in snapshot.series {
            if let last = result.last, last.date == point.date {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        return result
    }

    /// Forecast segment, empty on the last ticket day (start == end would give duplicate ids).
    private var chartForecast: [CumulativePoint] {
        guard let first = snapshot.forecast.first, let last = snapshot.forecast.last, first.date < last.date else { return [] }
        return snapshot.forecast
    }

    private var chart: some View {
        // De-duplicated once per render (it was rebuilt for each of the three mark lists).
        let series = chartSeries
        return Chart {
            areaMarks(series)
            valueLineMarks(series)
            forecastMarks
            priceRule
            todayMarks
            breakEvenMarks
        }
        .chartXScale(domain: periodStart...periodEnd)
        .chartYScale(domain: 0...maxY)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .chartXSelection(value: scrub.binding)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    backgroundLayer(proxy: proxy, frame: geo[anchor])
                }
            }
        }
        .chartOverlay { proxy in
            StatsScrubLayer(proxy: proxy, scrub: scrub, value: selectionMarkerValue, markerColor: Theme.dusk,
                            hapticsEnabled: app.settings.hapticsEnabled) { date, _ in
                callout(for: date)
            }
        }
        .environment(\.calendar, Calendar.vienna)
        .accessibilityLabel("Ersparnis-Verlauf")
        .accessibilityValue(accessibilityText)
        .accessibilityHint("Zum Erkunden horizontal über das Diagramm streichen.")
    }

    private var areaGradient: LinearGradient {
        LinearGradient(colors: [Theme.glacier.opacity(0.38), Theme.glacier.opacity(0.10), Theme.glacier.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var lineGradient: LinearGradient {
        LinearGradient(colors: [Theme.glacier, Theme.dusk], startPoint: .leading, endPoint: .trailing)
    }

    /// Same colours as `lineGradient` at 20 % – built from colours instead of `LinearGradient.opacity(_:)`,
    /// which is overloaded on View and ShapeStyle.
    private var glowGradient: LinearGradient {
        LinearGradient(colors: [Theme.glacier.opacity(0.2), Theme.dusk.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
    }

    @ChartContentBuilder
    private func areaMarks(_ series: [CumulativePoint]) -> some ChartContent {
        ForEach(series) { point in
            AreaMark(x: .value("Datum", point.date), y: .value("Wert", point.value * grow))
                .interpolationMethod(.monotone)
                .foregroundStyle(areaGradient)
        }
    }

    @ChartContentBuilder
    private func valueLineMarks(_ series: [CumulativePoint]) -> some ChartContent {
        // Soft glow under the route (like the summit chart on the dashboard).
        ForEach(series) { point in
            LineMark(x: .value("Datum", point.date), y: .value("Wert", point.value * grow), series: .value("Reihe", "Glanz"))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .foregroundStyle(glowGradient)
                .accessibilityHidden(true)
        }
        ForEach(series) { point in
            LineMark(x: .value("Datum", point.date), y: .value("Wert", point.value * grow), series: .value("Reihe", "Wert"))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineGradient)
        }
    }

    @ChartContentBuilder
    private var forecastMarks: some ChartContent {
        ForEach(chartForecast) { point in
            LineMark(x: .value("Datum", point.date), y: .value("Wert", point.value * grow), series: .value("Reihe", "Prognose"))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                .foregroundStyle(Theme.dusk.opacity(0.9))
        }
        if let last = chartForecast.last {
            PointMark(x: .value("Datum", last.date), y: .value("Wert", last.value * grow))
                .symbolSize(28)
                .foregroundStyle(Theme.dusk)
                .annotation(position: .topLeading, spacing: 2) {
                    StatsScrubFade(scrub: scrub, opacity: grow) {
                        Text("Prognose \(Format.euro(last.value, decimals: 0))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
        }
    }

    @ChartContentBuilder
    private var priceRule: some ChartContent {
        RuleMark(y: .value("Ticketpreis", price))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(Theme.summit)
            .annotation(position: .top, alignment: .leading, spacing: 3) {
                Text("Ticketpreis \(Format.euro(price))")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.summitText)
            }
    }

    @ChartContentBuilder
    private var todayMarks: some ChartContent {
        if isRunning, let today = snapshot.series.last {
            RuleMark(x: .value("Heute", today.date), yStart: .value("Wert", 0.0), yEnd: .value("Wert", today.value * grow))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Theme.dusk.opacity(0.35))
            PointMark(x: .value("Heute", today.date), y: .value("Wert", today.value * grow))
                .symbol {
                    Circle()
                        .fill(Theme.onAccent)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.dusk, lineWidth: 3))
                        .background(Circle().fill(Theme.dusk.opacity(0.25)).frame(width: 26, height: 26))
                }
                .annotation(position: .bottomTrailing, spacing: 6) {
                    StatsScrubFade(scrub: scrub) {
                        Text("HEUTE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
        }
    }

    @ChartContentBuilder
    private var breakEvenMarks: some ChartContent {
        if let day = StatsCalc.breakEvenDay(snapshot) {
            PointMark(x: .value("Break-even", day), y: .value("Wert", price * grow))
                .symbol {
                    Circle()
                        .fill(Theme.summit)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.onAccent, lineWidth: 2))
                }
                .annotation(position: .top, spacing: 8) {
                    StatsScrubFade(scrub: scrub, opacity: grow) {
                        flagPill(day)
                    }
                }
        }
    }

    private func flagPill(_ day: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.summit)
            Text(Format.dayMonth(day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Axes

    private var xAxis: some AxisContent {
        AxisMarks(values: .stride(by: .month)) { value in
            AxisValueLabel(centered: true) {
                if let date = value.as(Date.self) {
                    let current = isCurrentMonth(date)
                    Text(typeSize > .large ? StatsNames.narrowMonth(date) : StatsNames.shortMonth(date))
                        .font(.caption2.weight(current ? .bold : .medium))
                        .foregroundStyle(current ? Theme.textPrimary : Theme.textSecondary)
                }
            }
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Theme.separator)
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(Format.euro(amount, decimals: 0))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        isRunning && Calendar.vienna.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    // MARK: Background – profit zone + pine profit wedge

    private func backgroundLayer(proxy: ChartProxy, frame: CGRect) -> some View {
        let priceY = min(max(proxy.position(forY: price) ?? 0, 0), frame.height)
        return ZStack(alignment: .topLeading) {
            HatchShape(spacing: 7)
                .stroke(Theme.positive.opacity(0.16), lineWidth: 1)
                .background(Theme.positive.opacity(0.05))
                .frame(width: frame.width, height: priceY)
                .clipped()
                .mask {
                    LinearGradient(colors: [Color.black.opacity(0.15), Color.black], startPoint: .top, endPoint: .bottom)
                }
                .offset(x: frame.minX, y: frame.minY)
            if priceY > 34 {
                Text("GEWINNZONE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Theme.positiveText)
                    .offset(x: frame.minX + 8, y: frame.minY + 6)
            }
            wedgePath(proxy: proxy)
                .fill(LinearGradient(colors: [Theme.positive.opacity(0.42), Theme.positive.opacity(0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(x: frame.minX, y: frame.minY)
            forecastProfitLabel(proxy: proxy, frame: frame, priceY: priceY)
        }
        .opacity(grow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func forecastProfitLabel(proxy: ChartProxy, frame: CGRect, priceY: CGFloat) -> some View {
        if let last = snapshot.forecast.last, snapshot.forecast.count > 1, last.value > price,
           let x = proxy.position(forX: last.date) {
            Text("+ \(Format.euro(last.value - price, decimals: 0))")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.positiveText)
                .frame(width: 110, alignment: .trailing)
                .position(x: frame.minX + x - 57, y: frame.minY + priceY + 11)
        }
    }

    /// Polygons between the ticket-price line and the value/forecast line wherever the value is above the price.
    private func wedgePath(proxy: ChartProxy) -> Path {
        var path = Path()
        for polygon in wedgePolygons() {
            guard let first = polygon.first, let last = polygon.last,
                  let x0 = proxy.position(forX: first.date), let x1 = proxy.position(forX: last.date),
                  let base = proxy.position(forY: price * grow) else { continue }
            path.move(to: CGPoint(x: x0, y: base))
            for point in polygon {
                if let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value * grow) {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.addLine(to: CGPoint(x: x1, y: base))
            path.closeSubpath()
        }
        return path
    }

    private func wedgePolygons() -> [[CumulativePoint]] {
        var result: [[CumulativePoint]] = []
        // Actual series above the price (after break-even).
        if summary.isPaidOff, let index = snapshot.series.firstIndex(where: { $0.value >= price }) {
            var polygon: [CumulativePoint] = []
            if index > 0 {
                polygon.append(crossing(from: snapshot.series[index - 1], to: snapshot.series[index]))
            }
            polygon.append(contentsOf: snapshot.series[index...])
            if polygon.count > 1 { result.append(polygon) }
        }
        // Forecast above the price.
        if snapshot.forecast.count > 1, let a = snapshot.forecast.first, let b = snapshot.forecast.last, b.value > price {
            let startPoint = a.value >= price ? a : crossing(from: a, to: b)
            result.append([startPoint, b])
        }
        return result
    }

    private func crossing(from a: CumulativePoint, to b: CumulativePoint) -> CumulativePoint {
        guard b.value > a.value else { return b }
        let t = min(max((price - a.value) / (b.value - a.value), 0), 1)
        let date = a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * t)
        return CumulativePoint(date: date, value: price)
    }

    // MARK: Scrubbing

    /// Value at the selected date: actual up to today, forecast afterwards.
    private func selectionMarkerValue(_ date: Date) -> Double? {
        if let last = snapshot.series.last, date > last.date.addingTimeInterval(86_400) {
            guard let forecast = StatsCalc.forecastValue(at: date, in: snapshot.forecast) else { return nil }
            return forecast * grow
        }
        return StatsCalc.value(at: date, in: snapshot.series) * grow
    }

    private func callout(for date: Date) -> some View {
        let isForecast = (snapshot.series.last.map { date > $0.date.addingTimeInterval(86_400) } ?? false)
        let value = isForecast ? (StatsCalc.forecastValue(at: date, in: snapshot.forecast) ?? 0)
                               : StatsCalc.value(at: date, in: snapshot.series)
        let share = Format.percent(price > 0 ? value / price : 0)
        return VStack(alignment: .leading, spacing: 2) {
            Text(isForecast ? "PROGNOSE · \(Format.dayMonth(date))" : Format.weekdayDayMonth(date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(Format.euro(value, decimals: 0))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("\(share) amortisiert")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(value >= price ? Theme.positiveText : Theme.accentText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .statsCalloutSurface()
        .accessibilityElement(children: .combine)
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        var parts = ["\(SummitFigures.euro(summary.shownTotalEuro)) von \(SummitFigures.euro(price)) amortisiert, \(Format.percent(summary.amortizedFraction))"]
        if summary.isPaidOff {
            parts.append(paidOffText)
        } else if let date = summary.forecastBreakEvenDate, summary.forecastReachesBreakEven {
            parts.append("Break-even voraussichtlich am \(Format.dayMonth(date))")
        }
        if let last = snapshot.forecast.last, snapshot.forecast.count > 1 {
            parts.append("Prognose bis Ablauf \(Format.euro(last.value, decimals: 0))")
        }
        return parts.joined(separator: ". ")
    }
}
