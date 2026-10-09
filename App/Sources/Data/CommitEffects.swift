import Foundation
import SwiftData
import UIKit
import OSLog

/// The work that follows a save, coalesced so a tap only pays for `context.save()`:
/// • widget snapshot + timeline reload ~0.35 s later – one rebuild for a burst of commits (editor save + "Als Favorit",
///   "Duplizieren" with a note, quick-log ingest), after the sheet dismissal / toast animation started;
/// • the cloud sync pass ~1 s later (SyncService also coalesces overlapping passes), followed by a widget refresh so
///   rows pulled from other devices reach the widgets;
/// • a retry of a save that failed.
/// Everything pending runs at once when the app resigns active, so a suspended task never leaves the widgets or the
/// cloud behind.
@MainActor
enum CommitEffects {
    private struct Target {
        let context: ModelContext
        let app: AppState
    }

    private static var widgetTarget: Target?
    private static var widgetTask: Task<Void, Never>?
    private static var syncTarget: Target?
    private static var syncTask: Task<Void, Never>?
    private static var retryTarget: Target?
    private static var retryTask: Task<Void, Never>?
    private static var lifecycleObserver: NSObjectProtocol?

    static let widgetDelay: Duration = .milliseconds(350)
    static let syncDelay: Duration = .seconds(1)
    static let retryDelay: Duration = .seconds(8)

    // MARK: Widgets

    static func scheduleWidgetRefresh(context: ModelContext, app: AppState) {
        observeLifecycle()
        widgetTarget = Target(context: context, app: app)
        widgetTask?.cancel()
        widgetTask = Task { @MainActor in
            try? await Task.sleep(for: widgetDelay)
            guard !Task.isCancelled else { return }
            runWidgetRefresh()
        }
    }

    /// Called by `Repository.refreshWidgets()`: a refresh that just ran makes the scheduled one redundant.
    static func widgetRefreshDidRun() {
        widgetTask?.cancel()
        widgetTask = nil
        widgetTarget = nil
    }

    private static func runWidgetRefresh() {
        guard let target = widgetTarget else { return }
        Repository(context: target.context, app: target.app).refreshWidgets()
    }

    // MARK: Sync

    static func scheduleSync(context: ModelContext, app: AppState) {
        observeLifecycle()
        syncTarget = Target(context: context, app: app)
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: syncDelay)
            guard !Task.isCancelled else { return }
            await runSync()
        }
    }

    private static func runSync() async {
        guard let target = syncTarget else { return }
        syncTarget = nil
        // From here on the pass must not be cancelled (URLSession would fail it): a commit during the pass schedules a
        // new debounce instead, and SyncService turns it into one follow-up pass.
        syncTask = nil
        await target.app.sync.sync(context: target.context, auth: target.app.auth)
        if case .synced = target.app.sync.state {
            Repository(context: target.context, app: target.app).refreshWidgets()   // no-op when nothing changed
        }
    }

    // MARK: Failed saves

    /// The changes stay pending in the context; try again a little later (and when the app resigns active).
    static func scheduleSaveRetry(context: ModelContext, app: AppState) {
        observeLifecycle()
        retryTarget = Target(context: context, app: app)
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else { return }
            retrySave()
        }
    }

    /// A later commit saved the pending changes.
    static func saveDidSucceed() {
        retryTask?.cancel()
        retryTask = nil
        retryTarget = nil
    }

    private static func retrySave() {
        guard let target = retryTarget else { return }
        retryTarget = nil
        retryTask = nil
        guard target.context.hasChanges else { return }
        do {
            try target.context.save()
            Repository.log.notice("pending changes saved on retry")
            Analytics.invalidateCache()
            scheduleWidgetRefresh(context: target.context, app: target.app)
            scheduleSync(context: target.context, app: target.app)
        } catch {
            // Next chances: the next commit, resign-active, SwiftData's autosave.
            Repository.log.error("retry save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Lifecycle

    /// Runs everything pending now – the app is about to become inactive and may be suspended.
    static func flush() {
        if retryTarget != nil {
            retryTask?.cancel()
            retrySave()
        }
        if widgetTarget != nil {
            widgetTask?.cancel()
            runWidgetRefresh()
        }
        if syncTarget != nil {
            syncTask?.cancel()
            // The app is on its way to the background: ask iOS for the time to finish this pass (a just-saved trip
            // would otherwise wait for the next launch to reach the cloud).
            let assertion = BackgroundAssertion(name: "KlimaBilanz.sync")
            syncTask = Task { @MainActor in
                await runSync()
                assertion.end()
            }
        }
    }

    private static func observeLifecycle() {
        guard lifecycleObserver == nil else { return }
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { flush() }
        }
    }
}

/// A UIKit background-task assertion that ends once – when the work is done or when iOS's time runs out.
@MainActor
private final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
