import SwiftUI
import Charts
import KlimaCore

/// "Kosten-Verlauf": the car's cumulative cost climbs with every trip (plus prorated fixed costs), the KlimaTicket
/// stays flat at the own share. The pine wedge above the ticket line is money saved; flag = break-even vs. the car.
struct WorkCarChart: View {
    enum Style { case full, compact }

    let result: CarComparisonResult
    let period: TicketPeriod
    var style: Style = .full
    /// 0…1 entrance progress (values grow from the baseline).
    var grow: Double = 1

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?

    private var start: Date { Calendar.vienna.startOfDay(for: period.start) }
    private var end: Date { max(period.end, start.addingTimeInterval(86_400)) }
    private var ticket: Double { result.ticketCost }
    private var isFull: Bool { style == .full }
    private var isRunning: Bool { StatsCalc.isRunning(period) }

    private var maxY: Double {
        let current = result.series.last?.value ?? 0
        // The compact card draws no forecast – scaling for it would squash the actual line into the bottom half.
        let forecast = isFull ? (result.forecast.last?.value ?? 0) : 0
        return max(ticket * (isFull ? 1.32 : 1.15), current * (isFull ? 1.12 : 1.08), forecast * 1.08, 10)
    }

    /// The car ends above the ticket line (actual or forecast) – the right side below the line is free for labels.
    private var carEndsAboveTicket: Bool {
        (result.forecast.last?.value ?? result.series.last?.value ?? 0) > ticket
    }

    var body: some View {
        chartWithAxes
            .chartXScale(domain: start...end, range: .plotDimension(startPadding: 0, endPadding: isFull ? 8 : 6))
            .chartYScale(domain: 0...maxY)
            .chartLegend(.hidden)
            .chartXSelection(value: isFull ? $selectedDate : .constant(nil))
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let anchor = proxy.plotFrame {
                        wedgeLayer(proxy: proxy, frame: geo[anchor])
                    }
                }
            }
            .environment(\.calendar, Calendar.vienna)
            .sensoryFeedback(.selection, trigger: selectedDay) { _, new in new != nil && app.settings.hapticsEnabled }
            .accessibilityLabel("Kosten-Verlauf Auto gegen KlimaTicket")
            .accessibilityValue(accessibilityText)
            .accessibilityHint(isFull ? "Zum Erkunden horizontal über das Diagramm streichen." : "")
    }

    @ViewBuilder
    private var chartWithAxes: some View {
        if isFull {
            chart
                .chartXAxis { xAxis }
                .chartYAxis { yAxis }
        } else {
            chart
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }

    private var chart: some View {
        Chart {
            carAreaMarks
            carLineMarks
            forecastMarks
            ticketRule
            todayMarks
            breakEvenMarks
            selectionMarks
        }
    }

    // MARK: Styles

    private var carGradient: LinearGradient {
        LinearGradient(colors: [Theme.dawn, Theme.alpenglow], startPoint: .leading, endPoint: .trailing)
    }

    private var carArea: LinearGradient {
        LinearGradient(colors: [Theme.dawn.opacity(isFull ? 0.26 : 0.22), Theme.dawn.opacity(0.06), Theme.dawn.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Marks

    @ChartContentBuilder
    private var carAreaMarks: some ChartContent {
        ForEach(result.series) { point in
            AreaMark(x: .value("Datum", point.date), y: .value("Auto", point.value * grow))
                .interpolationMethod(.linear)
                .foregroundStyle(carArea)
                .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    private var carLineMarks: some ChartContent {
        ForEach(result.series) { point in
            LineMark(x: .value("Datum", point.date), y: .value("Auto", point.value * grow), series: .value("Reihe", "Auto"))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: isFull ? 3 : 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(carGradient)
        }
    }

    @ChartContentBuilder
    private var forecastMarks: some ChartContent {
        if isFull, result.forecast.count == 2 {
            ForEach(result.forecast) { point in
                LineMark(x: .value("Datum", point.date), y: .value("Auto", point.value * grow), series: .value("Reihe", "Prognose"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                    .foregroundStyle(Theme.alpenglow.opacity(0.85))
            }
            if let last = result.forecast.last {
                PointMark(x: .value("Datum", last.date), y: .value("Auto", last.value * grow))
                    .symbolSize(26)
                    .foregroundStyle(Theme.alpenglow)
                    .annotation(position: .topLeading, spacing: 2) {
                        Text("Prognose \(Format.euro(last.value, decimals: 0))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .opacity(selectedDate == nil ? grow : 0)
                    }
            }
        }
    }

    @ChartContentBuilder
    private var ticketRule: some ChartContent {
        RuleMark(y: .value("KlimaTicket", ticket))
            .lineStyle(StrokeStyle(lineWidth: isFull ? 2.5 : 2, lineCap: .round))
            .foregroundStyle(Theme.glacier)
            // Label where the car line is not: top-left while the car is still below the ticket, otherwise bottom-right
            // (the car has climbed past the ticket there and the break-even flag sits top-left of its point).
            .annotation(position: carEndsAboveTicket ? .bottom : .top, alignment: carEndsAboveTicket ? .trailing : .leading, spacing: 4) {
                if isFull {
                    Text("KlimaTicket \(Format.euro(ticket, decimals: 0))")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentText)
                        .opacity(selectedDate == nil ? 1 : 0)
                }
            }
    }

    @ChartContentBuilder
    private var todayMarks: some ChartContent {
        if let today = result.series.last, result.series.count > 1 {
            PointMark(x: .value("Heute", today.date), y: .value("Auto", today.value * grow))
                .symbol {
                    Circle()
                        .fill(Theme.onAccent)
                        .frame(width: isFull ? 12 : 9, height: isFull ? 12 : 9)
                        .overlay(Circle().stroke(Theme.dawn, lineWidth: isFull ? 3 : 2.5))
                        .background(Circle().fill(Theme.dawn.opacity(0.25)).frame(width: isFull ? 26 : 18, height: isFull ? 26 : 18))
                }
                .annotation(position: today.value > ticket * 0.9 ? .bottomTrailing : .topTrailing, spacing: 6) {
                    if isFull, isRunning {
                        Text("HEUTE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textSecondary)
                            .opacity(selectedDate == nil ? 1 : 0)
                    }
                }
        }
    }

    @ChartContentBuilder
    private var breakEvenMarks: some ChartContent {
        if let day = result.breakEvenDate {
            PointMark(x: .value("Break-even", day), y: .value("KlimaTicket", ticket * grow))
                .symbol {
                    Circle()
                        .fill(Theme.positive)
                        .frame(width: isFull ? 12 : 8, height: isFull ? 12 : 8)
                        .overlay(Circle().stroke(Theme.onAccent, lineWidth: 2))
                }
                .annotation(position: .topLeading, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    if isFull { flagPill(day, isForecast: false).opacity(selectedDate == nil ? grow : 0) }
                }
        } else if isFull, let day = result.forecastBreakEvenDate {
            PointMark(x: .value("Break-even", day), y: .value("KlimaTicket", ticket * grow))
                .symbol {
                    Circle()
                        .strokeBorder(Theme.positive, lineWidth: 2.5)
                        .background(Circle().fill(Theme.onAccent))
                        .frame(width: 12, height: 12)
                }
                .annotation(position: .topLeading, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    flagPill(day, isForecast: true).opacity(selectedDate == nil ? grow : 0)
                }
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if isFull, let selectedDate, let car = carValue(at: selectedDate) {
            RuleMark(x: .value("Auswahl", selectedDate))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    callout(date: selectedDate, car: car)
                }
            PointMark(x: .value("Auswahl", selectedDate), y: .value("Auto", car * grow))
                .symbolSize(70)
                .foregroundStyle(Theme.dawn)
        }
    }

    private func flagPill(_ day: Date, isForecast: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.positive)
            Text(isForecast ? "ab \(Format.dayMonth(day))" : Format.dayMonth(day))
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
                    let current = isRunning && Calendar.vienna.isDate(date, equalTo: Date(), toGranularity: .month)
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

    // MARK: Savings wedge (between the ticket line and the car line, wherever the car is more expensive)

    private func wedgeLayer(proxy: ChartProxy, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            wedgePath(points: actualWedge, proxy: proxy)
                .fill(LinearGradient(colors: [Theme.positive.opacity(0.42), Theme.positive.opacity(0.12)],
                                     startPoint: .top, endPoint: .bottom))
            wedgePath(points: forecastWedge, proxy: proxy)
                .fill(Theme.positive.opacity(0.10))
            if isFull { savingsLabel(proxy: proxy) }
        }
        .offset(x: frame.minX, y: frame.minY)
        .opacity(grow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Actual series from the crossing on.
    private var actualWedge: [CarCostPoint] {
        guard let index = result.series.firstIndex(where: { $0.value >= ticket }) else { return [] }
        var polygon: [CarCostPoint] = []
        if index > 0 { polygon.append(crossing(result.series[index - 1], result.series[index])) }
        polygon.append(contentsOf: result.series[index...])
        return polygon.count > 1 ? polygon : []
    }

    private var forecastWedge: [CarCostPoint] {
        guard isFull, result.forecast.count == 2, let a = result.forecast.first, let b = result.forecast.last, b.value > ticket else { return [] }
        return [a.value >= ticket ? a : crossing(a, b), b]
    }

    private func crossing(_ a: CarCostPoint, _ b: CarCostPoint) -> CarCostPoint {
        guard b.value > a.value else { return b }
        let t = min(max((ticket - a.value) / (b.value - a.value), 0), 1)
        return CarCostPoint(date: a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * t), value: ticket)
    }

    private func wedgePath(points: [CarCostPoint], proxy: ChartProxy) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last,
              let x0 = proxy.position(forX: first.date), let x1 = proxy.position(forX: last.date),
              let base = proxy.position(forY: ticket * grow) else { return path }
        path.move(to: CGPoint(x: x0, y: base))
        for point in points {
            if let x = proxy.position(forX: point.date), let y = proxy.position(forY: point.value * grow) {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.addLine(to: CGPoint(x: x1, y: base))
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    private func savingsLabel(proxy: ChartProxy) -> some View {
        if result.savings > 0, let today = result.series.last, let first = actualWedge.first,
           let x0 = proxy.position(forX: first.date), let x1 = proxy.position(forX: today.date),
           let yTop = proxy.position(forY: today.value * grow), let yBase = proxy.position(forY: ticket * grow),
           x1 - x0 > 70, yBase - yTop > 30 {
            Text("+ \(Format.euro(result.savings, decimals: 0))")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.positiveText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.positive.opacity(0.16), in: .capsule)
                .fixedSize()
                .position(x: x0 + (x1 - x0) * 0.72, y: yBase - (yBase - yTop) * 0.32)
                .opacity(selectedDate == nil ? 1 : 0)
        }
    }

    // MARK: Scrubbing

    private var selectedDay: Date? { selectedDate.map { Calendar.vienna.startOfDay(for: $0) } }

    /// Actual value up to today, forecast afterwards.
    private func carValue(at date: Date) -> Double? {
        guard let last = result.series.last else { return nil }
        if date > last.date {
            guard let a = result.forecast.first, let b = result.forecast.last, b.date > a.date else { return nil }
            let t = min(1, max(0, date.timeIntervalSince(a.date) / b.date.timeIntervalSince(a.date)))
            return a.value + (b.value - a.value) * t
        }
        var value = 0.0
        for point in result.series {
            if point.date <= date { value = point.value } else { break }
        }
        return value
    }

    private func callout(date: Date, car: Double) -> some View {
        let isForecast = (result.series.last.map { date > $0.date } ?? false)
        let difference = car - ticket
        return VStack(alignment: .leading, spacing: 3) {
            Text(isForecast ? "PROGNOSE · \(Format.dayMonth(date))" : Format.weekdayDayMonth(date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 5) {
                Image(systemName: "car.fill").font(.caption2.weight(.bold)).foregroundStyle(Theme.dawn)
                Text(Format.euro(car, decimals: 0))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(difference >= 0 ? "+ \(Format.euro(difference, decimals: 0)) gespart" : "noch \(Format.euro(-difference, decimals: 0)) bis zum Ticket")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(difference >= 0 ? Theme.positiveText : Theme.summitText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frostedCard(cornerRadius: 14)
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        var parts = ["Mit dem Auto bisher \(Format.euro(result.carCost, decimals: 0)), dein KlimaTicket \(Format.euro(ticket, decimals: 0))"]
        if let day = result.breakEvenDate {
            parts.append("Günstiger als das Auto seit \(Format.dayMonth(day)), \(Format.euro(result.savings, decimals: 0)) gespart")
        } else if let day = result.forecastBreakEvenDate {
            parts.append("Voraussichtlich günstiger als das Auto ab \(Format.dayMonth(day))")
        }
        if let last = result.forecast.last, result.forecast.count == 2 {
            parts.append("Prognose bis Ablauf: Auto \(Format.euro(last.value, decimals: 0))")
        }
        return parts.joined(separator: ". ")
    }
}
