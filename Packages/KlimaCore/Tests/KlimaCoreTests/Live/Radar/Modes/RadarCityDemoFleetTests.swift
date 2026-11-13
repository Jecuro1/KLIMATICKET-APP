import XCTest
@testable import KlimaCore

// MARK: radarmodes – the synthetic city fleets of -KBDemo and the CI scenes behave like the real service, and the crowded scene really is crowded
// and cut off when it runs through the scheduler (docs/RADAR_MODES.md §10).
final class RadarCityDemoFleetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)
    /// The crowded scene: Wien at about 0.12° × 0.12° around Stephansplatz (the map makes it a little taller).
    private let wien = RadarBox(north: 48.2805, west: 16.3125, south: 48.1365, east: 16.4325)

    func testWienHasTheFleetOfTheSpec() {
        let all = RadarCityDemoFleet.vehicles(now: t0)
        let wienBox = RadarBox(north: 48.35, west: 16.15, south: 48.05, east: 16.60)
        let inWien = all.filter { wienBox.contains($0.coordinate) }
        func count(_ cls: Int) -> Int { inWien.filter { $0.line?.productClass == cls }.count }
        XCTAssertEqual(count(64), 600)
        XCTAssertEqual(count(512), 297)
        XCTAssertEqual(count(256), 40)
        XCTAssertGreaterThan(count(32), 10, "S-Bahnen through Wien")
        XCTAssertTrue(all.allSatisfy { $0.stopovers.count == 4 }, "four stops per run, as the real answer")
        XCTAssertEqual(Set(all.map(\.tripID)).count, all.count, "unique trip ids")
        XCTAssertGreaterThan(all.filter { RadarDelay.state(of: $0, now: t0) == .late }.count, 50)
        XCTAssertGreaterThan(all.filter { RadarDelay.state(of: $0, now: t0) == .unknown }.count, 20)
        XCTAssertEqual(Set(all.compactMap { $0.line?.operatorName }), ["Stadtverkehr", "Regionalbus", "ÖBB"])
    }

    func testTheFleetIsDeterministicAndMovesWithTheClock() {
        let a = RadarCityDemoFleet.vehicles(now: t0)
        let b = RadarCityDemoFleet.vehicles(now: t0)
        XCTAssertEqual(a, b)
        let later = RadarCityDemoFleet.vehicles(now: t0.addingTimeInterval(20))
        let moved = zip(a, later).filter { $0.coordinate != $1.coordinate }.count
        XCTAssertGreaterThan(moved, a.count / 2)
    }

    func testTheServiceAnswersOnlyWhatWasAskedInsideTheBoxAndCapsAtMaxVehicles() {
        let busOnly = RadarCityDemoFleet.answer(RadarQuery(box: wien, when: t0, products: .bus))
        XCTAssertFalse(busOnly.vehicles.isEmpty)
        XCTAssertTrue(busOnly.vehicles.allSatisfy { $0.line?.productClass == 64 && wien.contains($0.coordinate) })
        let capped = RadarCityDemoFleet.answer(RadarQuery(box: wien, when: t0, products: [.bus, .tram], maxVehicles: 1000), crowded: true)
        XCTAssertEqual(capped.vehicles.count, 1000)
        XCTAssertTrue(RadarTiling.isTruncated(count: capped.answeredCount))
        let none = RadarCityDemoFleet.answer(RadarQuery(box: wien, when: t0, products: .ship))
        XCTAssertTrue(none.vehicles.isEmpty)
    }

    func testTheCrowdedSceneIsCrowdedAndCutOffInTheScheduler() {
        var scheduler = RadarScheduler(config: .syntheticCityDemo)
        scheduler.setViewport(wien, latitudeSpan: 0.144, now: t0)
        scheduler.setCityViewport(wien, latitudeSpan: 0.144, now: t0)
        let city: ProductMask = [.bus, .tram, .subway]
        var elapsed = 0.0
        while elapsed < 30 {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let tile) = scheduler.next(now: now) {
                let products: ProductMask = tile.lane == .city ? city : .rail
                let answer = RadarCityDemoFleet.answer(RadarQuery(box: RadarTileGrid.box(of: tile), when: now, products: products), crowded: true)
                scheduler.recordAnswer(tile, count: answer.answeredCount, at: now)
            }
            elapsed += 0.1
        }
        let status = scheduler.status(now: t0.addingTimeInterval(30))
        XCTAssertGreaterThanOrEqual(status.city.cappedTiles, 1, "the Stephansplatz knot is cut off at level 8")
        XCTAssertGreaterThanOrEqual(status.city.crowdedTiles, 1, "the other knots would need more than 16 tiles")
        XCTAssertEqual(status.city.visibleTiles, 16)
        XCTAssertEqual(status.city.pendingTiles, 0, "fully loaded within the CI capture delay (11 s) with the demo budget")
        XCTAssertNotNil(RadarDataEstimate.noteMegabytes(RadarDataEstimate.megabytesPerMinute(cityTileCounts: status.city.vehicleCounts,
                                                                                               period: status.city.period)))
    }

    func testTheCitySceneIsNotCutOff() {
        var scheduler = RadarScheduler(config: .syntheticCityDemo)
        let close = RadarBox(north: 48.2020, west: 16.3600, south: 48.1820, east: 16.3900)   // the scene: 0.02° around 48.192, 16.375
        scheduler.setViewport(close, latitudeSpan: 0.02, now: t0)
        scheduler.setCityViewport(close, latitudeSpan: 0.02, now: t0)
        var elapsed = 0.0
        var seen: [RadarVehicle] = []
        while elapsed < 11 {
            let now = t0.addingTimeInterval(elapsed)
            if case .request(let tile) = scheduler.next(now: now) {
                let products: ProductMask = tile.lane == .city ? [.bus, .tram, .subway] : .rail
                let answer = RadarCityDemoFleet.answer(RadarQuery(box: RadarTileGrid.box(of: tile), when: now, products: products))
                scheduler.recordAnswer(tile, count: answer.answeredCount, at: now)
                seen += answer.vehicles
            }
            elapsed += 0.1
        }
        let status = scheduler.status(now: t0.addingTimeInterval(11))
        XCTAssertEqual(status.city.cappedTiles, 0)
        XCTAssertEqual(status.city.crowdedTiles, 0)
        XCTAssertEqual(status.city.pendingTiles, 0)
        // At any time of day: all five modes in the close Wien view of the scene.
        for minute in stride(from: 0.0, to: 120, by: 7) {
            let vehicles = RadarCityDemoFleet.vehicles(now: t0.addingTimeInterval(minute * 60)).filter { close.contains($0.coordinate) }
            XCTAssertEqual(Set(vehicles.compactMap { RadarMode.of($0) }), Set(RadarMode.allCases), "minute \(minute)")
        }
        XCTAssertFalse(seen.isEmpty)
    }
}
