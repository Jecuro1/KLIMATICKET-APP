import XCTest
@testable import KlimaCore

/// Meine Routen: ordering, the route line, the CO₂ figure and the next cached connection.
final class SavedRoutesTests: XCTestCase {
    func testMovingToTheEnd() {
        XCTAssertEqual(SavedRoutes.moved(["a", "b", "c"], from: IndexSet(integer: 0), to: 3), ["b", "c", "a"])
    }

    func testMovingToTheFront() {
        XCTAssertEqual(SavedRoutes.moved(["a", "b", "c"], from: IndexSet(integer: 2), to: 0), ["c", "a", "b"])
    }

    func testMovingIntoTheMiddleCountsTheOriginalIndexes() {
        XCTAssertEqual(SavedRoutes.moved(["a", "b", "c"], from: IndexSet(integer: 2), to: 1), ["a", "c", "b"])
    }

    func testMovingSeveralItemsKeepsTheirOrder() {
        XCTAssertEqual(SavedRoutes.moved(["a", "b", "c"], from: IndexSet([0, 1]), to: 3), ["c", "a", "b"])
    }

    func testMovingWithoutValidIndexesChangesNothing() {
        XCTAssertEqual(SavedRoutes.moved(["a", "b"], from: IndexSet(integer: 5), to: 0), ["a", "b"])
        XCTAssertEqual(SavedRoutes.moved(["a", "b"], from: IndexSet(), to: 0), ["a", "b"])
    }

    func testRouteLineDropsEmptyNames() {
        XCTAssertEqual(SavedRoutes.routeLine(from: "St. Anton", via: ["Lech", "  "], to: "Innsbruck"), "St. Anton → Lech → Innsbruck")
        XCTAssertEqual(SavedRoutes.routeLine(from: "Bludenz", to: ""), "Bludenz")
    }

    func testCO2UsesTheEmissionFactorsPerPassengerKilometre() {
        XCTAssertEqual(SavedRoutes.co2Kg(distanceKm: 100, mode: .train), 0.72, accuracy: 1e-9)
        XCTAssertEqual(SavedRoutes.co2Kg(distanceKm: 100, mode: .bus), 5.07, accuracy: 1e-9)
        XCTAssertEqual(SavedRoutes.co2Kg(distanceKm: -4, mode: .train), 0)
    }

    func testNextConnectionIsTheEarliestUpcomingDeparture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func connection(_ id: String, planned: TimeInterval, realtime: TimeInterval? = nil) -> WidgetConnection {
            WidgetConnection(id: id, planned: now.addingTimeInterval(planned),
                             realtime: realtime.map { now.addingTimeInterval($0) }, fromName: "A", toName: "B",
                             lineName: "RJ 66", modeSymbol: "tram.fill")
        }
        let cached = [
            connection("late", planned: 1_200),
            connection("delayed", planned: -600, realtime: 300),   // departs in 5 min after the delay
            connection("gone", planned: -3_600),                    // long gone
        ]
        XCTAssertEqual(SavedRoutes.nextConnection(in: cached, now: now)?.id, "delayed")
    }

    func testNextConnectionIsNilWhenTheCacheIsEmptyOrOnlyPast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(SavedRoutes.nextConnection(in: [], now: now))
        let past = WidgetConnection(id: "p", planned: now.addingTimeInterval(-3_600), fromName: "A", toName: "B",
                                    lineName: "RJ", modeSymbol: "tram.fill")
        XCTAssertNil(SavedRoutes.nextConnection(in: [past], now: now))
    }
}
