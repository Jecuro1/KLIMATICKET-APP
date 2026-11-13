import XCTest
@testable import KlimaCore

// MARK: radarmodes – „Darstellung“.
final class RadarDisplayTests: XCTestCase {
    func testPitchFollowsTheSize() {
        XCTAssertEqual(RadarDisplay.Size.allCases.map(\.markerPitch), [44, 56, 70])
        XCTAssertEqual(RadarDisplay.standard.size.markerPitch, 56, "the default keeps the radar's 56 pt")
    }

    func testGroupsOffOnlyUpTo250() {
        var display = RadarDisplay()
        XCTAssertTrue(display.groups(pinCount: 10))
        display.groups = false
        XCTAssertFalse(display.groups(pinCount: 250))
        XCTAssertTrue(display.groups(pinCount: 251), "above 250 the radar groups again")
    }

    func testDestinationOnlyClose() {
        var display = RadarDisplay(label: .lineAndDestination)
        XCTAssertTrue(display.showsDestination(latitudeSpan: 0.3, singles: 80))
        XCTAssertFalse(display.showsDestination(latitudeSpan: 0.31, singles: 10))
        XCTAssertFalse(display.showsDestination(latitudeSpan: 0.1, singles: 81))
        display.label = .line
        XCTAssertFalse(display.showsDestination(latitudeSpan: 0.1, singles: 1))
    }

    func testCityRefresh() {
        XCTAssertEqual(RadarDisplay(cityRefresh: .automatic).cityInterval(metered: true), 60)
        XCTAssertEqual(RadarDisplay(cityRefresh: .automatic).cityInterval(metered: false), 20)
        XCTAssertEqual(RadarDisplay(cityRefresh: .every20).cityInterval(metered: true), 20)
        XCTAssertEqual(RadarDisplay(cityRefresh: .every60).cityInterval(metered: false), 60)
        XCTAssertTrue(RadarDisplay().meteredCity(metered: true))
        XCTAssertFalse(RadarDisplay(cityRefresh: .every60).meteredCity(metered: true), "a chosen 60 s is not the metered note")
    }

    func testStorage() {
        let display = RadarDisplay(label: .dots, size: .large, groups: false, arrows: false, cityRefresh: .every60)
        XCTAssertEqual(RadarDisplay(storage: display.storageValue), display)
        XCTAssertEqual(RadarDisplay(storage: ""), .standard)
        XCTAssertEqual(RadarDisplay(storage: "{"), .standard)
        XCTAssertEqual(RadarDisplay(storage: #"{"version":1,"label":"hologram","size":"large","groups":"no"}"#),
                       RadarDisplay(size: .large), "unknown values take their default")
        XCTAssertEqual(RadarDisplay.Label.allCases.map(\.title), ["Linie", "Linie und Ziel", "Nur Punkte"])
        XCTAssertEqual(RadarDisplay.CityRefresh.allCases.map(\.title), ["Automatisch", "Alle 20 s", "Alle 60 s"])
    }
}
