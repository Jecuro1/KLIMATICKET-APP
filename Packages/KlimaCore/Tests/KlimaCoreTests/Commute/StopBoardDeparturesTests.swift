import XCTest
@testable import KlimaCore

/// Haltestellen-Detail „Nächste Abfahrten“: the same gate as the Pendel-Modus (no live data → `consentRequired`, no request,
/// not even the station lookup), one board request with live data, and the eight departures still ahead.
final class StopBoardDeparturesTests: XCTestCase {
    private let now = CommuteFixtures.at(2026, 11, 13, 7, 30)

    func testNoConsentMeansNoRequest() async {
        let calls = LookupCounter()
        do {
            _ = try await StopBoardDepartures.load(timetable: nil, at: now) {
                await calls.bump()
                return CommuteFixtures.origin
            }
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error as? CommuteLiveError, .consentRequired)
        }
        let resolved = await calls.count
        XCTAssertEqual(resolved, 0, "not even the station lookup may run without consent")
    }

    func testWithLiveDataOneBoardRequestGoesOut() async throws {
        let timetable = RecordingTimetable()
        _ = try await StopBoardDepartures.load(timetable: timetable, at: now) { CommuteFixtures.origin }
        let boards = await timetable.boards
        let journeys = await timetable.queries
        XCTAssertEqual(boards.count, 1)
        XCTAssertTrue(journeys.isEmpty)
        XCTAssertEqual(boards.first?.kind, .departures)
        XCTAssertEqual(boards.first?.durationMinutes, StopBoardDepartures.minutes)
        XCTAssertEqual(boards.first?.maxResults, StopBoardDepartures.maxResults)
        XCTAssertEqual(boards.first?.date, now)
        XCTAssertEqual(boards.first?.station, CommuteFixtures.origin)
    }

    func testShowsEightDeparturesStillAhead() {
        var entries: [BoardEntry] = []
        // Two that left (one two minutes ago, one exactly a minute ago), then eleven ahead.
        entries.append(entry(-2, number: "1"))
        entries.append(entry(-1, number: "2"))
        for i in 0..<11 { entries.append(entry(3 + i * 5, number: "\(10 + i)")) }
        let snapshot = StopBoardDepartures.snapshot(Board(kind: .departures, entries: entries), now: now)
        XCTAssertEqual(snapshot.rows.count, StopBoardDepartures.shown)
        XCTAssertEqual(snapshot.rows.first?.lineTitle, "RJX 2", "a run stays until a minute after its departure")
        XCTAssertTrue(snapshot.hasMore)
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testLateRunStaysAndCancelledGoesByItsPlan() {
        let late = entry(-5, delay: 8, number: "late")          // planned 07:25, leaves 07:33
        let cancelled = entry(-3, cancelled: true, number: "gone") // planned 07:27, cancelled
        let snapshot = StopBoardDepartures.snapshot(Board(kind: .departures, entries: [late, cancelled]), now: now)
        XCTAssertEqual(snapshot.rows.map(\.lineTitle), ["RJX late"])
        XCTAssertFalse(snapshot.hasMore)
        XCTAssertEqual(snapshot.rows.first?.realtime.text, "07:33 +8")
    }

    func testRowsCarryPlatformCancellationAndRealtime() {
        let changed = entry(4, delay: 3, number: "5", platform: "2", changedTo: "3")
        let cancelled = entry(9, cancelled: true, number: "6")
        let plain = entry(12, delay: nil, number: "7")
        let snapshot = StopBoardDepartures.snapshot(Board(kind: .departures, entries: [changed, cancelled, plain]), now: now)
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows[0].platform?.changed, true)
        XCTAssertEqual(snapshot.rows[0].platform?.display, "3")
        XCTAssertTrue(snapshot.rows[1].isCancelled)
        XCTAssertEqual(snapshot.rows[2].realtime.state, .scheduled)
        XCTAssertTrue(snapshot.hasRealtime)
        XCTAssertEqual(StopBoardDepartures.dataAge(snapshot), "Stand 07:30 · Echtzeit")
    }

    func testPlanOnlyAnswerSaysFahrplan() {
        let snapshot = StopBoardDepartures.snapshot(Board(kind: .departures, entries: [entry(5, delay: nil, number: "9")]), now: now)
        XCTAssertFalse(snapshot.hasRealtime)
        XCTAssertEqual(StopBoardDepartures.dataAge(snapshot), "Stand 07:30 · Fahrplan")
    }

    func testRefreshIsAtMostOncePerMinute() {
        XCTAssertTrue(StopBoardDepartures.mayRefresh(lastFetch: nil, now: now))
        XCTAssertFalse(StopBoardDepartures.mayRefresh(lastFetch: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(StopBoardDepartures.mayRefresh(lastFetch: now.addingTimeInterval(-60), now: now))
    }

    // MARK: Builders

    private func entry(_ minutesFromNow: Int, delay: Int? = 0, cancelled: Bool = false, number: String, platform: String? = "4",
                       changedTo: String? = nil) -> BoardEntry {
        let planned = now.addingTimeInterval(Double(minutesFromNow) * 60)
        let event = StopEvent(planned: planned, realtime: cancelled ? nil : delay.map { planned.addingTimeInterval(Double($0) * 60) },
                              plannedPlatform: platform.map { Platform(text: $0, kind: .track) },
                              realtimePlatform: (changedTo ?? platform).map { Platform(text: $0, kind: .track) },
                              isCancelled: cancelled, platformChangeFlag: changedTo != nil)
        return BoardEntry(tripID: "trip|\(number)", line: CommuteFixtures.line("RJX \(number)", number: number), direction: "Wien Hbf",
                          stop: CommuteFixtures.origin, event: event)
    }
}

private actor LookupCounter {
    var count = 0
    func bump() { count += 1 }
}
