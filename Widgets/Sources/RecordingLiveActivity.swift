import ActivityKit
import WidgetKit
import SwiftUI

/// MARK: tripdetect – "Aufzeichnung läuft": the Live Activity of "Fahrt aufzeichnen". Started and ended by the app
/// (App/Sources/Features/LiveActivity/RecordingActivityController.swift); views in Shared/WidgetViews/RecordingActivityViews.swift.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.background.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.textPrimary)
                .widgetURL(WidDeepLink.overview)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { RecordingIslandLeading() }
                DynamicIslandExpandedRegion(.trailing) { RecordingIslandTimer(attributes: context.attributes) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isStopped ? "Aufzeichnung gestoppt" : "Aufzeichnung läuft").font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) { RecordingIslandBottom(state: context.state) }
            } compactLeading: {
                RecordingIslandLeading()
            } compactTrailing: {
                RecordingIslandTimer(attributes: context.attributes)
            } minimal: {
                RecordingIslandLeading()
            }
            .widgetURL(WidDeepLink.overview)
            .keylineTint(Theme.pine)
        }
    }
}
