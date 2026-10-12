import XCTest
@testable import KlimaCore

/// Live verfolgen: snapshot phases, next stops, notices (pure, fixed clock). Times are Vienna wall clock on 2026-10-12.
final class LiveFollowTests: XCTestCase {
    private func at(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: parts[0], minute: parts[1]))!
    }

    private let salzburg = Location(lid: "A=1@L=8100108@", kind: .station, extId: "8100108", name: "Salzburg Hbf")
    private let linz = Location(lid: "A=1@L=8100173@", kind: .station, extId: "8100173", name: "Linz Hbf")
    private let wien = Location(lid: "A=1@L=8100003@", kind: .station, extId: "8100003", name: "Wien Hbf")
    private let innsbruck = Location(lid: "A=1@L=8100002@", kind: .station, extId: "8100002", name: "Innsbruck Hbf")

    private var target: LiveFollowTarget {
        LiveFollowTarget(tripID: "T1", lineName: "RJX 66", boardingStop: salzburg, alightStop: wien,
                         plannedDeparture: at("09:30"), plannedArrival: at("12:01"))
    }

    /// Salzburg 09:30 (platform 5) → Linz 10:47 (+5, platform 3→4) → Wien 12:01 (+6).
    private func trip(delayLinz: Int = 300, delayWien: Int = 360, platformAtBoarding: String = "5",
                      cancelled: Bool = false, updatedAt: Date? = nil) -> TripDetails {
        func ev(_ planned: String, _ delay: Int, platform: String? = nil, planned_: String? = nil) -> StopEvent {
            let p = at(planned)
            return StopEvent(planned: p, realtime: p.addingTimeInterval(TimeInterval(delay)),
                             plannedPlatform: planned_.map { Platform(text: $0) } ?? platform.map { Platform(text: $0) },
                             realtimePlatform: platform.map { Platform(text: $0) }, isCancelled: false, prognosis: .prognosed,
                             platformChangeFlag: false)
        }
        let stops = [
            Stopover(location: salzburg, departure: ev("09:30", 0, platform: platformAtBoarding), index: 0),
            Stopover(location: linz, arrival: ev("10:45", delayLinz - 300), departure: ev("10:47", delayLinz, platform: "4", planned_: "3"), index: 1),
            Stopover(location: wien, arrival: ev("12:01", delayWien, platform: "11"), index: 2),
        ]
        return TripDetails(tripID: "T1", stopovers: stops, isCancelled: cancelled, realtimeUpdatedAt: updatedAt)
    }

    func testUpcomingBeforeDeparture() {
        let s = LiveFollow.snapshot(trip(), target: target, now: at("09:00"))
        XCTAssertEqual(s.phase, .upcoming)
        XCTAssertNil(s.lastPassedIndex)
        XCTAssertEqual(s.nextStops(limit: 2).map(\.location.name), ["Salzburg Hbf", "Linz Hbf"])
        XCTAssertEqual(s.boardingIndex, 0)
        XCTAssertEqual(s.alightIndex, 2)
    }

    func testUnderwayShowsLastPassedAndNextStops() {
        let s = LiveFollow.snapshot(trip(), target: target, now: at("10:00"))
        XCTAssertEqual(s.phase, .underway)
        XCTAssertEqual(s.lastPassedIndex, 0)
        XCTAssertEqual(s.nextStops(limit: 5).map(\.location.name), ["Linz Hbf", "Wien Hbf"])
        XCTAssertEqual(s.delaySeconds, 360, "delay at the alighting stop")
    }

    func testArrivedAfterAlightingArrival() {
        let s = LiveFollow.snapshot(trip(), target: target, now: at("12:10"))
        XCTAssertEqual(s.phase, .arrived)
        XCTAssertEqual(s.alighting?.location.name, "Wien Hbf")
        XCTAssertTrue(s.nextStops(limit: 3).isEmpty)
    }

    func testCancelledWins() {
        let s = LiveFollow.snapshot(trip(cancelled: true), target: target, now: at("10:00"))
        XCTAssertEqual(s.phase, .cancelled)
    }

    func testUnknownStopsFallBackToRunEnds() {
        var t = target
        t.boardingStop = innsbruck
        t.alightStop = Location(lid: "A=1@L=9999@", kind: .station, extId: "9999", name: "Nirgendwo")
        let s = LiveFollow.snapshot(trip(), target: t, now: at("09:00"))
        XCTAssertEqual(s.boardingIndex, 0)
        XCTAssertEqual(s.alightIndex, 2)
    }

    func testDelayBelowThresholdHasNoNotices() {
        let before = LiveFollow.snapshot(trip(delayWien: 60), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 120), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after), [])
    }

    func testDelayCrossingThresholdNotifiesOnce() {
        let before = LiveFollow.snapshot(trip(delayWien: 120), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 420), target: target, now: at("10:30"))
        let notices = LiveFollow.notices(from: before, to: after)
        XCTAssertEqual(notices, [.delay(minutes: 7, stop: "Wien Hbf")])
        // Same delay again: nothing new.
        XCTAssertEqual(LiveFollow.notices(from: after, to: after), [])
    }

    func testRecoveryBelowThreshold() {
        let before = LiveFollow.snapshot(trip(delayWien: 420), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 30), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after), [.delayRecovered(stop: "Wien Hbf")])
    }

    func testPlatformChangeAtBoarding() {
        let before = LiveFollow.snapshot(trip(platformAtBoarding: "5"), target: target, now: at("09:00"))
        let after = LiveFollow.snapshot(trip(platformAtBoarding: "6"), target: target, now: at("09:10"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after),
                       [.platform(stop: "Salzburg Hbf", from: "5", to: "6", isBoarding: true)])
    }

    func testFirstAnswerIsSilent() {
        let s = LiveFollow.snapshot(trip(delayWien: 900), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: nil, to: s), [])
    }

    func testCancelledAndArrivedNotices() {
        let running = LiveFollow.snapshot(trip(), target: target, now: at("10:00"))
        let cancelled = LiveFollow.snapshot(trip(cancelled: true), target: target, now: at("10:05"))
        XCTAssertEqual(LiveFollow.notices(from: running, to: cancelled), [.cancelled(stop: "Salzburg Hbf")])

        let arrived = LiveFollow.snapshot(trip(), target: target, now: at("12:10"))
        XCTAssertEqual(LiveFollow.notices(from: running, to: arrived), [.arrived(stop: "Wien Hbf")])
    }
}
