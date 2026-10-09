import SwiftUI
import SwiftData
import UserNotifications
import KlimaCore

@main
struct KlimaBilanzApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launch: AppLaunch

    init() {
        let launch: AppLaunch
        if let screen = LaunchMode.screenshotScreen {
            // Deterministic, isolated state for CI screenshots.
            let settings = AppSettings(defaults: UserDefaults(suiteName: "screenshots") ?? .standard)
            settings.onboardingCompleted = screen != "onboarding"
            settings.hapticsEnabled = false
            settings.autoUpdateCheck = false
            launch = AppLaunch(store: Self.screenshotStore(for: screen)) { AppState(settings: settings) }
        } else {
            launch = AppLaunch(store: StoreLoader()) { AppState() }
        }
        _launch = State(initialValue: launch)
        AppDelegate.launch = launch
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate(launch: launch)
        }
    }

    /// In-memory demo data – or, for the recovery screens, a fixed phase without any store.
    @MainActor
    private static func screenshotStore(for screen: String) -> StoreLoader {
        switch screen {
        case "storeLocked":
            return StoreLoader(previewPhase: .waitingForUnlock)
        case "storeFailed":
            return StoreLoader(previewPhase: .failed(.init(kind: .unreadable, detail: "NSCocoaErrorDomain 134110 → NSCocoaErrorDomain 134100",
                                                           backup: URL(filePath: "/tmp/StoreBackups/20261009-174512-fehler"),
                                                           backupFiles: [])))
        default:
            let container = DataSchema.makeInMemoryContainer()
            if screen != "onboarding" { DemoData.seed(into: container.mainContext) }
            return StoreLoader(container: container)
        }
    }
}

/// The store plus the app state. The app state is created once the store is open: in a launch before the first unlock
/// after a restart, UserDefaults and the Keychain read as empty too, and settings built from them would show onboarding.
@Observable
@MainActor
final class AppLaunch {
    let store: StoreLoader
    private(set) var app: AppState?
    private let makeAppState: () -> AppState

    init(store: StoreLoader, makeAppState: @escaping () -> AppState) {
        self.store = store
        self.makeAppState = makeAppState
        store.onOpen = { [weak self] _, event in self?.storeDidOpen(event) }
        store.start()
    }

    private func storeDidOpen(_ event: StoreLoader.OpenEvent) {
        let app = self.app ?? makeAppState()
        self.app = app
        if event == .startedFresh {
            // The rows are gone from this device: a signed-in account downloads everything again (the pull cursors
            // would otherwise only fetch changes newer than the last sync).
            app.sync.resetSyncCursor()
        }
    }
}

/// RootView with the open store – or the loading / recovery screen while there is none. Nothing below RootView
/// (widget refresh, quick-log ingest, sync, onboarding) runs before the user's real store is open.
private struct LaunchGate: View {
    let launch: AppLaunch
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let app = launch.app, let container = launch.store.container {
                RootView()
                    .environment(app)
                    .modelContainer(container)
            } else {
                StoreRecoveryView(store: launch.store)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { launch.store.retryIfNeeded() }
        }
    }
}

/// Notification handling (foreground banners, the "Erfassen" action of trip suggestions, routing a tap to its tab).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static var launch: AppLaunch?
    /// nil until the store is open (see AppLaunch).
    @MainActor static var appState: AppState? { launch?.app }
    @MainActor static var container: ModelContainer? { launch?.store.container }

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
            // A response right after the first unlock can arrive before the scene retried opening the store.
            AppDelegate.launch?.store.retryIfNeeded()
            guard let app = AppDelegate.appState, let container = AppDelegate.container else { return }
            if category == TripDetectionService.notificationCategory {
                if action == TripDetectionService.confirmAction {
                    app.detection.handleNotificationResponse(identifier: identifier,
                                                             repository: Repository(context: container.mainContext, app: app))
                } else {
                    app.selectedTab = .overview
                }
                return
            }
            guard action == UNNotificationDefaultActionIdentifier else { return }
            if identifier.hasPrefix("renewal.") {
                app.selectedTab = .ticket            // "Morgen läuft dein Ticket ab"
            } else if identifier == "weekly.summary" || identifier.hasPrefix("breakeven.") {
                app.selectedTab = .overview          // "Deine Woche mit den Öffis", "… hat sich rentiert"
            }
        }
    }
}
