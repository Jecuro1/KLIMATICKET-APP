import XCTest
@testable import KlimaCore

/// The hexagonal heat grid (docs/RADAR_HEATMAP.md §2): stable ids, regular cells, one cell per point, hatching inside the cell.
final class HeatGridTests: XCTestCase {
    func testTheOriginIsCellZeroAndIdsAreStable() {
        let origin = GeoPoint(latitude: HeatGrid.originLatitude, longitude: HeatGrid.originLongitude)
        XCTAssertEqual(HeatGrid.cell(containing: origin), HeatCellID(q: 0, r: 0))
        // The same place, asked again and from a few metres away, is the same cell: ids never depend on anything but the place.
        let innsbruck = GeoPoint(latitude: 47.2631, longitude: 11.4010)
        let first = HeatGrid.cell(containing: innsbruck)
        XCTAssertEqual(HeatGrid.cell(containing: innsbruck), first)
        XCTAssertEqual(HeatGrid.cell(containing: GeoPoint(latitude: 47.2632, longitude: 11.4011)), first)
        XCTAssertEqual(first.label, "\(first.q)|\(first.r)")
    }

    func testCentreRoundTripForAWideRangeOfCells() {
        for q in -45...45 {
            for r in -20...20 {
                let id = HeatCellID(q: q, r: r)
                XCTAssertEqual(HeatGrid.cell(containing: HeatGrid.center(of: id)), id, "cell \(id.label)")
            }
        }
    }

    func testEveryPointBelongsToExactlyTheNearestCentre() {
        var generator = HeatRandom(seed: 7)
        for _ in 0..<500 {
            let point = GeoPoint(latitude: 46.3 + generator.unit() * 2.8, longitude: 9.45 + generator.unit() * 7.8)
            let id = HeatGrid.cell(containing: point)
            let own = HeatGrid.distanceKm(point, HeatGrid.center(of: id))
            XCTAssertLessThanOrEqual(own, HeatGrid.radiusKm + 1e-6, "a point is never farther from its cell's centre than the corner is")
            for neighbour in HeatGrid.neighbors(of: id) {
                XCTAssertLessThanOrEqual(own, HeatGrid.distanceKm(point, HeatGrid.center(of: neighbour)) + 1e-6)
            }
        }
    }

    func testCellsAreRegularAboutTwelveHundredthsOfADegree() {
        // Neighbours are 0.12° of latitude apart (13.3 km), the brief's "about 0.12 degrees".
        let id = HeatCellID(q: 3, r: -2)
        let kmSpacing = HeatGrid.spacingDegrees * HeatGrid.kmPerDegreeLatitude
        for neighbour in HeatGrid.neighbors(of: id) {
            XCTAssertEqual(HeatGrid.distanceKm(HeatGrid.center(of: id), HeatGrid.center(of: neighbour)), kmSpacing, accuracy: 1e-6)
            XCTAssertEqual(HeatGrid.distance(id, neighbour), 1)
            XCTAssertEqual(HeatGrid.distance(neighbour, id), 1)
        }
        XCTAssertEqual(HeatGrid.neighbors(of: id).count, 6)
        XCTAssertEqual(Set(HeatGrid.neighbors(of: id)).count, 6)
        let corners = HeatGrid.vertices(of: id)
        XCTAssertEqual(corners.count, 6)
        for corner in corners {
            XCTAssertEqual(HeatGrid.distanceKm(corner, HeatGrid.center(of: id)), HeatGrid.radiusKm, accuracy: 1e-6)
        }
        XCTAssertEqual(HeatGrid.cellAreaKm2, 154.2, accuracy: 0.5)
    }

    func testNeighbouringCellsShareAnEdge() {
        let id = HeatCellID(q: 0, r: 0)
        for neighbour in HeatGrid.neighbors(of: id) {
            let mine = HeatGrid.vertices(of: id), theirs = HeatGrid.vertices(of: neighbour)
            let shared = mine.filter { a in theirs.contains { HeatGrid.distanceKm(a, $0) < 1e-6 } }
            XCTAssertEqual(shared.count, 2, "two cells that touch share two corners: no gap, no overlap")
        }
    }

    func testSmallerScaleStaysInsideTheCell() {
        let id = HeatCellID(q: -4, r: 5)
        let inner = HeatGrid.vertices(of: id, scale: 0.5)
        for corner in inner {
            XCTAssertEqual(HeatGrid.distanceKm(corner, HeatGrid.center(of: id)), HeatGrid.radiusKm * 0.5, accuracy: 1e-6)
        }
    }

    func testTheGridCoversAustriaWithAboutTwelveHundredCells() {
        var cells = Set<HeatCellID>()
        var latitude = RadarBox.austria.south
        while latitude <= RadarBox.austria.north {
            var longitude = RadarBox.austria.west
            while longitude <= RadarBox.austria.east {
                cells.insert(HeatGrid.cell(containing: GeoPoint(latitude: latitude, longitude: longitude)))
                longitude += 0.02
            }
            latitude += 0.02
        }
        XCTAssertTrue((1_050...1_350).contains(cells.count), "the radar rectangle holds about 1 200 cells, got \(cells.count)")
    }

    func testNonFinitePointsGetTheOriginCellInsteadOfCrashing() {
        XCTAssertEqual(HeatGrid.cell(containing: GeoPoint(latitude: .nan, longitude: 12)), HeatCellID(q: 0, r: 0))
        XCTAssertEqual(HeatGrid.cell(containing: GeoPoint(latitude: 47, longitude: .infinity)), HeatCellID(q: 0, r: 0))
    }

    func testPositionsBeyondTheGlobeAreInvalidAndNeverTrapTheIntegerConversion() {
        XCTAssertTrue(HeatGrid.isValid(GeoPoint(latitude: 47.3, longitude: 11.7)))
        XCTAssertTrue(HeatGrid.isValid(GeoPoint(latitude: -90, longitude: 180)))
        for bad in [GeoPoint(latitude: 90.1, longitude: 0), GeoPoint(latitude: 0, longitude: -180.5), GeoPoint(latitude: 1e300, longitude: 12),
                    GeoPoint(latitude: 47, longitude: -1e300), GeoPoint(latitude: .nan, longitude: 12), GeoPoint(latitude: 47, longitude: .infinity)] {
            XCTAssertFalse(HeatGrid.isValid(bad))
            // A finite 1e300 would overflow `Int(rq)`: it must give the origin cell, not trap.
            XCTAssertEqual(HeatGrid.cell(containing: bad), HeatCellID(q: 0, r: 0))
        }
    }

    func testIdsAreSortedRowByRowFromTheSouth() {
        let ids = [HeatCellID(q: 5, r: 1), HeatCellID(q: -2, r: 1), HeatCellID(q: 9, r: -3), HeatCellID(q: 0, r: 0)]
        XCTAssertEqual(ids.sorted(), [HeatCellID(q: 9, r: -3), HeatCellID(q: 0, r: 0), HeatCellID(q: -2, r: 1), HeatCellID(q: 5, r: 1)])
    }

    // MARK: Hatching

    func testHatchPathStaysInsideTheCell() {
        let id = HeatCellID(q: 2, r: 3)
        let path = HeatGrid.hatchPath(of: id, lines: 3)
        XCTAssertEqual(path.count, 6, "three chords, two ends each")
        for point in path {
            XCTAssertLessThanOrEqual(HeatGrid.distanceKm(point, HeatGrid.center(of: id)), HeatGrid.radiusKm * 0.78 + 1e-6)
        }
        // The chords run at 45°: both ends of each differ equally in x and in y.
        for index in stride(from: 0, to: path.count, by: 2) {
            let a = HeatGrid.project(path[index]), b = HeatGrid.project(path[index + 1])
            XCTAssertEqual(abs(b.x - a.x), abs(b.y - a.y), accuracy: 1e-6)
            XCTAssertGreaterThan(HeatGrid.distanceKm(path[index], path[index + 1]), 1)
        }
    }

    func testHatchPathEdgeCases() {
        let id = HeatCellID(q: 0, r: 0)
        XCTAssertTrue(HeatGrid.hatchPath(of: id, lines: 0).isEmpty)
        XCTAssertTrue(HeatGrid.hatchPath(of: id, lines: -2).isEmpty)
        XCTAssertEqual(HeatGrid.hatchPath(of: id, lines: 1).count, 2)
        XCTAssertEqual(HeatGrid.hatchPath(of: id, lines: 5).count, 10)
        XCTAssertEqual(HeatGrid.hatchPath(of: id, lines: 3), HeatGrid.hatchPath(of: id, lines: 3), "deterministic")
    }
}

/// A fixed-seed generator for the tests: the same trains every run.
struct HeatRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
