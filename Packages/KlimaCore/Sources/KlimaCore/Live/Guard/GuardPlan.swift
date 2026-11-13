import Foundation

// Anschluss-Wächter, the request plan (docs/CONNECTION_GUARD.md §4). Foreground only: the guard asks while the follow's
// target is its feeder, the app is active, live data is available, Low Power Mode is off, the guard is on and the time is
// inside the window (feeder's planned departure − 30 min … connecting departure + 5 min). One Reconstruction per 120 s,
// per 60 s while the state is worse than „Sicher“; at once on register and on a return after more than 60 s; „Jetzt
// prüfen“ at most every 20 s; never two in flight; backoff 15/30/60/120 s; after two failed Reconstructions in a row the
// JourneyDetails of the connecting trip. Every request goes through the app's throttle (40 a minute), not the radar budget.

/// What one guard request asks for.
public enum GuardRequestKind: String, Sendable, Hashable, Codable {
    /// `HafasClient.refresh(_:includeStopovers: false, includePolyline: false)` of the followed connection.
    case reconstruction
    /// JourneyDetails of the connecting trip (after two failed Reconstructions in a row).
    case connectionTrip
}

/// Why the guard does not ask right now.
public enum GuardIdleReason: Sendable, Hashable {
    /// The follow's target is not this guard's feeder (stopped or replaced).
    case notFollowing
    /// „Umstieg vorbei“, the window is over, or the record is older than 12 h.
    case ended
    /// „Wächter aus“ for this follow.
    case switchedOff
    /// No live timetable (consent, switch, kill switch, Offline-Modus or offline).
    case liveOff
    /// The app is not active: nothing is asked in the background.
    case background
    /// Low Power Mode: only „Jetzt prüfen“.
    case lowPower
    /// A request is on its way.
    case inFlight
    /// The window has not started yet (begins at the date).
    case beforeWindow(Date)
}

public enum GuardDecision: Sendable, Hashable {
    case ask(GuardRequestKind)
    /// Ask at that time if nothing changes before.
    case wait(Date)
    case idle(GuardIdleReason)
}

/// „Jetzt prüfen“.
public enum GuardManualDecision: Sendable, Hashable {
    case ask(GuardRequestKind)
    /// The last manual check is less than 20 s ago: possible again after these seconds.
    case tooSoon(TimeInterval)
    case unavailable(GuardIdleReason)
}

/// The conditions outside the guard (observed by the app service).
public struct GuardConditions: Sendable, Hashable {
    public var followsFeeder: Bool
    public var appActive: Bool
    public var liveAvailable: Bool
    public var lowPower: Bool
    public var switchedOff: Bool

    public init(followsFeeder: Bool, appActive: Bool, liveAvailable: Bool, lowPower: Bool, switchedOff: Bool) {
        self.followsFeeder = followsFeeder
        self.appActive = appActive
        self.liveAvailable = liveAvailable
        self.lowPower = lowPower
        self.switchedOff = switchedOff
    }
}

/// The guard's own request history (memory only).
public struct GuardRequestState: Sendable, Hashable {
    /// Send time of the last request, answered or failed.
    public var lastRequestAt: Date?
    /// Send time of the last answered request.
    public var lastAnswerAt: Date?
    public var consecutiveFailures: Int
    /// Failed Reconstructions in a row that were the Auskunft's doing (not offline / live data off).
    public var reconstructionFailures: Int
    /// After two failed Reconstructions the guard asks the connecting trip's JourneyDetails instead.
    public var usesFallback: Bool
    public var inFlight: Bool
    public var lastManualAt: Date?

    public init(lastRequestAt: Date? = nil, lastAnswerAt: Date? = nil, consecutiveFailures: Int = 0, reconstructionFailures: Int = 0,
                usesFallback: Bool = false, inFlight: Bool = false, lastManualAt: Date? = nil) {
        self.lastRequestAt = lastRequestAt
        self.lastAnswerAt = lastAnswerAt
        self.consecutiveFailures = consecutiveFailures
        self.reconstructionFailures = reconstructionFailures
        self.usesFallback = usesFallback
        self.inFlight = inFlight
        self.lastManualAt = lastManualAt
    }

    public var nextKind: GuardRequestKind { usesFallback ? .connectionTrip : .reconstruction }
}

/// How a request ended.
public enum GuardRequestOutcome: Sendable, Hashable {
    case answered
    /// `countsForFallback`: the Auskunft failed (not offline, not live data off); two in a row switch to the fallback.
    case failed(countsForFallback: Bool)
}

public enum GuardPlan {
    /// The window opens this long before the feeder's planned departure.
    public static let lead: TimeInterval = 30 * 60
    /// The window closes this long after the connecting departure.
    public static let tail: TimeInterval = 5 * 60
    /// Cadence while „Sicher“ (or „Nach Fahrplan“).
    public static let calmInterval: TimeInterval = 120
    /// Cadence while worse than „Sicher“.
    public static let alertInterval: TimeInterval = 60
    /// Back in the foreground with an answer older than this: ask at once.
    public static let foregroundStale: TimeInterval = 60
    /// „Jetzt prüfen“ at most this often.
    public static let manualSpacing: TimeInterval = 20
    /// Waits after 1, 2, 3 and 4+ failures in a row.
    public static let backoff: [TimeInterval] = [15, 30, 60, 120]
    /// Failed Reconstructions in a row before the fallback.
    public static let fallbackAfter = 2
    /// A guard record older than this is dropped.
    public static let recordLifetime: TimeInterval = 12 * 60 * 60

    /// The window: feeder's planned departure − 30 min … connecting departure (realtime, else planned) + 5 min.
    public static func window(feederPlannedDeparture: Date?, connectionDeparture: Date?) -> DateInterval? {
        guard let start = feederPlannedDeparture?.addingTimeInterval(-lead), let departure = connectionDeparture else { return nil }
        let end = departure.addingTimeInterval(tail)
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    /// The guard is over: „Umstieg vorbei“, past the window, or the record is older than 12 h.
    public static func hasEnded(state: GuardState?, window: DateInterval?, createdAt: Date, now: Date) -> Bool {
        if state == .over { return true }
        if now.timeIntervalSince(createdAt) > recordLifetime { return true }
        if let window, now > window.end { return true }
        return false
    }

    /// The automatic loop: what to do now. `returnedToForeground` is true for the first decision after the app became active.
    public static func next(conditions c: GuardConditions, requests r: GuardRequestState, shown: GuardState?,
                            window: DateInterval?, ended: Bool, returnedToForeground: Bool = false, now: Date) -> GuardDecision {
        if let reason = blocker(c, ended: ended, manual: false) { return .idle(reason) }
        if r.inFlight { return .idle(.inFlight) }
        if let window {
            if now < window.start { return .idle(.beforeWindow(window.start)) }
            if now > window.end { return .idle(.ended) }
        }
        let kind = r.nextKind
        guard let last = r.lastRequestAt else { return .ask(kind) }
        if r.consecutiveFailures > 0 {
            let wait = backoff[min(r.consecutiveFailures, backoff.count) - 1]
            let due = last.addingTimeInterval(wait)
            return due <= now ? .ask(kind) : .wait(due)
        }
        let answered = r.lastAnswerAt ?? last
        if returnedToForeground, now.timeIntervalSince(answered) > foregroundStale { return .ask(kind) }
        let interval = (shown?.isWarning ?? false) ? alertInterval : calmInterval
        let due = answered.addingTimeInterval(interval)
        return due <= now ? .ask(kind) : .wait(due)
    }

    /// „Jetzt prüfen“: allowed in Low Power Mode and before the window; never twice within 20 s, never with one in flight.
    public static func manual(conditions c: GuardConditions, requests r: GuardRequestState, ended: Bool, now: Date) -> GuardManualDecision {
        if let reason = blocker(c, ended: ended, manual: true) { return .unavailable(reason) }
        if r.inFlight { return .unavailable(.inFlight) }
        if let last = r.lastManualAt, now.timeIntervalSince(last) < manualSpacing {
            return .tooSoon(manualSpacing - now.timeIntervalSince(last))
        }
        return .ask(r.nextKind)
    }

    /// The history after a request sent at `sentAt`.
    public static func record(_ r: GuardRequestState, kind: GuardRequestKind, sentAt: Date, outcome: GuardRequestOutcome,
                              manual: Bool = false) -> GuardRequestState {
        var next = r
        next.inFlight = false
        next.lastRequestAt = sentAt
        if manual { next.lastManualAt = sentAt }
        switch outcome {
        case .answered:
            next.lastAnswerAt = sentAt
            next.consecutiveFailures = 0
            if kind == .reconstruction { next.reconstructionFailures = 0 }
        case .failed(let counts):
            next.consecutiveFailures += 1
            if kind == .reconstruction, counts {
                next.reconstructionFailures += 1
                if next.reconstructionFailures >= fallbackAfter { next.usesFallback = true }
            }
        }
        return next
    }

    /// The first condition that keeps the guard silent. Manual checks ignore the app state (the user tapped) and Low Power Mode.
    static func blocker(_ c: GuardConditions, ended: Bool, manual: Bool) -> GuardIdleReason? {
        if ended { return .ended }
        if !c.followsFeeder { return .notFollowing }
        if c.switchedOff { return .switchedOff }
        if !c.liveAvailable { return .liveOff }
        if manual { return nil }
        if !c.appActive { return .background }
        if c.lowPower { return .lowPower }
        return nil
    }
}
