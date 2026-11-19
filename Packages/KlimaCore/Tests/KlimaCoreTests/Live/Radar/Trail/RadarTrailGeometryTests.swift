import XCTest
@testable import KlimaCore

/// „Spuren“: a trail ends at the drawn marker, breaks at gaps, is thinned for the zoom and fades in two halves (docs/RADAR_TRAILS.md §2).
final class RadarTrailGeometryTests: XCTestCase {
    private typealias F = TrailFixture
    /// About 1 m per point: a close city zoom, so the tolerance is its floor of 10 m.
    private let span = 0.0072
    private let height = 800.0

    private func samples(_ points: [(seconds: Double, north: Double, east: Double)]) -> [RadarTrailSample] {
        points.map { RadarTrailSample(from: F.at($0.seconds), coordinate: F.point(north: $0.north, east: $0.east)) }
    }

    private func straight(count: Int, every seconds: Double = 20, step: Double = 300) -> [RadarTrailSample] {
        samples((0..<count).map { (Double($0) * seconds, Double($0) * step, 0) })
    }

    func testSamplesNewerThanTheDrawnMomentAreLeftOutAndTheLineEndsAtTheMarker() {
        let all = straight(count: 5)   // 0, 20, 40, 60, 80 s
        let marker = F.point(north: 750)   // between the answers of 40 s and 60 s
        let lines = RadarTrailGeometry.lines(for: all, until: F.at(50), drawnPoint: marker, spanDegrees: 0.2, heightPoints: height)
        XCTAssertEqual(lines.count, 1)
        let points = lines[0].points
        XCTAssertEqual(points.last?.coordinate, marker, "the line ends exactly at the drawn point")
        XCTAssertEqual(points.last?.at, F.at(50))
        XCTAssertFalse(points.contains { $0.at > F.at(50) }, "no line beyond the marker")
        XCTAssertLessThan(points.map(\.coordinate.latitude).max() ?? 0, F.point(north: 751).latitude)
        XCTAssertTrue(lines[0].isNewest)
    }

    func testAGapOfOneHundredFiftySecondsJoinsAndOneHundredFiftyOneSplits() {
        let joined = samples([(0, 0, 0), (20, 300, 0), (170, 600, 0)])
        XCTAssertEqual(RadarTrailGeometry.lines(for: joined, until: F.at(170), drawnPoint: nil, spanDegrees: span, heightPoints: height).count, 1)
        let split = samples([(0, 0, 0), (20, 300, 0), (171, 600, 0)])
        let lines = RadarTrailGeometry.lines(for: split, until: F.at(171), drawnPoint: nil, spanDegrees: span, heightPoints: height)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.isNewest), [false, true])
    }

    func testTheDrawnPointIsNotJoinedAcrossAGap() {
        let old = samples([(0, 0, 0), (20, 300, 0)])
        let lines = RadarTrailGeometry.lines(for: old, until: F.at(300), drawnPoint: F.point(north: 2_000), spanDegrees: span,
                                             heightPoints: height)
        XCTAssertEqual(lines.count, 2, "back after a long gap: the missing minutes are a gap, never a line")
        XCTAssertEqual(lines.last?.points.count, 1)
        XCTAssertFalse(lines.last?.isVisible ?? true)
    }

    func testDouglasPeuckerKeepsTheEndsAndARightAngleAndDropsAWiggle() {
        let corner = samples([(0, 0, 0), (20, 100, 0), (40, 200, 0), (60, 200, 100), (80, 200, 200)])
        let kept = RadarTrailGeometry.simplify(corner.map { RadarTrailPoint(coordinate: $0.coordinate, at: $0.from) }, toleranceMeters: 20)
        XCTAssertEqual(kept.map(\.at), [F.at(0), F.at(40), F.at(80)], "both ends and the 90° corner stay")
        let wiggle = samples([(0, 0, 0), (20, 100, 5), (40, 200, 0)])
        let thinned = RadarTrailGeometry.simplify(wiggle.map { RadarTrailPoint(coordinate: $0.coordinate, at: $0.from) }, toleranceMeters: 20)
        XCTAssertEqual(thinned.count, 2, "a 5 m wiggle goes")
    }

    func testToleranceIsTwoScreenPointsButAtLeastTenMetres() {
        XCTAssertEqual(RadarTrailGeometry.metersPerPoint(spanDegrees: 0.5, heightPoints: 800), 0.5 * 111_195 / 800, accuracy: 0.001)
        // 1 m a point at this zoom: an 8 m wiggle is still thinned away (the 10 m floor).
        let wiggle = samples([(0, 0, 0), (20, 100, 8), (40, 200, 0)])
        let runs = RadarTrailGeometry.simplifiedRuns(for: wiggle, until: F.at(40), metersPerPoint: 1)
        XCTAssertEqual(runs.first?.count, 2)
    }

    func testAtMostThirtyPointsIncludingTheDrawnOne() {
        var zigzag: [(Double, Double, Double)] = []
        for i in 0..<70 { zigzag.append((Double(i) * 20, Double(i) * 200, i.isMultiple(of: 2) ? 0 : 150)) }
        let lines = RadarTrailGeometry.lines(for: samples(zigzag), until: F.at(69 * 20), drawnPoint: F.point(north: 13_900, east: 50),
                                             spanDegrees: span, heightPoints: height)
        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThanOrEqual(lines[0].points.count, RadarTrailGeometry.maxPoints)
        XCTAssertEqual(lines[0].points.first?.at, F.at(0), "the oldest end stays")
        XCTAssertEqual(lines[0].points.last?.coordinate, F.point(north: 13_900, east: 50), "the drawn point stays")
    }

    func testTheHalvesShareTheirMiddlePoint() {
        let lines = RadarTrailGeometry.lines(for: straight(count: 4, step: 1_000), until: F.at(60), drawnPoint: F.point(north: 3_000),
                                             spanDegrees: 0.2, heightPoints: height)
        let halves = lines[0].halves
        XCTAssertFalse(halves.older.isEmpty)
        XCTAssertFalse(halves.newer.isEmpty)
        XCTAssertEqual(halves.older.last, halves.newer.first)
        XCTAssertEqual(halves.older.last?.at, F.at(30), "split at the middle moment")
        XCTAssertEqual(halves.older.first?.at, F.at(0))
        XCTAssertEqual(halves.newer.last?.at, F.at(60))
        // A line of two points still fades: the middle is interpolated.
        let two = RadarTrailLine(points: [RadarTrailPoint(coordinate: F.base, at: F.at(0)),
                                          RadarTrailPoint(coordinate: F.point(north: 1_000), at: F.at(100))], isNewest: true, isVisible: true)
        XCTAssertEqual(two.halves.older.count, 2)
        XCTAssertEqual(two.halves.newer.count, 2)
        XCTAssertEqual(two.halves.older[1].coordinate.latitude, F.point(north: 500).latitude, accuracy: 1e-9)
    }

    func testALineShorterThanSixScreenPointsIsInvisible() {
        // 0.2° over 800 pt ≈ 27.8 m a point: 100 m is 3.6 points.
        let short = straight(count: 2, step: 50)
        let hidden = RadarTrailGeometry.lines(for: short, until: F.at(20), drawnPoint: F.point(north: 100), spanDegrees: 0.2, heightPoints: height)
        XCTAssertFalse(hidden[0].isVisible)
        let long = straight(count: 2, step: 100)
        let shown = RadarTrailGeometry.lines(for: long, until: F.at(20), drawnPoint: F.point(north: 200), spanDegrees: 0.2, heightPoints: height)
        XCTAssertTrue(shown[0].isVisible, "200 m is 7.2 points")
    }

    func testAStandingVehicleDrawsNoTrail() {
        let stand = [RadarTrailSample(from: F.at(0), to: F.at(300), coordinate: F.base)]
        let lines = RadarTrailGeometry.lines(for: stand, until: F.at(300), drawnPoint: F.base, spanDegrees: span, heightPoints: height)
        XCTAssertTrue(lines.allSatisfy { !$0.isVisible })
    }

    func testLongitudeIsScaledByTheCosineOfTheLatitude() {
        let a = GeoPoint(latitude: 47, longitude: 13)
        let b = GeoPoint(latitude: 47, longitude: 13.01)
        XCTAssertEqual(RadarTrailGeometry.distance(a, b), 0.01 * 111_195 * cos(47 * Double.pi / 180), accuracy: 0.5)
        XCTAssertEqual(RadarTrailGeometry.distance(a, b), a.distanceKm(to: b) * 1000, accuracy: 1)
        // At 47° N a 30 m sideways wiggle survives a 20 m tolerance, a 10 m one does not (degrees east are shorter than north).
        let origin = GeoPoint(latitude: 47, longitude: 13)
        func line(_ east: Double) -> [RadarTrailPoint] {
            [RadarTrailPoint(coordinate: origin, at: F.at(0)),
             RadarTrailPoint(coordinate: F.point(north: 500, east: east, from: origin), at: F.at(20)),
             RadarTrailPoint(coordinate: F.point(north: 1_000, from: origin), at: F.at(40))]
        }
        XCTAssertEqual(RadarTrailGeometry.simplify(line(30), toleranceMeters: 20).count, 3)
        XCTAssertEqual(RadarTrailGeometry.simplify(line(10), toleranceMeters: 20).count, 2)
    }
}
