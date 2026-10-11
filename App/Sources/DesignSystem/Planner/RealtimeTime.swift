import SwiftUI
import KlimaCore

/// The live dot next to „pünktlich“ (a small disc with a soft halo). The halo breathes only while it is on screen
/// (docs/MOTION.md §12).
struct LiveDot: View {
    var state: RealtimeState
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(PlannerRealtimeStyle.dot(state))
            .frame(width: size, height: size)
            .padding(size * 0.28)
            .background(PlannerRealtimeStyle.dot(state).opacity(0.22), in: .circle)
            .accessibilityHidden(true)
    }
}

enum PlannerRealtimeStyle {
    /// Text-safe colours (≥ 4.5:1) for realtime labels.
    static func text(_ state: RealtimeState) -> Color {
        switch state {
        case .scheduled: Theme.textSecondary
        case .onTime: Theme.positiveText
        case .late: Theme.summitText
        case .veryLate, .cancelled: Theme.negativeText
        }
    }

    static func dot(_ state: RealtimeState) -> Color {
        switch state {
        case .scheduled: Theme.textTertiary
        case .onTime: Theme.positive
        case .late: Theme.dawn
        case .veryLate, .cancelled: Theme.negative
        }
    }
}

/// Planned time with its realtime line below: „12:16“ over „● pünktlich“ / „14:20 +4“ / „Fällt aus“.
/// A cancelled time is struck through. Without realtime nothing sits below (the detail says „Fahrplan“).
struct RealtimeTime: View {
    enum Style { case card, row, hero }

    var planned: Date?
    var label: RealtimeLabel
    var style: Style = .card
    /// Shows „Fahrplan“ under a time without realtime (detail timeline).
    var showsScheduledHint = false
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(planned.map(Format.time) ?? "–")
                .font(timeFont)
                .foregroundStyle(label.state == .cancelled ? Theme.textSecondary : Theme.textPrimary)
                .strikethrough(label.state == .cancelled, color: Theme.negativeText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            realtimeLine
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var realtimeLine: some View {
        if let text = label.text {
            HStack(spacing: 3) {
                if label.state == .onTime || label.state == .late || label.state == .veryLate {
                    LiveDot(state: label.state, size: 7)
                }
                Text(text)
                    .font(lineFont)
                    .foregroundStyle(PlannerRealtimeStyle.text(label.state))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentTransition(.numericText())
        } else if showsScheduledHint {
            Text("Fahrplan").font(lineFont).foregroundStyle(Theme.textSecondary)
        }
    }

    private var timeFont: Font {
        switch style {
        case .card: .system(size: 30, weight: .bold, design: .rounded)
        case .row: .system(size: 17, weight: .bold, design: .rounded)
        case .hero: .system(size: 40, weight: .bold, design: .rounded)
        }
    }

    private var lineFont: Font {
        switch style {
        case .card, .hero: .system(size: 14, weight: .semibold, design: .rounded)
        case .row: .system(size: 13, weight: .semibold, design: .rounded)
        }
    }

    private var spoken: String {
        let time = planned.map(RealtimePresentation.time) ?? ""
        let realtime = planned.flatMap { p in label.delayMinutes.map { p.addingTimeInterval(Double($0) * 60) } }
        if let s = RealtimePresentation.spoken(label, realtime: realtime) { return "\(time), \(s)" }
        return time
    }
}
