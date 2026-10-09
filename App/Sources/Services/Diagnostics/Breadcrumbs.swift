import Foundation
import SwiftUI
import os

/// Thread-safe ring buffer of the last user-visible steps (screens, sheets, key actions) plus the stack of
/// visible screens. Read by the hang watchdog from its background thread, so everything is behind a lock.
final class BreadcrumbLog: @unchecked Sendable {
    static let capacity = 200

    private let lock = NSLock()
    private var ring: [Breadcrumb] = []
    private var next = 0
    /// Selected tab (or "Onboarding"), the base of the screen stack.
    private var baseScreen: String?
    /// Sheets and pushed screens on top of the base, in presentation order.
    private var stack: [String] = []
    private var revision = 0

    /// Called (outside the lock) after every change – the service coalesces it into a disk write.
    var onChange: (() -> Void)?

    var currentScreen: String? {
        lock.lock(); defer { lock.unlock() }
        return stack.last ?? baseScreen
    }

    func record(_ kind: Breadcrumb.Kind, _ name: String, detail: String? = nil, at date: Date = Date()) {
        let crumb = Breadcrumb(t: date, kind: kind, name: name, detail: detail)
        lock.lock()
        if ring.count < Self.capacity {
            ring.append(crumb)
        } else {
            ring[next] = crumb
        }
        next = (next + 1) % Self.capacity
        revision += 1
        lock.unlock()
        onChange?()
    }

    func setBaseScreen(_ name: String) {
        lock.lock()
        let changed = baseScreen != name
        baseScreen = name
        lock.unlock()
        if changed { record(.screen, name, detail: "tab") }
    }

    func push(_ name: String, kind: Breadcrumb.Kind) {
        lock.lock()
        stack.append(name)
        lock.unlock()
        record(kind, name, detail: kind == .sheet ? "presented" : "appeared")
    }

    func pop(_ name: String, kind: Breadcrumb.Kind) {
        lock.lock()
        if let index = stack.lastIndex(of: name) { stack.remove(at: index) }
        lock.unlock()
        record(kind, name, detail: kind == .sheet ? "dismissed" : "disappeared")
    }

    /// Oldest first.
    func snapshot() -> [Breadcrumb] {
        lock.lock(); defer { lock.unlock() }
        guard ring.count == Self.capacity else { return ring }
        return Array(ring[next...] + ring[..<next])
    }

    func clear() {
        lock.lock()
        ring.removeAll()
        next = 0
        lock.unlock()
    }
}

/// Duration counters of instrumented code paths, aggregated per session.
final class TimingLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stats: [String: TimingStat] = [:]

    func add(_ name: String, ms: Double) {
        lock.lock()
        stats[name, default: TimingStat()].add(ms)
        lock.unlock()
    }

    func snapshot() -> [String: TimingStat] {
        lock.lock(); defer { lock.unlock() }
        return stats
    }
}

/// Entry points for breadcrumbs and timings – cheap enough to call from anywhere (lock + array write).
enum Diagnostics {
    /// Signposts for Instruments and the XCUITest performance tests (`XCTOSSignpostMetric`).
    static let signposter = OSSignposter(subsystem: "com.knitelarlberg.klimabilanz", category: "Performance")
    /// A single measured call longer than this is also written to the breadcrumb log.
    static let slowCallThresholdMs: Double = 50

    static var service: DiagnosticsService { DiagnosticsService.shared }

    static func action(_ name: String, detail: String? = nil) {
        service.breadcrumbs.record(.action, name, detail: detail)
    }

    static func screen(_ name: String, visible: Bool) {
        if visible { service.breadcrumbs.push(name, kind: .screen) } else { service.breadcrumbs.pop(name, kind: .screen) }
    }

    static func sheet(_ name: String, presented: Bool) {
        if presented { service.breadcrumbs.push(name, kind: .sheet) } else { service.breadcrumbs.pop(name, kind: .sheet) }
    }

    /// Measures `body` (signpost interval + per-session statistics). Use for hot paths such as `Analytics.make`.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            finish(name, start: start)
        }
        return try body()
    }

    /// Async variant (wall time across suspension points, e.g. a whole sync run).
    @MainActor @discardableResult
    static func measureAsync<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, state)
            finish(name, start: start, recordsSlowCall: false)
        }
        return try await body()
    }

    private static func finish(_ name: StaticString, start: UInt64, recordsSlowCall: Bool = true) {
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
        let key = name.description
        service.timings.add(key, ms: ms)
        if recordsSlowCall, ms >= slowCallThresholdMs {
            service.breadcrumbs.record(.perf, key, detail: "\(Int(ms.rounded())) ms\(Thread.isMainThread ? " (main)" : "")")
        }
    }
}

// MARK: - SwiftUI

extension View {
    /// Records appear/disappear of a pushed screen in the breadcrumb log (the current screen of a hang report).
    func diagnosticsScreen(_ name: String) -> some View {
        onAppear { Diagnostics.screen(name, visible: true) }
            .onDisappear { Diagnostics.screen(name, visible: false) }
    }

    /// Tracks the app-wide navigation state (tab, global sheets) in the breadcrumb log. Applied once by `RootView`.
    func diagnosticsNavigationTracking() -> some View {
        modifier(DiagnosticsNavigationTracker())
    }
}

/// Observes `AppState`'s navigation (selected tab, add/edit trip, Settings, Gipfelbuch, update sheet) – no edits
/// in the feature views needed.
private struct DiagnosticsNavigationTracker: ViewModifier {
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content
            .onAppear { Diagnostics.service.markFirstFrame() }
            .onChange(of: baseScreen, initial: true) { _, name in
                Diagnostics.service.breadcrumbs.setBaseScreen(name)
            }
            .onChange(of: tripSheet) { old, new in
                if let old { Diagnostics.sheet(old.name, presented: false) }
                if let new { Diagnostics.sheet(new.name, presented: true) }
            }
            .onChange(of: app.isShowingSettings) { _, shown in Diagnostics.sheet("Einstellungen", presented: shown) }
            .onChange(of: app.isShowingAchievements) { _, shown in Diagnostics.sheet("Gipfelbuch", presented: shown) }
            .onChange(of: app.updates.isPresentingSheet) { _, shown in Diagnostics.sheet("Update", presented: shown) }
    }

    private var baseScreen: String {
        if let screen = LaunchMode.screenshotScreen { return "Screenshot \(screen)" }
        if !app.settings.onboardingCompleted { return "Onboarding" }
        return app.selectedTab.title
    }

    private struct TripSheet: Equatable {
        var id: UUID
        var name: String
    }

    /// The add/edit trip sheet (a new draft while one is open counts as dismiss + present).
    private var tripSheet: TripSheet? {
        app.tripDraft.map { TripSheet(id: $0.id, name: $0.editingTripID == nil ? "Fahrt erfassen" : "Fahrt bearbeiten") }
    }
}
