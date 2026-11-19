import XCTest
@testable import KlimaCore

// MARK: radar2-fix-radarmodes – markers on either side of a grid cell border (CI screenshot radarTrails: S45 under REX 92 at Wien).
final class RadarMarkerOverlapTests: XCTestCase {
    /// One cell = 0.1° of longitude; at 48.2° a degree of latitude is 1.5 of longitude on the map (Mercator).
    private let cell = 0.1

    private func point(_ id: String, _ latitude: Double, _ longitude: Double, _ delay: RadarDelayState = .onTime) -> RadarPoint {
        RadarPoint(tripID: id, coordinate: GeoPoint(latitude: latitude, longitude: longitude), delay: delay)
    }

    private func vehicles(_ clusters: [RadarCluster]) -> [String] { clusters.flatMap(\.tripIDs).sorted() }

    func testTwoSinglesOnEitherSideOfACellBorderBecomeOneGroup() {
        let grid = RadarClustering.group([point("rex92", 48.20, 16.295, .late), point("s45", 48.20, 16.305)], cellDegrees: cell)
        XCTAssertEqual(grid.count, 2, "the grid alone: two singles, 0.1 cells apart")
        let result = RadarMarkerOverlap.resolve(grid, cellDegrees: cell)
        XCTAssertEqual(result.clusters.count, 1)
        let group = result.clusters[0]
        XCTAssertEqual(group.tripIDs, ["rex92", "s45"])
        XCTAssertEqual(group.id, "near|rex92")
        XCTAssertEqual(group.lateCount, 1)
        XCTAssertEqual(group.center.longitude, 16.30, accuracy: 1e-9)
        XCTAssertTrue(result.compact.isEmpty)
    }

    func testMarkersAPlateApartStaySingle() {
        let apart = RadarClustering.group([point("a", 48.20, 16.215), point("b", 48.20, 16.305)], cellDegrees: cell)   // 0.9 cells
        XCTAssertEqual(RadarMarkerOverlap.resolve(apart, cellDegrees: cell).clusters, apart.sorted { $0.id < $1.id })
    }

    func testTheHeightCountsOnTheMapNotInDegrees() {
        // 0.03° of latitude at 48.2° are 0.45 cells on the map (under half a plate): one group; 0.04° are 0.6 cells: two markers.
        let close = RadarClustering.group([point("a", 48.215, 16.295), point("b", 48.185, 16.305)], cellDegrees: cell)
        XCTAssertEqual(RadarMarkerOverlap.resolve(close, cellDegrees: cell).clusters.count, 1)
        let stacked = RadarClustering.group([point("a", 48.22, 16.295), point("b", 48.18, 16.305)], cellDegrees: cell)
        XCTAssertEqual(RadarMarkerOverlap.resolve(stacked, cellDegrees: cell).clusters.count, 2)
    }

    func testAKeptMarkerIsNeverFoldedAndASingleUnderItsPlateIsADot() {
        let kept = RadarClustering.single(point("rex92", 48.20, 16.295))
        let grid = RadarClustering.group([point("s45", 48.20, 16.305)], cellDegrees: cell) + [kept]
        let result = RadarMarkerOverlap.resolve(grid, cellDegrees: cell, kept: ["rex92"])
        XCTAssertEqual(result.clusters.count, 2, "both stay on the map")
        XCTAssertTrue(result.clusters.allSatisfy(\.isSingle))
        XCTAssertEqual(result.compact, ["s45"], "the other one is drawn as a dot")
        // Two kept markers: neither is folded, neither is a dot.
        let both = RadarMarkerOverlap.resolve(grid, cellDegrees: cell, kept: ["rex92", "s45"])
        XCTAssertEqual(both.clusters.count, 2)
        XCTAssertTrue(both.compact.isEmpty)
    }

    func testAGroupNextToAKeptMarkerStaysAGroup() {
        let kept = RadarClustering.single(point("rjx66", 48.20, 16.295))
        let grid = RadarClustering.group([point("a", 48.20, 16.302), point("b", 48.20, 16.308)], cellDegrees: cell) + [kept]
        let result = RadarMarkerOverlap.resolve(grid, cellDegrees: cell, kept: ["rjx66"])
        XCTAssertEqual(result.clusters.count, 2)
        XCTAssertEqual(result.clusters.first { !$0.isSingle }?.tripIDs, ["a", "b"])
        XCTAssertTrue(result.compact.isEmpty)
    }

    func testAGroupTakesTheKeyOfItsLargestCellAndCountsAddUp() {
        let grid = RadarClustering.group([point("a", 48.20, 16.291), point("b", 48.20, 16.292), point("c", 48.20, 16.293),
                                          point("d", 48.20, 16.305, .cancelled)], cellDegrees: cell)
        let largest = grid.first { $0.count == 3 }!
        let result = RadarMarkerOverlap.resolve(grid, cellDegrees: cell)
        XCTAssertEqual(result.clusters.count, 1)
        XCTAssertEqual(result.clusters[0].id, largest.id)
        XCTAssertEqual(result.clusters[0].count, 4)
        XCTAssertEqual(result.clusters[0].cancelledCount, 1)
        XCTAssertEqual(result.clusters[0].center.longitude, (16.291 + 16.292 + 16.293 + 16.305) / 4, accuracy: 1e-9)
    }

    func testNoMarkerOverlapsAfterwardsAndEveryVehicleStaysOnce() {
        for seed in 0..<12 {
            var generator = OverlapSeededGenerator(seed: UInt64(seed))
            let points = (0..<Int.random(in: 2...400, using: &generator)).map { index in
                point("t\(index)", Double.random(in: 47.8...48.6, using: &generator), Double.random(in: 15.8...17.0, using: &generator),
                      RadarDelayState.allCases.randomElement(using: &generator)!)
            }
            let kept = Set(points.prefix(3).map(\.tripID))
            let grid = RadarClustering.group(points.filter { !kept.contains($0.tripID) }, cellDegrees: cell)
                + points.filter { kept.contains($0.tripID) }.map(RadarClustering.single)
            let result = RadarMarkerOverlap.resolve(grid, cellDegrees: cell, kept: kept)
            XCTAssertEqual(vehicles(result.clusters), points.map(\.tripID).sorted(), "seed \(seed): every vehicle once")
            XCTAssertEqual(Set(result.clusters.map(\.id)).count, result.clusters.count, "seed \(seed): unique ids")
            XCTAssertEqual(result.clusters.reduce(0) { $0 + $1.lateCount }, points.filter { $0.delay == .late }.count)
            for id in kept { XCTAssertTrue(result.clusters.contains { $0.tripIDs == [id] }, "seed \(seed): \(id) stays single") }
            let free = result.clusters.filter { !($0.isSingle && kept.contains($0.tripIDs[0])) }.map { RadarMarkerOverlap.screen($0.center, cell) }
            for i in free.indices {
                for j in free.indices where j > i {
                    XCTAssertFalse(abs(free[i].x - free[j].x) < RadarMarkerOverlap.reachX && abs(free[i].y - free[j].y) < RadarMarkerOverlap.reachY,
                                   "seed \(seed): two markers still overlap")
                }
            }
            let again = RadarMarkerOverlap.resolve(grid.shuffled(using: &generator), cellDegrees: cell, kept: kept)
            XCTAssertEqual(again, result, "seed \(seed): the same markers for the same vehicles, in any order")
        }
    }

    func testNothingChangesWithoutAValidCell() {
        let grid = RadarClustering.group([point("a", 48.20, 16.295), point("b", 48.20, 16.305)], cellDegrees: cell)
        XCTAssertEqual(RadarMarkerOverlap.resolve(grid, cellDegrees: 0).clusters, grid)
        XCTAssertEqual(RadarMarkerOverlap.resolve(grid, cellDegrees: .nan).clusters, grid)
        XCTAssertEqual(RadarMarkerOverlap.resolve([], cellDegrees: cell).clusters, [])
    }
}

private struct OverlapSeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
