import XCTest
@testable import KlimaCore

/// Pure logic of the Fahrplan results: sorting, CO₂, walking filter, paging, .ics, share text, links and reminders.
final class PlannerLogicTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    private func loc(_ name: String, _ lat: Double, _ lon: Double, extId: String) -> Location {
        Location(lid: "A=1@L=\(extId)@", kind: .station, extId: extId, name: name, coordinate: GeoPoint(latitude: lat, longitude: lon))
    }

    private var ibk: Location { loc("Innsbruck Hauptbahnhof", 47.2633, 11.4010, extId: "8100108") }
    private var landeck: Location { loc("Landeck-Zams Bahnhof", 47.1396, 10.5667, extId: "8100035") }
    private var anton: Location { loc("St.Anton am Arlberg Bahnhof", 47.1285, 10.2685, extId: "8100002") }
    private var rjx: Line { Line(name: "RJX 19910", category: "RJX", categoryShort: "RJX", trainNumber: "19910", productClass: 1, mode: .train) }
    private var bus: Line { Line(name: "Bus 760", category: "Bus", categoryShort: "Bus", lineNumber: "760", trainNumber: "760", productClass: 64, mode: .bus) }

    private func ride(_ id: String, _ from: Location, _ to: Location, line: Line, stops: [Location], startMinute: Double, minutes: Int,
                      polyline: [GeoPoint]? = nil) -> Leg {
        let dep = t0.addingTimeInterval(startMinute * 60), arr = dep.addingTimeInterval(Double(minutes) * 60)
        let stopovers = stops.enumerated().map { i, location in
            Stopover(location: location, arrival: i == 0 ? nil : StopEvent(planned: dep), departure: i == stops.count - 1 ? nil : StopEvent(planned: dep), index: i)
        }
        return Leg(id: id, kind: .ride, origin: from, destination: to, departure: StopEvent(planned: dep), arrival: StopEvent(planned: arr),
                   line: line, tripID: id, stopovers: stopovers, polyline: polyline)
    }

    private func walk(_ id: String, meters: Int, at minute: Double) -> Leg {
        let dep = t0.addingTimeInterval(minute * 60)
        return Leg(id: id, kind: .walk, origin: landeck, destination: landeck, departure: StopEvent(planned: dep),
                   arrival: StopEvent(planned: dep.addingTimeInterval(240)), walkDistanceMeters: meters, walkDurationSeconds: 240)
    }

    /// Innsbruck → Landeck (train, 60 min), then a walk and a bus to St. Anton.
    private var connection: Journey {
        let train = ride("r1", ibk, landeck, line: rjx, stops: [ibk, landeck], startMinute: 0, minutes: 60)
        let bus = ride("r2", landeck, anton, line: bus, stops: [landeck, anton], startMinute: 75, minutes: 30)
        return Journey(legs: [train, walk("w", meters: 320, at: 60), bus], durationSeconds: 105 * 60, changes: 1, refreshToken: "t")
    }

    // MARK: Sorting

    private struct Row: SortableConnection, Equatable {
        var id: String
        var sortFacts: ConnectionSortFacts
    }

    private func row(_ id: String, minutes: Int, changes: Int = 0, start: Double = 0, price: Double? = nil, co2: Double? = nil) -> Row {
        Row(id: id, sortFacts: ConnectionSortFacts(departure: t0.addingTimeInterval(start * 60), durationSeconds: minutes * 60,
                                                   changes: changes, priceEUR: price, co2Kg: co2))
    }

    private func ids(_ rows: [Row]) -> [String] { rows.map(\.id) }

    func testFastestBreaksTiesByDeparture() {
        let rows = [row("a", minutes: 60), row("b", minutes: 45, start: 600), row("c", minutes: 45, start: 540)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .fastest)), ["c", "b", "a"])
    }

    func testFewestChangesComesBeforeDuration() {
        let rows = [row("direct-slow", minutes: 120, changes: 0), row("one-change-fast", minutes: 50, changes: 1)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .fewestChanges)), ["direct-slow", "one-change-fast"])
    }

    func testCheapestPutsUnknownPricesLast() {
        let rows = [row("none", minutes: 30), row("dear", minutes: 30, price: 29.7), row("cheap", minutes: 90, price: 9.9)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .cheapest)), ["cheap", "dear", "none"])
    }

    func testLowestCO2PutsUnknownLast() {
        let rows = [row("unknown", minutes: 20), row("dirty", minutes: 20, co2: 4.2), row("clean", minutes: 90, co2: 0.6)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .lowestCO2)), ["clean", "dirty", "unknown"])
    }

    func testDepartureOrderIsTheTimetable() {
        let rows = [row("late", minutes: 10, start: 600), row("early-long", minutes: 90, start: 60), row("early-short", minutes: 30, start: 60)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .departure)), ["early-short", "early-long", "late"])
    }

    func testEqualKeysKeepIncomingOrder() {
        let rows = [row("first", minutes: 30), row("second", minutes: 30), row("third", minutes: 30)]
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .fastest)), ["first", "second", "third"])
        XCTAssertEqual(ids(ConnectionSorting.sorted(rows, by: .cheapest)), ["first", "second", "third"])
    }

    func testSortEnumsHaveLabelsAndCodableRawValues() {
        XCTAssertEqual(ConnectionSort.allCases.map(\.rawValue), ["departure", "fastest", "fewestChanges", "cheapest", "lowestCO2"])
        XCTAssertEqual(ConnectionSort.cheapest.title, "Günstigste")
        XCTAssertTrue(ConnectionSort.cheapest.caption.contains("Normalpreis"))
        XCTAssertEqual(try JSONDecoder().decode(ConnectionSort.self, from: JSONEncoder().encode(ConnectionSort.lowestCO2)), .lowestCO2)
    }

    // MARK: CO₂

    func testRideDistancePrefersPolylineThenStopovers() {
        let polyline = [GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0, longitude: 1)]
        let withLine = ride("p", ibk, landeck, line: rjx, stops: [ibk, landeck], startMinute: 0, minutes: 60, polyline: polyline)
        XCTAssertEqual(PlannerEmissions.rideDistanceKm(withLine) ?? 0, GeoPoint(latitude: 0, longitude: 0).distanceKm(to: GeoPoint(latitude: 0, longitude: 1)), accuracy: 0.001)

        let stops = ride("s", ibk, anton, line: rjx, stops: [ibk, landeck, anton], startMinute: 0, minutes: 90)
        let expected = ibk.coordinate!.distanceKm(to: landeck.coordinate!) + landeck.coordinate!.distanceKm(to: anton.coordinate!)
        XCTAssertEqual(PlannerEmissions.rideDistanceKm(stops) ?? 0, expected, accuracy: 0.001)
    }

    func testTrainCO2UsesTrainFactorAndWalksAddNothing() {
        let journey = connection
        let train = journey.legs[0], bus = journey.legs[2]
        let expected = (PlannerEmissions.rideDistanceKm(train) ?? 0) * EmissionFactors.fallback.train / 1000
            + (PlannerEmissions.rideDistanceKm(bus) ?? 0) * EmissionFactors.fallback.bus / 1000
        XCTAssertEqual(PlannerEmissions.co2Kg(journey) ?? -1, expected, accuracy: 0.0001)
        XCTAssertGreaterThan(PlannerEmissions.co2Kg(journey) ?? 0, 0)
    }

    func testWalkOnlyIsZeroAndMissingCoordinatesGiveNoNumber() {
        let walkOnly = Journey(legs: [walk("w", meters: 500, at: 0)])
        XCTAssertEqual(PlannerEmissions.co2Kg(walkOnly), 0)

        let nowhere = Location(lid: "A=1@L=9@", kind: .station, extId: "9", name: "Ohne Koordinaten")
        let leg = Leg(id: "x", kind: .ride, origin: nowhere, destination: nowhere, departure: StopEvent(planned: t0),
                      arrival: StopEvent(planned: t0.addingTimeInterval(600)), line: rjx)
        XCTAssertNil(PlannerEmissions.co2Kg(Journey(legs: [leg])))
    }

    func testSortFactsUseTheDurationOfTheJourney() {
        let facts = PlannerResults.sortFacts(connection, priceEUR: 22.5)
        XCTAssertEqual(facts.durationSeconds, 105 * 60)
        XCTAssertEqual(facts.changes, 1)
        XCTAssertEqual(facts.priceEUR, 22.5)
        XCTAssertNotNil(facts.co2Kg)
        XCTAssertEqual(facts.departure, t0)
    }

    // MARK: Walking and paging

    func testWalkingLimitCountsFootpathsAndKeepsUnknownWalks() {
        XCTAssertEqual(PlannerResults.walkMeters(connection), 320)
        let short = connection
        var long = connection
        long.legs[1] = walk("w2", meters: 900, at: 60)
        XCTAssertEqual(PlannerResults.withinWalk([short, long], maxMeters: 500).map(\.id), [short.id])
        XCTAssertEqual(PlannerResults.withinWalk([short, long], maxMeters: nil).count, 2)
        XCTAssertEqual(PlannerResults.withinWalk([short, long], maxMeters: 900).count, 2)
    }

    func testPagingMergeDedupesAndKeepsDepartureOrder() {
        func journey(_ id: String, minute: Double) -> Journey {
            let dep = t0.addingTimeInterval(minute * 60)
            let leg = Leg(id: id, kind: .ride, origin: ibk, destination: landeck, departure: StopEvent(planned: dep),
                          arrival: StopEvent(planned: dep.addingTimeInterval(3600)), line: rjx)
            return Journey(legs: [leg], refreshToken: nil)
        }
        let a = journey("a", minute: 600), b = journey("b", minute: 660), early = journey("early", minute: 540), c = journey("c", minute: 720)
        let merged = PlannerResults.merge([a, b], page: [b, early, c])
        XCTAssertEqual(merged.map(\.id), [early, a, b, c].map(\.id), "departure order, the repeated b once")
        XCTAssertEqual(merged.count, 4)
        XCTAssertEqual(PlannerResults.merge([], page: []).count, 0)
    }

    // MARK: Calendar

    func testIcsHasUtcTimesAlarmAndEscapedText() throws {
        let stamp = t0
        let text = try XCTUnwrap(PlannerExport.ics(connection, uid: "uid-1@klimabilanz", stamp: stamp, alarmMinutes: 10))
        XCTAssertTrue(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(text.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertTrue(text.contains("UID:uid-1@klimabilanz"))
        XCTAssertNotNil(text.range(of: #"DTSTART:\d{8}T\d{6}Z"#, options: .regularExpression))
        XCTAssertTrue(text.contains("BEGIN:VALARM"))
        XCTAssertTrue(text.contains("TRIGGER:-PT10M"))
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
        XCTAssertTrue(unfolded.contains("Fußweg (320 m)"), "the walk is described")
        XCTAssertTrue(unfolded.contains("RJX 19910"))
        for physical in text.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(physical.utf8.count, 75, "line too long: \(physical)")
        }
    }

    func testIcsWithoutAlarmAndWithoutTimesIsNil() {
        let text = PlannerExport.ics(connection, uid: "u", stamp: t0, alarmMinutes: nil)
        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("BEGIN:VALARM") ?? true)
        let noTimes = Journey(legs: [Leg(id: "n", kind: .ride, origin: ibk, destination: landeck, departure: StopEvent(), arrival: StopEvent(), line: rjx)])
        XCTAssertNil(PlannerExport.ics(noTimes, uid: "u", stamp: t0))
    }

    func testIcsEscapesCommasSemicolonsAndBackslashes() {
        XCTAssertEqual(PlannerExport.escape("Wien, Hbf; Gleis\\2\nneu"), "Wien\\, Hbf\\; Gleis\\\\2\\nneu")
    }

    func testIcsFoldingNeverSplitsCharacters() {
        let long = String(repeating: "ö", count: 60)
        let folded = PlannerExport.fold("SUMMARY:" + long)
        for physical in folded.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(physical.utf8.count, 75)
        }
        XCTAssertEqual(folded.components(separatedBy: "\r\n").map { $0.hasPrefix(" ") ? String($0.dropFirst()) : $0 }.joined(), "SUMMARY:" + long)
    }

    func testIcsFileNameIsSafe() {
        let name = PlannerExport.icsFileName(connection)
        XCTAssertTrue(name.hasSuffix(".ics"))
        XCTAssertFalse(name.contains("/"))
    }

    // MARK: Share text

    func testShareTextNamesRouteTimesChangesAndLines() {
        let text = PlannerExport.shareText(connection)
        XCTAssertTrue(text.contains("→"))
        XCTAssertTrue(text.contains("1 Umstieg"))
        XCTAssertTrue(text.contains("RJX 19910"))
        XCTAssertTrue(text.contains("Fußweg 320 m"))
        XCTAssertTrue(text.contains("–"), "a range of times")
    }

    func testShareTextForDirectTrip() {
        let direct = Journey(legs: [ride("d", ibk, landeck, line: rjx, stops: [ibk, landeck], startMinute: 0, minutes: 60)])
        XCTAssertTrue(PlannerExport.shareText(direct).contains("direkt"))
        XCTAssertEqual(PlannerExport.changesText(2), "2 Umstiege")
    }

    // MARK: Links and reminders

    func testPlannerLinkRoundTripKeepsViasTimeAndArrival() throws {
        let at = Date(timeIntervalSince1970: 1_791_000_000)
        let link = PlannerLink(from: "uic:8100108", to: "Landeck-Zams", vias: ["Feldkirch", "Bregenz", "Dritter"], at: at, isArrival: true)
        let url = try XCTUnwrap(link.url)
        XCTAssertEqual(url.scheme, "klimabilanz")
        XCTAssertEqual(url.host, "plan")
        let parsed = try XCTUnwrap(PlannerLink.parse(url))
        XCTAssertEqual(parsed.from, "uic:8100108")
        XCTAssertEqual(parsed.to, "Landeck-Zams")
        XCTAssertEqual(parsed.vias, ["Feldkirch", "Bregenz"], "at most two via stops")
        XCTAssertEqual(parsed.at?.timeIntervalSince1970 ?? -1, at.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(parsed.isArrival)
    }

    func testPlannerLinkRejectsForeignAndIncompleteLinks() {
        XCTAssertNil(PlannerLink.parse(URL(string: "https://example.com/plan?from=a&to=b")!))
        XCTAssertNil(PlannerLink.parse(URL(string: "klimabilanz://plan?from=a")!))
        XCTAssertNil(PlannerLink.parse(URL(string: "klimabilanz://plan?from=%20&to=b")!))
        XCTAssertNil(PlannerLink.parse(URL(string: "klimabilanz://board?station=a")!))
        let minimal = PlannerLink.parse(URL(string: "klimabilanz://plan?from=Wien%20Hbf&to=Graz")!)
        XCTAssertEqual(minimal?.isArrival, false)
        XCTAssertNil(minimal?.at)
        XCTAssertEqual(minimal?.vias, [])
    }

    func testReminderFiresLeadMinutesBeforeDeparture() {
        let departure = t0.addingTimeInterval(3600)
        XCTAssertEqual(PlannerReminder.fireDate(departure: departure, leadMinutes: 10, now: t0), departure.addingTimeInterval(-600))
        XCTAssertNil(PlannerReminder.fireDate(departure: departure, leadMinutes: 90, now: t0), "already passed")
        XCTAssertNil(PlannerReminder.fireDate(departure: departure, leadMinutes: 0, now: departure), "the departure itself is past")
        XCTAssertEqual(PlannerReminder.leadMinutes, [5, 10, 15, 30])
    }
}
