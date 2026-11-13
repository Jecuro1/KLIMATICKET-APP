import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: the record that survives a relaunch (docs/CONNECTION_GUARD.md §7).
final class GuardRecordTests: XCTestCase {
    private func at(_ hhmm: String) -> Date { GuardFixture.at(hhmm) }

    func testRoundTrip() throws {
        let record = GuardFixture.record
        let data = try XCTUnwrap(record.encoded())
        XCTAssertEqual(GuardRecord.decode(data), record)
        XCTAssertEqual(record.version, 1)
    }

    func testSlimJourneyKeepsWhatTheGuardReads() {
        let slim = GuardFixture.record.journey
        XCTAssertEqual(slim.legs.count, 3)
        XCTAssertEqual(slim.legs.map(\.kind), [.ride, .walk, .ride], "walk legs stay")
        XCTAssertEqual(slim.refreshToken, "ctx-1")
        XCTAssertTrue(slim.legs.allSatisfy { $0.stopovers.isEmpty && $0.polyline == nil && $0.remarks.isEmpty })
        XCTAssertTrue(slim.remarks.isEmpty)
        XCTAssertNil(slim.shopURL)
        XCTAssertEqual(slim.legs[2].tripID, "trip-connection")
        XCTAssertEqual(slim.legs[0].arrival, GuardFixture.journey().legs[0].arrival)
    }

    func testGarbageAndOtherVersionsAreNil() throws {
        XCTAssertNil(GuardRecord.decode(Data("not json".utf8)))
        XCTAssertNil(GuardRecord.decode(Data("{}".utf8)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(GuardFixture.record.encoded())) as? [String: Any])
        object["version"] = 2
        XCTAssertNil(GuardRecord.decode(try JSONSerialization.data(withJSONObject: object)))
        object["version"] = 1
        object.removeValue(forKey: "journey")
        XCTAssertNil(GuardRecord.decode(try JSONSerialization.data(withJSONObject: object)))
    }

    func testExpiresAfterTwelveHours() {
        let record = GuardFixture.record   // created 13:00
        XCTAssertFalse(record.isExpired(now: GuardFixture.at("01:00", day: 13)))
        XCTAssertTrue(record.isExpired(now: GuardFixture.at("01:01", day: 13)))
    }

    func testBelongsToTheSameFollowWithTheSameChange() {
        let record = GuardFixture.record
        let transfer = FollowTransfer(stationName: "St.Pölten Hbf", plannedDeparture: at("14:40"), lineName: "REX 2")
        let same = LiveFollowTarget(tripID: "trip-feeder", lineName: "RJX 66", boardingStop: GuardFixture.wien,
                                    alightStop: GuardFixture.stPoelten, transfer: transfer)
        XCTAssertTrue(record.belongs(to: same))
        var radar = same
        radar.transfer = nil
        radar.alightStop = GuardFixture.linz
        XCTAssertFalse(record.belongs(to: radar), "a radar follow of the same trip has no change: the guard ends")
        var noTransfer = same
        noTransfer.transfer = nil
        XCTAssertFalse(record.belongs(to: noTransfer))
        var other = same
        other.tripID = "trip-other"
        XCTAssertFalse(record.belongs(to: other))
        var elsewhere = same
        elsewhere.alightStop = GuardFixture.linz
        elsewhere.transfer = FollowTransfer(stationName: "Linz/Donau Hbf", plannedDeparture: at("14:40"))
        XCTAssertFalse(record.belongs(to: elsewhere), "a change at another station")
    }

    func testOutlivesTheFollowStageButNotTheWindow() {
        var engine = GuardEngine(record: GuardFixture.record)
        _ = engine.followUpdated(GuardFixture.followSnapshot(delay: 0, now: at("14:41")), at: at("14:41"), now: at("14:41"))
        XCTAssertFalse(engine.hasEnded(now: at("14:41")), "the follow's stage is .arrived; the guard is not over")
        XCTAssertTrue(engine.hasEnded(now: at("14:47")))
    }

    func testUpdatedKeepsTheRecordSlim() {
        let updated = GuardFixture.record.updated(journey: GuardFixture.journey(feederDelay: 300), at: at("14:10"))
        XCTAssertEqual(updated.journeyAt, at("14:10"))
        XCTAssertTrue(updated.journey.legs.allSatisfy { $0.stopovers.isEmpty })
        XCTAssertEqual(updated.createdAt, GuardFixture.record.createdAt)
    }
}
