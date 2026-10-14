import SwiftUI
import WidgetKit
import KlimaCore

/// "Fahrten-Kalender": twelve weeks of trips, one square per day (Monday on top, the current week last). Today is outlined,
/// the days after today are dashed. The grid is drawn with one Canvas, so it stays light in memory.
struct HeatmapWidgetView: View {
    /// Trips per day, oldest first (`WidgetHeatmap.cellCount` values), as stored when the snapshot was written.
    var counts: [Int]?
    /// The day the counts were stored on.
    var storedDay: Date
    var now: Date
    var family: WidgetFamily
    var margins: EdgeInsets = WidLayout.defaultMargins

    private var levels: [UInt8] { WidgetHeatmap.levels(counts ?? []) }

    var body: some View {
        if counts == nil {
            WidLiveEmpty(status: .empty, family: family, choice: nil,
                         message: ("Noch keine Fahrten", "Erfasse eine Fahrt, dann füllt sich der Kalender"))
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
            HStack(spacing: 6) {
                WidEyebrow(text: "Zwölf Wochen", symbol: "square.grid.3x3.fill")
                Spacer(minLength: 4)
                Text(verbatim: "\(tripTotal) \(tripTotal == 1 ? "Fahrt" : "Fahrten")")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.widSecondary)
                    .monospacedDigit()
            }
            grid
                .frame(maxWidth: .infinity)
                .frame(height: family == .systemLarge ? 230 : 100)
                .accessibilityHidden(true)
            if family == .systemLarge {
                legend
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fahrten-Kalender, zwölf Wochen")
        .accessibilityValue("\(tripTotal) \(tripTotal == 1 ? "Fahrt" : "Fahrten") in den letzten zwölf Wochen")
    }

    private var tripTotal: Int { (counts ?? []).reduce(0, +) }

    private var grid: some View {
        let stored = levels
        let today = WidgetHeatmap.todayIndex(now)
        return Canvas { context, size in
            let columns = WidgetHeatmap.weeks
            let rows = 7
            let gap: CGFloat = 2.5
            let cellWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for index in 0..<WidgetHeatmap.cellCount {
                let column = index / rows
                let row = index % rows
                let rect = CGRect(x: CGFloat(column) * (cellWidth + gap), y: CGFloat(row) * (cellHeight + gap),
                                  width: cellWidth, height: cellHeight)
                let path = Path(roundedRect: rect, cornerRadius: min(cellWidth, cellHeight) * 0.25)
                if index > today {
                    context.stroke(path, with: .color(Theme.textTertiary), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    continue
                }
                let level = WidgetHeatmap.cell(index, stored: stored, fallback: 0, storedDay: storedDay, today: now)
                context.fill(path, with: .color(Self.shade(level)))
                if index == today {
                    context.stroke(path, with: .color(Theme.textPrimary), lineWidth: 1.4)
                }
            }
        }
        .widgetAccentable()
    }

    /// Shades of the accent for the levels 0 … 4 (0 = no trip, a quiet surface).
    static func shade(_ level: UInt8) -> Color {
        switch level {
        case 0: Theme.surfaceSecondary
        case 1: Theme.accent.opacity(0.28)
        case 2: Theme.accent.opacity(0.48)
        case 3: Theme.accent.opacity(0.72)
        default: Theme.accent
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text(verbatim: "weniger")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.widSecondary)
            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Self.shade(UInt8(level)))
                    .frame(width: 10, height: 10)
            }
            Text(verbatim: "mehr")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.widSecondary)
            Spacer(minLength: 0)
            Text(verbatim: "Stand \(WidFormat.clock(storedDay))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.widSecondary)
        }
    }
}
