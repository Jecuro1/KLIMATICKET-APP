import SwiftUI
import SwiftData
import UserNotifications
import KlimaCore

@main
struct KlimaBilanzApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app: AppState
    private let container: ModelContainer

    init() {
        // MARK: Diagnostics – launch timing starts here (Einstellungen › Diagnose & Stabilität).
        DiagnosticsService.shared.markLaunchStart()
        let state: AppState
        if LaunchMode.isScreenshot {
            // Deterministic, isolated state for CI screenshots.
            let settings = AppSettings(defaults: UserDefaults(suiteName: "screenshots") ?? .standard)
            settings.onboardingCompleted = LaunchMode.screenshotScreen != "onboarding"
            settings.hapticsEnabled = false
            settings.autoUpdateCheck = false
            state = AppState(settings: settings)
            container = DataSchema.makeContainer(inMemory: true)
            if LaunchMode.screenshotScreen != "onboarding" {
                DemoData.seed(into: container.mainContext)
            }
        } else if LaunchMode.isPerf {
            // MARK: Diagnostics – CI performance tests: the normal tab interface with in-memory demo data.
            state = AppState(settings: PerfMode.makeSettings())
            container = DataSchema.makeContainer(inMemory: true)
            PerfMode.seed(into: container.mainContext)
        } else {
            state = AppState()
            container = DataSchema.makeContainer()
        }
        _app = State(initialValue: state)
        AppDelegate.appState = state
        AppDelegate.container = container
        DiagnosticsService.shared.start(mode: LaunchMode.isScreenshot ? .screenshot : (LaunchMode.isPerf ? .perf : .standard))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(container)
    }
}

/// Notification handling (foreground banners + "Erfassen" action of trip suggestions).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var appState: AppState?
    @MainActor static var container: ModelContainer?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await MainActor.run {
            guard category == TripDetectionService.notificationCategory,
                  let app = AppDelegate.appState, let container = AppDelegate.container else { return }
            let repo = Repository(context: container.mainContext, app: app)
            if action == TripDetectionService.confirmAction {
                app.detection.handleNotificationResponse(identifier: identifier, repository: repo)
            } else {
                app.selectedTab = .overview
            }
        }
    }
}
