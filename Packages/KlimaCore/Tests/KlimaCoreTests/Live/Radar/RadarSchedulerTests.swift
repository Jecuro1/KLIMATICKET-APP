import XCTest
@testable import KlimaCore

/// The Zug-Radar request scheduler (docs/OEBB_LIVE.md §R11): adaptive splitting, the 24 requests per minute budget, fairness,
/// refresh by density, viewport changes, retention per tile and failure handling. Pure: the tests move the clock themselves.
final class RadarSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    private let west = RadarTileKey(level: 0, row: 0, col: 0)
    private let east = RadarTileKey(level: 0, row: 0, col: 1)
    /// One tile at level 2 (a zoomed-in view): latitude span 0.5, inside tile 2/1/3.
    private let oneTileView = RadarBox(north: 47.6, west: 12.6, south: 47.1, east: 13.1)
    private let oneTile = RadarTileKey(level: 2, row: 1, col: 3)

    private func austria(_ config: RadarSchedulerConfig = .standard) -> RadarScheduler {
        var scheduler = RadarScheduler(config: config)
        scheduler.setViewport(.austria, latitudeSpan: 4.2, now: t0)
        return scheduler
    }

    /// Runs the scheduler for `seconds` in `step` slices; every request is answered at once by `answer` (a vehicle count, or nil
    /// for a failure). Returns the requests.
    @discardableResult
    private func simulate(_ scheduler: inout RadarScheduler, from start: Date, seconds: TimeInterval, step: TimeInterval = 0.25,
                          answer: (RadarTileKey) -> Int?) -> [(at: Date, tile: RadarTileKey)] {
        var sent: [(Date, RadarTileKey)] = []
        var elapsed = 0.0
        while elapsed <= seconds {
            let now = start.addingTimeInterval(elapsed)
            if case .request(let tile) = scheduler.next(now: now) {
                sent.append((now, tile))
                if let count = answer(tile) {
                    scheduler.recordAnswer(tile, count: count, at: now)
                } else {
                    scheduler.recordFailure(tile, error: LiveError.network("test"), at: now)
                }
            }
            elapsed += step
        }
        return sent.map { (at: $0.0, tile: $0.1) }
    }

    private func maxInAnyMinute(_ sent: [(at: Date, tile: RadarTileKey)]) -> Int {
        sent.indices.map { i in sent.filter { $0.at <= sent[i].at && sent[i].at.timeIntervalSince($0.at) < 60 }.count }.max() ?? 0
    }

    // MARK: First round

    func testFirstRoundWaitsForTheViewToSettleThenSpreadsTheRequests() throws {
        var scheduler = austria()
        XCTAssertEqual(scheduler.visibleTiles(), [west, east], "the Austria view is two tiles")
        XCTAssertEqual(scheduler.next(now: t0), .wait(until: t0.addingTimeInterval(0.8)), "a new view settles first")
        guard case .request(let first) = scheduler.next(now: t0.addingTimeInterval(0.8)) else { return XCTFail("first request") }
        XCTAssertEqual(scheduler.next(now: t0.addingTimeInterval(0.8)), .wait(until: t0.addingTimeInterval(3.3)), "2.5 s between two requests")
        guard case .request(let second) = scheduler.next(now: t0.addingTimeInterval(3.3)) else { return XCTFail("second request") }
        XCTAssertEqual(Set([first, second]), [west, east])
    }

    func testNoValidViewMeansNothingToAsk() {
        var scheduler = RadarScheduler()
        XCTAssertEqual(scheduler.next(now: t0), .idle)
        scheduler.setViewport(RadarBox(north: 47, west: 13, south: 47, east: 14), latitudeSpan: 0, now: t0)
        XCTAssertEqual(scheduler.next(now: t0), .idle, "a degenerate box asks nothing")
    }

    func testAViewOutsideTheCoverageAsksNothingAndSaysSo() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarBox(north: 52, west: 5, south: 50, east: 8), latitudeSpan: 2, now: t0)
        XCTAssertEqual(scheduler.next(now: t0.addingTimeInterval(5)), .idle)
        XCTAssertTrue(scheduler.status(now: t0).outsideCoverage)
    }

    // MARK: Adaptive split

    func testATileAtTheCapIsReplacedByItsFourChildren() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 1000, at: t0)
        scheduler.recordAnswer(east, count: 420, at: t0)
        let visible = scheduler.visibleTiles()
        XCTAssertEqual(visible.count, 5, "the west tile became four tiles of level 1, the east tile stays")
        XCTAssertTrue(visible.contains(east))
        XCTAssertFalse(visible.contains(west))
        XCTAssertEqual(Set(visible.filter { $0.level == 1 }), Set(RadarTileGrid.children(of: west)))
    }

    func testSplittingContinuesDownToTheFinestLevelAndThenSaysSo() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        var key = oneTile
        var now = t0
        for level in 2..<RadarTileGrid.maxLevel {
            now = now.addingTimeInterval(3)
            scheduler.recordAnswer(key, count: 1000, at: now)
            let visible = scheduler.visibleTiles()
            XCTAssertFalse(visible.contains(key), "level \(level) is replaced by its children")
            guard let child = visible.first(where: { $0.level == level + 1 && RadarTileGrid.parent(of: $0) == key }) else {
                return XCTFail("no child of \(key.label) inside the view")
            }
            key = child
        }
        XCTAssertEqual(key.level, RadarTileGrid.maxLevel)
        scheduler.recordAnswer(key, count: 1000, at: now.addingTimeInterval(3))   // still cut off at the finest level
        XCTAssertTrue(scheduler.visibleTiles().contains(key), "there is nothing finer: the tile stays")
        let status = scheduler.status(now: now.addingTimeInterval(4))
        XCTAssertEqual(status.cappedTiles, 1, "the status owns up to a tile that is still cut off")
        XCTAssertEqual(RadarStatusText.notes(status, rail: true).first?.contains("mehr Züge"), true)
    }

    func testOnlyChildrenInsideTheViewAreAsked() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        scheduler.recordAnswer(oneTile, count: 1000, at: t0)
        let box = oneTileView
        let visible = scheduler.visibleTiles()
        XCTAssertTrue(visible.allSatisfy { RadarTileGrid.box(of: $0).intersects(box) })
        XCTAssertLessThan(visible.count, 4 + 1, "at most the four children, usually fewer")
    }

    func testSplitIsUndoneWhenTheChildrenTogetherAreSparse() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 1000, at: t0)
        let kids = RadarTileGrid.children(of: west)
        let now = t0.addingTimeInterval(10)
        for (index, kid) in kids.enumerated() { scheduler.recordAnswer(kid, count: [300, 200, 100, 50][index], at: now) }
        XCTAssertFalse(scheduler.visibleTiles().contains(west), "650 vehicles in four children: still split")
        // 650 is not below half the cap, so the split stays; now the evening comes and the children empty out.
        for kid in kids { scheduler.recordAnswer(kid, count: 40, at: now.addingTimeInterval(20)) }
        XCTAssertTrue(scheduler.visibleTiles().contains(west), "160 vehicles in four children: one tile is enough again")
    }

    // MARK: Refresh by density and zoom

    func testDenseTilesRefreshEvery20SecondsAndQuietOnesEvery45() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 480, at: t0)
        scheduler.recordAnswer(east, count: 40, at: t0)
        XCTAssertEqual(scheduler.interval(for: west), 20)
        XCTAssertEqual(scheduler.interval(for: east), 45)
        let sent = simulate(&scheduler, from: t0.addingTimeInterval(1), seconds: 95) { $0 == self.west ? 480 : 40 }
        let westTimes = sent.filter { $0.tile == west }.map { $0.at.timeIntervalSince(t0) }
        let eastTimes = sent.filter { $0.tile == east }.map { $0.at.timeIntervalSince(t0) }
        XCTAssertEqual(westTimes.count, 5, "the dense tile is asked about every 20 s: \(westTimes)")
        XCTAssertEqual(eastTimes.count, 3, "the quiet tile about every 45 s: \(eastTimes)")
        for (a, b) in zip(westTimes, westTimes.dropFirst()) { XCTAssertEqual(b - a, 20, accuracy: 1.1) }
        for (a, b) in zip(eastTimes, eastTimes.dropFirst()) { XCTAssertEqual(b - a, 45, accuracy: 1.1) }
    }

    func testEveryTileCountsAsDenseWhileTheViewIsZoomedIn() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        scheduler.recordAnswer(oneTile, count: 12, at: t0)
        XCTAssertEqual(scheduler.interval(for: oneTile), 20, "a quiet tile in a zoomed-in view")
        scheduler.setViewport(.austria, latitudeSpan: 4.2, now: t0)
        XCTAssertEqual(scheduler.interval(for: oneTile), 45, "the same tile in a country view")
        scheduler.setViewport(oneTileView, latitudeSpan: 2.9, now: t0)
        XCTAssertEqual(scheduler.interval(for: oneTile), 20, "a view two Bundesländer tall is still zoomed in")
        scheduler.setViewport(oneTileView, latitudeSpan: 3.1, now: t0)
        XCTAssertEqual(scheduler.interval(for: oneTile), 45)
    }

    // MARK: Budget

    func testTheBudgetOf24RequestsPerMinuteIsNeverExceededOverTenMinutes() {
        var scheduler = austria()
        // Every tile above level 1 is cut off, so the view ends up with 32 tiles of level 2, all of them dense.
        let sent = simulate(&scheduler, from: t0, seconds: 600) { $0.level < 2 ? 1000 : 300 }
        XCTAssertEqual(scheduler.visibleTiles().count, 32)
        XCTAssertLessThanOrEqual(maxInAnyMinute(sent), 24, "no minute holds more than 24 requests")
        XCTAssertGreaterThan(sent.count, 200, "and the budget is really used: \(sent.count) requests in 10 minutes")
        for (a, b) in zip(sent, sent.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.at.timeIntervalSince(a.at), 2.5 - 1e-9, "never a burst: 2.5 s apart at least")
        }
    }

    func testPanningAroundForTenMinutesNeverExceedsTheBudgetEither() {
        var scheduler = austria()
        let views: [(RadarBox, Double)] = [
            (.austria, 4.2), (oneTileView, 0.5), (RadarBox(north: 48.4, west: 15.5, south: 47.6, east: 17.0), 0.8),
            (RadarBox(north: 47.9, west: 9.5, south: 46.4, east: 11.5), 1.5),
        ]
        var sent: [(at: Date, tile: RadarTileKey)] = []
        for step in 0..<86 {   // a new view every 7 seconds: about ten minutes
            let start = t0.addingTimeInterval(Double(step) * 7)
            let (box, span) = views[step % views.count]
            scheduler.setViewport(box, latitudeSpan: span, now: start)
            sent += simulate(&scheduler, from: start, seconds: 6.75) { $0.level < 1 ? 1000 : 200 }
        }
        XCTAssertGreaterThan(sent.count, 100)
        XCTAssertLessThanOrEqual(maxInAnyMinute(sent), 24)
    }

    func testTheSharedBudgetLeavesRoomForThePlannerAndFollow() {
        XCTAssertEqual(RadarSchedulerConfig.standard.perMinute, 24)
        XCTAssertLessThanOrEqual(RadarSchedulerConfig.standard.perMinute, RequestThrottle.budget(for: .oebbHafas).perMinute - 16,
                                 "at least 16 of the 40 requests per minute stay with the other features")
    }

    func testNoTileStarvesWhenTheBudgetBinds() {
        var scheduler = austria()
        let sent = simulate(&scheduler, from: t0, seconds: 600) { $0.level < 2 ? 1000 : 300 }
        let tiles = scheduler.visibleTiles()
        var counts: [RadarTileKey: Int] = [:]
        for request in sent where tiles.contains(request.tile) { counts[request.tile, default: 0] += 1 }
        XCTAssertEqual(counts.count, 32, "every visible tile was asked")
        XCTAssertLessThanOrEqual((counts.values.max() ?? 0) - (counts.values.min() ?? 0), 2, "fair: \(counts.values.sorted())")
        // Once the first round is through, every tile waits about its stretched period (32 tiles at 24 a minute: 80 s) and
        // never longer: nobody is overtaken for ever.
        for tile in tiles {
            let times = sent.filter { $0.tile == tile }.map(\.at)
            let gaps = zip(times, times.dropFirst()).filter { $1.timeIntervalSince(t0) > 200 }.map { $1.timeIntervalSince($0) }
            XCTAssertFalse(gaps.isEmpty)
            XCTAssertLessThan(gaps.max() ?? 0, 85, "tile \(tile.label)")
        }
    }

    func testTheStatusSaysWhenTheBudgetCannotKeepEveryTileFresh() {
        var scheduler = austria()
        simulate(&scheduler, from: t0, seconds: 300) { $0.level < 2 ? 1000 : 300 }
        let status = scheduler.status(now: t0.addingTimeInterval(300))
        XCTAssertTrue(status.budgetLimited)
        XCTAssertEqual(status.visibleTiles, 32)
        XCTAssertEqual(status.period, 80, accuracy: 0.5, "32 tiles × 20 s each, 24 requests a minute")
        let notes = RadarStatusText.notes(status, rail: true)
        XCTAssertEqual(notes, ["Ganz Österreich · aktualisiert alle ~80 s"])
    }

    func testAFewTilesFitIntoTheBudgetWithoutAnyNote() {
        var scheduler = austria()
        simulate(&scheduler, from: t0, seconds: 120) { $0 == self.west ? 480 : 430 }
        let status = scheduler.status(now: t0.addingTimeInterval(120))
        XCTAssertFalse(status.budgetLimited)
        XCTAssertEqual(status.period, 20)
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).isEmpty)
    }

    // MARK: Viewport changes

    func testTilesThatLeftTheViewAreNotAskedAgainAndNewOnesComeFirst() {
        var scheduler = austria()
        let first = simulate(&scheduler, from: t0, seconds: 30) { _ in 480 }
        XCTAssertEqual(Set(first.map(\.tile)), [west, east])

        let moved = t0.addingTimeInterval(40)
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: moved)
        XCTAssertEqual(scheduler.visibleTiles(), [oneTile])
        XCTAssertEqual(scheduler.next(now: moved), .wait(until: moved.addingTimeInterval(0.8)), "the new view settles first")
        let after = simulate(&scheduler, from: moved, seconds: 60) { _ in 30 }
        XCTAssertTrue(after.allSatisfy { $0.tile == oneTile }, "the old tiles are not asked any more")
        XCTAssertEqual(after.first?.at.timeIntervalSince(moved) ?? 0, 0.8, accuracy: 0.26)
        XCTAssertEqual(after.count, 3, "zoomed in: every 20 s, at 1 s, 21 s and 41 s")
    }

    func testAMovingMapIsNotAskedWhileItKeepsMoving() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        // The view changes again 0.5 s later, before the first one has settled: the settle time starts over.
        let shifted = RadarBox(north: 47.65, west: 12.6, south: 47.15, east: 13.1)
        scheduler.setViewport(shifted, latitudeSpan: 0.5, now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(scheduler.next(now: t0.addingTimeInterval(1.0)), .wait(until: t0.addingTimeInterval(1.3)))
    }

    // MARK: Failures

    func testAFailedTileKeepsItsVehiclesAndRetriesWithBackoff() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        scheduler.recordAnswer(oneTile, count: 25, at: t0)
        let failedAt = t0.addingTimeInterval(20)
        scheduler.recordFailure(oneTile, error: LiveError.timeout, at: failedAt)
        XCTAssertEqual(scheduler.status(now: failedAt).failedTiles, 1)
        XCTAssertEqual(scheduler.next(now: failedAt.addingTimeInterval(5)).isWait, true, "backoff: not yet")
        scheduler.recordFailure(oneTile, error: LiveError.timeout, at: failedAt.addingTimeInterval(15))
        // First failure: 15 s, second: 30 s.
        let second = failedAt.addingTimeInterval(15)
        XCTAssertEqual(scheduler.next(now: second.addingTimeInterval(29)).isWait, true)
        XCTAssertEqual(scheduler.next(now: second.addingTimeInterval(30)), .request(oneTile))
        scheduler.recordAnswer(oneTile, count: 25, at: second.addingTimeInterval(31))
        XCTAssertEqual(scheduler.status(now: second.addingTimeInterval(31)).failedTiles, 0, "an answer clears the failure")
    }

    func testBackoffIsCappedAtTwoMinutes() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        var now = t0
        for _ in 0..<10 { scheduler.recordFailure(oneTile, error: nil, at: now); now = now.addingTimeInterval(1) }
        XCTAssertEqual(scheduler.states[oneTile]?.retryAt, now.addingTimeInterval(-1).addingTimeInterval(120))
    }

    func testOneFailedTileOfTwoIsNoPauseAndTheOtherKeepsRunning() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 480, at: t0)
        scheduler.recordAnswer(east, count: 430, at: t0)
        scheduler.recordFailure(east, error: LiveError.timeout, at: t0.addingTimeInterval(20))
        let status = scheduler.status(now: t0.addingTimeInterval(21))
        XCTAssertFalse(status.isPaused, "'Radar pausiert' only when every tile fails")
        XCTAssertEqual(status.failedTiles, 1)
        XCTAssertEqual(status.answeredTiles, 1)
        XCTAssertEqual(RadarStatusText.notes(status, rail: true), ["Für einen Teil der Karte kam keine Antwort. Es wird neu versucht."])
    }

    func testAllTilesFailingIsAPause() {
        var scheduler = austria()
        scheduler.recordFailure(west, error: LiveError.offline, at: t0)
        XCTAssertFalse(scheduler.status(now: t0).isPaused, "the other tile of the round is still to be asked: no flash of the banner")
        scheduler.recordFailure(east, error: LiveError.offline, at: t0.addingTimeInterval(1))
        let status = scheduler.status(now: t0.addingTimeInterval(2))
        XCTAssertTrue(status.isPaused)
        XCTAssertEqual(status.failedTiles, 2)
    }

    func testRateLimitPausesTheWholeRadarForTheTimeTheErrorNames() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 480, at: t0)
        scheduler.recordAnswer(east, count: 430, at: t0)
        let now = t0.addingTimeInterval(20)
        scheduler.recordFailure(west, error: LiveError.rateLimited(.oebbHafas, retryAfter: 45), at: now)
        XCTAssertEqual(scheduler.next(now: now.addingTimeInterval(10)), .wait(until: now.addingTimeInterval(45)), "no tile is asked during the pause")
        XCTAssertEqual(scheduler.next(now: now.addingTimeInterval(45)).isRequest, true)
    }

    func testAnOpenCircuitPausesUntilItCloses() {
        var scheduler = austria()
        let until = t0.addingTimeInterval(600)
        scheduler.recordFailure(west, error: LiveError.circuitOpen(.oebbHafas, until: until), at: t0.addingTimeInterval(5))
        XCTAssertEqual(scheduler.next(now: t0.addingTimeInterval(60)), .wait(until: until))
    }

    func testACancelledRequestGivesTheTileBackButNotTheBudgetSlot() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(oneTileView, latitudeSpan: 0.5, now: t0)
        let now = t0.addingTimeInterval(1)
        XCTAssertEqual(scheduler.next(now: now), .request(oneTile))
        scheduler.recordCancelled(oneTile)
        XCTAssertEqual(scheduler.next(now: now), .wait(until: now.addingTimeInterval(2.5)), "the request may have reached the server: spacing applies")
        XCTAssertEqual(scheduler.next(now: now.addingTimeInterval(2.5)), .request(oneTile), "but the tile is due again at once")
    }

    func testRefreshAllMakesEveryVisibleTileDueAndClearsTheBackoff() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 480, at: t0)
        scheduler.recordFailure(east, error: LiveError.rateLimited(.oebbHafas, retryAfter: 60), at: t0)
        scheduler.refreshAll()
        XCTAssertTrue(scheduler.hasDueTiles(now: t0.addingTimeInterval(1)))
        let sent = simulate(&scheduler, from: t0.addingTimeInterval(1), seconds: 4) { _ in 100 }
        XCTAssertEqual(Set(sent.map(\.tile)), [west, east], "both tiles are asked again, one after the other")
    }

    // MARK: Retention follows the refresh period

    func testRetentionFollowsTheTilesRefreshPeriod() {
        var scheduler = austria()
        scheduler.recordAnswer(west, count: 480, at: t0)   // dense: 20 s
        scheduler.recordAnswer(east, count: 40, at: t0)    // quiet: 45 s
        XCTAssertEqual(scheduler.retention(for: west), 60, "2.5 × 20 s = 50 s, never below the 60 s minimum")
        XCTAssertEqual(scheduler.retention(for: east), 112.5, "2.5 × 45 s")
    }

    func testRetentionGrowsWhenTheBudgetStretchesThePeriod() {
        var scheduler = austria()
        simulate(&scheduler, from: t0, seconds: 200) { $0.level < 2 ? 1000 : 300 }
        let tile = scheduler.visibleTiles()[0]
        XCTAssertEqual(scheduler.retention(for: tile), 200, accuracy: 1, "2.5 × 80 s: a tile asked every 80 s keeps its trains for 200 s")
    }
}

private extension RadarScheduler.Step {
    var isWait: Bool { if case .wait = self { return true } else { return false } }
    var isRequest: Bool { if case .request = self { return true } else { return false } }
}
