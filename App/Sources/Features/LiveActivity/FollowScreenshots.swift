import SwiftUI
import KlimaCore

// MARK: follow – CI screenshot hosts for "Live verfolgen": the six stages, the Live Activity layouts and the notice settings.
// Demo values only, built from today's clock: no network, no notification request, no Live Activity.

struct FollowScreenshotHost: View {
    static let screens: Set<String> = ["followStates", "followActivityPreview", "notificationSettings"]

    let screen: String

    var body: some View {
        switch screen {
        case "followStates":   // MARK: follow – the six stages as Lock Screen cards
            FollowStatesShot()
        case "followActivityPreview":   // MARK: follow – Lock Screen and the Dynamic Island layouts
            FollowActivityPreviewShot()
        default:   // MARK: follow – Einstellungen › Live-Mitteilungen with the switches on
            FollowNoticeSettingsShot()
        }
    }
}

/// Demo ride: Salzburg Hbf → Wien Hbf with a change in Wien, shown at each stage.
enum FollowDemo {
    static let attributes = FollowActivityAttributes(
        tripID: "demo-rjx66", lineName: "RJX 66", boardingName: "Salzburg Hbf", alightName: "Wien Hbf",
        plannedDeparture: Date().addingTimeInterval(-300), plannedArrival: Date().addingTimeInterval(2 * 3600),
        startedAt: Date().addingTimeInterval(-600))

    static var stages: [(title: String, state: FollowLiveState)] {
        let now = Date()
        return [
            ("Vor der Abfahrt", FollowLiveState(stage: .beforeDeparture, nextStopName: "Salzburg Hbf",
                                                nextStopTime: now.addingTimeInterval(50 * 60), delayMinutes: 0,
                                                platform: "5", progress: 0, updatedAt: now)),
            ("Einsteigen", FollowLiveState(stage: .boarding, nextStopName: "Salzburg Hbf",
                                           nextStopTime: now.addingTimeInterval(5 * 60), delayMinutes: 0,
                                           platform: "5", progress: 0, updatedAt: now)),
            ("Unterwegs, verspätet", FollowLiveState(stage: .riding, nextStopName: "Linz Hbf",
                                                     nextStopTime: now.addingTimeInterval(40 * 60), delayMinutes: 6,
                                                     platform: "11", progress: 0.5, updatedAt: now)),
            ("Umstieg in Wien", FollowLiveState(stage: .transfer, delayMinutes: 6, platform: "11", progress: 1,
                                                transferStation: "Wien Hbf",
                                                transferDeparture: now.addingTimeInterval(18 * 60), updatedAt: now)),
            ("Angekommen", FollowLiveState(stage: .arrived, delayMinutes: 6, platform: "11", progress: 1, updatedAt: now)),
            ("Fällt aus", FollowLiveState(stage: .cancelled, updatedAt: now)),
        ]
    }
}

private struct FollowStatesShot: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Live verfolgen")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(FollowDemo.stages.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(item.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                        FollowLockScreenView(attributes: FollowDemo.attributes, state: item.state)
                            .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile))
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.m)
        }
        .background(Theme.background)
    }
}

private struct FollowActivityPreviewShot: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Sperrbildschirm")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                FollowLockScreenView(attributes: FollowDemo.attributes, state: FollowDemo.stages[2].state)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.tile))

                Text("Dynamic Island, erweitert")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                VStack(spacing: 8) {
                    HStack(alignment: .center) {
                        FollowIslandCompactLeading(attributes: FollowDemo.attributes)
                        Spacer(minLength: 12)
                        FollowIslandCompactTrailing(state: FollowDemo.stages[2].state)
                    }
                    FollowIslandExpandedCenter(attributes: FollowDemo.attributes, state: FollowDemo.stages[2].state)
                    FollowIslandExpandedBottom(state: FollowDemo.stages[2].state)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.black, in: .rect(cornerRadius: 28))

                Text("Dynamic Island, kompakt und minimal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        FollowIslandCompactLeading(attributes: FollowDemo.attributes)
                        FollowIslandCompactTrailing(state: FollowDemo.stages[2].state)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black, in: .capsule)
                    ZStack {
                        Circle().fill(Color.black)
                        FollowIslandMinimal(state: FollowDemo.stages[2].state)
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.m)
        }
        .background(Theme.background)
    }
}

private struct FollowNoticeSettingsShot: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            List {
                SetFollowNoticesSection()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Mitteilungen")
            .task {
                // Demo: the switch is on so that the scene shows the switches (screenshot runs keep their own defaults).
                if !app.settings.followNotices.isEnabled {
                    var next = app.settings.followNotices
                    next.isEnabled = true
                    app.settings.followNotices = next
                }
            }
        }
    }
}
