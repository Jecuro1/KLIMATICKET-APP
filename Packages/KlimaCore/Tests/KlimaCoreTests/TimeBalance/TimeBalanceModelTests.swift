import XCTest
@testable import KlimaCore

/// The speed model behind „geschätzt“: documented anchors, positive, never shorter for a longer ride.
final class TimeBalanceModelTests: XCTestCase {
    let model = TravelTimeModel.standard

    func testStandardModelIsMonotonicByConstruction() {
        XCTAssertTrue(model.isMonotonic)
        for mode in TransportMode.allCases {
            XCTAssertNotNil(model.anchors[mode], "\(mode) has its own anchors")
        }
    }

    /// One more kilometre never saves time – for every mode, in 100-metre steps up to 700 km.
    func testEstimateIsMonotonicAndPositiveInKm() {
        for mode in TransportMode.allCases {
            var previous = 0.0
            for step in 0...7000 {
                let km = Double(step) / 10
                let minutes = model.minutes(mode, km: km)
                XCTAssertGreaterThan(minutes, 0, "\(mode) \(km) km")
                XCTAssertGreaterThanOrEqual(minutes + 1e-9, previous, "\(mode) \(km) km")
                previous = minutes
            }
        }
    }

    func testEstimateOfMissingOrBrokenDistancesIsTheMinimum() {
        XCTAssertEqual(model.minutes(.train, km: 0), model.minimumMinutes)
        XCTAssertEqual(model.minutes(.train, km: -12), model.minimumMinutes)
        XCTAssertEqual(model.minutes(.bus, km: .nan), model.minimumMinutes)
        XCTAssertEqual(model.minutes(.bus, km: .infinity), model.minimumMinutes)
        XCTAssertEqual(model.minimumMinutes, 2)
    }

    /// The documented anchor points (docs/TIME_BALANCE.md §3) and interpolation between them, by hand.
    func testDocumentedSpeeds() {
        XCTAssertEqual(model.averageSpeedKmh(.train, km: 3), 30)
        XCTAssertEqual(model.averageSpeedKmh(.train, km: 20), 50)
        XCTAssertEqual(model.averageSpeedKmh(.train, km: 40), 60, accuracy: 1e-9)   // halfway 50 → 70
        XCTAssertEqual(model.averageSpeedKmh(.train, km: 300), 125)
        XCTAssertEqual(model.averageSpeedKmh(.train, km: 600), 125)
        XCTAssertEqual(model.averageSpeedKmh(.tram, km: 6), 15.5, accuracy: 1e-9)
        XCTAssertEqual(model.averageSpeedKmh(.cableCar, km: 1.8), 15)
        XCTAssertEqual(model.averageSpeedKmh(.other, km: 19), model.averageSpeedKmh(.bus, km: 19))
        // St. Anton → Innsbruck, 101 km: 70 + 41 × 25/90 = 81,39 km/h → 74,5 minutes (Railjet about 72, REX about 85).
        XCTAssertEqual(model.minutes(.train, km: 101), 101 / (70 + 41 * 25.0 / 90) * 60, accuracy: 1e-9)
        XCTAssertEqual(model.minutes(.train, km: 101), 74.46, accuracy: 0.01)
        // Wien Hbf → Praterstern by U-Bahn, 4,5 km: 25 + 2,5 × 7/8 = 27,19 km/h → 9,9 minutes.
        XCTAssertEqual(model.minutes(.metro, km: 4.5), 9.93, accuracy: 0.01)
    }

    func testSpeedIsContinuousAtTheAnchors() {
        for (mode, anchors) in model.anchors {
            for anchor in anchors {
                let below = model.averageSpeedKmh(mode, km: anchor.km - 1e-6)
                let above = model.averageSpeedKmh(mode, km: anchor.km + 1e-6)
                XCTAssertEqual(below, anchor.kmh, accuracy: 1e-3, "\(mode) at \(anchor.km) km")
                XCTAssertEqual(above, anchor.kmh, accuracy: 1e-3, "\(mode) at \(anchor.km) km")
            }
        }
    }

    func testRoundTripAndLegsOfAnEntry() {
        let date = TimeBalanceFixtures.vienna(2026, 5, 4, 7)
        let one = TimeBalanceFixtures.trip(date, km: 41)
        let round = TimeBalanceFixtures.trip(date, km: 41, roundTrip: true)
        XCTAssertEqual(model.minutes(of: round), 2 * model.minutes(of: one), accuracy: 1e-9)
    }

    /// A speed that rises faster than the distance would make longer rides shorter – the check catches it.
    func testMonotonicCheckRejectsASteepAnchorPair() {
        let broken = TravelTimeModel(anchors: [.train: [.init(km: 10, kmh: 20), .init(km: 20, kmh: 80)]], minimumMinutes: 2)
        XCTAssertFalse(broken.isMonotonic)
        XCTAssertGreaterThan(broken.minutes(.train, km: 10), broken.minutes(.train, km: 20), "10 km take 30 min, 20 km 15 min")
        let descending = TravelTimeModel(anchors: [.train: [.init(km: 20, kmh: 50), .init(km: 10, kmh: 40)]], minimumMinutes: 2)
        XCTAssertFalse(descending.isMonotonic)
    }
}
