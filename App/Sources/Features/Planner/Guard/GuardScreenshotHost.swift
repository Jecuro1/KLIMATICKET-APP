import SwiftUI
import KlimaCore

// MARK: anschluss – CI screenshot scenes of the Anschluss-Wächter (synthetic, no network, no notification permission, no Live
// Activity): the follow sheet of the demo run RJX 66 with the card in each state, the alternatives, the tab bar accessory with
// the badge, and the card at AX5. The follow starts like `ScottyFollowShot`; the guard's answers are scripted (`GuardDemo`).

struct GuardScreenshotHost: View {
    static let screens: Set<String> = ["guardSafe", "guardTighter", "guardShaky", "guardMissed", "guardCancelled", "guardNoRealtime",
                                       "guardAlternatives", "guardAccessory", "guardAX5"]

    let screen: String
    @Environment(AppState.self) private var app

    private var scene: GuardDemo.Scene {
        switch screen {
        case "guardSafe": .safe
        case "guardTighter": .tighter
        case "guardMissed": .missed
        case "guardCancelled": .cancelled
        case "guardNoRealtime": .noRealtime
        case "guardAlternatives": .alternatives
        case "guardAccessory": .accessory
        case "guardAX5": .ax5
        default: .shaky
        }
    }

    var body: some View {
        content
            .task {
                let now = Date()
                if scene != .noRealtime {
                    LiveFollowTracker.shared.start(GuardDemo.followTarget(scene, now: now), live: app.live)
                }
                GuardDemo.install(scene, now: now)
                if scene == .accessory { app.selectedTab = .overview }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .accessory:
            MainTabView()
        case .noRealtime:
            GuardCardOnlyShot(target: GuardDemo.followTarget(.noRealtime, now: Date()))
        case .alternatives:
            GuardAlternativesSheet()
        case .ax5:
            LiveFollowDetailSheet(tracker: LiveFollowTracker.shared)
                .dynamicTypeSize(.accessibility5)
        default:
            LiveFollowDetailSheet(tracker: LiveFollowTracker.shared)
        }
    }
}

/// The card on its own (a connection without realtime: no follow answer with realtime may stand next to it).
private struct GuardCardOnlyShot: View {
    let target: LiveFollowTarget

    var body: some View {
        NavigationStack {
            ScrollView {
                ConnectionGuardCard(target: target, snapshot: nil)
                    .padding(Theme.Spacing.cardGutter)
            }
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle(target.lineName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
