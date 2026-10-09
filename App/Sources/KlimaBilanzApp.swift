import SwiftUI
import SwiftData
import KlimaCore

@main
struct KlimaBilanzApp: App {
    @State private var app: AppState
    private let container: ModelContainer

    init() {
        if LaunchMode.isScreenshot {
            // Deterministic, isolated state for CI screenshots.
            let settings = AppSettings(defaults: UserDefaults(suiteName: "screenshots") ?? .standard)
            settings.onboardingCompleted = LaunchMode.screenshotScreen != "onboarding"
            settings.hapticsEnabled = false
            settings.autoUpdateCheck = false
            _app = State(initialValue: AppState(settings: settings))
            container = DataSchema.makeContainer(inMemory: true)
            if LaunchMode.screenshotScreen != "onboarding" {
                DemoData.seed(into: container.mainContext)
            }
        } else {
            _app = State(initialValue: AppState())
            container = DataSchema.makeContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(container)
    }
}
