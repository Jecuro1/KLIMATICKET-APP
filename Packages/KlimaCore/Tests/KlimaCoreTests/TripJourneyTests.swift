import XCTest
@testable import KlimaCore

/// "Reise mit Etappen" (docs/JOURNEYS.md): legs keep their own figures, a journey counts as one "Fahrt".
final class TripJourneyTests: XCTestCase {
    let cal = Calendar.vienna
    lazy var day = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 7, minute: 12))!
    lazy var ticket = TicketPeriod(productID: "oe", name: "Ö", price: 1_400,
                                   start: cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!,
                                   end: cal.date(from: DateComponents(year: 2027, month: 2, day: 28))!)

    /// Lech → Langen (Bus) → Wien Hbf (Zug) → Praterstern (U-Bahn), one journey; plus a plain trip the same day.
    func sample(roundTrip: Bool = false) -> [TripRecord] {
        let journey = UUID()
        return [
            TripRecord(date: day, fromName: "Lech", toName: "Langen am Arlberg", mode: .bus, distanceKm: 16, fareEUR: 5.8,
                       isRoundTrip: roundTrip, states: ["V"], category: .leisure, journeyID: journey, legIndex: 0),
            TripRecord(date: day, fromName: "Langen am Arlberg", toName: "Wien Hauptbahnhof", mode: .train, distanceKm: 612,
                       fareEUR: 81.4, isRoundTrip: roundTrip,
                       states: ["V", "T", "S", "OÖ", "NÖ", "W"], category: .leisure, journeyID: journey, legIndex: 1),
            TripRecord(date: day, fromName: "Wien Hauptbahnhof", toName: "Wien Praterstern", mode: .metro, distanceKm: 4.5,
                       fareEUR: 3.2, isRoundTrip: roundTrip, states: ["W"], category: .leisure, journeyID: journey, legIndex: 2),
            TripRecord(date: day.addingTimeInterval(9 * 3600), fromName: "Wien Praterstern", toName: "Wien Hauptbahnhof",
                       mode: .metro, distanceKm: 4.5, fareEUR: 3.2, category: .leisure),
        ]
    }

    // MARK: Favourite legs

    func testLegCodecRoundTrip() {
        let legs = [JourneyLeg(fromName: "Lech", toName: "Langen am Arlberg", mode: .bus, distanceKm: 16.04, fareEUR: 5.8),
                    JourneyLeg(fromName: "Langen am Arlberg", fromStationID: "at:48:1226", toName: "Bregenz", toStationID: "at:48:452",
                               mode: .train, distanceKm: 88, fareEUR: 18.8, viaRaw: "at:48:130\tBludenz")]
        let raw = JourneyLegCodec.encode(legs)
        XCTAssertFalse(raw.isEmpty)
        XCTAssertLessThan(raw.utf8.count, 400)
        let decoded = JourneyLegCodec.decode(raw)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].distanceKm, 16, "km rounded to 0.1")
        XCTAssertEqual(decoded[1].via, [TripVia(name: "Bludenz", stationID: "at:48:130")])
        XCTAssertEqual(decoded[1].mode, .train)
        XCTAssertNil(decoded[0].fromStationID)
    }

    func testLegCodecTolerance() {
        XCTAssertEqual(JourneyLegCodec.decode(""), [])
        XCTAssertEqual(JourneyLegCodec.decode("{broken"), [])
        XCTAssertEqual(JourneyLegCodec.decode(#"[{"f":"A","t":"B","m":"bus","km":1,"eur":2}]"#), [], "one leg is no journey")
        XCTAssertEqual(JourneyLegCodec.encode([JourneyLeg(fromName: "A", toName: "B", mode: .bus, distanceKm: 1, fareEUR: 2)]), "")
        // Unknown keys and modes from a newer app, a negative fare, a leg without a name.
        let raw = #"[{"f":"A","t":"B","m":"hyperloop","km":-3,"eur":-1,"x":true},{"f":"B","t":"C","m":"tram","km":2,"eur":2.4},{"f":"","t":"D","m":"bus"}]"#
        let legs = JourneyLegCodec.decode(raw)
        XCTAssertEqual(legs.count, 2)
        XCTAssertEqual(legs[0].mode, .other)
        XCTAssertEqual(legs[0].fareEUR, 0)
        XCTAssertEqual(legs[0].distanceKm, 0)
        let many = (0..<9).map { JourneyLeg(fromName: "S\($0)", toName: "S\($0 + 1)", mode: .bus, distanceKm: 1, fareEUR: 1) }
        XCTAssertEqual(JourneyLegCodec.decode(JourneyLegCodec.encode(many)).count, JourneyLeg.maxCount)
    }

    func testMainMode() {
        XCTAssertEqual(JourneySummary.mainMode([(.bus, 16, 5.8), (.train, 612, 81.4), (.metro, 4.5, 3.2)]), .train)
        XCTAssertEqual(JourneySummary.mainMode([(.bus, 5, 2.4), (.tram, 5, 3.2)]), .tram, "same km: the dearer leg")
        XCTAssertNil(JourneySummary.mainMode([]))
    }

    // MARK: Statistics

    func testSummaryCountsAJourneyOnce() {
        let summary = SavingsCalculator.summary(ticket: ticket, trips: sample(), now: day.addingTimeInterval(86_400))
        XCTAssertEqual(summary.tripCount, 2, "the journey and the ride back")
        XCTAssertEqual(summary.legCount, 4)
        XCTAssertEqual(summary.totalValue, 5.8 + 81.4 + 3.2 + 3.2, accuracy: 0.001)
        XCTAssertEqual(summary.distanceKm, 16 + 612 + 4.5 + 4.5, accuracy: 0.001)
        XCTAssertEqual(summary.averageValuePerTrip, summary.totalValue / 2, accuracy: 0.001)
        // CO₂ per leg and mode: the bus leg saves at the bus factor, not the train's.
        let co2 = EmissionFactors.fallback
        let expected = co2.savedKg(km: 16, mode: .bus) + co2.savedKg(km: 612, mode: .train) + 2 * co2.savedKg(km: 4.5, mode: .metro)
        XCTAssertEqual(summary.co2SavedKg, expected, accuracy: 0.001)

        let round = SavingsCalculator.summary(ticket: ticket, trips: sample(roundTrip: true), now: day.addingTimeInterval(86_400))
        XCTAssertEqual(round.tripCount, 2)
        XCTAssertEqual(round.legCount, 7)
    }

    func testBucketsCountAJourneyOnce() {
        let trips = sample()
        let month = StatsAggregator.months(trips)
        XCTAssertEqual(month.count, 1)
        XCTAssertEqual(month[0].trips, 2)
        XCTAssertEqual(month[0].value, 93.6, accuracy: 0.001)
        XCTAssertEqual(StatsAggregator.days(trips).first?.trips, 2)
        XCTAssertEqual(StatsAggregator.weekdays(trips).map(\.trips).reduce(0, +), 2)
        // Modes count legs: each mode its own leg.
        let modes = Dictionary(uniqueKeysWithValues: StatsAggregator.modes(trips).map { ($0.mode, $0.trips) })
        XCTAssertEqual(modes, [.bus: 1, .train: 1, .metro: 2])
    }

    func testRoutesAndRecordsAreJourneys() {
        let trips = sample()
        let routes = StatsAggregator.topRoutes(trips)
        XCTAssertEqual(routes.count, 2)
        let journey = routes.first { $0.fromName == "Lech" || $0.toName == "Lech" }
        XCTAssertNotNil(journey)
        XCTAssertEqual(journey?.trips, 1)
        XCTAssertEqual(journey?.value ?? 0, 90.4, accuracy: 0.001)
        let records = StatsAggregator.records(trips, now: day)
        XCTAssertEqual(records.longestTrip?.fromName, "Lech")
        XCTAssertEqual(records.longestTrip?.toName, "Wien Praterstern")
        XCTAssertEqual(records.longestTrip?.distanceKm ?? 0, 632.5, accuracy: 0.001)
        XCTAssertEqual(records.uniqueStations, 4, "every leg's stations")
    }

    func testCollapsed() {
        let collapsed = JourneySummary.collapsed(sample(roundTrip: true))
        XCTAssertEqual(collapsed.count, 2)
        let journey = collapsed[0]
        XCTAssertEqual(journey.mode, .train)
        XCTAssertTrue(journey.isRoundTrip)
        XCTAssertEqual(journey.fareEUR, 90.4, accuracy: 0.001, "per direction")
        XCTAssertEqual(journey.totalValue, 180.8, accuracy: 0.001)
        XCTAssertEqual(journey.via.map(\.name), ["Langen am Arlberg", "Wien Hauptbahnhof"])
        XCTAssertEqual(journey.states.count, 6)
        XCTAssertEqual(collapsed[1].journeyID, nil)
        // Legs in any order come out in travel order; a lone leg (the others deleted) stays as it is.
        let shuffled = JourneySummary.collapsed(Array(sample().reversed()))
        XCTAssertEqual(shuffled.first { $0.journeyID != nil }?.fromName, "Lech")
        let lone = JourneySummary.collapsed([sample()[1]])
        XCTAssertEqual(lone.first?.fromName, "Langen am Arlberg")
    }

    func testCategoriesAndHonestBalance() {
        var trips = sample()
        trips[0].isInduced = true
        trips[2].isInduced = true
        let buckets = CategoryStats.buckets(trips)
        XCTAssertEqual(buckets.first?.trips, 2)
        XCTAssertEqual(buckets.first?.inducedTrips, 1)
        XCTAssertEqual(buckets.first?.tripShare ?? 0, 1, accuracy: 0.001)
        let honest = CategoryStats.honestBalance(ticket: ticket, trips: trips)
        XCTAssertEqual(honest.tripCount, 2)
        XCTAssertEqual(honest.inducedTripCount, 1)
        XCTAssertEqual(honest.extraValue, 9, accuracy: 0.001)
    }
}
