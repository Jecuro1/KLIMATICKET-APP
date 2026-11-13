import XCTest
@testable import KlimaCore

/// Pendel-Modus: without live data (consent, switch, kill switch, offline – `LiveDataService.timetable` is nil) the commute
/// search throws `consentRequired` and makes no request at all; with it, exactly one TripSearch goes out.
final class CommuteSearchGateTests: XCTestCase {
    func testNoConsentMeansNoRequest() async {
        let calls = CallCounter()
        do {
            _ = try await CommuteSearch.connections(timetable: nil, at: Date()) {
                await calls.bump()
                return (CommuteFixtures.origin, CommuteFixtures.destination)
            }
            XCTFail("must throw")
        } catch {
            XCTAssertEqual(error as? CommuteLiveError, .consentRequired)
        }
        let resolved = await calls.count
        XCTAssertEqual(resolved, 0, "not even the station lookup may run without consent")
    }

    func testWithLiveDataOneSearchGoesOut() async throws {
        let timetable = RecordingTimetable()
        let date = CommuteFixtures.at(2026, 11, 2, 7, 0)
        _ = try await CommuteSearch.connections(timetable: timetable, at: date) { (CommuteFixtures.origin, CommuteFixtures.destination) }
        let queries = await timetable.queries
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(queries.first?.results, CommuteSearch.results)
        XCTAssertEqual(queries.first?.includeStopovers, false)
        XCTAssertEqual(queries.first?.includePolyline, false)
        XCTAssertEqual(queries.first?.date, date)
    }

    func testRefreshIsAtMostOncePerMinute() {
        let t = Date()
        XCTAssertTrue(CommuteSearch.mayRefresh(lastFetch: nil, now: t))
        XCTAssertFalse(CommuteSearch.mayRefresh(lastFetch: t.addingTimeInterval(-59), now: t))
        XCTAssertTrue(CommuteSearch.mayRefresh(lastFetch: t.addingTimeInterval(-60), now: t))
    }
}

private actor CallCounter {
    var count = 0
    func bump() { count += 1 }
}

/// Records the journey queries; every other call fails the test.
actor RecordingTimetable: TimetableService {
    var queries: [JourneyQuery] = []
    var boards: [BoardQuery] = []

    func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location] { unexpected() }
    func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location] { unexpected() }
    func journeys(_ query: JourneyQuery) async throws -> JourneyPage {
        queries.append(query)
        return JourneyPage(journeys: [])
    }
    func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>] { unexpected() }
    func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey { unexpected() }
    func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>] { unexpected() }
    func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails { unexpected() }
    func board(_ query: BoardQuery) async throws -> Board {
        boards.append(query)
        return Board(kind: query.kind, entries: [])
    }
    func remarks(_ query: RemarksQuery) async throws -> [Remark] { unexpected() }

    private func unexpected() -> Never { fatalError("unexpected timetable call") }
}
