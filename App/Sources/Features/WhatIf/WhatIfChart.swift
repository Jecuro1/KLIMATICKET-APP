import SwiftUI
import Charts
import Accessibility
import KlimaCore

/// The 12-month cost chart: single tickets climb with every trip, the best ticket is paid at once (and climbs only with the
/// trips it does not cover). Where they meet is the break-even, drawn as a flag. The chart is redrawn on every frame of a
/// slider drag – no implicit animation, no scrub layer, 26 points.
struct WhatIfChart: View {
    let result: WhatIfResult

    @Environment(\.dynamicTypeSize) private var typeSize

    private var best: WhatIfOption? { result.bestTicket }

    private var maxY: Double {
        let top = max(result.single.cumulative.max() ?? 0, best?.cumulative.max() ?? 0)
        return max(top * 1.12, 10)
    }

    var body: some View {
        Chart {
            ForEach(Array(result.single.cumulative.enumerated()), id: \.offset) { month, cost in
                LineMark(x: .value("Monat", Double(month)), y: .value("Einzeltickets", cost), series: .value("Reihe", "Einzeltickets"))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Theme.dawn)
            }
            if let best {
                ForEach(Array(best.cumulative.enumerated()), id: \.offset) { month, cost in
                    LineMark(x: .value("Monat", Double(month)), y: .value("Ticket", cost), series: .value("Reihe", "Ticket"))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.glacier)
                }
                if let crossing = result.crossing {
                    RuleMark(x: .value("Break-even", crossing), yStart: .value("Kosten", 0.0), yEnd: .value("Kosten", valueAt(crossing, in: best.cumulative)))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Theme.positive.opacity(0.6))
                    PointMark(x: .value("Break-even", crossing), y: .value("Kosten", valueAt(crossing, in: best.cumulative)))
                        .symbol {
                            Circle()
                                .fill(Theme.onAccent)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Theme.positive, lineWidth: 3))
                        }
                        .annotation(position: crossing > 7 ? .topLeading : .topTrailing, spacing: 6) {
                            Label(WhatIfText.crossingTitle(crossing), systemImage: "flag.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.positiveText)
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                                .fixedSize()
                        }
                }
            }
        }
        .chartXScale(domain: 0.0...12.0)
        .chartYScale(domain: 0...maxY)
        .chartXAxis { xAxis }
        .chartYAxis { yAxis }
        .chartLegend(.hidden)
        .environment(\.calendar, Calendar.vienna)
        .transaction { $0.animation = nil }
        .accessibilityChartDescriptor(WhatIfChartDescriptor(result: result))
    }

    /// The cumulative line at a fractional chart position (linear between the month ends).
    private func valueAt(_ position: Double, in points: [Double]) -> Double {
        guard points.count > 1 else { return points.first ?? 0 }
        let clamped = min(max(position, 0), Double(points.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, points.count - 1)
        return points[lower] + (points[upper] - points[lower]) * (clamped - Double(lower))
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: [0.0, 3.0, 6.0, 9.0, 12.0]) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Theme.separator)
            AxisValueLabel(centered: false) {
                if let position = value.as(Double.self), case let month = Int(position.rounded()), result.monthStarts.indices.contains(month) {
                    Text(typeSize > .large ? StatsNames.narrowMonth(result.monthStarts[month]) : StatsNames.shortMonth(result.monthStarts[month]))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
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
}

/// The audio graph of the chart: two series over the twelve months, with the chart summary as its summary.
struct WhatIfChartDescriptor: AXChartDescriptorRepresentable {
    let result: WhatIfResult

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = max(result.single.cumulative.max() ?? 0, result.bestTicket?.cumulative.max() ?? 0, 1)
        let xAxis = AXNumericDataAxisDescriptor(title: "Monat", range: 0...12, gridlinePositions: [3, 6, 9]) { value in
            "Monat \(Int(value.rounded()))"
        }
        let yAxis = AXNumericDataAxisDescriptor(title: "Kosten in Euro", range: 0...top, gridlinePositions: []) { value in
            Format.euro(value, decimals: 0)
        }
        var series = [AXDataSeriesDescriptor(name: "Einzeltickets", isContinuous: true, dataPoints: Self.points(result.single.cumulative))]
        if let best = result.bestTicket {
            series.append(AXDataSeriesDescriptor(name: best.name, isContinuous: true, dataPoints: Self.points(best.cumulative)))
        }
        return AXChartDescriptor(title: "Kosten über zwölf Monate", summary: WhatIfText.chartSummary(result),
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: series)
    }

    private static func points(_ values: [Double]) -> [AXDataPoint] {
        var points: [AXDataPoint] = []
        for (month, cost) in values.enumerated() {
            let x: Double = Double(month)
            let y: Double = cost
            points.append(AXDataPoint(x: x, y: y))
        }
        return points
    }
}
