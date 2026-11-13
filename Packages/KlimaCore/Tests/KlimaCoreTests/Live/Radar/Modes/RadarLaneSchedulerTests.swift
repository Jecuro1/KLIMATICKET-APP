import XCTest
@testable import KlimaCore

// MARK: radarmodes – the scheduler with two lanes (docs/RADAR_MODES.md §3, §4): the wide lane as before, the city lane only when zoomed in, one
// budget for both, the 16-tile cap, per-lane reset and status. Pure: the tests move the clock themselves.
final class RadarLaneSchedulerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    /// A Wien view of about 20 × 26 km: wide level 3, city level 4.
    private let wien = RadarBox(north: 48.30, west: 16.20, south: 48.12, east: 16.55)
    private let wienSpan = 0.18

    private struct Sent { var at: Date; var tile: RadarTileKey? }

    /// Runs the scheduler for `seconds`; every request is answered `delay` seconds later with `answer(tile)` vehicles. `claimEvery`: one
    /// `claimSlot` (a side job) that often, taken at the first free moment. Returns every send (tile requests and claimed slots).
    private func simulate(_ scheduler: inout RadarScheduler, from start: Date, seconds: TimeInterval, step: TimeInterval = 0.25,
                          delay: TimeInterval = 0, claimEvery: TimeInterval? = nil, answer: (RadarTileKey) -> Int) -> [Sent] {
        var sent: [Sent] = []
        var pending: [(due: Date, tile: RadarTileKey)] = []
        var nextClaim = claimEvery.map { start.addingTimeInterval($0) }
        var elapsed = 0.0
        while elapsed <= seconds {
            let now = start.addingTimeInterval(elapsed)
            for item in pending where item.due <= now {
                scheduler.recordAnswer(item.tile, count: answer(item.tile), at: item.due)
            }
            pending.removeAll { $0.due <= now }
            if let claim = nextClaim, claim <= now, scheduler.claimSlot(now: now) == nil {
                sent.append(Sent(at: now, tile: nil))
                nextClaim = claim.addingTimeInterval(claimEvery ?? 60)
            }
            if case .request(let tile) = scheduler.next(now: now) {
                sent.append(Sent(at: now, tile: tile))
                if delay <= 0 {
                    scheduler.recordAnswer(tile, count: answer(tile), at: now)
                } else {
                    pending.append((now.addingTimeInterval(delay), tile))
                }
            }
            elapsed += step
        }
        return sent
    }

    private func maxInWindow(_ sent: [Sent], _ window: TimeInterval) -> Int {
        sent.indices.map { i in sent.filter { $0.at <= sent[i].at && sent[i].at.timeIntervalSince($0.at) < window }.count }.max() ?? 0
    }

    private func smallestGap(_ sent: [Sent]) -> TimeInterval {
        zip(sent.dropFirst(), sent).map { $0.at.timeIntervalSince($1.at) }.min() ?? .infinity
    }

    private func cityScheduler(_ config: RadarSchedulerConfig = .standard) -> RadarScheduler {
        var scheduler = RadarScheduler(config: config)
        scheduler.setViewport(wien, latitudeSpan: wienSpan, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: wienSpan, now: t0)
        return scheduler
    }

    // (a)
    func testTheWideLaneIsUnchangedWhileTheCityLaneHasNoTiles() {
        let views: [(RadarBox, Double)] = [(.austria, 4.2), (wien, wienSpan), (RadarBox(north: 47.6, west: 12.6, south: 47.1, east: 13.1), 0.5)]
        for (box, span) in views {
            var plain = RadarScheduler()
            plain.setViewport(box, latitudeSpan: span, now: t0)
            var off = RadarScheduler()
            off.setViewport(box, latitudeSpan: span, now: t0)
            off.setCityViewport(nil, latitudeSpan: span, now: t0)
            var outOfZoom = RadarScheduler()
            outOfZoom.setViewport(box, latitudeSpan: span, now: t0)
            outOfZoom.setCityViewport(box, latitudeSpan: 0.61, now: t0)
            let answer: (RadarTileKey) -> Int = { $0.level < 3 ? 1000 : 300 }
            let a = simulate(&plain, from: t0, seconds: 300, answer: answer)
            let b = simulate(&off, from: t0, seconds: 300, answer: answer)
            let c = simulate(&outOfZoom, from: t0, seconds: 300, answer: answer)
            XCTAssertFalse(a.isEmpty)
            XCTAssertEqual(a.map(\.at), b.map(\.at))
            XCTAssertEqual(a.map(\.tile), b.map(\.tile))
            XCTAssertEqual(a.map(\.at), c.map(\.at))
            XCTAssertEqual(a.map(\.tile), c.map(\.tile))
            var statusC = outOfZoom.status(now: t0.addingTimeInterval(300))
            XCTAssertTrue(statusC.city.outOfZoom)
            statusC.city = RadarLaneStatus()
            XCTAssertEqual(plain.status(now: t0.addingTimeInterval(300)), statusC)
        }
    }

    // (b)
    func testNoCityTileWithoutAViewOrAboveTheSpanLimit() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(wien, latitudeSpan: wienSpan, now: t0)
        XCTAssertTrue(scheduler.cityTiles().tiles.isEmpty)
        XCTAssertFalse(scheduler.status(now: t0).city.isActive)
        XCTAssertFalse(scheduler.status(now: t0).city.outOfZoom)
        scheduler.setCityViewport(wien, latitudeSpan: 0.61, now: t0)
        XCTAssertTrue(scheduler.cityTiles().tiles.isEmpty)
        XCTAssertTrue(scheduler.visibleTiles().allSatisfy { $0.lane == .wide })
        XCTAssertTrue(scheduler.status(now: t0).city.isActive)
        XCTAssertTrue(scheduler.status(now: t0).city.outOfZoom)
        scheduler.setCityViewport(wien, latitudeSpan: 0.6, now: t0)
        XCTAssertFalse(scheduler.cityTiles().tiles.isEmpty)
        XCTAssertFalse(scheduler.status(now: t0).city.outOfZoom)
        XCTAssertTrue(scheduler.cityTiles().tiles.allSatisfy { $0.lane == .city && $0.level == RadarTileGrid.cityLevel(forLatitudeSpan: 0.6) })
    }

    // (c)
    func testACappedCityTileSplitsDownToLevelEightAndThenCountsAsCapped() {
        var scheduler = RadarScheduler()
        let small = RadarBox(north: 48.212, west: 16.366, south: 48.205, east: 16.378)   // inside one level-6 tile
        scheduler.setCityViewport(small, latitudeSpan: 0.05, now: t0)
        XCTAssertEqual(scheduler.cityTiles().tiles.first?.level, 6)
        simulate(&scheduler, from: t0, seconds: 120) { _ in 1000 }
        let tiles = scheduler.cityTiles().tiles
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertTrue(tiles.allSatisfy { $0.level == 8 }, "split down to the finest city level: \(tiles.map(\.label))")
        let status = scheduler.status(now: t0.addingTimeInterval(120))
        XCTAssertEqual(status.city.cappedTiles, tiles.count)
        XCTAssertEqual(status.city.crowdedTiles, 0)
        XCTAssertEqual(status.cappedTiles, 0, "the wide lane has no view here")
    }

    // (d)
    func testASplitThatWouldPassSixteenTilesLeavesTheParentAndCountsAsCrowded() {
        var scheduler = cityScheduler()
        XCTAssertLessThanOrEqual(scheduler.cityTiles().tiles.count, 16)
        simulate(&scheduler, from: t0, seconds: 600) { $0.lane == .city ? 1000 : 200 }
        let city = scheduler.cityTiles()
        XCTAssertEqual(city.tiles.count, 16, "the cap holds: \(city.tiles.count)")
        XCTAssertGreaterThanOrEqual(city.crowded, 1)
        let status = scheduler.status(now: t0.addingTimeInterval(600))
        XCTAssertEqual(status.city.visibleTiles, 16)
        XCTAssertEqual(status.city.crowdedTiles, city.crowded)
        XCTAssertEqual(Set(city.tiles).count, 16, "no tile twice")
    }

    func testMoreBaseTilesThanTheCapKeepTheNearestAndSaySo() {
        var scheduler = RadarScheduler()
        scheduler.cityMaxTiles = 4
        scheduler.setCityViewport(wien, latitudeSpan: 0.12, now: t0)   // level 5: more than four tiles
        let city = scheduler.cityTiles()
        XCTAssertEqual(city.tiles.count, 4)
        XCTAssertGreaterThan(city.crowded, 0)
    }

    // (e)
    func testResettingTheCityLaneKeepsTheWideLane() {
        var scheduler = cityScheduler()
        simulate(&scheduler, from: t0, seconds: 30) { _ in 100 }
        let before = scheduler.status(now: t0.addingTimeInterval(30))
        XCTAssertGreaterThan(before.answeredTiles, 0)
        XCTAssertGreaterThan(before.city.answeredTiles, 0)
        scheduler.reset(lane: .city)
        let after = scheduler.status(now: t0.addingTimeInterval(30))
        XCTAssertEqual(after.answeredTiles, before.answeredTiles, "wide states kept")
        XCTAssertEqual(after.city.answeredTiles, 0)
        XCTAssertEqual(after.city.pendingTiles, after.city.visibleTiles)
        scheduler.reset(lane: .wide)
        XCTAssertEqual(scheduler.status(now: t0.addingTimeInterval(30)).answeredTiles, 0)
    }

    func testResettingALaneKeepsARateLimitPause() {
        var scheduler = cityScheduler()
        scheduler.recordFailure(RadarTileKey(level: 3, row: 3, col: 3), error: LiveError.rateLimited(.oebbHafas, retryAfter: 30), at: t0)
        scheduler.reset(lane: .city)
        XCTAssertEqual(scheduler.next(now: t0.addingTimeInterval(5)), .wait(until: t0.addingTimeInterval(30)))
    }

    // (f)
    func testTheCityIntervalIsTwentyOrSixtySeconds() {
        var scheduler = cityScheduler()
        let city = scheduler.cityTiles().tiles[0]
        let wide = scheduler.wideTiles()[0]
        XCTAssertEqual(scheduler.interval(for: city), 20)
        scheduler.setCityInterval(60)
        XCTAssertEqual(scheduler.interval(for: city), 60)
        XCTAssertEqual(scheduler.interval(for: wide), 20, "the wide lane keeps its own (zoomed in: 20 s)")
        scheduler.setCityInterval(0)
        XCTAssertEqual(scheduler.interval(for: city), 60, "a nonsense interval is ignored")
        // Every 60 s: a city tile is asked again a minute later, not after 20 s (a budget wide enough to ask every tile at once).
        var fast = cityScheduler(.syntheticCityDemo)
        fast.setCityInterval(60)
        let first = simulate(&fast, from: t0, seconds: 10) { _ in 10 }
        let asked = Set(first.compactMap(\.tile).filter { $0.lane == .city })
        XCTAssertEqual(asked, Set(fast.cityTiles().tiles))
        let soon = simulate(&fast, from: t0.addingTimeInterval(10.25), seconds: 45) { _ in 10 }
        XCTAssertTrue(soon.allSatisfy { $0.tile?.lane != .city }, "no city tile before 60 s")
        XCTAssertTrue(soon.contains { $0.tile?.lane == .wide }, "the wide tiles keep their 20 s")
        let later = simulate(&fast, from: t0.addingTimeInterval(55.5), seconds: 10) { _ in 10 }
        XCTAssertEqual(Set(later.compactMap(\.tile).filter { $0.lane == .city }), asked, "and all of them after a minute")
    }

    // (g)
    func testBothLanesAndASideJobStayWithinTheBudgetForTenMinutes() {
        var scheduler = cityScheduler()
        let sent = simulate(&scheduler, from: t0, seconds: 600, delay: 3, claimEvery: 60) { $0.lane == .city ? 1000 : 300 }
        let status = scheduler.status(now: t0.addingTimeInterval(600))
        XCTAssertEqual(status.city.visibleTiles, 16, "the Wien view runs with 16 city tiles")
        XCTAssertGreaterThanOrEqual(status.visibleTiles, 1)
        XCTAssertLessThanOrEqual(maxInWindow(sent, 60), 24)
        XCTAssertLessThanOrEqual(maxInWindow(sent, 10), 4)
        XCTAssertGreaterThanOrEqual(smallestGap(sent), 1 - 1e-9)
        XCTAssertGreaterThanOrEqual(40 - maxInWindow(sent, 60), 16, "at least 16 of the app's 40 stay for planner, boards, follow")
        XCTAssertGreaterThanOrEqual(sent.filter { $0.tile == nil }.count, 9, "the side job got its slot every minute")
        XCTAssertTrue(sent.contains { $0.tile?.lane == .wide }, "the wide lane is not starved")
        XCTAssertGreaterThan(sent.filter { $0.tile?.lane == .city }.count, 50)
    }

    // (h)
    func testThePunctualityLayerAndTheCityLaneShareTheSame24() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: 2.8, now: t0)   // the layer: all of Austria
        scheduler.setCityViewport(wien, latitudeSpan: wienSpan, now: t0)
        let sent = simulate(&scheduler, from: t0, seconds: 600, delay: 2) { $0.lane == .city ? 600 : 900 }
        XCTAssertLessThanOrEqual(maxInWindow(sent, 60), 24)
        XCTAssertLessThanOrEqual(maxInWindow(sent, 10), 4)
        XCTAssertGreaterThanOrEqual(smallestGap(sent), 1 - 1e-9)
        let austria = sent.filter { $0.tile?.lane == .wide }
        XCTAssertTrue(austria.allSatisfy { $0.tile?.level == 0 }, "the layer's two Austria tiles")
        XCTAssertGreaterThanOrEqual(austria.count, 20, "both Austria tiles keep coming")
    }

    // (i)
    func testCityTilesStretchTheWideLaneAndTheStatusSaysSo() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarBox(north: 48.35, west: 16.0, south: 47.95, east: 16.8), latitudeSpan: 0.4, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: wienSpan, now: t0)
        simulate(&scheduler, from: t0, seconds: 900) { $0.lane == .city ? 1000 : 500 }
        let status = scheduler.status(now: t0.addingTimeInterval(900))
        XCTAssertEqual(status.city.visibleTiles, 16)
        let total = status.visibleTiles + status.city.visibleTiles
        XCTAssertTrue(status.budgetLimited)
        XCTAssertEqual(status.period, 20 * Double(total) / 8, accuracy: 0.001, "every tile at 20 s, 24 a minute for \(total) tiles")
        XCTAssertEqual(status.city.period, status.period, accuracy: 0.001, "one stretch for both lanes")
        XCTAssertGreaterThan(status.period, 25)
        XCTAssertTrue(RadarStatusText.notes(status, rail: false).contains { $0.contains("aktualisiert alle ~") })
        // Without the city lane the same wide view needs no note.
        var plain = RadarScheduler()
        plain.setViewport(RadarBox(north: 48.35, west: 16.0, south: 47.95, east: 16.8), latitudeSpan: 0.4, now: t0)
        simulate(&plain, from: t0, seconds: 120) { _ in 500 }
        XCTAssertFalse(plain.status(now: t0.addingTimeInterval(120)).budgetLimited)
    }

    func testSixteenCityAndFourWideTilesTakeAboutFiftySeconds() {
        // The figure of docs/RADAR_MODES.md §4: 20 tiles at 20 s want 60 a minute; 24 are allowed: stretch 2.5, every tile about 50 s.
        var scheduler = RadarScheduler()
        let fourWide = RadarBox(north: 48.55, west: 16.0, south: 48.05, east: 16.6)   // crosses a row and a column of level 2
        scheduler.setViewport(fourWide, latitudeSpan: 0.5, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: wienSpan, now: t0)
        simulate(&scheduler, from: t0, seconds: 900) { $0.lane == .city ? 1000 : 400 }
        let status = scheduler.status(now: t0.addingTimeInterval(900))
        XCTAssertEqual(status.visibleTiles, 4)
        XCTAssertEqual(status.city.visibleTiles, 16)
        XCTAssertEqual(status.period, 50, accuracy: 0.001)
        XCTAssertEqual(status.city.period, 50, accuracy: 0.001)
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).contains("Dieser Ausschnitt · aktualisiert alle ~50 s"))
    }

    // (j)
    func testOnlyCityModesAskNoWideTileAndSayNothingAboutTheCoverage() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(wien, latitudeSpan: wienSpan, now: t0)
        scheduler.clearViewport()   // only Bus, Bim or U-Bahn on, Pünktlichkeit off
        scheduler.setCityViewport(wien, latitudeSpan: wienSpan, now: t0)
        let sent = simulate(&scheduler, from: t0, seconds: 120) { _ in 50 }
        XCTAssertTrue(sent.allSatisfy { $0.tile?.lane == .city })
        let status = scheduler.status(now: t0.addingTimeInterval(120))
        XCTAssertEqual(status.visibleTiles, 0)
        XCTAssertFalse(status.outsideCoverage)
        XCTAssertFalse(RadarStatusText.notes(status, rail: false).contains { $0.contains("Außerhalb") })
        XCTAssertTrue(status.anyAnswered)
        XCTAssertNotNil(status.oldestAnswerAgeOfBothLanes)
    }

    // (k)
    func testAPendingCityTileLeavesTheWideStatusAlone() {
        var plain = RadarScheduler()
        plain.setViewport(.austria, latitudeSpan: 4.2, now: t0)
        var both = RadarScheduler()
        both.setViewport(.austria, latitudeSpan: 4.2, now: t0)
        let small = RadarBox(north: 48.212, west: 16.366, south: 48.205, east: 16.378)
        both.setCityViewport(small, latitudeSpan: 0.05, now: t0)
        // Answer the wide tiles only: the city tile stays pending.
        simulate(&plain, from: t0, seconds: 30) { _ in 400 }
        var answered: [RadarTileKey] = []
        var elapsed = 0.0
        while elapsed <= 30 {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let tile) = both.next(now: now) {
                if tile.lane == .wide { both.recordAnswer(tile, count: 400, at: now); answered.append(tile) }
            }
            elapsed += 0.25
        }
        var status = both.status(now: t0.addingTimeInterval(30))
        XCTAssertGreaterThan(status.city.visibleTiles, 0)
        XCTAssertEqual(status.city.answeredTiles, 0)
        XCTAssertTrue(status.anyPending)
        status.city = RadarLaneStatus()
        let reference = plain.status(now: t0.addingTimeInterval(30))
        XCTAssertEqual(status.answeredTiles, reference.answeredTiles)
        XCTAssertEqual(status.pendingTiles, 0, "the Pünktlichkeit's completeness check reads the wide lane only")
        XCTAssertEqual(status.coversCountry, reference.coversCountry)
        XCTAssertEqual(status.isPaused, reference.isPaused)
        XCTAssertEqual(status.cappedTiles, reference.cappedTiles)
    }

    // (l)
    func testAWideAnswerIsRecordedAfterTheCityLaneWasReset() {
        var scheduler = cityScheduler()
        var wideTile: RadarTileKey?
        var elapsed = 1.0
        while wideTile == nil, elapsed < 30 {
            if case .request(let tile) = scheduler.next(now: t0.addingTimeInterval(elapsed)), tile.lane == .wide { wideTile = tile }
            elapsed += 0.25
        }
        guard let wideTile else { return XCTFail("no wide request") }
        XCTAssertGreaterThan(scheduler.inFlightCount(now: t0.addingTimeInterval(elapsed)), 0)
        scheduler.reset(lane: .city)   // a city mode changed while the wide request is on its way
        scheduler.recordAnswer(wideTile, count: 50, at: t0.addingTimeInterval(elapsed))
        XCTAssertEqual(scheduler.states[wideTile]?.isInFlight, false, "the wide tile is free again at once")
        XCTAssertNotNil(scheduler.states[wideTile]?.lastAnswerAt)
        XCTAssertEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(elapsed)), 0)
    }

    func testCombinedPauseCountsOnlyLanesWithTiles() {
        var status = RadarStatus()
        XCTAssertFalse(status.isPausedOnBothLanes)
        status.city.visibleTiles = 3
        status.city.isPaused = true
        XCTAssertTrue(status.isPausedOnBothLanes, "only the city lane has tiles, and it is paused")
        status.visibleTiles = 2
        XCTAssertFalse(status.isPausedOnBothLanes, "the wide lane still answers")
        status.isPaused = true
        XCTAssertTrue(status.isPausedOnBothLanes)
        status.oldestAnswerAge = 12
        status.city.oldestAnswerAge = 40
        XCTAssertEqual(status.oldestAnswerAgeOfBothLanes, 40)
    }
}
