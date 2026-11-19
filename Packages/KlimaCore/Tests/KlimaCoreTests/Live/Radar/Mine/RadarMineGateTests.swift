import XCTest
@testable import KlimaCore

/// When „Wo bleibt mein Bus?“ asks (docs/RADAR_MINE.md §4, docs/OEBB_LIVE.md §R11.5): only inside the running live loop with the train layer on and
/// the page open, never in Low Power Mode; the cadence of its side job; and that with the side job running the radar stays within 24 a minute and
/// leaves at least 16 of the app's 40.
final class RadarMineGateTests: XCTestCase {
    private let t0 = MineFixture.t0

    // MARK: The gate in every state

    func testTheStopPanelAsksOnlyWhereTheLiveLoopRunsWithTrainsOnAndNeverInLowPower() {
        let layerSets: [Set<MapLayer>] = [[], [.trains], [.punctuality], [.trains, .punctuality], [.stations, .trains]]
        let accesses: [RadarFeatureGate.Access] = [.open, .offline, .closed]
        var asked = 0
        for layers in layerSets {
            for access in accesses {
                for railOnly in [true, false] {
                    for scene in [true, false] {
                        for cockpit in [true, false] {
                            for timeOpen in [true, false] {
                                for timeAway in [true, false] {
                                    let gate = RadarFeatureGate(layers: MapLayerSelection(layers: layers), access: access, railOnly: railOnly,
                                                                sceneActive: scene, cockpitOpen: cockpit, timeOpen: timeOpen, timeAway: timeAway)
                                    for open in [true, false] {
                                        for lowPower in [true, false] {
                                            let asks = gate.stopPanelAsks(isOpen: open, lowPower: lowPower)
                                            let label = "\(layers) \(access) rail:\(railOnly) scene:\(scene) cockpit:\(cockpit) time:\(timeOpen)/\(timeAway) open:\(open) lp:\(lowPower)"
                                            if !gate.liveLoopRuns { XCTAssertFalse(asks, label) }
                                            if !gate.trainsOn { XCTAssertFalse(asks, "only the Pünktlichkeit or nothing on: \(label)") }
                                            if lowPower || !open { XCTAssertFalse(asks, label) }
                                            XCTAssertEqual(asks, gate.liveLoopRuns && gate.trainsOn && open && !lowPower, label)
                                            // The pause reason is nil exactly while it asks.
                                            XCTAssertEqual(gate.stopPanelPause(isOpen: open, lowPower: lowPower) == nil, asks, label)
                                            if asks { asked += 1 }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(asked, 0)
    }

    func testThePauseNamesTheReason() {
        let on = MapLayerSelection(layers: [.trains])
        XCTAssertNil(RadarFeatureGate(layers: on).stopPanelPause(isOpen: true, lowPower: false))
        XCTAssertEqual(RadarFeatureGate(layers: on, access: .closed).stopPanelPause(isOpen: true, lowPower: false), .accessClosed)
        XCTAssertEqual(RadarFeatureGate(layers: on, access: .offline).stopPanelPause(isOpen: true, lowPower: false), .offline)
        XCTAssertEqual(RadarFeatureGate(layers: MapLayerSelection(layers: [.punctuality])).stopPanelPause(isOpen: true, lowPower: false), .trainsOff)
        XCTAssertEqual(RadarFeatureGate(layers: on, timeOpen: true, timeAway: true).stopPanelPause(isOpen: true, lowPower: false), .timeAway)
        XCTAssertEqual(RadarFeatureGate(layers: on, cockpitOpen: true).stopPanelPause(isOpen: true, lowPower: false), .cockpit)
        XCTAssertEqual(RadarFeatureGate(layers: on, sceneActive: false).stopPanelPause(isOpen: true, lowPower: false), .background)
        XCTAssertEqual(RadarFeatureGate(layers: on).stopPanelPause(isOpen: true, lowPower: true), .lowPower)
        XCTAssertEqual(RadarFeatureGate(layers: on).stopPanelPause(isOpen: false, lowPower: false), .panelClosed)
        XCTAssertEqual(RadarMineText.pause(.timeAway, idle: false), "Pausiert, solange die Zeitreise eine andere Zeit zeigt.")
        XCTAssertEqual(RadarMineText.pause(.trainsOff, idle: false), "Die Ebene „Züge“ ist aus. Ohne sie fragt das Radar keine Abfahrten ab.")
        XCTAssertEqual(RadarMineText.pause(nil, idle: true), "Pausiert. Tippe zum Aktualisieren.")
        XCTAssertNil(RadarMineText.pause(nil, idle: false))
    }

    // MARK: The cadence

    func testDueAtOpenThenEverySixtySecondsAndNeverTwiceInFlight() {
        var plan = RadarStopWatchPlan()
        XCTAssertNil(plan.nextJob(now: t0), "no stop, nothing due")
        plan.start(stopID: "wl:1", needsLink: false, now: t0)
        XCTAssertEqual(plan.nextJob(now: t0), .board)
        plan.started(.board, now: t0)
        XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(1)), "one in flight")
        XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(90)), "still in flight, however long")
        plan.answered(now: t0.addingTimeInterval(2))
        XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(61)))
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(62)), .board)
    }

    func testANewStopIsLinkedFirstThenItsBoardInTheNextSlot() {
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "osm:1", needsLink: true, now: t0)
        XCTAssertEqual(plan.nextJob(now: t0), .link)
        plan.started(.link, now: t0)
        XCTAssertNil(plan.nextJob(now: t0))
        plan.linked(now: t0.addingTimeInterval(1))
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(1)), .board)
        let generation = plan.generation
        plan.start(stopID: "osm:2", needsLink: false, now: t0.addingTimeInterval(5))
        XCTAssertNotEqual(plan.generation, generation, "an answer of the old stop is dropped")
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(5)), .board, "a new stop restarts at once")
    }

    func testBackoffFifteenThirtySixtyAndTwoMinutes() {
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "wl:1", needsLink: false, now: t0)
        var now = t0
        for wait in [15.0, 30, 60, 120, 120] {
            plan.started(.board, now: now)
            plan.failed(now: now)
            XCTAssertNil(plan.nextJob(now: now.addingTimeInterval(wait - 0.5)))
            XCTAssertEqual(plan.nextJob(now: now.addingTimeInterval(wait)), .board)
            now = now.addingTimeInterval(wait)
            plan.interact(now: now)
        }
        plan.started(.board, now: now)
        plan.answered(now: now)
        XCTAssertEqual(plan.failures, 0)
        XCTAssertEqual(plan.nextJob(now: now.addingTimeInterval(60)), .board, "back to 60 s")
    }

    func testIdleAfterThirtyMinutesUntilATap() {
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "wl:1", needsLink: false, now: t0)
        var now = t0
        var asked = 0
        while now < t0.addingTimeInterval(40 * 60) {
            if plan.nextJob(now: now) != nil {
                plan.started(.board, now: now)
                plan.answered(now: now)
                asked += 1
            }
            now = now.addingTimeInterval(1)
        }
        XCTAssertTrue(plan.isIdle(now: now))
        XCTAssertEqual(asked, 30, "one a minute for thirty minutes, then nothing")
        plan.interact(now: now)
        XCTAssertEqual(plan.nextJob(now: now), .board, "a tap asks at once")
    }

    func testRefreshNowAndCancellation() {
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "wl:1", needsLink: false, now: t0)
        plan.started(.board, now: t0)
        plan.answered(now: t0)
        XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(10)))
        plan.refreshNow(now: t0.addingTimeInterval(10))
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(10)), .board, "„Jetzt aktualisieren“")
        plan.started(.board, now: t0.addingTimeInterval(10))
        plan.cancelled()
        XCTAssertEqual(plan.failures, 0)
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(80)), .board)
        plan.stop()
        XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(200)))
    }

    // MARK: Budget

    /// The worst city view (16 city tiles plus the wide lane) with the board as a side job for ten minutes, the way `RadarModel.run` does it: the side
    /// job first, one `claimSlot` per job, answers a second later.
    func testTheWorstCityViewWithTheBoardStaysWithinTheBudget() {
        var scheduler = RadarScheduler()
        let wien = RadarBox(north: 48.30, west: 16.20, south: 48.12, east: 16.55)
        scheduler.setViewport(wien, latitudeSpan: 0.18, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: 0.18, now: t0)
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "osm:1", needsLink: true, now: t0)
        var sent: [(at: Date, board: Bool)] = []
        var pending: [(due: Date, tile: RadarTileKey?)] = []
        var elapsed = 0.0
        while elapsed <= 600 {
            let now = t0.addingTimeInterval(elapsed)
            for item in pending where item.due <= now {
                if let tile = item.tile { scheduler.recordAnswer(tile, count: tile.lane == .city ? 1000 : 300, at: item.due) }
                else if plan.inFlight == .link { plan.linked(now: now) } else { plan.answered(now: now) }
            }
            pending.removeAll { $0.due <= now }
            plan.interact(now: now)
            if let job = plan.nextJob(now: now), scheduler.claimSlot(now: now) == nil {
                plan.started(job, now: now)
                sent.append((now, true))
                pending.append((now.addingTimeInterval(1), nil))
            }
            if case .request(let tile) = scheduler.next(now: now) {
                sent.append((now, false))
                pending.append((now.addingTimeInterval(3), tile))
            }
            elapsed += 0.25
        }
        func maxIn(_ window: TimeInterval) -> Int {
            sent.indices.map { i in sent.filter { $0.at <= sent[i].at && sent[i].at.timeIntervalSince($0.at) < window }.count }.max() ?? 0
        }
        XCTAssertEqual(scheduler.status(now: t0.addingTimeInterval(600)).city.visibleTiles, 16)
        XCTAssertLessThanOrEqual(maxIn(60), 24)
        XCTAssertLessThanOrEqual(maxIn(10), 4)
        XCTAssertGreaterThanOrEqual(40 - maxIn(60), 16, "at least 16 of the app's 40 stay for planner, boards and follow")
        let gaps = zip(sent.dropFirst(), sent).map { $0.at.timeIntervalSince($1.at) }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 1, 1 - 1e-9)
        let boards = sent.filter(\.board).count
        XCTAssertGreaterThanOrEqual(boards, 10, "the link and about one board a minute")
        XCTAssertLessThanOrEqual(boards, 12, "never more than one a minute")
        XCTAssertGreaterThan(sent.filter { !$0.board }.count, 200, "the tiles are not starved")
    }
}
