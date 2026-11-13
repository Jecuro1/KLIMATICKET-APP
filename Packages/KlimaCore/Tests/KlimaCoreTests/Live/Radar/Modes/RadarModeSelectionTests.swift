import XCTest
@testable import KlimaCore

// MARK: radarmodes – the modes of the radar and their request masks (docs/RADAR_MODES.md §2).
final class RadarModeSelectionTests: XCTestCase {
    func testDefaultAsksForTheSameMaskAsBefore() {
        let selection = RadarModeSelection.default
        XCTAssertEqual(selection.modes, [.rail, .suburban])
        XCTAssertEqual(selection.products.rawValue, 4157)
        XCTAssertEqual(selection.products, .rail)
        XCTAssertTrue(selection.carriesOnlyTrains)
        XCTAssertFalse(selection.hasCity)
    }

    func testTrainsNoLongerIncludeTheSBahn() {
        XCTAssertEqual(RadarMode.rail.products.rawValue, 4125)
        XCTAssertFalse(RadarMode.rail.products.contains(.suburban))
        var selection = RadarModeSelection.default
        selection.toggle(.suburban)
        XCTAssertEqual(selection.products.rawValue, 4125)
        XCTAssertTrue(selection.carriesOnlyTrains)
    }

    func testCityModes() {
        var selection = RadarModeSelection.default
        selection.toggle(.bus)
        XCTAssertEqual(selection.products.rawValue, 4157 | 64)
        XCTAssertTrue(selection.hasCity)
        XCTAssertFalse(selection.carriesOnlyTrains)
        XCTAssertEqual(selection.cityModes, [.bus])
        XCTAssertEqual(selection.wideModes, [.rail, .suburban])
        XCTAssertEqual(RadarModeSelection([.bus, .tram, .subway]).products.rawValue, 64 | 512 | 256)
    }

    func testCarriesOnlyTrainsTruthTable() {
        XCTAssertTrue(RadarModeSelection([.rail]).carriesOnlyTrains)
        XCTAssertTrue(RadarModeSelection([.suburban]).carriesOnlyTrains)
        XCTAssertTrue(RadarModeSelection([.rail, .suburban]).carriesOnlyTrains)
        for city in [RadarMode.bus, .tram, .subway] {
            XCTAssertFalse(RadarModeSelection([city]).carriesOnlyTrains)
            XCTAssertFalse(RadarModeSelection([.rail, city]).carriesOnlyTrains)
            XCTAssertFalse(RadarModeSelection([.rail, .suburban, city]).carriesOnlyTrains)
        }
    }

    func testStorageRoundTrip() {
        let selection = RadarModeSelection(storage: "rail,suburban,bus")
        XCTAssertEqual(selection.modes, [.rail, .suburban, .bus])
        XCTAssertEqual(selection.storageValue, "rail,suburban,bus")
        XCTAssertEqual(RadarModeSelection(storage: selection.storageValue), selection)
        // Chip order, whatever order was stored.
        XCTAssertEqual(RadarModeSelection(storage: "subway, bus,rail").storageValue, "rail,bus,subway")
    }

    func testStorageDropsUnknownWordsAndFallsBackToTheDefault() {
        XCTAssertEqual(RadarModeSelection(storage: "rail,ferry,zeppelin").modes, [.rail])
        XCTAssertEqual(RadarModeSelection(storage: ""), .default)
        XCTAssertEqual(RadarModeSelection(storage: "zeppelin"), .default)
        XCTAssertEqual(RadarModeSelection(storage: ",,"), .default)
        XCTAssertEqual(RadarModeSelection([]), .default)
    }

    func testTheLastModeStaysOn() {
        var selection = RadarModeSelection([.bus])
        XCTAssertFalse(selection.toggle(.bus))
        XCTAssertEqual(selection.modes, [.bus])
        XCTAssertFalse(selection.set(.bus, on: false))
        XCTAssertTrue(selection.set(.tram, on: true))
        XCTAssertTrue(selection.set(.bus, on: false))
        XCTAssertEqual(selection.modes, [.tram])
        XCTAssertFalse(selection.set(.tram, on: true))   // nothing changed
    }

    func testModeOfAVehicleComesFromItsClassBit() {
        for cls in [1, 4, 8, 16, 4096] { XCTAssertEqual(RadarMode.of(productClass: cls), .rail, "class \(cls)") }
        XCTAssertEqual(RadarMode.of(productClass: 32), .suburban)
        XCTAssertEqual(RadarMode.of(productClass: 64), .bus)
        XCTAssertEqual(RadarMode.of(productClass: 512), .tram)
        XCTAssertEqual(RadarMode.of(productClass: 256), .subway)
        // Rail replacement and coaches are `.bus` for the codec, but no city bus here.
        for cls in [0, 2, 128, 1024, 2048, 3] { XCTAssertNil(RadarMode.of(productClass: cls), "class \(cls)") }
        let sev = RadarVehicle(tripID: "sev", line: Line(name: "SEV", productClass: 2, mode: .bus), coordinate: GeoPoint(latitude: 47, longitude: 13))
        XCTAssertNil(RadarMode.of(sev))
        let bus = RadarVehicle(tripID: "bus", line: Line(name: "Bus 13A", productClass: 64, mode: .bus), coordinate: GeoPoint(latitude: 48, longitude: 16))
        XCTAssertEqual(RadarMode.of(bus), .bus)
    }

    func testEveryModeMaskIsInsideTheOldRailOrACityClass() {
        XCTAssertEqual(RadarMode.rail.products.union(RadarMode.suburban.products), .rail)
        XCTAssertEqual(RadarMode.allCases.filter(\.isCity), [.bus, .tram, .subway])
        XCTAssertEqual(RadarMode.allCases.map(\.title), ["Züge", "S-Bahn", "Bus", "Bim", "U-Bahn"])
        XCTAssertEqual(RadarMode.allCases.map(\.transportMode), [.train, .sBahn, .bus, .tram, .metro])
    }
}
