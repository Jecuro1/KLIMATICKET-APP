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
// - How many requests the radar may send: at most 24 per minute, at most 4 in any 10 seconds and never two within a second, so the planner, the
//   departures and "Live verfolgen" keep their share of the 40 requests per minute of `RequestThrottle`. When the visible
//   tiles want more than that, every tile slows down by the same factor (nobody starves) and the status says so.
// - How many requests are on their way at once (`maxInFlight`) and that a tile is never asked again while its request is still
//   on its way: an answer takes 0.4 to 21 s (docs/OEBB_LIVE.md §R11.1), more than a refresh interval at the worst.
// The budget counts the radar's own requests. The client's single retry after a timeout or a 5xx is not counted here: it goes through
// `RequestThrottle` (40 a minute for the whole app) and the circuit breaker (three failures in a row open it for two minutes).

public struct RadarSchedulerConfig: Sendable, Equatable {
    /// The radar's share of the HAFAS budget (docs/OEBB_LIVE.md §2: 40 per minute for the whole app).
    public var perMinute = 24
    /// Least time between two radar requests, and the most in any `burstWindow` seconds: 4 in 10 s is the same 24 a minute, so a
    /// busy view sends its requests in small steps (the first round of a new view in 4 s) and never as a burst of 12 or of 24.
    public var minGap: TimeInterval = 1.0
    public var burst = 4
    public var burstWindow: TimeInterval = 10
    /// Requests on their way at the same time. The loop that sends them also moves the markers and the status line every second,
    /// so it does not wait for an answer; three at once keep it within the budget above and keep a slow answer from holding up the rest.
    public var maxInFlight = 3
    /// A request that never reported back (a bug in the caller) frees its tile after this long: longer than the client can take for one
    /// request (two tries of at most 60 s, 1.5 s between them, up to 5 s in the throttle before each: 131.5 s). At 90 s a slow answer that
    /// was still loading was asked a second time (Zeitreise review 2).
    public var requestTimeout: TimeInterval = 150
    /// Refresh interval of a dense tile (`denseCount` vehicles or more) and of every tile while the view is zoomed in.
    public var denseInterval: TimeInterval = 20
    /// Refresh interval of a quiet tile in a wide view.
    public var quietInterval: TimeInterval = 45
    public var denseCount = 150
    /// Latitude span (degrees) up to which the view counts as zoomed in: about 330 km from top to bottom of the map, which on
    /// a phone held upright is a region of two Bundesländer, 150 km wide.
    public var zoomedInSpan = 3.0
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
    /// Visible tiles that were never asked or are still waiting for their first answer: their trains are not on the map yet.
    public var pendingTiles = 0
    /// Answered visible tiles whose last answer is older than its retention (`RadarScheduler.retention(for:)`): the store has dropped
    /// their vehicles, so they are on the map and in the numbers no more. It happens after the app was in the background, under the
    /// cockpit or in Low Power Mode for longer than a minute, until the next answer of the tile. A part of `answeredTiles`.
    public var staleTiles = 0
    /// Every visible tile that has an outcome failed: the map keeps its vehicles but nothing new arrives.
    public var isPaused = false
    /// The view is valid but outside the area the radar covers.
    public var outsideCoverage = false
    /// Latitude span of the view in degrees.
    public var latitudeSpan = 0.0
    /// The view contains the whole area the radar covers (all of Austria with its margin).
    public var coversCountry = false
    /// MARK: radarmodes – the city lane (Bus, Bim, U-Bahn; docs/RADAR_MODES.md §3). Every field above is the wide lane's only: the Pünktlichkeit's
    /// completeness, the Zeitreise's `holdsAllOfAustria` and `RadarStatusText.notes` read them unchanged. `period` and `budgetLimited` above
    /// include the shared stretch: city tiles slow the wide tiles down as well.
    public var city = RadarLaneStatus()

    public static let empty = RadarStatus()
}

/// MARK: radarmodes – the status of the city lane, with the same meaning per field as `RadarStatus`.
public struct RadarLaneStatus: Sendable, Equatable {
    /// The lane has a view: a city mode is on and its markers are drawn.
    public var isActive = false
    /// The lane has a view, but the map shows more than `RadarLanePlan.citySpanLimit`: it asks for nothing until you zoom in.
    public var outOfZoom = false
    public var visibleTiles = 0
    public var answeredTiles = 0
    public var failedTiles = 0
    public var pendingTiles = 0
    /// Tiles on the finest city level (8) still cut off at the request cap.
    public var cappedTiles = 0
    /// Tiles that would need a split but stay as they are: the view would need more than `RadarLanePlan.cityMaxTiles` city tiles.
    public var crowdedTiles = 0
    public var staleTiles = 0
    public var oldestAnswerAge: TimeInterval?
    /// Seconds one round of the lane takes under the shared budget.
    public var period: TimeInterval = 0
    public var isPaused = false
    /// The vehicles of the last answer of each answered visible tile (the data estimate counts them).
    public var vehicleCounts: [Int] = []

    public init() {}
}

public extension RadarStatus {
    /// MARK: radarmodes – one number for the pill and the load state: both lanes together.
    var anyAnswered: Bool { answeredTiles > 0 || city.answeredTiles > 0 }
    var anyVisible: Bool { visibleTiles > 0 || city.visibleTiles > 0 }
    /// The age of the oldest answer behind the map: the older of the two lanes.
    var oldestAnswerAgeOfBothLanes: TimeInterval? { [oldestAnswerAge, city.oldestAnswerAge].compactMap { $0 }.max() }
    /// „Radar pausiert“: every lane that has tiles is paused (a lane without tiles does not count).
    var isPausedOnBothLanes: Bool {
        let wide = visibleTiles > 0, cityTiles = city.visibleTiles > 0
        guard wide || cityTiles else { return false }
        return (!wide || isPaused) && (!cityTiles || city.isPaused)
    }
    /// Tiles still to come on either lane.
    var anyPending: Bool { pendingTiles > 0 || city.pendingTiles > 0 }
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
        /// A request for this tile is on its way (set by `next`, cleared by the outcome).
        var isInFlight = false
    }

    public let config: RadarSchedulerConfig
    var states: [RadarTileKey: TileState] = [:]
    private var viewport: RadarBox?
    private var latitudeSpan = 4.2
    private var viewChangedAt: Date?
    private var sentAt: [Date] = []
    private var pausedUntil: Date?
    // MARK: radarmodes – the city lane's view (nil: off), its span, when it changed, its refresh and its tile cap.
    private var cityViewport: RadarBox?
    private var citySpan = 0.0
    private var cityViewChangedAt: Date?
    public private(set) var cityInterval = RadarLanePlan.cityIntervalWiFi
    public var cityMaxTiles = RadarLanePlan.cityMaxTiles

    public init(config: RadarSchedulerConfig = .standard) {
        self.config = config
    }

    /// A scheduler that continues a budget: the send times of the last minute of an earlier radar view (`RadarBudgetLedger`). Its tiles
    /// start empty, and so does its pause: a rate limit or an open circuit is held for the whole app by `LiveHealth`, and a pause after the
    /// kill switch (5 minutes) must not hold a radar opened again after the switch was lifted.
    public init(config: RadarSchedulerConfig = .standard, budget: RadarBudgetState) {
        self.config = config
        sentAt = budget.sentAt.sorted()
    }

    /// What the budget remembers: handed to the next radar view, so closing and opening the radar again is no fresh budget.
    public var budgetState: RadarBudgetState { RadarBudgetState(sentAt: sentAt) }

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

    /// MARK: radarmodes – the wide lane asks for nothing (only Bus, Bim or U-Bahn are on and the Pünktlichkeit layer is off): no wide tile, and
    /// no „Außerhalb des Radar-Bereichs“ either.
    public mutating func clearViewport() {
        viewport = nil
    }

    /// MARK: radarmodes – the city lane's view: the map's rectangle while a city mode is on and its markers are drawn, nil when it is off. It
    /// asks only while `span` is at most `RadarLanePlan.citySpanLimit` (else `status.city.outOfZoom`).
    public mutating func setCityViewport(_ box: RadarBox?, latitudeSpan span: Double, now: Date) {
        guard let box, box.isValid else {
            cityViewport = nil
            return
        }
        if box != cityViewport { cityViewChangedAt = now }
        cityViewport = box
        citySpan = span.isFinite && span > 0 ? span : citySpan
    }

    /// MARK: radarmodes – the city lane's refresh (20 s, or 60 s on a metered path or by choice).
    public mutating func setCityInterval(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        cityInterval = seconds
    }

    /// The city lane may ask now: it has a view and the view is close enough.
    public var cityIsInZoom: Bool { cityViewport != nil && RadarLanePlan.cityInZoom(latitudeSpan: citySpan) }

    /// Forgets every tile (the transport modes changed: the old answers are for other vehicles). The request budget stays.
    public mutating func reset() {
        states = [:]
        pausedUntil = nil
    }

    /// MARK: radarmodes – forgets the tiles of one lane (its modes changed); the other lane, the budget and a pause stay.
    public mutating func reset(lane: RadarLane) {
        states = states.filter { $0.key.lane != lane }
    }

    /// The tiles the view needs: tiles of the zoom's level, each replaced by its children when it was cut off at the cap; then the city
    /// lane's tiles (`cityTiles`).
    public func visibleTiles() -> [RadarTileKey] {
        wideTiles() + cityTiles().tiles
    }

    /// MARK: radarmodes – the city lane's tiles: one level finer than the wide lane, split down to level 8 nearest the centre first, never more
    /// than `cityMaxTiles`. A tile whose split would need more stays as it is and counts as crowded.
    public func cityTiles() -> (tiles: [RadarTileKey], crowded: Int) {
        guard let cityViewport, cityIsInZoom else { return ([], 0) }
        let centre = cityViewport.center
        func distance(_ key: RadarTileKey) -> Double {
            let middle = RadarTileGrid.box(of: key).center
            return hypot(middle.latitude - centre.latitude, (middle.longitude - centre.longitude) * 0.67)
        }
        func nearer(_ a: RadarTileKey, _ b: RadarTileKey) -> Bool {
            let da = distance(a), db = distance(b)
            return da != db ? da < db : a < b
        }
        let level = RadarTileGrid.cityLevel(forLatitudeSpan: citySpan)
        var queue = RadarTileGrid.tiles(intersecting: cityViewport, level: level, lane: .city).sorted(by: nearer)
        var crowded = 0
        if queue.count > cityMaxTiles {
            crowded += queue.count - cityMaxTiles
            queue = Array(queue.prefix(cityMaxTiles))
        }
        var result: [RadarTileKey] = []
        while !queue.isEmpty {
            let key = queue.removeFirst()
            if states[key]?.isSplit == true, key.level < RadarTileGrid.cityMaxLevel {
                let children = RadarTileGrid.children(of: key).filter { RadarTileGrid.box(of: $0).intersects(cityViewport) }
                if result.count + queue.count + children.count <= cityMaxTiles {
                    queue.append(contentsOf: children)
                    queue.sort(by: nearer)
                    continue
                }
                crowded += 1
            }
            result.append(key)
        }
        return (result, crowded)
    }

    /// The wide lane's tiles (trains, S-Bahn, the Pünktlichkeit's Austria): exactly the tiles of the radar before the lanes.
    func wideTiles() -> [RadarTileKey] {
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

    /// Seconds between two requests of a tile, before the budget stretches it. A city tile: the city refresh (20 or 60 s).
    public func interval(for key: RadarTileKey) -> TimeInterval {
        if key.lane == .city { return cityInterval }   // MARK: radarmodes
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

    /// Requests on their way right now.
    public func inFlightCount(now: Date) -> Int {
        states.values.filter { isInFlight($0, now: now) }.count
    }

    private func isInFlight(_ state: TileState, now: Date) -> Bool {
        guard state.isInFlight else { return false }
        guard let last = state.lastRequestAt else { return false }
        return now.timeIntervalSince(last) < config.requestTimeout
    }

    /// A clock that moved backwards (set by hand, a correction) would leave timestamps in the future: the budget would count them
    /// as just sent and the radar would stand still until the clock catches up. They are pulled back to `now`.
    private mutating func pullBackFutureTimestamps(now: Date) {
        if let newest = sentAt.last, newest > now { sentAt = sentAt.map { min($0, now) } }
        for (key, state) in states where (state.lastRequestAt ?? .distantPast) > now || (state.lastAnswerAt ?? .distantPast) > now {
            var fixed = state
            if let at = fixed.lastRequestAt, at > now { fixed.lastRequestAt = now }
            if let at = fixed.lastAnswerAt, at > now { fixed.lastAnswerAt = now }
            states[key] = fixed
        }
    }

    /// What to do now. `.request` marks the tile as asked and uses one slot of the budget.
    public mutating func next(now: Date) -> Step {
        pullBackFutureTimestamps(now: now)
        sentAt.removeAll { now.timeIntervalSince($0) >= 60 }
        let tiles = visibleTiles()
        guard !tiles.isEmpty else { return .idle }
        if let pausedUntil, pausedUntil > now { return .wait(until: pausedUntil) }
        if inFlightCount(now: now) >= config.maxInFlight { return .wait(until: now.addingTimeInterval(0.25)) }

        var best: (key: RadarTileKey, ratio: Double, distance: Double)?
        var earliest: Date?
        let wideCentre = viewport?.center ?? RadarTileGrid.coverage.center
        let cityCentre = cityViewport?.center ?? wideCentre   // MARK: radarmodes – each lane ranks by its own view's centre
        let stretchFactor = stretch(for: tiles)
        for key in tiles {
            let state = states[key] ?? TileState()
            if isInFlight(state, now: now) { continue }   // its answer is on its way: never twice at once
            var dueAt: Date
            if let last = state.lastRequestAt {
                dueAt = last.addingTimeInterval(interval(for: key) * stretchFactor)
            } else {
                // Never asked: due once the view has settled (at once after "Erneut versuchen").
                let changedAt = key.lane == .city ? cityViewChangedAt : viewChangedAt   // MARK: radarmodes
                dueAt = changedAt.map { $0.addingTimeInterval(config.settleDelay) } ?? .distantPast
            }
            if let retryAt = state.retryAt { dueAt = max(dueAt, retryAt) }
            guard dueAt <= now else {
                earliest = min(earliest ?? dueAt, dueAt)
                continue
            }
            // The most overdue tile first; tiles never asked come before all others, the one nearest the centre first.
            let ratio = state.lastRequestAt.map { now.timeIntervalSince($0) / max(interval(for: key), 1) } ?? .infinity
            let middle = RadarTileGrid.box(of: key).center
            let centre = key.lane == .city ? cityCentre : wideCentre
            let distance = hypot(middle.latitude - centre.latitude, (middle.longitude - centre.longitude) * 0.67)
            if let current = best, ratio < current.ratio || (ratio == current.ratio && distance >= current.distance) { continue }
            best = (key, ratio, distance)
        }
        guard let best else { return .wait(until: earliest ?? now.addingTimeInterval(1)) }

        // The budget: spacing between two requests, at most `burst` in any `burstWindow` and `perMinute` in any minute.
        let free = budgetFreeAt(now: now)
        guard free <= now else { return .wait(until: free) }

        sentAt.append(now)
        var state = states[best.key] ?? TileState()
        state.requestBefore = state.lastRequestAt
        state.lastRequestAt = now
        state.isInFlight = true
        states[best.key] = state
        return .request(best.key)
    }

    /// When the budget allows the next request: `now` when it does, else the time it will. Spacing between two requests, at most `burst`
    /// in any `burstWindow` and `perMinute` in any minute. `sentAt` holds only the last minute (the caller prunes it).
    private func budgetFreeAt(now: Date) -> Date {
        var free = now
        if let last = sentAt.last { free = max(free, last.addingTimeInterval(config.minGap)) }
        let recent = sentAt.filter { now.timeIntervalSince($0) < config.burstWindow }
        if recent.count >= config.burst { free = max(free, recent[recent.count - config.burst].addingTimeInterval(config.burstWindow)) }
        if sentAt.count >= config.perMinute { free = max(free, sentAt[sentAt.count - config.perMinute].addingTimeInterval(60)) }
        return free
    }

    /// One slot of the radar's budget for a request that is not a tile: the Zeitreise's snapshots (docs/RADAR_TIMETRAVEL.md). nil: the slot
    /// is taken and the caller sends now; else the time the budget frees one. Counted like a tile request, so the live loop and the
    /// Zeitreise together never exceed 24 a minute, 4 in 10 seconds and one per second. A pause (rate limit, open circuit) holds this too.
    public mutating func claimSlot(now: Date) -> Date? {
        pullBackFutureTimestamps(now: now)
        sentAt.removeAll { now.timeIntervalSince($0) >= 60 }
        if let pausedUntil, pausedUntil > now { return pausedUntil }
        let free = budgetFreeAt(now: now)
        guard free <= now else { return free }
        sentAt.append(now)
        return nil
    }

    /// The whole radar waits until `time` (a rate limit or an open circuit that a Zeitreise request ran into).
    public mutating func pause(until time: Date) {
        pausedUntil = max(pausedUntil ?? .distantPast, time)
    }

    /// True when `next(now:)` would send a request now (ignoring the budget). The manual refresh uses it to know when it is done.
    public func hasDueTiles(now: Date) -> Bool {
        let tiles = visibleTiles()
        let stretchFactor = stretch(for: tiles)
        return tiles.contains { key in
            let state = states[key] ?? TileState()
            if isInFlight(state, now: now) { return false }
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
        state.isInFlight = false
        if RadarTiling.isTruncated(count: count), key.level < RadarTileGrid.finestLevel(for: key.lane) {   // MARK: radarmodes – city tiles to level 8
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
        state.isInFlight = false
        states[key] = state
    }

    /// The request was cancelled before it answered (the view went away): the tile is due again as before. The slot of the
    /// budget stays used, the request may have reached the server.
    public mutating func recordCancelled(_ key: RadarTileKey) {
        guard var state = states[key] else { return }
        state.lastRequestAt = state.requestBefore
        state.isInFlight = false
        states[key] = state
    }

    /// "Erneut versuchen" and "Jetzt aktualisieren": every visible tile is due at once; backoff and pause are cleared. A tile whose
    /// request is on its way stays as it is: that answer is the refresh.
    public mutating func refreshAll() {
        pausedUntil = nil
        viewChangedAt = nil
        cityViewChangedAt = nil   // MARK: radarmodes
        for key in visibleTiles() where states[key]?.isInFlight != true {
            states[key, default: TileState()].lastRequestAt = nil
            states[key]?.retryAt = nil
            states[key]?.failures = 0
        }
    }

    // MARK: Status

    public func status(now: Date) -> RadarStatus {
        var status = RadarStatus()
        status.latitudeSpan = latitudeSpan
        let wide = wideTiles()
        let city = cityTiles()
        let stretchFactor = stretch(for: wide + city.tiles)
        // MARK: radarmodes – the city lane's status first: it has a view of its own, whether the wide lane has one or not.
        status.city = laneStatus(city.tiles, stretch: stretchFactor, now: now)
        status.city.isActive = cityViewport != nil
        status.city.outOfZoom = cityViewport != nil && !cityIsInZoom
        status.city.crowdedTiles = city.crowded
        status.budgetLimited = stretchFactor > 1
        status.visibleTiles = wide.count
        guard let viewport else { return status }
        if wide.isEmpty { status.outsideCoverage = viewport.isValid }
        let area = RadarTileGrid.coverage
        status.coversCountry = viewport.west <= area.west && viewport.east >= area.east
            && viewport.south <= area.south && viewport.north >= area.north
        let lane = laneStatus(wide, stretch: stretchFactor, now: now)
        status.period = lane.period
        status.answeredTiles = lane.answeredTiles
        status.failedTiles = lane.failedTiles
        status.cappedTiles = lane.cappedTiles
        status.staleTiles = lane.staleTiles
        status.oldestAnswerAge = lane.oldestAnswerAge
        status.pendingTiles = lane.pendingTiles
        status.isPaused = lane.isPaused
        return status
    }

    /// The numbers of one lane's visible tiles (the wide lane's are the radar's status as it always was).
    private func laneStatus(_ tiles: [RadarTileKey], stretch stretchFactor: Double, now: Date) -> RadarLaneStatus {
        var status = RadarLaneStatus()
        status.visibleTiles = tiles.count
        status.period = tiles.map { interval(for: $0) * stretchFactor }.max() ?? 0
        var ages: [TimeInterval] = []
        var pending = 0
        for key in tiles {
            let state = states[key]
            if let state, state.failures > 0 {
                status.failedTiles += 1
            } else if let state, let answered = state.lastAnswerAt {
                status.answeredTiles += 1
                if RadarTiling.isTruncated(count: state.vehicleCount ?? 0), key.level >= RadarTileGrid.finestLevel(for: key.lane) {
                    status.cappedTiles += 1
                }
                if let count = state.vehicleCount { status.vehicleCounts.append(count) }
                // The same rule as `RadarFrameStore.prune`: an answer older than its retention has left the store.
                let retention = max(RadarTiling.frameRetention, config.retentionFactor * interval(for: key) * stretchFactor)
                if now.timeIntervalSince(answered) > retention { status.staleTiles += 1 }
            } else {
                pending += 1
            }
            if let answered = state?.lastAnswerAt { ages.append(max(0, now.timeIntervalSince(answered))) }
        }
        status.oldestAnswerAge = ages.max()
        status.pendingTiles = pending
        // Paused only when nothing answers: a tile that is still to be asked first is no failure yet, so the banner does not
        // flash while the other tiles of the same round are on their way. An active pause (rate limit) counts as settled.
        let settled = pending == 0 || (pausedUntil.map { $0 > now } ?? false)
        status.isPaused = status.answeredTiles == 0 && status.failedTiles > 0 && settled
        return status
    }
}

// MARK: - The budget across radar views

/// The radar budget's memory: when the last requests went out (the last minute is enough).
public struct RadarBudgetState: Sendable, Equatable {
    public var sentAt: [Date]

    public init(sentAt: [Date] = []) {
        self.sentAt = sentAt
    }
}

/// One radar budget for the whole app. Each radar view has its own model and scheduler; without this, closing the radar and opening it
/// again started an empty budget, and a user who did that every few seconds (or opened it, started a Zeitreise with its plan of 12
/// snapshots, closed it and opened it again) sent more than 24 radar requests a minute (Zeitreise review 2). The view's model writes its
/// budget here after every change and the next view starts from it. Only the app's throttle (40 a minute) held before.
public final class RadarBudgetLedger: @unchecked Sendable {
    public static let shared = RadarBudgetLedger()

    private let lock = NSLock()
    private var stored = RadarBudgetState()

    public init() {}

    public var state: RadarBudgetState {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            // Only the last minute counts; older send times are dropped so the ledger stays small.
            let newest = newValue.sentAt.max() ?? .distantPast
            stored = RadarBudgetState(sentAt: newValue.sentAt.filter { newest.timeIntervalSince($0) < 60 })
        }
    }
}
