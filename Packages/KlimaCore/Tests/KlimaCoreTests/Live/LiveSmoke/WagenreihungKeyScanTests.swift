// Offline self-test for the key scan used by WagenreihungProbeLiveTests (§R6). No network, runs in CI.
// Proves that the scan matches real key NAMES (case-insensitive) and ignores values and "Informationen" keys.
import Foundation
import XCTest
@testable import KlimaCore

final class WagenreihungKeyScanTests: XCTestCase {
    func testMatchesKeyNamesOnly() {
        let json = #"{"informationen":"Wagenreihung im Text","remL":[{"txtN":"formation"}],"jnyL":[{"prodL":[{"formationL":[{"sectorL":"A"}]}]}],"WagenNr":3}"#
        let scan = KeyScan.run(Data(json.utf8))
        XCTAssertTrue(scan.isJSON)
        XCTAssertEqual(scan.matched, ["WagenNr", "formationL", "sectorL"])
        XCTAssertEqual(scan.excludedInformation, 1)
        XCTAssertEqual(scan.distinctKeys, 8)
    }

    func testNonJSONIsReportedAsNotJSON() {
        let scan = KeyScan.run(Data("<html>formation</html>".utf8))
        XCTAssertFalse(scan.isJSON)
        XCTAssertTrue(scan.matched.isEmpty)
    }
}
