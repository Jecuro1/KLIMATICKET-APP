import SwiftUI
import KlimaCore

/// CI screenshot routes of the on-device assistant (`-KBScreenshot <screen> -KBDemo YES`, docs/LOCAL_AI.md §5).
/// Demo mode: the scenes show deterministic texts and never ask the model.
struct AIScreenshotHost: View {
    static let screens: Set<String> = ["aiAvailable", "aiUnavailable", "aiPlannerQuery", "aiBalance"]

    let screen: String
    @Environment(AppState.self) private var app

    var body: some View {
        switch screen {
        case "aiAvailable":
            NavigationStack { AssistantSettingsView() }
                .onAppear { app.assistant.showPreview(.available) }
        case "aiUnavailable":
            NavigationStack { AssistantSettingsView() }
                .onAppear { app.assistant.showPreview(.appleIntelligenceNotEnabled) }
        case "aiPlannerQuery":
            AssistantTripQuerySheet(initialText: "nächste Woche Freitag nach Innsbruck, Rückfahrt Sonntag", autoRun: true)
        default:
            AssistantBalanceSheet(facts: BalanceFacts.demo)
        }
    }
}
