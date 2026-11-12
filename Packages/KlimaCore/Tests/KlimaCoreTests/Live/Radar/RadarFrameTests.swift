import XCTest
@testable import KlimaCore

/// Zug-Radar vehicles across tiles (docs/OEBB_LIVE.md §R11): retention per answer, dedup by trip id, the lag that follows
/// the tile's refresh interval, and the cluster bounds for thousands of vehicles. No network, no clock.
final class RadarFrameTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_796_500)

    private func vehicle(_ id: String, lat: Double = 47.2, lon: Double = 11.4) -> RadarVehicle {
        RadarVehicle(tripID: id, line: Line(name: "RJX 66", category: "RJX", productClass: 1, mode: .train),
                     coordinate: GeoPoint(latitude: lat, longitude: lon))
    }

    // MARK: Retention per tile

    func testQuietTileKeepsItsTrainsLongerThanTheDefaultMinute() {
        var store = RadarFrameStore()
        // A tile refreshed every 45 s keeps its vehicles 2.5 periods (112.5 s): no train vanishes between two refreshes.
        store.merge([vehicle("quiet")], at: t0, retention: 112.5)
        store.merge([vehicle("dense")], at: t0)
        let after70 = store.visible(at: t0.addingTimeInterval(70)).map(\.vehicle.tripID)
        XCTAssertEqual(after70, ["quiet"], "the dense tile's vehicle is gone after 60 s, the quiet tile's is still there")
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(112)).count, 1)
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(113)).count, 0)
    }

    func testRetentionNeverDropsBelowTheDefault() {
        var store = RadarFrameStore()
        store.merge([vehicle("a")], at: t0, retention: 10)
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(60)).count, 1, "a short retention is raised to the 60 s minimum")
    }

    func testFreshAnswerRenewsTheRetention() {
        var store = RadarFrameStore()
        store.merge([vehicle("a")], at: t0)
        store.merge([vehicle("a")], at: t0.addingTimeInterval(45))
        XCTAssertEqual(store.visible(at: t0.addingTimeInterval(100)).count, 1, "100 s after the first answer, 55 s after the second")
    }

    // MARK: Dedup across tiles

    func testSameTripInTwoTilesIsOneEntryAndTheNewestAnswerWins() {
        var store = RadarFrameStore()
        // Tile A answers first, the neighbouring tile B two seconds later: the trip sits on the edge of both.
        store.merge([vehicle("edge", lat: 47.700), vehicle("a-only", lat: 47.6)], at: t0)
        store.merge([vehicle("edge", lat: 47.701), vehicle("b-only", lat: 47.8)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(store.entries.count, 3)
        let edge = store.entries["edge"]
        XCTAssertEqual(edge?.vehicle.coordinate.latitude ?? 0, 47.701, accuracy: 1e-12, "the newer answer wins")
        XCTAssertEqual(edge?.seenAt, t0.addingTimeInterval(2))
    }

    func testAnOlderAnswerNeverReplacesANewerOne() {
        var store = RadarFrameStore()
        store.merge([vehicle("a", lat: 47.2)], at: t0.addingTimeInterval(20))
        store.merge([vehicle("a", lat: 47.0)], at: t0)   // a slow request that finished late
        XCTAssertEqual(store.entries["a"]?.vehicle.coordinate.latitude ?? 0, 47.2, accuracy: 1e-12)
        XCTAssertEqual(store.entries["a"]?.seenAt, t0.addingTimeInterval(20))
    }

    func testThreeThousandVehiclesFromOverlappingAnswersStayUnique() {
        var store = RadarFrameStore()
        let all = (0..<3000).map { vehicle("trip-\($0)", lat: 46.5 + Double($0 % 100) * 0.02, lon: 9.6 + Double($0 / 100) * 0.2) }
        store.merge(Array(all[0..<1800]), at: t0)                       // tile A
        store.merge(Array(all[1200..<3000]), at: t0.addingTimeInterval(3))   // tile B overlaps by 600
        XCTAssertEqual(store.entries.count, 3000)
        XCTAssertEqual(store.entries["trip-1500"]?.seenAt, t0.addingTimeInterval(3))
        XCTAssertEqual(store.entries["trip-100"]?.seenAt, t0)
    }

    func testSwitchingAModeOffRemovesItsVehiclesAtOnce() {
        var store = RadarFrameStore()
        let bus = RadarVehicle(tripID: "bus", line: Line(name: "Bus 750", productClass: 64, mode: .bus),
                               coordinate: GeoPoint(latitude: 47, longitude: 11))
        store.merge([vehicle("rail"), bus], at: t0)
        store.removeAll { ($0.line?.productClass ?? 0) & ProductMask.bus.rawValue != 0 }
        XCTAssertEqual(store.entries.keys.sorted(), ["rail"])
    }

    // MARK: Lag follows the refresh interval

    func testLagGrowsWithTheIntervalBetweenTwoAnswers() throws {
        var store = RadarFrameStore()
        store.merge([vehicle("a", lat: 47.0)], at: t0)
        store.merge([vehicle("a", lat: 47.45)], at: t0.addingTimeInterval(45))   // a 45 s tile
        let entry = try XCTUnwrap(store.entries["a"])
        XCTAssertEqual(RadarEstimate.lag(of: entry), 45)
        // The moment the answer arrives the marker is where it was one answer ago and then moves over the whole interval:
        // with a fixed 20 s lag it would jump back to 47.25 here (25 of 45 seconds along the way).
        let arrival = RadarEstimate.shown(entry, now: t0.addingTimeInterval(45))
        XCTAssertEqual(arrival.coordinate.latitude, 47.0, accuracy: 1e-9)
        let halfway = RadarEstimate.shown(entry, now: t0.addingTimeInterval(45 + 22.5))
        XCTAssertEqual(halfway.coordinate.latitude, 47.225, accuracy: 1e-9)
        let done = RadarEstimate.shown(entry, now: t0.addingTimeInterval(45 + 45))
        XCTAssertEqual(done.coordinate.latitude, 47.45, accuracy: 1e-9)
        XCTAssertFalse(done.isEstimate)
    }

    func testLagStaysBetweenTwentyAndOneTwentySeconds() throws {
        var store = RadarFrameStore()
        store.merge([vehicle("a", lat: 47.0)], at: t0)
        store.merge([vehicle("a", lat: 47.1)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(RadarEstimate.lag(of: try XCTUnwrap(store.entries["a"])), RadarEstimate.displayLag, "two tiles answering a trip within seconds")
        store.merge([vehicle("a", lat: 47.2)], at: t0.addingTimeInterval(600))
        XCTAssertEqual(RadarEstimate.lag(of: try XCTUnwrap(store.entries["a"])), RadarEstimate.maxLag)
        store.merge([vehicle("b")], at: t0)
        XCTAssertEqual(RadarEstimate.lag(of: try XCTUnwrap(store.entries["b"])), RadarEstimate.displayLag, "one answer: the default")
    }

    // MARK: Clusters stay bounded

    /// 3000 synthetic vehicles spread over Austria like the real corridors, deterministic.
    private func synthetic(_ count: Int) -> [RadarPoint] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        return (0..<count).map { index in
            RadarPoint(tripID: "t\(index)",
                       coordinate: GeoPoint(latitude: 46.4 + next() * 2.6, longitude: 9.6 + next() * 7.5),
                       delay: index % 9 == 0 ? .late : .onTime)
        }
    }

    func testThreeThousandVehiclesNeverMakeMoreMarkersThanTheGridHasCells() {
        let points = synthetic(3000)
        for span in [4.2, 2.0, 1.0, 0.5, 0.2, 0.05] {
            let cell = RadarClustering.cellSize(forLatitudeSpan: span)
            // The visible box of a phone held upright, centred in Austria.
            let box = RadarBox(north: 47.9 + span / 2, west: 13.3 - span * 0.35, south: 47.9 - span / 2, east: 13.3 + span * 0.35)
            let inView = points.filter { box.contains($0.coordinate) }
            let clusters = RadarClustering.group(inView, cellDegrees: cell)
            let rows = Int((box.north - box.south) / cell) + 2
            let columns = Int((box.east - box.west) / cell) + 2
            XCTAssertLessThanOrEqual(clusters.count, rows * columns, "span \(span): one marker per grid cell at most")
            XCTAssertLessThanOrEqual(clusters.count, 100, "span \(span): the map never draws more than 100 markers")
            XCTAssertEqual(clusters.reduce(0) { $0 + $1.count }, inView.count, "span \(span): no vehicle gets lost")
        }
    }

    func testThreeThousandVehiclesOnAPhoneScreenStayUnder130Markers() {
        let points = synthetic(3000)
        for span in [13.0, 4.2, 2.0, 1.0, 0.5, 0.2, 0.05] {
            let lonSpan = span * 0.69   // upright phone at 48 degrees north
            let cell = RadarClustering.cellSize(latitudeSpan: span, longitudeSpan: lonSpan, widthPoints: 393, heightPoints: 852)
            let box = RadarBox(north: 47.9 + span / 2, west: 13.3 - lonSpan / 2, south: 47.9 - span / 2, east: 13.3 + lonSpan / 2).clamped
            let inView = points.filter { box.contains($0.coordinate) }
            let clusters = RadarClustering.group(inView, cellDegrees: cell)
            XCTAssertLessThanOrEqual(clusters.count, 130, "span \(span): \(clusters.count) markers for \(inView.count) vehicles")
            XCTAssertEqual(clusters.reduce(0) { $0 + $1.count }, inView.count, "span \(span): no vehicle gets lost")
        }
    }

    func testGridFollowsTheScreenSoAnUprightPhoneStillShowsTheCountryAsManyBubbles() {
        // iPhone held upright: 393 x 852 pt. The Austria zoom shows about 9 degrees of longitude and 13 of latitude.
        let cell = RadarClustering.cellSize(latitudeSpan: 13, longitudeSpan: 9, widthPoints: 393, heightPoints: 852)
        XCTAssertEqual(cell, 56 * 9 / 393, accuracy: 1e-9, "one marker (56 pt) wide, in degrees")
        XCTAssertLessThan(cell, RadarClustering.cellSize(forLatitudeSpan: 13) / 1.4, "finer than the latitude rule, which makes 1.9 degrees")
        let box = RadarBox.austria
        let clusters = RadarClustering.group(synthetic(1500).filter { box.contains($0.coordinate) }, cellDegrees: cell)
        XCTAssertGreaterThan(clusters.count, 18, "the country is more than a handful of bubbles: \(clusters.count)")
        XCTAssertLessThan(clusters.count, 80)
        // Without a screen size the old rule stays.
        XCTAssertEqual(RadarClustering.cellSize(latitudeSpan: 4.2, longitudeSpan: 9, widthPoints: 0, heightPoints: 0),
                       RadarClustering.cellSize(forLatitudeSpan: 4.2))
        XCTAssertEqual(RadarClustering.cellSize(latitudeSpan: 4.2, longitudeSpan: .nan, widthPoints: 393, heightPoints: 852),
                       RadarClustering.cellSize(forLatitudeSpan: 4.2))
    }

    func testAScreenNeverGetsMoreThanAbout150Cells() {
        for (width, height) in [(393.0, 852.0), (430.0, 932.0), (1024.0, 1366.0), (1366.0, 1024.0), (320.0, 568.0)] {
            let lonSpan = 2.0
            let cell = RadarClustering.cellSize(latitudeSpan: 2.0 * height / width, longitudeSpan: lonSpan, widthPoints: width, heightPoints: height)
            let latSpan = lonSpan * height / width
            let cells = (lonSpan / cell + 1).rounded(.up) * (latSpan / cell + 1).rounded(.up)
            XCTAssertLessThanOrEqual(cells, 200, "\(width) x \(height): \(cells) cells at most, edge cells included")
        }
    }

    func testAustriaViewDrawsClustersWithCountsAndZoomingInDissolvesThem() {
        let points = synthetic(3000)
        let wide = RadarClustering.group(points, cellDegrees: RadarClustering.cellSize(forLatitudeSpan: 4.2))
        XCTAssertLessThan(wide.count, 150, "3000 vehicles become well under 150 markers at country zoom")
        XCTAssertGreaterThan(wide.filter { !$0.isSingle }.count, wide.count / 2, "most markers are clusters with a count")
        XCTAssertEqual(wide.reduce(0) { $0 + $1.count }, 3000)

        let box = RadarBox(north: 48.2, west: 13.0, south: 47.6, east: 13.8)
        let inView = points.filter { box.contains($0.coordinate) }
        let close = RadarClustering.group(inView, cellDegrees: RadarClustering.cellSize(forLatitudeSpan: 0.6))
        let closer = RadarClustering.group(inView, cellDegrees: RadarClustering.cellSize(forLatitudeSpan: 0.06))
        XCTAssertGreaterThan(closer.filter(\.isSingle).count, close.filter(\.isSingle).count, "zooming in turns clusters into single trains")
        XCTAssertEqual(closer.reduce(0) { $0 + $1.count }, inView.count)
    }

    func testGroupingThreeThousandVehiclesIsFastEnoughForOnceASecond() {
        let points = synthetic(3000)
        let cell = RadarClustering.cellSize(forLatitudeSpan: 4.2)
        measure { _ = RadarClustering.group(points, cellDegrees: cell) }
    }
}
