import ActivityKit
import Foundation
import KlimaCore

// Live verfolgen: the app's side of the "Live verfolgen" Live Activity (Shared/FollowActivityAttributes.swift, docs/
// OEBB_LIVE.md §R8). Started by `LiveFollowTracker` only when the user switched Live-Mitteilungen on and allowed Live
// Activities for KlimaBilanz. Requests use `pushType: nil`: no remote updates, no APNs (docs/LIVE_PUSH.md).
// ActivityKit only accepts a request while the app is in the foreground, so a background refresh may fail to start one;
// the tracker then tries again on the next answer.

@MainActor
final class FollowActivityController {
    static let shared = FollowActivityController()

    /// The system allows Live Activities for KlimaBilanz right now (Einstellungen › KlimaBilanz).
    var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Starts the activity of a follow. Returns its id, or nil when iOS refuses (not allowed, too many, not in the foreground).
    func start(target: LiveFollowTarget, state: FollowLiveState, staleDate: Date, startedAt: Date) -> String? {
        guard isAllowed else { return nil }
        let attributes = FollowActivityAttributes(
            tripID: target.tripID,
            lineName: target.lineName,
            boardingName: target.boardingStop.name,
            alightName: target.alightStop.name,
            plannedDeparture: target.plannedDeparture,
            plannedArrival: target.plannedArrival,
            startedAt: startedAt)
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 80)
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: nil).id
        } catch {
            return nil
        }
    }

    /// Updates the activity. False when it no longer exists (the user removed it from the Lock Screen).
    @discardableResult
    func update(id: String, state: FollowLiveState, staleDate: Date) async -> Bool {
        guard let activity = activity(id: id) else { return false }
        await activity.update(ActivityContent(state: state, staleDate: staleDate, relevanceScore: 80))
        return true
    }

    /// Ends the activity. After the arrival it stays `dismissAfter` seconds on the Lock Screen; zero removes it at once.
    func end(id: String, final state: FollowLiveState?, staleDate: Date, dismissAfter: TimeInterval) async {
        guard let activity = activity(id: id) else { return }
        let content = ActivityContent(state: state ?? activity.content.state, staleDate: staleDate, relevanceScore: 0)
        let policy: ActivityUIDismissalPolicy = dismissAfter > 0
            ? .after(Date().addingTimeInterval(dismissAfter))
            : .immediate
        await activity.end(content, dismissalPolicy: policy)
    }

    func activity(id: String) -> Activity<FollowActivityAttributes>? {
        Activity<FollowActivityAttributes>.activities.first { $0.id == id }
    }
}
