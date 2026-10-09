import ActivityKit
import WidgetKit
import SwiftUI

/// "Unterwegs" – the Live Activity of a running ride (Lock Screen, banner, Dynamic Island). Started by the app
/// (trip editor "Fahrt jetzt starten", the "Fahrt starten" App Intent, later the ÖBB planner); its buttons save or end
/// the ride via `RideSaveIntent` / `RideDiscardIntent`. All views live in Shared/WidgetViews/RideActivityViews.swift.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .widgetURL(WidDeepLink.overview)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RideIslandLeading(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RideIslandTrailing(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    RideIslandCenter(attributes: context.attributes, state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RideIslandBottom(attributes: context.attributes, state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                RideIslandCompactLeading(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                RideIslandCompactTrailing(state: context.state)
            } minimal: {
                RideIslandMinimal(attributes: context.attributes, state: context.state)
            }
            .widgetURL(WidDeepLink.overview)
            .keylineTint(Theme.glacier)
        }
    }
}
