import XCTest
@testable import KlimaCore

/// „Spuren“: the recorder keeps what the answers said, in time order, compacted, within the window and under hard caps (docs/RADAR_TRAILS.md §3).
final class RadarTrailRecorderTests: XCTestCase {
    private typealias F = TrailFixture

    private func record(_ recorder: inout RadarTrailRecorder, _ id: String, north: Double, at seconds: Double, delay: Int? = 0,
                        productClass: Int = 1, cancelled: Bool = false) {
        recorder.record([F.vehicle(id, at: F.point(north: north), delayMinutes: delay, productClass: productClass, cancelled: cancelled,
                                   now: F.at(seconds))], at: F.at(seconds))
    }

    private func storedCount(_ recorder: RadarTrailRecorder) -> Int {
        recorder.tracks.values.reduce(0) { $0 + $1.samples.count }
    }

    func testAnswersAreKeptInTimeOrderAtTheirRequestTime() {
        var recorder = RadarTrailRecorder()
        for (i, north) in [0.0, 300, 600].enumerated() { record(&recorder, "a", north: north, at: Double(i) * 20) }
        let samples = recorder.samples(for: "a")
        XCTAssertEqual(samples.map(\.from), [F.at(0), F.at(20), F.at(40)])
        XCTAssertEqual(samples[1].coordinate.latitude, F.point(north: 300).latitude, accuracy: 1e-5)
        XCTAssertEqual(recorder.sampleCount, 3)
        XCTAssertEqual(recorder.tripCount, 1)
    }

    func testAnOlderAnswerIsInsertedBetweenAndNeverReplacesANewerOne() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0)
        record(&recorder, "a", north: 1_000, at: 40)
        record(&recorder, "a", north: 500, at: 20)   // a slow answer arrives last
        let samples = recorder.samples(for: "a")
        XCTAssertEqual(samples.map(\.from), [F.at(0), F.at(20), F.at(40)])
        XCTAssertEqual(samples[2].coordinate.latitude, F.point(north: 1_000).latitude, accuracy: 1e-5, "the newest answer stays")
        // The same moment twice (two tiles): the first stays.
        record(&recorder, "a", north: 9_000, at: 40)
        XCTAssertEqual(recorder.samples(for: "a")[2].coordinate.latitude, F.point(north: 1_000).latitude, accuracy: 1e-5)
        XCTAssertEqual(recorder.sampleCount, 3)
    }

    func testAStandingVehicleCostsOneSample() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0)
        record(&recorder, "a", north: 19, at: 20)   // within 20 m, same delay: the stand grows
        XCTAssertEqual(recorder.samples(for: "a").count, 1)
        XCTAssertEqual(recorder.samples(for: "a")[0].to, F.at(20))
        record(&recorder, "a", north: 40, at: 40)   // 21 m from the stand's point: a new sample
        XCTAssertEqual(recorder.samples(for: "a").count, 2)
    }

    func testCompactionAtTheTwentyMetreEdge() {
        var near = RadarTrailRecorder()
        record(&near, "a", north: 0, at: 0)
        record(&near, "a", north: 19, at: 20)
        XCTAssertEqual(near.samples(for: "a").count, 1, "19 m is a stand")
        var far = RadarTrailRecorder()
        record(&far, "a", north: 0, at: 0)
        record(&far, "a", north: 21, at: 20)
        XCTAssertEqual(far.samples(for: "a").count, 2, "21 m is a move")
    }

    func testADelayChangeIsNeverCompacted() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0, delay: 2)
        record(&recorder, "a", north: 0, at: 20, delay: 3)
        XCTAssertEqual(recorder.samples(for: "a").map(\.delaySeconds), [120, 180])
        record(&recorder, "a", north: 0, at: 40, delay: 3, cancelled: true)
        XCTAssertEqual(recorder.samples(for: "a").count, 3, "a cancellation is a change too")
    }

    func testAnOlderAnswerInsideAStandSplitsIt() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0)
        record(&recorder, "a", north: 5, at: 40)   // stand 0…40
        record(&recorder, "a", north: 800, at: 20)   // an older answer puts it elsewhere at 20
        let samples = recorder.samples(for: "a")
        XCTAssertEqual(samples.map(\.from), [F.at(0), F.at(20), F.at(40)])
        XCTAssertEqual(samples.map(\.to), [F.at(0), F.at(20), F.at(40)])
        XCTAssertEqual(recorder.sampleCount, storedCount(recorder))
    }

    func testTheWindowIsTheLengthPlusTheMargin() {
        var recorder = RadarTrailRecorder(window: RadarTrailSetting(mode: .mine, minutes: 10).window)
        XCTAssertEqual(recorder.window, 12 * 60)
        record(&recorder, "a", north: 0, at: 0)
        record(&recorder, "b", north: 0, at: 12 * 60)   // exactly 10 minutes plus 2: kept
        XCTAssertEqual(recorder.samples(for: "a").count, 1)
        record(&recorder, "b", north: 100, at: 12 * 60 + 60)   // 10:00 + 2 min + 1 min: gone
        XCTAssertTrue(recorder.samples(for: "a").isEmpty)
        XCTAssertEqual(recorder.tripCount, 1)
        XCTAssertEqual(recorder.sampleCount, storedCount(recorder))
    }

    func testPruneAtTheExactEdgeOfTenMinutes() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0)
        recorder.prune(now: F.at(600), window: 600)
        XCTAssertEqual(recorder.samples(for: "a").count, 1, "10:00 old is still inside a 10-minute window")
        recorder.prune(now: F.at(601), window: 600)
        XCTAssertTrue(recorder.samples(for: "a").isEmpty, "10:01 old is out")
    }

    func testAStandThatBeganBeforeTheWindowKeepsOnlyItsPartInside() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 0)
        record(&recorder, "a", north: 0, at: 500)
        recorder.prune(now: F.at(700), window: 600)
        let samples = recorder.samples(for: "a")
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].from, F.at(100))
        XCTAssertEqual(samples[0].to, F.at(500))
    }

    func testRemovingAProductClassDropsItsTrips() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "train", north: 0, at: 0, productClass: 1)
        record(&recorder, "bus", north: 0, at: 0, productClass: 64)
        record(&recorder, "tram", north: 0, at: 0, productClass: 512)
        record(&recorder, "unknown", north: 0, at: 0, productClass: 0)
        recorder.remove(products: [.bus, .tram])
        XCTAssertEqual(Set(recorder.tracks.keys), ["train", "unknown"], "a vehicle of unknown class stays")
        XCTAssertEqual(recorder.sampleCount, 2)
        recorder.remove { $0 == 1 }
        XCTAssertEqual(Set(recorder.tracks.keys), ["unknown"])
    }

    func testClearForgetsEverything() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 10)
        XCTAssertEqual(recorder.firstRecordedAt, F.at(10))
        recorder.clear()
        XCTAssertTrue(recorder.isEmpty)
        XCTAssertEqual(recorder.sampleCount, 0)
        XCTAssertNil(recorder.firstRecordedAt)
        XCTAssertNil(recorder.latestAt)
    }

    func testFirstRecordedAtIsTheEarliestAnswer() {
        var recorder = RadarTrailRecorder()
        record(&recorder, "a", north: 0, at: 40)
        record(&recorder, "a", north: 100, at: 20)
        XCTAssertEqual(recorder.firstRecordedAt, F.at(20))
        XCTAssertEqual(recorder.latestAt, F.at(40))
        recorder.record([], at: F.at(0))
        XCTAssertEqual(recorder.firstRecordedAt, F.at(20), "an empty answer records nothing")
    }

    func testTheSeventyFirstSampleDropsTheOldest() {
        var recorder = RadarTrailRecorder(window: 3_600)
        for i in 0..<71 { record(&recorder, "a", north: Double(i) * 100, at: Double(i) * 20) }
        let samples = recorder.samples(for: "a")
        XCTAssertEqual(samples.count, RadarTrailRecorder.maxSamplesPerTrip)
        XCTAssertEqual(samples.first?.from, F.at(20))
        XCTAssertEqual(recorder.sampleCount, 70)
    }

    func testTheLongestWindowAtTheTwentySecondCadenceIsKeptWhole() {
        let setting = RadarTrailSetting(mode: .mine, minutes: 20)
        var recorder = RadarTrailRecorder(window: setting.window)
        let answers = Int(setting.window / 20)   // 66
        for i in 0...answers { record(&recorder, "a", north: Double(i) * 100, at: Double(i) * 20) }
        XCTAssertEqual(recorder.samples(for: "a").count, answers + 1, "22 minutes at 20 s: every answer stays")
        XCTAssertLessThanOrEqual(answers + 1, RadarTrailRecorder.maxSamplesPerTrip)
    }

    func testTheTripCapEvictsTheTripSeenLeastRecently() {
        var recorder = RadarTrailRecorder(window: 7_200)
        recorder.record([F.vehicle("old", at: F.base)], at: F.at(0))
        let many = (0..<(RadarTrailRecorder.maxTrips - 1)).map { F.vehicle("t\($0)", at: F.base) }
        recorder.record(many, at: F.at(20))
        XCTAssertEqual(recorder.tripCount, RadarTrailRecorder.maxTrips)
        recorder.record([F.vehicle("new", at: F.base)], at: F.at(40))
        XCTAssertEqual(recorder.tripCount, RadarTrailRecorder.maxTrips)
        XCTAssertNil(recorder.tracks["old"], "the 4 001st trip evicts the one seen least recently")
        XCTAssertNotNil(recorder.tracks["new"])
        XCTAssertEqual(recorder.sampleCount, storedCount(recorder))
    }

    func testTheSampleCapEvictsByRecency() {
        var recorder = RadarTrailRecorder(window: 7_200)
        // 1 000 trips × 50 samples = 50 000 exactly, the first trip seen first.
        for step in 0..<50 {
            let vehicles = (0..<1_000).map { F.vehicle(String(format: "t%04d", $0), at: F.point(north: Double(step) * 100)) }
            recorder.record(vehicles, at: F.at(Double(step) * 20 + 1))
        }
        XCTAssertEqual(recorder.sampleCount, RadarTrailRecorder.maxSamples)
        // One trip is seen again later, then one more sample anywhere tips the total over the cap.
        recorder.record([F.vehicle("t0000", at: F.point(north: 99_000))], at: F.at(2_000))
        XCTAssertLessThanOrEqual(recorder.sampleCount, RadarTrailRecorder.maxSamples)
        XCTAssertNotNil(recorder.tracks["t0000"], "the trip seen last stays")
        XCTAssertNil(recorder.tracks["t0001"], "the least recently seen trip (lowest id among the oldest) goes first")
        XCTAssertEqual(recorder.sampleCount, storedCount(recorder))
    }

    /// 1 000 vehicles, an answer every 20 s for 30 minutes, random movement: never above a cap, the memory under its bound, only the window kept.
    func testSoakStaysWithinTheCapsAndTheMemoryBound() {
        var recorder = RadarTrailRecorder(window: RadarTrailSetting(mode: .all, minutes: 20).window)
        var rng = SplitMix(seed: 42)
        var positions = (0..<1_000).map { _ in F.point(north: rng.uniform(-20_000, 20_000), east: rng.uniform(-30_000, 30_000)) }
        var peakBytes = 0
        for step in 0..<90 {
            let now = F.at(Double(step) * 20)
            var vehicles: [RadarVehicle] = []
            vehicles.reserveCapacity(positions.count)
            for i in positions.indices {
                if rng.uniform(0, 1) < 0.8 {   // most move, some stand
                    positions[i] = F.point(north: rng.uniform(-400, 400), east: rng.uniform(-400, 400), from: positions[i])
                }
                let delay = Int(rng.uniform(0, 12))
                vehicles.append(F.vehicle(String(format: "trip-%04d", i), at: positions[i], delayMinutes: delay, now: now))
            }
            recorder.record(vehicles, at: now)
            XCTAssertLessThanOrEqual(recorder.tripCount, RadarTrailRecorder.maxTrips)
            XCTAssertLessThanOrEqual(recorder.sampleCount, RadarTrailRecorder.maxSamples)
            XCTAssertTrue(recorder.tracks.values.allSatisfy { $0.samples.count <= RadarTrailRecorder.maxSamplesPerTrip })
            peakBytes = max(peakBytes, recorder.estimatedBytes)
        }
        XCTAssertEqual(recorder.sampleCount, storedCount(recorder))
        XCTAssertLessThan(peakBytes, RadarTrailRecorder.memoryBound, "peak \(peakBytes) bytes")
        let cutoff = F.at(89 * 20 - recorder.window)
        XCTAssertTrue(recorder.tracks.values.allSatisfy { $0.samples.allSatisfy { $0.to >= cutoff.timeIntervalSinceReferenceDate } })
    }

    /// The bound in the worst case of the caps, by `MemoryLayout` alone: every sample slot taken twice over (array growth), 4 000 trips with
    /// long ids.
    func testTheWorstCaseByMemoryLayoutIsUnderFiveMegabytes() {
        let sample = MemoryLayout<RadarTrailRecorder.Packed>.stride
        XCTAssertLessThanOrEqual(sample, 24)
        let trip = MemoryLayout<String>.stride + MemoryLayout<RadarTrailRecorder.Track>.stride + 1 + 32 + 32 + 112   // entry, header, a 100-byte id
        let worst = 2 * RadarTrailRecorder.maxSamples * sample + 2 * RadarTrailRecorder.maxTrips * trip
        XCTAssertLessThan(worst, RadarTrailRecorder.memoryBound, "\(worst) bytes")
    }
}

/// A small deterministic generator (the soak test's „random“ movement is the same in every run).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * Double(next() >> 11) / Double(1 << 53)
    }
}
