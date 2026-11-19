import XCTest
@testable import KlimaCore

// MARK: radar2-review-radartrail – the review of „Spuren“ (docs/RADAR_TRAILS.md): the trail ends at the marker's own moment, „seit“ names the
// oldest drawn moment, the zoom never turns into NaN, and the trails follow every state of the radar's gate.
final class RadarTrailReviewTests: XCTestCase {
    private typealias F = TrailFixture

    /// A frame-store entry that glides from `previous` (at `previousAt` s) to `latest` (at `seenAt` s).
    private func entry(previous: GeoPoint?, previousAt: Double?, latest: GeoPoint, seenAt: Double) -> RadarFrameStore.Entry {
        RadarFrameStore.Entry(vehicle: F.vehicle("t", at: latest), seenAt: F.at(seenAt), previousCoordinate: previous,
                              previousSeenAt: previousAt.map(F.at), retention: 60)
    }

    // MARK: The marker's moment

    func testAnAnswerBetweenTheTwoTheMarkerGlidesBetweenIsNotDrawnAheadOfIt() {
        // Answers at 0, 20, 40 and 60 s along a line north, 300 m apart. The frame store holds 20 and 60 (the 40-s answer of another tile came
        // late), so the marker glides from 300 m to 900 m; a quarter of the way it stands at 450 m, the moment 30 s. The 40-s sample (600 m) lies
        // ahead of it.
        let samples = [0.0, 20, 40, 60].map { RadarTrailSample(from: F.at($0), coordinate: F.point(north: $0 / 20 * 300)) }
        let glide = entry(previous: F.point(north: 300), previousAt: 20, latest: F.point(north: 900), seenAt: 60)
        let marker = RadarEstimate.position(of: glide, at: F.at(30))
        XCTAssertTrue(marker.isEstimate)
        let moment = RadarTrailGeometry.drawnMoment(of: glide, at: marker.coordinate, isEstimate: marker.isEstimate)
        XCTAssertEqual(moment.timeIntervalSince(F.at(30)), 0, accuracy: 0.01, "the projection inverts the interpolation")

        let lines = RadarTrailGeometry.lines(for: samples, until: moment, drawnPoint: marker.coordinate, spanDegrees: 0.2, heightPoints: 800)
        let north = lines.flatMap(\.points).map(\.coordinate.latitude)
        XCTAssertLessThanOrEqual(north.max() ?? 0, marker.coordinate.latitude + 1e-9, "never a line beyond the marker")
        XCTAssertEqual(lines.last?.points.last?.coordinate, marker.coordinate)

        // The rule before the review („every answer before the newest“) drew the 40-s sample, beyond the marker and back.
        let before = RadarTrailGeometry.lines(for: samples, until: F.at(60).addingTimeInterval(-0.001), drawnPoint: marker.coordinate,
                                              spanDegrees: 0.2, heightPoints: 800)
        XCTAssertGreaterThan(before.flatMap(\.points).map(\.coordinate.latitude).max() ?? 0, marker.coordinate.latitude)
    }

    func testTheMomentIsTheNewestAnswerOnceTheMarkerHoldsAndNeverItWhileItGlides() {
        let glide = entry(previous: F.point(north: 0), previousAt: 0, latest: F.point(north: 400), seenAt: 20)
        XCTAssertEqual(RadarTrailGeometry.drawnMoment(of: glide, at: F.point(north: 400), isEstimate: false), F.at(20))
        // Still at the previous answer (the marker's moment lies before it): that answer's moment.
        XCTAssertEqual(RadarTrailGeometry.drawnMoment(of: glide, at: F.point(north: 0), isEstimate: true), F.at(0))
        // Gliding and almost there: before the newest answer, which is never part of the line yet.
        XCTAssertLessThan(RadarTrailGeometry.drawnMoment(of: glide, at: F.point(north: 400), isEstimate: true), F.at(20))
        // One answer only, or the same place twice: the newest answer.
        let single = entry(previous: nil, previousAt: nil, latest: F.point(north: 400), seenAt: 20)
        XCTAssertEqual(RadarTrailGeometry.drawnMoment(of: single, at: F.point(north: 400), isEstimate: false), F.at(20))
        let stood = entry(previous: F.point(north: 400), previousAt: 0, latest: F.point(north: 400), seenAt: 20)
        XCTAssertEqual(RadarTrailGeometry.drawnMoment(of: stood, at: F.point(north: 400), isEstimate: true), F.at(20))
    }

    // MARK: The window and „seit“

    func testAStandThatBeganBeforeTheLengthKeepsOnlyItsPartInside() {
        // Stood from 0 to 500 s, then moved on at 520 s; drawn until 700 s with a length of 300 s: the window starts at 400 s.
        let stand = RadarTrailSample(from: F.at(0), to: F.at(500), coordinate: F.point())
        let moved = RadarTrailSample(from: F.at(520), coordinate: F.point(north: 400))
        let ahead = RadarTrailSample(from: F.at(720), coordinate: F.point(north: 800))
        let gone = RadarTrailSample(from: F.at(-100), to: F.at(-50), coordinate: F.point(north: -400))
        let window = RadarTrailGeometry.window([gone, stand, moved, ahead], length: 300, until: F.at(700))
        XCTAssertEqual(window.map(\.from), [F.at(400), F.at(520)])
        XCTAssertEqual(window.first?.to, F.at(500))
        let lines = RadarTrailGeometry.lines(for: window, until: F.at(700), drawnPoint: F.point(north: 400), spanDegrees: 0.01, heightPoints: 800)
        XCTAssertEqual(RadarTrailGeometry.oldestMoment(of: lines), F.at(400), "„seit“ is never older than the chosen length")
        XCTAssertTrue(RadarTrailGeometry.window([], length: 300, until: F.at(700)).isEmpty)
    }

    func testSeitIsTheOldestDrawnMomentWhenTheMarkersLagBehindTheClock() {
        let now = F.at(3_600)
        // The radar opened an hour ago; the markers hold an answer of 100 s ago (a 45-s tile and its lag, or Low Power Mode).
        let drawnSince = now.addingTimeInterval(-100 - 600)
        let note = RadarTrailPolicy.note(mode: .mine, trainsOn: true, timeAway: false, choice: .init(tripIDs: ["t"]), drawn: 1,
                                         heldForReturn: true, firstRecordedAt: F.at(0), now: now, length: 600, drawnSince: drawnSince)
        XCTAssertEqual(note, .caption(since: drawnSince), "not „now minus ten minutes“: the lines reach back further")
        let limited = RadarTrailPolicy.note(mode: .all, trainsOn: true, timeAway: false, choice: .init(tripIDs: ["t"], limit: .tooWide),
                                            drawn: 1, heldForReturn: true, firstRecordedAt: F.at(0), now: now, length: 600,
                                            drawnSince: drawnSince)
        XCTAssertEqual(limited, .limited(.tooWide, since: drawnSince))
        XCTAssertEqual(RadarTrailText.caption(since: drawnSince), "Spuren seit \(RealtimePresentation.time(drawnSince)) · berechnete Positionen, kein GPS-Verlauf")
        XCTAssertNil(RadarTrailGeometry.oldestMoment(of: []))
    }

    // MARK: Zoom

    func testTheScaleIsAlwaysFinite() {
        for span in [Double.nan, .infinity, -1, 0] {
            for height in [Double.nan, .infinity, 0, 800] {
                let scale = RadarTrailGeometry.metersPerPoint(spanDegrees: span, heightPoints: height)
                XCTAssertTrue(scale.isFinite && scale > 0, "span \(span), height \(height): \(scale)")
                _ = Int((log2(max(scale, 0.01)) * 2).rounded())   // what the app's zoom bucket does: must not trap
            }
        }
        let samples = (0..<4).map { RadarTrailSample(from: F.at(Double($0) * 20), coordinate: F.point(north: Double($0) * 300)) }
        let lines = RadarTrailGeometry.lines(for: samples, until: F.at(60), drawnPoint: F.point(north: 900), spanDegrees: .nan, heightPoints: .nan)
        XCTAssertEqual(lines.last?.points.last?.coordinate, F.point(north: 900))
    }

    // MARK: Every state of the gate (docs/OEBB_LIVE.md §R11.3, specs radar2 README §5)

    func testTrailsFollowEveryStateOfTheRadarGate() {
        let layerSets: [Set<MapLayer>] = [[], [.trains], [.punctuality], [.trains, .punctuality], [.stations, .trains]]
        let accesses: [RadarFeatureGate.Access] = [.open, .offline, .closed]
        var states = 0
        for layers in layerSets {
            for access in accesses {
                for railOnly in [true, false] {
                    for sceneActive in [true, false] {
                        for cockpitOpen in [true, false] {
                            for timeOpen in [true, false] {
                                for timeAway in [true, false] {
                                    let gate = RadarFeatureGate(layers: MapLayerSelection(layers: layers), access: access, railOnly: railOnly,
                                                                sceneActive: sceneActive, cockpitOpen: cockpitOpen, timeOpen: timeOpen,
                                                                timeAway: timeAway)
                                    states += 1
                                    for mode in RadarTrailSetting.Mode.allCases {
                                        let drawn = RadarTrailPolicy.isDrawn(trainsOn: gate.trainsOn, timeAway: gate.timeAway, mode: mode)
                                        let label = "\(layers) \(access) scene \(sceneActive) cockpit \(cockpitOpen) away \(timeAway) \(mode)"
                                        // Drawn only with markers (train layer and live data open), at „Jetzt“, with the setting on.
                                        if drawn {
                                            XCTAssertTrue(gate.trainsOn && !timeAway && mode != .off, label)
                                            // Drawn while nothing new arrives only where nobody sees the map (cockpit over it, app not active);
                                            // Low Power Mode is outside the gate and keeps the last state on purpose.
                                            if !gate.liveLoopRuns { XCTAssertTrue(cockpitOpen || !sceneActive, label) }
                                        }
                                        if access != .open { XCTAssertFalse(drawn, "offline and closed draw no markers, so no trail: \(label)") }
                                        if timeAway { XCTAssertFalse(drawn, "away from now the Zeitreise draws its own trail: \(label)") }
                                        if mode == .off { XCTAssertFalse(drawn, label) }
                                        // The note never speaks of trails without markers.
                                        let note = RadarTrailPolicy.note(mode: mode, trainsOn: gate.trainsOn, timeAway: gate.timeAway,
                                                                         choice: .init(tripIDs: ["t"]), drawn: drawn ? 1 : 0, heldForReturn: true,
                                                                         firstRecordedAt: F.t0, now: F.at(600), length: 600, drawnSince: F.t0)
                                        if !gate.trainsOn || mode == .off { XCTAssertEqual(note, .none, label) }
                                        if gate.trainsOn && timeAway && mode != .off { XCTAssertEqual(note, .onlyNow, label) }
                                    }
                                    // What the access does to the samples: only a closed access clears them.
                                    XCTAssertEqual(RadarTrailPolicy.effect(of: access), access == .closed ? .clear : .keep)
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(states, 5 * 3 * 2 * 2 * 2 * 2 * 2)
    }
}
