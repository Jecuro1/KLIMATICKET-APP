import XCTest
@testable import KlimaCore

/// Radar time travel: which snapshot is requested when, and that the live radar's budget (24 a minute, 4 in 10 seconds, one a second) is
/// never exceeded over a simulated session of scrubbing and playing (docs/RADAR_TIMETRAVEL.md §4). Pure: the tests move the clock.
final class RadarTimeSchedulerTests: XCTestCase {
    private typealias F = RadarTimeFixtures

    /// Thursday 2026-11-12 21:47:36 in Vienna.
    private let now = F.vienna(2026, 11, 12, 21, 47, 36)

    /// The live scheduler and the Zeitreise scheduler sharing one budget, the way the app wires them.
    private final class Session {
        var live = RadarScheduler()
        var travel = RadarTimeScheduler()
        var sent: [Date] = []
        var requests: [RadarTimeRequest] = []
        /// Answers wait this long (the real ones take 0.4 to 21 s).
        var latency: TimeInterval = 0.5
        var answerCount = 900
        private var pending: [(at: Date, request: RadarTimeRequest)] = []

        init(start: Date) {
            live.setViewport(.austria, latitudeSpan: 4.2, now: start)
        }

        func tickLive(_ now: Date) {
            if case .request(let tile) = live.next(now: now) {
                sent.append(now)
                live.recordAnswer(tile, count: 450, at: now)
            }
        }

        func tickTravel(_ now: Date) {
            for item in pending.filter({ $0.at <= now }) {
                travel.recordAnswer(item.request, answeredCount: answerCount, now: now)
            }
            pending.removeAll { $0.at <= now }
            if case .request(let request) = travel.next(now: now, claim: { self.live.claimSlot(now: $0) }) {
                sent.append(now)
                requests.append(request)
                pending.append((now.addingTimeInterval(latency), request))
            }
        }

        func assertWithinBudget(file: StaticString = #filePath, line: UInt = #line) {
            let sorted = sent.sorted()
            for (index, time) in sorted.enumerated() {
                let inMinute = sorted.filter { $0 <= time && time.timeIntervalSince($0) < 60 }.count
                let inTen = sorted.filter { $0 <= time && time.timeIntervalSince($0) < 10 }.count
                XCTAssertLessThanOrEqual(inMinute, 24, "a minute ending at request \(index)", file: file, line: line)
                XCTAssertLessThanOrEqual(inTen, 4, "ten seconds ending at request \(index)", file: file, line: line)
                if index > 0 {
                    XCTAssertGreaterThanOrEqual(time.timeIntervalSince(sorted[index - 1]), 1 - 1e-9, "one second between requests \(index - 1) and \(index)", file: file, line: line)
                }
            }
        }
    }

    // MARK: The plan

    func testTheFinePlanIsElevenSnapshotsOnTheFullTwentyMinutes() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.progress.total, 11, "half an hour back to three hours ahead in steps of 20 minutes")
        let times = scheduler.slots.keys.map(\.time).sorted()
        XCTAssertEqual(times.first, F.vienna(2026, 11, 12, 21, 20), "27 minutes back")
        XCTAssertEqual(times.last, F.vienna(2026, 11, 13, 0, 40))
        XCTAssertEqual(zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }, Array(repeating: 1200, count: 10))
        XCTAssertTrue(times.allSatisfy { $0 >= now.addingTimeInterval(-1800) && $0 <= now.addingTimeInterval(10_800) })
    }

    func testTheCoarsePlanIsThreeSnapshotsOnTheFullHoursAndHasNothingInThePast() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        XCTAssertEqual(scheduler.slots.keys.map(\.time).sorted(), [F.vienna(2026, 11, 12, 22, 0), F.vienna(2026, 11, 12, 23, 0), F.vienna(2026, 11, 13, 0, 0)])
    }

    func testNowIsOneMoreSnapshotWhenTheLiveRadarDoesNotHoldAllOfAustria() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: true)
        XCTAssertEqual(scheduler.progress.total, 12)
        XCTAssertTrue(scheduler.slots.keys.contains { $0.time == now })
        // A grid point within 150 s of now stands in for it.
        var close = RadarTimeScheduler()
        close.begin(now: F.vienna(2026, 11, 12, 21, 58), profile: .fine, includeNow: true)
        XCTAssertEqual(close.progress.total, 10)
    }

    func testThePlanIsOnTheFullTwentyMinutesAcrossTheSwitchToSummerTime() {
        // 2026-03-29: 02:00 CET becomes 03:00 CEST. From 00:50 CET three hours reach 04:50 CEST.
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: F.vienna(2026, 3, 29, 0, 50), profile: .fine, includeNow: false)
        let times = scheduler.slots.keys.map(\.time).sorted()
        XCTAssertEqual(times.count, 11)
        XCTAssertEqual(times.first, F.vienna(2026, 3, 29, 0, 20))
        XCTAssertEqual(times.last, F.vienna(2026, 3, 29, 4, 40), "00:20 ... 01:40 then 03:00 CEST ... 04:40: the clock skips an hour, the steps do not")
        XCTAssertTrue(times.allSatisfy { $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1200) == 0 })
        XCTAssertEqual(Set(times.map { Calendar.vienna.component(.minute, from: $0) }), [0, 20, 40])
        XCTAssertEqual(zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }, Array(repeating: 1200, count: 10), "twenty real minutes apart, also over the jump")
    }

    func testThePlanIsOnTheFullTwentyMinutesAcrossTheSwitchToWinterTimeAndMidnight() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: Date(timeIntervalSince1970: 1_792_886_400), profile: .fine, includeNow: false)   // 2026-10-25 00:00 UTC = 02:00 CEST
        let times = scheduler.slots.keys.map(\.time).sorted()
        XCTAssertEqual(times.count, 11)
        XCTAssertTrue(times.allSatisfy { $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 1200) == 0 })
        XCTAssertEqual(zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }, Array(repeating: 1200, count: 10))
        var midnight = RadarTimeScheduler()
        midnight.begin(now: F.vienna(2026, 11, 12, 22, 50), profile: .fine, includeNow: false)
        XCTAssertEqual(midnight.slots.keys.map(\.time).sorted().first, F.vienna(2026, 11, 12, 22, 20))
        XCTAssertEqual(midnight.slots.keys.map(\.time).sorted().last, F.vienna(2026, 11, 13, 1, 40), "crosses midnight")
    }

    func testTheSnapshotNearestToTheScrubberComesFirst() {
        var scheduler = RadarTimeScheduler()
        scheduler.allowsAutoExact = false   // only the order of the plan is looked at here
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        scheduler.setTarget(now.addingTimeInterval(45 * 60), now: now)   // 22:32:36
        var order: [Date] = []
        var clock = now
        while order.count < 4 {
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                order.append(request.time)
                scheduler.recordAnswer(request, answeredCount: 900, now: clock)
            }
            clock = clock.addingTimeInterval(1)
        }
        XCTAssertEqual(order, [F.vienna(2026, 11, 12, 22, 40), F.vienna(2026, 11, 12, 22, 20), F.vienna(2026, 11, 12, 23, 0), F.vienna(2026, 11, 12, 22, 0)],
                       "7 min away, 12, 27, 32: the picture is usable around where the scrubber is long before the rest arrives")
    }

    func testProgressCountsTheLoadedPointsAndTheSnapshotsAreUsableBeforeTheLastOne() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.progress.loaded, 0)
        XCTAssertTrue(scheduler.isLoading)
        for second in 0..<3 {
            let at = now.addingTimeInterval(Double(second) * 2)
            if case .request(let request) = scheduler.next(now: at, claim: { _ in nil }) { scheduler.recordAnswer(request, answeredCount: 900, now: at) }
        }
        XCTAssertEqual(scheduler.progress.loaded, 3)
        XCTAssertEqual(RadarTimeText.loading(loaded: scheduler.progress.loaded, total: scheduler.progress.total), "Zeitreise lädt 3/11")
        XCTAssertTrue(scheduler.isLoading)
    }

    // MARK: Budget

    func testNothingIsSentWhenTheBudgetSaysWait() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        let later = now.addingTimeInterval(5)
        XCTAssertEqual(scheduler.next(now: now, claim: { _ in later }), .wait(until: later))
        XCTAssertEqual(scheduler.requestsSent, 0)
        XCTAssertEqual(scheduler.inFlightCount, 0)
        guard case .request = scheduler.next(now: later, claim: { _ in nil }) else { return XCTFail("the slot is free then") }
        XCTAssertEqual(scheduler.requestsSent, 1)
    }

    func testAtMostTwoRequestsAreOnTheirWayAtOnce() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        guard case .request = scheduler.next(now: now, claim: { _ in nil }), case .request = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("two") }
        XCTAssertEqual(scheduler.next(now: now, claim: { _ in nil }), .wait(until: now.addingTimeInterval(0.25)), "the third waits for an answer")
    }

    func testTheBudgetHoldsOverASimulatedSessionOfScrubbingAndPlaying() {
        let session = Session(start: now)
        var clock = now
        let end = now.addingTimeInterval(600)
        var lastMove = now
        var target = now
        var playing = false
        var entered = false
        while clock < end {
            let elapsed = clock.timeIntervalSince(now)
            // 0 ... 60 s: the live radar alone. 60 s: the Zeitreise starts. 60 ... 120 s: scrubbing in 5-minute steps every 0.4 s.
            // 120 ... 135 s: resting. 135 ... 171 s: playing (1 s = 5 minutes). Then: scrubbing back and forth, resting every 20 s. 480 s: back to live.
            if elapsed < 60 || elapsed >= 480 {
                session.tickLive(clock)
            } else {
                if !entered {
                    entered = true
                    session.live.setViewport(.austria, latitudeSpan: 4.2, now: clock)
                    session.travel.begin(now: clock, profile: .fine, includeNow: true)
                }
                if elapsed < 120, clock.timeIntervalSince(lastMove) >= 0.4 {
                    lastMove = clock
                    target = clock.addingTimeInterval(Double((Int(elapsed * 2.5) % 37)) * 300)
                    session.travel.setTarget(target, now: clock)
                    session.travel.setMoving(true, now: clock)
                } else if elapsed >= 120, !playing, elapsed < 135 {
                    session.travel.setMoving(false, now: clock)
                } else if elapsed >= 135, elapsed < 171 {
                    if !playing { playing = true; session.travel.setMoving(true, now: clock) }
                    session.travel.setTarget(clock.addingTimeInterval((elapsed - 135) * 300), now: clock)
                } else if elapsed >= 171 {
                    if playing { playing = false; session.travel.setMoving(false, now: clock) }
                    if Int(elapsed) % 20 == 0, clock.timeIntervalSince(lastMove) >= 1 {
                        lastMove = clock
                        target = clock.addingTimeInterval(Double(Int(elapsed) % 36 + 1) * 300)
                        session.travel.setTarget(target, now: clock)
                    }
                }
                session.tickTravel(clock)
            }
            clock = clock.addingTimeInterval(0.1)
        }
        XCTAssertGreaterThan(session.requests.count, 9, "the plan and some resting snapshots were requested")
        session.assertWithinBudget()
    }

    func testTheBudgetHoldsWhenTheLiveRadarAndTheZeitreiseAlternate() {
        let session = Session(start: now)
        session.latency = 3
        var clock = now
        let end = now.addingTimeInterval(300)
        while clock < end {
            let phase = Int(clock.timeIntervalSince(now) / 15) % 2
            if phase == 0 {
                session.tickLive(clock)
            } else {
                if !session.travel.isActive { session.travel.begin(now: clock, profile: .fine, includeNow: true) }
                session.tickTravel(clock)
            }
            clock = clock.addingTimeInterval(0.25)
        }
        session.assertWithinBudget()
        XCTAssertGreaterThan(session.sent.count, 20)
    }

    func testARateLimitPausesTheWholeRadarAndIsHandedToTheLiveScheduler() {
        let session = Session(start: now)
        session.travel.begin(now: now, profile: .fine, includeNow: false)
        guard case .request(let request) = session.travel.next(now: now, claim: { session.live.claimSlot(now: $0) }) else { return XCTFail("first") }
        session.travel.recordFailure(request, error: LiveError.rateLimited(.oebbHafas, retryAfter: nil), now: now)
        XCTAssertEqual(session.travel.pausedUntil, now.addingTimeInterval(20))
        XCTAssertEqual(session.travel.next(now: now.addingTimeInterval(5), claim: { _ in nil }), .wait(until: now.addingTimeInterval(20)))
        session.live.pause(until: session.travel.pausedUntil ?? now)
        XCTAssertEqual(session.live.claimSlot(now: now.addingTimeInterval(5)), now.addingTimeInterval(20), "the live radar waits too")
        XCTAssertNil(session.live.claimSlot(now: now.addingTimeInterval(21)))
    }

    // MARK: A snapshot for the minute the scrubber rests at

    func testTheRestingMinuteGetsItsOwnSnapshotAfterTheRestDelayAndOnlyOnce() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        drainPlan(&scheduler, from: now)
        let rest = now.addingTimeInterval(120)
        let target = F.vienna(2026, 11, 12, 22, 30)   // 10 minutes from the grid points at 22:20 and 22:40
        scheduler.setTarget(target, now: rest)
        XCTAssertEqual(scheduler.next(now: rest.addingTimeInterval(0.3), claim: { _ in nil }), .wait(until: rest.addingTimeInterval(0.6)), "still debouncing")
        guard case .request(let request) = scheduler.next(now: rest.addingTimeInterval(0.6), claim: { _ in nil }) else { return XCTFail("the minute's snapshot") }
        XCTAssertEqual(request.slot.kind, .exact)
        XCTAssertEqual(request.time, target)
        XCTAssertEqual(request.box, RadarBox.austria)
        scheduler.recordAnswer(request, answeredCount: 900, now: rest.addingTimeInterval(2))
        XCTAssertEqual(scheduler.next(now: rest.addingTimeInterval(3), claim: { _ in nil }), .idle, "once")
        XCTAssertTrue(scheduler.hasSnapshot(near: target, now: rest.addingTimeInterval(3)))
        XCTAssertEqual(scheduler.autoExactCount, 1)
    }

    func testNoSnapshotForAMinuteWhileTheScrubberMovesOrPlays() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        drainPlan(&scheduler, from: now)
        var clock = now.addingTimeInterval(120)
        scheduler.setMoving(true, now: clock)
        for step in 0..<50 {   // dragging: a new minute every 0.2 s
            clock = clock.addingTimeInterval(0.2)
            scheduler.setTarget(now.addingTimeInterval(Double(900 + step * 300)), now: clock)
            XCTAssertFalse(scheduler.next(now: clock, claim: { _ in nil }).isRequest, "step \(step)")
        }
        scheduler.setMoving(false, now: clock)
        clock = clock.addingTimeInterval(0.2)
        XCTAssertFalse(scheduler.next(now: clock, claim: { _ in nil }).isRequest, "the rest timer starts when the finger lifts")
        clock = clock.addingTimeInterval(0.5)
        XCTAssertTrue(scheduler.next(now: clock, claim: { _ in nil }).isRequest)
        XCTAssertEqual(scheduler.requestsSent, 12, "11 plan points and exactly one for the minute it stopped at")
    }

    func testAMinuteNextToAPlannedPointNeedsNoSnapshotOfItsOwn() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        scheduler.setTarget(F.vienna(2026, 11, 12, 22, 21), now: now)   // 1 minute from the 22:20 point
        var sent: [RadarTimeSlot.Kind] = []
        var clock = now.addingTimeInterval(2)
        for _ in 0..<12 {
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                sent.append(request.slot.kind)
                scheduler.recordAnswer(request, answeredCount: 900, now: clock)
            }
            clock = clock.addingTimeInterval(1)
        }
        XCTAssertEqual(sent, Array(repeating: .grid, count: 11), "the plan only")
    }

    func testTheLimitOfAutomaticSnapshotsAndTheTapThatGoesBeyondIt() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        drainPlan(&scheduler, from: now)
        var clock = now.addingTimeInterval(60)
        for index in 0..<20 {
            clock = clock.addingTimeInterval(2)
            scheduler.setTarget(clock.addingTimeInterval(Double(10 + index * 7) * 60 + 20), now: clock)
            clock = clock.addingTimeInterval(1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) { scheduler.recordAnswer(request, answeredCount: 900, now: clock) }
        }
        XCTAssertEqual(scheduler.autoExactCount, scheduler.config.autoExactLimit, "no more than 12 by themselves")
        let wanted = clock.addingTimeInterval(170 * 60 + 5)
        scheduler.setTarget(wanted, now: clock)
        clock = clock.addingTimeInterval(1)
        XCTAssertFalse(scheduler.next(now: clock, claim: { _ in nil }).isRequest, "the limit holds")
        scheduler.requestExact(for: wanted)
        guard case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) else { return XCTFail("a tap goes beyond the limit") }
        XCTAssertEqual(request.time, wanted)
    }

    func testOnAMeteredConnectionNothingIsFetchedForAMinuteByItself() {
        var scheduler = RadarTimeScheduler()
        scheduler.allowsAutoExact = false
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        drainPlan(&scheduler, from: now)
        let rest = now.addingTimeInterval(120)
        let target = F.vienna(2026, 11, 12, 22, 30)
        scheduler.setTarget(target, now: rest)
        XCTAssertEqual(scheduler.next(now: rest.addingTimeInterval(2), claim: { _ in nil }), .idle)
        scheduler.requestExact(for: target)
        XCTAssertTrue(scheduler.next(now: rest.addingTimeInterval(2), claim: { _ in nil }).isRequest, "on a tap it is")
    }

    func testNoSnapshotForNowItself() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        drainPlan(&scheduler, from: now)
        scheduler.setTarget(now.addingTimeInterval(30), now: now)   // half a minute ahead: the live radar is right there
        XCTAssertEqual(scheduler.next(now: now.addingTimeInterval(5), claim: { _ in nil }), .idle)
    }

    // MARK: Failures

    func testAFailedSnapshotIsTriedAgainAfter15And30SecondsAndThenGivenUp() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        var clock = now
        guard case .request(let first) = scheduler.next(now: clock, claim: { _ in nil }) else { return XCTFail("first") }
        scheduler.recordFailure(first, error: LiveError.timeout, now: clock)
        // The other two points go first; the failed one is due after 15 s.
        var failedAgain = 0
        for _ in 0..<200 {
            clock = clock.addingTimeInterval(1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                if request.slot == first.slot {
                    failedAgain += 1
                    scheduler.recordFailure(request, error: LiveError.timeout, now: clock)
                } else {
                    scheduler.recordAnswer(request, answeredCount: 900, now: clock)
                }
            }
        }
        XCTAssertEqual(failedAgain, 2, "three tries in all")
        XCTAssertEqual(scheduler.progress.failed, 1)
        XCTAssertEqual(scheduler.progress.loaded, 2)
        XCTAssertTrue(scheduler.isIncomplete)
        XCTAssertFalse(scheduler.isLoading, "nothing left to wait for")
        XCTAssertEqual(RadarTimeText.missing(1).hasPrefix("Ein Zeitpunkt"), true)
    }

    func testTheBackoffIs15ThenThirtySeconds() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        guard case .request(let request) = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("first") }
        scheduler.recordFailure(request, error: LiveError.network("x"), now: now)
        XCTAssertEqual(scheduler.slots[request.slot]?.retryAt, now.addingTimeInterval(15))
        scheduler.recordFailure(request, error: LiveError.network("x"), now: now.addingTimeInterval(15))
        XCTAssertEqual(scheduler.slots[request.slot]?.retryAt, now.addingTimeInterval(45))
    }

    func testACancelledRequestIsDueAgainWithoutATryCounted() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        guard case .request(let request) = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("first") }
        scheduler.recordCancelled(request)
        XCTAssertEqual(scheduler.slots[request.slot]?.attempts, 0)
        XCTAssertEqual(scheduler.inFlightCount, 0)
        XCTAssertTrue(scheduler.next(now: now.addingTimeInterval(1), claim: { _ in nil }).isRequest)
    }

    func testARequestThatNeverReportsBackFreesItsSlot() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        guard case .request = scheduler.next(now: now, claim: { _ in nil }), case .request = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("two") }
        XCTAssertFalse(scheduler.next(now: now.addingTimeInterval(30), claim: { _ in nil }).isRequest, "both still on their way")
        XCTAssertTrue(scheduler.next(now: now.addingTimeInterval(91), claim: { _ in nil }).isRequest, "after 90 s they are asked again")
    }

    // MARK: Answers cut off at the request cap

    func testAnAnswerCutOffAtTheCapIsReplacedByItsTwoHalves() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        guard case .request(let whole) = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("first") }
        XCTAssertEqual(whole.box, RadarBox.austria)
        XCTAssertFalse(RadarTimeScheduler.isComplete(whole, answeredCount: 1000), "cut off: it adds, it never removes")
        XCTAssertTrue(RadarTimeScheduler.isComplete(whole, answeredCount: 999))
        scheduler.recordAnswer(whole, answeredCount: 1000, now: now)
        XCTAssertEqual(scheduler.progress.loaded, 0, "not loaded until both halves are")
        var asked: [RadarTimeRequest] = []
        var clock = now
        for _ in 0..<2 {
            clock = clock.addingTimeInterval(1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) { asked.append(request) }
        }
        let parts = asked.filter { $0.slot.part != nil && $0.time == whole.time }
        XCTAssertEqual(parts.count, 2, "the halves come before the other points")
        XCTAssertEqual(Set(parts.map(\.box)), [RadarTileGrid.box(of: RadarTileKey(level: 0, row: 0, col: 0)), RadarTileGrid.box(of: RadarTileKey(level: 0, row: 0, col: 1))])
        XCTAssertFalse(RadarTimeScheduler.isComplete(parts[0], answeredCount: 400), "one half is not the whole picture")
        for part in parts { scheduler.recordAnswer(part, answeredCount: 500, now: clock) }
        XCTAssertEqual(scheduler.progress.loaded, 1)
        XCTAssertFalse(scheduler.isIncomplete)
    }

    func testAHalfCutOffAgainIsNotedAndShown() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        guard case .request(let whole) = scheduler.next(now: now, claim: { _ in nil }) else { return XCTFail("first") }
        scheduler.recordAnswer(whole, answeredCount: 1000, now: now)
        guard case .request(let half) = scheduler.next(now: now.addingTimeInterval(1), claim: { _ in nil }) else { return XCTFail("half") }
        scheduler.recordAnswer(half, answeredCount: 1000, now: now.addingTimeInterval(1))
        XCTAssertEqual(scheduler.cutOffParts, 1)
        XCTAssertTrue(scheduler.isIncomplete)
    }

    // MARK: Entering again, leaving

    func testEnteringAgainWithinTenMinutesFetchesNothingTwice() {
        // 21:57: the plan is 21:40 ... 00:40. Left, and entered again at 22:03: everything from 21:40 on is fresh and still in range, and
        // 01:00 came into range. Only that one is fetched.
        let start = F.vienna(2026, 11, 12, 21, 57)
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: start, profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.progress.total, 10)
        drainPlan(&scheduler, from: start)
        XCTAssertEqual(scheduler.progress.loaded, 10)
        scheduler.end()
        XCTAssertEqual(scheduler.next(now: start.addingTimeInterval(100), claim: { _ in nil }), .idle, "left: nothing is requested")
        let again = F.vienna(2026, 11, 12, 22, 3)
        scheduler.begin(now: again, profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.progress.total, 11)
        XCTAssertEqual(scheduler.progress.loaded, 10, "the ten that are in range are kept")
        var sent: [Date] = []
        var clock = again
        for _ in 0..<60 {
            clock = clock.addingTimeInterval(1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                sent.append(request.time)
                scheduler.recordAnswer(request, answeredCount: 900, now: clock)
            }
        }
        XCTAssertEqual(sent, [F.vienna(2026, 11, 13, 1, 0)], "only the point that came into range")
        // A quarter of an hour later everything is old.
        scheduler.end()
        scheduler.begin(now: F.vienna(2026, 11, 12, 22, 20, 30), profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.progress.loaded, 0)
        XCTAssertEqual(scheduler.progress.total, 11)
    }

    func testNothingIsRequestedWhenTheZeitreiseIsNotRunning() {
        var scheduler = RadarTimeScheduler()
        XCTAssertEqual(scheduler.next(now: now, claim: { _ in nil }), .idle)
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        scheduler.end()
        XCTAssertEqual(scheduler.next(now: now, claim: { _ in nil }), .idle)
        XCTAssertFalse(scheduler.isActive)
    }

    func testTheVolumeIsStatedHonestly() {
        // 1.8 MB is the largest answer measured (evening peak); at 22 Uhr it was 1.2 MB. So the number is an upper bound: "bis etwa".
        XCTAssertEqual(RadarTimeText.volume(points: 11), "Bis etwa 20 MB (entpackt, 11 Abfragen). Auf der Leitung ist es weniger.")
        XCTAssertEqual(RadarTimeText.volume(points: 3), "Bis etwa 5,4 MB (entpackt, 3 Abfragen). Auf der Leitung ist es weniger.")
        XCTAssertEqual(RadarTimeScheduler.megabytesPerAnswer, 1.8, "the measured 1 831 536 bytes, rounded up")
    }

    // MARK: Review 1

    func testTheCoarsePlanHasFourPointsWhenTheLastFullHourIsInRange() {
        // 21:10: the range is 20:40 ... 00:10, so 21:00 (ten minutes back) is a point too.
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: F.vienna(2026, 11, 12, 21, 10), profile: .coarse, includeNow: false)
        XCTAssertEqual(scheduler.slots.keys.map(\.time).sorted(),
                       [F.vienna(2026, 11, 12, 21, 0), F.vienna(2026, 11, 12, 22, 0), F.vienna(2026, 11, 12, 23, 0), F.vienna(2026, 11, 13, 0, 0)])
    }

    func testFeinLadenDuringAZeitreiseKeepsTheRequestsOnTheirWay() {
        // On a metered connection the coarse plan runs; "Fein laden" starts the fine one while two answers are on their way. They are
        // awaited, not asked again, and never more than two are on their way at once.
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .coarse, includeNow: false)
        var clock = now
        var first: [RadarTimeRequest] = []
        for _ in 0..<6 {
            clock = clock.addingTimeInterval(1.1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) { first.append(request) }
        }
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(scheduler.inFlightCount, 2)
        scheduler.begin(now: clock, profile: .fine, includeNow: false)
        XCTAssertEqual(scheduler.inFlightCount, 2, "still on their way")
        var more: [RadarTimeRequest] = []
        for _ in 0..<6 {
            clock = clock.addingTimeInterval(1.1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) { more.append(request) }
        }
        XCTAssertTrue(more.isEmpty, "two are on their way: nothing more")
        for request in first { scheduler.recordAnswer(request, answeredCount: 900, now: clock) }
        XCTAssertEqual(scheduler.progress.loaded, 2, "their answers count for the fine plan: 22:00 and 23:00 are points of it")
        var sent: [Date] = []
        for _ in 0..<80 {
            clock = clock.addingTimeInterval(1.1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                sent.append(request.time)
                scheduler.recordAnswer(request, answeredCount: 900, now: clock)
            }
        }
        XCTAssertFalse(sent.contains { time in first.contains { $0.time == time } }, "nothing is asked twice")
        XCTAssertEqual(scheduler.progress.loaded, scheduler.progress.total)
        // Entering a new Zeitreise after leaving one: a request of the old one that never answered is asked afresh.
        scheduler.end()
        var fresh = RadarTimeScheduler()
        fresh.begin(now: now, profile: .coarse, includeNow: false)
        _ = fresh.next(now: now.addingTimeInterval(1), claim: { _ in nil })
        XCTAssertEqual(fresh.inFlightCount, 1)
        fresh.end()
        fresh.begin(now: now.addingTimeInterval(5), profile: .coarse, includeNow: false)
        XCTAssertEqual(fresh.inFlightCount, 0)
    }

    func testTheRangeMovesOnWithTheClockDuringALongZeitreise() {
        // 21:47: the plan is 21:20 ... 00:40. Twenty minutes later the range is 21:37 ... 01:07: 21:20 is forgotten, 01:00 comes in.
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        drainPlan(&scheduler, from: now)
        XCTAssertEqual(scheduler.progress.loaded, 11)
        let later = now.addingTimeInterval(20 * 60)
        scheduler.extendPlan(now: later)
        let times = scheduler.slots.keys.filter { $0.kind == .grid }.map(\.time).sorted()
        XCTAssertEqual(times.first, F.vienna(2026, 11, 12, 21, 40))
        XCTAssertEqual(times.last, F.vienna(2026, 11, 13, 1, 0))
        XCTAssertEqual(scheduler.progress.total, 11)
        XCTAssertEqual(scheduler.progress.loaded, 10, "the ten still in range are not fetched again")
        guard case .request(let request) = scheduler.next(now: later, claim: { _ in nil }) else { return XCTFail("the new point") }
        XCTAssertEqual(request.time, F.vienna(2026, 11, 13, 1, 0))
        // A point that failed for good is not planned again, and nothing happens outside a Zeitreise.
        scheduler.recordFailure(request, error: LiveError.disabled(.oebbHafas), now: later)
        scheduler.extendPlan(now: later.addingTimeInterval(60))
        XCTAssertEqual(scheduler.progress.failed, 1)
        XCTAssertEqual(scheduler.next(now: later.addingTimeInterval(61), claim: { _ in nil }), .idle)
        scheduler.end()
        scheduler.extendPlan(now: later.addingTimeInterval(3600))
        XCTAssertEqual(scheduler.progress.total, 11, "not running: the plan stays as it was")
    }

    func testTheSnapshotNearTheChosenMinuteIsNamedByItsTime() {
        var scheduler = RadarTimeScheduler()
        scheduler.begin(now: now, profile: .fine, includeNow: false)
        drainPlan(&scheduler, from: now)
        let clock = now.addingTimeInterval(90)
        XCTAssertEqual(scheduler.snapshotTime(near: F.vienna(2026, 11, 12, 22, 19), now: clock), F.vienna(2026, 11, 12, 22, 20))
        XCTAssertEqual(scheduler.snapshotTime(near: F.vienna(2026, 11, 12, 22, 20), now: clock), F.vienna(2026, 11, 12, 22, 20))
        XCTAssertNil(scheduler.snapshotTime(near: F.vienna(2026, 11, 12, 22, 25), now: clock), "five minutes away: none")
        XCTAssertNil(scheduler.snapshotTime(near: F.vienna(2026, 11, 12, 22, 20), now: clock.addingTimeInterval(700)), "older than ten minutes")
        XCTAssertTrue(scheduler.hasSnapshot(near: F.vienna(2026, 11, 12, 22, 21), now: clock))
        // The words: only the very minute is the server's own picture; one minute off it is named.
        let at2219 = F.vienna(2026, 11, 12, 22, 19), at2220 = F.vienna(2026, 11, 12, 22, 20)
        XCTAssertEqual(RadarTimeText.snapshotNote(snapshot: at2220, target: at2220, now: now),
                       "Für diese Minute hat die Auskunft die Positionen selbst berechnet.")
        XCTAssertEqual(RadarTimeText.snapshotNote(snapshot: at2220, target: at2219, now: now),
                       "Für 22:20 hat die Auskunft die Positionen selbst berechnet, für 22:19 rechnet die App von dort aus.")
    }

    // MARK: Helpers

    /// Answers every point of the plan at once.
    private func drainPlan(_ scheduler: inout RadarTimeScheduler, from start: Date) {
        var clock = start
        for _ in 0..<80 {
            clock = clock.addingTimeInterval(1)
            if case .request(let request) = scheduler.next(now: clock, claim: { _ in nil }) {
                scheduler.recordAnswer(request, answeredCount: 900, now: clock)
            }
        }
    }
}

private extension RadarTimeScheduler.Step {
    var isRequest: Bool {
        if case .request = self { return true }
        return false
    }
}
