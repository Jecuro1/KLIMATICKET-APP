import XCTest
@testable import KlimaCore

final class CockpitCameraTests: XCTestCase {
    typealias F = CockpitFixtures

    private func eastInput(km: Double = 40, speed: Double? = 120, mode: CockpitCameraMode = .follow, reduceMotion: Bool = false) -> CockpitCameraInput {
        let path = CockpitPath(F.straightPolyline())!
        return CockpitCameraInput(train: path.point(atKm: km), trainKm: km, path: path, speedKmh: speed, mode: mode, reduceMotion: reduceMotion)
    }

    // MARK: Distance, pitch, look-ahead

    func testFollowDistanceGrowsWithSpeedWithinLimits() {
        let config = CockpitCameraConfig.standard
        var last = 0.0
        for speed in stride(from: 0.0, through: 300.0, by: 10) {
            let distance = CockpitCameraPlanner.followDistance(speedKmh: speed)
            XCTAssertGreaterThanOrEqual(distance, last, "never closer for a faster train")
            XCTAssertGreaterThanOrEqual(distance, config.followMin)
            XCTAssertLessThanOrEqual(distance, config.followMax)
            last = distance
        }
        XCTAssertEqual(CockpitCameraPlanner.followDistance(speedKmh: 0), 1_500 + 0, accuracy: 1)
        XCTAssertEqual(CockpitCameraPlanner.followDistance(speedKmh: 120), 1_500 + 26 * 120, accuracy: 1)
        XCTAssertEqual(CockpitCameraPlanner.followDistance(speedKmh: 900), config.followMax)
        XCTAssertEqual(CockpitCameraPlanner.followDistance(speedKmh: -20), config.followMin, "a negative speed is a standstill")
    }

    func testUnknownSpeedUsesTheCruiseSpeed() {
        let config = CockpitCameraConfig.standard
        XCTAssertEqual(CockpitCameraPlanner.followDistance(speedKmh: nil), CockpitCameraPlanner.followDistance(speedKmh: config.cruiseKmh))
        XCTAssertEqual(CockpitCameraPlanner.followPitch(speedKmh: nil), CockpitCameraPlanner.followPitch(speedKmh: config.cruiseKmh))
        XCTAssertEqual(CockpitCameraPlanner.lookAheadKm(speedKmh: nil), CockpitCameraPlanner.lookAheadKm(speedKmh: config.cruiseKmh))
    }

    func testFollowPitchStaysBetweenSixtyAndSixtyEight() {
        for speed in [0.0, 30, 100, 200, 400] {
            let pitch = CockpitCameraPlanner.followPitch(speedKmh: speed)
            XCTAssertTrue((60...68).contains(pitch), "\(pitch)")
        }
        XCTAssertGreaterThan(CockpitCameraPlanner.followPitch(speedKmh: 0), CockpitCameraPlanner.followPitch(speedKmh: 200))
    }

    func testBirdIsFurtherOutThanFollowButWithinLimits() {
        let config = CockpitCameraConfig.standard
        for speed in [0.0, 60, 120, 250] {
            let bird = CockpitCameraPlanner.birdDistance(speedKmh: speed)
            XCTAssertGreaterThanOrEqual(bird, CockpitCameraPlanner.followDistance(speedKmh: speed))
            XCTAssertTrue((config.birdMin...config.birdMax).contains(bird))
        }
    }

    func testLookAheadIsSecondsOfTravelWithinLimits() {
        XCTAssertEqual(CockpitCameraPlanner.lookAheadKm(speedKmh: 0), 0.15, accuracy: 1e-9)
        XCTAssertEqual(CockpitCameraPlanner.lookAheadKm(speedKmh: 120), 120 / 3600 * 7, accuracy: 1e-9)
        XCTAssertEqual(CockpitCameraPlanner.lookAheadKm(speedKmh: 1000), 1.4, accuracy: 1e-9)
    }

    // MARK: Target

    func testFollowTargetLooksAlongTheRouteFromAheadOfTheTrain() throws {
        let input = eastInput(km: 40, speed: 120)
        let target = CockpitCameraPlanner.target(for: input)
        XCTAssertEqual(target.heading, 90, accuracy: 0.5)
        XCTAssertEqual(target.pitch, CockpitCameraPlanner.followPitch(speedKmh: 120), accuracy: 1e-9)
        XCTAssertEqual(target.distance, CockpitCameraPlanner.followDistance(speedKmh: 120), accuracy: 1e-9)
        let ahead = CockpitCameraPlanner.lookAheadKm(speedKmh: 120)
        XCTAssertEqual(input.train.distanceKm(to: target.center), ahead, accuracy: 0.01)
        XCTAssertGreaterThan(target.center.longitude, input.train.longitude, "the camera looks at a point east of the train")
    }

    func testBirdTargetIsStraightDownNorthUpOnTheTrain() {
        let input = eastInput(mode: .bird)
        let target = CockpitCameraPlanner.target(for: input)
        XCTAssertEqual(target.pitch, 0)
        XCTAssertEqual(target.heading, 0)
        F.assertClose(target.center, input.train)
        XCTAssertEqual(target.distance, CockpitCameraPlanner.birdDistance(speedKmh: 120), accuracy: 1e-9)
    }

    func testReduceMotionIsAFixedTopDownView() {
        let target = CockpitCameraPlanner.target(for: eastInput(mode: .follow, reduceMotion: true))
        XCTAssertEqual(target.pitch, 0)
        XCTAssertEqual(target.heading, 0)
        F.assertClose(target.center, eastInput().train)
    }

    func testTravelHeadingFallsBackStepByStep() throws {
        let train = F.point(15.0)
        // Without a route: from the earlier position when the train moved.
        let moved = CockpitCameraInput(train: train, previous: F.point(14.99))
        XCTAssertEqual(try XCTUnwrap(CockpitCameraPlanner.travelHeading(moved)), 90, accuracy: 0.5)
        // Standing still: towards the next stop.
        let north = CockpitCameraInput(train: train, previous: train, nextStop: GeoPoint(latitude: 48.2, longitude: 15.0))
        XCTAssertEqual(try XCTUnwrap(CockpitCameraPlanner.travelHeading(north)), 0, accuracy: 0.5)
        // Nothing tells: nil, the camera keeps its heading.
        XCTAssertNil(CockpitCameraPlanner.travelHeading(CockpitCameraInput(train: train)))
    }

    func testFollowWithoutRouteUsesTheFallbackHeading() {
        let input = CockpitCameraInput(train: F.point(15.0), speedKmh: 90)
        let target = CockpitCameraPlanner.target(for: input, fallbackHeading: 135)
        XCTAssertEqual(target.heading, 135, accuracy: 1e-9)
        XCTAssertEqual(input.train.distanceKm(to: target.center), CockpitCameraPlanner.lookAheadKm(speedKmh: 90), accuracy: 0.01)
    }

    // MARK: Controller

    func testTheFirstStepLandsOnTheTarget() {
        var controller = CockpitCameraController()
        let input = eastInput()
        XCTAssertEqual(controller.step(input, dt: 0.05), CockpitCameraPlanner.target(for: input))
    }

    func testHeadingDoesNotWhipAtACurve() throws {
        // East for 10 km, then north: the heading target turns by 90 degrees within a short stretch. No step may turn faster than the rate limit.
        let corner = F.point(14.0 + 10 / 74.5)
        let north = CockpitGeo.destination(from: corner, bearing: 0, km: 10)
        let path = try XCTUnwrap(CockpitPath([F.point(14.0), corner, north]))
        var controller = CockpitCameraController()
        var heading = 90.0
        let dt = 0.05
        var maxStep = 0.0
        for index in 0..<400 {   // 20 seconds at 120 km/h: 0.0333 km per second: 0.67 km
            let km = 9.5 + Double(index) * 0.00167
            let input = CockpitCameraInput(train: path.point(atKm: km), trainKm: km, path: path, speedKmh: 120)
            let camera = controller.step(input, dt: dt)
            if index > 0 { maxStep = max(maxStep, abs(CockpitAngle.delta(from: heading, to: camera.heading))) }
            heading = camera.heading
        }
        XCTAssertLessThanOrEqual(maxStep, CockpitCameraConfig.standard.headingMaxRate * dt + 1e-9)
        XCTAssertEqual(heading, 0, accuracy: 6, "after the curve the camera looks north")
    }

    func testHeadingTurnsTheShortWayAcrossNorth() {
        var controller = CockpitCameraController()
        controller.reset(to: CockpitCamera(center: F.point(15.0), distance: 3000, heading: 350, pitch: 65))
        // A target heading of 10: the camera must turn clockwise through 0, not back through 180.
        let path = CockpitPath([F.point(15.0), CockpitGeo.destination(from: F.point(15.0), bearing: 10, km: 50)])!
        let input = CockpitCameraInput(train: F.point(15.0), trainKm: 0, path: path, speedKmh: 100)
        let first = controller.step(input, dt: 0.05)
        XCTAssertTrue(first.heading > 350 || first.heading < 10, "\(first.heading)")
        XCTAssertGreaterThan(CockpitAngle.delta(from: 350, to: first.heading), 0)
    }

    func testControllerConvergesOnASteadyTarget() {
        var controller = CockpitCameraController()
        controller.reset(to: CockpitCamera(center: F.point(14.0), distance: 9000, heading: 200, pitch: 20))
        let input = eastInput()
        let target = CockpitCameraPlanner.target(for: input)
        var camera = target
        for _ in 0..<600 { camera = controller.step(input, dt: 0.05) }
        XCTAssertEqual(camera.heading, target.heading, accuracy: 0.1)
        XCTAssertEqual(camera.pitch, target.pitch, accuracy: 0.1)
        XCTAssertEqual(camera.distance, target.distance, accuracy: 5)
        XCTAssertEqual(camera.center.longitude, target.center.longitude, accuracy: 1e-4)
    }

    func testSwitchingToBirdGlidesInsteadOfJumping() {
        var controller = CockpitCameraController()
        var camera = controller.step(eastInput(mode: .follow), dt: 0.05)
        let followPitch = camera.pitch
        camera = controller.step(eastInput(mode: .bird), dt: 0.05)
        XCTAssertLessThan(camera.pitch, followPitch)
        XCTAssertGreaterThan(camera.pitch, 55, "one step does not swoop to the top-down view")
        for _ in 0..<400 { camera = controller.step(eastInput(mode: .bird), dt: 0.05) }
        XCTAssertEqual(camera.pitch, 0, accuracy: 0.5)
        XCTAssertEqual(camera.heading, 0, accuracy: 0.5)
    }

    func testReduceMotionSnapsAndNeverTilts() {
        var controller = CockpitCameraController()
        _ = controller.step(eastInput(mode: .follow), dt: 0.05)
        let camera = controller.step(eastInput(km: 60, mode: .follow, reduceMotion: true), dt: 0.05)
        XCTAssertEqual(camera.pitch, 0)
        XCTAssertEqual(camera.heading, 0)
        F.assertClose(camera.center, eastInput(km: 60).train)
    }

    func testResetStartsTheGlideWhereTheUserLeftTheMap() {
        var controller = CockpitCameraController()
        let user = CockpitCamera(center: F.point(16.5, lat: 48.3), distance: 40_000, heading: 30, pitch: 10)
        controller.reset(to: user)
        let camera = controller.step(eastInput(), dt: 0.05)
        XCTAssertEqual(camera.distance, 40_000, accuracy: 3_000, "the first step is still near the user's view")
        XCTAssertLessThan(camera.distance, 40_000)
        controller.reset()
        XCTAssertNil(controller.camera)
    }

    func testAZeroOrBadStepLandsOnTheTarget() {
        var controller = CockpitCameraController()
        _ = controller.step(eastInput(), dt: 0.05)
        let input = eastInput(km: 70)
        XCTAssertEqual(controller.step(input, dt: 0), CockpitCameraPlanner.target(for: input))
        XCTAssertEqual(controller.step(input, dt: .nan), CockpitCameraPlanner.target(for: input))
    }

    func testFrameInterval() {
        XCTAssertEqual(CockpitCameraController.frameInterval(lowPower: false), 0.05, accuracy: 1e-9)
        XCTAssertGreaterThan(CockpitCameraController.frameInterval(lowPower: true), CockpitCameraController.frameInterval(lowPower: false))
    }

    func testModeTitles() {
        XCTAssertEqual(CockpitCameraMode.allCases.map(\.title), ["Verfolgen", "Vogelperspektive", "Frei"])
        XCTAssertEqual(CockpitCameraMode.allCases.filter(\.isDriven), [.follow, .bird])
    }
}
