import XCTest
@testable import KlimaCore

/// The aggregation of the delay heat map (docs/RADAR_HEATMAP.md): buckets with the radar's own limit, the median, the minimum
/// sample rule, the no-realtime rule, national numbers, top delays, hot spots, determinism and a bound for 2 000 trains.
final class RadarHeatTests: XCTestCase {
    private let tirol = GeoPoint(latitude: 47.30, longitude: 11.70)

    private func sample(_ id: String, at point: GeoPoint? = nil, delay: Int? = 0, cancelled: Bool = false, line: String = "RJX 66",
                        next: String? = nil) -> HeatSample {
        HeatSample(tripID: id, coordinate: point ?? tirol, lineTitle: line, direction: "Wien Hbf", nextStopName: next, delaySeconds: delay,
                   isCancelled: cancelled)
    }

    /// `count` trains in the cell of `point`, each with the given delay.
    private func trains(_ prefix: String, count: Int, delays: [Int?], at point: GeoPoint? = nil, next: String? = nil) -> [HeatSample] {
        (0..<count).map { index in sample("\(prefix)\(index)", at: point, delay: delays[index % delays.count], next: next) }
    }

    // MARK: Buckets

    func testBucketLimitsAreTheRadarsOwn() {
        XCTAssertEqual(RadarHeat.lateThresholdSeconds, RadarDelay.lateThresholdSeconds)
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: 299, isCancelled: false), .onTime)
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: 300, isCancelled: false), .delayed, "5:00 is late, like the marker's ring")
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: 900, isCancelled: false), .delayed, "15:00 is still 5 to 15")
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: 901, isCancelled: false), .severe)
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: -120, isCancelled: false), .onTime, "early is on time")
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: nil, isCancelled: false), .noRealtime)
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: 1200, isCancelled: true), .cancelled)
        XCTAssertEqual(RadarHeat.bucket(delaySeconds: nil, isCancelled: true), .cancelled)
    }

    func testBucketsAgreeWithTheRadarsDelayState() {
        let now = Date(timeIntervalSince1970: 1_791_796_500)
        for delay in [0, 120, 299, 300, 600, 900, 901, 2400] {
            let planned = now.addingTimeInterval(600)
            let vehicle = RadarVehicle(tripID: "t", coordinate: tirol, stopovers: [
                Stopover(location: Location(lid: "l", name: "Jenbach"), arrival: StopEvent(planned: planned, realtime: planned.addingTimeInterval(TimeInterval(delay))))])
            let heat = HeatSample(vehicle: vehicle, coordinate: tirol, now: now)
            let state = RadarDelay.state(of: vehicle, now: now)
            XCTAssertEqual(heat.bucket == .onTime, state == .onTime, "delay \(delay)")
            XCTAssertEqual(heat.bucket == .delayed || heat.bucket == .severe, state == .late, "delay \(delay)")
            XCTAssertEqual(heat.delaySeconds, delay)
            XCTAssertEqual(heat.nextStopName, "Jenbach")
        }
    }

    func testAVehicleWithoutRealtimeAndACancelledOne() {
        let now = Date(timeIntervalSince1970: 1_791_796_500)
        let planned = now.addingTimeInterval(600)
        let noData = RadarVehicle(tripID: "a", coordinate: tirol, stopovers: [
            Stopover(location: Location(lid: "l", name: "Jenbach"), arrival: StopEvent(planned: planned))])
        XCTAssertEqual(HeatSample(vehicle: noData, coordinate: tirol, now: now).bucket, .noRealtime)
        let cancelled = RadarVehicle(tripID: "b", coordinate: tirol, stopovers: noData.stopovers, isCancelled: true)
        let heat = HeatSample(vehicle: cancelled, coordinate: tirol, now: now)
        XCTAssertEqual(heat.bucket, .cancelled)
        XCTAssertNil(heat.delaySeconds, "a cancelled train has no delay to average")
        XCTAssertEqual(HeatSample(vehicle: RadarVehicle(tripID: "c", coordinate: tirol), coordinate: tirol, now: now).lineTitle, "Zug")
    }

    // MARK: Median and the minimum sample

    func testMedian() {
        XCTAssertNil(RadarHeat.median([]))
        XCTAssertEqual(RadarHeat.median([600]), 600)
        XCTAssertEqual(RadarHeat.median([900, 60, 300]), 300)
        XCTAssertEqual(RadarHeat.median([60, 120, 600, 900]), 360, "even count: the mean of the middle two")
        XCTAssertEqual(RadarHeat.median([0, 0, 0, 3000]), 0, "one extreme train does not move the median")
    }

    func testACellWithFewerThanThreeTrainsStaysNeutral() {
        let two = RadarHeat.snapshot(trains("a", count: 2, delays: [1800]))
        XCTAssertEqual(two.cells.count, 1)
        XCTAssertTrue(two.cells[0].isNeutral)
        XCTAssertNil(two.cells[0].medianDelaySeconds, "never a median, never a colour")
        XCTAssertNil(two.cells[0].bucket)
        XCTAssertEqual(two.cells[0].sampleCount, 2)
        XCTAssertTrue(two.hotspots.isEmpty, "a neutral cell is no hot spot however late its two trains are")

        let three = RadarHeat.snapshot(trains("a", count: 3, delays: [1800]))
        XCTAssertFalse(three.cells[0].isNeutral)
        XCTAssertEqual(three.cells[0].medianDelaySeconds, 1800)
        XCTAssertEqual(three.cells[0].bucket, .severe)
        XCTAssertEqual(RadarHeat.minimumSample, 3)
    }

    func testTheMinimumCountsTrainsWithADelayNotAllTrains() {
        // Two trains with a delay and five without realtime data: seven trains in the cell, but only two to base a median on.
        let input = trains("a", count: 2, delays: [900]) + trains("b", count: 5, delays: [nil])
        let cell = RadarHeat.snapshot(input).cells[0]
        XCTAssertEqual(cell.trainCount, 7)
        XCTAssertEqual(cell.sampleCount, 2)
        XCTAssertEqual(cell.noRealtimeCount, 5)
        XCTAssertTrue(cell.isNeutral)
    }

    func testCancelledTrainsAreCountedButNotInTheMedian() {
        let input = trains("a", count: 3, delays: [120]) + [sample("x", delay: 3600, cancelled: true)]
        let cell = RadarHeat.snapshot(input).cells[0]
        XCTAssertEqual(cell.trainCount, 4)
        XCTAssertEqual(cell.sampleCount, 3)
        XCTAssertEqual(cell.cancelledCount, 1)
        XCTAssertEqual(cell.medianDelaySeconds, 120)
        XCTAssertEqual(cell.delaySumMinutes, 6, accuracy: 1e-9)
    }

    func testAnEarlyTrainCountsZeroInTheDelaySum() {
        let cell = RadarHeat.snapshot(trains("a", count: 3, delays: [-300, 600, 60])).cells[0]
        XCTAssertEqual(cell.delaySumMinutes, 11, accuracy: 1e-9)
        XCTAssertEqual(cell.lateCount, 1)
    }

    func testTrainsFallIntoTheirOwnCells() {
        let far = GeoPoint(latitude: 48.20, longitude: 16.37)
        let snapshot = RadarHeat.snapshot(trains("a", count: 3, delays: [0]) + trains("w", count: 4, delays: [900], at: far))
        XCTAssertEqual(snapshot.cells.count, 2)
        XCTAssertEqual(snapshot.cells.map(\.trainCount).sorted(), [3, 4])
        XCTAssertEqual(snapshot.cells.map(\.id), snapshot.cells.map(\.id).sorted(), "cells are sorted by id")
        let wien = snapshot.cell(HeatGrid.cell(containing: far))
        XCTAssertEqual(wien?.medianDelaySeconds, 900)
        XCTAssertNil(snapshot.cell(HeatCellID(q: 999, r: 999)))
        for cell in snapshot.cells { XCTAssertEqual(snapshot.cell(cell.id), cell, "the binary search finds every cell") }
    }

    // MARK: National numbers and the no-realtime rule

    func testNoRealtimeIsNeverPunctual() {
        // 3 punctual, 1 late, 6 without realtime data: the percentage is over the four that have data.
        let input = trains("p", count: 3, delays: [60]) + [sample("l", delay: 1200)] + trains("n", count: 6, delays: [nil])
        let summary = RadarHeat.snapshot(input).summary
        XCTAssertEqual(summary.total, 10)
        XCTAssertEqual(summary.withRealtime, 4)
        XCTAssertEqual(summary.noRealtime, 6)
        XCTAssertEqual(summary.onTime, 3)
        XCTAssertEqual(summary.punctualShare ?? 0, 0.75, accuracy: 1e-12)
        XCTAssertEqual(summary.punctualPercent, 75, "not 30 % (3 of 10) and not 90 % (everything without data counted as punctual)")
    }

    func testWithoutAnyRealtimeThereIsNoPercentage() {
        let summary = RadarHeat.snapshot(trains("n", count: 5, delays: [nil])).summary
        XCTAssertEqual(summary.withRealtime, 0)
        XCTAssertEqual(summary.noRealtime, 5)
        XCTAssertNil(summary.punctualShare)
        XCTAssertNil(summary.punctualPercent)
        XCTAssertTrue(summary.segments.isEmpty)
        XCTAssertNil(summary.averageLateSeconds)
    }

    func testCancelledCountsAsOneOfTheTrainsWithDataAndNotPunctual() {
        let input = trains("p", count: 3, delays: [0]) + [sample("x", delay: nil, cancelled: true)]
        let summary = RadarHeat.snapshot(input).summary
        XCTAssertEqual(summary.cancelled, 1)
        XCTAssertEqual(summary.withRealtime, 4)
        XCTAssertEqual(summary.punctualPercent, 75)
        XCTAssertEqual(summary.late, 0)
    }

    func testRoundingNeverSaysAHundredWhileATrainIsLate() {
        var input = trains("p", count: 999, delays: [0], at: GeoPoint(latitude: 48.0, longitude: 14.0))
        input.append(sample("late", delay: 600))
        let summary = RadarHeat.snapshot(input).summary
        XCTAssertEqual(summary.punctualPercent, 99, "99.9 % rounds to 100, but a train is late")
        let allGood = RadarHeat.snapshot(trains("p", count: 5, delays: [0])).summary
        XCTAssertEqual(allGood.punctualPercent, 100)
        var few = trains("l", count: 1000, delays: [900], at: GeoPoint(latitude: 48.0, longitude: 14.0))
        few.append(sample("ok", delay: 0))
        XCTAssertEqual(RadarHeat.snapshot(few).summary.punctualPercent, 1, "0.1 % of punctual trains is not 0 %")
        let none = RadarHeat.snapshot(trains("l", count: 4, delays: [900])).summary
        XCTAssertEqual(none.punctualPercent, 0)
    }

    func testTheAverageDelayIsOverTheLateTrainsOnly() {
        let input = trains("p", count: 5, delays: [0]) + [sample("a", delay: 600), sample("b", delay: 1200), sample("c", delay: 300)]
        let summary = RadarHeat.snapshot(input).summary
        XCTAssertEqual(summary.late, 3)
        XCTAssertEqual(summary.averageLateSeconds ?? 0, 700, accuracy: 1e-9)
        XCTAssertEqual(summary.delayed, 2)
        XCTAssertEqual(summary.severe, 1)
    }

    func testTheStackedBarAddsUpToOne() {
        let input = trains("p", count: 6, delays: [0]) + [sample("a", delay: 600), sample("b", delay: 1200), sample("x", cancelled: true)]
            + trains("n", count: 3, delays: [nil])
        let segments = RadarHeat.snapshot(input).summary.segments
        XCTAssertEqual(segments.map(\.bucket), [.onTime, .delayed, .severe, .cancelled])
        XCTAssertEqual(segments.map(\.count), [6, 1, 1, 1])
        XCTAssertEqual(segments.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-12, "no-realtime trains are not part of the bar")
        XCTAssertEqual(segments[0].share, 6.0 / 9.0, accuracy: 1e-12)
    }

    // MARK: Top delays

    func testTopDelaysAreTheFiveLargestAtLeastFiveMinutes() {
        var input = trains("p", count: 10, delays: [0, 120, 240])
        for (index, delay) in [3000, 900, 1800, 301, 299, 600, 2400, 1200].enumerated() {
            input.append(sample("late\(index)", at: GeoPoint(latitude: 47.0 + Double(index) * 0.2, longitude: 12.0), delay: delay))
        }
        let top = RadarHeat.snapshot(input).topDelays
        XCTAssertEqual(top.map(\.delaySeconds), [3000, 2400, 1800, 1200, 900])
        XCTAssertEqual(top.count, RadarHeat.topDelayCount)
    }

    func testTopDelaysHoldOnlyLateTrainsAndBreakTiesByTripID() {
        XCTAssertTrue(RadarHeat.snapshot(trains("p", count: 8, delays: [0, 299])).topDelays.isEmpty, "no train is 5 minutes late: nothing to list")
        let tied = RadarHeat.snapshot([sample("b", delay: 600), sample("a", delay: 600), sample("c", delay: 900)]).topDelays
        XCTAssertEqual(tied.map(\.tripID), ["c", "a", "b"])
    }

    func testTopDelaysSkipCancelledAndNoRealtimeTrains() {
        let top = RadarHeat.snapshot([sample("x", cancelled: true), sample("n", delay: nil), sample("l", delay: 700)]).topDelays
        XCTAssertEqual(top.map(\.tripID), ["l"])
    }

    // MARK: Hot spots

    func testHotspotsAreRankedBySumOfDelayMinutes() {
        let a = GeoPoint(latitude: 47.30, longitude: 11.70)
        let b = GeoPoint(latitude: 47.80, longitude: 13.0)
        let c = GeoPoint(latitude: 48.20, longitude: 16.37)
        let d = GeoPoint(latitude: 46.62, longitude: 14.30)
        let input = trains("a", count: 4, delays: [1200], at: a, next: "Jenbach")   // 80 min together
            + trains("b", count: 3, delays: [900], at: b, next: "Salzburg Hbf")      // 45
            + trains("c", count: 10, delays: [360], at: c, next: "Wien Hbf")         // 60
            + trains("d", count: 3, delays: [330], at: d, next: "Klagenfurt Hbf")    // 16.5
        let hotspots = RadarHeat.snapshot(input).hotspots
        XCTAssertEqual(hotspots.count, RadarHeat.hotspotCount)
        XCTAssertEqual(hotspots.map(\.rank), [1, 2, 3])
        XCTAssertEqual(hotspots.map(\.placeName), ["Jenbach", "Wien Hbf", "Salzburg Hbf"])
        XCTAssertEqual(hotspots[0].delaySumMinutes, 80, accuracy: 1e-9)
        XCTAssertEqual(hotspots[0].sampleCount, 4)
        XCTAssertEqual(hotspots[0].lateCount, 4)
        XCTAssertEqual(hotspots[0].medianDelaySeconds, 1200)
    }

    func testHotspotsNeedAMinimumSampleAndALateMedian() {
        // Two very late trains: too few. Twelve trains about four minutes late: many minutes in total, but not late.
        let input = trains("few", count: 2, delays: [3000], at: tirol)
            + trains("calm", count: 12, delays: [240], at: GeoPoint(latitude: 48.2, longitude: 16.4))
        XCTAssertTrue(RadarHeat.snapshot(input).hotspots.isEmpty)
    }

    func testAHotspotNextToABetterOneIsSkipped() {
        let first = HeatCellID(q: 0, r: 0)
        let next = HeatGrid.neighbors(of: first)[0]
        let apart = HeatCellID(q: 6, r: 0)
        let input = trains("a", count: 5, delays: [1200], at: HeatGrid.center(of: first))
            + trains("b", count: 4, delays: [1200], at: HeatGrid.center(of: next))
            + trains("c", count: 3, delays: [600], at: HeatGrid.center(of: apart))
        let hotspots = RadarHeat.snapshot(input).hotspots
        XCTAssertEqual(hotspots.map(\.cellID), [first, apart], "three hot spots are three places, not one corridor counted twice")
    }

    func testAHotspotTwoStepsAwayIsSkippedToo() {
        let origin = HeatCellID(q: 0, r: 0)
        let twoAway = HeatCellID(q: 2, r: 0), threeAway = HeatCellID(q: 3, r: 0)
        XCTAssertEqual(HeatGrid.distance(origin, twoAway), 2)
        XCTAssertEqual(HeatGrid.distance(origin, threeAway), 3)
        let input = trains("a", count: 5, delays: [1200], at: HeatGrid.center(of: origin))
            + trains("b", count: 4, delays: [1200], at: HeatGrid.center(of: twoAway))
            + trains("c", count: 3, delays: [1200], at: HeatGrid.center(of: threeAway))
        let hotspots = RadarHeat.snapshot(input).hotspots
        XCTAssertEqual(hotspots.map(\.cellID), [origin, threeAway], "two steps (about 27 km) is still the same place; three is another")
        XCTAssertEqual(RadarHeat.hotspotSeparation, 2)
    }

    func testThePlaceNameIsTheMostCommonNextStop() {
        let input = [sample("a", next: "Schwaz"), sample("b", next: "Jenbach"), sample("c", next: "Jenbach"), sample("d", next: nil)]
        XCTAssertEqual(RadarHeat.snapshot(input).cells[0].placeName, "Jenbach")
        let tied = [sample("a", next: "Wörgl Hbf"), sample("b", next: "Jenbach")]
        XCTAssertEqual(RadarHeat.snapshot(tied).cells[0].placeName, "Jenbach", "a tie goes to the name that sorts first")
        XCTAssertNil(RadarHeat.snapshot([sample("a", next: nil), sample("b", next: "")]).cells[0].placeName)
    }

    // MARK: Empty, partial, odd input

    func testNoTrainsGiveTheEmptySnapshot() {
        let snapshot = RadarHeat.snapshot([])
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot, .empty)
        XCTAssertTrue(snapshot.cells.isEmpty && snapshot.hotspots.isEmpty && snapshot.topDelays.isEmpty)
        XCTAssertEqual(snapshot.summary.total, 0)
        XCTAssertNil(snapshot.summary.punctualPercent)
    }

    func testAPartialAnswerStillAggregatesWhatIsThere() {
        // One region only (the western tile answered): the national numbers are over those trains, not extrapolated.
        let snapshot = RadarHeat.snapshot(trains("w", count: 5, delays: [0, 600]))
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.summary.total, 5)
        XCTAssertEqual(snapshot.cells.count, 1)
    }

    func testDuplicatesCountOnceAndOddPositionsAreDropped() {
        let input = [sample("a", delay: 0), sample("a", delay: 3000), sample("b", at: GeoPoint(latitude: .nan, longitude: 12), delay: 600),
                     sample("c", at: GeoPoint(latitude: 47, longitude: .infinity), delay: 600)]
        let summary = RadarHeat.snapshot(input).summary
        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.late, 0, "of two entries with one trip id the first counts")
    }

    func testTrainsBeyondTheGlobeAreLeftOutLikeNonFiniteOnes() {
        let input = [sample("ok", delay: 0), sample("far", at: GeoPoint(latitude: 1e300, longitude: 12), delay: 600),
                     sample("lon", at: GeoPoint(latitude: 47, longitude: 400), delay: 600)]
        let snapshot = RadarHeat.snapshot(input)
        XCTAssertEqual(snapshot.summary.total, 1)
        XCTAssertEqual(snapshot.cells.count, 1)
        XCTAssertNil(snapshot.sample("far"))
    }

    func testTheSamplesOfACellAreListedLatestFirst() {
        let input = [sample("a", delay: 60), sample("b", delay: 900), sample("c", delay: nil), sample("d", cancelled: true), sample("e", delay: 1500)]
        let snapshot = RadarHeat.snapshot(input)
        let listed = snapshot.samples(in: snapshot.cells[0]).map(\.tripID)
        XCTAssertEqual(listed, ["e", "b", "a", "d", "c"], "latest first, then cancelled, then the trains without realtime data")
        XCTAssertEqual(snapshot.sample("e")?.delaySeconds, 1500)
        XCTAssertNil(snapshot.sample("zzz"))
    }

    // MARK: Determinism

    func testTheOrderOfTheInputChangesNothing() {
        var generator = HeatRandom(seed: 11)
        var input: [HeatSample] = []
        for index in 0..<400 {
            let point = GeoPoint(latitude: 46.5 + generator.unit() * 2.4, longitude: 10.0 + generator.unit() * 6.5)
            let roll = generator.unit()
            input.append(HeatSample(tripID: "t\(index)", coordinate: point, lineTitle: "REX \(index % 9)",
                                    nextStopName: ["Linz Hbf", "Wels Hbf", "Jenbach", "Graz Hbf"][index % 4],
                                    delaySeconds: roll < 0.1 ? nil : Int(generator.unit() * 1500), isCancelled: roll > 0.97))
        }
        let reference = RadarHeat.snapshot(input)
        for seed in 1...5 {
            var shuffled = input
            var rng = HeatRandom(seed: UInt64(seed))
            for index in stride(from: shuffled.count - 1, to: 0, by: -1) {
                shuffled.swapAt(index, Int(rng.next() % UInt64(index + 1)))
            }
            XCTAssertEqual(RadarHeat.snapshot(shuffled), reference, "the same trains in another order give the same cells, ranking and ids")
        }
    }

    // MARK: Size

    func testTwoThousandTrainsAreFastAndBounded() {
        var generator = HeatRandom(seed: 5)
        let input = (0..<2000).map { index -> HeatSample in
            HeatSample(tripID: "t\(index)", coordinate: GeoPoint(latitude: 46.3 + generator.unit() * 2.8, longitude: 9.45 + generator.unit() * 7.8),
                       lineTitle: "REX \(index % 20)", nextStopName: "Halt \(index % 40)", delaySeconds: Int(generator.unit() * 1200))
        }
        let start = Date()
        let snapshot = RadarHeat.snapshot(input)
        let drawn = HeatLayer.drawCells(from: snapshot)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "2 000 trains: aggregation and drawing set well under a second even in a debug build")
        XCTAssertEqual(snapshot.summary.total, 2000)
        XCTAssertLessThanOrEqual(snapshot.cells.count, 1_350, "never more cells than the grid has over the radar's rectangle")
        XCTAssertLessThanOrEqual(drawn.count, HeatLayer.maxDrawnCells)
        XCTAssertLessThanOrEqual(snapshot.topDelays.count, RadarHeat.topDelayCount)
        XCTAssertLessThanOrEqual(snapshot.hotspots.count, RadarHeat.hotspotCount)
    }

    // MARK: Taps

    func testATapFindsTheCellUnderItOrTheNearestOneWithinReach() {
        let snapshot = RadarHeat.snapshot(trains("a", count: 4, delays: [600]))
        let cell = snapshot.cells[0]
        XCTAssertEqual(RadarHeat.cell(at: cell.center, in: snapshot, toleranceKm: 0)?.id, cell.id)
        // Two cells away: the finger missed by a cell and a half. Within 30 km of the centre it still finds it.
        let off = HeatGrid.center(of: HeatCellID(q: cell.id.q + 2, r: cell.id.r))
        XCTAssertNil(RadarHeat.cell(at: off, in: snapshot, toleranceKm: 0))
        XCTAssertNil(RadarHeat.cell(at: off, in: snapshot, toleranceKm: 20), "2 cells = 26 km")
        XCTAssertEqual(RadarHeat.cell(at: off, in: snapshot, toleranceKm: 30)?.id, cell.id)
        XCTAssertNil(RadarHeat.cell(at: off, in: snapshot, toleranceKm: .nan))
        XCTAssertNil(RadarHeat.cell(at: off, in: .empty, toleranceKm: 100))
    }
}
