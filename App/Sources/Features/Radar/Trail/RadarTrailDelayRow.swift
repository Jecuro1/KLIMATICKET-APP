import SwiftUI
import KlimaCore

// MARK: radar2-radartrail – „Verspätung, seit du zuschaust“ in the radar's trip sheet (docs/RADAR_TRAILS.md §5): how the delay of this vehicle moved in the
// answers this iPhone got while the radar was open. Hidden until there is enough of it (three moments over two minutes): no empty promise. The words
// take the full width at every text size, the line runs under them as wide as the card (it keeps its 44 pt).

struct RadarTrailDelayRow: View {
    let vehicle: RadarVehicle
    let trail: RadarTrailModel

    var body: some View {
        let series = trail.series(for: vehicle.tripID)
        if series.isShowable, let start = series.start {
            GlassCard(padding: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label(RadarTrailText.rowTitle, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(RadarTrailText.value(series))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    RadarTrailSparkline(series: series)
                        .padding(.vertical, 2)
                    Text(RadarTrailText.sinceLine(start))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RadarTrailText.spoken(series))
            .motionTransition(.rise)
        }
    }
}
