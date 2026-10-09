import XCTest
@testable import KlimaCore

/// SPEC §C3.3 / §D2 WP-C 5.
final class DisplayNamesTests: XCTestCase {
    func testRules() {
        XCTAssertEqual(DisplayNames.make("Langen am Arlberg Bahnhof (Vorplatz)"),
                       DisplayName(raw: "Langen am Arlberg Bahnhof (Vorplatz)", name: "Langen am Arlberg", sub: "Vorplatz"))
        XCTAssertEqual(DisplayNames.make("St.Anton am Arlberg Bahnhof (Vorplatz)").name, "St. Anton am Arlberg")
        XCTAssertEqual(DisplayNames.make("St. Pölten Hauptbahnhof").name, "St. Pölten Hbf")
        XCTAssertEqual(DisplayNames.make("Innsbruck Hbf"), DisplayName(raw: "Innsbruck Hbf", name: "Innsbruck Hbf"))
        XCTAssertEqual(DisplayNames.make("Wien Hbf (Bahnsteige 3-12)").sub, "Bahnsteige 3-12")
        XCTAssertEqual(DisplayNames.make("Innsbruck Hbf (Südtiroler Platz/Steige D-F)").name, "Innsbruck Hbf")
        XCTAssertEqual(DisplayNames.make("Landeck-Zams Bahnhof").name, "Landeck-Zams")
        XCTAssertEqual(DisplayNames.make("Lech Rüfiplatz").name, "Lech Rüfiplatz")
        // „Bahnhof“ only at the end; „Bahnhst“ and inner words stay.
        XCTAssertEqual(DisplayNames.make("Bahnhofstraße").name, "Bahnhofstraße")
        XCTAssertEqual(DisplayNames.make("Rum Bahnhst").name, "Rum Bahnhst")
        XCTAssertEqual(DisplayNames.make("Bad St.Leonhard").name, "Bad St. Leonhard")
        // Degenerate input never yields an empty name.
        XCTAssertEqual(DisplayNames.make("(Vorplatz)").name, "(Vorplatz)")
        XCTAssertEqual(DisplayNames.make("").name, "")
        XCTAssertEqual(DisplayNames.name("  Feldkirch Bahnhof "), "Feldkirch")
    }

    /// Every from/to display name of the trips goldens.
    func testGoldenDisplayNames() throws {
        var n = 0
        for (vm, _) in VM.trips {
            for c in try VM.connections(vm) {
                for leg in try XCTUnwrap(c["legs"] as? [[String: Any]]) where leg["kind"] as? String == "ride" {
                    for key in ["fromDisplay", "toDisplay"] {
                        let g = try XCTUnwrap(leg[key] as? [String: Any])
                        let raw = try XCTUnwrap(g["raw"] as? String)
                        XCTAssertEqual(DisplayNames.make(raw), DisplayName(raw: raw, name: g["name"] as! String, sub: VM.value(g["sub"])), raw)
                        n += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(n, 20)
    }
}
