import XCTest
@testable import KlimaCore

/// Fusion of the timetable and the GPS, the state machine and the scripted tracks (docs/EXIT_ALARM.md §3).
final class ExitAlarmPlannerTests: XCTestCase {
    typealias F = ExitAlarmFixtures

    private func armed(stop: Int = 2, lead: ExitAlarmLead = .fiveMinutes, now: Date? = nil, harness: ExitAlarmHarness? = nil) -> (ExitAlarmHarness, ExitAlarmSpec) {
        let h = harness ?? ExitAlarmHarness()
        let spec = F.spec(stop: stop, lead: lead)
        h.engine.arm(spec, arrival: F.arrival(at: stop))
        return (h, spec)
    }

    // MARK: Normal approach

    func testNormalApproachRingsOnceAtLeadBeforeArrival() {
        let (h, spec) = armed()
        let trigger = F.arrival(at: 2).addingTimeInterval(-300)
        XCTAssertEqual(h.scheduler.scheduled[spec.id], trigger, "the time-based alarm is scheduled for arrival minus lead")
        XCTAssertNotNil(h.location.regions[spec.id], "the geofence is set around the stop")

        h.play(F.fixes(toStop: 2))
        let state = h.state(spec.id)!
        XCTAssertEqual(state.phase, .fired)
        XCTAssertEqual(h.ringCount, 1, "rang exactly once")
        let firedAt = state.firedAt!
        XCTAssertLessThan(abs(firedAt.timeIntervalSince(trigger)), 12, "within one fix interval of the moment")
        XCTAssertNil(h.scheduler.scheduled[spec.id], "no second alarm is left behind")
    }

    func testAFasterTrainRingsByGPSBeforeTheTimetable() {
        let (h, spec) = armed()
        let planned = F.arrival(at: 2).addingTimeInterval(-300)
        // 50 m/s instead of the planned 40: the GPS estimate runs ahead of the timetable.
        for fix in F.fixes(toStop: 2, speed: 50) where h.state(spec.id)?.phase != .fired { h.play([fix]) }
        let state = h.state(spec.id)!
        XCTAssertEqual(state.phase, .fired)
        XCTAssertEqual(state.firedBy, .gps)
        XCTAssertLessThan(state.firedAt!, planned.addingTimeInterval(-60), "earlier than the timetable moment")
        XCTAssertNil(h.scheduler.scheduled[spec.id], "the time-based alarm was dropped when the GPS rang first")
        XCTAssertEqual(h.scheduler.log.suffix(2), ["cancel \(spec.id)", "ring \(spec.id)"])
        XCTAssertEqual(h.ringCount, 1)
        // The remaining distance at that moment is about five minutes at 50 m/s.
        XCTAssertEqual(state.remainingMeters ?? 0, 50 * 300, accuracy: 600)
    }

    func testASlowTrainWithAReportedDelayRingsOnTheDelayedMoment() {
        let (h, spec) = armed()
        // Ten minutes late, reported before departure: the alarm moves and the slower GPS estimate agrees.
        let delayedArrival = F.arrival(at: 2).addingTimeInterval(600)
        h.engine.timetable(tripID: spec.tripID, stopovers: [Stopover(location: Location(lid: spec.stopID, name: spec.stopName, coordinate: spec.stopCoordinate),
                                                                  arrival: StopEvent(planned: F.arrival(at: 2), realtime: delayedArrival),
                                                                  departure: nil, index: 2)])
        XCTAssertEqual(h.scheduler.scheduled[spec.id], delayedArrival.addingTimeInterval(-300))
        let speed = F.length(to: 2) / delayedArrival.timeIntervalSince(F.t0)
        h.play(F.fixes(toStop: 2, speed: speed))
        let state = h.state(spec.id)!
        XCTAssertEqual(state.phase, .fired)
        XCTAssertEqual(h.ringCount, 1)
        XCTAssertLessThan(abs(state.firedAt!.timeIntervalSince(delayedArrival.addingTimeInterval(-300))), 15)
        XCTAssertGreaterThan(state.firedAt!, F.arrival(at: 2).addingTimeInterval(-300), "later than the planned moment")
    }

    func testApproachingPulseStartsThreeMinutesBeforeTheMoment() {
        let (h, spec) = armed()
        let trigger = F.arrival(at: 2).addingTimeInterval(-300)
        h.advance(to: trigger.addingTimeInterval(-400))
        XCTAssertEqual(h.state(spec.id)?.phase, .armed)
        h.advance(to: trigger.addingTimeInterval(-170))
        XCTAssertEqual(h.state(spec.id)?.phase, .approaching)
    }

    // MARK: Delay

    func testDelayIncreaseMovesTheTimeAlarmLater() {
        let (h, spec) = armed()
        let original = h.scheduler.scheduled[spec.id]!
        h.advance(to: F.t0.addingTimeInterval(1000))
        let delayed = F.arrival(at: 2).addingTimeInterval(8 * 60)
        h.engine.timetable(tripID: spec.tripID, stopovers: stopovers(arrivalAtLinz: delayed, delay: 480))
        XCTAssertEqual(h.scheduler.scheduled[spec.id], delayed.addingTimeInterval(-300))
        XCTAssertGreaterThan(h.scheduler.scheduled[spec.id]!, original)
        XCTAssertEqual(h.state(spec.id)?.delaySeconds, 480)
        XCTAssertEqual(h.ringCount, 0)
    }

    func testDelayFallsBackFromApproachingToArmed() {
        let (h, spec) = armed()
        let trigger = F.arrival(at: 2).addingTimeInterval(-300)
        h.advance(to: trigger.addingTimeInterval(-100))
        XCTAssertEqual(h.state(spec.id)?.phase, .approaching)
        let delayed = F.arrival(at: 2).addingTimeInterval(10 * 60)
        h.engine.timetable(tripID: spec.tripID, stopovers: stopovers(arrivalAtLinz: delayed, delay: 600))
        XCTAssertEqual(h.state(spec.id)?.phase, .armed, "a delay re-arms: the card stops pulsing")
        XCTAssertEqual(h.scheduler.scheduled[spec.id], delayed.addingTimeInterval(-300))
        h.advance(to: trigger.addingTimeInterval(120))
        XCTAssertEqual(h.ringCount, 0, "the old moment passes without a ring")
    }

    func testSmallDelayChangeKeepsTheScheduledAlarm() {
        let (h, spec) = armed()
        let before = h.scheduler.log.count
        h.engine.timetable(tripID: spec.tripID, stopovers: stopovers(arrivalAtLinz: F.arrival(at: 2).addingTimeInterval(20), delay: 20))
        XCTAssertEqual(h.scheduler.log.count, before, "20 s is inside the tolerance: nothing is rescheduled")
    }

    func testTimetableMovingEarlierThanTheScheduledAlarmRingsNow() {
        let (h, spec) = armed()
        // 20 minutes before the arrival the timetable says the train arrives in 2 minutes: the alarm moment is long past.
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-1200))
        h.engine.timetable(tripID: spec.tripID, stopovers: stopovers(arrivalAtLinz: h.now.addingTimeInterval(120), delay: -1080))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertEqual(h.ringCount, 1)
        XCTAssertNil(h.scheduler.scheduled[spec.id], "the late scheduled alarm is gone")
    }

    // MARK: Tunnel and GPS loss

    func testTunnelFallsBackToTheTimetable() {
        let (h, spec) = armed()
        let all = F.fixes(toStop: 2)
        let cut = F.t0.addingTimeInterval(1500)
        h.play(all.filter { $0.time <= cut })
        XCTAssertNotNil(h.state(spec.id)?.gpsArrival)
        // No fix any more (tunnel, GPS lost). The clock runs on.
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-290))
        let state = h.state(spec.id)!
        XCTAssertFalse(state.motion.isFresh(at: h.now, config: .standard))
        XCTAssertEqual(state.phase, .fired)
        XCTAssertEqual(state.firedBy, .timetable, "the timetable carried it")
        XCTAssertEqual(h.ringCount, 1)
        let estimate = ExitAlarmPresentation.estimate(state, now: h.now)
        XCTAssertEqual(estimate.source, .timetable)
        XCTAssertNil(estimate.remainingMeters, "no distance without a fresh fix")
    }

    // MARK: Standing still

    func testStandingStillGivesNoGPSEstimateNotAnInfiniteOne() {
        let (h, spec) = armed()
        let track = ExitAlarmTrack(path: F.path(to: 4), interval: 5)
        let fixes = track.fixes(from: F.t0, segments: [.init(meters: F.length(to: 1), speed: F.speed),
                                                       .init(meters: 300, speed: 0),      // 300 s at the station
                                                       .init(meters: 20_000, speed: F.speed)])
        let stillRange = fixes.filter { $0.speed == 0 }
        XCTAssertFalse(stillRange.isEmpty)
        // Play up to the end of the standstill.
        h.play(fixes.filter { $0.time <= stillRange.last!.time })
        let state = h.state(spec.id)!
        XCTAssertNotNil(state.motion.smoothedSpeed)
        XCTAssertLessThan(state.motion.smoothedSpeed!, ExitAlarmConfig.standard.minTravelSpeed, "smoothing has come down to standing")
        XCTAssertNil(state.gpsArrival, "standing: no GPS arrival")
        let estimate = ExitAlarmPresentation.estimate(state, now: h.now)
        XCTAssertNotNil(estimate.remainingSeconds)
        XCTAssertTrue(estimate.remainingSeconds!.isFinite)
        XCTAssertEqual(estimate.source, .timetable)
        XCTAssertEqual(state.phase, .armed, "standing does not ring")
        // Moving again: a finite GPS arrival comes back.
        h.play(fixes.filter { $0.time > stillRange.last!.time }.prefix(30).map { $0 })
        XCTAssertNotNil(h.state(spec.id)?.gpsArrival)
        XCTAssertTrue(h.state(spec.id)!.gpsArrival!.timeIntervalSince(h.now).isFinite)
    }

    func testStandingStillWithNoSpeedAtAllDoesNotRingByGPS() {
        let (h, spec) = armed()
        // 10 minutes before the moment the train stands 8 km before Linz: speed 0. The GPS says nothing, the timetable rings later.
        let early = F.fixes(toStop: 2).filter { $0.time <= F.arrival(at: 2).addingTimeInterval(-800) }
        h.play(early)
        for i in 1...20 {
            let last = early.last!
            let stand = LocationFix(time: last.time.addingTimeInterval(Double(i) * 5), coordinate: last.coordinate, speed: 0)
            h.play([stand])
        }
        XCTAssertEqual(h.state(spec.id)?.phase == .fired, false)
        XCTAssertEqual(h.ringCount, 0)
    }

    // MARK: Jitter and hysteresis

    func testJitteryMomentDoesNotFlipApproaching() {
        var state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        let trigger = F.arrival(at: 2).addingTimeInterval(-300)
        ExitAlarmPlanner.apply(.tick, to: &state, now: trigger.addingTimeInterval(-170))
        XCTAssertEqual(state.phase, .approaching)
        // The moment jitters by a minute: inside the hysteresis band the phase stays.
        for shift in [60.0, -40, 90, -20, 100] {
            ExitAlarmPlanner.apply(.timetable(arrival: F.arrival(at: 2).addingTimeInterval(shift), departure: nil, delaySeconds: Int(shift)),
                                   to: &state, now: trigger.addingTimeInterval(-170))
            XCTAssertEqual(state.phase, .approaching, "shift \(shift)")
        }
        ExitAlarmPlanner.apply(.timetable(arrival: F.arrival(at: 2).addingTimeInterval(200), departure: nil, delaySeconds: 200),
                               to: &state, now: trigger.addingTimeInterval(-170))
        XCTAssertEqual(state.phase, .armed, "beyond window plus hysteresis it goes back")
    }

    func testOneWildFixDoesNotRing() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        h.play(F.fixes(toStop: 2).filter { $0.time <= F.t0.addingTimeInterval(1200) })
        // One fix that claims to be next to Linz at 40 m/s, then the normal track resumes.
        let wildTime = h.now.addingTimeInterval(5)
        h.play([LocationFix(time: wildTime, coordinate: F.linz, speed: 40, horizontalAccuracy: 10)])
        XCTAssertEqual(h.ringCount, 0, "GPS needs two fixes in a row")
        XCTAssertEqual(h.state(spec.id)?.phase == .fired, false)
    }

    // MARK: Never twice

    func testNoDoubleFireAcrossGeofenceTimeAndGPS() {
        let (h, spec) = armed()
        // The geofence rings first (the train is early), then the other two ways must stay silent.
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-700))
        h.location.enterRegion(spec.id)
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertEqual(h.state(spec.id)?.firedBy, .geofence)
        XCTAssertNil(h.scheduler.scheduled[spec.id], "the time-based alarm was cancelled")
        h.play(F.fixes(toStop: 2))
        h.advance(to: F.arrival(at: 2))
        h.engine.tick()
        h.scheduler.onEvent?(.rang(spec.id))   // even a late event of the system
        XCTAssertEqual(h.ringCount, 1)
        XCTAssertEqual(h.state(spec.id)?.firedBy, .geofence)
    }

    func testTimeAlarmFirstThenLocationStaysQuiet() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))   // the system alarm rang at -300
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertEqual(h.state(spec.id)?.firedBy, .timetable)
        h.location.enterRegion(spec.id)   // the circle is entered a minute later
        h.play(F.fixes(toStop: 2).filter { $0.time > h.now })
        XCTAssertEqual(h.ringCount, 1)
    }

    func testEffectsAfterFiringAreEmpty() {
        var state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        _ = ExitAlarmPlanner.apply(.regionEntered, to: &state, now: F.arrival(at: 2).addingTimeInterval(-400))
        XCTAssertEqual(state.phase, .fired)
        XCTAssertTrue(ExitAlarmPlanner.apply(.regionEntered, to: &state, now: F.arrival(at: 2).addingTimeInterval(-300)).isEmpty)
        XCTAssertTrue(ExitAlarmPlanner.apply(.timeAlarmRang, to: &state, now: F.arrival(at: 2).addingTimeInterval(-300)).isEmpty)
        XCTAssertTrue(ExitAlarmPlanner.apply(.tick, to: &state, now: F.arrival(at: 2).addingTimeInterval(-200)).isEmpty)
    }

    // MARK: Geofence

    func testGeofenceRadiusIsAtLeast1500MetresAndGrowsWithSpeedAndLead() {
        var spec = F.spec(stop: 2, lead: .atArrival)
        XCTAssertEqual(ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: 40), 1500, "lead 0: the floor")
        spec.lead = .fiveMinutes
        XCTAssertEqual(ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: 40), 12_000, accuracy: 0.5)
        XCTAssertEqual(ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: 8), 2400, accuracy: 0.5, "a tram: 8 m/s × 300 s")
        XCTAssertEqual(ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: 1), ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: nil),
                       "a standstill does not shrink the circle")
        spec.lead = .tenMinutes
        XCTAssertEqual(ExitAlarmGeometry.geofenceRadius(spec: spec, smoothedSpeed: 80), 20_000, "capped")
    }

    func testGeofenceEntryRingsAndCancelsTheTimeAlarm() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-900))
        h.location.enterRegion(spec.id)
        XCTAssertEqual(h.scheduler.log.suffix(2), ["cancel \(spec.id)", "ring \(spec.id)"], "cancel first, then ring")
        XCTAssertNil(h.location.regions[spec.id], "the circle is removed after it fired")
    }

    func testImplausibleGeofenceEntryIsIgnored() {
        let (h, spec) = armed()
        h.advance(to: F.t0)   // the trigger is 40 minutes away
        h.location.enterRegion(spec.id)
        XCTAssertEqual(h.state(spec.id)?.phase, .armed)
        XCTAssertEqual(h.ringCount, 0)
    }

    func testGeofenceRadiusFollowsTheSpeed() {
        let (h, spec) = armed()
        let initial = h.location.regions[spec.id]!.radius
        XCTAssertEqual(initial, F.length(to: 2) / (F.length(to: 2) / F.speed) * 300, accuracy: 1, "starts from the leg's average speed")
        // The train is much slower than planned.
        let slow = ExitAlarmTrack(path: F.path(to: 4), interval: 5).fixes(from: F.t0.addingTimeInterval(100), segments: [.init(meters: 3000, speed: 10)])
        h.play(slow)
        let adjusted = h.location.regions[spec.id]!.radius
        XCTAssertLessThan(adjusted, initial)
        XCTAssertGreaterThanOrEqual(adjusted, 1500)
    }

    // MARK: Overshoot

    func testOvershootAlertsOnceWhenNotAcknowledged() {
        let h = ExitAlarmHarness()
        // The alarm is for Linz (an intermediate stop); the train rides on towards Amstetten and the user sleeps on.
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2), departure: F.arrival(at: 2).addingTimeInterval(120))
        h.play(F.fixes(toStop: 2, extraMeters: 15_000))
        let state = h.state(spec.id)!
        XCTAssertNotNil(state.firedAt)
        XCTAssertNotNil(state.passedAt, "Du bist an Linz Hbf vorbeigefahren")
        XCTAssertEqual(h.ringCount, 2, "the alarm, then one passed alert")
        XCTAssertEqual(h.scheduler.rings.last?.kind, .passed)
        XCTAssertEqual(ExitAlarmPresentation.firedSubtitle(state), "Du bist an Linz Hbf vorbeigefahren.")
    }

    func testNoPassedAlertWhenAcknowledged() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2), departure: F.arrival(at: 2).addingTimeInterval(120))
        let fixes = F.fixes(toStop: 2, extraMeters: 15_000)
        h.play(fixes.filter { $0.time <= F.arrival(at: 2).addingTimeInterval(-250) })
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        h.engine.acknowledge(id: spec.id)
        h.play(fixes.filter { $0.time > h.now })
        XCTAssertNil(h.state(spec.id)?.passedAt)
        XCTAssertEqual(h.scheduler.rings.count + h.systemRings.count, 1)
    }

    func testPassedByTimetableWithoutGPS() {
        let h = ExitAlarmHarness(authorization: .denied)
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2), departure: F.arrival(at: 2).addingTimeInterval(120))
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        h.advance(to: F.arrival(at: 2).addingTimeInterval(120 + 100))
        XCTAssertNotNil(h.state(spec.id)?.passedAt)
        XCTAssertEqual(h.scheduler.rings.map(\.kind), [.passed], "the system rang the first alarm, the app rings the passed alert")
    }

    func testTerminusIsNeverPassedByTheTimetable() {
        let h = ExitAlarmHarness(authorization: .denied)
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2), departure: nil)   // the last stop of the run
        h.advance(to: F.arrival(at: 2).addingTimeInterval(500))
        XCTAssertNil(h.state(spec.id)?.passedAt)
    }

    func testUserWalkingAwayFromTheStationIsNotPassed() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        var fixes = F.fixes(toStop: 2)
        h.play(fixes)
        h.engine.acknowledge(id: spec.id)
        // Afterwards the user walks away from the station: acknowledged, so nothing rings.
        fixes = ExitAlarmTrack(path: F.path(to: 4), startAlong: F.length(to: 2)).fixes(from: h.now, segments: [.init(meters: 1500, speed: 1.4)])
        h.play(fixes)
        XCTAssertNil(h.state(spec.id)?.passedAt)
    }

    // MARK: Snooze, acknowledge, cancel

    func testSnoozeRingsAgainAfterFiveMinutesAndOnlyOnce() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        XCTAssertEqual(h.ringCount, 1)
        h.engine.snooze(id: spec.id, minutes: 5)
        XCTAssertEqual(h.state(spec.id)?.phase, .snoozed)
        let until = h.now.addingTimeInterval(300)
        XCTAssertEqual(h.scheduler.scheduled[spec.id], until)
        // A geofence entry or a fix during the snooze rings nothing.
        h.location.enterRegion(spec.id)
        h.advance(to: h.now.addingTimeInterval(200))
        XCTAssertEqual(h.ringCount, 1)
        h.advance(to: until.addingTimeInterval(1))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertEqual(h.state(spec.id)?.firedBy, .snooze)
        XCTAssertEqual(h.ringCount, 2, "one more ring: the one the user asked for")
        h.advance(to: until.addingTimeInterval(60))
        XCTAssertEqual(h.ringCount, 2)
        XCTAssertEqual(h.state(spec.id)?.snoozeCount, 1)
    }

    func testSnoozeIsClampedAndNotAvailableAfterPassing() {
        var state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        _ = ExitAlarmPlanner.apply(.regionEntered, to: &state, now: F.arrival(at: 2).addingTimeInterval(-400))
        let now = F.arrival(at: 2).addingTimeInterval(-390)
        _ = ExitAlarmPlanner.apply(.snooze(minutes: 60), to: &state, now: now)
        XCTAssertEqual(state.snoozedUntil, now.addingTimeInterval(15 * 60), "at most 15 minutes")
        var passed = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), departure: F.arrival(at: 2).addingTimeInterval(60), now: F.t0).state
        _ = ExitAlarmPlanner.apply(.timeAlarmRang, to: &passed, now: F.arrival(at: 2).addingTimeInterval(-300))
        _ = ExitAlarmPlanner.apply(.tick, to: &passed, now: F.arrival(at: 2).addingTimeInterval(200))
        XCTAssertNotNil(passed.passedAt)
        _ = ExitAlarmPlanner.apply(.snooze(minutes: 5), to: &passed, now: F.arrival(at: 2).addingTimeInterval(210))
        XCTAssertEqual(passed.phase, .fired, "no snooze for a passed stop")
    }

    func testAcknowledgeStopsEverythingAndCompletesAfterTheArrival() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        h.engine.acknowledge(id: spec.id)
        XCTAssertEqual(h.state(spec.id)?.phase, .acknowledged)
        XCTAssertTrue(h.scheduler.ringing.isEmpty)
        XCTAssertFalse(h.location.isUpdating, "no location once acknowledged")
        h.advance(to: F.arrival(at: 2).addingTimeInterval(601))
        XCTAssertEqual(h.state(spec.id)?.phase, .ended)
        XCTAssertEqual(h.state(spec.id)?.endReason, .completed)
    }

    func testCancelRemovesTheAlarmTheCircleAndTheUpdates() {
        let (h, spec) = armed()
        h.advance(to: F.t0)
        XCTAssertTrue(h.location.isUpdating)
        h.engine.cancel(id: spec.id)
        XCTAssertEqual(h.state(spec.id)?.phase, .ended)
        XCTAssertEqual(h.state(spec.id)?.endReason, .cancelledByUser)
        XCTAssertNil(h.scheduler.scheduled[spec.id])
        XCTAssertTrue(h.location.regions.isEmpty)
        XCTAssertFalse(h.location.isUpdating)
        h.play(F.fixes(toStop: 2))
        h.advance(to: F.arrival(at: 2))
        XCTAssertEqual(h.ringCount, 0, "a cancelled alarm never rings")
    }

    func testExpiryTenMinutesAfterTheArrival() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        h.advance(to: F.arrival(at: 2).addingTimeInterval(601))
        XCTAssertEqual(h.state(spec.id)?.endReason, .expired, "never acknowledged")
        XCTAssertFalse(h.location.isUpdating)
    }

    func testFollowEndedAndKillSwitchEndTheAlarms() {
        let (h, spec) = armed()
        h.engine.followEnded(tripID: spec.tripID)
        XCTAssertEqual(h.state(spec.id)?.endReason, .followEnded)
        XCTAssertNil(h.scheduler.scheduled[spec.id])

        let k = ExitAlarmHarness()
        k.engine.arm(spec, arrival: F.arrival(at: 2))
        k.engine.liveDataOff()
        XCTAssertEqual(k.state(spec.id)?.endReason, .killSwitch)
        XCTAssertTrue(k.scheduler.scheduled.isEmpty)
        XCTAssertTrue(k.location.regions.isEmpty)
    }

    func testFollowEndedAfterAcknowledgementIsCompleted() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        h.engine.acknowledge(id: spec.id)
        h.engine.followEnded(tripID: spec.tripID)
        XCTAssertEqual(h.state(spec.id)?.endReason, .completed)
    }

    // MARK: Two alarms

    func testTwoAlarmsOnOneRunAreIndependent() {
        let h = ExitAlarmHarness()
        let linz = F.spec(stop: 2, isTransfer: true)
        let amstetten = F.spec(stop: 3)
        h.engine.arm(linz, arrival: F.arrival(at: 2))
        h.engine.arm(amstetten, arrival: F.arrival(at: 3))
        XCTAssertEqual(h.scheduler.scheduled.count, 2)
        h.play(F.fixes(toStop: 3).filter { $0.time <= F.arrival(at: 2).addingTimeInterval(-250) })
        XCTAssertEqual(h.state(linz.id)?.phase, .fired)
        XCTAssertEqual(h.state(amstetten.id)?.phase == .fired, false)
        h.engine.acknowledge(id: linz.id)
        XCTAssertEqual(h.state(amstetten.id)?.phase == .armed || h.state(amstetten.id)?.phase == .approaching, true)
        XCTAssertNotNil(h.scheduler.scheduled[amstetten.id], "the second alarm is untouched")
        h.play(F.fixes(toStop: 3).filter { $0.time > h.now })
        XCTAssertEqual(h.state(amstetten.id)?.phase, .fired)
        XCTAssertEqual(h.ringCount, 2, "one ring per alarm")
        XCTAssertEqual(h.engine.book.needsAttention?.id, amstetten.id)
    }

    func testAtMostThreeActiveAlarms() {
        let h = ExitAlarmHarness()
        var results: [ExitAlarmBook.ArmResult] = []
        for stop in [1, 2, 3, 4] {
            results.append(h.engine.arm(F.spec(stop: stop), arrival: F.arrival(at: stop)))
        }
        XCTAssertEqual(results.last, .full)
        XCTAssertEqual(h.engine.book.active.count, 3)
        // The same stop again replaces, it does not count twice.
        XCTAssertEqual(h.engine.arm(F.spec(stop: 2, lead: .tenMinutes), arrival: F.arrival(at: 2)), .replaced(F.spec(stop: 2).id))
        XCTAssertEqual(h.engine.book.active.count, 3)
        XCTAssertEqual(h.scheduler.scheduled[F.spec(stop: 2).id], F.arrival(at: 2).addingTimeInterval(-600))
    }

    func testArmingAfterTheArrivalIsRefused() {
        let h = ExitAlarmHarness(start: F.arrival(at: 2).addingTimeInterval(700))
        XCTAssertEqual(h.engine.arm(F.spec(stop: 2), arrival: F.arrival(at: 2)), .arrivalOver)
        XCTAssertTrue(h.engine.book.alarms.isEmpty)
    }

    func testArmingWithTheMomentAlreadyPastRingsAtOnce() {
        let h = ExitAlarmHarness(start: F.arrival(at: 2).addingTimeInterval(-120))   // 2 minutes to go, lead 5
        h.engine.arm(F.spec(stop: 2), arrival: F.arrival(at: 2))
        XCTAssertEqual(h.state(F.spec(stop: 2).id)?.phase, .fired)
        XCTAssertEqual(h.scheduler.rings.count, 1)
    }

    // MARK: Without location, without the system alarm

    func testTimetableAloneRingsWithoutLocationPermission() {
        let h = ExitAlarmHarness(authorization: .denied)
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        XCTAssertTrue(h.location.regions.isEmpty, "no circle without permission")
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-290))
        XCTAssertEqual(h.state(spec.id)?.firedBy, .timetable)
        XCTAssertEqual(h.ringCount, 1)
    }

    func testRingsInTheAppWhenTheSchedulerCannotTakeTheAlarm() {
        let h = ExitAlarmHarness(authorization: .denied, kind: .none)
        h.scheduler.rejectsScheduling = true
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        XCTAssertNil(h.state(spec.id)?.scheduledTimeAlarm, "the scheduler said no: the planner stops counting on it")
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-290))
        XCTAssertEqual(h.scheduler.rings.count, 1, "no system alarm: the app rings it itself")
    }

    func testStoppingTheSystemAlarmOutsideTheAppAcknowledges() {
        let (h, spec) = armed()
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        h.scheduler.onEvent?(.stopped(spec.id))
        XCTAssertEqual(h.state(spec.id)?.phase, .acknowledged)
    }

    // MARK: Location window

    func testUpdatesOnlyRunWhileTheTripRuns() {
        let spec = F.spec(stop: 2)
        let early = ExitAlarmHarness(start: F.t0.addingTimeInterval(-3600))
        early.engine.arm(spec, arrival: F.arrival(at: 2))
        XCTAssertFalse(early.location.isUpdating, "an hour before the departure: only the circle")
        XCTAssertNotNil(early.location.regions[spec.id])
        early.advance(to: F.t0.addingTimeInterval(-590))
        XCTAssertTrue(early.location.isUpdating)
        early.advance(to: F.arrival(at: 2).addingTimeInterval(-290))
        early.engine.acknowledge(id: spec.id)
        XCTAssertFalse(early.location.isUpdating, "stops when the alarm is done")
    }

    func testWhenInUseKeepsTheCircleButTheWakeUpNeedsAlways() {
        XCTAssertTrue(ExitAlarmLocationAuthorization.always.allowsWakeUp)
        XCTAssertFalse(ExitAlarmLocationAuthorization.whenInUse.allowsWakeUp)
        XCTAssertTrue(ExitAlarmLocationAuthorization.whenInUse.allowsUpdates)
        XCTAssertFalse(ExitAlarmLocationAuthorization.denied.allowsUpdates)
        let h = ExitAlarmHarness(authorization: .notDetermined)
        h.engine.arm(F.spec(stop: 2), arrival: F.arrival(at: 2))
        XCTAssertFalse(h.location.isUpdating)
        XCTAssertTrue(h.location.regions.isEmpty)
        h.location.changeAuthorization(.always)   // the user chose "Immer" afterwards
        XCTAssertTrue(h.location.isUpdating)
        XCTAssertNotNil(h.location.regions[F.spec(stop: 2).id], "the circle is set when the permission arrives")
    }

    // MARK: Test alarm

    func testTestAlarmRingsInTenSecondsAndIsNotPartOfTheBook() {
        let h = ExitAlarmHarness()
        h.engine.scheduleTest(after: 10, soundKey: "standard")
        XCTAssertEqual(h.scheduler.scheduled[ExitAlarmEngine.testID], h.now.addingTimeInterval(10))
        XCTAssertTrue(h.engine.book.alarms.isEmpty)
        h.advance(to: h.now.addingTimeInterval(11))
        XCTAssertTrue(h.engine.testRang)
        h.engine.acknowledgeTest()
        XCTAssertFalse(h.engine.testRang)
        XCTAssertNil(h.engine.testAt)
    }

    // MARK: Privacy and persistence

    func testNothingOfThePositionIsSaved() throws {
        let (h, spec) = armed()
        h.play(F.fixes(toStop: 2).filter { $0.time <= F.t0.addingTimeInterval(1200) })
        XCTAssertNotNil(h.state(spec.id)?.lastFix)
        let data = try JSONEncoder().encode(h.engine.book)
        let json = String(decoding: data, as: UTF8.self)
        let fix = h.state(spec.id)!.lastFix!
        XCTAssertFalse(json.contains("lastFix"))
        XCTAssertFalse(json.contains("motion"))
        XCTAssertFalse(json.contains("remainingMeters"))
        XCTAssertFalse(json.contains("closestMeters"))
        XCTAssertFalse(json.contains(String(fix.coordinate.latitude)), "no coordinate of the user")
        let back = try JSONDecoder().decode(ExitAlarmBook.self, from: data)
        XCTAssertNil(back.state(id: spec.id)?.lastFix)
        XCTAssertEqual(back.state(id: spec.id)?.spec, spec)
    }

    func testRelaunchRestoresAlarmsCircleAndSchedule() {
        let (h, spec) = armed()
        let saved = h.persistence.stored
        XCTAssertNotNil(saved)
        // The system relaunches the app for the circle: a new engine, fresh fakes.
        let after = ExitAlarmHarness(start: F.t0.addingTimeInterval(1000), book: saved)
        after.engine.restore()
        XCTAssertEqual(after.engine.book.active.count, 1)
        XCTAssertNotNil(after.location.regions[spec.id])
        XCTAssertEqual(after.scheduler.scheduled[spec.id], F.arrival(at: 2).addingTimeInterval(-300))
        after.location.enterRegion(spec.id)   // the circle fires when the app is relaunched, near the stop
        after.advance(to: F.arrival(at: 2).addingTimeInterval(-600))
        after.location.enterRegion(spec.id)
        XCTAssertEqual(after.state(spec.id)?.firedBy, .geofence)
    }

    func testRestoreDropsOldEndedAlarms() {
        let (h, spec) = armed()
        h.engine.cancel(id: spec.id)
        let saved = h.persistence.stored
        let later = ExitAlarmHarness(start: h.now.addingTimeInterval(2 * 3600), book: saved)
        later.engine.restore()
        XCTAssertTrue(later.engine.book.alarms.isEmpty)
    }

    func testRegionFailureKeepsTheGPSPath() {
        let (h, spec) = armed()
        h.engine.locationProvider(regionMonitoringFailed: spec.id)
        XCTAssertTrue(h.engine.geofenceFailed)
        h.play(F.fixes(toStop: 2))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertEqual(h.ringCount, 1)
    }

    // MARK: Helpers

    /// A fresh answer for the run: only the Linz stop carries an arrival.
    private func stopovers(arrivalAtLinz: Date, delay: Int) -> [Stopover] {
        F.stops.enumerated().map { index, stop in
            let location = Location(lid: "lid-\(index)", name: stop.name, coordinate: stop.point)
            let planned = F.arrival(at: index)
            let event = StopEvent(planned: planned, realtime: index == 2 ? arrivalAtLinz : planned.addingTimeInterval(Double(delay)),
                                  prognosis: .prognosed)
            return Stopover(location: location, arrival: index == 0 ? nil : event, departure: event, index: index)
        }
    }
}
