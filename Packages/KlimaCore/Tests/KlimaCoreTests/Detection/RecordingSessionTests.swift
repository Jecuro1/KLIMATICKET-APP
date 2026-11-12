import XCTest
@testable import KlimaCore

final class RecordingSessionTests: XCTestCase {
    typealias F = DetectFixtures

    private func session(at start: Date = F.nov12("08:00")) -> RecordingSession {
        RecordingSession(startedAt: start, lookup: F.lookup)
    }

    private func pathKm(_ waypoints: [Station]) -> Double {
        zip(waypoints, waypoints.dropFirst()).reduce(0) { $0 + $1.0.location.distanceKm(to: $1.1.location) }
    }

    /// A recorded regional train with a stop at each station on the way.
    func testTrainRecordingGivesLiveNumbersAndAProposal() throws {
        let start = F.nov12("08:00")
        let stops: [Station] = [F.innsbruck, F.telfs, F.imst, F.landeck]
        let fixes = ScriptedTrack.ride(waypoints: stops.map(\.location), start: start, cruiseKmh: 90, interval: 5, halts: [1: 60, 2: 60, 3: 40])
        var s = session(at: start)
        var midSnapshot: RecordingSnapshot?
        for (i, fix) in fixes.enumerated() {
            s.ingest(fix)
            if i == fixes.count / 2 { midSnapshot = s.snapshot(now: fix.time) }
        }
        let last = fixes.last!.time
        let end = s.snapshot(now: last)

        XCTAssertEqual(end.distanceKm, pathKm(stops), accuracy: pathKm(stops) * 0.03, "GPS jitter must not inflate the distance by more than 3 %")
        XCTAssertEqual(end.elapsed, last.timeIntervalSince(start), accuracy: 0.1)
        XCTAssertEqual(end.maxSpeedKmh, 90, accuracy: 2)
        XCTAssertEqual(end.currentStation?.station.id, F.landeck.id)
        XCTAssertEqual(end.lastStation?.id, F.landeck.id)
        XCTAssertEqual(end.speedKmh, 0, accuracy: 3, "standing at the destination")
        XCTAssertNotNil(midSnapshot)
        XCTAssertGreaterThan(midSnapshot?.speedKmh ?? 0, 60)
        XCTAssertGreaterThan(end.track.count, 20)
        XCTAssertEqual(end.secondsSinceFix, 0)

        let proposal = try XCTUnwrap(s.proposal(endedAt: last.addingTimeInterval(20)))
        XCTAssertEqual(proposal.from?.station.id, F.innsbruck.id)
        XCTAssertEqual(proposal.to?.station.id, F.landeck.id)
        XCTAssertEqual(proposal.halts.map(\.id), [F.telfs.id, F.imst.id])
        XCTAssertEqual(proposal.mode, .train)
        XCTAssertTrue(proposal.isComplete)
        XCTAssertEqual(proposal.straightKm, F.km(F.innsbruck, F.landeck), accuracy: 0.01)
        XCTAssertEqual(proposal.start, start)
        XCTAssertFalse(proposal.sketch.isStraight)
    }

    func testSpeedIsReportedFromTheProviderOrDerivedFromTheSteps() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        // No provider speed: 100 m every 10 s = 36 km/h.
        var point = F.innsbruck.location
        for i in 0..<20 {
            s.ingest(CoarsePoint(time: start.addingTimeInterval(Double(i) * 10), at: point, accuracyMeters: 8, source: .recording))
            point = DetectionGeo.offset(point, meters: 100, bearingDegrees: 270)
        }
        XCTAssertEqual(s.snapshot(now: start.addingTimeInterval(190)).speedKmh, 36, accuracy: 3)
    }

    func testInaccurateFixesAndGPSJumpsAreIgnored() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        s.ingest(CoarsePoint(time: start, at: F.innsbruck.location, accuracyMeters: 8, source: .recording))
        s.ingest(CoarsePoint(time: start.addingTimeInterval(5), at: DetectionGeo.offset(F.innsbruck.location, meters: 5000, bearingDegrees: 90),
                             accuracyMeters: 8, source: .recording))   // 1 km/s: a jump
        s.ingest(CoarsePoint(time: start.addingTimeInterval(10), at: DetectionGeo.offset(F.innsbruck.location, meters: 100, bearingDegrees: 90),
                             accuracyMeters: 400, source: .recording))   // too inaccurate
        s.ingest(CoarsePoint(time: start.addingTimeInterval(-60), at: F.hall.location, accuracyMeters: 8, source: .recording))   // before the start
        let snap = s.snapshot(now: start.addingTimeInterval(11))
        XCTAssertEqual(snap.fixCount, 1)
        XCTAssertEqual(snap.distanceKm, 0, accuracy: 0.001)
    }

    func testAStandingPhoneDoesNotAddDistance() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        for fix in ScriptedTrack.stay(at: F.innsbruck.location, from: start, to: start.addingTimeInterval(1200), interval: 5, accuracy: 10, jitterMeters: 4, source: .recording) {
            s.ingest(fix)
        }
        XCTAssertLessThan(s.snapshot(now: start.addingTimeInterval(1200)).distanceKm, 0.05)
        XCTAssertNil(s.proposal(endedAt: start.addingTimeInterval(1200)), "an accidental start is no ride")
    }

    func testLostGPSShowsInTheSnapshot() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        XCTAssertNil(s.snapshot(now: start).secondsSinceFix)
        s.ingest(CoarsePoint(time: start.addingTimeInterval(10), at: F.innsbruck.location, accuracyMeters: 8, source: .recording))
        XCTAssertEqual(s.snapshot(now: start.addingTimeInterval(100)).secondsSinceFix ?? 0, 90, accuracy: 0.1)
    }

    /// Started in a field, ended in a field: the proposal exists, with no stations – the person picks them.
    func testProposalWithoutStationsAsksForThem() throws {
        let start = F.nov12("08:00")
        let a = DetectionGeo.offset(F.hall.location, meters: 6000, bearingDegrees: 0)
        let b = DetectionGeo.offset(a, meters: 9000, bearingDegrees: 90)
        let fixes = ScriptedTrack.ride(waypoints: [a, b], start: start, cruiseKmh: 60, interval: 10)
        var s = session(at: start)
        fixes.forEach { s.ingest($0) }
        let proposal = try XCTUnwrap(s.proposal(endedAt: fixes.last!.time))
        XCTAssertNil(proposal.from)
        XCTAssertNil(proposal.to)
        XCTAssertFalse(proposal.isComplete)
        XCTAssertEqual(proposal.straightKm, 9, accuracy: 0.2)
    }

    func testTramRecordingInTheCityIsAProposalEvenBelowFiveKilometres() throws {
        let start = F.nov12("17:00")
        let fixes = ScriptedTrack.ride(waypoints: [F.schottentor.location, F.suedtirolerPlatz.location], start: start, cruiseKmh: 20, interval: 5)
        var s = session(at: start)
        fixes.forEach { s.ingest($0) }
        let proposal = try XCTUnwrap(s.proposal(endedAt: fixes.last!.time))
        XCTAssertEqual(proposal.from?.station.id, F.schottentor.id)
        XCTAssertEqual(proposal.to?.station.id, F.suedtirolerPlatz.id)
        XCTAssertEqual(proposal.mode, .tram)
    }

    func testTheLiveMapLineIsThinnedButKeepsItsEnds() {
        let start = F.nov12("08:00")
        var config = RecordingConfig()
        config.maxTrackPoints = 100
        var s = RecordingSession(startedAt: start, lookup: F.lookup, config: config)
        let fixes = ScriptedTrack.ride(waypoints: [F.innsbruck.location, F.landeck.location], start: start, cruiseKmh: 100, interval: 2)
        fixes.forEach { s.ingest($0) }
        let track = s.snapshot(now: fixes.last!.time).track
        XCTAssertLessThanOrEqual(track.count, 100)
        XCTAssertGreaterThan(track.count, 40)
        XCTAssertLessThan(DetectionGeo.meters(track.first!, F.innsbruck.location), 60)
        XCTAssertLessThan(DetectionGeo.meters(track.last!, F.landeck.location), 400)
    }

    // MARK: A forgotten recording ends by itself (battery, blue pill, privacy)

    /// A phone left on a desk: fixes keep coming from the same place; after half an hour the recording stops itself.
    func testARecordingLeftOnADeskEndsAfterHalfAnHour() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        for fix in ScriptedTrack.stay(at: F.innsbruck.location, from: start, to: start.addingTimeInterval(50 * 60), interval: 5, accuracy: 10, jitterMeters: 4, source: .recording) {
            s.ingest(fix)
        }
        XCTAssertNil(s.autoStop(now: start.addingTimeInterval(29 * 60)), "29 minutes of waiting is a delayed train, not a forgotten phone")
        guard case .idle(let since)? = s.autoStop(now: start.addingTimeInterval(31 * 60)) else { return XCTFail("30 minutes without moving must end it") }
        XCTAssertEqual(since.timeIntervalSince(start), 0, accuracy: 6, "idle since the first fix")
    }

    /// A ride, then the phone stays in the pocket at the destination: the proposal ends where the ride ended, not half an hour later.
    func testTheProposalOfAnIdleStopEndsWithTheRide() throws {
        let start = F.nov12("08:00")
        let ride = ScriptedTrack.ride(waypoints: [F.innsbruck, F.landeck].map(\.location), start: start, cruiseKmh: 100, interval: 5)
        var s = session(at: start)
        ride.forEach { s.ingest($0) }
        let arrival = ride.last!.time
        for fix in ScriptedTrack.stay(at: F.landeck.location, from: arrival.addingTimeInterval(5), to: arrival.addingTimeInterval(45 * 60), interval: 5, accuracy: 10,
                                      jitterMeters: 4, source: .recording) {
            s.ingest(fix)
        }
        XCTAssertNil(s.autoStop(now: arrival.addingTimeInterval(20 * 60)), "a 20 minute halt is still part of a ride")
        guard case .idle(let since)? = s.autoStop(now: arrival.addingTimeInterval(45 * 60)) else { return XCTFail("45 minutes of standing still must end it") }
        XCTAssertLessThan(abs(since.timeIntervalSince(arrival)), 60, "the moment it last moved is the arrival")

        let proposal = try XCTUnwrap(s.proposal(endedAt: since))
        XCTAssertEqual(proposal.from?.station.id, F.innsbruck.id)
        XCTAssertEqual(proposal.to?.station.id, F.landeck.id)
        XCTAssertLessThan(abs(proposal.end.timeIntervalSince(arrival)), 60, "the proposal ends with the ride, not with the waiting")
        XCTAssertEqual(proposal.distanceKm, F.km(F.innsbruck, F.landeck), accuracy: F.km(F.innsbruck, F.landeck) * 0.05)
    }

    /// Moving keeps the recording alive however long the fixes go on – until the 12 hour limit.
    func testARideIsNeverIdleButAnythingBeyondTwelveHoursIsForgotten() {
        let start = F.nov12("08:00")
        var s = session(at: start)
        let ride = ScriptedTrack.ride(waypoints: [F.innsbruck, F.landeck].map(\.location), start: start, cruiseKmh: 60, interval: 10)
        for fix in ride {
            s.ingest(fix)
            XCTAssertNil(s.autoStop(now: fix.time), "a moving train is not idle")
        }
        XCTAssertNotEqual(s.autoStop(now: start.addingTimeInterval(12 * 3600 - 1)), .tooLong)
        XCTAssertEqual(s.autoStop(now: start.addingTimeInterval(12 * 3600)), .tooLong)
    }

    /// No fix at all (GPS never found, location off): half an hour later the recording ends, too.
    func testARecordingWithoutAnyFixEndsToo() {
        let start = F.nov12("08:00")
        let s = session(at: start)
        XCTAssertNil(s.autoStop(now: start.addingTimeInterval(10 * 60)))
        XCTAssertEqual(s.autoStop(now: start.addingTimeInterval(30 * 60)), .idle(since: start))
        XCTAssertNil(s.proposal(endedAt: start.addingTimeInterval(30 * 60)), "nothing was recorded, nothing is proposed")
    }

    func testTheAutoStopTextsNameTheReason() {
        XCTAssertTrue(RecordingAutoStop.idle(since: Date()).text().contains("30 Minuten nicht bewegt"))
        XCTAssertTrue(RecordingAutoStop.tooLong.text().contains("12 Stunden"))
        XCTAssertTrue(RecordingAutoStop.locationOff.text().contains("Standortzugriff"))
    }

    /// The recorder reads its fixes from any provider: here the scripted one, as the demo scenes and CI do.
    func testRecordingFromAScriptedProvider() async throws {
        let start = F.nov12("08:00")
        let provider = ScriptedTrackProvider(script: ScriptedTrack.ride(waypoints: [F.innsbruck, F.landeck].map(\.location), start: start,
                                                                           cruiseKmh: 80, interval: 10))
        var s = session(at: start)
        var last = start
        for await fix in provider.positions() {
            s.ingest(fix)
            last = fix.time
        }
        let proposal = try XCTUnwrap(s.proposal(endedAt: last))
        XCTAssertEqual(proposal.from?.station.id, F.innsbruck.id)
        XCTAssertEqual(proposal.to?.station.id, F.landeck.id)
    }
}
