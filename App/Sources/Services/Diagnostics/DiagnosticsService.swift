import Foundation
import UIKit
import MetricKit
import os

/// Local stability diagnostics – nothing leaves the device unless the user shares the export file.
///
/// * **MetricKit**: subscribes to `MXMetricManager`, stores crash / hang / CPU / disk-write / launch diagnostics and
///   the daily metrics as JSON (30 days, size-capped).
/// * **Hang watchdog**: pings the main queue every 0.5 s and logs every hang > 250 ms with the visible screen.
/// * **Breadcrumbs**: ring buffer of screens, sheets and key actions, persisted (coalesced) so the steps before a
///   crash survive it.
/// * **Sessions**: a session that ends in the foreground without a clean exit is reported on the next launch.
/// * **Timings**: count / average / max of instrumented hot paths (`Diagnostics.measure`), per session.
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsService()

    enum Mode {
        /// Normal app: real storage, watchdog per user setting.
        case standard
        /// CI performance tests (`-KBPerf`): real storage, watchdog on.
        case perf
        /// CI screenshots: throw-away storage with sample entries, no watchdog, no MetricKit.
        case screenshot
    }

    static let watchdogDefaultsKey = "diagnosticsHangWatchdog"
    private static let logger = Logger(subsystem: "com.knitelarlberg.klimabilanz", category: "Diagnostics")

    let breadcrumbs = BreadcrumbLog()
    let timings = TimingLog()
    private(set) var store = DiagnosticsStore(root: DiagnosticsStore.defaultRoot)
    private let watchdog = HangWatchdog()

    private let lock = NSLock()
    private var session: DiagnosticsSession
    private var started = false
    private var flushScheduled = false
    private var launchStart: UInt64 = DispatchTime.now().uptimeNanoseconds
    private var firstFrameSeen = false
    private var watchdogHangsThisSession = 0
    private var observers: [NSObjectProtocol] = []

    /// At most this many watchdog events per session (a permanently slow screen must not flood the log).
    static let maxWatchdogEventsPerSession = 150

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let prewarmed = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
        session = DiagnosticsSession(
            id: UUID().uuidString, startedAt: Date(), lastSeenAt: Date(), state: .launching, prewarmed: prewarmed,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        super.init()
        breadcrumbs.onChange = { [weak self] in self?.scheduleFlush() }
    }

    // MARK: Lifecycle

    /// Earliest point of the launch (call first thing in `KlimaBilanzApp.init`).
    func markLaunchStart() {
        lock.lock()
        launchStart = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    /// Starts everything. Cheap on the calling (main) thread – file work happens on the store's queue.
    @MainActor
    func start(mode: Mode) {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        if mode == .screenshot {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticsScreenshot", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            store = DiagnosticsStore(root: root)
        }
        let store = store
        let current = currentSession()
        store.queue.async {
            store.ensureDirectories()
            self.closePreviousSession(store: store, current: current)
            if mode == .screenshot { self.seedScreenshotSamples(store: store) }
            store.prunePayloads()
            store.saveEventsIfNeeded()
        }

        breadcrumbs.record(.lifecycle, "launch", detail: "\(current.appVersion) (\(current.build))")
        observeLifecycle()

        guard mode != .screenshot else { return }
        MXMetricManager.shared.add(self)
        store.queue.async {
            // Payloads iOS delivered before this subscriber existed (deduplicated by content hash).
            let manager = MXMetricManager.shared
            self.ingest(diagnostics: manager.pastDiagnosticPayloads)
            self.ingest(metrics: manager.pastPayloads)
        }

        configureWatchdog()
        // CI performance tests: frame pacing, transitions and memory per screen (perf-<session>.json).
        if mode == .perf { PerfFrameMonitor.shared.start() }
        // Starts paused; `didBecomeActive` resumes it (the observers above exist before the app first becomes active –
        // `UIApplication.shared` must not be touched this early, `App.init` may run before it exists).
        if mode == .perf || isWatchdogEnabled { watchdog.start() }
    }

    var isWatchdogEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.watchdogDefaultsKey) as? Bool ?? true
    }

    @MainActor
    func setWatchdogEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.watchdogDefaultsKey)
        breadcrumbs.record(.action, "diagnostics.watchdog", detail: enabled ? "on" : "off")
        if enabled {
            watchdog.start()
            watchdog.resume()
        } else {
            watchdog.stop()
        }
    }

    /// First appearance of the root view – completes the launch timing.
    func markFirstFrame() {
        lock.lock()
        guard !firstFrameSeen else { lock.unlock(); return }
        firstFrameSeen = true
        let initMs = Double(DispatchTime.now().uptimeNanoseconds &- launchStart) / 1_000_000
        var processMs: Double?
        if !session.prewarmed, let start = Self.processStartDate() {
            processMs = Date().timeIntervalSince(start) * 1000
        }
        session.launch = LaunchTiming(initToFirstFrameMs: initMs, processToFirstFrameMs: processMs)
        lock.unlock()
        breadcrumbs.record(.perf, "firstFrame", detail: "\(Int(initMs.rounded())) ms seit init"
                           + (processMs.map { ", \(Int($0.rounded())) ms seit Prozessstart" } ?? ""))
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        let pairs: [(Notification.Name, DiagnosticsSession.State?, String)] = [
            (UIApplication.didBecomeActiveNotification, .active, "active"),
            (UIApplication.willResignActiveNotification, .inactive, "inactive"),
            (UIApplication.didEnterBackgroundNotification, .background, "background"),
            (UIApplication.willEnterForegroundNotification, nil, "foreground"),
            (UIApplication.didReceiveMemoryWarningNotification, nil, "memoryWarning"),
        ]
        for (name, state, label) in pairs {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.handleLifecycle(state: state, label: label)
            })
        }
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.updateSession { $0.state = .terminated }
            self.breadcrumbs.record(.lifecycle, "terminate")
            self.flushNow(synchronously: true)
        })
    }

    private func handleLifecycle(state: DiagnosticsSession.State?, label: String) {
        if let state { updateSession { $0.state = state } }
        breadcrumbs.record(.lifecycle, label)
        switch state {
        case .active?: watchdog.resume()
        case .background?: watchdog.pause()
        default: break
        }
        if state == .inactive || state == .background { flushNow(synchronously: false) }
    }

    // MARK: Session

    var currentSessionID: String { currentSession().id }
    var currentLaunchTiming: LaunchTiming? { currentSession().launch }
    var currentHangCount: Int { currentSession().hangCount }

    private func currentSession() -> DiagnosticsSession {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    private func updateSession(_ change: (inout DiagnosticsSession) -> Void) {
        lock.lock()
        change(&session)
        lock.unlock()
    }

    /// Runs once per launch on the store queue: reports how the previous session ended and rotates its files.
    private func closePreviousSession(store: DiagnosticsStore, current: DiagnosticsSession) {
        var file = store.read(DiagnosticsSessionsFile.self, from: "sessions.json") ?? DiagnosticsSessionsFile(current: nil, history: [])
        var events: [DiagnosticsEvent] = []
        let marker = store.read(HangMarker.self, from: "hang-inprogress.json")

        if let previous = file.current, previous.id != current.id {
            if let marker, marker.sessionID == previous.id {
                events.append(DiagnosticsEvent(
                    id: "fatal-\(previous.id)", kind: .fatalHang, source: .watchdog, date: marker.start,
                    durationMs: marker.durationMs, screen: marker.screen,
                    title: "Hänger bis zum Ende der App",
                    detail: "Hauptthread mindestens \(Self.seconds(marker.durationMs)) blockiert, danach wurde die App beendet",
                    appVersion: previous.appVersion, build: previous.build))
            } else if previous.endedUnexpectedly {
                let during = previous.state == .launching ? "beim Start" : "im Vordergrund"
                events.append(DiagnosticsEvent(
                    id: "exit-\(previous.id)", kind: .abnormalExit, source: .session, date: previous.lastSeenAt,
                    screen: previous.lastScreen, title: "Unerwartet beendet",
                    detail: "Die App endete \(during) ohne sauberes Beenden (Absturz, Hänger oder Speicher)",
                    appVersion: previous.appVersion, build: previous.build))
            }
            file.history.append(previous)
            file.history = Array(file.history.suffix(DiagnosticsStore.maxSessions))
        }
        store.remove("hang-inprogress.json")
        file.current = current
        store.write(file, to: "sessions.json")
        store.move("breadcrumbs.json", to: "breadcrumbs-previous.json")
        store.append(events)
    }

    // MARK: Watchdog

    private func configureWatchdog() {
        watchdog.screenProvider = { [weak self] in self?.breadcrumbs.currentScreen }
        watchdog.onHang = { [weak self] hang in self?.recordWatchdogHang(hang) }
        watchdog.onLongHang = { [weak self] hang in
            guard let self else { return }
            let sessionID = self.currentSession().id
            let store = self.store
            store.queue.async {
                if let hang {
                    store.write(HangMarker(sessionID: sessionID, start: hang.start, durationMs: hang.durationMs, screen: hang.screen),
                                to: "hang-inprogress.json")
                } else {
                    store.remove("hang-inprogress.json")
                }
            }
        }
    }

    private func recordWatchdogHang(_ hang: HangWatchdog.Hang) {
        lock.lock()
        session.hangCount += 1
        session.longestHangMs = max(session.longestHangMs, hang.durationMs)
        watchdogHangsThisSession += 1
        let logEvent = watchdogHangsThisSession <= Self.maxWatchdogEventsPerSession
        let current = session
        lock.unlock()

        Self.logger.notice("Hang \(Int(hang.durationMs.rounded())) ms on \(hang.screen ?? "?", privacy: .public)")
        breadcrumbs.record(.perf, "hang", detail: "\(Int(hang.durationMs.rounded())) ms")
        guard logEvent else { return }
        let event = DiagnosticsEvent(
            id: "wd-\(current.id.prefix(8))-\(Int(hang.start.timeIntervalSince1970 * 1000))", kind: .watchdogHang,
            source: .watchdog, date: hang.start, durationMs: hang.durationMs, screen: hang.screen,
            title: "Hänger", detail: "Hauptthread \(Int(hang.durationMs.rounded())) ms blockiert",
            appVersion: current.appVersion, build: current.build)
        let store = store
        store.queue.async { store.append([event]) }
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXMetricPayload]) {
        store.queue.async { self.ingest(metrics: payloads) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        store.queue.async { self.ingest(diagnostics: payloads) }
    }

    /// Call on the store queue.
    private func ingest(diagnostics payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        var events: [DiagnosticsEvent] = []
        for payload in payloads {
            let (name, data) = MetricKitParser.fileName(for: payload)
            store.storePayload(named: name, data: data)
            events += MetricKitParser.events(from: payload, file: name)
        }
        store.append(events)
        store.prunePayloads()
        breadcrumbs.record(.lifecycle, "metricKit.diagnostics", detail: "\(events.count) Einträge")
    }

    /// Call on the store queue.
    private func ingest(metrics payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        var latest: MXMetricPayload?
        for payload in payloads {
            let (name, data) = MetricKitParser.fileName(for: payload)
            store.storePayload(named: name, data: data)
            if latest == nil || payload.timeStampEnd > latest!.timeStampEnd { latest = payload }
        }
        if let latest {
            let highlights = MetricKitParser.highlights(from: latest)
            let existing = store.read(MetricKitHighlights.self, from: "metrics-highlights.json")
            if existing == nil || existing!.periodEnd <= highlights.periodEnd {
                store.write(highlights, to: "metrics-highlights.json")
            }
        }
        store.prunePayloads()
    }

    // MARK: Persistence

    private func scheduleFlush() {
        lock.lock()
        guard !flushScheduled, started else { lock.unlock(); return }
        flushScheduled = true
        lock.unlock()
        store.queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.flushScheduled = false
            self.lock.unlock()
            self.writeSessionFiles()
        }
    }

    private func flushNow(synchronously: Bool) {
        if synchronously {
            store.queue.sync { writeSessionFiles() }
        } else {
            store.queue.async { self.writeSessionFiles() }
        }
    }

    /// Call on the store queue.
    private func writeSessionFiles() {
        updateSession {
            $0.lastSeenAt = Date()
            $0.lastScreen = breadcrumbs.currentScreen
            $0.timings = timings.snapshot()
        }
        let current = currentSession()
        var file = store.read(DiagnosticsSessionsFile.self, from: "sessions.json") ?? DiagnosticsSessionsFile(current: nil, history: [])
        file.current = current
        store.write(file, to: "sessions.json")
        store.write(DiagnosticsBreadcrumbFile(sessionID: current.id, crumbs: breadcrumbs.snapshot()), to: "breadcrumbs.json")
        store.saveEventsIfNeeded()
    }

    // MARK: Reading (settings page, export)

    func overview() async -> DiagnosticsOverview {
        let store = store
        let running = snapshotForReading()
        return await withCheckedContinuation { continuation in
            store.queue.async {
                continuation.resume(returning: Self.makeOverview(store: store, running: running))
            }
        }
    }

    private func snapshotForReading() -> DiagnosticsSession {
        updateSession {
            $0.lastScreen = breadcrumbs.currentScreen
            $0.timings = timings.snapshot()
        }
        return currentSession()
    }

    private static func makeOverview(store: DiagnosticsStore, running: DiagnosticsSession) -> DiagnosticsOverview {
        let now = Date()
        let since = now.addingTimeInterval(-DiagnosticsStore.retention)
        let events = DiagnosticsStore.pruned(store.events(), now: now)
        let sessions = store.read(DiagnosticsSessionsFile.self, from: "sessions.json")
        let lastLaunch = running.launch ?? sessions?.history.last?.launch
        let hangs = events.filter(\.isHang)
        return DiagnosticsOverview(
            since: since,
            crashes: events.filter(\.isCrashLike).count,
            hangs: hangs.count,
            longestHangMs: hangs.compactMap(\.durationMs).max(),
            abnormalExits: events.filter { $0.kind == .abnormalExit }.count,
            resourceWarnings: events.filter(\.isResourceWarning).count,
            slowLaunches: events.filter { $0.kind == .slowLaunch }.count,
            latest: Array(events.reversed().prefix(20)),
            lastLaunch: lastLaunch,
            sessionCount: (sessions?.history.filter { $0.startedAt >= since }.count ?? 0) + 1,
            metricKit: store.read(MetricKitHighlights.self, from: "metrics-highlights.json"),
            metricKitPayloadCount: store.payloadFiles().count,
            timings: running.timings)
    }

    /// Deletes all stored diagnostics (the running session keeps counting).
    func clearAll() async {
        let store = store
        breadcrumbs.clear()
        breadcrumbs.record(.action, "diagnostics.clear")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.queue.async {
                store.clearAll()
                store.write(DiagnosticsSessionsFile(current: self.currentSession(), history: []), to: "sessions.json")
                store.remove("metrics-highlights.json")
                continuation.resume()
            }
        }
    }

    // MARK: Export

    /// Writes the shareable JSON bundle (diagnostics, breadcrumbs, sessions, timings, raw MetricKit payloads,
    /// app/device info, data counts) to a temporary file.
    func writeExport(context: DiagnosticsExportContext) async throws -> URL {
        let store = store
        let running = snapshotForReading()
        let currentCrumbs = breadcrumbs.snapshot()
        return try await withCheckedThrowingContinuation { continuation in
            store.queue.async {
                do {
                    let url = try DiagnosticsExport.write(store: store, running: running, crumbs: currentCrumbs, context: context)
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Helpers

    static func seconds(_ ms: Double) -> String {
        let value = ms / 1000
        return value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_AT"))) + " s"
    }

    /// Kernel start time of this process (includes the time before `main`), nil if unavailable.
    static func processStartDate() -> Date? {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        #else
        return nil
        #endif
    }

    // MARK: Screenshot samples

    /// Sample entries for the CI screenshot `diagnostics` (never in normal use).
    private func seedScreenshotSamples(store: DiagnosticsStore) {
        let now = Date()
        let version = currentSession().appVersion
        let build = currentSession().build
        func event(_ id: String, _ kind: DiagnosticsEvent.Kind, _ source: DiagnosticsEvent.Source, hoursAgo: Double,
                   ms: Double?, screen: String?, title: String, detail: String) -> DiagnosticsEvent {
            DiagnosticsEvent(id: id, kind: kind, source: source, date: now.addingTimeInterval(-hoursAgo * 3600), durationMs: ms,
                             screen: screen, title: title, detail: detail, appVersion: version, build: build)
        }
        store.append([
            event("s1", .watchdogHang, .watchdog, hoursAgo: 0.6, ms: 420, screen: "Statistik", title: "Hänger",
                  detail: "Hauptthread 420 ms blockiert"),
            event("s2", .watchdogHang, .watchdog, hoursAgo: 5, ms: 1_350, screen: "Fahrten", title: "Hänger",
                  detail: "Hauptthread 1350 ms blockiert"),
            event("s3", .abnormalExit, .session, hoursAgo: 26, ms: nil, screen: "Fahrt erfassen", title: "Unerwartet beendet",
                  detail: "Die App endete im Vordergrund ohne sauberes Beenden (Absturz, Hänger oder Speicher)"),
            event("s4", .crash, .metricKit, hoursAgo: 26, ms: nil, screen: nil, title: "Swift-Laufzeitfehler",
                  detail: "EXC_BREAKPOINT · SIGTRAP · KlimaBilanz +0x4a3f0"),
        ])
        updateSession { $0.launch = LaunchTiming(initToFirstFrameMs: 412, processToFirstFrameMs: 780) }
    }
}
