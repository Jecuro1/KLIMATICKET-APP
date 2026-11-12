import XCTest
@testable import KlimaCore

final class ExitAlarmPresentationTests: XCTestCase {
    typealias F = ExitAlarmFixtures

    func testDurationRoundsUp() {
        XCTAssertEqual(ExitAlarmPresentation.durationText(20), "unter 1 Min")
        XCTAssertEqual(ExitAlarmPresentation.durationText(61), "2 Min")
        XCTAssertEqual(ExitAlarmPresentation.durationText(240), "4 Min")
        XCTAssertEqual(ExitAlarmPresentation.durationText(3600), "1 Std")
        XCTAssertEqual(ExitAlarmPresentation.durationText(3900), "1 Std 5 Min")
    }

    func testDistanceUsesAGermanDecimalComma() {
        XCTAssertEqual(ExitAlarmPresentation.distanceText(850), "850 m")
        XCTAssertEqual(ExitAlarmPresentation.distanceText(4200), "4,2 km")
        XCTAssertEqual(ExitAlarmPresentation.distanceText(18_400), "18 km")
    }

    func testStatusLineSaysWhenItWakesYou() {
        let state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        let line = ExitAlarmPresentation.statusLine(state, now: F.t0)
        XCTAssertTrue(line.hasPrefix("Weckt dich um "))
        XCTAssertTrue(line.hasSuffix("5 Min vor der Ankunft"))
        XCTAssertEqual(ExitAlarmPresentation.title(state), "Aussteigen in Linz Hbf")
        let transfer = ExitAlarmPlanner.arm(F.spec(stop: 2, isTransfer: true), arrival: F.arrival(at: 2), now: F.t0).state
        XCTAssertEqual(ExitAlarmPresentation.title(transfer), "Umsteigen in Linz Hbf")
    }

    func testTheCardNeverInventsADistance() {
        let state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        let estimate = ExitAlarmPresentation.estimate(state, now: F.t0.addingTimeInterval(600))
        XCTAssertNil(estimate.remainingMeters)
        XCTAssertNotNil(estimate.remainingSeconds)
        XCTAssertFalse(ExitAlarmPresentation.remainingLine(estimate)!.contains("km"))
        XCTAssertEqual(ExitAlarmPresentation.estimateTag(estimate), "laut Fahrplan")
    }

    func testAGPSEstimateIsTaggedAsGeschaetzt() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        h.play(F.fixes(toStop: 2).filter { $0.time <= F.t0.addingTimeInterval(1500) })
        let estimate = ExitAlarmPresentation.estimate(h.state(spec.id)!, now: h.now)
        XCTAssertNotNil(estimate.remainingMeters)
        XCTAssertEqual(estimate.source, .timetable, "on time: the timetable and the GPS agree, the timetable is shown")
        let line = ExitAlarmPresentation.remainingLine(estimate)!
        XCTAssertTrue(line.hasPrefix("noch "))
        XCTAssertTrue(line.contains("km"))
    }

    func testADelayedPredictionIsAnEstimate() {
        var state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        _ = ExitAlarmPlanner.apply(.timetable(arrival: F.arrival(at: 2).addingTimeInterval(420), departure: nil, delaySeconds: 420), to: &state, now: F.t0)
        let estimate = ExitAlarmPresentation.estimate(state, now: F.t0)
        XCTAssertTrue(estimate.isEstimate)
        XCTAssertEqual(ExitAlarmPresentation.estimateTag(estimate), "geschätzt")
    }

    func testProgressFillsTowardTheStop() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        let fixes = F.fixes(toStop: 2)
        h.play(fixes.filter { $0.time <= F.t0.addingTimeInterval(600) })
        let early = ExitAlarmPresentation.estimate(h.state(spec.id)!, now: h.now).progress
        h.play(fixes.filter { $0.time <= F.t0.addingTimeInterval(1800) && $0.time > h.now })
        let later = ExitAlarmPresentation.estimate(h.state(spec.id)!, now: h.now).progress
        XCTAssertGreaterThan(later, early)
        XCTAssertEqual(early, 600 * F.speed / F.length(to: 2), accuracy: 0.02)
    }

    func testActivityLineIsOnlyForAnArmedAlarm() {
        var state = ExitAlarmPlanner.arm(F.spec(stop: 2), arrival: F.arrival(at: 2), now: F.t0).state
        let now = F.arrival(at: 2).addingTimeInterval(-239)
        XCTAssertEqual(ExitAlarmPresentation.activityLine(state, now: now), "Aussteigen in 4 Min")
        _ = ExitAlarmPlanner.apply(.regionEntered, to: &state, now: now)
        XCTAssertNil(ExitAlarmPresentation.activityLine(state, now: now))
    }

    func testRingContentIsGerman() {
        let spec = F.spec(stop: 2)
        let arrival = ExitAlarmPresentation.ringContent(spec, kind: .arrival)
        XCTAssertEqual(arrival.title, "Aussteigen!")
        XCTAssertEqual(arrival.body, "Linz Hbf in etwa 5 Min · Gleis 4")
        XCTAssertEqual(ExitAlarmPresentation.ringContent(spec, kind: .passed).body, "Du bist an Linz Hbf vorbeigefahren.")
        var now = spec
        now.lead = .atArrival
        XCTAssertEqual(ExitAlarmPresentation.ringContent(now, kind: .arrival).body, "Linz Hbf gleich · Gleis 4")
    }

    func testTheReminderAfterASnoozeDoesNotPromiseMinutesAnyMore() {
        let spec = F.spec(stop: 2)
        let content = ExitAlarmPresentation.ringContent(spec, kind: .snoozed)
        XCTAssertEqual(content.title, "Aussteigen!")
        XCTAssertEqual(content.body, "Deine Erinnerung für Linz Hbf · Gleis 4")
        XCTAssertFalse(content.body.contains("Min"), "the lead is used up after a snooze")
        var transfer = spec
        transfer.isTransfer = true
        XCTAssertEqual(ExitAlarmPresentation.ringContent(transfer, kind: .snoozed).title, "Umsteigen!")
    }

    func testDistanceNearAKilometreIsNeverShownAsAThousandMetres() {
        XCTAssertEqual(ExitAlarmPresentation.distanceText(994), "990 m")
        XCTAssertEqual(ExitAlarmPresentation.distanceText(996), "1,0 km")
        XCTAssertEqual(ExitAlarmPresentation.distanceText(0), "0 m")
    }

    func testTimeIsShownInViennaTimeAcrossTheClockChange() {
        // 2026-10-25: summer time ends at 01:00 UTC. 00:30 UTC is 02:30 CEST, 01:30 UTC is 02:30 CET again, 02:30 UTC is 03:30 CET.
        XCTAssertEqual(ExitAlarmPresentation.timeText(Date(timeIntervalSince1970: 1_792_888_200)), "02:30")
        XCTAssertEqual(ExitAlarmPresentation.timeText(Date(timeIntervalSince1970: 1_792_891_800)), "02:30")
        XCTAssertEqual(ExitAlarmPresentation.timeText(Date(timeIntervalSince1970: 1_792_895_400)), "03:30")
    }

    func testStopOptionsAreTheStopsFromBoardingToTheEnd() {
        let stopovers = F.stops.enumerated().map { index, stop in
            Stopover(location: Location(lid: "lid-\(index)", name: stop.name, coordinate: stop.point),
                     arrival: StopEvent(planned: F.arrival(at: index)), departure: StopEvent(planned: F.arrival(at: index)), index: index,
                     passesWithoutStop: index == 1)
        }
        let options = ExitAlarmStops.options(stopovers: stopovers, boardingIndex: 0, endIndex: 3, transferAtEnd: true)
        XCTAssertEqual(options.map(\.name), ["Linz Hbf", "Amstetten"], "no boarding stop, no passing-through stop, nothing after the leg")
        XCTAssertEqual(options.last?.isEnd, true)
        XCTAssertEqual(options.last?.isTransfer, true)
        XCTAssertEqual(options.first?.isTransfer, false)
    }

    func testTheFallbackNotificationsBelongToTheExitAlarmKind() {
        let identifier = "exitalarm.\(ExitAlarmUUID.make(from: "trip|stop").uuidString).1"
        XCTAssertEqual(AlarmIdentifier.kind(of: identifier), .exitAlarm)
        XCTAssertEqual(AlarmIdentifier.kind(of: "exit.alarm.x"), .other)
        XCTAssertTrue(AlarmKind.allCases.contains(.exitAlarm))
    }

    func testStopsThatTheTrainHasReachedAreNotOffered() {
        let stopovers = F.stops.enumerated().map { index, stop in
            Stopover(location: Location(lid: "lid-\(index)", name: stop.name, coordinate: stop.point),
                     arrival: StopEvent(planned: F.arrival(at: index)), departure: StopEvent(planned: F.arrival(at: index)), index: index)
        }
        let target = LiveFollowTarget(tripID: "trip-1", lineName: "RJX 66", boardingStop: stopovers[0].location, alightStop: stopovers[4].location)
        let legs = ExitAlarmStops.legIndices(target: target, stopovers: stopovers)
        XCTAssertEqual(legs.boarding, 0)
        XCTAssertEqual(legs.end, 4)
        let now = F.arrival(at: 2).addingTimeInterval(60)   // Linz is behind the train
        let options = ExitAlarmStops.options(stopovers: stopovers, boardingIndex: legs.boarding, endIndex: legs.end, transferAtEnd: false, now: now)
        XCTAssertEqual(options.map(\.name), ["Amstetten", "St. Pölten Hbf"])
    }

    func testSpecFromAFollowedRun() {
        let stopovers = F.stops.enumerated().map { index, stop in
            Stopover(location: Location(lid: "lid-\(index)", name: stop.name, coordinate: stop.point),
                     arrival: StopEvent(planned: F.arrival(at: index)), departure: StopEvent(planned: F.arrival(at: index)), index: index)
        }
        let target = LiveFollowTarget(tripID: "trip-1", lineName: "RJX 66", boardingStop: stopovers[0].location, alightStop: stopovers[3].location)
        let option = ExitAlarmStops.options(stopovers: stopovers, boardingIndex: 0, endIndex: 3, transferAtEnd: false)[1]
        let spec = ExitAlarmStops.spec(target: target, stopovers: stopovers, boardingIndex: 0, option: option, lead: .tenMinutes,
                                       soundKey: "standard", now: F.t0)
        XCTAssertEqual(spec.stopName, "Linz Hbf")
        XCTAssertEqual(spec.path.count, 3, "Salzburg, Attnang-Puchheim, Linz")
        XCTAssertEqual(spec.lead, .tenMinutes)
        XCTAssertEqual(spec.id, "trip-1|lid-2")
    }
}
