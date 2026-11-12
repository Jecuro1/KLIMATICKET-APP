import XCTest
@testable import KlimaCore

/// The reference distances of the year story come from the coordinates of the bundled stations, never from a typed number.
final class ReferenceDistancesTests: XCTestCase {
    /// The bundled stations.json (App/Resources), read from the repository like the places tests read their fixtures.
    static let stations: StationIndex = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }   // file, YearReview, KlimaCoreTests, Tests, KlimaCore, Packages
        let data = try! Data(contentsOf: url.appendingPathComponent("App/Resources/stations.json"))
        return try! StationIndex(jsonData: data)
    }()

    var lookup: (String) -> Station? { { Self.stations.station(id: $0) } }

    func testEveryPairResolvesInTheBundledStationList() {
        for pair in ReferenceDistances.pairs {
            XCTAssertNotNil(Self.stations.station(id: pair.fromID), "\(pair.fromLabel): \(pair.fromID)")
            XCTAssertNotNil(Self.stations.station(id: pair.toID), "\(pair.toLabel): \(pair.toID)")
        }
    }

    func testLabelsMatchTheStationsTheyStandFor() {
        for pair in ReferenceDistances.pairs {
            XCTAssertTrue(Self.stations.station(id: pair.fromID)!.name.hasPrefix(pair.fromLabel), pair.fromLabel)
            XCTAssertTrue(Self.stations.station(id: pair.toID)!.name.hasPrefix(pair.toLabel), pair.toLabel)
        }
    }

    func testDistancesArePositiveAndSymmetric() throws {
        for pair in ReferenceDistances.pairs {
            let forward = try XCTUnwrap(ReferenceDistances.distanceKm(pair, stations: lookup), pair.fromLabel)
            let backward = try XCTUnwrap(ReferenceDistances.distanceKm(
                ReferenceDistances.Pair(fromID: pair.toID, toID: pair.fromID, fromLabel: pair.toLabel, toLabel: pair.fromLabel), stations: lookup))
            XCTAssertGreaterThan(forward, 50)
            XCTAssertLessThan(forward, 700, "Austria is not wider than that")
            XCTAssertEqual(forward, backward, accuracy: 1e-9)
        }
    }

    func testDistanceComesFromTheStationCoordinates() throws {
        let pair = ReferenceDistances.pairs.first { $0.fromLabel == "Bregenz" && $0.toLabel == "Wien" }!
        let from = try XCTUnwrap(Self.stations.station(id: pair.fromID))
        let to = try XCTUnwrap(Self.stations.station(id: pair.toID))
        let km = try XCTUnwrap(ReferenceDistances.distanceKm(pair, stations: lookup))
        XCTAssertEqual(km, from.location.distanceKm(to: to.location), accuracy: 1e-9)
        // Great circle, not rail: Bregenz–Wien is about 530 km as the crow flies.
        XCTAssertEqual(km, 530, accuracy: 25)
    }

    func testAMissingStationSkipsThePair() {
        XCTAssertNil(ReferenceDistances.distanceKm(ReferenceDistances.pairs[0], stations: { _ in nil }))
        XCTAssertNil(ReferenceDistances.compare(km: 1_000, stations: { _ in nil }))
    }

    func testCompareFollowsTheLongestPairNotLongerThanTheDistance() throws {
        let resolved = ReferenceDistances.pairs.compactMap { pair in
            ReferenceDistances.distanceKm(pair, stations: lookup).map { (pair, $0) }
        }.sorted { $0.1 < $1.1 }
        let longest = try XCTUnwrap(resolved.last)
        let shortest = try XCTUnwrap(resolved.first)

        // Far more than the longest: "N-mal Bregenz–Wien".
        let far = try XCTUnwrap(ReferenceDistances.compare(km: 4_812, stations: lookup))
        XCTAssertEqual(far.fromLabel, longest.0.fromLabel)
        XCTAssertEqual(far.toLabel, longest.0.toLabel)
        XCTAssertEqual(far.referenceKm, longest.1, accuracy: 1e-9)
        XCTAssertEqual(far.factor, 4_812 / longest.1, accuracy: 1e-9)
        XCTAssertGreaterThan(far.factor, 5)

        // Less than the shortest: a part of it.
        let near = try XCTUnwrap(ReferenceDistances.compare(km: shortest.1 / 2, stations: lookup))
        XCTAssertEqual(near.toLabel, shortest.0.toLabel)
        XCTAssertEqual(near.factor, 0.5, accuracy: 1e-9)

        // In between: the longest pair that fits.
        for (index, entry) in resolved.enumerated() {
            let km = entry.1 + 1
            let pick = try XCTUnwrap(ReferenceDistances.compare(km: km, stations: lookup))
            let expected = resolved.last { $0.1 <= km }!
            XCTAssertEqual(pick.referenceKm, expected.1, accuracy: 1e-9, "index \(index)")
            XCTAssertGreaterThanOrEqual(pick.factor, 1)
        }
    }

    func testNoComparisonWithoutDistance() {
        XCTAssertNil(ReferenceDistances.compare(km: 0, stations: lookup))
        XCTAssertNil(ReferenceDistances.compare(km: -5, stations: lookup))
        XCTAssertNil(ReferenceDistances.compare(km: .nan, stations: lookup))
        XCTAssertNil(ReferenceDistances.compare(km: .infinity, stations: lookup))
    }

    func testTheYearReviewCarriesTheReference() throws {
        let trips = [TripRecord(date: Date(), fromName: "A", toName: "B", mode: .train, distanceKm: 1_000, fareEUR: 50)]
        let now = Date()
        let period = YearReviewPeriods.calendarYear(Calendar.vienna.component(.year, from: now))
        let review = YearReview.make(trips: trips, tickets: [], car: nil, period: period, now: now, stations: lookup)
        let reference = try XCTUnwrap(review.distance?.reference)
        XCTAssertEqual(reference.factor, 1_000 / reference.referenceKm, accuracy: 1e-9)
    }
}
