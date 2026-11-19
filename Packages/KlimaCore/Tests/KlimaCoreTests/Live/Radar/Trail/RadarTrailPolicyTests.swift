import XCTest
@testable import KlimaCore

/// „Spuren“: which trails are drawn, when, and what the one stored setting holds (docs/RADAR_TRAILS.md §4, §7).
final class RadarTrailPolicyTests: XCTestCase {
    private let singles = (0..<40).map { "t\($0)" }

    func testOffDrawsNothing() {
        let choice = RadarTrailPolicy.trips(mode: .off, selected: "t1", followed: "t2", remembered: ["t3"], singles: singles, span: 0.1)
        XCTAssertEqual(choice, RadarTrailPolicy.Choice())
    }

    func testMineIsSelectedFollowedAndRememberedAmongTheSingleMarkers() {
        let choice = RadarTrailPolicy.trips(mode: .mine, selected: "t5", followed: "t2", remembered: ["t9", "gone", "t5"], singles: singles,
                                            span: 2)
        XCTAssertEqual(choice.tripIDs, ["t5", "t2", "t9"], "selected first; a trip without a single marker and duplicates are left out")
        XCTAssertFalse(choice.tooMany)
    }

    func testMineIsCappedAtTwelve() {
        let remembered = (10..<30).map { "t\($0)" }
        let choice = RadarTrailPolicy.trips(mode: .mine, selected: "t1", followed: nil, remembered: remembered, singles: singles, span: 0.1)
        XCTAssertEqual(choice.tripIDs.count, RadarTrailPolicy.mineLimit)
        XCTAssertEqual(choice.tripIDs.first, "t1")
    }

    func testAllAtTheLimits() {
        let sixty = (0..<60).map { "t\($0)" }
        let all = RadarTrailPolicy.trips(mode: .all, selected: "t7", followed: nil, remembered: [], singles: sixty, span: 0.5)
        XCTAssertEqual(all.tripIDs.count, 60)
        XCTAssertEqual(all.tripIDs.first, "t7", "the selected trail is drawn first")
        XCTAssertFalse(all.tooMany)

        let wide = RadarTrailPolicy.trips(mode: .all, selected: "t7", followed: nil, remembered: [], singles: sixty, span: 0.51)
        XCTAssertEqual(wide, RadarTrailPolicy.Choice(tripIDs: ["t7"], tooMany: true))

        let full = RadarTrailPolicy.trips(mode: .all, selected: nil, followed: "t3", remembered: [], singles: sixty + ["t60"], span: 0.2)
        XCTAssertEqual(full, RadarTrailPolicy.Choice(tripIDs: ["t3"], tooMany: true))
    }

    func testTheSettingRoundTripsAndToleratesUnknownValues() {
        for mode in RadarTrailSetting.Mode.allCases {
            for minutes in RadarTrailSetting.lengths {
                let setting = RadarTrailSetting(mode: mode, minutes: minutes)
                XCTAssertEqual(RadarTrailSetting(storage: setting.storageValue), setting)
            }
        }
        XCTAssertEqual(RadarTrailSetting(storage: ""), .standard)
        XCTAssertEqual(RadarTrailSetting(storage: "{\"version\":1,\"mode\":\"rainbow\",\"minutes\":7}"), RadarTrailSetting(mode: .mine, minutes: 10))
        XCTAssertEqual(RadarTrailSetting(storage: "{\"mode\":\"all\"}"), RadarTrailSetting(mode: .all, minutes: 10))
        XCTAssertEqual(RadarTrailSetting.standard, RadarTrailSetting(mode: .mine, minutes: 10))
        XCTAssertEqual(RadarTrailSetting(mode: .all, minutes: 3).minutes, 10)
        XCTAssertEqual(RadarTrailSetting.storageKey, "radar.trail.v1")
        XCTAssertEqual(RadarTrailSetting(mode: .mine, minutes: 20).window, 22 * 60)
    }

    func testTrailsAreDrawnOnlyWithTrainsAtNowAndTheSettingOn() {
        XCTAssertTrue(RadarTrailPolicy.isDrawn(trainsOn: true, timeAway: false, mode: .mine))
        XCTAssertFalse(RadarTrailPolicy.isDrawn(trainsOn: true, timeAway: true, mode: .mine), "the Zeitreise draws its own computed trail")
        XCTAssertFalse(RadarTrailPolicy.isDrawn(trainsOn: true, timeAway: false, mode: .off))
        // Offline: the gate's trainsOn is false (no markers at all), so no trail either.
        let offline = RadarFeatureGate(access: .offline)
        XCTAssertFalse(RadarTrailPolicy.isDrawn(trainsOn: offline.trainsOn, timeAway: false, mode: .all))
        XCTAssertTrue(RadarTrailPolicy.isDrawn(trainsOn: RadarFeatureGate(access: .open).trainsOn, timeAway: false, mode: .all))
    }

    func testOfflineKeepsTheSamplesAndAClosedAccessClearsThem() {
        XCTAssertEqual(RadarTrailPolicy.effect(of: .offline), .keep)
        XCTAssertEqual(RadarTrailPolicy.effect(of: .open), .keep)
        XCTAssertEqual(RadarTrailPolicy.effect(of: .closed), .clear)
    }
}
