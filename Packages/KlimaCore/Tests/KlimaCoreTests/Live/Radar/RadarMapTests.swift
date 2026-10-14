import XCTest
@testable import KlimaCore

/// Zug-Radar pure logic (docs/OEBB_LIVE.md §R7): tiling, frame retention, estimates, delay tint, filter, search,
/// clusters and the summary line. No network, no clock: every function gets `now`.
final class RadarMapTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)

    private func stop(_ name: String, planned: Date?, delay: Int? = nil) -> Stopover {
        let realtime = (planned.flatMap { p in delay.map { p.addingTimeInterval(TimeInterval($0)) } })
        let event = planned.map { StopEvent(planned: $0, realtime: realtime) }
        return Stopover(location: Location(lid: "lid|\(name)", name: name), departure: event)
    }

    private func vehicle(_ id: String, line: String, category: String, lat: Double = 47.2, lon: Double = 11.4,
                         direction: String? = nil, stops: [Stopover] = [], cancelled: Bool = false) -> RadarVehicle {
        RadarVehicle(tripID: id, line: Line(name: line, category: category, productClass: 1, mode: .train),
                     direction: direction, coordinate: GeoPoint(latitude: lat, longitude: lon), stopovers: stops,
                     isCancelled: cancelled)
    }

    // MARK: Tiling

    func testTruncationAtServerCap() {
        XCTAssertFalse(RadarTiling.isTruncated(count: 255))
        XCTAssertTrue(RadarTiling.isTruncated(count: 256))
    }

    func testQuadrantsCoverTheBoxWithoutLeavingIt() {
        let box = RadarBox(north: 48, west: 13, south: 46, east: 17)
        let tiles = RadarTiling.tiles(for: box, split: true)
        XCTAssertEqual(tiles.count, RadarTiling.maxTiles)
        XCTAssertTrue(tiles.allSatisfy { $0.isValid })
        XCTAssertTrue(tiles.allSatisfy { $0.north <= box.north && $0.south >= box.south && $0.west >= box.west && $0.east <= box.east })
        // Each quadrant is a quarter of the area and they touch at the centre.
        let area = tiles.reduce(0.0) { $0 + ($1.north - $1.south) * ($1.east - $1.west) }
        XCTAssertEqual(area, (box.north - box.south) * (box.east - box.west), accuracy: 1e-9)
        XCTAssertEqual(tiles.map(\.north).max() ?? 0, box.north, accuracy: 1e-12)
        XCTAssertEqual(tiles.map(\.east).max() ?? 0, box.east, accuracy: 1e-12)
    }

    func testNoSplitKeepsOneRectangleAndInvalidBoxAsksNothing() {
        let box = RadarBox.austria
        XCTAssertEqual(RadarTiling.tiles(for: box, split: false), [box])
        let flat = RadarBox(north: 47, west: 13, south: 47, east: 14)
        XCTAssertTrue(RadarTiling.tiles(for: flat, split: true).isEmpty)
        XCTAssertTrue(RadarTiling.quadrants(of: flat).isEmpty)
    }

    // MARK: Frame store and estimates

    func testVehicleStaysSixtySecondsAfterLastSeen() {
        var store = RadarFrameStore()
        store.merge([vehicle("a", line: "RJX 66", category: "RJX")], at: t0)
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(60)).count, 1, "exactly 60 s is still shown")
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(61)).count, 0, "after 60 s the frame is gone")
    }

    func testMergeKeepsPreviousPositionOnlyWhenItMoved() {
        var store = RadarFrameStore()
        store.merge([vehicle("a", line: "RJX 66", category: "RJX", lat: 47.0)], at: t0)
        store.merge([vehicle("a", line: "RJX 66", category: "RJX", lat: 47.2)], at: t0.addingTimeInterval(20))
        let moved = store.entries["a"]
        XCTAssertEqual(moved?.previousCoordinate?.latitude ?? 0, 47.0, accuracy: 1e-12)
        XCTAssertEqual(moved?.previousSeenAt, t0)
        // Same position again: the previous point stays the one before the move.
        store.merge([vehicle("a", line: "RJX 66", category: "RJX", lat: 47.2)], at: t0.addingTimeInterval(40))
        XCTAssertEqual(store.entries["a"]?.previousCoordinate?.latitude ?? 0, 47.0, accuracy: 1e-12)
    }

    func testEstimateMovesLinearlyBetweenAnswersAndHoldsAfterwards() throws {
        var store = RadarFrameStore()
        store.merge([vehicle("a", line: "RJX 66", category: "RJX", lat: 47.0, lon: 11.0)], at: t0)
        store.merge([vehicle("a", line: "RJX 66", category: "RJX", lat: 47.2, lon: 11.4)], at: t0.addingTimeInterval(20))
        let entry = try XCTUnwrap(store.entries["a"])

        let middle = RadarEstimate.position(of: entry, at: t0.addingTimeInterval(10))
        XCTAssertEqual(middle.coordinate.latitude, 47.1, accuracy: 1e-9)
        XCTAssertEqual(middle.coordinate.longitude, 11.2, accuracy: 1e-9)
        XCTAssertTrue(middle.isEstimate, "between two answers the position is an estimate")

        let late = RadarEstimate.position(of: entry, at: t0.addingTimeInterval(45))
        XCTAssertEqual(late.coordinate.latitude, 47.2, accuracy: 1e-9, "after the latest answer it holds, no extrapolation")
        XCTAssertFalse(late.isEstimate)

        let early = RadarEstimate.position(of: entry, at: t0.addingTimeInterval(-5))
        XCTAssertEqual(early.coordinate.latitude, 47.0, accuracy: 1e-9, "before the previous answer it starts there")
    }

    func testSingleAnswerIsNotAnEstimate() throws {
        var store = RadarFrameStore()
        store.merge([vehicle("a", line: "RJX 66", category: "RJX")], at: t0)
        let entry = try XCTUnwrap(store.entries["a"])
        XCTAssertFalse(RadarEstimate.position(of: entry, at: t0.addingTimeInterval(5)).isEstimate)
    }

    // MARK: Delay tint

    func testDelayTintThresholdsAndCancellation() {
        let planned = t0.addingTimeInterval(600)
        XCTAssertEqual(RadarDelay.state(of: vehicle("a", line: "RJX 66", category: "RJX", stops: [stop("Linz Hbf", planned: planned, delay: 299)]), now: t0), .onTime)
        XCTAssertEqual(RadarDelay.state(of: vehicle("a", line: "RJX 66", category: "RJX", stops: [stop("Linz Hbf", planned: planned, delay: 300)]), now: t0), .late, "five minutes is late")
        XCTAssertEqual(RadarDelay.state(of: vehicle("a", line: "RJX 66", category: "RJX", stops: [stop("Linz Hbf", planned: planned, delay: 900)], cancelled: true), now: t0), .cancelled, "cancelled wins over delay")
        XCTAssertEqual(RadarDelay.state(of: vehicle("a", line: "RJX 66", category: "RJX"), now: t0), .unknown, "no realtime data is unknown, never on time")
    }

    func testCurrentDelayIsTheNextStopNotYetReached() {
        let stops = [
            stop("Wien Hbf", planned: t0.addingTimeInterval(-600), delay: 0),
            stop("St. Pölten Hbf", planned: t0.addingTimeInterval(-60), delay: 420),
            stop("Amstetten", planned: t0.addingTimeInterval(900), delay: 600),
        ]
        let v = vehicle("a", line: "RJX 66", category: "RJX", stops: stops)
        XCTAssertEqual(RadarDelay.currentDelay(of: v, now: t0), 600, "the next stop carries the delay now")
        // After the last stop the last known delay is used.
        XCTAssertEqual(RadarDelay.currentDelay(of: v, now: t0.addingTimeInterval(5_000)), 600)
    }

    // MARK: Regions

    func testRegionGuessByStopKeywords() {
        let tirol = vehicle("t", line: "RJX 66", category: "RJX", direction: "Innsbruck Hbf",
                            stops: [stop("Wörgl Hbf", planned: nil), stop("Innsbruck Hbf", planned: nil)])
        XCTAssertEqual(AustrianState.guess(for: tirol), .tirol)
        let linz = vehicle("o", line: "R 1", category: "R", stops: [stop("Linz Hbf", planned: nil), stop("Wels", planned: nil)])
        XCTAssertEqual(AustrianState.guess(for: linz), .oberoesterreich)
        let unknown = vehicle("u", line: "R 2", category: "R", stops: [stop("Nirgendwo", planned: nil)])
        XCTAssertNil(AustrianState.guess(for: unknown))
        let tie = vehicle("x", line: "R 3", category: "R", stops: [stop("Linz Hbf", planned: nil), stop("Innsbruck Hbf", planned: nil)])
        XCTAssertNil(AustrianState.guess(for: tie), "a tie is no answer")
    }

    // MARK: Filter

    func testFilterByCategoryDelayAndRegion() {
        let late = vehicle("1", line: "RJX 66", category: "RJX", direction: "Innsbruck Hbf",
                           stops: [stop("Innsbruck Hbf", planned: t0.addingTimeInterval(60), delay: 400)])
        let ontime = vehicle("2", line: "REX 92", category: "REX", direction: "Wiener Neustadt Hbf",
                             stops: [stop("Wiener Neustadt Hbf", planned: t0.addingTimeInterval(60), delay: 0)])
        let cancelled = vehicle("3", line: "EC 81", category: "EC", stops: [], cancelled: true)
        let all = [late, ontime, cancelled]

        var onlyRJX = RadarFilter(); onlyRJX.categories = ["RJX"]
        XCTAssertEqual(onlyRJX.apply(all, now: t0).map(\.tripID), ["1"])

        var onlyLate = RadarFilter(); onlyLate.onlyLate = true
        XCTAssertEqual(onlyLate.apply(all, now: t0).map(\.tripID), ["1"])

        var cancelledOnly = RadarFilter(); cancelledOnly.delays = [.cancelled]
        XCTAssertEqual(cancelledOnly.apply(all, now: t0).map(\.tripID), ["3"])

        var tirol = RadarFilter(); tirol.state = .tirol
        XCTAssertEqual(tirol.apply(all, now: t0).map(\.tripID), ["1"])

        XCTAssertFalse(RadarFilter().isActive)
        XCTAssertEqual(RadarFilter().apply(all, now: t0).count, 3, "the default filter keeps everything")
    }

    // MARK: Search

    func testSearchParsesCategoryAndNumberInAnyWriting() throws {
        for text in ["RJX 66", "rjx66", " RJX  66 "] {
            let q = try XCTUnwrap(RadarSearchQuery(text))
            XCTAssertEqual(q.category, "RJX", text)
            XCTAssertEqual(q.number, "66", text)
        }
        let number = try XCTUnwrap(RadarSearchQuery("66"))
        XCTAssertNil(number.category)
        XCTAssertEqual(number.number, "66")
        let word = try XCTUnwrap(RadarSearchQuery("Innsbruck"))
        XCTAssertNil(word.category, "a plain word is text, not a category")
        XCTAssertNil(word.number)
        XCTAssertNil(RadarSearchQuery("   "))
    }

    func testSearchMatchesTrainsAndSuggestsUniqueLines() throws {
        let vehicles = [
            vehicle("a", line: "RJX 66", category: "RJX", direction: "Innsbruck Hbf"),
            vehicle("b", line: "RJX 66", category: "RJX", direction: "Wien Hbf"),
            vehicle("c", line: "REX 92", category: "REX", direction: "Wiener Neustadt Hbf"),
            vehicle("d", line: "RJX 1830", category: "RJX", direction: "Wien Hbf"),
        ]
        let rjx66 = try XCTUnwrap(RadarSearchQuery("RJX 66"))
        XCTAssertEqual(vehicles.filter(rjx66.matches).map(\.tripID), ["a", "b"])
        let number = try XCTUnwrap(RadarSearchQuery("66"))
        XCTAssertEqual(vehicles.filter(number.matches).map(\.tripID), ["a", "b"], "a bare number matches the exact token")
        let rj = try XCTUnwrap(RadarSearchQuery("RJX"))
        XCTAssertEqual(vehicles.filter(rj.matches).count, 3)
        let text = try XCTUnwrap(RadarSearchQuery("neustadt"))
        XCTAssertEqual(vehicles.filter(text.matches).map(\.tripID), ["c"])

        let suggestions = RadarSearch.suggestions(for: rj, in: vehicles)
        XCTAssertEqual(suggestions.compactMap { $0.line?.name }, ["RJX 1830", "RJX 66"], "one suggestion per line, sorted")
    }

    // MARK: Clusters

    func testClustersGroupByCellAndCountDelay() {
        let points = [
            RadarPoint(tripID: "a", coordinate: GeoPoint(latitude: 47.201, longitude: 11.401), delay: .late),
            RadarPoint(tripID: "b", coordinate: GeoPoint(latitude: 47.203, longitude: 11.404), delay: .onTime),
            RadarPoint(tripID: "c", coordinate: GeoPoint(latitude: 48.20, longitude: 16.37), delay: .cancelled),
        ]
        let clusters = RadarClustering.group(points, cellDegrees: 0.1)
        XCTAssertEqual(clusters.count, 2)
        let pair = clusters.first { $0.count == 2 }
        XCTAssertEqual(pair?.tripIDs, ["a", "b"])
        XCTAssertEqual(pair?.lateCount, 1)
        XCTAssertEqual(clusters.first { $0.isSingle }?.cancelledCount, 1)
        XCTAssertEqual(RadarClustering.group(points, cellDegrees: 0.1).map(\.id), clusters.map(\.id), "stable ids")
        XCTAssertTrue(RadarClustering.group(points, cellDegrees: 0).isEmpty)
    }

    func testCellSizeGrowsWithTheVisibleSpan() {
        XCTAssertLessThan(RadarClustering.cellSize(forLatitudeSpan: 0.5), RadarClustering.cellSize(forLatitudeSpan: 4))
        XCTAssertEqual(RadarClustering.cellSize(forLatitudeSpan: .nan), 0.01)
        XCTAssertGreaterThanOrEqual(RadarClustering.cellSize(forLatitudeSpan: 0.001), 0.005)
    }

    func testBearingPointsNorthEastSouthWest() {
        let origin = GeoPoint(latitude: 47, longitude: 11)
        XCTAssertEqual(RadarBearing.degrees(from: origin, to: GeoPoint(latitude: 48, longitude: 11)), 0, accuracy: 0.01)
        XCTAssertEqual(RadarBearing.degrees(from: origin, to: GeoPoint(latitude: 47, longitude: 12)), 90, accuracy: 0.5)
        XCTAssertEqual(RadarBearing.degrees(from: origin, to: GeoPoint(latitude: 46, longitude: 11)), 180, accuracy: 0.01)
        XCTAssertEqual(RadarBearing.degrees(from: origin, to: GeoPoint(latitude: 47, longitude: 10)), 270, accuracy: 0.5)
    }

    func testNextStopIsFirstPlannedAfterNow() throws {
        let stops = [stop("Wien Hbf", planned: t0.addingTimeInterval(-600)), stop("Linz Hbf", planned: t0.addingTimeInterval(300))]
        let next = try XCTUnwrap(RadarRun.nextStop(of: vehicle("a", line: "RJX 66", category: "RJX", stops: stops), now: t0))
        XCTAssertEqual(next.location.name, "Linz Hbf")
        XCTAssertNil(RadarRun.nextStop(of: vehicle("a", line: "RJX 66", category: "RJX", stops: stops), now: t0.addingTimeInterval(900)))
    }

    // MARK: Summary and text

    func testSummaryLine() {
        XCTAssertEqual(RadarSummary.line(count: 12, late: 3, rail: true), "12 Züge im Ausschnitt, 3 verspätet")
        XCTAssertEqual(RadarSummary.line(count: 1, late: 0, rail: true), "1 Zug im Ausschnitt")
        XCTAssertEqual(RadarSummary.line(count: 2, late: 0, rail: false), "2 Fahrzeuge im Ausschnitt")
    }

    func testFoldingForComparisons() {
        XCTAssertEqual(RadarText.fold("Mödling Wörgl"), "modling worgl")
        XCTAssertEqual(RadarText.words("St. Pölten Hbf"), ["st", "polten", "hbf"])
    }
}
