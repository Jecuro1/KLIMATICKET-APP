import XCTest
@testable import KlimaCore

// MARK: siri – the table Siri answers from (docs/SIRI_QUESTIONS.md §2): its days add up to Statistik's SavingsSummary, journeys count
// once, Vienna day boundaries, and the JSON survives a round trip and garbage.
final class SiriKpiTableTests: XCTestCase {
    let cal = Calendar.vienna

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func trip(_ date: Date, km: Double = 50, fare: Double = 20, mode: TransportMode = .train, roundTrip: Bool = false,
              journey: UUID? = nil, leg: Int = 0) -> TripRecord {
        TripRecord(date: date, fromName: "A", toName: "B", mode: mode, distanceKm: km, fareEUR: fare, isRoundTrip: roundTrip,
                   journeyID: journey, legIndex: leg)
    }

    var ticket: TicketPeriod {
        TicketPeriod(productID: "oe", name: "KlimaTicket Ö Classic", price: 1_179, start: date(2026, 3, 1, 0), end: TicketPeriod.standardEnd(for: date(2026, 3, 1, 0)))
    }

    /// Several fixture sets: mixed modes, round trips, a journey of three legs, DST days, the first and last moment of the ticket.
    func fixtures() -> [[TripRecord]] {
        let journey = UUID()
        let mixed = [
            trip(date(2026, 3, 1, 0, 1), km: 104, fare: 22.8, roundTrip: true),
            trip(date(2026, 3, 29, 1, 30), km: 12, fare: 3.1, mode: .bus),           // DST: 2 → 3 o'clock that night
            trip(date(2026, 3, 29, 23, 30), km: 4, fare: 2.4, mode: .tram),
            trip(date(2026, 6, 12, 7, 10), km: 30, fare: 9, mode: .sBahn, journey: journey, leg: 0),
            trip(date(2026, 6, 12, 7, 55), km: 3, fare: 2.4, mode: .metro, journey: journey, leg: 1),
            trip(date(2026, 6, 12, 8, 20), km: 2, fare: 2.4, mode: .tram, journey: journey, leg: 2),
            trip(date(2026, 10, 25, 2, 30), km: 60, fare: 14, roundTrip: true),      // DST: 3 → 2 o'clock, the hour twice
            trip(date(2027, 2, 28, 23, 59), km: 200, fare: 49.9),
        ]
        var daily: [TripRecord] = []
        for offset in stride(from: 0, to: 360, by: 3) {
            let day = cal.date(byAdding: .day, value: offset, to: date(2026, 3, 2, 7, 45))!
            daily.append(trip(day, km: 37.5 + Double(offset % 7), fare: 8.6 + Double(offset % 5), mode: offset % 2 == 0 ? .train : .bus,
                              roundTrip: offset % 4 == 0))
        }
        return [mixed, daily, mixed + daily, []]
    }

    func testDaysOfTheTicketPeriodAddUpToTheSummary() {
        let now = date(2027, 3, 1, 9)
        for (index, trips) in fixtures().enumerated() {
            let summary = SavingsCalculator.summary(ticket: ticket, trips: trips, now: now)
            let table = KpiTableBuilder.make(ticket: (ticket, summary), trips: trips, now: now, emissions: .fallback)
            let sum = table.sum(from: KpiDailyTable.dayKey(ticket.start), through: KpiDailyTable.dayKey(ticket.end))
            XCTAssertEqual(sum.journeys, summary.tripCount, "fixture \(index)")
            XCTAssertEqual(sum.value, summary.totalValue, accuracy: 1e-6, "fixture \(index)")
            XCTAssertEqual(sum.km, summary.distanceKm, accuracy: 1e-6, "fixture \(index)")
            XCTAssertEqual(sum.co2, summary.co2SavedKg, accuracy: 1e-6, "fixture \(index)")
            // The ticket row is the summary as it is.
            XCTAssertEqual(table.ticket?.tripCount, summary.tripCount)
            XCTAssertEqual(table.ticket?.totalValue, summary.totalValue)
            XCTAssertEqual(table.ticket?.distanceKm, summary.distanceKm)
            XCTAssertEqual(table.ticket?.co2SavedKg, summary.co2SavedKg)
            XCTAssertEqual(table.ticket?.price, summary.ticketPrice)
        }
    }

    func testMonthsMatchStatistik() {
        let now = date(2027, 3, 1, 9)
        let trips = fixtures()[2]
        let table = KpiTableBuilder.make(ticket: nil, trips: trips, now: now, emissions: .fallback)
        for bucket in StatsAggregator.months(trips) {
            let c = cal.dateComponents([.year, .month], from: bucket.month)
            let sum = table.sum(from: KpiDailyTable.dayKey(year: c.year!, month: c.month!, day: 1),
                                through: KpiDailyTable.dayKey(year: c.year!, month: c.month!, day: 31))
            XCTAssertEqual(sum.journeys, bucket.trips, "\(c)")
            XCTAssertEqual(sum.value, bucket.value, accuracy: 1e-6)
            XCTAssertEqual(sum.km, bucket.distanceKm, accuracy: 1e-6)
        }
    }

    func testJourneyCountsOnceOnTheDayOfItsFirstLeg() {
        let journey = UUID()
        // Leaves at 23:40, the second leg after midnight.
        let trips = [trip(date(2026, 5, 8, 23, 40), fare: 10, journey: journey, leg: 0),
                     trip(date(2026, 5, 9, 0, 20), fare: 4, journey: journey, leg: 1)]
        let days = KpiTableBuilder.days(trips, now: date(2026, 5, 10), emissions: .fallback)
        XCTAssertEqual(days.map(\.day), ["2026-05-08", "2026-05-09"])
        XCTAssertEqual(days.map(\.journeys), [1, 0])
        XCTAssertEqual(days.map(\.value), [10, 4])
    }

    func testDayKeysAreViennaDays() {
        // 23:30 UTC on 31 Oct is already 1 Nov in Vienna (CET, UTC+1); 22:30 UTC on 30 Jun is 1 Jul (CEST, UTC+2).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let late = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!
        let summer = utc.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 22, minute: 30))!
        XCTAssertEqual(KpiDailyTable.dayKey(late), "2026-11-01")
        XCTAssertEqual(KpiDailyTable.dayKey(summer), "2026-07-01")
        // Both DST nights stay one day each.
        let days = KpiTableBuilder.days([trip(date(2026, 3, 29, 0, 30)), trip(date(2026, 3, 29, 23, 30)),
                                         trip(date(2026, 10, 25, 0, 30)), trip(date(2026, 10, 25, 23, 30))],
                                        now: date(2026, 11, 1), emissions: .fallback)
        XCTAssertEqual(days.map(\.day), ["2026-03-29", "2026-10-25"])
        XCTAssertEqual(days.map(\.journeys), [2, 2])
    }

    func testWindowKeepsFourHundredDays() {
        let now = date(2026, 11, 20, 9)
        let today = cal.startOfDay(for: now)
        let oldest = cal.date(byAdding: .day, value: -(KpiDailyTable.dayWindow - 1), to: today)!
        let trips = [trip(cal.date(byAdding: .minute, value: -1, to: oldest)!), trip(oldest), trip(now),
                     trip(cal.date(byAdding: .day, value: 5, to: now)!)]
        let days = KpiTableBuilder.days(trips, now: now, emissions: .fallback)
        XCTAssertEqual(days.first?.day, KpiDailyTable.dayKey(oldest))
        XCTAssertEqual(days.count, 3, "the day before the window is left out, a trip logged ahead is kept")
    }

    func testRoundTripAndSize() {
        let now = date(2027, 3, 1, 9)
        let trips = fixtures()[2]
        let summary = SavingsCalculator.summary(ticket: ticket, trips: trips, now: now)
        let table = KpiTableBuilder.make(ticket: (ticket, summary), trips: trips, now: now, emissions: .fallback,
                                         format: FormatPrefs(amounts: .cents, weekStart: .sunday, co2: .kilograms))
        let data = table.encoded()!
        XCTAssertEqual(KpiDailyTable.decode(data), table)
        // A full year of daily trips stays small (the spec's „about 30 KB“ for 400 days).
        var everyDay: [TripRecord] = []
        for offset in 0..<400 { everyDay.append(trip(cal.date(byAdding: .day, value: -offset, to: now)!, km: 123.4567, fare: 31.4159)) }
        let full = KpiTableBuilder.make(ticket: (ticket, summary), trips: everyDay, now: now, emissions: .fallback)
        XCTAssertEqual(full.days.count, 400)
        XCTAssertLessThan(full.encoded()!.count, 60_000)
    }

    func testGarbageAndBadRows() {
        for text in ["", "null", "[]", "42", "{", "{\"version\":1}", "{\"generatedAt\":\"gestern\"}"] {
            XCTAssertNil(KpiDailyTable.decode(Data(text.utf8)), text)
        }
        let text = #"""
        {"generatedAt":0,"version":7,"format":"bunt","ticket":{"name":"X"},
         "days":[{"day":"2026-10-01","journeys":2,"value":20,"km":10,"co2":1},
                 {"day":"2026-13-01","journeys":1,"value":1,"km":1,"co2":1},
                 {"day":"2026-10-02","journeys":-1,"value":1,"km":1,"co2":1},
                 {"day":"2026-10-03","journeys":1,"value":-5,"km":1,"co2":1},
                 "Fahrt", 3, null,
                 {"day":"2026-10-01","journeys":9,"value":99,"km":9,"co2":9},
                 {"day":"2026-09-30","journeys":1,"value":3,"km":2,"co2":0.5}]}
        """#
        let table = KpiDailyTable.decode(Data(text.utf8))
        XCTAssertNotNil(table)
        XCTAssertEqual(table?.format, .standard)
        XCTAssertNil(table?.ticket)
        XCTAssertEqual(table?.days.map(\.day), ["2026-09-30", "2026-10-01"], "bad rows dropped, a day only once, sorted")
        XCTAssertEqual(table?.days.last?.journeys, 2, "the first row of a day wins")
    }

    func testStaleAfterOneDay() {
        let made = date(2026, 11, 12, 8)
        let table = KpiDailyTable(generatedAt: made, ticket: nil, days: [])
        XCTAssertFalse(table.isStale(at: made.addingTimeInterval(24 * 3600)))
        XCTAssertTrue(table.isStale(at: made.addingTimeInterval(24 * 3600 + 1)))
    }

    func testSameFiguresIgnoreTheTimeStamp() {
        let a = KpiDailyTable(generatedAt: date(2026, 11, 12), ticket: nil, days: [.init(day: "2026-11-12", journeys: 1, value: 2, km: 3, co2: 4)])
        var b = a
        b.generatedAt = date(2026, 11, 13)
        XCTAssertTrue(a.hasSameFigures(as: b))
        b.days[0].value = 2.5
        XCTAssertFalse(a.hasSameFigures(as: b))
    }
}
