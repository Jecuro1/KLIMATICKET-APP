import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: when the guard asks (docs/CONNECTION_GUARD.md §4). Foreground only, never two in flight, the window,
/// the cadence, the backoff, the fallback, Low Power Mode and „Jetzt prüfen“.
final class GuardPlanTests: XCTestCase {
    private func at(_ hhmm: String, second: Int = 0) -> Date { GuardFixture.at(hhmm, second: second) }
    private let on = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: false, switchedOff: false)
    /// Feeder planned 13:30, connection 14:40 (+1 → 14:41).
    private var window: DateInterval { GuardPlan.window(feederPlannedDeparture: at("13:30"), connectionDeparture: at("14:41"))! }

    private func next(_ r: GuardRequestState = GuardRequestState(), conditions c: GuardConditions? = nil, shown: GuardState? = .safe,
                      foreground: Bool = false, now: String) -> GuardDecision {
        GuardPlan.next(conditions: c ?? on, requests: r, shown: shown, window: window, ended: false, returnedToForeground: foreground,
                       now: at(now))
    }

    func testWindow() {
        XCTAssertEqual(window.start, at("13:00"))
        XCTAssertEqual(window.end, at("14:46"))
        XCTAssertEqual(next(now: "12:59"), .idle(.beforeWindow(at("13:00"))))
        XCTAssertEqual(next(now: "13:00"), .ask(.reconstruction))
        XCTAssertEqual(next(now: "14:47"), .idle(.ended))
    }

    func testImmediateOnRegisterThenCadence() {
        XCTAssertEqual(next(now: "14:00"), .ask(.reconstruction), "at once on register")
        let r = GuardPlan.record(GuardRequestState(), kind: .reconstruction, sentAt: at("14:00"), outcome: .answered)
        XCTAssertEqual(next(r, shown: .safe, now: "14:01"), .wait(at("14:02")), "120 s while „Sicher“")
        XCTAssertEqual(next(r, shown: .scheduled, now: "14:01"), .wait(at("14:02")))
        XCTAssertEqual(next(r, shown: .tighter, now: "14:00"), .wait(at("14:01")), "60 s when worse than „Sicher“")
        XCTAssertEqual(next(r, shown: .shaky, now: "14:01"), .ask(.reconstruction))
        XCTAssertEqual(next(r, shown: .safe, now: "14:02"), .ask(.reconstruction))
    }

    func testForegroundReturnAsksWhenTheAnswerIsOlderThanAMinute() {
        let r = GuardPlan.record(GuardRequestState(), kind: .reconstruction, sentAt: at("14:00"), outcome: .answered)
        XCTAssertEqual(GuardPlan.next(conditions: on, requests: r, shown: .safe, window: window, ended: false, returnedToForeground: true,
                                      now: at("14:01", second: 1)), .ask(.reconstruction))
        XCTAssertEqual(GuardPlan.next(conditions: on, requests: r, shown: .safe, window: window, ended: false, returnedToForeground: true,
                                      now: at("14:00", second: 59)), .wait(at("14:02")))
    }

    func testNeverTwoInFlight() {
        var r = GuardRequestState()
        r.inFlight = true
        XCTAssertEqual(next(r, now: "14:00"), .idle(.inFlight))
        XCTAssertEqual(GuardPlan.manual(conditions: on, requests: r, ended: false, now: at("14:00")), .unavailable(.inFlight))
    }

    func testBackoffAndFallback() {
        var r = GuardPlan.record(GuardRequestState(), kind: .reconstruction, sentAt: at("14:00"), outcome: .failed(countsForFallback: true))
        XCTAssertEqual(next(r, now: "14:00"), .wait(at("14:00", second: 15)))
        XCTAssertFalse(r.usesFallback)
        r = GuardPlan.record(r, kind: .reconstruction, sentAt: at("14:00", second: 15), outcome: .failed(countsForFallback: true))
        XCTAssertTrue(r.usesFallback, "two failed Reconstructions in a row")
        XCTAssertEqual(next(r, now: "14:00"), .wait(at("14:00", second: 45)))
        XCTAssertEqual(next(r, now: "14:01"), .ask(.connectionTrip))
        r = GuardPlan.record(r, kind: .connectionTrip, sentAt: at("14:01"), outcome: .failed(countsForFallback: true))
        XCTAssertEqual(next(r, now: "14:01"), .wait(at("14:02")), "third failure: 60 s")
        r = GuardPlan.record(r, kind: .connectionTrip, sentAt: at("14:02"), outcome: .failed(countsForFallback: true))
        XCTAssertEqual(next(r, now: "14:02"), .wait(at("14:04")), "fourth: 120 s")
        r = GuardPlan.record(r, kind: .connectionTrip, sentAt: at("14:04"), outcome: .failed(countsForFallback: true))
        XCTAssertEqual(next(r, now: "14:04"), .wait(at("14:06")), "and 120 s from then on")
        r = GuardPlan.record(r, kind: .connectionTrip, sentAt: at("14:06"), outcome: .answered)
        XCTAssertEqual(r.consecutiveFailures, 0)
        XCTAssertEqual(next(r, now: "14:06"), .wait(at("14:08")))
    }

    func testOfflineFailuresDoNotSwitchToTheFallback() {
        var r = GuardRequestState()
        for i in 0..<3 {
            r = GuardPlan.record(r, kind: .reconstruction, sentAt: at("14:0\(i)"), outcome: .failed(countsForFallback: false))
        }
        XCTAssertFalse(r.usesFallback)
        XCTAssertEqual(r.consecutiveFailures, 3)
    }

    func testAnAnswerBetweenTwoFailuresResetsTheFallbackCount() {
        var r = GuardPlan.record(GuardRequestState(), kind: .reconstruction, sentAt: at("14:00"), outcome: .failed(countsForFallback: true))
        r = GuardPlan.record(r, kind: .reconstruction, sentAt: at("14:01"), outcome: .answered)
        r = GuardPlan.record(r, kind: .reconstruction, sentAt: at("14:03"), outcome: .failed(countsForFallback: true))
        XCTAssertFalse(r.usesFallback)
    }

    func testGates() {
        func with(_ change: (inout GuardConditions) -> Void) -> GuardConditions {
            var c = on
            change(&c)
            return c
        }
        XCTAssertEqual(next(conditions: with { $0.liveAvailable = false }, now: "14:00"), .idle(.liveOff), "timetable nil: no request")
        XCTAssertEqual(next(conditions: with { $0.appActive = false }, now: "14:00"), .idle(.background), "app inactive: no request")
        XCTAssertEqual(next(conditions: with { $0.lowPower = true }, now: "14:00"), .idle(.lowPower))
        XCTAssertEqual(next(conditions: with { $0.switchedOff = true }, now: "14:00"), .idle(.switchedOff))
        XCTAssertEqual(next(conditions: with { $0.followsFeeder = false }, now: "14:00"), .idle(.notFollowing), "follow stopped or replaced")
        XCTAssertEqual(GuardPlan.next(conditions: on, requests: GuardRequestState(), shown: .safe, window: window, ended: true, now: at("14:00")),
                       .idle(.ended))
    }

    func testManualCheck() {
        let lowPower = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: true, switchedOff: false)
        XCTAssertEqual(GuardPlan.manual(conditions: lowPower, requests: GuardRequestState(), ended: false, now: at("14:00")),
                       .ask(.reconstruction), "Low Power Mode: only „Jetzt prüfen“")
        let r = GuardPlan.record(GuardRequestState(), kind: .reconstruction, sentAt: at("14:00"), outcome: .answered, manual: true)
        XCTAssertEqual(GuardPlan.manual(conditions: on, requests: r, ended: false, now: at("14:00", second: 15)), .tooSoon(5))
        XCTAssertEqual(GuardPlan.manual(conditions: on, requests: r, ended: false, now: at("14:00", second: 20)), .ask(.reconstruction))
        var off = on
        off.liveAvailable = false
        XCTAssertEqual(GuardPlan.manual(conditions: off, requests: GuardRequestState(), ended: false, now: at("14:00")), .unavailable(.liveOff))
        off = on
        off.switchedOff = true
        XCTAssertEqual(GuardPlan.manual(conditions: off, requests: GuardRequestState(), ended: false, now: at("14:00")), .unavailable(.switchedOff))
        XCTAssertEqual(GuardPlan.manual(conditions: on, requests: GuardRequestState(), ended: true, now: at("14:00")), .unavailable(.ended))
    }

    func testEnd() {
        XCTAssertTrue(GuardPlan.hasEnded(state: .over, window: window, createdAt: at("13:00"), now: at("14:00")))
        XCTAssertTrue(GuardPlan.hasEnded(state: .safe, window: window, createdAt: at("13:00"), now: at("14:46", second: 1)))
        XCTAssertFalse(GuardPlan.hasEnded(state: .missed, window: window, createdAt: at("13:00"), now: at("14:45")))
        XCTAssertTrue(GuardPlan.hasEnded(state: .safe, window: nil, createdAt: at("01:00"), now: at("13:01")), "older than 12 h")
    }

    // MARK: The engine (what the app service runs)

    private func engine() -> GuardEngine { GuardEngine(record: GuardFixture.record) }

    func testEngineSwitchedOffAsksNothing() {
        var e = engine()
        e.setSwitchedOff(true)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:00")), .idle(.switchedOff))
        XCTAssertEqual(e.manualDecision(conditions: on, now: at("14:00")), .unavailable(.switchedOff))
        e.setSwitchedOff(false)
        XCTAssertEqual(e.decision(conditions: on, now: at("14:00")), .ask(.reconstruction))
    }

    func testEngineRestoreInABackgroundRefreshAsksNothing() {
        // Restoring computes, it never asks: the loop starts only when the app is active.
        var e = GuardEngine(record: GuardFixture.record)
        _ = e.reassess(now: at("14:00"))
        let background = GuardConditions(followsFeeder: true, appActive: false, liveAvailable: true, lowPower: false, switchedOff: false)
        XCTAssertEqual(e.decision(conditions: background, now: at("14:00")), .idle(.background))
    }

    func testEngineFallsBackToTheConnectingTrip() {
        var e = engine()
        e.begin()
        e.applyFailure(kind: .reconstruction, countsForFallback: true, sentAt: at("14:00"))
        e.begin()
        e.applyFailure(kind: .reconstruction, countsForFallback: true, sentAt: at("14:00", second: 15))
        XCTAssertEqual(e.decision(conditions: on, now: at("14:01")), .ask(.connectionTrip))
        XCTAssertEqual(e.connectionTripID, "trip-connection")
        let trip = TripDetails(tripID: "trip-connection", stopovers: [
            Stopover(location: GuardFixture.stPoelten, departure: GuardFixture.event(at("14:40"), delay: 3 * 60, platform: "5")),
        ])
        e.begin()
        _ = e.applyConnectionTrip(trip, sentAt: at("14:01"), now: at("14:01"))
        XCTAssertEqual(e.assessment?.bufferMinutes, 9, "14:31 → 14:43, walk 3")
        XCTAssertEqual(e.decision(conditions: on, now: at("14:02")), .wait(at("14:03")))
    }

    func testEngineAnswerWithoutTheChangeIsAFailure() {
        var e = engine()
        var broken = GuardFixture.journey()
        broken.legs = [broken.legs[0]]
        e.begin()
        let change = e.applyReconstruction(broken, sentAt: at("14:00"), now: at("14:00"))
        XCTAssertEqual(change, .none)
        XCTAssertEqual(e.requests.consecutiveFailures, 1)
        XCTAssertFalse(e.requests.inFlight)
    }

    func testEngineTransferEstimateForTheNotice() {
        var e = engine()
        e.begin()
        _ = e.applyReconstruction(GuardFixture.journey(), sentAt: at("14:00"), now: at("14:00"))
        let estimate = e.transferEstimate
        XCTAssertEqual(estimate?.expectedDeparture, at("14:41"))
        XCTAssertEqual(estimate?.observedAt, at("14:00"))
        XCTAssertEqual(estimate?.walkMinutes, 3)
        // A newer follow answer of the feeder does not make the connection's departure newer.
        _ = e.followUpdated(GuardFixture.followSnapshot(delay: 180, now: at("14:05")), at: at("14:05"), now: at("14:05"))
        XCTAssertEqual(e.assessment?.dataAt, at("14:05"))
        XCTAssertEqual(e.transferEstimate?.observedAt, at("14:00"))
    }

    func testEngineToastsOncePerWorseningAndSearchesOnce() {
        var e = engine()
        e.begin()
        var change = e.applyReconstruction(GuardFixture.journey(feederDelay: 0, connectionDelay: 0), sentAt: at("14:00"), now: at("14:00"))
        XCTAssertFalse(change.worsened, "the first state is no worsening")
        e.begin()
        change = e.applyReconstruction(GuardFixture.journey(feederDelay: 8 * 60, connectionDelay: 0), sentAt: at("14:01"), now: at("14:01"))
        XCTAssertEqual(change.current, .shaky)
        XCTAssertTrue(change.worsened)
        XCTAssertFalse(change.searchAlternatives)
        e.begin()
        change = e.applyReconstruction(GuardFixture.journey(feederDelay: 8 * 60, connectionDelay: 0), sentAt: at("14:02"), now: at("14:02"))
        XCTAssertFalse(change.worsened, "same state: no second toast")
        e.begin()
        change = e.applyReconstruction(GuardFixture.journey(feederDelay: 13 * 60, connectionDelay: 0), sentAt: at("14:03"), now: at("14:03"))
        XCTAssertEqual(change.current, .likelyMissed)
        XCTAssertTrue(change.searchAlternatives, "„Wahrscheinlich verpasst“ opens the alternatives once")
        let query = e.alternativesQuery(now: at("14:03"))
        XCTAssertNotNil(query)
        e.alternativesSearched(at: at("14:03"))
        XCTAssertNil(e.alternativesQuery(now: at("14:05")), "no second search within three minutes")
        // Missed at the departure: still inside the group, no second automatic search.
        change = e.reassess(now: at("14:41"))
        XCTAssertEqual(change.current, .missed)
        XCTAssertFalse(change.searchAlternatives)
        XCTAssertNotNil(e.alternativesQuery(now: at("14:06")))
    }
}

/// The gate test of §11: with live data off the plan says „no request“, and a driver that runs the engine like the app
/// service never calls its refresh closure (App-independent double, simulated hour).
final class GuardGateTests: XCTestCase {
    private final class Driver {
        var engine: GuardEngine
        var refreshCalls = 0
        var tripCalls = 0
        let refresh: () -> Journey

        init(record: GuardRecord, refresh: @escaping () -> Journey) {
            engine = GuardEngine(record: record)
            self.refresh = refresh
        }

        func tick(_ conditions: GuardConditions, now: Date) {
            _ = engine.reassess(now: now)   // the service recomputes on every wake-up (time moves)
            guard case .ask(let kind) = engine.decision(conditions: conditions, now: now) else { return }
            engine.begin()
            switch kind {
            case .reconstruction:
                refreshCalls += 1
                _ = engine.applyReconstruction(refresh(), sentAt: now, now: now)
            case .connectionTrip:
                tripCalls += 1
                engine.abandon()
            }
        }
    }

    func testLiveDataOffNeverCallsRefresh() {
        let driver = Driver(record: GuardFixture.record) { GuardFixture.journey() }
        let off = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: false, lowPower: false, switchedOff: false)
        for second in stride(from: 0, to: 3600, by: 10) {
            driver.tick(off, now: GuardFixture.at("13:45").addingTimeInterval(TimeInterval(second)))
        }
        XCTAssertEqual(driver.refreshCalls, 0)
        XCTAssertEqual(driver.tripCalls, 0)
    }

    func testBackgroundLowPowerAndSwitchOffNeverCallRefresh() {
        for conditions in [
            GuardConditions(followsFeeder: true, appActive: false, liveAvailable: true, lowPower: false, switchedOff: false),
            GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: true, switchedOff: false),
            GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: false, switchedOff: true),
            GuardConditions(followsFeeder: false, appActive: true, liveAvailable: true, lowPower: false, switchedOff: false),
        ] {
            let driver = Driver(record: GuardFixture.record) { GuardFixture.journey() }
            for second in stride(from: 0, to: 3600, by: 10) {
                driver.tick(conditions, now: GuardFixture.at("13:45").addingTimeInterval(TimeInterval(second)))
            }
            XCTAssertEqual(driver.refreshCalls, 0, "\(conditions)")
        }
    }

    func testCadenceOverTheWholeWindow() {
        let driver = Driver(record: GuardFixture.record) { GuardFixture.journey() }   // „Sicher“ (7 minutes)
        let on = GuardConditions(followsFeeder: true, appActive: true, liveAvailable: true, lowPower: false, switchedOff: false)
        for second in stride(from: 0, to: 2 * 3600, by: 5) {
            driver.tick(on, now: GuardFixture.at("12:50").addingTimeInterval(TimeInterval(second)))
        }
        // Window 13:00 … 14:46 (connection 14:41 + 5): one ask at 13:00, then every 120 s; „Umstieg vorbei“ at 14:43 ends it.
        XCTAssertEqual(driver.refreshCalls, 52)
        XCTAssertLessThanOrEqual(Double(driver.refreshCalls) / 106.0, 0.5, "at most one request every two minutes while „Sicher“")
    }
}
