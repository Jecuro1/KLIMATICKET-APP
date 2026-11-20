import SwiftUI

// MARK: review-uebersicht – „Live verfolgen“ in the tab bar accessory only while a follow runs (as RootView's comment always said).
// `tabViewBottomAccessory { }` of iOS 26.0 shows its glass capsule even when its content is empty: every tab carried an empty capsule
// over its content above the tab bar (on the Übersicht in every screenshot). iOS 26.1 switches the accessory off with `isEnabled:`.
extension View {
    func liveFollowAccessory(_ tracker: LiveFollowTracker) -> some View {
        modifier(LiveFollowAccessoryVisibility(tracker: tracker))
    }
}

private struct LiveFollowAccessoryVisibility: ViewModifier {
    let tracker: LiveFollowTracker

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: tracker.target != nil) {
                LiveFollowAccessoryHost(tracker: tracker)
            }
        } else {
            content.tabViewBottomAccessory {
                LiveFollowAccessoryHost(tracker: tracker)
            }
        }
    }
}
