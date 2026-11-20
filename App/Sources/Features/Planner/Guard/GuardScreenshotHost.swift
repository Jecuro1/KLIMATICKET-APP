import SwiftUI
import KlimaCore

// MARK: anschluss – CI screenshot scenes of the Anschluss-Wächter (synthetic, no network, no notification permission, no Live
// Activity): the follow sheet of the demo run RJX 66 with the card in each state, the alternatives, the tab bar accessory with
// the badge, and the card at AX5. The follow starts like `ScottyFollowShot`; the guard's answers are scripted (`GuardDemo`).

struct GuardScreenshotHost: View {
    static let screens: Set<String> = ["guardSafe", "guardTighter", "guardShaky", "guardMissed", "guardCancelled", "guardNoRealtime",
                                       "guardAlternatives", "guardAccessory", "guardAX5", "guardOver",
                                       "guardEnded", "guardEndedAX5", "guardOverShort"]   // MARK: fix-anschluss

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
        case "guardOver": .over
        case "guardEnded": .ended
        case "guardEndedAX5": .endedAX5
        case "guardOverShort": .overShort
        default: .shaky
        }
    }

    var body: some View {
        content
            .task {
                let now = GuardDemo.sceneNow()
                if !scene.isCardOnly {
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
        case .noRealtime, .over, .ended, .overShort:
            GuardCardOnlyShot(target: GuardDemo.followTarget(scene, now: GuardDemo.sceneNow()))
        case .endedAX5:
            // The card's end at AX5 (its top is the same as in guardAX5): the reason, „Prüfung beendet“ and what is offered.
            GuardCardOnlyShot(target: GuardDemo.followTarget(scene, now: GuardDemo.sceneNow()), showsEnd: true)
                .dynamicTypeSize(.accessibility5)
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
    /// Opens scrolled to the end of the card (the AX5 scene of the end).
    var showsEnd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ConnectionGuardCard(target: target, snapshot: nil)
                    .padding(Theme.Spacing.cardGutter)
            }
            .defaultScrollAnchor(showsEnd ? .bottom : .top)
            .ambientBackground(.standard, glow: 0.3)
            .navigationTitle(target.lineName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
