import XCTest
@testable import KlimaCore

/// SPEC §C3.6 / §D2 WP-C 8: Innsbruck → Lech (RJX 19960 11:16 → Langen 12:32, Bus 750 13:10 → Lech 13:32).
final class LiveJourneySnapshotTests: XCTestCase {
    func journey() throws -> Journey { try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0] }

    func testPhasesAtFakeTimes() throws {
        let j = try journey()
        let quote = PriceQuote(amountEUR: 29.70, source: .liveOebb, travelDate: Vienna.date("2026-10-09 11:16"), explanation: "")

        let before = LiveJourneySnapshotBuilder.make(journey: j, quote: quote, now: Vienna.date("2026-10-09 11:00"))
        XCTAssertEqual(before.phase, .beforeDeparture)
        XCTAssertEqual(before.nextEventTitle, "Abfahrt in 16 min · Gl. 3")
        XCTAssertEqual(before.nextEventTime, Vienna.date("2026-10-09 11:16"))
        XCTAssertEqual(before.nextEventPlatform, "3")
        XCTAssertEqual(before.nextEventRealtime.state, .onTime)
        XCTAssertEqual(before.currentLine, "RJX 19960")
        XCTAssertEqual(before.currentMode, .train)
        XCTAssertEqual(before.progress, 0)
        XCTAssertEqual(before.originName, "Innsbruck Hbf")
        XCTAssertEqual(before.destinationName, "Lech Rüfiplatz")
        XCTAssertEqual(before.regularPriceEUR, 29.70)
        XCTAssertEqual(before.arrival, Vienna.date("2026-10-09 13:32"))
        XCTAssertEqual(before.staleAfter, Vienna.date("2026-10-09 11:18"))
        XCTAssertEqual(before.updatedAt, Vienna.date("2026-10-09 11:00"))

        let riding = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 11:40"))
        XCTAssertEqual(riding.phase, .riding)
        XCTAssertEqual(riding.nextEventTitle, "Umsteigen in Langen am Arlberg")
        XCTAssertEqual(riding.nextEventTime, Vienna.date("2026-10-09 13:10"))
        XCTAssertEqual(riding.currentLine, "RJX 19960")
        XCTAssertEqual(riding.transfer?.text, "38 min Umstiegszeit")
        XCTAssertEqual(riding.transfer?.risk, .ok)
        XCTAssertEqual(riding.staleAfter, Vienna.date("2026-10-09 13:12"))
        XCTAssertNil(riding.regularPriceEUR)

        let transferring = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 12:40"))
        XCTAssertEqual(transferring.phase, .transferring)
        XCTAssertEqual(transferring.nextEventTitle, "Umsteigen in Langen am Arlberg")
        XCTAssertEqual(transferring.currentLine, "Bus 750")
        XCTAssertEqual(transferring.currentMode, .bus)
        XCTAssertEqual(transferring.nextEventRealtime.state, .scheduled)
        XCTAssertNotNil(transferring.transfer)

        let onBus = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 13:20"))
        XCTAssertEqual(onBus.phase, .riding)
        XCTAssertEqual(onBus.nextEventTitle, "Ankunft Lech Rüfiplatz 13:32")
        XCTAssertNil(onBus.transfer)

        let arrived = LiveJourneySnapshotBuilder.make(journey: j, quote: quote, now: Vienna.date("2026-10-09 13:32"))
        XCTAssertEqual(arrived.phase, .arrived)
        XCTAssertEqual(arrived.nextEventTitle, "Angekommen in Lech Rüfiplatz")
        XCTAssertEqual(arrived.progress, 1)
        XCTAssertNil(arrived.staleAfter)
        XCTAssertEqual(LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 13:31")).phase, .arrived,
                       "one minute before the final arrival counts as arrived")
    }

    func testProgressIsMonotonicAndClamped() throws {
        let j = try journey()
        var last = -1.0
        var t = Vienna.date("2026-10-09 10:30")
        while t <= Vienna.date("2026-10-09 14:00") {
            let s = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: t)
            XCTAssertGreaterThanOrEqual(s.progress, last, "\(t)")
            XCTAssertTrue((0...1).contains(s.progress))
            last = s.progress
            t = t.addingTimeInterval(60)
        }
        XCTAssertEqual(last, 1)
        let mid = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 12:24"))
        XCTAssertEqual(mid.progress, 68.0 / 136.0, accuracy: 0.0001)
    }

    func testRealtimeAwareAndCancelled() throws {
        var j = try journey()
        // 7 min late at Innsbruck: still before departure at 11:20.
        j.legs[0].departure.realtime = Vienna.date("2026-10-09 11:23")
        let late = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 11:20"))
        XCTAssertEqual(late.phase, .beforeDeparture)
        XCTAssertEqual(late.nextEventTitle, "Abfahrt in 3 min · Gl. 3")
        XCTAssertEqual(late.nextEventRealtime.state, .veryLate)

        j.legs[2].isCancelled = true
        let cancelled = LiveJourneySnapshotBuilder.make(journey: j, quote: nil, now: Vienna.date("2026-10-09 11:20"))
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertEqual(cancelled.nextEventTitle, "Bus 750 fällt aus")
        XCTAssertEqual(cancelled.nextEventRealtime.state, .cancelled)
        XCTAssertNil(cancelled.staleAfter)
    }
}
