import Foundation

// Radar time travel, part 4: which snapshot is requested when (docs/RADAR_TIMETRAVEL.md §4). Pure and deterministic: no network, no
// timer, no clock of its own; every method takes `now`. The caller asks `next(now:claim:)` and sends one request when the answer is
// `.request`, then reports the outcome.
//
// The plan is a coarse timeline: one snapshot of all rail vehicles of Austria (one request with `maxJny` 1000, answered with up to ~1.8 MB) at
// every full 20 minutes from half an hour back to three hours ahead (`fine`, 10 or 11 answers), or at every full hour on a metered connection
// (`coarse`, 3 or 4 answers), plus one for "now" when the live radar does not already hold all of Austria. While a Zeitreise lasts, the plan
// moves on with the clock (`extendPlan`). The order follows the scrubber: the answer nearest to the
// chosen time comes first, so the picture is usable long before the last one arrives. When the scrubber has rested (0.6 s), one more
// snapshot for exactly that minute replaces the projection there.
//
// The budget is the live radar's: every request first asks `claim`, which the app wires to `RadarScheduler.claimSlot`, so the live loop and the
// Zeitreise together never send more than 24 a minute, 4 in 10 seconds, one a second (docs/OEBB_LIVE.md §R11.2).

public enum RadarTimeProfile: Sendable, Equatable {
    /// Every 20 minutes from half an hour back to three hours ahead: 10 or 11 answers.
    case fine
    /// Every full hour in the same range: 3 or 4 answers (one in the past when the last full hour is less than 30 minutes ago). For a
    /// metered or constrained connection.
    case coarse

    public var gridSeconds: TimeInterval { self == .fine ? 1200 : 3600 }
}

/// One snapshot to fetch: the time it is for, whether it is a point of the plan or an extra for the minute the scrubber rests at, and
/// which part of Austria (all of it, or one of the two level-0 tiles when the whole answer was cut off at the request cap).
public struct RadarTimeSlot: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case grid, exact }

    public var kind: Kind
    public var time: Date
    public var part: RadarTileKey?

    public init(kind: Kind, time: Date, part: RadarTileKey? = nil) {
        self.kind = kind
        self.time = time
        self.part = part
    }
}

public struct RadarTimeRequest: Sendable, Hashable {
    public var slot: RadarTimeSlot

    public init(slot: RadarTimeSlot) {
        self.slot = slot
    }

    public var time: Date { slot.time }

    /// All of Austria with its margin, or one half of it.
    public var box: RadarBox { slot.part.map { RadarTileGrid.box(of: $0) } ?? RadarTileGrid.coverage }
}

public struct RadarTimeSchedulerConfig: Sendable, Equatable {
    /// The scrubber's range ahead and back.
    public var range: TimeInterval = RadarTimeAxis.maxOffset
    public var pastRange: TimeInterval = -RadarTimeAxis.minOffset
    /// The scrubber must rest this long before the snapshot for its minute is requested.
    public var restDelay: TimeInterval = 0.6
    /// Requests on their way at the same time (the live loop is paused meanwhile).
    public var maxInFlight = 2
    public var requestTimeout: TimeInterval = 90
    /// Tries per snapshot, with 15 s, then 30 s between them. After the last one the point stays missing and the panel says so.
    public var maxAttempts = 3
    public var baseBackoff: TimeInterval = 15
    /// Snapshots for resting minutes that are requested by themselves in one Zeitreise; more only on a tap.
    public var autoExactLimit = 12
    /// A snapshot is fresh this long: a Zeitreise entered again within it does not fetch it again.
    public var freshness: TimeInterval = 600
    /// A resting minute this close to a planned or fetched snapshot needs none of its own.
    public var exactWindow: TimeInterval = 150
    /// A resting minute closer to now than this needs none (the live radar is right there).
    public var minExactDistance: TimeInterval = 60

    public init() {}

    public static let standard = RadarTimeSchedulerConfig()
}

public struct RadarTimeScheduler: Sendable {
    public enum Step: Sendable, Equatable {
        /// Send this request now (its budget slot is taken).
        case request(RadarTimeRequest)
        /// Nothing may be sent before this time (budget, spacing, backoff, the scrubber still moving).
        case wait(until: Date)
        /// Nothing to do: everything is loaded, failed for good, or the Zeitreise is not running.
        case idle
    }

    /// The measured size of one answer for all of Austria, unpacked, in megabytes (docs/OEBB_LIVE.md §R11.1: 1 831 536 bytes). The size on the
    /// wire (gzip) was not measured; the numbers shown to the user say "entpackt".
    public static let megabytesPerAnswer = 1.8

    enum Phase: Sendable, Equatable {
        case pending
        case inFlight(since: Date)
        case done(at: Date)
        /// The whole answer was cut off at the request cap: its two halves are asked instead.
        case split(at: Date)
        case failed
    }

    struct SlotState: Sendable {
        var phase: Phase = .pending
        var attempts = 0
        var retryAt: Date?
    }

    public let config: RadarTimeSchedulerConfig
    var slots: [RadarTimeSlot: SlotState] = [:]
    public private(set) var isActive = false
    public private(set) var profile: RadarTimeProfile = .fine
    /// The whole radar waits until then (a rate limit or an open circuit answered a request). The app forwards it to the live scheduler.
    public private(set) var pausedUntil: Date?
    /// Snapshots for resting minutes requested by themselves, and parts of a split answer that were cut off again.
    public private(set) var autoExactCount = 0
    public private(set) var cutOffParts = 0
    /// Requests handed out in this Zeitreise.
    public private(set) var requestsSent = 0
    /// False on a metered connection: a resting minute is then fetched only on a tap (`requestExact`).
    public var allowsAutoExact = true

    private var target: Date?
    private var movedAt: Date = .distantPast
    private var isMoving = false
    private var manualExact: Date?

    public init(config: RadarTimeSchedulerConfig = .standard) {
        self.config = config
    }

    // MARK: Begin and end

    /// Starts a Zeitreise at `now`. Snapshots that are still fresh from an earlier one stay (nothing is fetched twice); the plan's points
    /// are the full 20 minutes (or hours) up to three hours ahead. `includeNow`: the live radar does not hold all of Austria, so "now" is one more snapshot.
    /// Called again during a running Zeitreise ("Fein laden"), the requests on their way stay on their way: their answers are awaited, not
    /// asked a second time.
    public mutating func begin(now: Date, profile: RadarTimeProfile, includeNow: Bool) {
        let wasActive = isActive
        isActive = true
        self.profile = profile
        pausedUntil = nil
        autoExactCount = 0
        cutOffParts = 0
        requestsSent = 0
        manualExact = nil
        slots = slots.filter { key, state in
            guard key.time >= now.addingTimeInterval(-config.pastRange - 60) else { return false }
            switch state.phase {
            case .done(let at), .split(let at): return now.timeIntervalSince(at) <= config.freshness
            case .inFlight: return wasActive   // the same Zeitreise: still on its way. An earlier one ended before it finished: asked afresh
            case .pending, .failed: return false
            }
        }
        for time in Self.gridTimes(from: now.addingTimeInterval(-config.pastRange), through: now.addingTimeInterval(config.range), every: profile.gridSeconds)
        where !isCovered(time) {
            slots[RadarTimeSlot(kind: .grid, time: time)] = SlotState()
        }
        if includeNow, !isCovered(now) {
            slots[RadarTimeSlot(kind: .grid, time: now)] = SlotState()
        }
    }

    /// The clock moves on during a long Zeitreise, and the scrubber's range with it: points of the plan that came into the range on the right
    /// are added (one every 20 minutes, or every hour), points that left it on the left are forgotten (the timeline keeps what they brought).
    /// A point that failed for good stays failed. Nothing else changes: no counter is reset, nothing fresh is fetched again.
    public mutating func extendPlan(now: Date) {
        guard isActive else { return }
        let start = now.addingTimeInterval(-config.pastRange)
        slots = slots.filter { key, state in
            if key.time >= start.addingTimeInterval(-60) { return true }
            if case .inFlight = state.phase { return true }   // its answer is still awaited
            return false
        }
        for time in Self.gridTimes(from: start, through: now.addingTimeInterval(config.range), every: profile.gridSeconds)
        where slots[RadarTimeSlot(kind: .grid, time: time)] == nil && !isCovered(time) {
            slots[RadarTimeSlot(kind: .grid, time: time)] = SlotState()
        }
    }

    /// Leaves the Zeitreise: nothing more is requested. Requests on their way are the caller's to cancel (`recordCancelled`).
    public mutating func end() {
        isActive = false
        target = nil
        manualExact = nil
    }

    /// The full `step` seconds (since 1970; Vienna's offsets are whole hours, so these are full clock times) from `start` through `end`, both inclusive.
    public static func gridTimes(from start: Date, through end: Date, every step: TimeInterval) -> [Date] {
        guard step > 0 else { return [] }
        var t = (start.timeIntervalSince1970 / step).rounded(.up) * step
        var times: [Date] = []
        while t <= end.timeIntervalSince1970 + 0.001 {
            times.append(Date(timeIntervalSince1970: t))
            t += step
        }
        return times
    }

    // MARK: The scrubber

    /// The scrubber says it is at `target`. A new target starts the rest timer.
    public mutating func setTarget(_ newTarget: Date, now: Date) {
        guard newTarget != target else { return }
        target = newTarget
        movedAt = now
    }

    /// Dragging or playing: no snapshot for a resting minute is requested while it is true; the rest timer starts when it ends.
    public mutating func setMoving(_ moving: Bool, now: Date) {
        if isMoving && !moving { movedAt = now }
        isMoving = moving
    }

    /// "Für diese Zeit genau laden": the snapshot for `time` even where nothing is fetched by itself (metered, or the limit is reached).
    public mutating func requestExact(for time: Date) {
        manualExact = time
    }

    // MARK: Covered

    /// A snapshot of any kind (planned, on its way, fetched, or given up on) lies within the window around `time`.
    func isCovered(_ time: Date) -> Bool {
        slots.contains { key, state in
            guard key.part == nil, abs(key.time.timeIntervalSince(time)) <= config.exactWindow else { return false }
            if case .failed = state.phase { return key.kind == .exact }   // a planned point that failed is not a snapshot; an exact one is not retried by itself
            return true
        }
    }

    /// True when a snapshot for the minute around `time` is fetched (the picture there is calculated from a fresh answer).
    public func hasSnapshot(near time: Date, now: Date) -> Bool {
        snapshotTime(near: time, now: now) != nil
    }

    /// The time of the fetched, fresh snapshot nearest to `time` within the window (up to 150 s away). The card names it: only when it is
    /// this very minute is the picture the server's own; up to two and a half minutes away it is calculated from that answer.
    public func snapshotTime(near time: Date, now: Date) -> Date? {
        var best: Date?
        for (key, state) in slots where key.part == nil && abs(key.time.timeIntervalSince(time)) <= config.exactWindow {
            switch state.phase {
            case .done(let at), .split(let at):
                guard now.timeIntervalSince(at) <= config.freshness else { continue }
                let distance = abs(key.time.timeIntervalSince(time))
                if let current = best {
                    let currentDistance = abs(current.timeIntervalSince(time))
                    if currentDistance < distance || (currentDistance == distance && current <= key.time) { continue }   // the earlier one on a tie
                }
                best = key.time
            default:
                continue
            }
        }
        return best
    }

    // MARK: Progress

    /// The points of the plan: how many are loaded, how many failed for good, how many there are.
    public var progress: (loaded: Int, failed: Int, total: Int) {
        var loaded = 0, failed = 0, total = 0
        for (key, state) in slots where key.kind == .grid && key.part == nil {
            total += 1
            switch state.phase {
            case .done: loaded += 1
            case .failed: failed += 1
            case .split:
                let halves = slots.filter { $0.key.kind == .grid && $0.key.time == key.time && $0.key.part != nil }
                if halves.contains(where: { $0.value.phase == .failed }) {
                    failed += 1
                } else if halves.count == 2, halves.allSatisfy({ if case .done = $0.value.phase { return true } else { return false } }) {
                    loaded += 1
                }
            default: break
            }
        }
        return (loaded, failed, total)
    }

    public var isLoading: Bool {
        isActive && slots.contains { key, state in
            switch state.phase {
            case .pending, .inFlight: return key.kind == .grid || key.part != nil
            default: return false
            }
        }
    }

    /// Requests on their way.
    public var inFlightCount: Int {
        slots.values.filter { if case .inFlight = $0.phase { return true } else { return false } }.count
    }

    /// A snapshot for a resting minute is on its way or waiting for its turn.
    public var isRefreshingExact: Bool {
        slots.contains { key, state in
            guard key.kind == .exact else { return false }
            switch state.phase {
            case .pending, .inFlight: return true
            default: return false
            }
        }
    }

    /// The snapshots are fewer than planned or cut off: some trains may be missing.
    public var isIncomplete: Bool { progress.failed > 0 || cutOffParts > 0 }

    // MARK: Next step

    public mutating func next(now: Date, claim: (Date) -> Date?) -> Step {
        guard isActive else { return .idle }
        // A request that never reported back frees its slot (a bug in the caller must not stop the plan for good).
        for (key, state) in slots {
            if case .inFlight(let since) = state.phase, now.timeIntervalSince(since) >= config.requestTimeout {
                slots[key]?.phase = .pending
            }
        }
        if let pausedUntil, pausedUntil > now { return .wait(until: pausedUntil) }
        if inFlightCount >= config.maxInFlight { return .wait(until: now.addingTimeInterval(0.25)) }

        var earliest: Date?
        if let exact = exactCandidate(now: now, earliest: &earliest) {
            return send(exact, now: now, claim: claim)
        }
        if let slot = gridCandidate(now: now, earliest: &earliest) {
            return send(slot, now: now, claim: claim)
        }
        if let earliest { return .wait(until: earliest) }
        return .idle
    }

    private mutating func send(_ slot: RadarTimeSlot, now: Date, claim: (Date) -> Date?) -> Step {
        if let free = claim(now) { return .wait(until: free) }
        slots[slot]?.phase = .inFlight(since: now)
        requestsSent += 1
        return .request(RadarTimeRequest(slot: slot))
    }

    /// The resting scrubber: a new snapshot for exactly its minute, once, when nothing near it is planned or fetched.
    private mutating func exactCandidate(now: Date, earliest: inout Date?) -> RadarTimeSlot? {
        let wanted: Date
        let manual: Bool
        if let manualExact {
            wanted = manualExact
            manual = true
        } else if let target, allowsAutoExact, autoExactCount < config.autoExactLimit {
            wanted = target
            manual = false
        } else {
            return nil
        }
        guard abs(wanted.timeIntervalSince(now)) >= config.minExactDistance else {
            if manual { manualExact = nil }
            return nil
        }
        if isMoving { return nil }
        let restsAt = movedAt.addingTimeInterval(config.restDelay)
        if !manual, now < restsAt {
            earliest = min(earliest ?? restsAt, restsAt)
            return nil
        }
        guard !isCovered(wanted) else {
            if manual { manualExact = nil }
            return nil
        }
        let slot = RadarTimeSlot(kind: .exact, time: wanted)
        slots[slot] = SlotState()
        if manual { manualExact = nil } else { autoExactCount += 1 }
        return slot
    }

    /// The pending slot nearest to the scrubber (the earliest while there is none); the two halves of a split answer first.
    private mutating func gridCandidate(now: Date, earliest: inout Date?) -> RadarTimeSlot? {
        var best: (slot: RadarTimeSlot, key: (Int, Double, Date))?
        for (slot, state) in slots {
            guard case .pending = state.phase else { continue }
            if let retryAt = state.retryAt, retryAt > now {
                earliest = min(earliest ?? retryAt, retryAt)
                continue
            }
            let distance = target.map { abs(slot.time.timeIntervalSince($0)) } ?? slot.time.timeIntervalSince(now)
            let key = (slot.part == nil ? 1 : 0, distance, slot.time)
            if let current = best, !Self.precedes(key, current.key) { continue }
            best = (slot, key)
        }
        return best?.slot
    }

    private static func precedes(_ a: (Int, Double, Date), _ b: (Int, Double, Date)) -> Bool {
        if a.0 != b.0 { return a.0 < b.0 }
        if a.1 != b.1 { return a.1 < b.1 }
        return a.2 < b.2
    }

    // MARK: Outcomes

    /// True when the answer is the whole picture for its time: a request for all of Austria that was not cut off at the request cap. A cut-off
    /// answer or one half of a split only adds vehicles to the timeline and never removes any.
    public static func isComplete(_ request: RadarTimeRequest, answeredCount: Int) -> Bool {
        request.slot.part == nil && !RadarTiling.isTruncated(count: answeredCount)
    }

    /// An answer with `answeredCount` entries (`jnyL`, before dropping those without a position). All of Austria cut off at the cap: its two
    /// halves are requested next. A half cut off again is noted (`cutOffParts`) and shown.
    public mutating func recordAnswer(_ request: RadarTimeRequest, answeredCount: Int, now: Date) {
        let slot = request.slot
        var state = slots[slot] ?? SlotState()
        state.attempts = 0
        state.retryAt = nil
        if RadarTiling.isTruncated(count: answeredCount) {
            if slot.part == nil {
                state.phase = .split(at: now)
                slots[slot] = state
                for col in 0..<2 {
                    let half = RadarTimeSlot(kind: slot.kind, time: slot.time, part: RadarTileKey(level: 0, row: 0, col: col))
                    if slots[half] == nil { slots[half] = SlotState() }
                }
                return
            }
            cutOffParts += 1
        }
        state.phase = .done(at: now)
        slots[slot] = state
    }

    /// A failed request: tried again after 15 s, then 30 s, then given up (the point stays missing). A rate limit or an open circuit
    /// pauses all requests (20 s unless the server names a time; at least 10 s).
    public mutating func recordFailure(_ request: RadarTimeRequest, error: Error?, now: Date) {
        var state = slots[request.slot] ?? SlotState()
        state.attempts += 1
        var wait = config.baseBackoff * pow(2, Double(state.attempts - 1))
        if let live = error as? LiveError {
            switch live {
            case .rateLimited(_, let retryAfter):
                let pause = max(retryAfter ?? 20, 10)
                pausedUntil = max(pausedUntil ?? .distantPast, now.addingTimeInterval(pause))
                wait = max(wait, pause)
            case .circuitOpen(_, let until):
                pausedUntil = max(pausedUntil ?? .distantPast, max(until, now.addingTimeInterval(10)))
                wait = max(wait, until.timeIntervalSince(now))
            case .disabled:
                state.attempts = config.maxAttempts
            default:
                break
            }
        }
        if state.attempts >= config.maxAttempts {
            state.phase = .failed
            state.retryAt = nil
        } else {
            state.phase = .pending
            state.retryAt = now.addingTimeInterval(wait)
        }
        slots[request.slot] = state
    }

    /// The request was cancelled before it answered (the view went away): the snapshot is due again, without a try counted.
    public mutating func recordCancelled(_ request: RadarTimeRequest) {
        guard var state = slots[request.slot], case .inFlight = state.phase else { return }
        state.phase = .pending
        slots[request.slot] = state
    }
}
