import XCTest
@testable import KlimaCore

/// Review 2 of the Pünktlichkeit layer (docs/RADAR_HEATMAP.md §1a): no gesture gets the radar past its budget of 24 requests a minute,
/// 4 in 10 seconds and one a second, and a tile whose answer is too old to count is known as such. The layer itself sends nothing:
/// it hands the radar's scheduler the country as its view (`RadarModel.applyViewport`). These runs drive the scheduler the way the
/// radar model does, with answers that take seconds (several requests on their way at once) and with the gestures of a person.
final class HeatBudgetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    /// What `RadarModel.heatSpan` hands the scheduler while the layer is on.
    private let heatSpan = RadarTileGrid.coverage.north - RadarTileGrid.coverage.south
    /// Vienna, zoomed in: what the map shows while the layer is off.
    private let vienna = RadarBox(north: 48.32, west: 16.18, south: 48.10, east: 16.58)

    private struct Flight {
        var tile: RadarTileKey
        var requestedAt: Date
        var answerAt: Date
    }

    /// Runs the loop of `RadarModel.run` every quarter second for `seconds`. Each request answers after `latency` s with `count`
    /// vehicles. `gesture` runs before each step and may change the view, cancel what is on its way (the view went away) or claim
    /// slots for the Zeitreise; it returns false while the loop is not running (the app in the background). Returns the times at
    /// which a slot of the budget was used: tile requests and claimed slots.
    private func drive(_ scheduler: inout RadarScheduler, seconds: TimeInterval, latency: TimeInterval = 3, count: Int = 450,
                       gesture: (inout RadarScheduler, Date, inout [Flight], inout [Date]) -> Bool) -> [Date] {
        var used: [Date] = []
        var flights: [Flight] = []
        var elapsed = 0.0
        while elapsed <= seconds {
            let now = t0.addingTimeInterval(elapsed)
            for flight in flights where flight.answerAt <= now {
                // The model records the answer at the time of its request: that is the time the positions belong to.
                scheduler.recordAnswer(flight.tile, count: count, at: flight.requestedAt)
            }
            flights.removeAll { $0.answerAt <= now }
            if gesture(&scheduler, now, &flights, &used), case .request(let tile) = scheduler.next(now: now) {
                used.append(now)
                flights.append(Flight(tile: tile, requestedAt: now, answerAt: now.addingTimeInterval(latency)))
            }
            elapsed += 0.25
        }
        return used.sorted()
    }

    private func assertWithinBudget(_ used: [Date], file: StaticString = #filePath, line: UInt = #line) {
        let config = RadarSchedulerConfig.standard
        for (index, at) in used.enumerated() {
            let lastMinute = used.filter { $0 <= at && at.timeIntervalSince($0) < 60 }.count
            XCTAssertLessThanOrEqual(lastMinute, config.perMinute, "more than 24 in a minute at \(at.timeIntervalSince(t0)) s", file: file, line: line)
            let lastTen = used.filter { $0 <= at && at.timeIntervalSince($0) < config.burstWindow }.count
            XCTAssertLessThanOrEqual(lastTen, config.burst, "more than 4 in 10 s at \(at.timeIntervalSince(t0)) s", file: file, line: line)
            if index > 0 {
                XCTAssertGreaterThanOrEqual(at.timeIntervalSince(used[index - 1]), config.minGap - 0.001, "two within a second", file: file, line: line)
            }
        }
    }

    func testSwitchingTheLayerOnAndOffNeverExceedsTheBudget() {
        // The chip tapped every 0.75 s for ten minutes: the view jumps between the country and Vienna, each time with new tiles
        // that were never asked (the settle delay starts again) and requests still on their way.
        var scheduler = RadarScheduler()
        scheduler.setViewport(vienna, latitudeSpan: 0.22, now: t0)
        var on = false
        var lastToggle = t0
        let used = drive(&scheduler, seconds: 600) { scheduler, now, _, _ in
            if now.timeIntervalSince(lastToggle) >= 0.75 {
                on.toggle()
                lastToggle = now
                if on {
                    scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: self.heatSpan, now: now)
                } else {
                    scheduler.setViewport(self.vienna, latitudeSpan: 0.22, now: now)
                }
            }
            return true
        }
        assertWithinBudget(used)
        XCTAssertLessThanOrEqual(used.count, 240, "ten minutes, 24 a minute at the most")
    }

    func testGoingToTheBackgroundAndBackNeverExceedsTheBudget() {
        // Every 4 s the app leaves (the loop is cancelled: every request on its way reports `recordCancelled`) and comes back 2 s
        // later. A cancelled request may have reached the server: its slot stays used, only the tile is due again.
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: heatSpan, now: t0)
        var cycleStart = t0
        var wasRunning = true
        let used = drive(&scheduler, seconds: 600, latency: 3) { scheduler, now, flights, _ in
            let phase = now.timeIntervalSince(cycleStart)
            if phase >= 4 { cycleStart = now }
            let running = now.timeIntervalSince(cycleStart) < 2
            if wasRunning && !running {
                for flight in flights { scheduler.recordCancelled(flight.tile) }
                flights.removeAll()
                XCTAssertEqual(scheduler.inFlightCount(now: now), 0, "a cancelled request frees its tile")
            }
            wasRunning = running
            return running
        }
        assertWithinBudget(used)
        XCTAssertGreaterThan(used.count, 20, "the radar keeps loading between the interruptions")
    }

    func testTheZeitreiseAndTheLayerShareOneBudget() {
        // The Zeitreise's snapshots (`claimSlot`, here one wished every 2 s, more than its plan ever asks) and the layer's tiles in
        // one run: together they never pass the radar's budget. (In the app the live loop pauses while the Zeitreise is away from
        // now, so they rarely meet at all; the budget does not rely on that.)
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: heatSpan, now: t0)
        var lastWish = t0.addingTimeInterval(-1)
        var claimed = 0
        let used = drive(&scheduler, seconds: 600) { scheduler, now, _, used in
            if now.timeIntervalSince(lastWish) >= 2 {
                lastWish = now
                if scheduler.claimSlot(now: now) == nil {
                    used.append(now)
                    claimed += 1
                }
            }
            return true
        }
        assertWithinBudget(used)
        XCTAssertGreaterThan(claimed, 0, "the Zeitreise got slots")
        XCTAssertGreaterThan(used.count - claimed, 0, "and so did the layer's tiles")
    }

    func testTappingRefreshAgainAndAgainNeverExceedsTheBudget() {
        // "Jetzt aktualisieren" (Low Power Mode) or "Erneut versuchen" tapped twice a second: every visible tile is due at once each
        // time, and still the budget holds.
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: heatSpan, now: t0)
        var lastTap = t0
        let used = drive(&scheduler, seconds: 600, latency: 1) { scheduler, now, _, _ in
            if now.timeIntervalSince(lastTap) >= 0.5 {
                scheduler.refreshAll()
                lastTap = now
            }
            return true
        }
        assertWithinBudget(used)
    }

    func testAnAnswerOlderThanItsRetentionIsStaleUntilTheNextOne() throws {
        // Back from the background after five minutes: both tiles have an answer, but their trains left the store after 60 s
        // (2.5 × 20 s, at least `RadarTiling.frameRetention`). The status says so, and each tile is asked once, at once.
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: heatSpan, now: t0)
        let tiles = scheduler.visibleTiles()
        XCTAssertEqual(tiles.count, 2)
        for tile in tiles { scheduler.recordAnswer(tile, count: 450, at: t0) }
        XCTAssertEqual(scheduler.status(now: t0.addingTimeInterval(59)).staleTiles, 0)
        XCTAssertEqual(scheduler.retention(for: tiles[0]), RadarTiling.frameRetention)

        let back = t0.addingTimeInterval(300)
        var status = scheduler.status(now: back)
        XCTAssertEqual(status.answeredTiles, 2)
        XCTAssertEqual(status.staleTiles, 2, "their trains are gone: the numbers must not pass for the country")
        XCTAssertEqual(status.pendingTiles, 0, "an old answer is not a tile still loading: hence a count of its own")

        guard case .request(let first) = scheduler.next(now: back) else { return XCTFail("an overdue tile is asked at once") }
        guard case .wait = scheduler.next(now: back) else { return XCTFail("the second one waits for the spacing") }
        guard case .request(let second) = scheduler.next(now: back.addingTimeInterval(1)) else { return XCTFail("then the second tile") }
        XCTAssertNotEqual(first, second)
        scheduler.recordAnswer(first, count: 450, at: back)
        status = scheduler.status(now: back.addingTimeInterval(3))
        XCTAssertEqual(status.staleTiles, 1, "half the country is fresh, the other half still too old")
        scheduler.recordAnswer(second, count: 450, at: back.addingTimeInterval(1))
        XCTAssertEqual(scheduler.status(now: back.addingTimeInterval(5)).staleTiles, 0)
        guard case .wait = scheduler.next(now: back.addingTimeInterval(5)) else { return XCTFail("nothing is replayed: each tile once") }
    }

    func testAFailedTileIsAFailureNotAnOldAnswer() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: heatSpan, now: t0)
        let tiles = scheduler.visibleTiles()
        scheduler.recordAnswer(tiles[0], count: 450, at: t0)
        scheduler.recordFailure(tiles[0], error: LiveError.timeout, at: t0.addingTimeInterval(20))
        let status = scheduler.status(now: t0.addingTimeInterval(200))
        XCTAssertEqual(status.failedTiles, 1)
        XCTAssertEqual(status.staleTiles, 0)
    }
}
