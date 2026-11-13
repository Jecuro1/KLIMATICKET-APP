import SwiftUI
import WidgetKit
import KlimaCore

// MARK: smartwidgets – the lock-screen variants added for the Smart Stack track (docs/WIDGETS_SMARTSTACK.md §4): the round
// countdown of "Nächste Verbindung" and "Abfahrten", and the rectangular "Ticket-Restzeit". Vibrant like every lock-screen
// widget: no colours of their own, the key figure is `widgetAccentable()`, and every figure has a spoken label.

/// The next departure as a ring that empties over the last 45 minutes before the train leaves (the system runs it by
/// itself, `ProgressView(timerInterval:)`), with the departure time in the middle and the delay under it.
struct WidDepartureRing: View {
    var time: Date
    var delay: Int?
    var showsDelay: Bool
    var isCancelled: Bool
    /// Above the time: the line ("S 4") or nil for the mode symbol.
    var caption: String?
    var modeSymbol: String
    /// One sentence for VoiceOver.
    var spoken: String

    /// The ring counts down this long before the departure (the Smart Stack window, `WidgetRelevance.departureLead`).
    static let window: TimeInterval = WidgetRelevance.departureLead

    /// `.accessoryCircular` only inside the widget extension (the app's previews pass the family as a parameter).
    @Environment(\.widgetFamily) private var hostFamily

    var body: some View {
        ZStack {
            if isCancelled {
                Circle()
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 4, dash: [3, 4]))
            } else if hostFamily == .accessoryCircular {
                // In a widget the circular style is the capacity gauge, and the system runs it by itself.
                ProgressView(timerInterval: time.addingTimeInterval(-Self.window)...time, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
            } else {
                // In the app the circular style is a spinner: the previews draw the same ring as a gauge, every 30 s.
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    Gauge(value: Self.remainingShare(of: time, at: context.date)) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            }
            VStack(spacing: 0) {
                if let caption {
                    Text(verbatim: caption)
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Image(systemName: modeSymbol)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                Text(verbatim: WidFormat.clock(time))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .strikethrough(isCancelled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                if isCancelled {
                    Text(verbatim: "fällt aus")
                        .font(.system(size: 8.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if showsDelay, let text = WidFormat.delay(delay) {
                    Text(verbatim: text)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The ring's fill at `now`: 1 up to 45 minutes before the departure, 0 at the departure.
    static func remainingShare(of departure: Date, at now: Date) -> Double {
        min(max(departure.timeIntervalSince(now) / window, 0), 1)
    }
}

/// "Ticket-Restzeit" in a lock-screen row: the days left as the key figure, the last day and a slim bar of the year.
struct WidTicketRemainingRectangular: View {
    var snapshot: WidgetSnapshot
    var now: Date

    var body: some View {
        let days = max(WidInsight.daysRemaining(snapshot, now: now), 0)
        let expired = WidInsight.isExpired(snapshot, now: now)
        VStack(alignment: .leading, spacing: 1) {
            Label("Ticket-Restzeit", systemImage: "ticket.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: expired ? "Abgelaufen" : "\(days)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(verbatim: expired ? WidFormat.dayMonth(snapshot.validUntil)
                                       : "\(days == 1 ? "Tag" : "Tage") · bis \(WidFormat.dayMonth(snapshot.validUntil))")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            WidLinearBar(progress: Double(min(days, 365)) / 365)
                .frame(height: 5)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ticket-Restzeit")
        .accessibilityValue("\(WidInsight.validityText(snapshot, now: now)), gültig bis \(WidFormat.dayMonth(snapshot.validUntil))")
    }
}
