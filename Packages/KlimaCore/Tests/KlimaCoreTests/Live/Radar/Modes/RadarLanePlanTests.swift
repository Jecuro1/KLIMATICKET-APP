import XCTest
@testable import KlimaCore

// MARK: radarmodes – what each lane asks for, when the city lane runs, and the demo-only scheduler config (docs/RADAR_MODES.md §3, §10).
final class RadarLanePlanTests: XCTestCase {
    func testTheDefaultAsksTheWideLaneFor4157AndTheCityLaneForNothing() {
        let selection = RadarModeSelection.default
        XCTAssertEqual(RadarLanePlan.products(for: .wide, selection: selection, heatOn: false).rawValue, 4157)
        XCTAssertEqual(RadarLanePlan.products(for: .city, selection: selection, heatOn: false).rawValue, 0)
        XCTAssertEqual(RadarLanePlan.requestMask(selection: selection, heatOn: false).rawValue, 4157)
    }

    func testCityModesGoToTheCityLane() {
        let selection = RadarModeSelection([.rail, .bus, .tram, .subway])
        XCTAssertEqual(RadarLanePlan.products(for: .wide, selection: selection, heatOn: false).rawValue, 4125)
        XCTAssertEqual(RadarLanePlan.products(for: .city, selection: selection, heatOn: false).rawValue, 64 | 512 | 256)
        XCTAssertEqual(RadarLanePlan.lane(of: .suburban), .wide)
        XCTAssertEqual(RadarLanePlan.lane(of: .subway), .city)
    }

    func testThePunctualityLayerAsksForEveryTrainWhateverTheChips() {
        // Only Bus on: the layer's two Austria tiles still ask for rail only, never for buses.
        let busOnly = RadarModeSelection([.bus])
        XCTAssertEqual(RadarLanePlan.products(for: .wide, selection: busOnly, heatOn: true), .rail)
        XCTAssertEqual(RadarLanePlan.products(for: .wide, selection: busOnly, heatOn: false).rawValue, 0, "an empty mask: no wide tile")
        XCTAssertEqual(RadarLanePlan.products(for: .city, selection: busOnly, heatOn: true), .bus, "buses only in the city lane")
        // S-Bahn chip off: the layer still holds the S-Bahnen.
        let noSBahn = RadarModeSelection([.rail])
        XCTAssertEqual(RadarLanePlan.products(for: .wide, selection: noSBahn, heatOn: true).rawValue, 4157)
        XCTAssertEqual(RadarLanePlan.requestMask(selection: noSBahn, heatOn: true).rawValue, 4157)
        XCTAssertEqual(RadarLanePlan.requestMask(selection: noSBahn, heatOn: false).rawValue, 4125)
    }

    func testTheCityLaneRunsOnlyWhenZoomedIn() {
        XCTAssertTrue(RadarLanePlan.cityInZoom(latitudeSpan: 0.12))
        XCTAssertTrue(RadarLanePlan.cityInZoom(latitudeSpan: 0.6))
        XCTAssertFalse(RadarLanePlan.cityInZoom(latitudeSpan: 0.61))
        XCTAssertFalse(RadarLanePlan.cityInZoom(latitudeSpan: 4.2))
        XCTAssertFalse(RadarLanePlan.cityInZoom(latitudeSpan: 0))
        XCTAssertFalse(RadarLanePlan.cityInZoom(latitudeSpan: .nan))
    }

    func testTheLimitInKilometresFollowsTheLimit() {
        XCTAssertEqual(RadarLanePlan.cityLimitKilometres(), Int((RadarLanePlan.citySpanLimit * 111.2).rounded()))
        XCTAssertEqual(RadarLanePlan.cityLimitKilometres(0.6), 67)
        XCTAssertEqual(RadarLanePlan.cityLimitKilometres(0.3), 33)
        XCTAssertEqual(RadarLanePlan.cityLimitKilometres(0.8), 89)
    }

    func testAutomaticCityRefresh() {
        XCTAssertEqual(RadarLanePlan.automaticCityInterval(metered: false), 20)
        XCTAssertEqual(RadarLanePlan.automaticCityInterval(metered: true), 60)
    }

    func testTheFastConfigExistsOnlyForTheSyntheticCityDemoInASandbox() {
        XCTAssertEqual(RadarSchedulerConfig.forRadar(syntheticCityDemo: false, sandboxed: false), .standard)
        XCTAssertEqual(RadarSchedulerConfig.forRadar(syntheticCityDemo: false, sandboxed: true), .standard)
        XCTAssertEqual(RadarSchedulerConfig.forRadar(syntheticCityDemo: true, sandboxed: false), .standard, "never with a real service")
        let demo = RadarSchedulerConfig.forRadar(syntheticCityDemo: true, sandboxed: true)
        XCTAssertNotEqual(demo, .standard)
        XCTAssertEqual(demo.perMinute, 600)
        XCTAssertEqual(demo.settleDelay, 0)
        XCTAssertEqual(RadarSchedulerConfig.standard.perMinute, 24)
        XCTAssertEqual(RadarSchedulerConfig.standard.burst, 4)
    }
}
