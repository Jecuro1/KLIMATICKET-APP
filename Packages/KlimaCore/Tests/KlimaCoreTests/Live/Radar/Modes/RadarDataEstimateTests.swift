import XCTest
@testable import KlimaCore

// MARK: radarmodes – the data estimate of the city lane.
final class RadarDataEstimateTests: XCTestCase {
    func testSixTilesOfFourHundredBusesAtTwentySecondsAreAboutTwelveMegabytes() {
        let mb = RadarDataEstimate.megabytesPerMinute(cityTileCounts: Array(repeating: 400, count: 6), period: 20)
        XCTAssertEqual(mb, 12.24, accuracy: 0.001)
        XCTAssertEqual(RadarDataEstimate.noteMegabytes(mb), 12)
        XCTAssertEqual(RadarModesText.dataEstimate([.bus, .tram, .subway], megabytes: 12), "Bus, Bim und U-Bahn: etwa 12 MB pro Minute (geschätzt).")
    }

    func testTheStretchedPeriodLowersTheEstimate() {
        let fast = RadarDataEstimate.megabytesPerMinute(cityTileCounts: Array(repeating: 400, count: 6), period: 20)
        let slow = RadarDataEstimate.megabytesPerMinute(cityTileCounts: Array(repeating: 400, count: 6), period: 50)
        XCTAssertEqual(slow, fast * 20 / 50, accuracy: 1e-9)
    }

    func testRoundingAndThreshold() {
        XCTAssertNil(RadarDataEstimate.noteMegabytes(1.99), "below 2 MB: no note")
        XCTAssertEqual(RadarDataEstimate.noteMegabytes(2.0), 2)
        XCTAssertEqual(RadarDataEstimate.noteMegabytes(4.6), 5)
        XCTAssertEqual(RadarDataEstimate.noteMegabytes(9.4), 9)
        XCTAssertNil(RadarDataEstimate.noteMegabytes(.nan))
        XCTAssertEqual(RadarDataEstimate.megabytesPerMinute(cityTileCounts: [100], period: 0), 0)
        XCTAssertEqual(RadarDataEstimate.megabytesPerMinute(cityTileCounts: [], period: 20), 0)
    }

    func testTheCeilingIsTheWholeBudgetFull() {
        XCTAssertEqual(RadarDataEstimate.ceilingMegabytesPerMinute, 40.8, accuracy: 0.001)
    }
}
