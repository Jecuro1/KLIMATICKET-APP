import BackgroundTasks
import Foundation
import UIKit
import KlimaCore

// Live verfolgen: the background refresh (docs/OEBB_LIVE.md §R8). iOS decides when, whether and how often an app refresh
// runs. The app only submits "not before" times (`earliestBeginDate`) and never promises a notice at a given minute. Each
// run asks ÖBB about the saved follow once, and only when the user switched Live-Mitteilungen on and granted live data.
// Nothing runs for a user who has not switched it on, and nothing runs once the follow is over.

enum FollowBackgroundRefresh {
    static let identifier = "com.knitelarlberg.klimabilanz.follow-refresh"

    /// Registers the launch handler. Called from the app delegate during launch, before the app finishes launching.
    static func register() {
        guard !LaunchMode.isSandboxed else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Asks iOS for a refresh no earlier than `date`. A request only: iOS may run it later, or not at all (Background App
    /// Refresh off, low power mode, or the user closing the app).
    static func schedule(at date: Date) {
        guard !LaunchMode.isSandboxed else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS refused the request. The foreground polling keeps working; nothing else to do.
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    /// Whether iOS currently lets apps refresh in the background (Einstellungen › Allgemein › Hintergrundaktualisierung).
    @MainActor
    static var isBackgroundRefreshAvailable: Bool {
        UIApplication.shared.backgroundRefreshStatus == .available
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            guard let live = AppDelegate.appState?.live else {
                task.setTaskCompleted(success: false)
                return
            }
            let refreshed = await LiveFollowTracker.shared.refreshInBackground(live: live)
            task.setTaskCompleted(success: refreshed)
        }
        task.expirationHandler = { work.cancel() }
    }
}
