import XCTest
@testable import KlimaCore

/// Totals, the split entered / departure-arrival / estimated, the car comparison, delays, weeks, modes, longest trip.
final class TimeBalanceCalculatorTests: XCTestCase {
    typealias F = TimeBalanceFixtures
    let model = TravelTimeModel.standard
    let start = TimeBalanceFixtures.vienna(2026, 3, 1)
    let end = TimeBalanceFixtures.vienna(2027, 2, 28, 23, 59, 59)
    let now = TimeBalanceFixtures.vienna(2026, 11, 13, 12)

    // MARK: Totals and split

    func testTotalsSplitBySourceAndRoundTripsCountTwice() {
        let trips = [
            F.trip(F.vienna(2026, 5, 4, 7), km: 101, roundTrip: true, duration: 75),                       // 150 entered
            F.trip(F.vienna(2026, 5, 5, 7), km: 101, arrival: F.vienna(2026, 5, 5, 8, 12)),                // 72 timetable
            F.trip(F.vienna(2026, 5, 6, 7), mode: .bus, km: 19),                                           // estimated
        ]
        let balance = F.compute(trips, from: start, to: end, now: now)
        XCTAssertEqual(balance.enteredMinutes, 150, accuracy: 1e-9)
        XCTAssertEqual(balance.timetableMinutes, 72, accuracy: 1e-9)
        XCTAssertEqual(balance.estimatedMinutes, model.minutes(.bus, km: 19), accuracy: 1e-9)
        XCTAssertEqual(balance.totalMinutes, 222 + model.minutes(.bus, km: 19), accuracy: 1e-9)
        XCTAssertEqual(balance.recordedMinutes, 222, accuracy: 1e-9)
        XCTAssertEqual(balance.tripCount, 3)
        XCTAssertEqual(balance.rideCount, 4)
        XCTAssertEqual(balance.estimatedTripCount, 1)
        XCTAssertEqual(balance.recordedShare, 222 / balance.totalMinutes, accuracy: 1e-9)
    }

    /// Acceptance: a trip without any duration data still counts – as estimated.
    func testTripWithoutAnyDurationDataCountsAsEstimated() {
        let balance = F.compute([F.trip(F.vienna(2026, 6, 1, 9), km: 41)], from: start, to: end, now: now)
        XCTAssertEqual(balance.rideCount, 1)
        XCTAssertEqual(balance.estimatedTripCount, 1)
        XCTAssertEqual(balance.recordedMinutes, 0)
        XCTAssertGreaterThan(balance.estimatedMinutes, 0)
        XCTAssertEqual(balance.totalMinutes, balance.estimatedMinutes)
    }

    func testOnlyTripsInsideThePeriodAndUpToNowCount() {
        let trips = [
            F.trip(F.vienna(2026, 2, 28, 18), duration: 60),          // before the period
            F.trip(start, duration: 30),                               // exactly at the start (midnight: entered still counts)
            F.trip(F.vienna(2026, 11, 13, 11), duration: 20),          // today, before now
            F.trip(F.vienna(2026, 11, 13, 18), duration: 45),          // later today: not yet
        ]
        let balance = F.compute(trips, from: start, to: end, now: now)
        XCTAssertEqual(balance.totalMinutes, 50, accuracy: 1e-9)
        XCTAssertEqual(balance.tripCount, 2)
    }

    func testEmptyPeriod() {
        let balance = F.compute([], from: start, to: end, now: now)
        XCTAssertTrue(balance.isEmpty)
        XCTAssertEqual(balance.totalMinutes, 0)
        XCTAssertEqual(balance.carVerdict, .unavailable)
        XCTAssertNil(balance.delays)
        XCTAssertNil(balance.longest)
        XCTAssertTrue(balance.modes.isEmpty)
        XCTAssertEqual(balance.weeks.count, 12)
        XCTAssertTrue(balance.weeks.allSatisfy { $0.minutes == 0 })
    }

    // MARK: Car (acceptance: the same figure as the Auto-Vergleich)

    func testCarMinutesEqualTheAutoVergleichForTheTicketYear() {
        var trips: [TimeTripInput] = []
        let journey = UUID()
        for day in 0..<200 {
            let date = Calendar.vienna.date(byAdding: .hour, value: day * 37 + 7, to: F.vienna(2026, 2, 20))!
            let mode = TransportMode.allCases[day % TransportMode.allCases.count]
            trips.append(F.trip(date, mode: mode, km: Double((day * 13) % 140) + 0.5, roundTrip: day % 3 == 0))
        }
        trips.append(F.trip(F.vienna(2026, 8, 1, 8), km: 189, journey: journey, leg: 0))
        trips.append(F.trip(F.vienna(2026, 8, 1, 8), mode: .bus, km: 19, journey: journey, leg: 1))
        for profile in [CarProfile(), CarProfile(roadDistanceFactor: 1.3), CarProfile(mode: .fuelOnly, roadDistanceFactor: 1)] {
            let ticket = TicketPeriod(productID: "oe-klassik", name: "Ö", price: 1400, start: start, end: end)
            let auto = CarComparison.compare(ticket: ticket, trips: trips.map(F.record), profile: profile, now: now)
            let balance = F.compute(trips, from: start, to: end, now: now, profile: profile)
            XCTAssertEqual(balance.carMinutes, auto.drivingHours * 60, accuracy: 1e-6)
            XCTAssertGreaterThan(balance.carMinutes, 0)
        }
    }

    func testCarMinutesPerTripAreThePerTripTermOfTheAutoVergleich() {
        let trip = F.trip(F.vienna(2026, 5, 4, 7), km: 101, roundTrip: true)
        // 101 km × 1,15 = 116,15 road km per leg at 70 km/h = 1,659 h, two legs.
        XCTAssertEqual(TimeBalanceCalculator.carMinutes(trip, profile: CarProfile()), 2 * 116.15 / 70 * 60, accuracy: 1e-9)
    }

    // MARK: Wording

    func testVerdictForLongerEqualAndShorterTransitTime() {
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 600, carMinutes: 480), .transitLonger(extraMinutes: 120))
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 400, carMinutes: 480), .transitShorter(gainedMinutes: 80))
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 480, carMinutes: 480), .aboutEqual)
        // 5 % of 480 = 24 minutes either way is „about equal“, 25 is not.
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 504, carMinutes: 480), .aboutEqual)
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 456, carMinutes: 480), .aboutEqual)
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 505, carMinutes: 480), .transitLonger(extraMinutes: 25))
        // Small totals: at least 5 minutes.
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 24, carMinutes: 20), .aboutEqual)
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 26, carMinutes: 20), .transitLonger(extraMinutes: 6))
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: 30, carMinutes: 0), .unavailable)
        XCTAssertEqual(TimeBalanceCarVerdict.compare(transitMinutes: .nan, carMinutes: 20), .unavailable)
    }

    func testVerdictOfARealBalance() {
        // A slow city bus: 3 km take 10 minutes by bus (18 km/h) but 6,9 minutes by car (3,45 km at 30 km/h).
        let slow = F.compute([F.trip(F.vienna(2026, 5, 4, 7), mode: .bus, km: 3)], from: start, to: end, now: now)
        XCTAssertEqual(slow.carVerdict, .aboutEqual, "3,1 minutes apart: within 5 minutes")
        let many = (0..<20).map { F.trip(F.vienna(2026, 5, 4 + $0, 7), mode: .bus, km: 3) }
        guard case .transitLonger(let extra) = F.compute(many, from: start, to: end, now: now).carVerdict else {
            return XCTFail("20 slow bus rides take longer than driving")
        }
        XCTAssertEqual(extra, 20 * (10 - 3.45 / 30 * 60), accuracy: 1e-6)
        // The Railjet beats the Arlberg road: entered 72 minutes vs 116,15 km at 70 km/h = 99,6 minutes.
        let fast = F.compute([F.trip(F.vienna(2026, 5, 4, 7), km: 101, duration: 72)], from: start, to: end, now: now)
        guard case .transitShorter(let gained) = fast.carVerdict else { return XCTFail("the train is faster") }
        XCTAssertEqual(gained, 116.15 / 70 * 60 - 72, accuracy: 1e-6)
    }

    // MARK: Delays

    func testDelaySumIgnoresTripsWithoutARecordedDelay() {
        let trips = [
            F.trip(F.vienna(2026, 5, 4, 7), delay: 12, delaySource: .live),
            F.trip(F.vienna(2026, 5, 5, 7), delay: 8, delaySource: .manual),
            F.trip(F.vienna(2026, 5, 6, 7), delay: 0, delaySource: .live),       // recorded, punctual
            F.trip(F.vienna(2026, 5, 7, 7), delay: 30),                          // a value without a source is not recorded
            F.trip(F.vienna(2026, 5, 8, 7), delay: -4, delaySource: .manual),   // never negative
            F.trip(F.vienna(2026, 5, 9, 7)),
        ]
        let delays = F.compute(trips, from: start, to: end, now: now).delays
        XCTAssertEqual(delays?.totalMinutes, 20)
        XCTAssertEqual(delays?.recordedTrips, 4)
        XCTAssertEqual(delays?.delayedTrips, 2)
        XCTAssertEqual(delays?.longestMinutes, 12)
    }

    func testNoRecordedDelayMeansNoDelayRow() {
        let trips = [F.trip(F.vienna(2026, 5, 4, 7), delay: 25), F.trip(F.vienna(2026, 5, 5, 7))]
        XCTAssertNil(F.compute(trips, from: start, to: end, now: now).delays)
        XCTAssertNil(TripDelaySource(storedValue: ""))
        XCTAssertNil(TripDelaySource(storedValue: "radar"))
        XCTAssertEqual(TripDelaySource(storedValue: "live"), .live)
    }

    func testDelaysDoNotChangeTheRideTime() {
        let plain = F.compute([F.trip(F.vienna(2026, 5, 4, 7), duration: 60)], from: start, to: end, now: now)
        let late = F.compute([F.trip(F.vienna(2026, 5, 4, 7), duration: 60, delay: 15, delaySource: .live)], from: start, to: end, now: now)
        XCTAssertEqual(plain.totalMinutes, late.totalMinutes, "the delay row is shown on its own, not added")
    }

    // MARK: Weeks

    func testTwelveContiguousWeeksEndingWithTheReferenceWeek() {
        let balance = F.compute([], from: start, to: end, now: now)
        XCTAssertEqual(balance.weeks.count, 12)
        XCTAssertEqual(balance.weeks.last?.start, F.vienna(2026, 11, 9), "Monday of the week of Friday 13 Nov")
        XCTAssertEqual(balance.weeks.first?.start, F.vienna(2026, 8, 24))
        XCTAssertEqual(balance.weeks.filter(\.isCurrent).count, 1)
        XCTAssertTrue(balance.weeks.last?.isCurrent ?? false)
        for (a, b) in zip(balance.weeks, balance.weeks.dropFirst()) {
            XCTAssertEqual(a.end, b.start)
            XCTAssertEqual(Calendar.vienna.component(.weekday, from: b.start), 2, "weeks start on Monday")
        }
    }

    func testWeekEdgeIsMondayMidnightInVienna() {
        let sunday = F.trip(F.vienna(2026, 11, 8, 23, 59), duration: 10)
        let monday = F.trip(F.vienna(2026, 11, 9, 0, 0), duration: 20)
        let balance = F.compute([sunday, monday], from: start, to: end, now: now)
        let weeks = balance.weeks
        XCTAssertEqual(weeks[weeks.count - 2].minutes, 10)
        XCTAssertEqual(weeks[weeks.count - 1].minutes, 20)
    }

    /// Summer time starts on Sunday 29 March 2026 (that week has 167 hours) and ends on Sunday 25 October 2026 (169 hours).
    func testWeekEdgesAroundTheDSTChanges() {
        let spring = [F.trip(F.vienna(2026, 3, 29, 23, 30), duration: 10), F.trip(F.vienna(2026, 3, 30, 0, 15), duration: 20)]
        let springWeeks = F.compute(spring, from: start, to: end, now: F.vienna(2026, 4, 1, 12)).weeks
        let march23 = springWeeks.first { $0.start == F.vienna(2026, 3, 23) }
        let march30 = springWeeks.first { $0.start == F.vienna(2026, 3, 30) }
        XCTAssertEqual(march23?.minutes, 10)
        XCTAssertEqual(march30?.minutes, 20)
        XCTAssertEqual(march23.map { $0.end.timeIntervalSince($0.start) / 3600 }, 167)

        let autumn = [F.trip(F.vienna(2026, 10, 25, 23, 30), duration: 10), F.trip(F.vienna(2026, 10, 26, 0, 15), duration: 20),
                      F.trip(F.vienna(2026, 10, 19, 0, 0), duration: 5)]
        let autumnWeeks = F.compute(autumn, from: start, to: end, now: now).weeks
        let october19 = autumnWeeks.first { $0.start == F.vienna(2026, 10, 19) }
        let october26 = autumnWeeks.first { $0.start == F.vienna(2026, 10, 26) }
        XCTAssertEqual(october19?.minutes, 15)
        XCTAssertEqual(october26?.minutes, 20)
        XCTAssertEqual(october19.map { $0.end.timeIntervalSince($0.start) / 3600 }, 169)
    }

    func testWeeksBeforeThePeriodShowTripsButAreMarkedOutside() {
        let month = (F.vienna(2026, 11, 1), F.vienna(2026, 11, 30, 23, 59, 59))
        let trips = [F.trip(F.vienna(2026, 10, 20, 7), duration: 40), F.trip(F.vienna(2026, 11, 3, 7), duration: 30, arrival: nil)]
        let balance = F.compute(trips, from: month.0, to: month.1, now: now)
        XCTAssertEqual(balance.totalMinutes, 30, "totals: November only")
        let october19 = balance.weeks.first { $0.start == F.vienna(2026, 10, 19) }
        XCTAssertEqual(october19?.minutes, 40, "the chart keeps its context")
        XCTAssertEqual(october19?.isInRange, false)
        XCTAssertEqual(balance.weeks.first { $0.start == F.vienna(2026, 10, 26) }?.isInRange, true, "26 Oct – 2 Nov touches November")
    }

    func testWeeksSplitRecordedAndEstimated() {
        let trips = [F.trip(F.vienna(2026, 11, 10, 7), duration: 30), F.trip(F.vienna(2026, 11, 11, 7), km: 101)]
        let week = F.compute(trips, from: start, to: end, now: now).weeks.last
        XCTAssertEqual(week?.recordedMinutes, 30)
        XCTAssertEqual(week?.estimatedMinutes ?? 0, model.minutes(.train, km: 101), accuracy: 1e-9)
    }

    func testReferenceIsThePeriodEndForAPastPeriod() {
        let pastEnd = F.vienna(2026, 6, 30, 23, 59, 59)
        let balance = F.compute([], from: F.vienna(2026, 6, 1), to: pastEnd, now: now)
        XCTAssertEqual(balance.reference, pastEnd)
        XCTAssertEqual(balance.weeks.last?.start, F.vienna(2026, 6, 29))
        XCTAssertEqual(balance.weeksElapsed, 30.0 / 7, accuracy: 1e-9)
    }

    // MARK: Average, modes, longest

    func testAverageMinutesPerWeek() {
        let trips = [F.trip(F.vienna(2026, 11, 2, 7), duration: 70), F.trip(F.vienna(2026, 11, 9, 7), duration: 70)]
        let balance = F.compute(trips, from: F.vienna(2026, 11, 1), to: F.vienna(2026, 11, 30, 23, 59, 59), now: now)
        XCTAssertEqual(balance.weeksElapsed, 13.0 / 7, accuracy: 1e-9, "1–13 November")
        XCTAssertEqual(balance.averageMinutesPerWeek, 140 / (13.0 / 7), accuracy: 1e-9)
        let firstDays = F.compute(trips, from: F.vienna(2026, 11, 1), to: F.vienna(2026, 11, 30, 23, 59, 59),
                                  now: F.vienna(2026, 11, 2, 9))
        XCTAssertEqual(firstDays.weeksElapsed, 1, "at least one week")
        XCTAssertEqual(F.compute(trips, from: F.vienna(2026, 12, 1), to: F.vienna(2026, 12, 31), now: now).averageMinutesPerWeek, 0)
    }

    func testModeShareSumsToOneAndIsSortedByTime() {
        let trips = [F.trip(F.vienna(2026, 5, 4, 7), duration: 90), F.trip(F.vienna(2026, 5, 5, 7), mode: .bus, duration: 40),
                     F.trip(F.vienna(2026, 5, 6, 7), mode: .tram, roundTrip: true, duration: 15),
                     F.trip(F.vienna(2026, 5, 7, 7), mode: .metro, duration: 30)]
        let modes = F.compute(trips, from: start, to: end, now: now).modes
        XCTAssertEqual(modes.map(\.mode), [.train, .bus, .metro, .tram], "a tie keeps the order of the modes")
        XCTAssertEqual(modes.map(\.minutes), [90, 40, 30, 30])
        XCTAssertEqual(modes.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
    }

    func testLongestTripIsAJourneyOrOneDirection() {
        let journey = UUID()
        let trips = [
            F.trip(F.vienna(2026, 5, 4, 7), roundTrip: true, duration: 100, from: "St. Anton", to: "Innsbruck"),   // 100 one way
            F.trip(F.vienna(2026, 6, 6, 8), duration: 80, journey: journey, leg: 0, from: "Innsbruck", to: "Salzburg"),
            F.trip(F.vienna(2026, 6, 6, 8), mode: .bus, km: 19, duration: 45, journey: journey, leg: 1, from: "Salzburg", to: "St. Gilgen"),
        ]
        let balance = F.compute(trips, from: start, to: end, now: now)
        XCTAssertEqual(balance.tripCount, 2, "a journey is one trip")
        XCTAssertEqual(balance.rideCount, 4)
        XCTAssertEqual(balance.longest?.minutes, 125)
        XCTAssertEqual(balance.longest?.fromName, "Innsbruck")
        XCTAssertEqual(balance.longest?.toName, "St. Gilgen")
        XCTAssertEqual(balance.longest?.legCount, 2)
        XCTAssertEqual(balance.longest?.isEstimated, false)
    }

    func testLongestTripTieKeepsTheEarlierAndMarksEstimates() {
        let trips = [F.trip(F.vienna(2026, 5, 5, 7), km: 101, from: "B"), F.trip(F.vienna(2026, 5, 4, 7), km: 101, from: "A")]
        let longest = F.compute(trips, from: start, to: end, now: now).longest
        XCTAssertEqual(longest?.fromName, "A")
        XCTAssertEqual(longest?.isEstimated, true)
    }
}
