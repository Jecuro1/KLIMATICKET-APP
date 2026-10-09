import Foundation

// Value types of the local diagnostics (Einstellungen › Diagnose & Stabilität). Everything stays on the device;
// nothing here contains trips, stations, names or account data – only app/screen names, timings and iOS reports.

/// One stability incident: an iOS report (MetricKit), a hang seen by the in-app watchdog, or a session that ended
/// unexpectedly in the foreground.
struct DiagnosticsEvent: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        /// MetricKit crash report (delivered by iOS on the next launch, up to 24 h later).
        case crash
        /// MetricKit hang report (main thread blocked for a long time).
        case hang
        /// In-app watchdog: the main thread did not respond within 250 ms.
        case watchdogHang
        /// In-app watchdog: a hang was still in progress when the app ended (likely killed by iOS).
        case fatalHang
        /// The previous session ended in the foreground without a clean exit (crash, hang kill, memory).
        case abnormalExit
        /// MetricKit: CPU usage above the iOS limit.
        case cpuException
        /// MetricKit: disk writes above the iOS limit.
        case diskWriteException
        /// MetricKit: a slow app launch.
        case slowLaunch
    }

    enum Source: String, Codable, Sendable {
        case metricKit, watchdog, session
    }

    var id: String
    var kind: Kind
    var source: Source
    var date: Date
    var durationMs: Double?
    /// Screen (tab or sheet) that was visible, from the breadcrumb log.
    var screen: String?
    var title: String
    /// Technical detail for the developer (exception type, signal, unsymbolicated top app frame).
    var detail: String?
    var appVersion: String?
    var build: String?
    /// Raw MetricKit payload this event came from (`payloads/<file>`), included in the export.
    var payloadFile: String?

    var isCrashLike: Bool { kind == .crash }
    var isHang: Bool { kind == .hang || kind == .watchdogHang || kind == .fatalHang }
    var isResourceWarning: Bool { kind == .cpuException || kind == .diskWriteException }
}

/// One entry of the breadcrumb ring buffer (what the user did right before a hang or crash).
struct Breadcrumb: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case screen, sheet, action, lifecycle, perf
    }

    var t: Date
    var kind: Kind
    var name: String
    var detail: String?
}

/// Duration statistics of an instrumented code path (`Diagnostics.measure`).
struct TimingStat: Codable, Hashable, Sendable {
    var count: Int = 0
    var totalMs: Double = 0
    var maxMs: Double = 0

    var averageMs: Double { count > 0 ? totalMs / Double(count) : 0 }

    mutating func add(_ ms: Double) {
        count += 1
        totalMs += ms
        maxMs = max(maxMs, ms)
    }
}

/// Launch duration of one session.
struct LaunchTiming: Codable, Hashable, Sendable {
    /// From `KlimaBilanzApp.init` to the first appearance of the root view.
    var initToFirstFrameMs: Double
    /// From process start (kernel) to the first appearance – nil when iOS pre-warmed the process.
    var processToFirstFrameMs: Double?
}

/// One app session (launch → termination), kept for the last sessions to detect unclean exits.
struct DiagnosticsSession: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case launching, active, inactive, background, terminated
    }

    var id: String
    var startedAt: Date
    var lastSeenAt: Date
    var state: State
    var prewarmed: Bool
    var appVersion: String
    var build: String
    var osVersion: String
    var lastScreen: String?
    var launch: LaunchTiming?
    var hangCount: Int = 0
    var longestHangMs: Double = 0
    var timings: [String: TimingStat] = [:]

    /// Ended in the foreground without `willResignActive` / `didEnterBackground` / `willTerminate`.
    var endedUnexpectedly: Bool {
        state == .active || (state == .launching && !prewarmed)
    }
}

/// `sessions.json`: the running session and the ones before it.
struct DiagnosticsSessionsFile: Codable, Sendable {
    var current: DiagnosticsSession?
    var history: [DiagnosticsSession]
}

/// `breadcrumbs.json` / `breadcrumbs-previous.json`.
struct DiagnosticsBreadcrumbFile: Codable, Sendable {
    var sessionID: String
    var crumbs: [Breadcrumb]
}

/// A hang that was still in progress the last time the watchdog wrote its marker.
struct HangMarker: Codable, Hashable, Sendable {
    var sessionID: String
    var start: Date
    var durationMs: Double
    var screen: String?
}

/// Highlights of the latest daily MetricKit metrics payload (only delivered when iOS shares analytics with developers).
struct MetricKitHighlights: Codable, Hashable, Sendable {
    var periodEnd: Date
    var scrollHitchTimeRatio: Double?
    var averageTimeToFirstDrawMs: Double?
    var averageHangTimeMs: Double?
    var peakMemoryMB: Double?
}

/// What the settings page shows.
struct DiagnosticsOverview: Sendable {
    var since: Date
    var crashes: Int
    var hangs: Int
    var longestHangMs: Double?
    var abnormalExits: Int
    var resourceWarnings: Int
    var slowLaunches: Int
    var latest: [DiagnosticsEvent]
    var lastLaunch: LaunchTiming?
    var sessionCount: Int
    var metricKit: MetricKitHighlights?
    var metricKitPayloadCount: Int
    var timings: [String: TimingStat]

    var isQuiet: Bool { crashes == 0 && hangs == 0 && abnormalExits == 0 && resourceWarnings == 0 }

    static let empty = DiagnosticsOverview(since: Date(), crashes: 0, hangs: 0, longestHangMs: nil, abnormalExits: 0,
                                           resourceWarnings: 0, slowLaunches: 0, latest: [], lastLaunch: nil,
                                           sessionCount: 0, metricKit: nil, metricKitPayloadCount: 0, timings: [:])
}

/// App, device and data-volume facts for the export (collected on the main actor; no personal content).
struct DiagnosticsExportContext: Sendable {
    var app: [String: String]
    var device: [String: String]
    var settings: [String: String]
    var dataCounts: [String: Int]
}
