import SwiftUI
import KlimaCore

// MARK: radarmodes – the counts line of the status card (docs/RADAR_MODES.md §9): „Zug 21 · S-Bahn 28 · Bus 180 · Bim 92 · U-Bahn 12“, each with the
// mode's colour dot; at accessibility sizes two columns when they fit, else one per row (MARK: radar2-fix-radarmodes – the card grows up to AX2, where
// two columns fit a phone; one per row from AX3 pushed the notes off the screen). The numbers roll (`Motion.number`).

struct RadarModeCountsRow: View {
    var counts: RadarModeCounts
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 7

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {   // MARK: radar2-fix-radarmodes – a Grid measures its columns, so the fallback is chosen when needed
                    Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.m, verticalSpacing: 2) {
                        ForEach(Array(stride(from: 0, to: counts.entries.count, by: 2)), id: \.self) { start in
                            GridRow {
                                item(counts.entries[start])
                                if start + 1 < counts.entries.count { item(counts.entries[start + 1]) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) { items }
                }
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
        ForEach(counts.entries) { entry in item(entry) }
    }

    private func item(_ entry: RadarModeCounts.Entry) -> some View {
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
