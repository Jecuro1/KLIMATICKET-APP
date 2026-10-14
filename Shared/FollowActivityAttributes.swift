import Foundation
import ActivityKit
import KlimaCore

// "Live verfolgen" Live Activity (docs/OEBB_LIVE.md §R8): one followed ride on the Lock Screen and in the Dynamic Island.
// Started by the app when a follow starts (planner, Zug-Radar, saved ride), updated while the app runs and on background
// refreshes, ended on arrival or when the user stops the follow. Started with `pushType: nil`: no remote pushes (see
// docs/LIVE_PUSH.md). Shared source file: compiled into the app and the widget extension.

/// Static data of one followed ride. The live part is `FollowLiveState` (ActivityKit caps the content state at 4 KB).
struct FollowActivityAttributes: ActivityAttributes {
    typealias ContentState = FollowLiveState

    /// The HAFAS trip id. The app matches a running activity to its follow with it.
    var tripID: String
    /// "RJX 66", as the planner shows it.
    var lineName: String
    var boardingName: String
    var alightName: String
    var plannedDeparture: Date?
    var plannedArrival: Date?
    var startedAt: Date

    /// "Salzburg Hbf → Wien Hbf"
    var routeTitle: String { "\(boardingName) → \(alightName)" }
}
