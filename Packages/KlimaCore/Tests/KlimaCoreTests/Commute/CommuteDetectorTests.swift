import XCTest
@testable import KlimaCore

/// Pendel-Modus: the commute guess from logged trips – positives, the negatives that must stay silent, ties and clock times.
final class CommuteDetectorTests: XCTestCase {
    private typealias F = CommuteFixtures
    private let now = CommuteFixtures.at(2026, 11, 6, 12, 0)   // Friday

    // MARK: Positive

    func testWeekdayCommuteIsAConfidentGuessWithTimes() throws {
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: F.commuteWeeks(4), now: now))
        XCTAssertEqual(guess.confidence, .high)
        XCTAssertEqual(guess.origin.name, "Linz Hbf")
        XCTAssertEqual(guess.destination.name, "Wien Hbf")
        XCTAssertEqual(guess.rides, 24)
        XCTAssertEqual(guess.weeks, 4)
        XCTAssertEqual(guess.weekdays, [.monday, .tuesday, .thursday])
        XCTAssertEqual(guess.outboundMinute, 7 * 60 + 20)
        XCTAssertEqual(guess.returnMinute, 17 * 60 + 10)
        XCTAssertFalse(guess.mostlyRoundTrips)
    }

    func testTheMorningDirectionDecidesTheOrigin() throws {
        // Lives in Wien, works in Linz: the morning rides start in Wien.
        let trips = F.commuteWeeks(4, from: F.wien, to: F.linz)
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertEqual(guess.origin, F.wien)
        XCTAssertEqual(guess.destination, F.linz)
    }

    func testExactlyTheThresholdQualifies() throws {
        // 6 rides on 3 weeks and 2 weekdays (Mon out, Tue back).
        var trips: [TripRecord] = []
        let mondays = [F.at(2026, 11, 2, 7, 0), F.at(2026, 10, 26, 7, 0), F.at(2026, 10, 19, 7, 0)]
        let tuesdays = [F.at(2026, 11, 3, 17, 0), F.at(2026, 10, 27, 17, 0), F.at(2026, 10, 20, 17, 0)]
        trips += mondays.map { F.trip(F.linz, F.wien, $0) }
        trips += tuesdays.map { F.trip(F.wien, F.linz, $0) }
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertEqual(guess.rides, 6)
        XCTAssertEqual(guess.confidence, .high)
    }

    func testRoundTripsCountTwiceAndSayWhereHomeIs() throws {
        // „Hin und retour“ from Wien on Mon/Wed for 3 weeks, logged at 20:00 (capture time, not a departure).
        let days = [F.at(2026, 11, 2, 20, 0), F.at(2026, 11, 4, 20, 0), F.at(2026, 10, 26, 20, 0),
                    F.at(2026, 10, 28, 20, 0), F.at(2026, 10, 19, 20, 0), F.at(2026, 10, 21, 20, 0)]
        let trips = days.map { F.trip(F.wien, F.stPoelten, $0, roundTrip: true) }
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertEqual(guess.rides, 12)
        XCTAssertTrue(guess.mostlyRoundTrips)
        XCTAssertEqual(guess.origin, F.wien)
        XCTAssertNil(guess.outboundMinute, "one direction only says nothing about clock times")
        XCTAssertNil(guess.returnMinute)
    }

    /// The invitation and the suggestion rows say „N Fahrten“: the same number Statistik shows for the same trips (a round trip
    /// and a journey with legs are one trip each), not the rides of the qualifying rule.
    func testShownTripCountMatchesStatistik() throws {
        var trips: [TripRecord] = []
        let roundTripDays = [F.at(2026, 11, 2, 7, 0), F.at(2026, 10, 26, 7, 0), F.at(2026, 10, 19, 7, 0)]
        trips += roundTripDays.map { F.trip(F.linz, F.wien, $0, roundTrip: true) }
        for day in [F.at(2026, 11, 3, 7, 0), F.at(2026, 10, 27, 7, 0)] {
            let journey = UUID()
            trips.append(F.trip(F.linz, F.stPoelten, day, journey: journey, leg: 0))
            trips.append(F.trip(F.stPoelten, F.wien, day.addingTimeInterval(3600), journey: journey, leg: 1))
        }
        trips.append(F.trip(F.wien, F.linz, F.at(2026, 10, 20, 17, 10)))
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertEqual(guess.rides, 9, "3 round trips count twice for the rule")
        XCTAssertEqual(guess.trips, 6)
        XCTAssertEqual(guess.trips, JourneySummary.tripCount(trips), "the shown count is the Statistik count")
    }

    func testJourneyLegsCountAsOneRideFromFirstStartToLastStop() throws {
        var trips: [TripRecord] = []
        let days = [F.at(2026, 11, 2, 7, 0), F.at(2026, 11, 3, 7, 0), F.at(2026, 10, 26, 7, 0),
                    F.at(2026, 10, 27, 7, 0), F.at(2026, 10, 19, 7, 0), F.at(2026, 10, 20, 7, 0)]
        for day in days {
            let journey = UUID()
            trips.append(F.trip(F.linz, F.stPoelten, day, journey: journey, leg: 0))
            trips.append(F.trip(F.stPoelten, F.wien, day.addingTimeInterval(3600), journey: journey, leg: 1))
        }
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertEqual(guess.pairKey, CommuteDetector.pairKey(F.linz, F.wien))
        XCTAssertEqual(guess.rides, 6)
    }

    func testStationNamesWithoutIDsMatchIgnoringCaseAndAccents() throws {
        let a = CommuteEndpoint(stationID: nil, name: "St. Pölten Hbf")
        let b = CommuteEndpoint(stationID: nil, name: "Wien Hbf")
        let a2 = CommuteEndpoint(stationID: nil, name: "st. polten  hbf ")
        XCTAssertEqual(a.key, a2.key)
        let days = [F.at(2026, 11, 2, 7, 0), F.at(2026, 11, 3, 7, 0), F.at(2026, 10, 26, 7, 0),
                    F.at(2026, 10, 27, 7, 0), F.at(2026, 10, 19, 7, 0), F.at(2026, 10, 20, 7, 0)]
        let trips = days.enumerated().map { F.trip($0.offset % 2 == 0 ? a : a2, b, $0.element) }
        XCTAssertNotNil(CommuteDetector.guess(trips: trips, now: now))
    }

    // MARK: Negative

    func testRandomTripsStaySilent() {
        let places = [F.linz, F.wien, F.stPoelten, F.salzburg,
                      CommuteEndpoint(stationID: "x1", name: "Graz Hbf"), CommuteEndpoint(stationID: "x2", name: "Villach Hbf")]
        var generator = CommuteRandom(seed: 42)
        var trips: [TripRecord] = []
        for index in 0..<40 {
            let a = places[Int(generator.next() % UInt64(places.count))]
            var b = places[Int(generator.next() % UInt64(places.count))]
            if a == b { b = places[(places.firstIndex(of: a)! + 1) % places.count] }
            let day = Int(generator.next() % 50)
            let date = Calendar.vienna.date(byAdding: .day, value: -day, to: now)!.addingTimeInterval(Double(index) * 60)
            trips.append(F.trip(a, b, date))
        }
        // 40 rides over 15 pairs: no pair reaches 6 rides on 3 weeks and 2 weekdays with a lead.
        let all = CommuteDetector.candidates(trips: trips, now: now)
        XCTAssertFalse(all.contains { $0.confidence == .high }, "random trips must never produce a confident commute: \(all.map(\.pairKey))")
    }

    func testOneOffHolidayWeekIsNotACommute() {
        // Ten rides Linz ↔ Salzburg in one holiday week.
        let trips = (0..<10).map { F.trip($0 % 2 == 0 ? F.linz : F.salzburg, $0 % 2 == 0 ? F.salzburg : F.linz,
                                          F.at(2026, 10, 26 + $0 / 2, 9 + $0 % 2 * 8, 0)) }
        XCTAssertNil(CommuteDetector.guess(trips: trips, now: now))
    }

    func testRoundTripsOnOneDayAreNotACommute() {
        let day = F.at(2026, 11, 4, 8, 0)
        let trips = (0..<6).map { F.trip(F.linz, F.wien, day.addingTimeInterval(Double($0) * 600), roundTrip: true) }
        XCTAssertNil(CommuteDetector.guess(trips: trips, now: now), "12 rides on one day are one busy day, not a commute")
    }

    func testRoundTripsOnOneWeekdayAreNotACommute() {
        // Every Saturday for six weeks: a weekly visit, not a commute (one weekday only).
        let saturdays = (0..<6).map { Calendar.vienna.date(byAdding: .day, value: -7 * $0, to: F.at(2026, 10, 31, 9, 0))! }
        let trips = saturdays.map { F.trip(F.linz, F.salzburg, $0, roundTrip: true) }
        XCTAssertNil(CommuteDetector.guess(trips: trips, now: now))
    }

    func testFiveRidesAreTooFew() {
        let trips = Array(F.commuteWeeks(4).prefix(5))
        XCTAssertNil(CommuteDetector.guess(trips: trips, now: now))
    }

    func testTripsOlderThan56DaysDoNotCount() {
        // A commute that ended in summer.
        let old = F.commuteWeeks(4).map { trip -> TripRecord in
            var t = trip
            t.date = Calendar.vienna.date(byAdding: .day, value: -70, to: trip.date)!
            return t
        }
        XCTAssertNil(CommuteDetector.guess(trips: old, now: now))
    }

    func testFutureTripsDoNotCount() {
        let future = F.commuteWeeks(4).map { trip -> TripRecord in
            var t = trip
            t.date = Calendar.vienna.date(byAdding: .day, value: 30, to: trip.date)!
            return t
        }
        XCTAssertNil(CommuteDetector.guess(trips: future, now: now))
    }

    // MARK: Ties and leads

    func testTwoEqualPairsAreATieWithoutConfidence() throws {
        let a = F.commuteWeeks(3)
        let b = F.commuteWeeks(3, from: F.salzburg, to: F.stPoelten)
        let all = CommuteDetector.candidates(trips: a + b, now: now)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].rides, all[1].rides)
        XCTAssertEqual(all[0].confidence, .medium)
        XCTAssertEqual(all[1].confidence, .medium)
        // Deterministic order for the suggestion in Einstellungen.
        XCTAssertEqual(CommuteDetector.candidates(trips: (b + a).reversed(), now: now).map(\.pairKey), all.map(\.pairKey))
    }

    func testAClearLeadIsConfident() throws {
        // 24 rides against 12 (2×): confident. 24 against 18 (1.33×): not.
        let main = F.commuteWeeks(4)
        let side = Array(F.commuteWeeks(3, from: F.salzburg, to: F.stPoelten).prefix(12))
        XCTAssertEqual(CommuteDetector.guess(trips: main + side, now: now)?.confidence, .high)
        let bigSide = F.commuteWeeks(3, from: F.salzburg, to: F.stPoelten)
        XCTAssertEqual(CommuteDetector.guess(trips: main + bigSide, now: now)?.confidence, .medium)
    }

    // MARK: Clock times

    func testOneCaptureClusterGivesNoTimes() throws {
        // Both directions logged at 21:00 the same evening: capture time, not departures.
        let trips = F.commuteWeeks(4, outHour: 21, outMinute: 0, backHour: 21)
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertNil(guess.outboundMinute)
        XCTAssertNil(guess.returnMinute)
    }

    func testMidnightDatesGiveNoTimes() throws {
        let trips = F.commuteWeeks(4, outHour: 0, outMinute: 0, backHour: 0).map { trip -> TripRecord in
            var t = trip
            t.date = Calendar.vienna.startOfDay(for: trip.date)
            return t
        }
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now))
        XCTAssertNil(guess.outboundMinute)
    }

    func testWithoutTimesTheHomeStationDecidesTheOrigin() throws {
        let trips = F.commuteWeeks(4, outHour: 21, outMinute: 0, backHour: 21)
        let guess = try XCTUnwrap(CommuteDetector.guess(trips: trips, now: now, homeStationID: F.wien.stationID))
        XCTAssertEqual(guess.origin, F.wien)
    }

    func testTimesRoundToFiveMinutes() {
        XCTAssertEqual(CommuteDetector.roundTo5(7 * 60 + 22), 7 * 60 + 20)
        XCTAssertEqual(CommuteDetector.roundTo5(7 * 60 + 23), 7 * 60 + 25)
        XCTAssertEqual(CommuteDetector.roundTo5(23 * 60 + 59), 23 * 60 + 59, "clamped to the day")
    }
}

/// Deterministic random numbers (SplitMix64) for the negative tests.
private struct CommuteRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
