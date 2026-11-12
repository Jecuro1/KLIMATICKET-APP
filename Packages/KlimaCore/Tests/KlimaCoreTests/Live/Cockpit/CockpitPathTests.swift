import XCTest
@testable import KlimaCore

final class CockpitPathTests: XCTestCase {
    typealias F = CockpitFixtures

    // MARK: Angles

    func testNormalizedAngle() {
        XCTAssertEqual(CockpitAngle.normalized(0), 0)
        XCTAssertEqual(CockpitAngle.normalized(360), 0)
        XCTAssertEqual(CockpitAngle.normalized(-10), 350, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.normalized(725), 5, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.normalized(.nan), 0)
        XCTAssertEqual(CockpitAngle.normalized(.infinity), 0)
    }

    func testDeltaTakesTheShortSide() {
        XCTAssertEqual(CockpitAngle.delta(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.delta(from: 10, to: 350), -20, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.delta(from: 90, to: 270), 180, accuracy: 1e-9)   // exactly opposite: either way, never more than 180
        XCTAssertEqual(abs(CockpitAngle.delta(from: 0, to: 180)), 180, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.delta(from: 100, to: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.delta(from: 720, to: 10), 10, accuracy: 1e-9)
    }

    func testBlendWrapsAndClamps() {
        XCTAssertEqual(CockpitAngle.blend(350, toward: 10, fraction: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.blend(10, toward: 350, fraction: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.blend(0, toward: 90, fraction: 2), 90, accuracy: 1e-9)
        XCTAssertEqual(CockpitAngle.blend(0, toward: 90, fraction: -1), 0, accuracy: 1e-9)
    }

    func testDestinationEastAlongAParallel() {
        let target = CockpitGeo.destination(from: F.point(14.0), bearing: 90, km: 10)
        // 10 km east at 48° N: 10 / (111.32 · cos 48°) degrees of longitude, and the great circle bends slightly towards the pole.
        XCTAssertEqual(target.longitude, 14.0 + 10 / 74.5, accuracy: 0.002)
        XCTAssertEqual(target.latitude, 48.0, accuracy: 0.002)
        let north = CockpitGeo.destination(from: F.point(14.0), bearing: 0, km: 111.2)
        XCTAssertEqual(north.latitude, 49.0, accuracy: 0.01)
        XCTAssertEqual(north.longitude, 14.0, accuracy: 1e-6)
    }

    // MARK: Path

    func testLengthAndPointAlongAStraightPath() throws {
        let path = try XCTUnwrap(CockpitPath(F.straightPolyline()))
        XCTAssertEqual(path.lengthKm, 3.2 * 74.5, accuracy: 1.0)
        F.assertClose(path.point(atKm: 0), F.point(13.9))
        F.assertClose(path.point(atKm: path.lengthKm), F.point(17.1))
        let middle = path.point(atKm: path.lengthKm / 2)
        XCTAssertEqual(middle.longitude, 15.5, accuracy: 1e-3)
        // Clamped at both ends, and a non-finite mark is the start.
        F.assertClose(path.point(atKm: -5), F.point(13.9))
        F.assertClose(path.point(atKm: 1e9), F.point(17.1))
        F.assertClose(path.point(atKm: .nan), F.point(13.9))
    }

    func testPathDropsUnusablePointsAndRepeats() throws {
        let points = [F.point(14.0), F.point(14.0), GeoPoint(latitude: .nan, longitude: 14.5), F.point(14.5), GeoPoint(latitude: 91, longitude: 0), F.point(15.0)]
        let path = try XCTUnwrap(CockpitPath(points))
        XCTAssertEqual(path.points.count, 3)
        XCTAssertNil(CockpitPath([F.point(14.0)]))
        XCTAssertNil(CockpitPath([F.point(14.0), F.point(14.0)]))
        XCTAssertNil(CockpitPath([]))
    }

    func testBearingAlongAndAroundACorner() throws {
        let east = try XCTUnwrap(CockpitPath(F.straightPolyline()))
        XCTAssertEqual(east.bearing(atKm: 20), 90, accuracy: 0.5)
        // East for 10 km, then north: at 9.8 km a 0.6 km look ahead already turns towards the corner (between east and north),
        // at 12 km the heading is north.
        let corner = F.point(14.0 + 10 / 74.5)
        let north = CockpitGeo.destination(from: corner, bearing: 0, km: 10)
        let bend = try XCTUnwrap(CockpitPath([F.point(14.0), corner, north]))
        XCTAssertEqual(bend.bearing(atKm: 5, lookKm: 0.6), 90, accuracy: 0.5)
        let before = bend.bearing(atKm: 9.7, lookKm: 0.6)
        XCTAssertTrue(before > 5 && before < 90, "looks ahead around the corner: \(before)")
        XCTAssertEqual(CockpitAngle.delta(from: bend.bearing(atKm: 12, lookKm: 0.6), to: 0), 0, accuracy: 0.6)
        // At the very end it looks back along the last piece instead of failing.
        XCTAssertEqual(bend.bearing(atKm: bend.lengthKm, lookKm: 0.6), 0, accuracy: 0.5)
    }

    func testProjectFindsTheNearestPointAndHowFarOff() throws {
        let path = try XCTUnwrap(CockpitPath(F.straightPolyline()))
        // 0.01° north of the line at 15.0 E: 1.1 km off, 81.9 km (1.1° · 74.5) along.
        let hit = try XCTUnwrap(path.project(GeoPoint(latitude: 48.01, longitude: 15.0)))
        XCTAssertEqual(hit.offKm, 1.106, accuracy: 0.02)
        XCTAssertEqual(hit.km, 1.1 * 74.5, accuracy: 0.6)
        XCTAssertNil(path.project(GeoPoint(latitude: .nan, longitude: 15.0)))
    }

    func testProjectWindowKeepsTheTrainOnItsOwnTrack() throws {
        // A hairpin: east for 20 km, a bend, and back west 1 km north of it. A point between the two legs is nearer to the way back, but a
        // train that is at 5 km along the way out has to be found on the way out.
        let out = F.point(14.0 + 20 / 74.5)
        let turnNorth = GeoPoint(latitude: 48.0 + 1.0 / 110.574, longitude: out.longitude)
        let back = GeoPoint(latitude: turnNorth.latitude, longitude: 14.0)
        let path = try XCTUnwrap(CockpitPath([F.point(14.0), out, turnNorth, back]))
        let probe = GeoPoint(latitude: 48.0 + 0.6 / 110.574, longitude: 14.0 + 5 / 74.5)
        let free = try XCTUnwrap(path.project(probe))
        XCTAssertGreaterThan(free.km, 20, "without a window the nearer way back wins")
        let windowed = try XCTUnwrap(path.project(probe, fromKm: 3, toKm: 8))
        XCTAssertEqual(windowed.km, 5, accuracy: 0.2)
        XCTAssertEqual(windowed.offKm, 0.6, accuracy: 0.05)
        XCTAssertNil(path.project(probe, fromKm: 50, toKm: 40), "an empty window finds nothing")
    }

    func testSliceCutsOnTheSegments() throws {
        let path = try XCTUnwrap(CockpitPath(F.straightPolyline()))
        let piece = path.slice(fromKm: 10, toKm: 30)
        XCTAssertGreaterThanOrEqual(piece.count, 3)
        F.assertClose(piece.first, path.point(atKm: 10))
        F.assertClose(piece.last, path.point(atKm: 30))
        // The pieces are in order and inside the range.
        XCTAssertEqual(piece.map(\.longitude), piece.map(\.longitude).sorted())
        XCTAssertTrue(path.slice(fromKm: 30, toKm: 10).isEmpty)
        XCTAssertTrue(path.slice(fromKm: 5, toKm: 5).isEmpty)
        XCTAssertEqual(path.slice(fromKm: -10, toKm: 1e9).count, path.points.count)
    }
}
