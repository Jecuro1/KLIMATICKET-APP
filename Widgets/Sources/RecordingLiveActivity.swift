import ActivityKit
import WidgetKit
import SwiftUI

/// MARK: tripdetect – "Aufzeichnung läuft": the Live Activity of "Fahrt aufzeichnen". Started and ended by the app
/// (App/Sources/Features/LiveActivity/RecordingActivityController.swift); views in Shared/WidgetViews/RecordingActivityViews.swift.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Theme.background.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.textPrimary)
                .widgetURL(WidDeepLink.overview)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { RecordingIslandLeading() }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingIslandTimer(attributes: context.attributes, pausedAt: RecordingCopy.pausedAt(context.state, isStale: context.isStale))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(RecordingCopy.headline(context.state, isStale: context.isStale)).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) { RecordingIslandBottom(state: context.state, isStale: context.isStale) }
            } compactLeading: {
                RecordingIslandLeading()
            } compactTrailing: {
                RecordingIslandTimer(attributes: context.attributes, pausedAt: RecordingCopy.pausedAt(context.state, isStale: context.isStale))
            } minimal: {
                RecordingIslandLeading()
            }
            .widgetURL(WidDeepLink.overview)
            .keylineTint(Theme.pine)
        }
    }
}
