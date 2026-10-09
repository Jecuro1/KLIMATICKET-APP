import XCTest
@testable import KlimaCore

final class RideTrackingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    private func trip(fare: Double = 24.9, roundTrip: Bool = false, from: String = "St. Anton am Arlberg",
                      to: String = "Innsbruck Hauptbahnhof") -> RideTrip {
        RideTrip(fromName: from, toName: to, fromStationID: "at:47:1", toStationID: "at:47:2", mode: .train,
                 distanceKm: 101, fareEUR: fare, isRoundTrip: roundTrip, states: ["T"])
    }

    private func record(_ id: UUID = UUID(), activity: String? = nil, startedHoursAgo: Double = 1) -> RideRecord {
        RideRecord(id: id, activityID: activity, trip: trip(), startedAt: t0.addingTimeInterval(-startedHoursAgo * 3600),
                   ticketName: "KlimaTicket Ö Klassik")
    }

    // MARK: Trip payload

    func testTripValueDoublesForRoundTrip() {
        XCTAssertEqual(trip(fare: 24.9).totalValue, 24.9, accuracy: 0.0001)
        XCTAssertEqual(trip(fare: 24.9, roundTrip: true).totalValue, 49.8, accuracy: 0.0001)
        XCTAssertEqual(trip(roundTrip: true).totalDistanceKm, 202, accuracy: 0.0001)
    }

    func testTripValueIgnoresInvalidFares() {
        XCTAssertEqual(trip(fare: -3).totalValue, 0)
        XCTAssertEqual(trip(fare: .nan).totalValue, 0)
        XCTAssertFalse(trip(fare: 0).isValid)
    }

    func testTripValidityNeedsTwoDifferentEndpoints() {
        XCTAssertTrue(trip().isValid)
        XCTAssertFalse(trip(from: "  ").isValid)
        XCTAssertFalse(trip(from: "Landeck-Zams", to: "Landeck-Zams").isValid)
    }

    func testTripCodableRoundTrip() throws {
        var original = trip(roundTrip: true)
        original.category = .commute
        original.isInduced = true
        original.favoriteID = UUID()
        original.travelClass = .first
        original.note = "Mit Rad"
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(RideTrip.self, from: data), original)
    }

    func testTripDecodingToleratesMissingAndUnknownValues() throws {
        let json = #"{"fromName":"Wien Hbf","toName":"Linz Hbf","mode":"hyperloop","fareEUR":38.2,"category":"space"}"#
        let decoded = try JSONDecoder().decode(RideTrip.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fromName, "Wien Hbf")
        XCTAssertEqual(decoded.mode, .other)
        XCTAssertNil(decoded.category)
        XCTAssertEqual(decoded.travelClass, .second)
        XCTAssertFalse(decoded.isRoundTrip)
        XCTAssertEqual(decoded.totalValue, 38.2, accuracy: 0.0001)
    }

    // MARK: Payoff

    func testPayoffBeforeAndAfter() throws {
        let p = try XCTUnwrap(RidePayoff(currentValue: 1_022, ticketPrice: 1_400, rideValue: 49.8))
        XCTAssertEqual(p.before, 0.73, accuracy: 0.0001)
        XCTAssertEqual(p.after, 0.7656, accuracy: 0.0001)
        XCTAssertEqual(p.percentBefore, 73)
        XCTAssertEqual(p.percentAfter, 77)
        XCTAssertEqual(p.delta, 0.0356, accuracy: 0.0001)
        XCTAssertFalse(p.reachesSummit)
        XCTAssertFalse(p.needsDecimals)
        XCTAssertEqual(p.remainingAfter, 1_400 - 1_071.8, accuracy: 0.001)
    }

    func testPayoffWithoutPriceIsNil() {
        XCTAssertNil(RidePayoff(currentValue: 100, ticketPrice: 0, rideValue: 10))
        XCTAssertNil(RidePayoff(currentValue: 100, ticketPrice: .infinity, rideValue: 10))
    }

    func testPayoffCrossingTheSummit() throws {
        let p = try XCTUnwrap(RidePayoff(currentValue: 1_380, ticketPrice: 1_400, rideValue: 49.8))
        XCTAssertTrue(p.reachesSummit)
        XCTAssertFalse(p.isPaidOffBefore)
        XCTAssertTrue(p.isPaidOffAfter)
        XCTAssertEqual(p.profitAfter, 29.8, accuracy: 0.001)
        XCTAssertEqual(p.remainingAfter, 0)
    }

    func testPayoffAlreadyPaidOff() throws {
        let p = try XCTUnwrap(RidePayoff(currentValue: 1_600, ticketPrice: 1_400, rideValue: 20))
        XCTAssertTrue(p.isPaidOffBefore)
        XCTAssertFalse(p.reachesSummit)
        XCTAssertEqual(p.percentAfter, 116)
    }

    func testPercentNeverShows100BeforeTheSummit() {
        XCTAssertEqual(RidePayoff.percent(0.996), 99)
        XCTAssertEqual(RidePayoff.percent(1.0), 100)
        XCTAssertEqual(RidePayoff.percent(-0.2), 0)
        XCTAssertEqual(RidePayoff.percent(.nan), 0)
    }

    func testSmallGainNeedsDecimals() throws {
        let p = try XCTUnwrap(RidePayoff(currentValue: 1_022, ticketPrice: 1_400, rideValue: 2.4))
        XCTAssertEqual(p.percentBefore, p.percentAfter)
        XCTAssertTrue(p.needsDecimals)
        let none = try XCTUnwrap(RidePayoff(currentValue: 1_022, ticketPrice: 1_400, rideValue: 0))
        XCTAssertFalse(none.needsDecimals)
    }

    func testPayoffSanitisesInput() {
        let p = RidePayoff(before: 0.8, after: 0.5, ticketPrice: -10)
        XCTAssertEqual(p.after, 0.8, "after never drops below before")
        XCTAssertEqual(p.ticketPrice, 0)
    }

    func testPayoffRebasesOnNewTotal() throws {
        let p = try XCTUnwrap(RidePayoff(currentValue: 700, ticketPrice: 1_400, rideValue: 70))
        let rebased = p.rebased(currentValue: 770, rideValue: 70)
        XCTAssertEqual(rebased.before, 0.55, accuracy: 0.0001)
        XCTAssertEqual(rebased.after, 0.60, accuracy: 0.0001)
    }

    // MARK: Policy

    func testEightHourLimit() {
        XCTAssertEqual(RidePolicy.staleDate(for: t0).timeIntervalSince(t0), 8 * 3600)
        XCTAssertFalse(RidePolicy.isOverdue(startedAt: t0, now: t0.addingTimeInterval(7.9 * 3600)))
        XCTAssertTrue(RidePolicy.isOverdue(startedAt: t0, now: t0.addingTimeInterval(8 * 3600)))
    }

    // MARK: Reconciler

    func testRunningRideIsKept() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A")],
                                       activities: [.init(activityID: "A", rideID: id, status: .active)], now: t0)
        XCTAssertEqual(plan, RideReconciler.Plan(running: [id]))
    }

    func testStaleButYoungRideKeepsRunning() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A", startedHoursAgo: 2)],
                                       activities: [.init(activityID: "A", rideID: id, status: .stale)], now: t0)
        XCTAssertEqual(plan.running, [id])
    }

    func testOverdueRideIsEndedAndNeedsDecision() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A", startedHoursAgo: 9)],
                                       activities: [.init(activityID: "A", rideID: id, status: .active)], now: t0)
        XCTAssertEqual(plan.endActivityIDs, ["A"])
        XCTAssertEqual(plan.needsDecision, [id])
        XCTAssertTrue(plan.running.isEmpty)
    }

    func testSwipedAwayRideNeedsDecision() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A")], activities: [], now: t0)
        XCTAssertEqual(plan.needsDecision, [id])
        XCTAssertTrue(plan.endActivityIDs.isEmpty)
    }

    func testRideEndedBySystemIsClearedAndNeedsDecision() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A")],
                                       activities: [.init(activityID: "A", rideID: id, status: .ended)], now: t0)
        XCTAssertEqual(plan.endActivityIDs, ["A"])
        XCTAssertEqual(plan.needsDecision, [id])
    }

    func testMatchesByActivityIDWhenRideIDIsUnknown() {
        let id = UUID()
        let plan = RideReconciler.plan(records: [record(id, activity: "A")],
                                       activities: [.init(activityID: "A", rideID: nil, status: .active)], now: t0)
        XCTAssertEqual(plan.running, [id])
        XCTAssertTrue(plan.endActivityIDs.isEmpty)
    }

    func testOrphanActivitiesAreEndedButSavedConfirmationsStay() {
        let plan = RideReconciler.plan(records: [],
                                       activities: [.init(activityID: "orphan", rideID: UUID(), status: .active),
                                                    .init(activityID: "saved", rideID: UUID(), status: .ended),
                                                    .init(activityID: "pending", rideID: nil, status: .pending)],
                                       now: t0)
        XCTAssertEqual(plan.endActivityIDs, ["orphan", "pending"])
        XCTAssertTrue(plan.needsDecision.isEmpty)
    }

    func testDecisionsAreOldestFirst() {
        let older = UUID(), newer = UUID()
        let plan = RideReconciler.plan(records: [record(newer, startedHoursAgo: 1), record(older, startedHoursAgo: 3)],
                                       activities: [], now: t0)
        XCTAssertEqual(plan.needsDecision, [older, newer])
    }

    // MARK: Climb

    func testClimbIsDownSampledAndKeepsEndpoints() {
        let values = (0...100).map { Double($0) * 10 }   // 0 … 1000
        let climb = RideClimb.fractions(cumulative: values, ticketPrice: 1_000, maxPoints: 12)
        XCTAssertEqual(climb.count, 12)
        XCTAssertEqual(climb.first, 0)
        XCTAssertEqual(climb.last, 1)
        XCTAssertEqual(climb, climb.sorted(), "a cumulative series stays monotonic")
    }

    func testClimbShortSeriesAndInvalidInput() {
        XCTAssertEqual(RideClimb.fractions(cumulative: [0, 350, 700], ticketPrice: 1_400), [0, 0.25, 0.5])
        XCTAssertEqual(RideClimb.fractions(cumulative: [10, .nan], ticketPrice: 100), [0.1, 0])
        XCTAssertTrue(RideClimb.fractions(cumulative: [1, 2], ticketPrice: 0).isEmpty)
    }

    // MARK: Names

    func testShortNames() {
        XCTAssertEqual(RideNames.short("Innsbruck Hauptbahnhof"), "Innsbruck Hbf")
        XCTAssertEqual(RideNames.short("St. Anton am Arlberg"), "St. Anton")
        XCTAssertEqual(RideNames.route(from: "St. Anton am Arlberg", to: "Innsbruck Hbf", roundTrip: false), "St. Anton → Innsbruck Hbf")
        XCTAssertEqual(RideNames.route(from: "Bludenz", to: "Feldkirch", roundTrip: true), "Bludenz ⇄ Feldkirch")
    }

    // MARK: Phase decoding

    func testUnknownPhaseDecodesAsRiding() throws {
        let decoded = try JSONDecoder().decode([RidePhase].self, from: Data(#"["saved","teleported"]"#.utf8))
        XCTAssertEqual(decoded, [.saved, .riding])
        XCTAssertTrue(RidePhase.saved.isFinal)
        XCTAssertFalse(RidePhase.arrived.isFinal)
    }
}
