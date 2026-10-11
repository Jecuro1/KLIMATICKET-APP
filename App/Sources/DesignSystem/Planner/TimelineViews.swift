import SwiftUI
import KlimaCore

// The connection timeline (UX §4.3, mock 12): stops with times and platforms on a rail, ride legs in their line colour,
// walks and changes dotted. All three views share one rail column so the line runs unbroken from row to row.

enum TimelineRail: Equatable {
    case none
    case ride(Color)
    case walk
}

private enum RailMetrics {
    static let width: CGFloat = 30
    static let timeWidth: CGFloat = 58
    static let nodeSize: CGFloat = 16
    static let lineWidth: CGFloat = 4
}

/// One rail segment: a solid coloured bar for rides, a dotted grey line for walks and changes.
private struct RailSegment: View {
    var style: TimelineRail

    var body: some View {
        switch style {
        case .none:
            Color.clear.frame(width: RailMetrics.lineWidth)
        case .ride(let color):
            RoundedRectangle(cornerRadius: RailMetrics.lineWidth / 2).fill(color).frame(width: RailMetrics.lineWidth)
        case .walk:
            GeometryReader { proxy in
                Path { p in
                    p.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    p.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                }
                .stroke(Theme.textTertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 5]))
            }
            .frame(width: RailMetrics.lineWidth)
        }
    }
}

/// A stop: planned time and realtime on the left, the node on the rail, the name and a caption, the platform.
struct TimelineStopRow: View {
    enum Role { case start, transfer, end }

    var role: Role
    var planned: Date?
    var realtime: RealtimeLabel
    var name: DisplayName
    var caption: String?
    var platform: PlatformLabel?
    var above: TimelineRail
    var below: TimelineRail
    /// A walk to or from an address or POI: the node is hollow and grey.
    var isFootnote = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            RealtimeTime(planned: planned, label: realtime, style: .row, showsScheduledHint: false)
                .frame(width: RailMetrics.timeWidth, alignment: .leading)
                .padding(.top, 1)
            VStack(spacing: 0) {
                RailSegment(style: above).frame(height: 7)
                node
                RailSegment(style: below).frame(maxHeight: .infinity)
            }
            .frame(width: RailMetrics.width)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(isFootnote ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let sub = name.sub ?? caption {
                    Text(name.sub != nil && caption != nil ? "\(sub) · \(caption!)" : sub)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let platform {
                PlatformBox(platform: platform)
            }
        }
        .frame(minHeight: 56, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var node: some View {
        ZStack {
            switch role {
            case .start:
                Circle().strokeBorder(Theme.accent, lineWidth: 4).background(Circle().fill(Theme.sheetBackground))
            case .transfer:
                Circle().fill(Theme.accent)
            case .end:
                Circle().fill(Theme.dawn).overlay(Circle().stroke(Theme.dawn.opacity(0.28), lineWidth: 5))
            }
        }
        .frame(width: RailMetrics.nodeSize, height: RailMetrics.nodeSize)
        .opacity(isFootnote ? 0.6 : 1)
    }

    private var spoken: String {
        var parts = [name.name]
        if let planned { parts.append("um \(RealtimePresentation.time(planned))") }
        if let s = RealtimePresentation.spoken(realtime, realtime: nil) { parts.append(s) }
        if let platform { parts.append(platform.spoken + (platform.changed ? ", geändert" : "")) }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ", ")
    }
}

/// One stop between the ends of a ride leg (a collapsed „n Zwischenhalte“ list opens into these).
struct TimelineIntermediateStop: Identifiable, Hashable {
    var id: String
    var time: Date?
    var realtime: RealtimeLabel
    var name: String
}

/// A ride leg on the rail: line plate and title, direction, the attribute chips and the expandable intermediate stops.
struct TimelineRideLeg: View {
    var badge: LineBadge
    var title: String
    var direction: String?
    var subtitle: String?
    var attributes: [String]
    var stops: [TimelineIntermediateStop]
    var color: Color
    var notices: [Notice] = []
    var isCancelled = false
    @Binding var isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Color.clear.frame(width: RailMetrics.timeWidth)
            RailSegment(style: .ride(color)).frame(width: RailMetrics.width)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: 8) {
                    LinePlate(badge, size: .m)
                    Text(title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(isCancelled ? Theme.textSecondary : Theme.textPrimary)
                        .strikethrough(isCancelled, color: Theme.negativeText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let direction {
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        Text(direction)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(isCancelled ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                if let subtitle {
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
                if !attributes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attributes, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 30)
                                .background(Theme.surfaceSecondary, in: .rect(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .accessibilityHidden(true)
                }
                ForEach(notices) { NoticeRow(notice: $0, compact: false) }
                if !stops.isEmpty { intermediate }
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var intermediate: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withMotion(Motion.smooth) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(stops.count == 1 ? "1 Zwischenhalt" : "\(stops.count) Zwischenhalte")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Blendet die Zwischenhalte aus" : "Zeigt die Zwischenhalte")
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stops) { stop in
                        HStack(spacing: 12) {
                            Text(stop.time.map(Format.time) ?? "–")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(stop.realtime.state == .cancelled ? Theme.textSecondary : Theme.textPrimary)
                                .strikethrough(stop.realtime.state == .cancelled)
                                .monospacedDigit()
                                .frame(width: 52, alignment: .leading)
                            Text(stop.name).font(.system(size: 17)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            if let text = stop.realtime.text, stop.realtime.state == .late || stop.realtime.state == .veryLate {
                                Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(PlannerRealtimeStyle.text(stop.realtime.state))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
                .motionTransition(.rise)
            }
        }
    }
}

/// A walk or a change on the dotted rail: „3 min Fußweg · 42 m zum Vorplatz“ and the transfer chip.
struct TimelineWalkLeg: View {
    var text: String
    var transfer: TransferInfo?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Color.clear.frame(width: RailMetrics.timeWidth)
            RailSegment(style: .walk).frame(width: RailMetrics.width)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                }
                if let transfer { TransferChip(info: transfer) }
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// „✓ 15 min Umstiegszeit“ / „Knapp: 3 min zum Umsteigen“ / „Anschluss gefährdet“.
struct TransferChip: View {
    var info: TransferInfo

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            Text(info.text).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: .capsule)
    }

    private var symbol: String {
        switch info.risk {
        case .ok: "checkmark"
        case .tight: "exclamationmark.triangle.fill"
        case .atRisk: "exclamationmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch info.risk {
        case .ok: Theme.positiveText
        case .tight: Theme.summitText
        case .atRisk: Theme.negativeText
        }
    }
}
