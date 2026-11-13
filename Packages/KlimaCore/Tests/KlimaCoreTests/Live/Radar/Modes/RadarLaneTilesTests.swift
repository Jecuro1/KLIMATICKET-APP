import XCTest
@testable import KlimaCore

// MARK: radarmodes – the tile grid with two lanes (docs/RADAR_MODES.md §3): city tiles go down to level 8, wide tiles stay at 6.
final class RadarLaneTilesTests: XCTestCase {
    func testTheLaneIsKeptByChildrenAndParent() {
        let city = RadarTileKey(level: 5, row: 20, col: 30, lane: .city)
        let children = RadarTileGrid.children(of: city)
        XCTAssertEqual(children.count, 4)
        XCTAssertTrue(children.allSatisfy { $0.lane == .city && $0.level == 6 })
        XCTAssertEqual(RadarTileGrid.parent(of: children[3]), city)
        let wide = RadarTileKey(level: 5, row: 20, col: 30)
        XCTAssertEqual(wide.lane, .wide, "a key without a lane is a wide tile")
        XCTAssertNotEqual(wide, city, "the same place in two lanes is two tiles")
        XCTAssertTrue(RadarTileGrid.children(of: wide).allSatisfy { $0.lane == .wide })
    }

    func testCityLevelsSevenAndEightAreValidWideLevelSevenIsNot() {
        XCTAssertEqual(RadarTileGrid.maxLevel, 6, "the wide lane is unchanged")
        XCTAssertEqual(RadarTileGrid.cityMaxLevel, 8)
        XCTAssertTrue(RadarTileGrid.isValid(RadarTileKey(level: 7, row: 0, col: 0, lane: .city)))
        XCTAssertTrue(RadarTileGrid.isValid(RadarTileKey(level: 8, row: 255, col: 511, lane: .city)))
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 9, row: 0, col: 0, lane: .city)))
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 8, row: 256, col: 0, lane: .city)))
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 7, row: 0, col: 0)))
        XCTAssertTrue(RadarTileGrid.children(of: RadarTileKey(level: 8, row: 3, col: 3, lane: .city)).isEmpty)
        XCTAssertTrue(RadarTileGrid.children(of: RadarTileKey(level: 6, row: 3, col: 3)).isEmpty)
        XCTAssertEqual(RadarTileGrid.children(of: RadarTileKey(level: 6, row: 3, col: 3, lane: .city)).count, 4)
    }

    func testCityLevelIsOneFinerThanTheWideLevelUpToEight() {
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 0.12), 4)
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 0.12), 5, "a Wien view: 9.7 × 9 km tiles")
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 0.6), 3)
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 0.03), 7)
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 0.002), 8, "clamped at the finest city level")
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 1e-320), 8)
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 10), 1, "a span above the root: level 0 plus the offset")
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: .nan), 1)
        XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: 0.12, offset: 0), 4)
        for span in stride(from: 0.03, through: 0.6, by: 0.01) {
            XCTAssertEqual(RadarTileGrid.cityLevel(forLatitudeSpan: span), min(RadarTileGrid.level(forLatitudeSpan: span) + 1, 8), "span \(span)")
        }
    }

    func testTilesIntersectingCarryTheLaneAndClampAtItsFinestLevel() {
        let box = RadarBox(north: 48.215, west: 16.36, south: 48.205, east: 16.38)
        let city = RadarTileGrid.tiles(intersecting: box, level: 8, lane: .city)
        XCTAssertFalse(city.isEmpty)
        XCTAssertTrue(city.allSatisfy { $0.lane == .city && $0.level == 8 })
        let wide = RadarTileGrid.tiles(intersecting: box, level: 8)
        XCTAssertTrue(wide.allSatisfy { $0.lane == .wide && $0.level == 6 }, "the wide lane clamps at 6 as before")
        XCTAssertEqual(RadarTileGrid.tiles(intersecting: box, level: 9, lane: .city).first?.level, 8)
    }

    func testABoxOfLevelEightIsAQuarterOfItsLevelSevenParent() {
        let parent = RadarTileKey(level: 7, row: 80, col: 175, lane: .city)
        let parentBox = RadarTileGrid.box(of: parent)
        XCTAssertEqual(parentBox.north - parentBox.south, 2.8 / 128, accuracy: 1e-12)
        XCTAssertEqual(parentBox.east - parentBox.west, 3.9 / 128, accuracy: 1e-12)
        for child in RadarTileGrid.children(of: parent) {
            let box = RadarTileGrid.box(of: child)
            XCTAssertEqual(box.north - box.south, (parentBox.north - parentBox.south) / 2, accuracy: 1e-12)
            XCTAssertEqual(box.east - box.west, (parentBox.east - parentBox.west) / 2, accuracy: 1e-12)
            XCTAssertTrue(box.south >= parentBox.south - 1e-12 && box.north <= parentBox.north + 1e-12)
            XCTAssertTrue(box.west >= parentBox.west - 1e-12 && box.east <= parentBox.east + 1e-12)
        }
        // About 1.2 × 1.1 km.
        let eight = RadarTileGrid.box(of: RadarTileGrid.children(of: parent)[0])
        XCTAssertEqual((eight.north - eight.south) * 111.2, 1.2, accuracy: 0.05)
        XCTAssertEqual((eight.east - eight.west) * 74.0, 1.1, accuracy: 0.05)
    }

    func testLabelsTellTheLanesApart() {
        XCTAssertEqual(RadarTileKey(level: 2, row: 1, col: 3).label, "2/1/3")
        XCTAssertEqual(RadarTileKey(level: 7, row: 1, col: 3, lane: .city).label, "c7/1/3")
        XCTAssertTrue(RadarTileKey(level: 8, row: 0, col: 0) < RadarTileKey(level: 0, row: 0, col: 0, lane: .city), "wide tiles sort first")
    }
}
