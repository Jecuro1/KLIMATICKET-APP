import Foundation

// MARK: radar2-radarmine – when „Wo bleibt mein Bus?“ asks (docs/RADAR_MINE.md §4, docs/OEBB_LIVE.md §R11.5). The departures board is a side job of the
// radar's one live loop (`Radar2Parts.dueSideJob`, `RadarScheduler.claimSlot`): one request per slot of the same 24 a minute, never two in flight,
// paused whenever the loop is (Zeitreise away from now, Cockpit, background, no access), while the train layer is off (the map shows no vehicle
// then, and the Pünktlichkeit alone keeps the loop running) and in Low Power Mode (there only „Jetzt aktualisieren“ asks, with the radar's own
// manual round).

/// Why the stop page does not ask right now (the page says it).
public enum RadarStopPause: Equatable, Sendable {
    case panelClosed
    /// No consent, live data switched off, kill switch, Funktionen „Offline-Modus“.
    case accessClosed
    case offline
    /// The train layer is off.
    case trainsOff
    /// The Zeitreise shows another time.
    case timeAway
    case cockpit
    case background
    case lowPower
}

public extension RadarFeatureGate {
    /// The stop page's board may be asked now: the live loop runs, the train layer is on, the page is open and Low Power Mode is off.
    func stopPanelAsks(isOpen: Bool, lowPower: Bool) -> Bool {
        liveLoopRuns && trainsOn && isOpen && !lowPower
    }

    /// Why it does not ask; nil exactly when `stopPanelAsks` is true.
    func stopPanelPause(isOpen: Bool, lowPower: Bool) -> RadarStopPause? {
        guard isOpen else { return .panelClosed }
        switch access {
        case .closed: return .accessClosed
        case .offline: return .offline
        case .open: break
        }
        if !layers.isOn(.trains) { return .trainsOff }
        if timeAway { return .timeAway }
        if cockpitOpen { return .cockpit }
        if !sceneActive { return .background }
        if lowPower { return .lowPower }
        return stopPanelAsks(isOpen: isOpen, lowPower: lowPower) ? nil : .background
    }
}

/// When the stop page's next request is due: at once when a stop is chosen (first the station link when the stop needs a lookup, then the board,
/// each in its own slot), then 60 s after the last answer; never two in flight; 15/30/60/120 s after failures in a row; nothing after 30 minutes
/// without a tap („Pausiert. Tippe zum Aktualisieren.“). Pure: the app tells it what happened and asks it what is due.
public struct RadarStopWatchPlan: Sendable, Equatable {
    public enum Job: String, Sendable, Equatable {
        /// One LocMatch for a stop the linker may not know yet (none for `uic:` stations).
        case link
        /// One StationBoard.
        case board
    }

    public static let interval: TimeInterval = 60
    public static let backoff: [TimeInterval] = [15, 30, 60, 120]
    public static let idleLimit: TimeInterval = 30 * 60

    public private(set) var stopID: String?
    /// Moves with every new stop and with `stop()`: an answer for an older generation is dropped.
    public private(set) var generation = 0
    public private(set) var needsLink = false
    public private(set) var inFlight: Job?
    public private(set) var lastAnswerAt: Date?
    public private(set) var failures = 0
    public private(set) var retryAt: Date?
    public private(set) var lastInteraction: Date?
    private var forceDue = false

    public init() {}

    /// A stop was chosen: due at once.
    public mutating func start(stopID: String, needsLink: Bool, now: Date) {
        self.stopID = stopID
        generation &+= 1
        self.needsLink = needsLink
        inFlight = nil
        lastAnswerAt = nil
        failures = 0
        retryAt = nil
        lastInteraction = now
        forceDue = false
    }

    /// No stop any more (the page or the panel closed, the access closed).
    public mutating func stop() {
        stopID = nil
        generation &+= 1
        inFlight = nil
        needsLink = false
        lastAnswerAt = nil
        failures = 0
        retryAt = nil
        forceDue = false
    }

    /// A tap on the page: the idle clock starts again (after an idle pause the board is due at once, its last answer being old).
    public mutating func interact(now: Date) {
        lastInteraction = now
    }

    /// „Jetzt aktualisieren“: due at once, also during a backoff.
    public mutating func refreshNow(now: Date) {
        lastInteraction = now
        retryAt = nil
        forceDue = true
    }

    public func isIdle(now: Date) -> Bool {
        guard let lastInteraction else { return false }
        return now.timeIntervalSince(lastInteraction) >= RadarStopWatchPlan.idleLimit
    }

    /// When the next job is due (`.distantPast`: at once); nil with no stop, one in flight or while idle.
    public func dueAt(now: Date) -> Date? {
        guard stopID != nil, inFlight == nil, !isIdle(now: now) else { return nil }
        if forceDue { return .distantPast }
        if let retryAt { return retryAt }
        if needsLink { return .distantPast }
        return lastAnswerAt.map { $0.addingTimeInterval(RadarStopWatchPlan.interval) } ?? .distantPast
    }

    /// The job due now, if any.
    public func nextJob(now: Date) -> Job? {
        guard let due = dueAt(now: now), due <= now else { return nil }
        return needsLink ? .link : .board
    }

    // MARK: Outcomes

    /// The live loop took a slot for the job and sends it.
    public mutating func started(_ job: Job, now: Date) {
        inFlight = job
        forceDue = false
    }

    /// The stop is linked: the board is due at once (in the next slot).
    public mutating func linked(now: Date) {
        inFlight = nil
        needsLink = false
        failures = 0
        retryAt = nil
    }

    /// The board answered.
    public mutating func answered(now: Date) {
        inFlight = nil
        lastAnswerAt = now
        failures = 0
        retryAt = nil
    }

    /// The job failed: the next try waits 15, 30, 60, then 120 s.
    public mutating func failed(now: Date) {
        inFlight = nil
        failures += 1
        let wait = RadarStopWatchPlan.backoff[min(failures, RadarStopWatchPlan.backoff.count) - 1]
        retryAt = now.addingTimeInterval(wait)
    }

    /// The job was cancelled (the loop ended): due as before, nothing counted.
    public mutating func cancelled() {
        inFlight = nil
    }
}
