import Foundation
import UIKit
import os

/// `-KBPerfTour <name>` (perf mode only): the app drives itself, so Instruments can profile one screen without
/// XCUITest querying the accessibility tree in between (scripts/perf_profile.sh records the Time Profiler around it).
///
/// 4 s after the first frame it opens the screen (`overview`, `trips`, `stats`, `ticket`, `gipfelbuch`; `all` visits
/// them in turn, `launch` only waits), lets it settle for 2.5 s and then scrolls its main scroll view to the end and
/// back, three times, at a constant 2 400 pt/s – a display link moves `contentOffset`, the same rendering path as a
/// flick, measured by `PerfFrameMonitor` as source `tour`. Every phase is a signpost interval (category
/// PointsOfInterest) and is listed in `Diagnostics/perf-tour.json` in seconds since process start. The app stays
/// open afterwards (xctrace stops at its time limit – an attached recording hung when the target exited).
///
/// `-KBPerfPresent gipfelbuch` (the XCUITests) only opens the Gipfelbuch sheet after the first frame.
@MainActor
final class PerfTour: NSObject {
    static var requested: String? { UserDefaults.standard.string(forKey: "KBPerfTour") }
    static var presentRequest: String? { UserDefaults.standard.string(forKey: "KBPerfPresent") }

    /// True while the tour moves a scroll view (keeps the frame monitor's display link running).
    private(set) static var isScrolling = false

    private static var started = false
    private static let signposter = OSSignposter(subsystem: "com.knitelarlberg.klimabilanz", category: .pointsOfInterest)

    private struct Phase: Codable {
        var name: String
        var start: Double
        var end: Double
    }

    private static var phases: [Phase] = []
    private static let processStart = DiagnosticsService.processStartDate() ?? Date()

    static let speed: CGFloat = 2_400
    static let rounds = 3
    /// A pass ends at the end of the content or after this long (the +1 500-trip list would take a minute).
    static let maxPass: CFTimeInterval = 2.5

    /// Called once a second by the frame monitor.
    static func startIfRequested(firstFrameSeen: Bool) {
        guard firstFrameSeen, !started, LaunchMode.isPerf else { return }
        if let present = presentRequest {
            started = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                open(present)
            }
            return
        }
        guard let tour = requested else { return }
        started = true
        Task { @MainActor in await run(tour) }
    }

    private static func run(_ tour: String) async {
        // Time for an attaching profiler (scripts/perf_profile.sh) to start recording.
        try? await Task.sleep(for: .seconds(4))
        let screens: [String]
        switch tour {
        case "all": screens = ["overview", "trips", "stats", "ticket", "gipfelbuch"]
        case "launch": screens = []
        default: screens = [tour]
        }
        if screens.isEmpty {
            await phase("idle") { try? await Task.sleep(for: .seconds(6)) }
        }
        for screen in screens {
            await phase("open \(screen)") {
                open(screen)
                try? await Task.sleep(for: .seconds(2.5))
            }
            await phase("scroll \(screen)") {
                await scrollMainScrollView()
            }
            if screen == "gipfelbuch" { AppDelegate.appState?.isShowingAchievements = false }
        }
        PerfFrameMonitor.shared.write()
        writePhases()
    }

    private static func open(_ screen: String) {
        guard let app = AppDelegate.appState else { return }
        switch screen {
        case "trips": app.selectedTab = .trips
        case "stats": app.selectedTab = .stats
        case "ticket": app.selectedTab = .ticket
        case "gipfelbuch":
            app.selectedTab = .overview
            app.isShowingAchievements = true
        default: app.selectedTab = .overview
        }
    }

    private static func phase(_ name: String, _ body: () async -> Void) async {
        let signpostName: StaticString = "Tour"
        let state = signposter.beginInterval(signpostName, id: signposter.makeSignpostID(), "\(name, privacy: .public)")
        let start = Date().timeIntervalSince(processStart)
        await body()
        signposter.endInterval(signpostName, state)
        phases.append(Phase(name: name, start: start, end: Date().timeIntervalSince(processStart)))
    }

    private static func writePhases() {
        let store = Diagnostics.service.store
        let list = phases
        store.queue.async { store.write(list, to: "perf-tour.json") }
    }

    // MARK: Scrolling

    /// The largest vertically scrollable scroll view of the topmost presented screen (a sheet's own list, not the tab
    /// behind it).
    private static func mainScrollView() -> UIScrollView? {
        var best: UIScrollView?
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                var top = window.rootViewController
                while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
                guard let root = top?.view else { continue }
                visit(root) { scrollView in
                    guard scrollView.window != nil, !scrollView.isHidden,
                          scrollView.contentSize.height > scrollView.bounds.height + 40 else { return }
                    let area = scrollView.bounds.width * scrollView.bounds.height
                    if area > (best.map { $0.bounds.width * $0.bounds.height } ?? 0) { best = scrollView }
                }
            }
        }
        return best
    }

    private static func visit(_ view: UIView, _ found: (UIScrollView) -> Void) {
        if let scrollView = view as? UIScrollView { found(scrollView) }
        for sub in view.subviews { visit(sub, found) }
    }

    private static func scrollMainScrollView() async {
        guard let scrollView = mainScrollView() else { return }
        isScrolling = true
        defer { isScrolling = false }
        for _ in 0..<rounds {
            await ScrollDriver(scrollView: scrollView, down: true).run()
            try? await Task.sleep(for: .seconds(0.4))
            await ScrollDriver(scrollView: scrollView, down: false).run()
            try? await Task.sleep(for: .seconds(0.4))
        }
    }

    /// Moves `contentOffset` at `speed` with a display link until the end of the content (time-based, so a slow frame
    /// jumps further – like a deceleration).
    @MainActor
    private final class ScrollDriver: NSObject {
        private weak var scrollView: UIScrollView?
        private let down: Bool
        private var link: CADisplayLink?
        private var last: CFTimeInterval?
        private var elapsed: CFTimeInterval = 0
        private var continuation: CheckedContinuation<Void, Never>?

        init(scrollView: UIScrollView, down: Bool) {
            self.scrollView = scrollView
            self.down = down
        }

        func run() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                let link = CADisplayLink(target: self, selector: #selector(step(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            }
        }

        @objc func step(_ link: CADisplayLink) {
            guard let scrollView else { return finish() }
            let dt = last.map { link.timestamp - $0 } ?? 0
            last = link.timestamp
            elapsed += dt
            let minY = -scrollView.adjustedContentInset.top
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            var y = scrollView.contentOffset.y + (down ? 1 : -1) * PerfTour.speed * CGFloat(dt)
            y = min(max(y, minY), maxY)
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: y)
            if (down && (y >= maxY || elapsed >= PerfTour.maxPass)) || (!down && y <= minY) { finish() }
        }

        private func finish() {
            link?.invalidate()
            link = nil
            continuation?.resume()
            continuation = nil
        }
    }
}
