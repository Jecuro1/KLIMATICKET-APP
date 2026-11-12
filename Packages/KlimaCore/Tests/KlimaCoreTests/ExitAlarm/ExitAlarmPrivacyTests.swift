import XCTest
@testable import KlimaCore

/// Privacy review of the Aussteige-Wecker (docs/EXIT_ALARM.md §6): "Alle Daten löschen" really deletes, and "Genauer Standort: aus"
/// leaves the alarm to the timetable instead of promising a location it does not get.
final class ExitAlarmPrivacyTests: XCTestCase {
    typealias F = ExitAlarmFixtures

    // MARK: Delete everything

    func testResetEndsEveryAlarmAndLeavesNothingBehind() throws {
        let h = ExitAlarmHarness()
        let first = F.spec(stop: 2)
        let second = F.spec(stop: 3)
        h.engine.arm(first, arrival: F.arrival(at: 2))
        h.engine.arm(second, arrival: F.arrival(at: 3))
        h.engine.scheduleTest(after: 10, soundKey: "standard")
        h.advance(to: F.t0)   // the trip window is open: the updates run
        XCTAssertTrue(h.location.isUpdating)
        XCTAssertEqual(h.location.regions.count, 2)

        h.engine.reset()

        XCTAssertTrue(h.engine.book.alarms.isEmpty, "not even the ended ones stay")
        XCTAssertNil(h.engine.testAt)
        XCTAssertTrue(h.scheduler.scheduled.isEmpty, "no system alarm is left behind")
        XCTAssertTrue(h.scheduler.ringing.isEmpty)
        XCTAssertTrue(h.location.regions.isEmpty, "no circle is left behind")
        XCTAssertFalse(h.location.isUpdating, "no location once everything is deleted")
        let saved = try XCTUnwrap(h.persistence.stored)
        XCTAssertTrue(saved.alarms.isEmpty, "the saved book is empty")
        let json = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        XCTAssertFalse(json.contains("Linz"), "no stop name stays in what is saved")

        let rings = h.ringCount
        h.advance(to: F.arrival(at: 3).addingTimeInterval(60))
        XCTAssertEqual(h.ringCount, rings, "a deleted alarm never rings")
    }

    func testResetSilencesAnAlarmThatIsRinging() {
        let h = ExitAlarmHarness()
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        h.advance(to: F.arrival(at: 2).addingTimeInterval(-299))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertFalse(h.scheduler.ringing.isEmpty)

        h.engine.reset()

        XCTAssertTrue(h.scheduler.ringing.isEmpty, "the ringing alarm is stopped")
        XCTAssertNil(h.engine.book.needsAttention, "the full-screen moment goes away")
    }

    func testAfterResetARelaunchRestoresNothing() {
        let h = ExitAlarmHarness()
        h.engine.arm(F.spec(stop: 2), arrival: F.arrival(at: 2))
        h.engine.reset()
        let relaunched = ExitAlarmHarness(start: h.now.addingTimeInterval(60), book: h.persistence.stored)
        relaunched.engine.restore()
        XCTAssertTrue(relaunched.engine.book.alarms.isEmpty)
        XCTAssertTrue(relaunched.scheduler.scheduled.isEmpty)
        XCTAssertTrue(relaunched.location.regions.isEmpty)
    }

    func testResetOfAnEmptyBookIsHarmless() {
        let h = ExitAlarmHarness()
        h.engine.reset()
        XCTAssertTrue(h.engine.book.alarms.isEmpty)
        XCTAssertFalse(h.location.isUpdating)
        // New alarms can be armed afterwards.
        let spec = F.spec(stop: 2)
        XCTAssertEqual(h.engine.arm(spec, arrival: F.arrival(at: 2)), .armed(spec.id))
    }

    func testAnAlarmWithoutAnyArrivalDoesNotKeepTheLocationRunningForEver() {
        let h = ExitAlarmHarness()
        // The timetable gave no arrival, so nothing ends the alarm by the clock of the trip.
        let spec = ExitAlarmSpec(tripID: "trip-x", lineName: "RJX 66", stopID: "lid-x", stopName: "Linz Hbf",
                                 stopCoordinate: F.linz, path: F.path(to: 2), plannedArrival: nil, boardingDeparture: F.t0,
                                 lead: .fiveMinutes, createdAt: F.t0.addingTimeInterval(-600))
        h.engine.arm(spec, arrival: nil)
        h.advance(to: F.t0)
        XCTAssertTrue(h.location.isUpdating, "the trip window is open")
        // The circle rings it; nobody acknowledges.
        h.location.enterRegion(spec.id)
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        h.advance(to: h.now.addingTimeInterval(5 * 3600))
        XCTAssertEqual(h.state(spec.id)?.phase, .fired)
        XCTAssertTrue(h.location.isUpdating, "still within the limit")
        h.advance(to: h.now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(h.state(spec.id)?.phase, .ended)
        XCTAssertEqual(h.state(spec.id)?.endReason, .expired)
        XCTAssertFalse(h.location.isUpdating, "no location for an alarm that is over")
    }

    func testAnArmedAlarmWithoutAnyArrivalExpiresToo() {
        let h = ExitAlarmHarness()
        let spec = ExitAlarmSpec(tripID: "trip-y", lineName: "RJX 66", stopID: "lid-y", stopName: "Linz Hbf",
                                 stopCoordinate: F.linz, path: F.path(to: 2), plannedArrival: nil, boardingDeparture: F.t0,
                                 lead: .fiveMinutes, createdAt: F.t0.addingTimeInterval(-600))
        h.engine.arm(spec, arrival: nil)
        h.advance(to: F.t0.addingTimeInterval(7 * 3600))
        XCTAssertEqual(h.state(spec.id)?.phase, .ended)
        XCTAssertTrue(h.location.regions.isEmpty)
        XCTAssertFalse(h.location.isUpdating)
    }

    // MARK: Genauer Standort aus

    func testApproximateLocationIsReportedOnlyWhereThePermissionAllowsReading() {
        let h = ExitAlarmHarness(authorization: .always)
        XCTAssertFalse(h.engine.locationIsApproximate)
        h.location.isReducedAccuracy = true
        XCTAssertTrue(h.engine.locationIsApproximate)
        h.location.changeAuthorization(.whenInUse)
        XCTAssertTrue(h.engine.locationIsApproximate)
        h.location.changeAuthorization(.denied)
        XCTAssertFalse(h.engine.locationIsApproximate, "no permission: the question is a different one")
    }

    func testApproximateFixesDoNotRingAndTheTimetableCarriesTheAlarm() {
        let h = ExitAlarmHarness()
        h.location.isReducedAccuracy = true
        let spec = F.spec(stop: 2)
        h.engine.arm(spec, arrival: F.arrival(at: 2))
        // iOS delivers only places good to some kilometres: far too coarse for a stop that is 1.5 km wide.
        h.play(F.fixes(toStop: 2).map { fix in
            var coarse = fix
            coarse.horizontalAccuracy = 5_000
            return coarse
        })
        let state = h.state(spec.id)
        XCTAssertEqual(state?.phase, .fired)
        XCTAssertEqual(state?.firedBy, .timetable, "the fix was not believed, the timetable rang")
        XCTAssertNil(state?.lastFix, "an approximate fix is not even kept in memory")
        XCTAssertEqual(h.ringCount, 1)
    }

    // MARK: Honest words

    func testTheSleepPromiseStandsOnlyWhereItIsTrue() {
        let alarmKit = ExitAlarmPresentation.promise(kind: .alarmKit)
        XCTAssertTrue(alarmKit.contains("auch im Schlaf"))
        XCTAssertTrue(alarmKit.contains("lautlos"))
        let notifications = ExitAlarmPresentation.promise(kind: .notifications)
        XCTAssertFalse(notifications.contains("im Schlaf"), "a notification can be muted: no promise about sleep")
        XCTAssertTrue(notifications.contains("stumm"))
        let none = ExitAlarmPresentation.promise(kind: .none)
        XCTAssertFalse(none.contains("im Schlaf"))
        XCTAssertTrue(none.contains("Erlaubnis"))
        for kind in [ExitAlarmKind.alarmKit, .notifications, .none] {
            XCTAssertFalse(ExitAlarmPresentation.promise(kind: kind).contains("Sie "), "Du-Form")
        }
    }
}
