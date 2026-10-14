import XCTest
@testable import KlimaCore

/// Widget cache: freshness, filtering, timeline entries, heatmap grid, year teaser and the mapping of live answers
/// (docs/WIDGETS.md). Pure logic, no network.
final class WidgetCacheTests: XCTestCase {
    let cal = Calendar.vienna

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Freshness

    func testFreshnessWithoutCacheIsNone() {
        XCTAssertEqual(WidgetFreshness.of(fetchedAt: nil, now: at(2026, 10, 14)), .none)
    }

    func testFreshnessTurnsStaleAfterTwoHours() {
        let fetched = at(2026, 10, 14, 8, 0)
        XCTAssertEqual(WidgetFreshness.of(fetchedAt: fetched, now: at(2026, 10, 14, 9, 59)), .fresh)
        XCTAssertEqual(WidgetFreshness.of(fetchedAt: fetched, now: at(2026, 10, 14, 10, 1)), .stale)
    }

    func testFreshnessOfAFutureCacheIsFresh() {
        // A clock that went back must not hide the times.
        XCTAssertEqual(WidgetFreshness.of(fetchedAt: at(2026, 10, 14, 12, 0), now: at(2026, 10, 14, 11, 0)), .fresh)
    }

    // MARK: Filtering

    private func departure(_ id: String, _ h: Int, _ min: Int, realtimeDelay: Int? = nil, cancelled: Bool = false) -> WidgetDeparture {
        let planned = at(2026, 10, 14, h, min)
        let realtime = realtimeDelay.map { planned.addingTimeInterval(TimeInterval($0 * 60)) }
        return WidgetDeparture(id: id, planned: planned, realtime: realtime, lineName: "S 4", modeSymbol: "tram.fill",
                               isCancelled: cancelled)
    }

    func testUpcomingKeepsOrderAndDropsDepartedTrains() {
        let items = [departure("c", 14, 40), departure("a", 14, 5), departure("b", 14, 20)]
        let now = at(2026, 10, 14, 14, 10)
        XCTAssertEqual(WidgetFilter.upcoming(items, now: now, limit: 5).map(\.id), ["b", "c"])
    }

    func testUpcomingKeepsATrainThatLeftLessThanAMinuteAgo() {
        let items = [departure("a", 14, 0)]
        XCTAssertEqual(WidgetFilter.upcoming(items, now: at(2026, 10, 14, 14, 0).addingTimeInterval(30), limit: 3).map(\.id), ["a"])
        XCTAssertEqual(WidgetFilter.upcoming(items, now: at(2026, 10, 14, 14, 2), limit: 3).map(\.id), [])
    }

    func testUpcomingUsesTheRealtimeTime() {
        // 14:05 planned, 14:20 realtime: the 14:10 train is due first.
        let items = [departure("late", 14, 5, realtimeDelay: 15), departure("next", 14, 10)]
        XCTAssertEqual(WidgetFilter.upcoming(items, now: at(2026, 10, 14, 14, 0), limit: 2).map(\.id), ["next", "late"])
    }

    func testUpcomingRespectsTheLimit() {
        let items = (0..<8).map { departure("d\($0)", 15, $0 * 5) }
        XCTAssertEqual(WidgetFilter.upcoming(items, now: at(2026, 10, 14, 14, 0), limit: 3).count, 3)
        XCTAssertEqual(WidgetFilter.upcoming(items, now: at(2026, 10, 14, 14, 0), limit: 0).count, 0)
    }

    func testNextRunningSkipsCancelledDepartures() {
        let items = [departure("gone", 14, 5, cancelled: true), departure("ok", 14, 20)]
        XCTAssertEqual(WidgetFilter.nextRunning(items, now: at(2026, 10, 14, 14, 0)).map(\.id), ["ok"])
    }

    // MARK: Timeline entries

    func testEntryDatesAreNowThenOneMinuteBeforeEachDepartureThenStale() {
        let now = at(2026, 10, 14, 14, 0)
        let fetched = at(2026, 10, 14, 13, 30)
        let items = [departure("a", 14, 10), departure("b", 14, 25)]
        let dates = WidgetTimeline.entryDates(for: items, fetchedAt: fetched, now: now)
        XCTAssertEqual(dates, [now, at(2026, 10, 14, 14, 9), at(2026, 10, 14, 14, 24), at(2026, 10, 14, 15, 30)])
    }

    func testEntryDatesSkipPastDeparturesAndDuplicates() {
        let now = at(2026, 10, 14, 14, 0)
        let items = [departure("old", 13, 50), departure("now", 14, 1), departure("now2", 14, 1)]
        let dates = WidgetTimeline.entryDates(for: items, fetchedAt: nil, now: now)
        XCTAssertEqual(dates, [now])
    }

    func testEntryDatesRespectTheLimit() {
        let now = at(2026, 10, 14, 14, 0)
        let items = (1...20).map { departure("d\($0)", 14, $0 * 3) }
        let dates = WidgetTimeline.entryDates(for: items, fetchedAt: nil, now: now, limit: 6)
        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(dates, dates.sorted())
    }

    // MARK: Heatmap

    func testHeatmapGridStartsOnTheMondayElevenWeeksBack() {
        // 14 October 2026 is a Wednesday: the current week starts on Monday 12 October.
        let start = WidgetHeatmap.windowStart(for: at(2026, 10, 14), calendar: cal)
        XCTAssertEqual(start, at(2026, 7, 27, 0, 0))
        XCTAssertEqual(cal.component(.weekday, from: start), 2)   // Monday
        XCTAssertEqual(WidgetHeatmap.todayIndex(at(2026, 10, 14), calendar: cal), 77 + 2)
    }

    func testHeatmapLevelsPlaceTripsOnTheirDay() {
        let today = at(2026, 10, 14)
        let trips = [at(2026, 10, 14, 8), at(2026, 10, 14, 18), at(2026, 10, 12, 9), at(2026, 6, 1, 9), at(2026, 10, 20, 9)]
        let counts = WidgetHeatmap.counts(tripDates: trips, today: today, calendar: cal)
        XCTAssertEqual(counts.count, WidgetHeatmap.cellCount)
        let levels = WidgetHeatmap.levels(counts)
        // Two trips on today (the busiest day) -> level 4; one trip on Monday -> level 2 (1 of 2 is half the maximum).
        XCTAssertEqual(levels[WidgetHeatmap.todayIndex(today, calendar: cal)], 4)
        XCTAssertEqual(levels[77], 2)
        // Future days and trips outside the grid are not counted.
        XCTAssertEqual(levels.filter { $0 > 0 }.count, 2)
    }

    func testLevelsSplitTheMaximumIntoQuarters() {
        XCTAssertEqual(WidgetHeatmap.levels([0, 1, 2, 3, 4, 8]), [0, 1, 1, 2, 2, 4])
        XCTAssertEqual(WidgetHeatmap.levels([0, 0]), [0, 0])
    }

    func testCellLevelFollowsTheDayWhenTheSnapshotIsOlder() {
        // Levels stored on Tuesday 13 October share the grid of 14 October: the same cell is the same day.
        var levels = Array(repeating: UInt8(0), count: WidgetHeatmap.cellCount)
        levels[79] = 3   // Wednesday 14 October
        XCTAssertEqual(WidgetHeatmap.cell(79, stored: levels, fallback: 0, storedDay: at(2026, 10, 13), today: at(2026, 10, 14), calendar: cal), 3)
        // On a grid one week later (today 20 October) the same day is cell 72: the widget shifts by the grid start.
        XCTAssertEqual(WidgetHeatmap.cell(72, stored: levels, fallback: 0, storedDay: at(2026, 10, 13), today: at(2026, 10, 20), calendar: cal), 3)
        // Cells the stored grid does not cover (days after 13 October's grid) read as empty.
        XCTAssertEqual(WidgetHeatmap.cell(83, stored: levels, fallback: 0, storedDay: at(2026, 10, 13), today: at(2026, 10, 20), calendar: cal), 0)
    }

    // MARK: Year teaser

    func testYearReviewShowsInDecemberAndInTheLastDaysOfTheTicket() {
        let validUntil = at(2027, 1, 31)
        XCTAssertTrue(WidgetYearReview.isVisible(now: at(2026, 12, 3), validUntil: validUntil, calendar: cal))
        XCTAssertFalse(WidgetYearReview.isVisible(now: at(2026, 10, 14), validUntil: validUntil, calendar: cal))
        XCTAssertTrue(WidgetYearReview.isVisible(now: at(2026, 10, 14), validUntil: at(2026, 11, 10), calendar: cal))
        XCTAssertFalse(WidgetYearReview.isVisible(now: at(2026, 10, 14), validUntil: at(2026, 11, 20), calendar: cal))
    }

    // MARK: Mapping of live answers

    func testShortenedTextCutsAtAWordBoundary() {
        XCTAssertEqual(WidgetCacheBuilder.shortened("Kurzer   Text", limit: 40), "Kurzer Text")
        XCTAssertEqual(WidgetCacheBuilder.shortened("Eins zwei drei vier fünf", limit: 12), "Eins zwei…")
    }

    private func location(_ name: String, _ lid: String) -> Location {
        Location(lid: lid, name: name)
    }

    private func ride(_ id: String, line: String, mode: TransportMode, from: String, to: String, planned: Date,
                      delay: Int? = nil, remarks: [Remark] = [], cancelled: Bool = false, platform: String? = nil) -> Leg {
        let realtime = delay.map { planned.addingTimeInterval(TimeInterval($0 * 60)) }
        let dep = StopEvent(planned: planned, realtime: realtime,
                            plannedPlatform: platform.map { Platform(text: $0, kind: .track) }, isCancelled: cancelled)
        let arr = StopEvent(planned: planned.addingTimeInterval(3_600))
        return Leg(id: id, kind: .ride, origin: location(from, "L-\(from)"), destination: location(to, "L-\(to)"),
                   departure: dep, arrival: arr, line: Line(name: line, mode: mode), direction: "Innsbruck Hbf",
                   remarks: remarks, isCancelled: cancelled)
    }

    func testConnectionMapsFirstRideAndTrainEquipment() {
        let attribute = Remark(kind: .attribute, code: "OC", text: "WC rollstuhltauglich")
        let leg = ride("r1", line: "RJX 19960", mode: .train, from: "St. Anton am Arlberg", to: "Innsbruck Hbf",
                       planned: at(2026, 10, 14, 14, 32), delay: 4, remarks: [attribute], platform: "3")
        let journey = Journey(legs: [leg], durationSeconds: 5_400, changes: 0)
        let connection = try! XCTUnwrap(WidgetCacheBuilder.connection(from: journey))
        XCTAssertEqual(connection.lineName, "RJX 19960")
        XCTAssertEqual(connection.delayMinutes, 4)
        XCTAssertEqual(connection.departureTime, at(2026, 10, 14, 14, 36))
        XCTAssertEqual(connection.platform, "Gl. 3")
        XCTAssertEqual(connection.durationMinutes, 90)
        XCTAssertEqual(connection.trainAttributes, ["toilet"])
        XCTAssertFalse(connection.isCancelled)
    }

    func testConnectionsKeepTheNextOnes() {
        let early = Journey(legs: [ride("a", line: "S 4", mode: .sBahn, from: "A", to: "B", planned: at(2026, 10, 14, 13, 0))])
        let later = Journey(legs: [ride("b", line: "S 4", mode: .sBahn, from: "A", to: "B", planned: at(2026, 10, 14, 14, 30))])
        let page = JourneyPage(journeys: [early, later])
        let list = WidgetCacheBuilder.connections(from: page, now: at(2026, 10, 14, 14, 0))
        XCTAssertEqual(list.map(\.id), [later.id])
    }

    func testDeparturesCarryCancellationAndPlatformChange() {
        let planned = at(2026, 10, 14, 15, 0)
        let entry = BoardEntry(tripID: "t1", line: Line(name: "R 51", mode: .train), direction: "Bludenz",
                               stop: location("Bludenz", "L-B"),
                               event: StopEvent(planned: planned, realtime: nil, plannedPlatform: Platform(text: "2", kind: .track),
                                                realtimePlatform: Platform(text: "4", kind: .track), isCancelled: true,
                                                platformChangeFlag: true))
        let board = Board(kind: .departures, entries: [entry])
        let rows = WidgetCacheBuilder.departures(from: board, now: at(2026, 10, 14, 14, 50))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isCancelled)
        XCTAssertTrue(rows[0].platformChanged)
        XCTAssertEqual(rows[0].platform, "Gl. 4")
        XCTAssertEqual(rows[0].direction, "Bludenz")
    }

    func testDisruptionsKeepOnlyFollowedLinesAndValidNotices() {
        let now = at(2026, 10, 14, 9, 0)
        let relevant = Remark(kind: .disruption, id: "h1", title: "Baustelle", text: "Die S 4 fährt bis 14 Uhr nicht.",
                              validFrom: now, validUntil: at(2026, 10, 14, 14, 0), affectedLines: ["S 4"])
        let other = Remark(kind: .disruption, id: "h2", title: "Andere", text: "Nur die S 1.", affectedLines: ["S 1"])
        let expired = Remark(kind: .disruption, id: "h3", title: "Alt", text: "Vorbei.", validUntil: at(2026, 10, 13, 9, 0),
                             affectedLines: ["S 4"])
        let items = WidgetCacheBuilder.disruptions([relevant, other, expired], followedLines: ["S 4"], now: now)
        XCTAssertEqual(items.map(\.id), ["h1"])
        XCTAssertEqual(items.first?.lines, ["S 4"])
    }

    func testFacilitiesFromPlaceMarks() {
        let marks = [StopMark(kind: .bikeAndRide, confidence: 90), StopMark(kind: .barrierefrei, confidence: 90, isPartial: true)]
        XCTAssertEqual(WidgetCacheBuilder.facilities(marks), [.bikeRide, .barrierFreePartial])
        XCTAssertEqual(WidgetCacheBuilder.facilities([]), [])
    }

    func testFacilitiesAddOnlyWhatOpenStreetMapStates() {
        let equipment = [
            StopFacility(kind: .elevator, status: .present, count: 2),
            StopFacility(kind: .toilets, status: .limited),
            StopFacility(kind: .bicycleParking, status: .absent),
            StopFacility(kind: .ticketMachine, status: .present),
        ]
        XCTAssertEqual(WidgetCacheBuilder.facilities([StopMark(kind: .parkAndRide, confidence: 90)], equipment: equipment),
                       [.parkRide, .elevator, .toilets])
        // Nothing stated (`notRecorded`) and an explicit `absent` never become an item.
        XCTAssertEqual(WidgetCacheBuilder.facilities([], equipment: [StopFacility(kind: .elevator, status: .notRecorded),
                                                                   StopFacility(kind: .bicycleParking, status: .absent)]), [])
    }

    func testTrainWheelchairSpaceAndPartialToiletAreMapped() {
        let remarks = [Remark(kind: .attribute, code: "HS", text: "Rollstuhlstellplatz"),
                       Remark(kind: .attribute, code: "OG", text: "bedingt rollstuhltaugliches WC")]
        XCTAssertEqual(WidgetCacheBuilder.trainEquipment(remarks), ["figure.roll", "toilet"])
    }

    // MARK: Selection never shows an unfetched list as fresh

    func testUnfetchedRouteIsNotAFreshEmptyList() {
        let now = at(2026, 10, 14, 14, 0)
        let fetched = WidgetConnection(id: "c1", planned: at(2026, 10, 14, 14, 30), fromName: "A", toName: "B",
                                       lineName: "S 4", modeSymbol: "tram.fill")
        let cache = WidgetConnectionCache(fetchedAt: now, routes: ["fav-a": [fetched]])
        let missing = WidgetSelection.connections(cache, routeID: "fav-b", consent: .granted, now: now)
        XCTAssertEqual(missing.state, .empty)
        XCTAssertEqual(missing.items, [])
        XCTAssertEqual(WidgetSelection.connections(cache, routeID: "fav-b", consent: .declined, now: now).state, .off)
        // A fetched route with no journey left is a real, fresh "no connection".
        let empty = WidgetConnectionCache(fetchedAt: now, routes: ["fav-b": []])
        XCTAssertEqual(WidgetSelection.connections(empty, routeID: "fav-b", consent: .granted, now: now).state, .fresh(now))
    }

    func testUnfetchedStationIsNotAFreshEmptyList() {
        let now = at(2026, 10, 14, 14, 0)
        let board = WidgetDeparture(id: "d1", planned: at(2026, 10, 14, 14, 30), lineName: "R 51", modeSymbol: "tram.fill")
        let cache = WidgetDepartureCache(fetchedAt: now, stations: ["home": [board]])
        let missing = WidgetSelection.departures(cache, stationID: "other", consent: .granted, now: now)
        XCTAssertEqual(missing.state, .empty)
        XCTAssertEqual(missing.items, [])
        XCTAssertEqual(WidgetSelection.departures(cache, stationID: "home", consent: .granted, now: now).items.map(\.id), ["d1"])
    }

    // MARK: Codable

    func testConnectionCacheRoundTripsThroughJSON() throws {
        let connection = WidgetConnection(id: "j1", planned: at(2026, 10, 14, 14, 32), realtime: nil, arrival: at(2026, 10, 14, 16, 0),
                                          changes: 1, durationMinutes: 88, fromName: "St. Anton", toName: "Innsbruck",
                                          lineName: "RJX 19960", modeSymbol: "tram.fill", platform: "Gl. 3",
                                          trainAttributes: ["wifi"])
        let cache = WidgetConnectionCache(fetchedAt: at(2026, 10, 14, 14, 0), routes: ["fav": [connection]])
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(WidgetConnectionCache.self, from: data)
        XCTAssertEqual(decoded, cache)
        XCTAssertEqual(decoded.version, 1)
    }

    func testStationListIsCappedAtTen() {
        let stations = (1...14).map { WidgetStation(id: "s\($0)", name: "Station \($0)") }
        let list = WidgetStationList(updatedAt: at(2026, 10, 14, 9, 0), stations: stations)
        XCTAssertEqual(list.stations.count, WidgetStationList.maxCount)
    }
}
