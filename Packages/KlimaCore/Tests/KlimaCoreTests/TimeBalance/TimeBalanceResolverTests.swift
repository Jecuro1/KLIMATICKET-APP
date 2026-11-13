import XCTest
@testable import KlimaCore

/// Duration resolution: entered → departure/arrival → estimate, with the bounds of docs/TIME_BALANCE.md §2.
final class TimeBalanceResolverTests: XCTestCase {
    typealias F = TimeBalanceFixtures
    let departure = TimeBalanceFixtures.vienna(2026, 5, 4, 7, 12)

    private func resolve(_ trip: TimeTripInput) -> ResolvedTravelTime { TravelTimeResolver.resolve(trip) }

    // MARK: Priority

    func testEnteredDurationWinsOverArrivalAndEstimate() {
        let trip = F.trip(departure, km: 101, duration: 75, arrival: departure.addingTimeInterval(90 * 60))
        let time = resolve(trip)
        XCTAssertEqual(time.source, .entered)
        XCTAssertEqual(time.minutesPerDirection, 75)
    }

    func testArrivalWinsOverEstimate() {
        let time = resolve(F.trip(departure, km: 101, arrival: departure.addingTimeInterval(72 * 60)))
        XCTAssertEqual(time.source, .timetable)
        XCTAssertEqual(time.minutesPerDirection, 72, accuracy: 1e-9)
    }

    func testWithoutAnyDurationDataTheTripIsEstimated() {
        let trip = F.trip(departure, km: 101)
        let time = resolve(trip)
        XCTAssertEqual(time.source, .estimated)
        XCTAssertEqual(time.minutesPerDirection, TravelTimeModel.standard.minutes(.train, km: 101), accuracy: 1e-9)
        XCTAssertGreaterThan(time.minutes, 0)
    }

    // MARK: Bounds of an entered duration

    func testEnteredDurationBounds() {
        XCTAssertEqual(resolve(F.trip(departure, duration: 0)).source, .estimated, "0 = unknown")
        XCTAssertEqual(resolve(F.trip(departure, duration: -5)).source, .estimated)
        XCTAssertEqual(resolve(F.trip(departure, duration: 1)).source, .entered)
        XCTAssertEqual(resolve(F.trip(departure, duration: 1)).minutesPerDirection, 1)
        XCTAssertEqual(resolve(F.trip(departure, duration: 1440)).source, .entered)
        XCTAssertEqual(resolve(F.trip(departure, duration: 1441)).source, .estimated, "more than a day is not a ride time")
        // An out-of-range entry falls through to the arrival.
        let fallback = resolve(F.trip(departure, duration: 5000, arrival: departure.addingTimeInterval(40 * 60)))
        XCTAssertEqual(fallback.source, .timetable)
        XCTAssertEqual(fallback.minutesPerDirection, 40, accuracy: 1e-9)
    }

    // MARK: Bounds of arrival minus departure

    func testArrivalBounds() {
        func source(afterMinutes minutes: Double) -> TravelTimeSource {
            resolve(F.trip(departure, arrival: departure.addingTimeInterval(minutes * 60))).source
        }
        XCTAssertEqual(source(afterMinutes: 0), .estimated, "arrival = departure is no ride")
        XCTAssertEqual(source(afterMinutes: 0.5), .estimated)
        XCTAssertEqual(source(afterMinutes: 1), .timetable)
        XCTAssertEqual(source(afterMinutes: 1440), .timetable)
        XCTAssertEqual(source(afterMinutes: 1441), .estimated)
        XCTAssertEqual(source(afterMinutes: -30), .estimated, "an arrival before the departure (e.g. the date was moved) is ignored")
        XCTAssertEqual(resolve(F.trip(departure, arrival: departure.addingTimeInterval(1440 * 60))).minutesPerDirection, 1440, accuracy: 1e-9)
    }

    func testMidnightOnlyDateDoesNotUseTheArrival() {
        let midnight = F.vienna(2026, 5, 4)
        let trip = F.trip(midnight, km: 30, arrival: F.vienna(2026, 5, 4, 8, 30))
        XCTAssertFalse(TravelTimeResolver.hasTimeOfDay(midnight))
        XCTAssertEqual(resolve(trip).source, .estimated, "a date without a time says nothing about the departure")
        // One minute after midnight is a real departure (a night train).
        let night = F.trip(F.vienna(2026, 5, 4, 0, 1), km: 30, arrival: F.vienna(2026, 5, 4, 0, 46))
        XCTAssertTrue(TravelTimeResolver.hasTimeOfDay(night.date))
        XCTAssertEqual(resolve(night).source, .timetable)
        XCTAssertEqual(resolve(night).minutesPerDirection, 45, accuracy: 1e-9)
        // An entered duration does not need a time of day.
        XCTAssertEqual(resolve(F.trip(midnight, duration: 50)).source, .entered)
    }

    func testMidnightIsLocalNotUTC() {
        // 00:00 in Vienna is 22:00 or 23:00 UTC the day before: still a date without a time.
        XCTAssertFalse(TravelTimeResolver.hasTimeOfDay(F.vienna(2026, 7, 1)))
        XCTAssertFalse(TravelTimeResolver.hasTimeOfDay(F.vienna(2026, 1, 15)))
        XCTAssertTrue(TravelTimeResolver.hasTimeOfDay(F.vienna(2026, 7, 1, 2)))
    }

    // MARK: Round trips

    func testRoundTripCountsTwiceForEverySource() {
        let entered = resolve(F.trip(departure, roundTrip: true, duration: 30))
        XCTAssertEqual(entered.minutesPerDirection, 30)
        XCTAssertEqual(entered.minutes, 60)
        let timetable = resolve(F.trip(departure, roundTrip: true, arrival: departure.addingTimeInterval(45 * 60)))
        XCTAssertEqual(timetable.minutes, 90, accuracy: 1e-9)
        let one = resolve(F.trip(departure, km: 80)).minutes
        let both = resolve(F.trip(departure, km: 80, roundTrip: true)).minutes
        XCTAssertEqual(both, 2 * one, accuracy: 1e-9)
    }

    // MARK: Journeys

    /// A planner journey stores the journey's departure as every leg's date and each leg's own arrival: a later leg
    /// starts when the leg before it arrived, so the legs add up to first departure → last arrival.
    func testPlannerJourneyLegsStartAtThePreviousArrival() {
        let journey = UUID()
        let start = F.vienna(2026, 6, 6, 8, 0)
        let legs = [
            F.trip(start, km: 120, arrival: F.vienna(2026, 6, 6, 9, 0), journey: journey, leg: 0),
            F.trip(start, mode: .bus, km: 30, arrival: F.vienna(2026, 6, 6, 10, 30), journey: journey, leg: 1),
            F.trip(start, mode: .tram, km: 3, arrival: F.vienna(2026, 6, 6, 10, 50), journey: journey, leg: 2),
        ]
        let times = TravelTimeResolver.resolveAll(legs.reversed())
        XCTAssertEqual(times[legs[0].id]?.minutesPerDirection ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(times[legs[1].id]?.minutesPerDirection ?? 0, 90, accuracy: 1e-9, "includes the change at the first stop")
        XCTAssertEqual(times[legs[2].id]?.minutesPerDirection ?? 0, 20, accuracy: 1e-9)
        XCTAssertTrue(legs.allSatisfy { times[$0.id]?.source == .timetable })
        let total = legs.compactMap { times[$0.id]?.minutes }.reduce(0, +)
        XCTAssertEqual(total, 170, accuracy: 1e-9, "08:00 → 10:50")
    }

    func testJourneyLegWithoutThePreviousArrivalIsEstimated() {
        let journey = UUID()
        let start = F.vienna(2026, 6, 6, 8, 0)
        let first = F.trip(start, km: 120, journey: journey, leg: 0)
        let second = F.trip(start, mode: .bus, km: 30, arrival: F.vienna(2026, 6, 6, 10, 30), journey: journey, leg: 1)
        let times = TravelTimeResolver.resolveAll([first, second])
        XCTAssertEqual(times[first.id]?.source, .estimated)
        XCTAssertEqual(times[second.id]?.source, .estimated, "10:30 − 08:00 would count the first leg twice")
    }

    func testJourneyLegWithItsOwnLaterDepartureStartsThere() {
        let journey = UUID()
        let first = F.trip(F.vienna(2026, 6, 6, 8, 0), arrival: F.vienna(2026, 6, 6, 9, 0), journey: journey, leg: 0)
        let second = F.trip(F.vienna(2026, 6, 6, 9, 20), arrival: F.vienna(2026, 6, 6, 9, 50), journey: journey, leg: 1)
        let times = TravelTimeResolver.resolveAll([first, second])
        XCTAssertEqual(times[second.id]?.minutesPerDirection ?? 0, 30, accuracy: 1e-9)
    }

    func testJourneyEstimatesAddUpLegByLeg() {
        let journey = UUID()
        let start = F.vienna(2026, 6, 6, 8, 0)
        let legs = [F.trip(start, km: 189, journey: journey, leg: 0), F.trip(start, mode: .bus, km: 19, journey: journey, leg: 1),
                    F.trip(start, mode: .metro, km: 4.5, journey: journey, leg: 2)]
        let times = TravelTimeResolver.resolveAll(legs)
        let model = TravelTimeModel.standard
        let expected = model.minutes(.train, km: 189) + model.minutes(.bus, km: 19) + model.minutes(.metro, km: 4.5)
        XCTAssertEqual(legs.compactMap { times[$0.id]?.minutes }.reduce(0, +), expected, accuracy: 1e-9)
        XCTAssertEqual(times.count, 3)
        // The journey as one 212,5 km train ride would be faster: the legs are not merged.
        XCTAssertNotEqual(expected, model.minutes(.train, km: 212.5), accuracy: 1)
    }

    func testEnteredLegDurationsInAJourneyStayAsEntered() {
        let journey = UUID()
        let start = F.vienna(2026, 6, 6, 8, 0)
        let legs = [F.trip(start, duration: 50, journey: journey, leg: 0), F.trip(start, duration: 25, journey: journey, leg: 1)]
        let times = TravelTimeResolver.resolveAll(legs)
        XCTAssertEqual(times[legs[1].id]?.source, .entered)
        XCTAssertEqual(times[legs[1].id]?.minutes, 25)
    }

    // MARK: Duration wheel

    func testDurationWheelSnapsToFiveMinuteSteps() {
        XCTAssertEqual(DurationWheel.snapped(74.46), 75)
        XCTAssertEqual(DurationWheel.snapped(72.4), 70)
        XCTAssertEqual(DurationWheel.snapped(1), 5, "never 0: 0 means unknown")
        XCTAssertEqual(DurationWheel.snapped(5000), DurationWheel.maximumMinutes)
        XCTAssertEqual(DurationWheel.snapped(.nan), 5)
        XCTAssertEqual(DurationWheel.split(75).hours, 1)
        XCTAssertEqual(DurationWheel.split(75).minutes, 15)
        XCTAssertEqual(DurationWheel.join(hours: 1, minutes: 15), 75)
        XCTAssertEqual(DurationWheel.join(hours: 0, minutes: 0), 5)
        XCTAssertEqual(DurationWheel.join(hours: 23, minutes: 55), 1435)
        XCTAssertEqual(DurationWheel.minutes.count, 12)
        XCTAssertNotNil(TravelTimeResolver.enteredMinutes(DurationWheel.maximumMinutes), "every wheel value is a valid entry")
    }
}
