import Foundation

// Zug-Radar request scheduler (docs/OEBB_LIVE.md §R11). Pure and deterministic: no network, no timer, no clock of its own,
// every method takes `now`. The caller asks `next(now:)` what to do, sends one request when the answer is `.request`, and
// reports the outcome with `recordAnswer` or `recordFailure`.
//
// What it decides:
// - Which tiles the view needs: the grid level follows the zoom (`RadarTileGrid.level(forLatitudeSpan:)`); a tile whose
//   answer was cut off at the request cap is replaced by its four children, recursively, down to the finest level.
// - When a tile is asked again: dense tiles and zoomed-in views every 20 s, quiet tiles every 45 s. Tiles that left the view
//   are not asked again.
// - How many requests the radar may send: at most 24 per minute and never two within 2.5 seconds, so the planner, the
//   departures and "Live verfolgen" keep their share of the 40 requests per minute of `RequestThrottle`. When the visible
//   tiles want more than that, every tile slows down by the same factor (nobody starves) and the status says so.

public struct RadarSchedulerConfig: Sendable, Equatable {
    /// The radar's share of the HAFAS budget (docs/OEBB_LIVE.md §2: 40 per minute for the whole app).
    public var perMinute = 24
    /// Least time between two radar requests: 60 s / 24 = 2.5 s, so the requests of a minute are spread evenly and never sent
    /// as a burst of 24 followed by silence.
    public var minGap: TimeInterval = 2.5
    /// Refresh interval of a dense tile (`denseCount` vehicles or more) and of every tile while the view is zoomed in.
    public var denseInterval: TimeInterval = 20
    /// Refresh interval of a quiet tile in a wide view.
    public var quietInterval: TimeInterval = 45
    public var denseCount = 150
    /// Latitude span (degrees) up to which the view counts as zoomed in: about 165 km.
    public var zoomedInSpan = 1.5
    /// A new view settles for this long before its tiles are asked for the first time (a series of moves costs one round).
    public var settleDelay: TimeInterval = 0.8
    /// Retention = this factor × the tile's actual refresh period, never below `RadarTiling.frameRetention`.
    public var retentionFactor = 2.5
    /// Seconds a tile waits after its first failure; doubles with every further failure up to `maxBackoff`.
    public var baseBackoff: TimeInterval = 15
    public var maxBackoff: TimeInterval = 120

    public init() {}

    public static let standard = RadarSchedulerConfig()
}

/// What the status line says, computed from the scheduler (no UI strings here: `RadarStatusText`).
public struct RadarStatus: Sendable, Equatable {
    /// Tiles the view needs now (after splitting).
    public var visibleTiles = 0
    /// Visible tiles whose last outcome is an answer, and those whose last outcome is a failure.
    public var answeredTiles = 0
    public var failedTiles = 0
    /// Age of the oldest answer among the visible tiles that have one.
    public var oldestAnswerAge: TimeInterval?
    /// Seconds one round over all visible tiles takes under the budget (the slowest tile's actual period).
    public var period: TimeInterval = 0
    /// The visible tiles want more requests per minute than the radar may send.
    public var budgetLimited = false
    /// Visible tiles on the finest level that are still cut off at the request cap.
    public var cappedTiles = 0
    /// Every visible tile that has an outcome failed: the map keeps its vehicles but nothing new arrives.
    public var isPaused = false
    /// The view is valid but outside the area the radar covers.
    public var outsideCoverage = false
    /// Latitude span of the view in degrees.
    public var latitudeSpan = 0.0

    public static let empty = RadarStatus()
}

public struct RadarScheduler: Sendable {
    public enum Step: Sendable, Equatable {
        /// Send one request for this tile now.
        case request(RadarTileKey)
        /// Nothing may be sent before this time (budget, spacing, backoff or the next refresh).
        case wait(until: Date)
        /// Nothing to ask: no valid view, or the view is outside the coverage.
        case idle
    }

    struct TileState: Sendable {
        var lastRequestAt: Date?
        var lastAnswerAt: Date?
        var vehicleCount: Int?
        var isSplit = false
        var failures = 0
        var retryAt: Date?
        /// The request time before the one in flight, to give the slot back when a request is cancelled.
        var requestBefore: Date?
    }

    public let config: RadarSchedulerConfig
    var states: [RadarTileKey: TileState] = [:]
    private var viewport: RadarBox?
    private var latitudeSpan = 4.2
    private var viewChangedAt: Date?
    private var sentAt: [Date] = []
    private var pausedUntil: Date?

    public init(config: RadarSchedulerConfig = .standard) {
        self.config = config
    }

    // MARK: View

    /// The visible rectangle and its latitude span. A new rectangle starts the settle delay for tiles never asked before.
    public mutating func setViewport(_ box: RadarBox, latitudeSpan span: Double, now: Date) {
        guard box.isValid else {
            viewport = nil
            return
        }
        if box != viewport { viewChangedAt = now }
        viewport = box
        latitudeSpan = span.isFinite && span > 0 ? span : latitudeSpan
    }

    /// Forgets every tile (the transport modes changed: the old answers are for other vehicles). The request budget stays.
    public mutating func reset() {
        states = [:]
        pausedUntil = nil
    }

    /// The tiles the view needs: tiles of the zoom's level, each replaced by its children when it was cut off at the cap.
    public func visibleTiles() -> [RadarTileKey] {
        guard let viewport else { return [] }
        var result: [RadarTileKey] = []
        func resolve(_ key: RadarTileKey) {
            if states[key]?.isSplit == true, key.level < RadarTileGrid.maxLevel {
                for child in RadarTileGrid.children(of: key) where RadarTileGrid.box(of: child).intersects(viewport) {
                    resolve(child)
                }
            } else {
                result.append(key)
            }
        }
        for key in RadarTileGrid.tiles(intersecting: viewport, level: RadarTileGrid.level(forLatitudeSpan: latitudeSpan)) {
            resolve(key)
        }
        return result
    }

    // MARK: Intervals and budget

    /// Seconds between two requests of a tile, before the budget stretches it.
    public func interval(for key: RadarTileKey) -> TimeInterval {
        let dense = (states[key]?.vehicleCount ?? 0) >= config.denseCount
        return dense || latitudeSpan <= config.zoomedInSpan ? config.denseInterval : config.quietInterval
    }

    /// 1 when the visible tiles fit into the budget; above 1 every tile is slowed down by this factor.
    func stretch(for tiles: [RadarTileKey]) -> Double {
        let demand = tiles.reduce(0.0) { $0 + 1 / interval(for: $1) }
        return max(1, demand / (Double(config.perMinute) / 60))
    }

    /// The seconds a tile really waits between two requests: its interval times the budget stretch.
    public func period(for key: RadarTileKey) -> TimeInterval {
        interval(for: key) * stretch(for: visibleTiles())
    }

    /// How long the vehicles of an answer stay: 2.5 periods, at least `RadarTiling.frameRetention`. A quiet tile that is
    /// refreshed every 45 s keeps its trains for 112 s, so they do not vanish between two refreshes.
    public func retention(for key: RadarTileKey) -> TimeInterval {
        max(RadarTiling.frameRetention, config.retentionFactor * period(for: key))
    }

    // MARK: Next step

    /// What to do now. `.request` marks the tile as asked and uses one slot of the budget.
    public mutating func next(now: Date) -> Step {
        sentAt.removeAll { now.timeIntervalSince($0) >= 60 }
        let tiles = visibleTiles()
        guard !tiles.isEmpty else { return .idle }
        if let pausedUntil, pausedUntil > now { return .wait(until: pausedUntil) }

        var best: (key: RadarTileKey, ratio: Double, distance: Double)?
        var earliest: Date?
        let centre = viewport?.center ?? RadarTileGrid.coverage.center
        let stretchFactor = stretch(for: tiles)
        for key in tiles {
            let state = states[key] ?? TileState()
            var dueAt: Date
            if let last = state.lastRequestAt {
                dueAt = last.addingTimeInterval(interval(for: key) * stretchFactor)
            } else {
                // Never asked: due once the view has settled (at once after "Erneut versuchen").
                dueAt = viewChangedAt.map { $0.addingTimeInterval(config.settleDelay) } ?? .distantPast
            }
            if let retryAt = state.retryAt { dueAt = max(dueAt, retryAt) }
            guard dueAt <= now else {
                earliest = min(earliest ?? dueAt, dueAt)
                continue
            }
            // The most overdue tile first; tiles never asked come before all others, the one nearest the centre first.
            let ratio = state.lastRequestAt.map { now.timeIntervalSince($0) / max(interval(for: key), 1) } ?? .infinity
            let middle = RadarTileGrid.box(of: key).center
            let distance = hypot(middle.latitude - centre.latitude, (middle.longitude - centre.longitude) * 0.67)
            if let current = best, ratio < current.ratio || (ratio == current.ratio && distance >= current.distance) { continue }
            best = (key, ratio, distance)
        }
        guard let best else { return .wait(until: earliest ?? now.addingTimeInterval(1)) }

        // The budget: spacing between two requests and at most `perMinute` in any minute.
        var free = now
        if let last = sentAt.last { free = max(free, last.addingTimeInterval(config.minGap)) }
        if sentAt.count >= config.perMinute { free = max(free, sentAt[sentAt.count - config.perMinute].addingTimeInterval(60)) }
        guard free <= now else { return .wait(until: free) }

        sentAt.append(now)
        var state = states[best.key] ?? TileState()
        state.requestBefore = state.lastRequestAt
        state.lastRequestAt = now
        states[best.key] = state
        return .request(best.key)
    }

    /// True when `next(now:)` would send a request now (ignoring the budget). The manual refresh uses it to know when it is done.
    public func hasDueTiles(now: Date) -> Bool {
        let tiles = visibleTiles()
        let stretchFactor = stretch(for: tiles)
        return tiles.contains { key in
            let state = states[key] ?? TileState()
            if let retryAt = state.retryAt, retryAt > now { return false }
            guard let last = state.lastRequestAt else { return true }
            return now >= last.addingTimeInterval(interval(for: key) * stretchFactor)
        }
    }

    // MARK: Outcomes

    /// An answer with `count` vehicles. A tile at the request cap is split (the next rounds ask its children); when the
    /// four children of a split tile together hold less than half the cap, the split is undone.
    public mutating func recordAnswer(_ key: RadarTileKey, count: Int, at now: Date) {
        var state = states[key] ?? TileState()
        state.lastAnswerAt = now
        state.vehicleCount = count
        state.failures = 0
        state.retryAt = nil
        if RadarTiling.isTruncated(count: count), key.level < RadarTileGrid.maxLevel {
            state.isSplit = true
        }
        states[key] = state
        mergeIfSparse(parentOf: key, now: now)
    }

    private mutating func mergeIfSparse(parentOf key: RadarTileKey, now: Date) {
        guard let parent = RadarTileGrid.parent(of: key), states[parent]?.isSplit == true else { return }
        let counts = RadarTileGrid.children(of: parent).map { child -> (Int, Date)? in
            guard let count = states[child]?.vehicleCount, let at = states[child]?.lastAnswerAt else { return nil }
            return (count, at)
        }
        guard counts.allSatisfy({ $0 != nil }) else { return }
        let all = counts.compactMap { $0 }
        guard all.allSatisfy({ now.timeIntervalSince($0.1) < 120 }),
              all.reduce(0, { $0 + $1.0 }) * 2 < RadarTiling.requestCap else { return }
        states[parent]?.isSplit = false
        states[parent]?.lastRequestAt = nil   // the parent is asked again at once; its old answer is the children's
    }

    /// A failed request. Rate limit (20 s unless the server names a time) and open circuit pause the whole radar; any other
    /// failure backs the tile off (15 s, 30 s, … up to 2 min).
    public mutating func recordFailure(_ key: RadarTileKey, error: Error?, at now: Date) {
        var state = states[key] ?? TileState()
        state.failures += 1
        var wait = min(config.baseBackoff * pow(2, Double(state.failures - 1)), config.maxBackoff)
        if let live = error as? LiveError {
            switch live {
            case .rateLimited(_, let retryAfter):
                let pause = max(retryAfter ?? 20, 10)
                pausedUntil = now.addingTimeInterval(pause)
                wait = max(wait, pause)
            case .circuitOpen(_, let until):
                pausedUntil = max(until, now.addingTimeInterval(10))
                wait = max(wait, until.timeIntervalSince(now))
            case .disabled:
                pausedUntil = now.addingTimeInterval(300)
                wait = max(wait, 300)
            default:
                break
            }
        }
        state.retryAt = now.addingTimeInterval(wait)
        states[key] = state
    }

    /// The request was cancelled before it answered (the view went away): the tile is due again as before. The slot of the
    /// budget stays used, the request may have reached the server.
    public mutating func recordCancelled(_ key: RadarTileKey) {
        guard var state = states[key] else { return }
        state.lastRequestAt = state.requestBefore
        states[key] = state
    }

    /// "Erneut versuchen" and "Jetzt aktualisieren": every visible tile is due at once; backoff and pause are cleared.
    public mutating func refreshAll() {
        pausedUntil = nil
        viewChangedAt = nil
        for key in visibleTiles() {
            states[key, default: TileState()].lastRequestAt = nil
            states[key]?.retryAt = nil
            states[key]?.failures = 0
        }
    }

    // MARK: Status

    public func status(now: Date) -> RadarStatus {
        var status = RadarStatus()
        status.latitudeSpan = latitudeSpan
        let tiles = visibleTiles()
        status.visibleTiles = tiles.count
        guard let viewport else { return status }
        if tiles.isEmpty { status.outsideCoverage = viewport.isValid }
        let stretchFactor = stretch(for: tiles)
        status.budgetLimited = stretchFactor > 1
        status.period = tiles.map { interval(for: $0) * stretchFactor }.max() ?? 0
        var ages: [TimeInterval] = []
        var pending = 0
        for key in tiles {
            let state = states[key]
            if let state, state.failures > 0 {
                status.failedTiles += 1
            } else if let state, state.lastAnswerAt != nil {
                status.answeredTiles += 1
                if RadarTiling.isTruncated(count: state.vehicleCount ?? 0), key.level >= RadarTileGrid.maxLevel {
                    status.cappedTiles += 1
                }
            } else {
                pending += 1
            }
            if let answered = state?.lastAnswerAt { ages.append(max(0, now.timeIntervalSince(answered))) }
        }
        status.oldestAnswerAge = ages.max()
        // Paused only when nothing answers: a tile that is still to be asked first is no failure yet, so the banner does not
        // flash while the other tiles of the same round are on their way. An active pause (rate limit) counts as settled.
        let settled = pending == 0 || (pausedUntil.map { $0 > now } ?? false)
        status.isPaused = status.answeredTiles == 0 && status.failedTiles > 0 && settled
        return status
    }
}
