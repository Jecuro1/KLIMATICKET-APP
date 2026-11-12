import XCTest
@testable import KlimaCore

/// The load of the Pünktlichkeit layer (docs/RADAR_HEATMAP.md §1): while it is on the scheduler's view is all of Austria, which is two
/// tiles asked every 20 s, six requests a minute, well inside the radar's budget of 24. No second loop, no viewport dependence.
final class HeatLoadTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    /// What `RadarModel.heatSpan` hands the scheduler: the height of the radar's coverage.
    private let span = RadarTileGrid.coverage.north - RadarTileGrid.coverage.south

    private func simulate(_ scheduler: inout RadarScheduler, seconds: TimeInterval, count: Int,
                          before: (inout RadarScheduler, Date) -> Void = { _, _ in }) -> [Date] {
        var sent: [Date] = []
        var elapsed = 0.0
        while elapsed <= seconds {
            let now = t0.addingTimeInterval(elapsed)
            before(&scheduler, now)
            if case .request(let tile) = scheduler.next(now: now) {
                sent.append(now)
                scheduler.recordAnswer(tile, count: count, at: now)
            }
            elapsed += 0.25
        }
        return sent
    }

    func testTheCountryViewIsTwoLevelZeroTiles() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: span, now: t0)
        let tiles = scheduler.visibleTiles()
        XCTAssertEqual(tiles, [RadarTileKey(level: 0, row: 0, col: 0), RadarTileKey(level: 0, row: 0, col: 1)])
        XCTAssertTrue(tiles.allSatisfy { scheduler.interval(for: $0) == 20 }, "a view of 2.8° counts as zoomed in: every tile every 20 s, quiet or not")
        XCTAssertEqual(scheduler.status(now: t0).coversCountry, true)
    }

    func testSixRequestsAMinuteInsideTheRadarsBudget() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: span, now: t0)
        // The measured answers: about 500 and 400 vehicles, far from the cap of 1000.
        let sent = simulate(&scheduler, seconds: 600, count: 450)
        XCTAssertTrue((58...62).contains(sent.count), "two tiles, every 20 s, for ten minutes: about 60, got \(sent.count)")
        let perMinute = sent.indices.map { index in sent.filter { $0 <= sent[index] && sent[index].timeIntervalSince($0) < 60 }.count }.max() ?? 0
        XCTAssertLessThanOrEqual(perMinute, 7, "6 a minute (7 at the edge of a window), against a budget of \(RadarSchedulerConfig.standard.perMinute)")
        XCTAssertLessThan(perMinute, RadarSchedulerConfig.standard.perMinute)
        XCTAssertFalse(scheduler.status(now: t0.addingTimeInterval(600)).budgetLimited, "the layer never stretches the refresh")
    }

    func testTheMapDoesNotMoveTheRequests() {
        // The model re-applies the same viewport on every camera change (`RadarModel.applyViewport`): that must not reset the
        // tiles' settle delay or their timing. Re-applied every quarter second, the requests are those of a view that never moved.
        var still = RadarScheduler()
        still.setViewport(RadarTileGrid.coverage, latitudeSpan: span, now: t0)
        let reference = simulate(&still, seconds: 300, count: 450)
        var moving = RadarScheduler()
        moving.setViewport(RadarTileGrid.coverage, latitudeSpan: span, now: t0)
        let sent = simulate(&moving, seconds: 300, count: 450) { scheduler, now in
            scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: self.span, now: now)
        }
        XCTAssertEqual(sent, reference)
    }

    func testAnAnswerAtTheCapStillSplitsAsBefore() {
        var scheduler = RadarScheduler()
        scheduler.setViewport(RadarTileGrid.coverage, latitudeSpan: span, now: t0)
        scheduler.recordAnswer(RadarTileKey(level: 0, row: 0, col: 0), count: RadarTiling.requestCap, at: t0)
        XCTAssertEqual(scheduler.visibleTiles().count, 5, "a cut-off tile is replaced by its four children: the layer inherits the splitting")
    }
}
