import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – „Verspätung, seit du zuschaust“ in the radar's trip sheet (docs/RADAR_TRAILS.md §5): how the delay of this vehicle moved in the
// answers this iPhone got while the radar was open. Hidden until there is enough of it (three moments over two minutes): no empty promise.

struct RadarTrailDelayRow: View {
    let vehicle: RadarVehicle
    let trail: RadarTrailModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let series = trail.series(for: vehicle.tripID)
        if series.isShowable, let start = series.start {
            GlassCard(padding: Theme.Spacing.m) {
                if typeSize >= .accessibility3 {
                    // The chart keeps its height; at the largest sizes it moves under the words instead of squeezing them.
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        words(series, start: start)
                        RadarTrailSparkline(series: series)
                    }
                } else {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        words(series, start: start)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RadarTrailSparkline(series: series)
                            .frame(width: 132)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RadarTrailText.spoken(series))
            .motionTransition(.rise)
        }
    }

    private func words(_ series: RadarDelaySeries, start: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(RadarTrailText.rowTitle, systemImage: "chart.line.uptrend.xyaxis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(RadarTrailText.value(series))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(RadarTrailText.sinceLine(start))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
