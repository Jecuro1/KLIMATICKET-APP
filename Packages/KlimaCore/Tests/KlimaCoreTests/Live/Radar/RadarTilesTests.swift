import XCTest
@testable import KlimaCore

/// The fixed tile grid of the Zug-Radar (docs/OEBB_LIVE.md §R11): keys, boxes, levels by zoom, children and parents.
final class RadarTilesTests: XCTestCase {
    func testLevelZeroIsTwoTilesThatTogetherAreAustria() {
        let west = RadarTileGrid.box(of: RadarTileKey(level: 0, row: 0, col: 0))
        let east = RadarTileGrid.box(of: RadarTileKey(level: 0, row: 0, col: 1))
        let austria = RadarBox.austria
        XCTAssertEqual(west.south, austria.south, accuracy: 1e-9)
        XCTAssertEqual(west.north, austria.north, accuracy: 1e-9)
        XCTAssertEqual(west.west, austria.west, accuracy: 1e-9)
        XCTAssertEqual(east.east, austria.east, accuracy: 1e-9)
        XCTAssertEqual(west.east, east.west, "the two halves share their edge exactly")
        XCTAssertEqual(RadarTileGrid.rows(atLevel: 0), 1)
        XCTAssertEqual(RadarTileGrid.columns(atLevel: 0), 2)
        XCTAssertEqual(RadarTileGrid.columns(atLevel: 6), 128)
    }

    func testChildrenTileTheirParentExactlyAndNeighboursShareEdgesBitForBit() throws {
        for parent in [RadarTileKey(level: 0, row: 0, col: 1), RadarTileKey(level: 2, row: 3, col: 5), RadarTileKey(level: 5, row: 17, col: 40)] {
            let box = RadarTileGrid.box(of: parent)
            let kids = RadarTileGrid.children(of: parent)
            XCTAssertEqual(kids.count, 4)
            let boxes = kids.map(RadarTileGrid.box(of:))
            XCTAssertEqual(boxes.map(\.north).max(), box.north, "child north edge is the parent's")
            XCTAssertEqual(boxes.map(\.south).min(), box.south)
            XCTAssertEqual(boxes.map(\.east).max(), box.east)
            XCTAssertEqual(boxes.map(\.west).min(), box.west)
            let area = boxes.reduce(0.0) { $0 + ($1.north - $1.south) * ($1.east - $1.west) }
            XCTAssertEqual(area, (box.north - box.south) * (box.east - box.west), accuracy: 1e-9)
            for kid in kids { XCTAssertEqual(RadarTileGrid.parent(of: kid), parent) }
        }
        let a = RadarTileGrid.box(of: RadarTileKey(level: 4, row: 3, col: 7))
        let b = RadarTileGrid.box(of: RadarTileKey(level: 4, row: 4, col: 7))
        let c = RadarTileGrid.box(of: RadarTileKey(level: 4, row: 3, col: 8))
        XCTAssertEqual(a.north, b.south, "no gap and no overlap between neighbours")
        XCTAssertEqual(a.east, c.west)
    }

    func testFinestLevelAndInvalidKeys() {
        XCTAssertTrue(RadarTileGrid.children(of: RadarTileKey(level: RadarTileGrid.maxLevel, row: 0, col: 0)).isEmpty)
        XCTAssertNil(RadarTileGrid.parent(of: RadarTileKey(level: 0, row: 0, col: 0)))
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 1, row: 2, col: 0)), "level 1 has rows 0 and 1")
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 1, row: 0, col: 4)), "and columns 0 to 3")
        XCTAssertFalse(RadarTileGrid.isValid(RadarTileKey(level: 7, row: 0, col: 0)))
        XCTAssertTrue(RadarTileGrid.isValid(RadarTileKey(level: 6, row: 63, col: 127)))
        // The finest tile is about 4.9 x 9 km: small enough for the densest bus areas.
        let finest = RadarTileGrid.box(of: RadarTileKey(level: 6, row: 0, col: 0))
        XCTAssertEqual(finest.north - finest.south, 2.8 / 64, accuracy: 1e-9)
        XCTAssertEqual(finest.east - finest.west, 3.9 / 64, accuracy: 1e-9)
    }

    func testLevelFollowsTheZoomSoAViewTouchesAtMostFourTiles() {
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 4.2), 0, "the Austria view")
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 2.8), 0)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 1.4), 1)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 0.9), 1, "Wien zoom: tiles of 1.4 degrees")
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 0.2), 3)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 0.0001), RadarTileGrid.maxLevel)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: .nan), 0)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: -3), 0)
        XCTAssertEqual(RadarTileGrid.level(forLatitudeSpan: 1e-320), RadarTileGrid.maxLevel, "a denormal span must not trap")

        // Across spans and positions a view never needs more than 2 x 2 tiles.
        var worst = 0
        for span in stride(from: 0.03, through: 4.2, by: 0.07) {
            for centreLat in stride(from: 46.5, through: 48.9, by: 0.37) {
                for centreLon in stride(from: 9.8, through: 17.0, by: 0.61) {
                    let box = RadarBox(north: centreLat + span / 2, west: centreLon - span * 0.35,
                                       south: centreLat - span / 2, east: centreLon + span * 0.35)
                    let tiles = RadarTileGrid.tiles(intersecting: box, level: RadarTileGrid.level(forLatitudeSpan: span))
                    worst = max(worst, tiles.count)
                }
            }
        }
        XCTAssertLessThanOrEqual(worst, 4)
    }

    func testTilesIntersectingTheViewAreClippedToTheCoverage() {
        let all = RadarTileGrid.tiles(intersecting: RadarBox(north: 52, west: 5, south: 43, east: 22), level: 0)
        XCTAssertEqual(all, [RadarTileKey(level: 0, row: 0, col: 0), RadarTileKey(level: 0, row: 0, col: 1)])
        XCTAssertTrue(RadarTileGrid.tiles(intersecting: RadarBox(north: 52, west: 5, south: 50, east: 6), level: 0).isEmpty, "Germany only: no tiles")
        XCTAssertTrue(RadarTileGrid.tiles(intersecting: RadarBox(north: 47, west: 13, south: 47, east: 14), level: 0).isEmpty, "degenerate box")
        // A box that only touches the shared edge of two tiles belongs to one of them.
        let edge = RadarTileGrid.box(of: RadarTileKey(level: 0, row: 0, col: 0)).east
        let touching = RadarTileGrid.tiles(intersecting: RadarBox(north: 48, west: edge - 1, south: 47, east: edge), level: 0)
        XCTAssertEqual(touching, [RadarTileKey(level: 0, row: 0, col: 0)])
    }

    func testEveryPointOfAustriaIsInExactlyOneTileAtEveryLevel() {
        for level in 0...RadarTileGrid.maxLevel {
            for lat in stride(from: 46.31, through: 49.09, by: 0.31) {
                for lon in stride(from: 9.46, through: 17.24, by: 0.53) {
                    let tiny = RadarBox(north: lat + 1e-6, west: lon - 1e-6, south: lat - 1e-6, east: lon + 1e-6)
                    let tiles = RadarTileGrid.tiles(intersecting: tiny, level: level)
                    XCTAssertEqual(tiles.count, 1, "level \(level) at \(lat), \(lon)")
                    if let tile = tiles.first { XCTAssertTrue(RadarTileGrid.box(of: tile).contains(GeoPoint(latitude: lat, longitude: lon))) }
                }
            }
        }
    }

    func testBoxIntersectionIgnoresBoxesThatOnlyTouch() {
        let a = RadarBox(north: 48, west: 13, south: 47, east: 14)
        XCTAssertTrue(a.intersects(RadarBox(north: 47.5, west: 13.5, south: 46, east: 15)))
        XCTAssertFalse(a.intersects(RadarBox(north: 47, west: 13, south: 46, east: 14)), "shares the south edge only")
        XCTAssertFalse(a.intersects(RadarBox(north: 48, west: 14, south: 47, east: 15)), "shares the east edge only")
    }
}
