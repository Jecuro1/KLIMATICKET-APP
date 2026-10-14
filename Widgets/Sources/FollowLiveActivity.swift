import ActivityKit
import WidgetKit
import SwiftUI

/// "Live verfolgen" – the Live Activity of a followed ride (docs/OEBB_LIVE.md §R8). Started by the app when a follow starts,
/// updated while the app runs and on background refreshes, ended on arrival or when the follow is stopped. The views live in
/// Shared/WidgetViews/FollowActivityViews.swift. No buttons here: the actions are notification actions (see the app).
struct FollowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FollowActivityAttributes.self) { context in
            FollowLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Theme.background.opacity(0.92))
                .activitySystemActionForegroundColor(Theme.textPrimary)
                .widgetURL(WidDeepLink.overview)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FollowIslandCompactLeading(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FollowIslandCompactTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    FollowIslandExpandedCenter(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FollowIslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                FollowIslandCompactLeading(attributes: context.attributes)
            } compactTrailing: {
                FollowIslandCompactTrailing(state: context.state)
            } minimal: {
                FollowIslandMinimal(state: context.state)
            }
            .widgetURL(WidDeepLink.overview)
            .keylineTint(Theme.glacier)
        }
    }
}
