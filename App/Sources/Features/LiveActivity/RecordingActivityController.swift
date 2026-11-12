import ActivityKit
import Foundation
import KlimaCore

// The app's side of the "Aufzeichnung läuft" Live Activity (Shared/RecordingActivityAttributes.swift). Started when a recording
// starts, updated at most every 10 s while it runs, ended when it stops. `pushType: nil`: no remote updates, no APNs.
// Never in a screenshot or perf run.

@MainActor
final class RecordingActivityController {
    static let shared = RecordingActivityController()

    private var activity: Activity<RecordingActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastState = RecordingActivityAttributes.ContentState()

    var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Starts the activity of a recording (nothing happens when Live Activities are off – the recording itself runs).
    func begin(startedAt: Date) {
        guard !LaunchMode.isSandboxed, isAllowed, activity == nil else { return }
        let content = ActivityContent(state: RecordingActivityAttributes.ContentState(), staleDate: nil, relevanceScore: 70)
        activity = try? Activity.request(attributes: RecordingActivityAttributes(startedAt: startedAt), content: content, pushType: nil)
        lastUpdate = Date()
    }

    /// Takes the live numbers; the system gets them at most every 10 s.
    func update(_ snapshot: RecordingSnapshot) {
        guard let activity else { return }
        let station = snapshot.currentStation?.station.name ?? snapshot.lastStation?.name
        let state = RecordingActivityAttributes.ContentState(distanceKm: snapshot.distanceKm, speedKmh: snapshot.speedKmh, stationName: station,
                                                              isAtStation: snapshot.currentStation != nil)
        lastState = state
        guard Date().timeIntervalSince(lastUpdate) >= 10 else { return }
        lastUpdate = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil, relevanceScore: 70)) }
    }

    /// Ends the activity; a stopped recording stays on the Lock Screen for a moment as "Aufzeichnung gestoppt".
    func end(proposal: RecordingProposal?) {
        guard let activity else { return }
        self.activity = nil
        var state = lastState
        state.isStopped = true
        state.speedKmh = 0
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil, relevanceScore: 0), dismissalPolicy: proposal == nil ? .immediate : .after(Date().addingTimeInterval(120)))
        }
    }
}
