import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// The system alarm of the Aussteige-Wecker as a Live Activity (docs/EXIT_ALARM.md §3). AlarmKit presents its alarms through
/// ActivityKit, so the extension carries the layout for the Lock Screen and the Dynamic Island. The alarm has no countdown (it is
/// scheduled for a fixed moment), so only the alert state is drawn; the ringing screen itself is the system's.
struct ExitAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<ExitAlarmMetadata>.self) { context in
            ExitAlarmAlertView(metadata: context.attributes.metadata)
                .activityBackgroundTint(Theme.background.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.and.waves.left.and.right.fill").foregroundStyle(Theme.dawn)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExitAlarmAlertView(metadata: context.attributes.metadata, compact: true)
                }
            } compactLeading: {
                Image(systemName: "bell.fill").foregroundStyle(Theme.dawn)
            } compactTrailing: {
                Text(context.attributes.metadata?.stopName ?? "Wecker").font(.caption2.weight(.semibold)).lineLimit(1)
            } minimal: {
                Image(systemName: "bell.fill").foregroundStyle(Theme.dawn)
            }
            .keylineTint(Theme.dawn)
        }
    }
}

/// "Aussteigen!" and the stop, for the Lock Screen and the island.
private struct ExitAlarmAlertView: View {
    let metadata: ExitAlarmMetadata?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font((compact ? Font.subheadline : Font.headline).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(metadata?.stopName ?? "Aussteige-Wecker")
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(compact ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch metadata?.kind {
        case "passed": "Vorbeigefahren"
        case "test": "Test: Aussteigen!"
        default: "Aussteigen!"
        }
    }
}
