import XCTest
@testable import KlimaCore

// MARK: radar2-fix-radarmodes – a lane that starts over (`reset(lane:)`, a mode chip changed) while a tile's request is on its way: the tile is never
// asked a second time before that request is back, `maxInFlight` holds across the reset, and the dropped outcome frees the tile at once.
final class RadarSchedulerInFlightResetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    private let wien = RadarBox(north: 48.30, west: 16.20, south: 48.12, east: 16.55)

    private func cityScheduler() -> RadarScheduler {
        var scheduler = RadarScheduler()
        scheduler.setViewport(wien, latitudeSpan: 0.18, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: 0.18, now: t0)
        return scheduler
    }

    /// Steps the clock until `next` sends a request of `lane`; nothing is answered on the way.
    private func firstRequest(_ scheduler: inout RadarScheduler, lane: RadarLane, from start: TimeInterval,
                              sent: inout [RadarTileKey]) -> (RadarTileKey, TimeInterval)? {
        var elapsed = start
        while elapsed < start + 60 {
            if case .request(let tile) = scheduler.next(now: t0.addingTimeInterval(elapsed)) {
                sent.append(tile)
                if tile.lane == lane { return (tile, elapsed) }
            }
            elapsed += 0.25
        }
        return nil
    }

    func testATileOnItsWayIsNotAskedAgainAfterItsLaneStartedOver() {
        var scheduler = cityScheduler()
        var sent: [RadarTileKey] = []
        guard let (tile, at) = firstRequest(&scheduler, lane: .city, from: 1, sent: &sent) else { return XCTFail("no city request") }
        for other in sent where other != tile { scheduler.recordAnswer(other, count: 10, at: t0.addingTimeInterval(at)) }
        scheduler.reset(lane: .city)   // a city chip changed while the request is on its way
        XCTAssertEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(at)), 1, "the request still counts")

        // Two minutes of the loop, every other request answered at once: the tile is never asked while its old request is out.
        var elapsed = at + 0.25
        while elapsed < at + 120 {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let next) = scheduler.next(now: now) {
                XCTAssertNotEqual(next, tile, "a second request for the same tile at \(elapsed - at) s")
                scheduler.recordAnswer(next, count: 10, at: now)
            }
            XCTAssertLessThanOrEqual(scheduler.inFlightCount(now: now), scheduler.config.maxInFlight)
            elapsed += 0.25
        }

        // The old answer comes back and is dropped: the tile is free and asked for the new modes at the next free slot.
        scheduler.recordDropped(tile)
        XCTAssertEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(elapsed)), 0)
        var askedAgain = false
        let back = elapsed
        while elapsed < back + 30, !askedAgain {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let next) = scheduler.next(now: now) {
                if next == tile { askedAgain = true } else { scheduler.recordAnswer(next, count: 10, at: now) }
            }
            elapsed += 0.25
        }
        XCTAssertTrue(askedAgain, "never asked for the new modes: it comes first, as a tile never asked")
        XCTAssertLessThan(elapsed - back, 10)
    }

    func testTheCapOfThreeRequestsOnTheirWayHoldsAcrossAReset() {
        var scheduler = cityScheduler()
        var sent: [RadarTileKey] = []
        var elapsed = 1.0
        while sent.count < 3, elapsed < 30 {
            if case .request(let tile) = scheduler.next(now: t0.addingTimeInterval(elapsed)) { sent.append(tile) }
            elapsed += 0.25
        }
        XCTAssertEqual(sent.count, 3)
        scheduler.reset(lane: .city)
        scheduler.reset(lane: .wide)
        XCTAssertEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(elapsed)), 3)
        if case .request = scheduler.next(now: t0.addingTimeInterval(elapsed + 5)) {
            XCTFail("a fourth request while three are on their way")
        }
        // One comes back (dropped), one is cancelled: two slots are free, and the status counts them as still to come.
        scheduler.recordDropped(sent[0])
        scheduler.recordCancelled(sent[1])
        XCTAssertEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(elapsed + 5)), 1)
        XCTAssertNil(scheduler.states[sent[1]], "cancelled before it answered: never asked for the new modes")
    }

    func testADroppedOutcomeDoesNotFreeANewerRequestForTheTile() {
        var scheduler = cityScheduler()
        var sent: [RadarTileKey] = []
        guard let (tile, at) = firstRequest(&scheduler, lane: .city, from: 1, sent: &sent) else { return XCTFail("no city request") }
        scheduler.reset(lane: .city)
        // The old request never reports back (a bug): after `requestTimeout` the tile is asked again, and the late old outcome changes nothing.
        let late = at + scheduler.config.requestTimeout + 1
        for other in sent where other != tile { scheduler.recordAnswer(other, count: 10, at: t0.addingTimeInterval(at)) }
        var elapsed = late
        var reasked = false
        while elapsed < late + 150, !reasked {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let next) = scheduler.next(now: now) {
                if next == tile { reasked = true } else { scheduler.recordAnswer(next, count: 10, at: now) }
            }
            elapsed += 0.25
        }
        XCTAssertTrue(reasked)
        scheduler.recordDropped(tile)
        XCTAssertEqual(scheduler.states[tile]?.isInFlight, true, "the newer request is still on its way")
    }

    func testResetWithoutALaneKeepsARequestOnItsWayToo() {
        var scheduler = cityScheduler()
        var sent: [RadarTileKey] = []
        guard let (tile, at) = firstRequest(&scheduler, lane: .wide, from: 1, sent: &sent) else { return XCTFail("no wide request") }
        scheduler.reset()
        XCTAssertEqual(scheduler.states[tile]?.isInFlight, true)
        XCTAssertGreaterThanOrEqual(scheduler.inFlightCount(now: t0.addingTimeInterval(at)), 1)
        scheduler.recordDropped(tile)
        XCTAssertNil(scheduler.states[tile])
    }
}
