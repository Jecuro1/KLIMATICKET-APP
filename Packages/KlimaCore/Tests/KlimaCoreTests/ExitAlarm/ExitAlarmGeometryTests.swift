import XCTest
@testable import KlimaCore

final class ExitAlarmGeometryTests: XCTestCase {
    typealias F = ExitAlarmFixtures

    func testPathLengthIsTheSumOfTheLegs() {
        let path = GeoPath(F.path(to: 2))
        let direct = F.salzburg.distanceKm(to: F.attnang) * 1000 + F.attnang.distanceKm(to: F.linz) * 1000
        XCTAssertEqual(path.length, direct, accuracy: 0.01)
    }

    func testRemainingDistanceAlongTheStops() {
        let spec = F.spec(stop: 2)
        let total = GeoPath(spec.path).length
        let atStart = ExitAlarmGeometry.distance(of: LocationFix(time: F.t0, coordinate: F.salzburg), spec: spec)!
        XCTAssertEqual(atStart.remaining, total, accuracy: 1)
        let mid = GeoPath(spec.path).point(at: total / 2)!
        let half = ExitAlarmGeometry.distance(of: LocationFix(time: F.t0, coordinate: mid), spec: spec)!
        XCTAssertEqual(half.remaining, total / 2, accuracy: 5)
        XCTAssertLessThan(half.offPath, 5)
        let atEnd = ExitAlarmGeometry.distance(of: LocationFix(time: F.t0, coordinate: F.linz), spec: spec)!
        XCTAssertEqual(atEnd.remaining, 0, accuracy: 1)
    }

    func testAFixFarFromTheRunHasNoGPSDistance() {
        let spec = F.spec(stop: 2)
        let farAway = GeoPoint(latitude: 46.6, longitude: 14.3)   // Klagenfurt
        XCTAssertNil(ExitAlarmGeometry.distance(of: LocationFix(time: F.t0, coordinate: farAway), spec: spec))
    }

    func testWithoutAPathTheStraightLineIsStretched() {
        var spec = F.spec(stop: 2)
        spec.path = []
        let fix = LocationFix(time: F.t0, coordinate: F.attnang)
        let direct = F.attnang.distanceKm(to: F.linz) * 1000
        XCTAssertEqual(ExitAlarmGeometry.distance(of: fix, spec: spec)!.remaining, direct * ExitAlarmGeometry.detourFactor, accuracy: 1)
        spec.stopCoordinate = nil
        XCTAssertNil(ExitAlarmGeometry.distance(of: fix, spec: spec))
    }

    func testPointAtDistanceClampsToBothEnds() {
        let path = GeoPath(F.path(to: 2))
        XCTAssertEqual(path.point(at: -5), F.salzburg)
        XCTAssertEqual(path.point(at: path.length + 5), F.linz)
        XCTAssertNil(GeoPath([]).point(at: 1))
    }

    func testSpeedSmoothingIgnoresBadFixes() {
        var motion = ExitAlarmMotion()
        XCTAssertTrue(motion.ingest(LocationFix(time: F.t0, coordinate: F.salzburg, speed: 40)))
        XCTAssertFalse(motion.ingest(LocationFix(time: F.t0.addingTimeInterval(5), coordinate: F.salzburg, speed: 40, horizontalAccuracy: 500)), "too inaccurate")
        XCTAssertFalse(motion.ingest(LocationFix(time: F.t0.addingTimeInterval(5), coordinate: F.salzburg, speed: 40, horizontalAccuracy: -1)), "invalid")
        XCTAssertFalse(motion.ingest(LocationFix(time: F.t0.addingTimeInterval(-5), coordinate: F.salzburg, speed: 40)), "older than the last")
        XCTAssertEqual(motion.smoothedSpeed ?? 0, 40, accuracy: 0.001)
    }

    func testSpeedIsDerivedFromTwoFixesWhenTheSystemReportsNone() {
        var motion = ExitAlarmMotion()
        let a = F.salzburg
        let b = GeoPath([F.salzburg, F.attnang]).point(at: 1000)!
        motion.ingest(LocationFix(time: F.t0, coordinate: a, speed: nil))
        motion.ingest(LocationFix(time: F.t0.addingTimeInterval(50), coordinate: b, speed: nil))
        XCTAssertEqual(motion.smoothedSpeed ?? 0, 20, accuracy: 0.5)
    }

    func testStableUUID() {
        XCTAssertEqual(ExitAlarmUUID.make(from: "trip|stop"), ExitAlarmUUID.make(from: "trip|stop"))
        XCTAssertNotEqual(ExitAlarmUUID.make(from: "trip|stop"), ExitAlarmUUID.make(from: "trip|stop2"))
    }

    func testSafeKeyIsAlphanumeric() {
        let spec = ExitAlarmSpec(tripID: "1|2#abc|x", lineName: "RJX 66", stopID: "A=1@L=8100002@", stopName: "Linz")
        XCTAssertTrue(spec.safeKey.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }
}
