import XCTest
@testable import KlimaCore

/// Live verfolgen: snapshot phases, next stops, change notices (pure, fixed clock). Times are Vienna wall clock on 2026-10-12.
final class LiveFollowTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { FollowFixture.at(hhmm) }
    private var target: LiveFollowTarget { FollowFixture.target() }
    private func trip(delayLinz: Int = 300, delayWien: Int = 360, platformAtBoarding: String = "5",
                      cancelled: Bool = false) -> TripDetails {
        FollowFixture.trip(delayLinz: delayLinz, delayWien: delayWien, platformAtBoarding: platformAtBoarding, cancelled: cancelled)
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
        t.boardingStop = FollowFixture.innsbruck
        t.alightStop = Location(lid: "A=1@L=9999@", kind: .station, extId: "9999", name: "Nirgendwo")
        let s = LiveFollow.snapshot(trip(), target: t, now: at("09:00"))
        XCTAssertEqual(s.boardingIndex, 0)
        XCTAssertEqual(s.alightIndex, 2)
    }

    func testDelayBelowThresholdHasNoNotices() {
        let before = LiveFollow.snapshot(trip(delayWien: 60), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 120), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("10:30")), [])
    }

    func testDelayCrossingThresholdNotifiesOnce() {
        let before = LiveFollow.snapshot(trip(delayWien: 120), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 420), target: target, now: at("10:30"))
        let notices = LiveFollow.notices(from: before, to: after, now: at("10:30"))
        XCTAssertEqual(notices, [.delay(minutes: 7, stop: "Wien Hbf")])
        // Same delay again: nothing new.
        XCTAssertEqual(LiveFollow.notices(from: after, to: after, now: at("10:30")), [])
    }

    func testRecoveryBelowThreshold() {
        let before = LiveFollow.snapshot(trip(delayWien: 420), target: target, now: at("10:00"))
        let after = LiveFollow.snapshot(trip(delayWien: 30), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("10:30")), [.delayRecovered(stop: "Wien Hbf")])
    }

    func testPlatformChangeAtBoarding() {
        let before = LiveFollow.snapshot(trip(platformAtBoarding: "5"), target: target, now: at("09:00"))
        let after = LiveFollow.snapshot(trip(platformAtBoarding: "6"), target: target, now: at("09:10"))
        XCTAssertEqual(LiveFollow.notices(from: before, to: after, now: at("09:10")),
                       [.platform(stop: "Salzburg Hbf", from: "5", to: "6", isBoarding: true)])
    }

    func testFirstAnswerIsSilentAboutChanges() {
        let s = LiveFollow.snapshot(trip(delayWien: 900), target: target, now: at("10:30"))
        XCTAssertEqual(LiveFollow.notices(from: nil, to: s, now: at("10:30")), [])
    }

    func testCancelledAndArrivedNotices() {
        let running = LiveFollow.snapshot(trip(), target: target, now: at("10:00"))
        let cancelled = LiveFollow.snapshot(trip(cancelled: true), target: target, now: at("10:05"))
        XCTAssertEqual(LiveFollow.notices(from: running, to: cancelled, now: at("10:05")), [.cancelled(stop: "Salzburg Hbf")])

        let arrived = LiveFollow.snapshot(trip(), target: target, now: at("12:10"))
        XCTAssertEqual(LiveFollow.notices(from: running, to: arrived, now: at("12:10")), [.arrived(stop: "Wien Hbf")])
    }
}
