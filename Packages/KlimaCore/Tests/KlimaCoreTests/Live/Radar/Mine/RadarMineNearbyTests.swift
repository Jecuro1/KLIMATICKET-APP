import XCTest
@testable import KlimaCore

/// „In der Nähe“ and „Wo bleibt mein Bus?“ (docs/RADAR_MINE.md §3, §4): the radius, the order, the minutes, the board rows with their positions and
/// the radar match by trip id.
final class RadarMineNearbyTests: XCTestCase {
    private typealias F = MineFixture

    // MARK: In der Nähe

    func testTheRadiusEdge() {
        let inside = F.vehicle("in", line: F.bus(), at: F.point(north: 1499))
        let outside = F.vehicle("out", line: F.bus(), at: F.point(north: 1501))
        let rows = RadarNearby.rows([RadarMineSighting(vehicle: inside, coordinate: inside.coordinate),
                                     RadarMineSighting(vehicle: outside, coordinate: outside.coordinate)], from: F.neubau, now: F.t0)
        XCTAssertEqual(rows.map(\.tripID), ["in"])
        XCTAssertEqual(rows[0].distanceKm, 1.499, accuracy: 0.002)
    }

    func testNearestFirstTiesByTripIDAndNoNextStopIsDropped() {
        let a = F.vehicle("b", line: F.bus(), at: F.point(east: 300))
        let b = F.vehicle("a", line: F.tramD, at: F.point(east: -300))
        let c = F.vehicle("c", line: F.u6, at: F.point(north: 100))
        var noNext = F.vehicle("d", line: F.bus(), at: F.point(north: 50))
        noNext.stopovers = [Stopover(location: Location(lid: "x", name: "Vorher"), departure: StopEvent(planned: F.t0.addingTimeInterval(-60)))]
        let rows = RadarNearby.rows([a, b, c, noNext].map { RadarMineSighting(vehicle: $0, coordinate: $0.coordinate) }, from: F.neubau, now: F.t0)
        XCTAssertEqual(rows.map(\.tripID), ["c", "a", "b"])
        XCTAssertEqual(rows[0].nextStop, "Neubaugasse")
        // The sighting's coordinate (the drawn marker) counts, not the answer's.
        let moved = RadarNearby.rows([RadarMineSighting(vehicle: a, coordinate: F.point(north: 5000))], from: F.neubau, now: F.t0)
        XCTAssertTrue(moved.isEmpty)
        XCTAssertTrue(RadarNearby.rows([RadarMineSighting(vehicle: a, coordinate: a.coordinate)], from: GeoPoint(latitude: .nan, longitude: 0), now: F.t0).isEmpty)
    }

    func testRealtimeBeforePlannedAndTheMinutes() throws {
        let late = F.vehicle("a", line: F.bus(), nextIn: 120, delayMinutes: 1)
        let row = try XCTUnwrap(RadarNearby.rows([RadarMineSighting(vehicle: late, coordinate: F.point(north: 240))], from: F.neubau, now: F.t0).first)
        XCTAssertTrue(row.eta.isRealtime)
        XCTAssertEqual(row.eta.minutes(from: F.t0), 3, "two planned and one late")
        XCTAssertEqual(row.eta.delayMinutes, 1)
        XCTAssertEqual(RadarMineText.nearDetail(row, now: F.t0), "240 m · nächster Halt Neubaugasse in 3 Min (+1)")
        let plan = F.vehicle("b", line: F.bus(), nextIn: 120, delayMinutes: nil)
        let planRow = try XCTUnwrap(RadarNearby.rows([RadarMineSighting(vehicle: plan, coordinate: plan.coordinate)], from: F.neubau, now: F.t0).first)
        XCTAssertFalse(planRow.eta.isRealtime)
        XCTAssertEqual(RadarMineText.stopETA(stop: "Neubaugasse", eta: planRow.eta, now: F.t0), "Neubaugasse in 2 Min laut Fahrplan")
        let eta = RadarMineETA(time: F.t0.addingTimeInterval(59), isRealtime: true, delaySeconds: 0, isCancelled: false)
        XCTAssertEqual(eta.minutes(from: F.t0), 1, "59 s is „in 1 Min“")
        XCTAssertEqual(RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 0, isCancelled: false).minutes(from: F.t0), 0)
        XCTAssertEqual(RadarMineText.minutesText(0), "jetzt")
        XCTAssertEqual(RadarMineText.minutesText(-3), "jetzt")
    }

    func testACancelledRunSaysSo() throws {
        let gone = F.vehicle("a", line: F.bus(), cancelled: true)
        let row = try XCTUnwrap(RadarNearby.rows([RadarMineSighting(vehicle: gone, coordinate: gone.coordinate)], from: F.neubau, now: F.t0).first)
        XCTAssertTrue(row.eta.isCancelled)
        XCTAssertTrue(RadarMineText.nearDetail(row, now: F.t0).hasSuffix("Neubaugasse · fällt aus"))
        XCTAssertTrue(RadarMineText.nearSpoken(row, now: F.t0).contains("fällt aus"))
    }

    // MARK: Haltestelle

    func testTheBoardQueryAsksEveryCityModeWhateverTheChips() {
        let query = RadarStopArrivals.query(station: Location(lid: "A=1@L=1@", name: "Neubaugasse"), at: F.t0)
        XCTAssertEqual(query.products.rawValue, 4989)
        XCTAssertEqual(query.durationMinutes, 30)
        XCTAssertEqual(query.maxResults, 12)
        XCTAssertEqual(query.kind, .departures)
    }

    func testBoardOrderIsKeptAndPastEntriesAreDropped() {
        let board = Board(kind: .departures, entries: [
            F.entry("gone", inMinutes: -2), F.entry("justGone", inMinutes: -0.5), F.entry("a", inMinutes: 1), F.entry("b", inMinutes: 4),
            F.entry("cancelledPast", inMinutes: -2, cancelled: true), F.entry("cancelled", inMinutes: 6, cancelled: true),
        ])
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0)
        XCTAssertEqual(rows.map(\.tripID), ["justGone", "a", "b", "cancelled"])
        XCTAssertTrue(rows[3].isCancelled)
        let many = Board(kind: .departures, entries: (0..<12).map { F.entry("t\($0)", inMinutes: Double($0)) })
        XCTAssertEqual(RadarStopArrivals.rows(board: many, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0).count, 8)
    }

    func testPositionAtTheStopAwayAndUnknown() {
        let board = Board(kind: .departures, entries: [
            F.entry("at", inMinutes: 1, position: F.point(north: 99.9)),
            F.entry("away", inMinutes: 2, position: F.point(north: 100.5)),
            F.entry("far", inMinutes: 3, position: F.point(north: 1200)),
            F.entry("none", inMinutes: 4, position: nil),
        ])
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0)
        XCTAssertEqual(rows[0].position, .atStop)
        guard case .away(let km) = rows[1].position else { return XCTFail("101 m is away") }
        XCTAssertEqual(km, 0.1005, accuracy: 0.0005)
        XCTAssertEqual(RadarMineText.position(rows[2].position), "noch 1,2 km")
        XCTAssertEqual(rows[3].position, .unknown)
        XCTAssertEqual(rows[3].source, .none)
        XCTAssertNil(rows[3].point)
        XCTAssertEqual(RadarMineText.position(rows[3].position), "Position unbekannt")
        XCTAssertEqual(rows[2].source, .board)
        XCTAssertEqual(rows[2].positionAt, F.t0)
    }

    func testTheRadarReplacesTheBoardOnlyForTheSameTripAndANewerAnswer() {
        let boardAt = F.t0
        let board = Board(kind: .departures, entries: [
            F.entry("same", inMinutes: 2, position: F.point(north: 900)),
            F.entry("older", inMinutes: 3, position: F.point(north: 800)),
            F.entry("other", inMinutes: 4, position: F.point(north: 700)),
            F.entry("noPos", inMinutes: 5, position: nil),
        ])
        let radar = ["same": RadarHeldVehicle(coordinate: F.point(north: 500), seenAt: boardAt.addingTimeInterval(10)),
                     "older": RadarHeldVehicle(coordinate: F.point(north: 300), seenAt: boardAt.addingTimeInterval(-10)),
                     "different": RadarHeldVehicle(coordinate: F.point(north: 50), seenAt: boardAt.addingTimeInterval(10)),
                     "noPos": RadarHeldVehicle(coordinate: F.point(north: 400), seenAt: boardAt.addingTimeInterval(-30))]
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: boardAt, stop: F.neubau, radar: radar, now: boardAt.addingTimeInterval(15))
        XCTAssertEqual(rows[0].source, .radar)
        XCTAssertEqual(rows[0].point, F.point(north: 500))
        XCTAssertEqual(rows[0].positionAt, boardAt.addingTimeInterval(10))
        XCTAssertEqual(rows[1].source, .board, "the radar's answer is older than the board's")
        XCTAssertEqual(rows[2].source, .board, "only an equal trip id matches")
        XCTAssertEqual(rows[3].source, .radar, "without a board position the radar's is the only one")
    }

    func testPlatformTextAndAge() {
        let board = Board(kind: .departures, entries: [
            F.entry("bus", inMinutes: 1, platform: Platform(text: "2", kind: .stand)),
            F.entry("rail", line: F.rjx66, inMinutes: 2, platform: Platform(text: "4", kind: .track)),
            F.entry("none", inMinutes: 3, platform: nil),
        ])
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0)
        XCTAssertEqual(rows.map(\.platform), ["Steig 2", "Gleis 4", nil])
        XCTAssertFalse(RadarStopArrivals.isStale(F.t0, now: F.t0.addingTimeInterval(120)))
        XCTAssertTrue(RadarStopArrivals.isStale(F.t0, now: F.t0.addingTimeInterval(121)))
        XCTAssertFalse(RadarStopArrivals.isStale(nil, now: F.t0))
        XCTAssertEqual(RadarMineText.positionAge(180), "Position von vor 3 Min")
    }

    func testMapNumbersSkipCancelledUnknownAndModesOffTheMap() {
        let board = Board(kind: .departures, entries: [
            F.entry("bus1", inMinutes: 1, position: F.point(north: 500)),
            F.entry("cancelled", inMinutes: 2, cancelled: true, position: F.point(north: 400)),
            F.entry("unknown", inMinutes: 3, position: nil),
            F.entry("tram", line: F.tramD, inMinutes: 4, position: F.point(north: 300)),
            F.entry("bus2", inMinutes: 5, position: F.point(north: 600)),
            F.entry("bus3", inMinutes: 6, position: F.point(north: 700)),
            F.entry("bus4", inMinutes: 7, position: F.point(north: 800)),
            F.entry("bus5", inMinutes: 8, position: F.point(north: 900)),
        ])
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0)
        let all = RadarStopArrivals.numbers(rows, shownModes: Set(RadarMode.allCases))
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all[rows[0].id], 1)
        XCTAssertNil(all[rows[1].id])
        XCTAssertNil(all[rows[2].id])
        XCTAssertEqual(all[rows[3].id], 2)
        XCTAssertNil(all[rows[7].id], "only five numbers")
        // Bim off: the tram stays in the list without a number, and the page names the mode.
        let noTram = RadarStopArrivals.numbers(rows, shownModes: [.rail, .suburban, .bus])
        XCTAssertNil(noTram[rows[3].id])
        XCTAssertEqual(noTram[rows[7].id], 5)
        XCTAssertEqual(RadarStopArrivals.hiddenModes(rows, shownModes: [.rail, .suburban, .bus]), [.tram])
        XCTAssertEqual(RadarMineText.modesOffMap([.tram]), "Bim ist aus – diese Abfahrten stehen in der Liste, aber nicht auf der Karte.")
    }
}
