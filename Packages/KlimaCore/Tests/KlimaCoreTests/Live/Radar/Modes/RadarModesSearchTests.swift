import XCTest
@testable import KlimaCore

// MARK: radarmodes – the search finds buses, Bims and U-Bahnen by their line („13A“, „U6“, „D“).
final class RadarModesSearchTests: XCTestCase {
    private func vehicle(_ name: String, category: String?, number: String?, cls: Int, mode: TransportMode, direction: String = "Floridsdorf") -> RadarVehicle {
        RadarVehicle(tripID: name, line: Line(name: name, fullName: name, category: category, lineNumber: number, productClass: cls, mode: mode),
                     direction: direction, coordinate: GeoPoint(latitude: 48.2, longitude: 16.37))
    }

    private lazy var vehicles = [
        vehicle("Bus 13A", category: "Bus", number: "13A", cls: 64, mode: .bus),
        vehicle("U6", category: "U", number: "U6", cls: 256, mode: .metro),
        vehicle("Tram D", category: "Tram", number: "D", cls: 512, mode: .tram, direction: "Nußdorf"),
        vehicle("RJX 66", category: "RJX", number: nil, cls: 1, mode: .train, direction: "Innsbruck Hbf"),
        vehicle("S 45", category: "S", number: "45", cls: 32, mode: .sBahn, direction: "Hütteldorf"),
    ]

    private func names(_ text: String) -> [String] {
        RadarSearch.suggestions(for: RadarSearchQuery(text)!, in: vehicles).compactMap { $0.line?.name }
    }

    func testLinesAsAWhole() {
        XCTAssertEqual(names("13A"), ["Bus 13A"])
        XCTAssertEqual(names("13 a"), ["Bus 13A"])
        XCTAssertEqual(names("U6"), ["U6"])
        XCTAssertEqual(names("u 6"), ["U6"])
        XCTAssertEqual(names("D").first, "Tram D", "the Bim D before every name with a d")
        XCTAssertEqual(names("S45"), ["S 45"])
    }

    func testTrainsAsBefore() {
        XCTAssertEqual(names("RJX 66"), ["RJX 66"])
        XCTAssertEqual(names("rjx66"), ["RJX 66"])
        XCTAssertEqual(names("66"), ["RJX 66"])
        XCTAssertEqual(names("Innsbruck"), ["RJX 66"])
    }
}
