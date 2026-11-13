import SwiftUI
import KlimaCore

// MARK: radarmodes – the counts line of the status card (docs/RADAR_MODES.md §9): „Zug 21 · S-Bahn 28 · Bus 180 · Bim 92 · U-Bahn 12“, each with the
// mode's colour dot; at accessibility sizes a two-column grid, from AX3 one per row. The numbers roll (`Motion.number`).

struct RadarModeCountsRow: View {
    var counts: RadarModeCounts
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 7

    var body: some View {
        Group {
            if typeSize >= .accessibility3 {
                VStack(alignment: .leading, spacing: 2) { items }
            } else if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 2) { items }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.s) { items }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 2) { items }
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .motionAnimation(Motion.number, value: counts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.spoken)
    }

    @ViewBuilder private var items: some View {
        ForEach(counts.entries) { entry in
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.mode?.color ?? Theme.textTertiary)
                    .frame(width: dot, height: dot)
                Text(RadarModesText.label(entry.mode))
                Text(verbatim: String(entry.count))   // no thousands separator: the pill says „5080 Fahrzeuge“ the same way
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(entry.count)))
            }
            .fixedSize()
        }
    }
}
