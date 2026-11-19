import XCTest
@testable import KlimaCore

/// „Linien“ of „Meine Fahrzeuge“ (docs/RADAR_MINE.md §2): one key per line whatever way the answer spells it, never across modes, at most 20, the
/// file round trip and its tolerance, the highlight cap.
final class RadarMineLinesTests: XCTestCase {
    private typealias F = MineFixture

    // MARK: RadarLineKey

    func testKeysFromTheWaysALineIsSpelled() throws {
        let full = try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("a", line: F.bus())))
        XCTAssertEqual(full.mode, .bus)
        XCTAssertEqual(full.compact, "BUS13A")
        XCTAssertEqual(full.title, "Bus 13A")
        // Only the line number, no „Bus“ in the name.
        let bare = try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("b", line: F.bus(name: "13A", lineNumber: .some(nil)))))
        XCTAssertEqual(bare.id, full.id)
        XCTAssertEqual(try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("c", line: F.sBahn()))).compact, "S45")
        XCTAssertEqual(try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("d", line: F.sBahn(name: "S45")))).id, "suburban|S45")
        XCTAssertEqual(try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("e", line: F.u6))).id, "subway|U6")
        XCTAssertEqual(try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("f", line: F.tramD))).title, "Tram D")
        let train = try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("g", line: F.rjx66)))
        XCTAssertEqual(train.id, "rail|RJX66")
        XCTAssertEqual(train.title, "RJX 66")
    }

    func testCaseAndSpacesDoNotMatterButModesDo() throws {
        let key = RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A")
        XCTAssertTrue(key.matches(F.vehicle("a", line: F.bus(name: "bus 13a", lineNumber: .some("13a")))))
        XCTAssertTrue(key.matches(F.vehicle("b", line: F.bus(name: "Bus  13A"))))
        // „S 1“ is not „Bus 1“, and a bus line of the same name in another mode never matches.
        let s1 = try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("s", line: F.sBahn("1"))))
        XCTAssertFalse(s1.matches(F.vehicle("t", line: F.bus("1"))))
        let u6AsBus = Line(name: "U6", lineNumber: "U6", productClass: 64, mode: .bus)
        XCTAssertFalse(try XCTUnwrap(RadarLineKey(vehicle: F.vehicle("u", line: F.u6))).matches(F.vehicle("v", line: u6AsBus)))
        // Rail replacement and vehicles without a line cannot be remembered.
        XCTAssertNil(RadarLineKey(vehicle: F.vehicle("w", line: F.sev)))
        XCTAssertNil(RadarLineKey(vehicle: F.vehicle("x", line: nil)))
    }

    func testAnOptionalDirection() {
        let both = RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A")
        let one = RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A", direction: " Hauptbahnhof ")
        XCTAssertEqual(one.direction, "Hauptbahnhof")
        XCTAssertNotEqual(both.id, one.id)
        XCTAssertEqual(one.lineID, both.lineID)
        XCTAssertTrue(one.matches(F.vehicle("a", line: F.bus(), direction: "hauptbahnhof")))
        XCTAssertFalse(one.matches(F.vehicle("b", line: F.bus(), direction: "Alser Straße")))
        XCTAssertTrue(both.matches(F.vehicle("c", line: F.bus(), direction: "Alser Straße")))
        XCTAssertNil(RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A", direction: "  ").direction)
    }

    func testTheAreaIsTheLevelThreeTileCentreRoundedToTwoDecimals() throws {
        let area = try XCTUnwrap(RadarLineKey.area(of: F.neubau))
        XCTAssertEqual(area.latitude * 100, (area.latitude * 100).rounded(), accuracy: 1e-9)
        XCTAssertEqual(area.longitude * 100, (area.longitude * 100).rounded(), accuracy: 1e-9)
        // The tile is about 39 × 36 km: the centre is within half a tile, and two points in the same tile give the same area.
        XCTAssertLessThan(area.distanceKm(to: F.neubau), 30)
        XCTAssertEqual(RadarLineKey.area(of: F.point(north: 100, east: 100)), area)
        let tile = try XCTUnwrap(RadarTileGrid.tiles(intersecting: RadarBox.around(F.neubau, halfSpan: 1e-6), level: 3).first)
        let centre = RadarTileGrid.box(of: tile).center
        XCTAssertEqual(area.latitude, (centre.latitude * 100).rounded() / 100, accuracy: 1e-12)
        XCTAssertNil(RadarLineKey.area(of: GeoPoint(latitude: 52.52, longitude: 13.40)), "outside the radar's coverage")
        XCTAssertNil(RadarLineKey.area(of: GeoPoint(latitude: .nan, longitude: 16)))
    }

    // MARK: RadarMineLines

    func testAddRemoveAndDedupe() {
        var lines = RadarMineLines()
        let key = RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A")
        XCTAssertEqual(lines.add(key), .added)
        XCTAssertEqual(lines.add(key), .alreadyThere)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines.contains(F.vehicle("a", line: F.bus())))
        XCTAssertEqual(lines.wholeLineIDs, ["bus|BUS13A"])
        lines.remove(lineOf: F.vehicle("a", line: F.bus()))
        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(RadarMineLines([key, key]).count, 1)
    }

    func testTheTwentyFirstIsRefusedAndNothingOldIsDropped() {
        var lines = RadarMineLines()
        for n in 1...20 { XCTAssertEqual(lines.add(RadarLineKey(mode: .bus, compact: "BUS\(n)", title: "Bus \(n)")), .added) }
        XCTAssertTrue(lines.isFull)
        XCTAssertEqual(lines.add(RadarLineKey(mode: .bus, compact: "BUS21", title: "Bus 21")), .full)
        XCTAssertEqual(lines.count, 20)
        XCTAssertEqual(lines.keys.first?.compact, "BUS1", "the oldest stays")
        XCTAssertEqual(RadarMineLines((1...25).map { RadarLineKey(mode: .tram, compact: "TRAM\($0)", title: "Tram \($0)") }).count, 20)
    }

    // MARK: RadarMineFile

    func testTheFileRoundTripsLinesStopsAndTheHighlight() {
        var file = RadarMineFile(lines: RadarMineLines([RadarLineKey(mode: .bus, compact: "BUS13A", title: "Bus 13A", area: GeoPoint(latitude: 48.12, longitude: 16.38)),
                                                        RadarLineKey(mode: .rail, compact: "RJX66", title: "RJX 66", direction: "Salzburg Hbf")]),
                                 highlight: true)
        file.noteStop(RadarMineStop(id: "wl:1", name: "Neubaugasse", coordinate: F.neubau))
        let back = RadarMineFile(data: file.encoded())
        XCTAssertEqual(back, file)
        XCTAssertTrue(back.highlight)
        XCTAssertEqual(back.lines.keys.map(\.id), ["bus|BUS13A", "rail|RJX66|salzburg hbf"])
        XCTAssertEqual(back.lines.keys.first?.area, GeoPoint(latitude: 48.12, longitude: 16.38))
    }

    func testAnUnknownVersionOrGarbageIsEmptyAndBadEntriesAreDropped() {
        XCTAssertEqual(RadarMineFile(data: Data("{\"version\":2,\"lines\":[]}".utf8)), .empty)
        XCTAssertEqual(RadarMineFile(data: Data("nonsense".utf8)), .empty)
        XCTAssertEqual(RadarMineFile(data: Data()), .empty)
        let mixed = """
        {"version":1,"lines":[{"mode":"bus","compact":"BUS13A","title":"Bus 13A"},{"mode":"ship","compact":"X","title":"X"},{"compact":"Y"},7],
         "stops":[{"id":"a","name":"A","lat":48.2,"lon":16.3},{"id":"b","name":"B","lat":"x","lon":16.3},{"id":"","name":"C","lat":1,"lon":1}],
         "highlight":"yes"}
        """
        let file = RadarMineFile(data: Data(mixed.utf8))
        XCTAssertEqual(file.lines.keys.map(\.id), ["bus|BUS13A"])
        XCTAssertEqual(file.stops.map(\.id), ["a"])
        XCTAssertFalse(file.highlight)
    }

    func testTheLastFiveStopsNewestFirst() {
        var file = RadarMineFile()
        for n in 1...7 { file.noteStop(RadarMineStop(id: "s\(n)", name: "S\(n)", coordinate: F.neubau)) }
        XCTAssertEqual(file.stops.map(\.id), ["s7", "s6", "s5", "s4", "s3"])
        file.noteStop(RadarMineStop(id: "s4", name: "S4", coordinate: F.neubau))
        XCTAssertEqual(file.stops.map(\.id), ["s4", "s7", "s6", "s5", "s3"])
        // „Alle löschen“ empties it.
        file.lines.removeAll()
        file.stops = []
        file.highlight = false
        XCTAssertTrue(file.isEmpty)
    }

    // MARK: Highlight cap

    func testUpToSixtyHighlightedStaySingleNearestTheCentreFirst() {
        let few = (0..<60).map { RadarMineHighlight.Candidate(tripID: "t\($0)", coordinate: F.point(north: Double($0) * 100)) }
        XCTAssertEqual(RadarMineHighlight.singles(few, centre: F.neubau).count, 60)
        let many = few + [RadarMineHighlight.Candidate(tripID: "far", coordinate: F.point(north: 9000)),
                          RadarMineHighlight.Candidate(tripID: "near", coordinate: F.point(east: 10))]
        let singles = RadarMineHighlight.singles(many, centre: F.neubau)
        XCTAssertEqual(singles.count, 60, "the 61st groups")
        XCTAssertTrue(singles.contains("near"))
        XCTAssertFalse(singles.contains("far"))
        XCTAssertFalse(singles.contains("t59"), "the farthest of the rest groups")
        XCTAssertTrue(RadarMineHighlight.singles([], centre: F.neubau).isEmpty)
    }
}
