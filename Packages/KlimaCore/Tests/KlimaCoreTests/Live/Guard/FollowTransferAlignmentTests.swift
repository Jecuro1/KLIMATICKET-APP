import XCTest
@testable import KlimaCore

/// Anschluss-Wächter §4.6: the follow's „Anschluss knapp“ notice counts with the guard's expected departure while it is fresh
/// and with the walk, in the whole minutes of the card and the detail. Old follow records decode unchanged.
final class FollowTransferAlignmentTests: XCTestCase {
    private func at(_ hhmm: String, second: Int = 0) -> Date { FollowFixture.at(hhmm, second: second) }

    /// RJX 66 arrives in Wien at 12:07 (planned 12:01, +6) while riding at 11:30.
    private func snapshot(_ transfer: FollowTransfer, now: String = "11:30") -> LiveFollowSnapshot {
        LiveFollow.snapshot(FollowFixture.trip(), target: FollowFixture.target(transfer: transfer), now: at(now))
    }

    func testOldRecordWithoutTheNewFieldsDecodes() throws {
        let json = #"{"stationName":"Wien Hbf","plannedDeparture":813500000,"lineName":"RJ 162"}"#
        let transfer = try JSONDecoder().decode(FollowTransfer.self, from: Data(json.utf8))
        XCTAssertEqual(transfer.stationName, "Wien Hbf")
        XCTAssertNil(transfer.expectedDeparture)
        XCTAssertNil(transfer.expectedAt)
        XCTAssertNil(transfer.walkMinutes)
        let target = #"{"tripID":"T1","lineName":"RJX 66","boardingStop":{"lid":"a","kind":"S","name":"A","products":0,"isMeta":false},"#
            + #""alightStop":{"lid":"b","kind":"S","name":"B","products":0,"isMeta":false},"transfer":\#(json)}"#
        XCTAssertNotNil(try JSONDecoder().decode(LiveFollowTarget.self, from: Data(target.utf8)).transfer)
        // And the new fields round-trip.
        let full = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"), expectedDeparture: at("12:14"),
                                  expectedAt: at("11:30"), walkMinutes: 2)
        XCTAssertEqual(try JSONDecoder().decode(FollowTransfer.self, from: JSONEncoder().encode(full)), full)
    }

    func testExpectedDepartureCountsWhileFresh() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"), expectedDeparture: at("12:15"),
                                      expectedAt: at("11:20"))
        let s = snapshot(transfer)
        XCTAssertEqual(s.transferBufferMinutes(now: at("11:30")), 8, "10 minutes old: still fresh")
        XCTAssertEqual(s.transferBufferMinutes(now: at("11:31")), 3, "11 minutes old: the planned departure")
        XCTAssertEqual(s.transferBufferMinutes(now: at("11:30", second: 1)), 3)
    }

    func testWalkIsSubtractedWhenKnown() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:20"), walkMinutes: 4)
        XCTAssertEqual(snapshot(transfer).transferBufferMinutes(now: at("11:30")), 9)
        XCTAssertEqual(snapshot(FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:20"))).transferBufferMinutes(now: at("11:30")), 13)
    }

    func testNoNoticeWhenTheExpectedDepartureMakesItSafe() {
        // Planned 12:10 (3 minutes), but the guard expects it at 12:12: five minutes, no notice.
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"), expectedDeparture: at("12:12"),
                                      expectedAt: at("11:29"))
        let s = snapshot(transfer)
        XCTAssertEqual(s.transferBufferMinutes(now: at("11:30")), 5)
        XCTAssertFalse(LiveFollow.notices(from: s, to: s, now: at("11:30")).contains { $0.kind == .tightTransfer })
        // Stale: the planned departure, the notice comes.
        XCTAssertEqual(LiveFollow.notices(from: s, to: s, now: at("11:45")).filter { $0.kind == .tightTransfer },
                       [.tightTransfer(station: "Wien Hbf", bufferMinutes: 3)])
    }

    func testFourMinutesFortySecondsIsFiveAndSilent() {
        // Arrival 12:07:00, departure 12:11:40: the card says „5 Min, Sicher“ – the notice stays silent (it said 4 before).
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:11", second: 40))
        let s = snapshot(transfer)
        XCTAssertEqual(s.transferBufferSeconds, 280, "the old seconds property is unchanged")
        XCTAssertEqual(s.transferBufferMinutes(now: at("11:30")), 5)
        XCTAssertFalse(LiveFollow.notices(from: s, to: s, now: at("11:30")).contains { $0.kind == .tightTransfer })
    }

    func testLiveActivityShowsTheExpectedDepartureWhileFresh() {
        let transfer = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"), expectedDeparture: at("12:14"),
                                      expectedAt: at("11:25"))
        XCTAssertEqual(FollowLiveState.make(from: snapshot(transfer), now: at("11:30")).transferDeparture, at("12:14"))
        XCTAssertEqual(FollowLiveState.make(from: snapshot(transfer), now: at("11:36")).transferDeparture, at("12:10"), "stale: planned")
        let plain = FollowTransfer(stationName: "Wien Hbf", plannedDeparture: at("12:10"))
        XCTAssertEqual(FollowLiveState.make(from: snapshot(plain), now: at("11:30")).transferDeparture, at("12:10"))
    }

    func testNoticeMinutesEqualTheCard() {
        // The same arrival and departure through the guard: one number.
        for departureSeconds in stride(from: 0, through: 9 * 60, by: 20) {
            let departure = at("12:07").addingTimeInterval(TimeInterval(departureSeconds))
            let s = snapshot(FollowTransfer(stationName: "Wien Hbf", plannedDeparture: departure, walkMinutes: 1))
            let card = TransferBuffer.minutes(arrival: at("12:07"), departure: departure, walkMinutes: 1)
            XCTAssertEqual(s.transferBufferMinutes(now: at("11:30")), card)
            let notice = LiveFollow.notices(from: s, to: s, now: at("11:30")).compactMap { n -> Int? in
                if case .tightTransfer(_, let minutes) = n { return minutes }
                return nil
            }
            XCTAssertEqual(notice, card < 5 ? [card] : [], "departure +\(departureSeconds) s")
        }
    }
}
