import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – the delay line of the trip sheet's row (docs/RADAR_TRAILS.md §5). 44 pt tall at every text size; a light band marks the
// radar's „pünktlich“ (under five minutes, the threshold of its markers), the first and the last value are written under the line. Decorative for
// VoiceOver: the row says the sentence.

struct RadarTrailSparkline: View {
    let series: RadarDelaySeries
    static let height: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    /// The chart's frame in minutes: never above zero at the bottom, at least up to the late threshold plus one at the top.
    private var range: (low: Double, high: Double) {
        let values = series.points.map(\.minutes)
        let low = Double(min(values.min() ?? 0, 0))
        let high = Double(max((values.max() ?? 0) + 1, RadarDelay.lateThresholdSeconds / 60 + 1))
        return (low, max(high, low + 1))
    }

    private func y(_ minutes: Double, height: CGFloat) -> CGFloat {
        let (low, high) = range
        return height * (1 - CGFloat((minutes - low) / (high - low)))
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let start = series.start ?? Date()
        let span = max(series.span, 1)
        return series.points.map { point in
            CGPoint(x: size.width * point.at.timeIntervalSince(start) / span, y: y(Double(point.minutes), height: size.height))
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                let coordinates = points(in: proxy.size)
                let bandTop = y(Double(RadarDelay.lateThresholdSeconds / 60), height: proxy.size.height)
                let bandBottom = y(0, height: proxy.size.height)
                ZStack(alignment: .topLeading) {
                    // „pünktlich“: from on time up to the five minutes the markers call late
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.positive.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: proxy.size.width, height: max(bandBottom - bandTop, 0))
                        .offset(y: bandTop)
                    Path { path in
                        guard let first = coordinates.first else { return }
                        path.move(to: first)
                        for point in coordinates.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(Theme.summit, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let last = coordinates.last {
                        Circle()
                            .fill(Theme.summit)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
                            .position(last)
                    }
                }
            }
            .frame(height: Self.height)
            HStack {
                Text(series.first.map(RadarTrailText.label) ?? "")
                Spacer(minLength: 4)
                Text(series.last.map(RadarTrailText.label) ?? "")
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityHidden(true)
    }
}
