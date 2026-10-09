import Foundation
import SwiftUI
import UIKit

/// The shareable diagnostics bundle: one JSON file `KlimaBilanz-Diagnose-<datum>.json` with
///
///     format, createdAt, app, device, settings, dataCounts     (no trips, stations, names, e-mail or tokens)
///     summary                                                  (30-day counts)
///     events                                                   (crashes, hangs, unexpected exits, …)
///     sessions { current, history }                            (launch time, hang count, timings per session)
///     breadcrumbs { current, previous }                        (screens, sheets, actions before an incident)
///     metricKit { highlights, payloads: [ raw MetricKit JSON ] }
enum DiagnosticsExport {
    static let format = "klimabilanz-diagnostics/1"

    /// Call on the store queue.
    static func write(store: DiagnosticsStore, running: DiagnosticsSession, crumbs: [Breadcrumb],
                      context: DiagnosticsExportContext) throws -> URL {
        let now = Date()
        let events = DiagnosticsStore.pruned(store.events(), now: now)
        var sessions = store.read(DiagnosticsSessionsFile.self, from: "sessions.json")
            ?? DiagnosticsSessionsFile(current: nil, history: [])
        sessions.current = running
        let previousCrumbs = store.read(DiagnosticsBreadcrumbFile.self, from: "breadcrumbs-previous.json")

        var payloads: [Any] = []
        for file in store.payloadFiles() {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            payloads.append(["file": file.lastPathComponent, "payload": object])
        }

        let hangs = events.filter(\.isHang)
        let summary: [String: Any] = [
            "days": 30,
            "crashes": events.filter(\.isCrashLike).count,
            "hangs": hangs.count,
            "watchdogHangs": events.filter { $0.kind == .watchdogHang }.count,
            "longestHangMs": hangs.compactMap(\.durationMs).max() ?? 0,
            "abnormalExits": events.filter { $0.kind == .abnormalExit }.count,
            "fatalHangs": events.filter { $0.kind == .fatalHang }.count,
            "resourceWarnings": events.filter(\.isResourceWarning).count,
            "slowLaunches": events.filter { $0.kind == .slowLaunch }.count,
        ]

        var bundle: [String: Any] = [
            "format": format,
            "createdAt": ISO8601DateFormatter().string(from: now),
            "app": context.app,
            "device": context.device,
            "settings": context.settings,
            "dataCounts": context.dataCounts,
            "summary": summary,
            "events": try jsonObject(events),
            "sessions": try jsonObject(sessions),
            "breadcrumbs": [
                "current": try jsonObject(crumbs),
                "previous": try jsonObject(previousCrumbs?.crumbs ?? []),
            ],
        ]
        var metricKit: [String: Any] = ["payloads": payloads]
        if let highlights = store.read(MetricKitHighlights.self, from: "metrics-highlights.json") {
            metricKit["highlights"] = try jsonObject(highlights)
        }
        bundle["metricKit"] = metricKit

        let data = try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KlimaBilanz-Diagnose-\(formatter.string(from: now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try DiagnosticsStore.encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: Context (main actor)

    /// App, device and coarse settings – nothing that identifies the user or their trips.
    @MainActor
    static func context(app: AppState, trips: Int, tickets: Int, favorites: Int) -> DiagnosticsExportContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        var deviceInfo: [String: String] = [
            "model": modelIdentifier(),
            "system": "\(device.systemName) \(device.systemVersion)",
            "memoryMB": "\(process.physicalMemory / 1_048_576)",
            "processors": "\(process.activeProcessorCount)",
            "lowPowerMode": "\(process.isLowPowerModeEnabled)",
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "reduceMotion": "\(UIAccessibility.isReduceMotionEnabled)",
            "contentSize": UIApplication.shared.preferredContentSizeCategory.rawValue,
        ]
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attributes[.systemFreeSize] as? NSNumber {
            deviceInfo["freeDiskMB"] = "\(free.int64Value / 1_048_576)"
        }
        let appInfo: [String: String] = [
            "version": info["CFBundleShortVersionString"] as? String ?? "?",
            "build": info["CFBundleVersion"] as? String ?? "?",
            "bundleID": Bundle.main.bundleIdentifier ?? "?",
            "launchMode": LaunchMode.isPerf ? "perf" : (LaunchMode.isScreenshot ? "screenshot" : "standard"),
        ]
        let settings: [String: String] = [
            "appearance": app.settings.appearance.rawValue,
            "haptics": "\(app.settings.hapticsEnabled)",
            "autoUpdateCheck": "\(app.settings.autoUpdateCheck)",
            "renewalReminders": "\(app.settings.renewalRemindersEnabled)",
            "cloudSignedIn": "\(app.auth.isSignedIn)",
            "hangWatchdog": "\(DiagnosticsService.shared.isWatchdogEnabled)",
        ]
        return DiagnosticsExportContext(app: appInfo, device: deviceInfo, settings: settings,
                                        dataCounts: ["trips": trips, "tickets": tickets, "favorites": favorites])
    }

    /// "iPhone17,1" (on the simulator the simulated model).
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
