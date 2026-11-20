import XCTest
@testable import KlimaCore

/// „Verspätungs-Tagebuch“ (docs/DELAY_DIARY.md): the late mark, Fahrten, validity months, the share, the PDF rows and the copy.
final class DelayDiaryTests: XCTestCase {
    private let calendar = Calendar.vienna

    private func vienna(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func trip(_ date: Date, delay: Int = 0, source: TripDelaySource? = nil, mode: TransportMode = .train,
                      journey: UUID? = nil, leg: Int = 0, from: String = "A", to: String = "B", line: String = "",
                      roundTrip: Bool = false) -> DelayDiaryTrip {
        DelayDiaryTrip(date: date, fromName: from, toName: to, mode: mode, lineSummary: line, journeyID: journey, legIndex: leg,
                       isRoundTrip: roundTrip, delayMinutes: delay, delaySource: source)
    }

    /// A ticket from 1 March 2026 (Vienna) for a year.
    private var ticketStart: Date { vienna(2026, 3, 1) }
    private var ticketEnd: Date { TicketPeriod.standardEnd(for: ticketStart) }

    private func year(_ trips: [DelayDiaryTrip], now: Date, options: DelayDiaryOptions = DelayDiaryOptions(),
                      start: Date? = nil) -> DelayDiaryYear {
        let start = start ?? ticketStart
        return DelayDiaryCalculator.compute(trips: trips, ticketStart: start, ticketEnd: TicketPeriod.standardEnd(for: start), now: now,
                                            options: options)
    }

    // MARK: The late mark

    func testThresholdEdgesFourFiveSix() {
        XCTAssertEqual(DelayDiaryRules.defaultThresholdMinutes, 5)
        XCTAssertFalse(DelayDiaryRules.isLate(4))
        XCTAssertTrue(DelayDiaryRules.isLate(5))
        XCTAssertTrue(DelayDiaryRules.isLate(6))
        XCTAssertFalse(DelayDiaryRules.isLate(0))

        let day = vienna(2026, 3, 10, 8)
        let trips = [4, 5, 6].enumerated().map { index, minutes in
            trip(day.addingTimeInterval(Double(index) * 3600), delay: minutes, source: .manual)
        }
        let month = year(trips, now: vienna(2026, 3, 20)).months[0]
        XCTAssertEqual(month.recordedCount, 3)
        XCTAssertEqual(month.lateCount, 2)
        XCTAssertEqual(month.onTimeCount, 1)
        XCTAssertEqual(month.lateEntries.map(\.minutes), [5, 6])
    }

    func testChosenThresholdAndNormalisation() {
        XCTAssertEqual(DelayDiaryRules.normalizedThreshold(10), 10)
        XCTAssertEqual(DelayDiaryRules.normalizedThreshold(7), 5)
        XCTAssertEqual(DelayDiaryRules.normalizedThreshold(-3), 5)
        XCTAssertFalse(DelayDiaryRules.isLate(9, threshold: 10))
        XCTAssertTrue(DelayDiaryRules.isLate(10, threshold: 10))
        // A threshold of 0 would call „pünktlich“ late: never below 1 minute.
        XCTAssertFalse(DelayDiaryRules.isLate(0, threshold: 0))

        let day = vienna(2026, 3, 10, 8)
        let trips = [3, 9, 10, 15].enumerated().map { index, minutes in
            trip(day.addingTimeInterval(Double(index) * 3600), delay: minutes, source: .live)
        }
        XCTAssertEqual(year(trips, now: vienna(2026, 3, 20), options: DelayDiaryOptions(thresholdMinutes: 10)).lateCount, 2)
        XCTAssertEqual(year(trips, now: vienna(2026, 3, 20), options: DelayDiaryOptions(thresholdMinutes: 3)).lateCount, 4)
    }

    func testClampKeepsTheStepperRange() {
        XCTAssertEqual(DelayDiaryRules.clamp(-5), 0)
        XCTAssertEqual(DelayDiaryRules.clamp(240), 240)
        XCTAssertEqual(DelayDiaryRules.clamp(241), 240)
        let stored = trip(vienna(2026, 3, 2, 9), delay: 999, source: .manual)
        XCTAssertEqual(stored.recordedDelayMinutes, 240)
        XCTAssertNil(trip(vienna(2026, 3, 2, 9), delay: 12, source: nil).recordedDelayMinutes)
    }

    // MARK: Validity months

    func testMonthBucketingAroundMidnightAtMonthEnd() {
        let lastMinute = trip(vienna(2026, 3, 31, 23, 59, 59), delay: 7, source: .manual)
        let midnight = trip(vienna(2026, 4, 1, 0, 0, 0), delay: 8, source: .manual)
        let result = year([lastMinute, midnight], now: vienna(2026, 4, 10))
        XCTAssertEqual(result.months.count, 2)
        XCTAssertEqual(result.months[0].entries.map(\.id), [lastMinute.id])
        XCTAssertEqual(result.months[1].entries.map(\.id), [midnight.id])
        // The first month's last second (summer time began on 29 March): 31 March 23:59:59 Vienna.
        XCTAssertEqual(result.months[0].end, vienna(2026, 3, 31, 23, 59, 59))
        XCTAssertEqual(result.months[1].start, vienna(2026, 4, 1))
    }

    func testValidityMonthsStartOnTheTicketsDayNumber() {
        let start = vienna(2026, 3, 15)
        let before = trip(vienna(2026, 4, 14, 23, 59, 59), delay: 6, source: .manual)
        let after = trip(vienna(2026, 4, 15, 0, 0, 0), delay: 6, source: .manual)
        let result = year([before, after], now: vienna(2026, 4, 20), start: start)
        XCTAssertEqual(result.months.map(\.start), [vienna(2026, 3, 15), vienna(2026, 4, 15)])
        XCTAssertEqual(result.months[0].entries.map(\.id), [before.id])
        XCTAssertEqual(result.months[1].entries.map(\.id), [after.id])
        XCTAssertTrue(result.months[1].isCurrent)
        XCTAssertFalse(result.months[0].isCurrent)
    }

    func testOnlyBegunMonthsAndTripsUpToNowInsideTheTicket() {
        let now = vienna(2026, 5, 3, 12)
        let trips = [
            trip(vienna(2026, 2, 28, 18), delay: 30, source: .manual),     // before the ticket
            trip(vienna(2026, 5, 3, 11), delay: 9, source: .manual),
            trip(vienna(2026, 5, 3, 18), delay: 9, source: .manual),       // later today: not yet
        ]
        let result = year(trips, now: now)
        XCTAssertEqual(result.months.count, 3, "March, April and May have begun")
        XCTAssertTrue(result.months[2].isCurrent)
        XCTAssertEqual(result.tripCount, 1)
        XCTAssertEqual(result.lateCount, 1)
        // An unstarted ticket has no months.
        XCTAssertTrue(year(trips, now: vienna(2026, 2, 20)).months.isEmpty)
        // An ended ticket year has twelve months, none current.
        let ended = year([], now: vienna(2027, 6, 1))
        XCTAssertEqual(ended.months.count, 12)
        XCTAssertFalse(ended.months.contains(where: \.isCurrent))
    }

    // MARK: The share

    func testFewerThanFiveRecordedGiveNoShare() {
        let day = vienna(2026, 3, 3, 7)
        var trips = (0..<4).map { trip(day.addingTimeInterval(Double($0) * 86_400), delay: 0, source: .manual) }
        // Ten more without a recorded arrival change nothing: they are not „pünktlich“.
        trips += (0..<10).map { trip(day.addingTimeInterval(Double($0) * 86_400 + 3600)) }
        let month = year(trips, now: vienna(2026, 3, 25)).months[0]
        XCTAssertEqual(month.tripCount, 14)
        XCTAssertEqual(month.recordedCount, 4)
        XCTAssertEqual(month.notRecordedCount, 10)
        XCTAssertNil(month.onTimeShare)
        XCTAssertEqual(DelayDiaryText.shareLine(month.onTimeShare), "zu wenig Fahrten für eine Quote")

        trips.append(trip(day.addingTimeInterval(20 * 86_400), delay: 12, source: .live))
        let five = year(trips, now: vienna(2026, 3, 25)).months[0]
        XCTAssertEqual(five.recordedCount, 5)
        XCTAssertEqual(five.onTimeShare ?? -1, 0.8, accuracy: 1e-12)
    }

    func testUnrecordedTripsStayOutOfTheShareAndMarkedPunctualCountsAsOnTime() {
        let day = vienna(2026, 3, 3, 7)
        let punctual = (0..<6).map { trip(day.addingTimeInterval(Double($0) * 86_400), delay: 0, source: .manual) }
        let late = (0..<2).map { trip(day.addingTimeInterval(Double($0) * 86_400 + 7200), delay: 25, source: .manual) }
        let unknown = (0..<12).map { trip(day.addingTimeInterval(Double($0) * 86_400 + 3600)) }
        let result = year(punctual + late + unknown, now: vienna(2026, 3, 28))
        XCTAssertEqual(result.recordedCount, 8)
        XCTAssertEqual(result.onTimeCount, 6)
        XCTAssertEqual(result.lateCount, 2)
        XCTAssertEqual(result.notRecordedCount, 12)
        XCTAssertEqual(result.onTimeShare ?? -1, 0.75, accuracy: 1e-12)
        XCTAssertEqual(result.months[0].unrecordedEntries.count, 12)
        XCTAssertEqual(result.lateMinutes, 50)
    }

    func testEmptyYearAndNoNaN() {
        let result = year([], now: vienna(2026, 4, 2))
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.onTimeShare)
        XCTAssertNil(result.longest)
        XCTAssertEqual(DelayDiaryText.percent(.nan), "–")
        XCTAssertNil(DelayDiaryRules.onTimeShare(recorded: 0, late: 0))
    }

    // MARK: Fahrten

    func testJourneyCountsOnceWithItsLastRecordedArrival() {
        let journey = UUID()
        let date = vienna(2026, 3, 12, 6, 40)
        let legs = [
            trip(date, delay: 14, source: .live, mode: .bus, journey: journey, leg: 0, from: "Lech", to: "St. Anton", line: "Bus 4235"),
            trip(date, delay: 3, source: .manual, journey: journey, leg: 1, from: "St. Anton", to: "Innsbruck Hbf", line: "RJX 662"),
            trip(date, mode: .tram, journey: journey, leg: 2, from: "Innsbruck Hbf", to: "Marktplatz", line: "Tram 1"),
        ]
        let entries = DelayDiaryEntries.make(legs, now: vienna(2026, 3, 20))
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.id, journey)
        XCTAssertEqual(entry.minutes, 3, "the last recorded arrival, not the bus's 14 nor a sum")
        XCTAssertEqual(entry.source, .manual)
        XCTAssertEqual(entry.editTripID, legs[1].id)
        XCTAssertFalse(entry.isLate)
        XCTAssertEqual(entry.fromName, "Lech")
        XCTAssertEqual(entry.toName, "Marktplatz")
        XCTAssertEqual(entry.lines, "Bus 4235 · RJX 662 · Tram 1")
        XCTAssertEqual(entry.modes, [.bus, .train, .tram])
        XCTAssertEqual(entry.legCount, 3)

        // „Nur Bahn“: only the train leg counts.
        let rail = DelayDiaryEntries.make(legs, options: DelayDiaryOptions(scope: .rail), now: vienna(2026, 3, 20))
        XCTAssertEqual(rail.count, 1)
        XCTAssertEqual(rail[0].legCount, 1)
        XCTAssertEqual(rail[0].fromName, "St. Anton")
        XCTAssertEqual(rail[0].lines, "RJX 662")
        // A bus-only trip is not a Fahrt with „Nur Bahn“.
        XCTAssertTrue(DelayDiaryEntries.make([trip(date, delay: 20, source: .manual, mode: .bus)], options: DelayDiaryOptions(scope: .rail),
                                             now: vienna(2026, 3, 20)).isEmpty)
    }

    func testUnrecordedJourneyEditsItsLastLeg() {
        let journey = UUID()
        let date = vienna(2026, 3, 12, 6, 40)
        let first = trip(date, journey: journey, leg: 0)
        let last = trip(date, journey: journey, leg: 1)
        let entry = DelayDiaryEntries.make([last, first], now: vienna(2026, 3, 20))[0]
        XCTAssertNil(entry.minutes)
        XCTAssertEqual(entry.editTripID, last.id)
        XCTAssertEqual(entry.tripIDs, [first.id, last.id])
    }

    /// The diary counts recorded Fahrten exactly like the Zeitbilanz's „Verspätungen“ card (no drift between the two screens).
    func testRecordedFahrtenMatchTheZeitbilanz() {
        var inputs: [TimeTripInput] = []
        var generator = SystemRandomNumberGenerator()
        let base = vienna(2026, 3, 2, 6)
        for index in 0..<120 {
            let date = base.addingTimeInterval(Double(index) * 3 * 3600)
            let roll = Int.random(in: 0..<10, using: &generator)
            let source: TripDelaySource? = roll < 3 ? nil : (roll < 7 ? .manual : .live)
            let delay = Int.random(in: 0..<40, using: &generator)
            if index % 7 == 0 {
                let journey = UUID()
                for leg in 0..<3 {
                    let legSource: TripDelaySource? = leg == 1 ? nil : source
                    inputs.append(TimeTripInput(date: date, mode: .train, distanceKm: 20, journeyID: journey, legIndex: leg,
                                                delayMinutes: delay + leg, delaySource: legSource))
                }
            } else {
                inputs.append(TimeTripInput(date: date, mode: .train, distanceKm: 20, delayMinutes: delay, delaySource: source))
            }
        }
        let now = vienna(2026, 4, 30)
        let range = ticketStart...ticketEnd
        let balance = TimeBalanceCalculator.compute(trips: inputs, range: range, now: now, carProfile: CarProfile())
        let diary = DelayDiaryCalculator.compute(trips: inputs.map { DelayDiaryTrip($0) }, ticketStart: ticketStart, ticketEnd: ticketEnd,
                                                 now: now)
        XCTAssertEqual(diary.tripCount, balance.tripCount)
        XCTAssertEqual(diary.recordedCount, balance.delays?.recordedTrips)
        let anyMinute = diary.entries.filter { ($0.minutes ?? 0) >= 1 }.count
        XCTAssertEqual(anyMinute, balance.delays?.delayedTrips)
        XCTAssertEqual(diary.entries.compactMap(\.minutes).reduce(0, +), Int(balance.delays?.totalMinutes ?? -1))
    }

    // MARK: Report

    func testReportOrderingAndSelection() {
        let april = vienna(2026, 4, 9, 7, 5)
        let trips = [
            trip(vienna(2026, 5, 2, 17), delay: 31, source: .live, from: "Wien", to: "Linz", line: "RJ 540"),
            trip(april, delay: 12, source: .manual, from: "St. Anton", to: "Landeck", line: "REX 5"),
            trip(april, delay: 9, source: .live, from: "Innsbruck", to: "Wörgl", line: "S 1"),
            trip(vienna(2026, 3, 20, 9), delay: 4, source: .manual),          // below the mark: not in the PDF
            trip(vienna(2026, 3, 21, 9), delay: 0, source: .manual),
            trip(vienna(2026, 3, 22, 9), delay: 18, source: .manual, from: "Bludenz", to: "Bregenz", roundTrip: true),
        ]
        let diary = year(trips, now: vienna(2026, 5, 10))
        let report = DelayReportBuilder.make(diary)
        XCTAssertEqual(report.months.map(\.index), [0, 1, 2])
        XCTAssertEqual(report.rows.map(\.minutes), [18, 9, 12, 31], "oldest first; the same moment by route (Innsbruck before St. Anton)")
        XCTAssertEqual(report.rows[0].route, "Bludenz → Bregenz (Hin & Retour)")
        XCTAssertEqual(report.rows[1].train, "S 1")
        XCTAssertEqual(report.rows[3].source, .live)
        XCTAssertEqual(report.months[0].recordedCount, 3)
        XCTAssertEqual(report.months[0].lateCount, 1)
        XCTAssertNil(report.months[0].onTimeShare)
        XCTAssertEqual(report.threshold, 5)

        let selected = DelayReportBuilder.make(diary, months: [2, 0, 7])
        XCTAssertEqual(selected.months.map(\.index), [0, 2])
        XCTAssertEqual(selected.rows.map(\.minutes), [18, 31])
        XCTAssertEqual(DelayReportBuilder.defaultSelection(diary), [0, 1, 2])
        XCTAssertTrue(DelayReportBuilder.make(diary, months: []).isEmpty)
    }

    func testDefaultSelectionWithoutLateFahrten() {
        let trips = [trip(vienna(2026, 4, 3, 8), delay: 2, source: .manual)]
        let diary = year(trips, now: vienna(2026, 5, 10))
        XCTAssertEqual(DelayReportBuilder.defaultSelection(diary), [1])
        XCTAssertEqual(DelayReportBuilder.make(diary, months: [1]).rows.count, 0)
    }

    // MARK: Options

    func testOptionsDecodeTolerantly() throws {
        XCTAssertEqual(DelayDiaryOptions.decode(nil), DelayDiaryOptions())
        XCTAssertEqual(DelayDiaryOptions.decode(Data("nonsense".utf8)), DelayDiaryOptions())
        XCTAssertEqual(DelayDiaryOptions.decode(Data(#"{"thresholdMinutes":10,"scope":"rail"}"#.utf8)),
                       DelayDiaryOptions(thresholdMinutes: 10, scope: .rail))
        XCTAssertEqual(DelayDiaryOptions.decode(Data(#"{"thresholdMinutes":"x","scope":"bus"}"#.utf8)), DelayDiaryOptions())
        XCTAssertEqual(DelayDiaryOptions.decode(Data(#"{"thresholdMinutes":7}"#.utf8)).thresholdMinutes, 5)
        let round = try JSONEncoder().encode(DelayDiaryOptions(thresholdMinutes: 15, scope: .rail))
        XCTAssertEqual(DelayDiaryOptions.decode(round), DelayDiaryOptions(thresholdMinutes: 15, scope: .rail))
        XCTAssertTrue(DelayDiaryOptions().isDefault)
    }

    // MARK: Copy

    func testPercentRoundsDownBelowAHundred() {
        XCTAssertEqual(DelayDiaryText.percent(1), "100\u{00A0}%")
        XCTAssertEqual(DelayDiaryText.percent(299.0 / 300.0), "99\u{00A0}%")
        XCTAssertEqual(DelayDiaryText.percent(0.875), "87\u{00A0}%")
        XCTAssertEqual(DelayDiaryText.percent(0), "0\u{00A0}%")
        XCTAssertEqual(DelayDiaryText.percent(0.004), "< 1\u{00A0}%")
    }

    func testRowAndSpokenTexts() {
        XCTAssertEqual(DelayDiaryText.rowValue(minutes: 12, source: .manual), "+12\u{00A0}Min. · von Hand")
        XCTAssertEqual(DelayDiaryText.rowValue(minutes: 12, source: .live), "+12\u{00A0}Min. · live")
        XCTAssertEqual(DelayDiaryText.rowValue(minutes: 0, source: .manual), "pünktlich · von Hand")
        XCTAssertEqual(DelayDiaryText.rowValue(minutes: nil, source: nil), "nicht erfasst")
        XCTAssertEqual(DelayDiaryText.spoken(12), "12 Minuten Verspätung")
        XCTAssertEqual(DelayDiaryText.spoken(1), "1 Minute Verspätung")
        XCTAssertEqual(DelayDiaryText.spoken(0), "Pünktlich")
        XCTAssertEqual(DelayDiaryText.monthSummary(trips: 12, recorded: 9, late: 2), "12\u{00A0}Fahrten · 9 erfasst · 2 verspätet")
        XCTAssertEqual(DelayDiaryText.monthSummary(trips: 1, recorded: 0, late: 0), "1\u{00A0}Fahrt · 0 erfasst")
        XCTAssertEqual(DelayDiaryText.monthSummary(trips: 3, recorded: 3, late: 0), "3\u{00A0}Fahrten · alle erfasst · 0 verspätet")
        XCTAssertEqual(DelayDiaryText.capturedToast(12), "Verspätung +12\u{00A0}Min. übernommen")
        XCTAssertEqual(DelayDiaryText.route(from: "A", to: "B", roundTrip: false, legs: 3), "A → B (3 Etappen)")
    }

    /// A personal log: the caveat cites Punkt 24, and no sentence claims a right or names money.
    func testCopyIsAPersonalLog() {
        XCTAssertEqual(DelayDiaryText.caveat,
                       "Das ist deine persönliche Quote. Für eine Entschädigung zählt laut AGB die Pünktlichkeit der Bahn im Gültigkeitsmonat (Punkt 24), nicht einzelne Verspätungen.")
        XCTAssertTrue(DelayDiaryText.reportCaveat.contains("Punkt 24"))
        let all = [
            DelayDiaryText.caveat, DelayDiaryText.reportCaveat, DelayDiaryText.emptyState, DelayDiaryText.tooFewForShare,
            DelayDiaryText.reportTitle, DelayDiaryText.reportIntro(threshold: 5, scope: .all),
            DelayDiaryText.reportIntro(threshold: 10, scope: .rail), DelayDiaryText.thresholdLine(5),
            DelayDiaryText.shareLine(0.87), DelayDiaryText.capturedToast(0), DelayDiaryText.capturedToast(30),
        ]
        for text in all {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("anspruch"), text)
            XCTAssertFalse(text.contains("€"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("euro"), text)
        }
        XCTAssertTrue(DelayDiaryText.reportIntro(threshold: 10, scope: .rail).contains("10\u{00A0}Minuten"))
        XCTAssertTrue(DelayDiaryText.reportIntro(threshold: 5, scope: .rail).contains("Zug- und S-Bahn-Fahrten"))
    }
}
