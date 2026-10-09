import Foundation
import UIKit
import Observation

/// CI performance runs only (`-KBPerf`, `LaunchMode.isPerf`): what the simulator does not report through
/// `XCTOSSignpostMetric` (hitch counts and ratios need a device), measured by the app itself.
///
/// * **Scrolling** – every scroll view in the window is observed (KVO on `contentOffset`, re-scanned once a second
///   while nothing moves). A vertical offset change starts a `CADisplayLink`; it stops 0.3 s after the last change.
///   A frame interval above 1.5 × the expected duration is a hitch, its excess is hitch time; hitch time ratio =
///   hitch ms per scrolled second (Apple: < 5 good, 5–10 noticeable, ≥ 10 critical). Kept per screen and source:
///   `touch` (the XCUITest swipes – dragging or decelerating), `tour` (`PerfTour`) or `other` (programmatic).
/// * **Transitions** – from the moment a tab, the Gipfelbuch or Einstellungen is selected (observation `willSet`,
///   before SwiftUI builds anything) 1.5 s of frames: time to the first frame, longest frame, hitch time.
/// * **Launch** – from `App.init`: time to the first frame, then 4 s of frames like a transition.
/// * **Memory** – physical footprint once a second and after every segment (peak overall and per screen).
///
/// Writes `Diagnostics/perf-<session>.json` (collected by the CI job "perf", read by scripts/perf_summary.py).
@MainActor
final class PerfFrameMonitor: NSObject {
    static let shared = PerfFrameMonitor()

    /// A frame interval above this multiple of the expected duration is a hitch.
    static let hitchFactor = 1.5
    static let idleEnd: TimeInterval = 0.3
    static let transitionWindow: TimeInterval = 1.5
    static let launchWindow: TimeInterval = 4

    // All times are `CACurrentMediaTime()` – the clock of `CADisplayLink.timestamp` (ProcessInfo.systemUptime may
    // count sleep and would never line up with the frames).

    private struct Key: Hashable {
        var screen: String
        var source: String
    }

    fileprivate struct FrameStats: Codable {
        var frames = 0
        var seconds = 0.0
        var hitches = 0
        var hitchMs = 0.0
        /// Intervals above 3 × the expected duration (two or more frames lost).
        var severeHitches = 0
        var longestFrameMs = 0.0

        mutating func add(interval: Double, expected: Double) {
            frames += 1
            seconds += interval
            longestFrameMs = max(longestFrameMs, interval * 1000)
            if interval > expected * PerfFrameMonitor.hitchFactor {
                hitches += 1
                hitchMs += (interval - expected) * 1000
                if interval > expected * 3 { severeHitches += 1 }
            }
        }

        mutating func merge(_ other: FrameStats) {
            frames += other.frames
            seconds += other.seconds
            hitches += other.hitches
            hitchMs += other.hitchMs
            severeHitches += other.severeHitches
            longestFrameMs = max(longestFrameMs, other.longestFrameMs)
        }
    }

    private struct Segment {
        var screen: String
        var stats = FrameStats()
        /// Frame intervals since the last offset change – dropped if the scroll ends without another change.
        var pending: [(interval: Double, expected: Double)] = []
        var sawTouch = false
        var distancePt = 0.0
    }

    struct ScrollRecord: Codable {
        var screen: String
        var source: String
        var segments = 0
        var distancePt = 0.0
        fileprivate var stats = FrameStats()

        enum CodingKeys: String, CodingKey {
            case screen, source, segments, distancePt, frames, seconds, hitches, hitchMs, severeHitches, longestFrameMs
        }

        init(screen: String, source: String) {
            self.screen = screen
            self.source = source
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            screen = try c.decode(String.self, forKey: .screen)
            source = try c.decode(String.self, forKey: .source)
            segments = try c.decode(Int.self, forKey: .segments)
            distancePt = try c.decode(Double.self, forKey: .distancePt)
            stats.frames = try c.decode(Int.self, forKey: .frames)
            stats.seconds = try c.decode(Double.self, forKey: .seconds)
            stats.hitches = try c.decode(Int.self, forKey: .hitches)
            stats.hitchMs = try c.decode(Double.self, forKey: .hitchMs)
            stats.severeHitches = try c.decode(Int.self, forKey: .severeHitches)
            stats.longestFrameMs = try c.decode(Double.self, forKey: .longestFrameMs)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(screen, forKey: .screen)
            try c.encode(source, forKey: .source)
            try c.encode(segments, forKey: .segments)
            try c.encode(distancePt, forKey: .distancePt)
            try c.encode(stats.frames, forKey: .frames)
            try c.encode(stats.seconds, forKey: .seconds)
            try c.encode(stats.hitches, forKey: .hitches)
            try c.encode(stats.hitchMs, forKey: .hitchMs)
            try c.encode(stats.severeHitches, forKey: .severeHitches)
            try c.encode(stats.longestFrameMs, forKey: .longestFrameMs)
        }
    }

    struct TransitionRecord: Codable {
        var from: String
        var to: String
        /// Selection (or App.init for the launch) → first frame after it.
        var firstFrameMs: Double?
        var longestFrameMs = 0.0
        var hitchMs = 0.0
        var frames = 0
        /// Seconds since the monitor started.
        var at: Double
    }

    struct Report: Codable {
        var session: String
        var pid: Int32
        var startedAt: Date
        var extraTrips: Int
        var tour: String?
        var launch: LaunchTiming?
        var launchFrames: TransitionRecord?
        var footprintPeakMB: Double?
        var footprintByScreenMB: [String: Double]
        var scroll: [ScrollRecord]
        var transitions: [TransitionRecord]
        var watchdogHangs: Int
    }

    private final class Watched {
        weak var view: UIScrollView?
        var token: NSKeyValueObservation?
        init(view: UIScrollView) { self.view = view }
    }

    private var isRunning = false
    private var origin: TimeInterval = 0
    private var startedAt = Date()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var lastActivity: TimeInterval = 0
    private var segment: Segment?
    private var scroll: [Key: ScrollRecord] = [:]
    private var transition: (record: TransitionRecord, start: TimeInterval, last: CFTimeInterval?, end: TimeInterval?)?
    private var transitions: [TransitionRecord] = []
    private var launchFrames: TransitionRecord?
    private var watched: [ObjectIdentifier: Watched] = [:]
    private var scanTimer: Timer?
    private var footprintPeak: Double?
    private var footprintByScreen: [String: Double] = [:]
    private var navigationName: String?
    private var observesNavigation = false
    private var writeScheduled = false
    private lazy var fileName = "perf-\(startedAt.timeIntervalSince1970.rounded())-\(ProcessInfo.processInfo.processIdentifier).json"

    /// Called once from `DiagnosticsService.start(mode: .perf)` (App.init) – the launch window starts here.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        origin = CACurrentMediaTime()
        startedAt = Date()
        transition = (TransitionRecord(from: "–", to: "Start", at: 0), origin, nil, nil)
        startLink()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PerfFrameMonitor.shared.periodic() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scanTimer = timer
    }

    // MARK: Display link

    private func startLink() {
        guard link == nil else { return }
        lastTick = nil
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLinkIfIdle() {
        guard segment == nil, transition == nil, !PerfTour.isScrolling else { return }
        link?.invalidate()
        link = nil
        lastTick = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let expected = max(link.targetTimestamp - link.timestamp, 1.0 / 240)
        let previous = lastTick
        lastTick = now

        if var current = transition {
            if current.record.firstFrameMs == nil, now >= current.start {
                // The first frame after the selection: everything SwiftUI did for it happened before this tick.
                current.record.firstFrameMs = (now - current.start) * 1000
                current.end = now + (current.record.to == "Start" ? Self.launchWindow : Self.transitionWindow)
                if current.record.to == "Start" { current.record.to = screenName }
            } else if let last = current.last {
                let interval = now - last
                current.record.frames += 1
                current.record.longestFrameMs = max(current.record.longestFrameMs, interval * 1000)
                if interval > expected * Self.hitchFactor { current.record.hitchMs += (interval - expected) * 1000 }
            }
            current.last = now
            transition = current
            // The window ends after its frames – or at the latest 12 s after the selection (never a display link that
            // keeps running: XCUITest waits for an idle app after every gesture).
            if let end = current.end, now >= end {
                finishTransition()
            } else if now - current.start > 12 {
                finishTransition()
            }
        }

        if segment != nil, let previous {
            segment!.pending.append((now - previous, expected))
            if CACurrentMediaTime() - lastActivity > Self.idleEnd { endSegment() }
        }
        stopLinkIfIdle()
    }

    // MARK: Scrolling

    private func offsetChanged(_ view: UIScrollView, dy: CGFloat) {
        guard abs(dy) >= 0.5, isRunning else { return }
        lastActivity = CACurrentMediaTime()
        if segment == nil {
            segment = Segment(screen: screenName)
            startLink()
        }
        if view.isDragging || view.isDecelerating || view.isTracking { segment!.sawTouch = true }
        segment!.distancePt += Double(abs(dy))
        for frame in segment!.pending { segment!.stats.add(interval: frame.interval, expected: frame.expected) }
        segment!.pending.removeAll(keepingCapacity: true)
    }

    private func endSegment() {
        guard let finished = segment else { return }
        segment = nil
        // A few frames are layout adjustments (insets, content size), not scrolling.
        guard finished.stats.frames >= 10 else { return }
        let source = finished.sawTouch ? "touch" : (PerfTour.isScrolling ? "tour" : "other")
        let key = Key(screen: finished.screen, source: source)
        var record = scroll[key] ?? ScrollRecord(screen: key.screen, source: key.source)
        record.segments += 1
        record.distancePt += finished.distancePt
        record.stats.merge(finished.stats)
        scroll[key] = record
        sampleFootprint()
        scheduleWrite()
    }

    /// Observes every scroll view in the app's windows (new ones appear with sheets and pushed screens).
    private func scan() {
        watched = watched.filter { $0.value.view != nil }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { visit(window) }
        }
    }

    private func visit(_ view: UIView) {
        if let scrollView = view as? UIScrollView { watch(scrollView) }
        for sub in view.subviews { visit(sub) }
    }

    private func watch(_ scrollView: UIScrollView) {
        let id = ObjectIdentifier(scrollView)
        if let entry = watched[id], entry.view === scrollView { return }
        let entry = Watched(view: scrollView)
        entry.token = scrollView.observe(\.contentOffset, options: [.old, .new]) { view, change in
            let dy = (change.newValue?.y ?? 0) - (change.oldValue?.y ?? 0)
            MainActor.assumeIsolated { PerfFrameMonitor.shared.offsetChanged(view, dy: dy) }
        }
        watched[id] = entry
    }

    // MARK: Transitions

    /// Tab / Gipfelbuch / Einstellungen, as the breadcrumbs name them.
    private var screenName: String {
        Diagnostics.service.breadcrumbs.currentScreen ?? "?"
    }

    private func observeNavigation() {
        guard !observesNavigation, let app = AppDelegate.appState else { return }
        observesNavigation = true
        navigationName = Self.navigationName(app)
        track(app)
    }

    private static func navigationName(_ app: AppState) -> String {
        if app.isShowingAchievements { return "Gipfelbuch" }
        if app.isShowingSettings { return "Einstellungen" }
        return app.selectedTab.title
    }

    private func track(_ app: AppState) {
        withObservationTracking {
            _ = app.selectedTab
            _ = app.isShowingAchievements
            _ = app.isShowingSettings
        } onChange: {
            // willSet, on the main thread (AppState is main-actor isolated): the clock starts before SwiftUI builds
            // the new screen. The new value is read on the next turn.
            let start = CACurrentMediaTime()
            MainActor.assumeIsolated { PerfFrameMonitor.shared.beginTransition(at: start) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let monitor = PerfFrameMonitor.shared
                    monitor.resolveTransition(to: Self.navigationName(app))
                    monitor.track(app)
                }
            }
        }
    }

    private func beginTransition(at start: TimeInterval) {
        if transition != nil { finishTransition() }
        transition = (TransitionRecord(from: navigationName ?? "?", to: "?", at: start - origin), start, nil, nil)
        startLink()
    }

    private func resolveTransition(to name: String) {
        if transition != nil, transition!.record.to == "?" {
            if name == navigationName {
                transition = nil   // the value was set to what it already was
            } else {
                transition!.record.to = name
            }
        }
        navigationName = name
    }

    private func finishTransition() {
        guard let finished = transition?.record else { return }
        transition = nil
        if finished.from == "–" {
            launchFrames = finished
        } else if finished.to != "?" {
            transitions.append(finished)
            if transitions.count > 300 { transitions.removeFirst(transitions.count - 300) }
        }
        sampleFootprint()
        scheduleWrite()
    }

    // MARK: Periodic work, memory, file

    private func periodic() {
        observeNavigation()
        sampleFootprint()
        if segment == nil { scan() }
        PerfTour.startIfRequested(firstFrameSeen: launchFrames != nil || transition?.record.firstFrameMs != nil)
    }

    private func sampleFootprint() {
        guard let mb = Self.footprintMB() else { return }
        footprintPeak = max(footprintPeak ?? 0, mb)
        let screen = screenName
        footprintByScreen[screen] = max(footprintByScreen[screen] ?? 0, mb)
    }

    private func scheduleWrite() {
        guard !writeScheduled else { return }
        writeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                let monitor = PerfFrameMonitor.shared
                monitor.writeScheduled = false
                monitor.write()
            }
        }
    }

    /// Also called by `PerfTour` when it is done.
    func write() {
        let service = Diagnostics.service
        let report = Report(
            session: service.currentSessionID, pid: ProcessInfo.processInfo.processIdentifier, startedAt: startedAt,
            extraTrips: PerfMode.extraTrips, tour: PerfTour.requested, launch: service.currentLaunchTiming,
            launchFrames: launchFrames, footprintPeakMB: footprintPeak, footprintByScreenMB: footprintByScreen,
            scroll: scroll.values.sorted { ($0.screen, $0.source) < ($1.screen, $1.source) },
            transitions: transitions, watchdogHangs: service.currentHangCount)
        let store = service.store
        let name = fileName
        store.queue.async { store.write(report, to: name) }
    }

    /// Physical footprint (what iOS counts against the memory limit), nil where unavailable.
    static func footprintMB() -> Double? {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
        #else
        return nil
        #endif
    }
}
