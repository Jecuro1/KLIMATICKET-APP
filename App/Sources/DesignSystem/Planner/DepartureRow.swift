import SwiftUI
import KlimaCore

/// One row of the departure / arrival board (UX §4.4, mock 13): time with realtime, line plate, destination, a notice
/// line and the platform box. A cancelled run is struck through and says „Fällt aus“.
struct DepartureRow: View {
    var row: BoardRow
    var isArrival = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            timeColumn
                .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    PlannerLinePlate(row: row, size: .m)
                        .opacity(row.isCancelled ? 0.6 : 1)
                    Text(row.destination.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(row.isCancelled ? Theme.textSecondary : Theme.textPrimary)
                        .strikethrough(row.isCancelled, color: Theme.negativeText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let platform = row.platform {
                PlatformBox(platform: platform, compact: true)
            }
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.time)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(row.isCancelled ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(row.isCancelled, color: Theme.negativeText)
                .monospacedDigit()
            if let text = row.realtime.text {
                HStack(spacing: 3) {
                    if row.realtime.state != .cancelled { LiveDot(state: row.realtime.state, size: 6) }
                    Text(text)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(PlannerRealtimeStyle.text(row.realtime.state))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if let notice = row.notices.max(by: { $0.severity < $1.severity }) {
            NoticeRow(notice: notice)
                .lineLimit(1)
        } else if let sub = row.destination.sub {
            Text(sub).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        } else if !row.lineTitle.isEmpty {
            Text(row.lineTitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }

    private var spoken: String {
        var parts = ["\(row.lineTitle) \(isArrival ? "von" : "nach") \(row.destination.name)", "um \(row.time)"]
        if let s = RealtimePresentation.spoken(row.realtime, realtime: nil) { parts.append(s) }
        if let p = row.platform { parts.append(p.spoken + (p.changed ? ", geändert" : "")) }
        if let n = row.notices.first { parts.append(n.title) }
        return parts.joined(separator: ", ")
    }
}
