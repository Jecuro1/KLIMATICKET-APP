import XCTest
@testable import KlimaCore

/// Smart Stack relevance, the lock-screen inline text, the privacy flags and the small Live Activity line
/// (docs/WIDGETS_SMARTSTACK.md). Pure logic, no network.
final class WidgetSmartStackTests: XCTestCase {
    let cal = Calendar.vienna

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    // MARK: Relevance – departures

    func testDepartureRelevanceAroundTheWindow() {
        let departure = at(2026, 11, 13, 7, 42)
        func score(_ minutes: Double) -> Double {
            WidgetRelevance.departure(now: departure.addingTimeInterval(minutes * 60), nextDeparture: departure)
        }
        XCTAssertEqual(score(-60), 0)                 // an hour before: not yet
        XCTAssertEqual(score(-45), 100)               // the window opens 45 minutes before
        XCTAssertEqual(score(-45.02), 0)              // a second earlier it is still closed
        XCTAssertEqual(score(-1), 100)
        XCTAssertEqual(score(0), 100)
        XCTAssertEqual(score(1), 80, accuracy: 0.0001)  // decaying after the departure
        XCTAssertEqual(score(2.5), 50, accuracy: 0.0001)
        XCTAssertEqual(score(5), 0)
        XCTAssertEqual(score(30), 0)
    }

    func testDepartureRelevanceWithoutDepartureIsZero() {
        XCTAssertEqual(WidgetRelevance.departure(now: at(2026, 11, 13), nextDeparture: nil), 0)
    }

    func testDepartureChangeDatesAddTheLeadAndTheDecayEnd() {
        let now = at(2026, 11, 13, 7, 0)
        let first = at(2026, 11, 13, 7, 30)   // lead (6:45) already passed
        let second = at(2026, 11, 13, 8, 40)  // lead at 7:55
        let dates = WidgetRelevance.departureChangeDates([second, first], now: now)
        XCTAssertEqual(dates, [at(2026, 11, 13, 7, 35), at(2026, 11, 13, 7, 55), at(2026, 11, 13, 8, 45)])
        XCTAssertEqual(WidgetRelevance.departureChangeDates([second, first], now: now, limit: 1), [at(2026, 11, 13, 7, 35)])
        XCTAssertTrue(WidgetRelevance.departureChangeDates([], now: now).isEmpty)
    }

    func testMergedDatesKeepTheBaseAndFillTheRest() {
        let a = at(2026, 11, 13, 7, 0), b = at(2026, 11, 13, 7, 10), c = at(2026, 11, 13, 7, 20), d = at(2026, 11, 13, 7, 30)
        XCTAssertEqual(WidgetRelevance.merged([a, c], [b, d, c], limit: 3), [a, b, c])
        XCTAssertEqual(WidgetRelevance.merged([a, c], [b, d], limit: 8), [a, b, c, d])
        // The base wins when room runs out.
        XCTAssertEqual(WidgetRelevance.merged([a, b, c], [d], limit: 3), [a, b, c])
    }

    // MARK: Relevance – ticket and break-even

    func testTicketRelevanceInTheLastFourteenDays() {
        let validUntil = at(2026, 12, 31, 23, 59, 59)   // the ticket's last day
        func score(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Double {
            WidgetRelevance.ticketRemaining(now: at(y, m, d, h), validUntil: validUntil)
        }
        XCTAssertEqual(score(2026, 12, 1), 0)
        XCTAssertEqual(score(2026, 12, 17, 23), 0)      // 14 days ahead: not yet among the last 14
        XCTAssertEqual(score(2026, 12, 18, 0), 30)      // the first of the last 14 days, from midnight
        XCTAssertEqual(score(2026, 12, 31, 23), 30)     // the last day
        XCTAssertEqual(score(2027, 1, 1, 0), 0)         // expired
        XCTAssertEqual(WidgetRelevance.ticketRemaining(now: at(2026, 12, 20), validUntil: nil), 0)
    }

    func testBreakEvenRelevanceOnlyOnItsDay() {
        let forecast = at(2026, 12, 14, 9)
        XCTAssertEqual(WidgetRelevance.breakEven(now: at(2026, 12, 13, 23, 59), breakEvenDate: forecast), 0)
        XCTAssertEqual(WidgetRelevance.breakEven(now: at(2026, 12, 14, 0, 0), breakEvenDate: forecast), 60)
        XCTAssertEqual(WidgetRelevance.breakEven(now: at(2026, 12, 14, 23, 59), breakEvenDate: forecast), 60)
        XCTAssertEqual(WidgetRelevance.breakEven(now: at(2026, 12, 15, 0, 0), breakEvenDate: forecast), 0)
        XCTAssertEqual(WidgetRelevance.breakEven(now: forecast, breakEvenDate: nil), 0)
    }

    func testCombinedScoreIsTheHighest() {
        let now = at(2026, 12, 20, 7, 0)
        XCTAssertEqual(WidgetRelevance.score(now: now, nextDeparture: at(2026, 12, 20, 7, 20),
                                             validUntil: at(2026, 12, 31, 23, 59), breakEvenDate: now), 100)
        XCTAssertEqual(WidgetRelevance.score(now: now, nextDeparture: nil,
                                             validUntil: at(2026, 12, 31, 23, 59), breakEvenDate: now), 60)
        XCTAssertEqual(WidgetRelevance.score(now: now, nextDeparture: nil,
                                             validUntil: at(2026, 12, 31, 23, 59), breakEvenDate: nil), 30)
        XCTAssertEqual(WidgetRelevance.score(now: now, nextDeparture: nil, validUntil: nil, breakEvenDate: nil), 0)
    }

    // MARK: Inline text

    private let nbsp = "\u{00A0}"

    func testInlineTextWordings() {
        XCTAssertEqual(InlineAmortizationText.text(.unpaid(remaining: 142)), "€\(nbsp)142 bis zum Ziel")
        XCTAssertEqual(InlineAmortizationText.text(.paid(profit: 37)), "Lohnt sich · +€\(nbsp)37")
        XCTAssertEqual(InlineAmortizationText.text(.unpaid(remaining: 1_300)), "€\(nbsp)1.300 bis zum Ziel")
        XCTAssertEqual(InlineAmortizationText.text(.paid(profit: 1_456)), "Lohnt sich · +€\(nbsp)1.456")
        XCTAssertEqual(InlineAmortizationText.text(.expired), "Ticket abgelaufen")
        XCTAssertEqual(InlineAmortizationText.text(.noTicket), "Kein Ticket erfasst")
    }

    func testInlineTextStaysWithinTwentyTwoCharacters() {
        let amounts: [Double] = [0, 0.4, 1, 9, 37, 142, 999, 1_000, 9_999, 12_345, 99_999, 123_456, 1_234_567,
                                 987_654_321, 1e12, 1e18, -50, .nan, .infinity]
        for amount in amounts {
            for state in [InlineAmortizationText.State.unpaid(remaining: amount), .paid(profit: amount)] {
                let text = InlineAmortizationText.text(state)
                XCTAssertLessThanOrEqual(text.count, InlineAmortizationText.maxLength, "\(state): \(text)")
                XCTAssertFalse(text.isEmpty)
            }
        }
        for state in [InlineAmortizationText.State.expired, .noTicket] {
            XCTAssertLessThanOrEqual(InlineAmortizationText.text(state).count, InlineAmortizationText.maxLength)
        }
    }

    func testInlineTextFallsBackToShorterWordings() {
        // "€ 123.456 bis zum Ziel" is exactly 22 characters; one more digit needs the short form.
        XCTAssertEqual(InlineAmortizationText.text(.unpaid(remaining: 123_456)), "€\(nbsp)123.456 bis zum Ziel")
        XCTAssertEqual(InlineAmortizationText.text(.unpaid(remaining: 1_234_567)), "noch €\(nbsp)1.234.567")
        XCTAssertEqual(InlineAmortizationText.text(.paid(profit: 12_345)), "Lohnt sich · +€\(nbsp)12.345")
        XCTAssertEqual(InlineAmortizationText.text(.paid(profit: 123_456)), "Im Plus · +€\(nbsp)123.456")
        XCTAssertEqual(InlineAmortizationText.text(.unpaid(remaining: -5)), "€\(nbsp)0 bis zum Ziel")
    }

    func testInlineStateOrder() {
        XCTAssertEqual(InlineAmortizationText.state(hasTicket: false, isExpired: true, isPaidOff: true, remaining: 0, profit: 5),
                       .noTicket)
        XCTAssertEqual(InlineAmortizationText.state(hasTicket: true, isExpired: true, isPaidOff: true, remaining: 0, profit: 5),
                       .expired)
        XCTAssertEqual(InlineAmortizationText.state(hasTicket: true, isExpired: false, isPaidOff: true, remaining: 0, profit: 5),
                       .paid(profit: 5))
        XCTAssertEqual(InlineAmortizationText.state(hasTicket: true, isExpired: false, isPaidOff: false, remaining: 354, profit: 0),
                       .unpaid(remaining: 354))
    }

    func testInlineSpokenTexts() {
        XCTAssertEqual(InlineAmortizationText.spoken(.unpaid(remaining: 1_354)), "Noch 1.354 Euro bis zum Ticketpreis")
        XCTAssertEqual(InlineAmortizationText.spoken(.paid(profit: 37)), "Ticket lohnt sich, 37 Euro im Plus")
    }

    // MARK: Privacy flags

    func testPrivacyDefaults() {
        XCTAssertTrue(WidgetPrivacy.standard.hidesRoutes)
        XCTAssertFalse(WidgetPrivacy.standard.hidesAmounts)
        XCTAssertTrue(WidgetPrivacy.standard.hides(.route))
        XCTAssertFalse(WidgetPrivacy.standard.hides(.amount))
        XCTAssertEqual(WidgetPrivacy.standard.resolved,
                       WidgetPrivacy(hidesRoutesWhenLocked: true, hidesAmountsWhenLocked: false))
    }

    /// A snapshot as the app wrote it before the flags existed (`widgetSnapshot.v1`, every field of 1.1).
    private let oldSnapshotJSON = """
    {"generatedAt":784900000,"ticketName":"KlimaTicket Ö Klassik","ticketPrice":1300,"totalValue":946.4,
     "amortizedFraction":0.728,"tripCount":87,"distanceKm":4812,"co2SavedKg":612,"daysRemaining":143,
     "validUntil":797000000,"isPaidOff":false,"forecastBreakEvenDate":790600000,
     "lastTrip":{"fromName":"St. Anton am Arlberg","toName":"Innsbruck Hbf","modeSymbol":"train.side.front.car","value":22.8,"date":784900000},
     "favorites":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Arbeit","modeSymbol":"train.side.front.car","value":22.8,
                   "distanceKm":104,"fromName":"Landeck-Zams","toName":"Innsbruck Hbf"}],
     "sparkline":[0,40,88],"heat":[0,1,2]}
    """

    func testOldSnapshotDecodesAsDefaults() throws {
        let privacy = try XCTUnwrap(WidgetPrivacy.fromSnapshotJSON(Data(oldSnapshotJSON.utf8)))
        XCTAssertEqual(privacy, .standard)
        XCTAssertTrue(privacy.hidesRoutes)
        XCTAssertFalse(privacy.hidesAmounts)
    }

    func testNewSnapshotCarriesTheFlags() throws {
        let json = oldSnapshotJSON.dropLast() + #","hidesRoutesWhenLocked":false,"hidesAmountsWhenLocked":true}"#
        let privacy = try XCTUnwrap(WidgetPrivacy.fromSnapshotJSON(Data(json.utf8)))
        XCTAssertFalse(privacy.hidesRoutes)
        XCTAssertTrue(privacy.hidesAmounts)
    }

    func testPrivacyRoundTripsWithTheSnapshotKeys() throws {
        let data = try JSONEncoder().encode(WidgetPrivacy(hidesRoutesWhenLocked: false, hidesAmountsWhenLocked: true))
        let object = try JSONDecoder().decode([String: Bool].self, from: data)
        XCTAssertEqual(object, ["hidesRoutesWhenLocked": false, "hidesAmountsWhenLocked": true])
        XCTAssertEqual(WidgetPrivacy.fromSnapshotJSON(Data("[]".utf8)), nil)
    }

    func testStoredChoiceWinsFieldByField() {
        let stored = WidgetPrivacy(hidesRoutesWhenLocked: false, hidesAmountsWhenLocked: nil)
        let snapshot = WidgetPrivacy(hidesRoutesWhenLocked: true, hidesAmountsWhenLocked: true)
        let resolved = WidgetPrivacy.resolve(stored: stored, snapshot: snapshot)
        XCTAssertFalse(resolved.hidesRoutes)
        XCTAssertTrue(resolved.hidesAmounts)
        XCTAssertEqual(WidgetPrivacy.resolve(stored: nil, snapshot: nil), .standard)
        XCTAssertEqual(WidgetPrivacy.resolve(stored: nil, snapshot: snapshot), snapshot)
    }

    // MARK: Small Live Activity line (Apple Watch Smart Stack)

    func testFollowBeforeDepartureShowsPlannedTimeAndDelay() {
        let line = ActivitySmallText.follow(lineName: "RJX 66", alightName: "Wien Hauptbahnhof", stage: .beforeDeparture,
                                            plannedDeparture: at(2026, 11, 13, 7, 42), plannedArrival: at(2026, 11, 13, 10, 12),
                                            nextStopTime: at(2026, 11, 13, 7, 45), delayMinutes: 5, transferStation: nil,
                                            transferDeparture: nil, updatedAt: at(2026, 11, 13, 7, 30), isStale: false)
        XCTAssertEqual(line.headline, "RJX 66 07:42 +3")
        XCTAssertEqual(line.delay, "+3")
        XCTAssertEqual(line.destination, "Wien Hbf")
        XCTAssertEqual(line.countdownTarget, at(2026, 11, 13, 7, 45))
        XCTAssertEqual(line.countdownLabel, "Abfahrt in")
        XCTAssertNil(line.footnote)
        XCTAssertEqual(line.spoken, "RJX 66 nach Wien Hbf, Abfahrt um 07:45, 3 Minuten später.")
    }

    func testFollowRidingCountsToTheArrival() {
        let line = ActivitySmallText.follow(lineName: "S 4", alightName: "Feldkirch Bahnhof", stage: .riding,
                                            plannedDeparture: nil, plannedArrival: at(2026, 11, 13, 8, 10),
                                            nextStopTime: nil, delayMinutes: 0, transferStation: nil, transferDeparture: nil,
                                            updatedAt: nil, isStale: false)
        XCTAssertEqual(line.headline, "S 4 08:10")
        XCTAssertNil(line.delay)
        XCTAssertEqual(line.destination, "Feldkirch Bf")
        XCTAssertEqual(line.countdownTarget, at(2026, 11, 13, 8, 10))
        XCTAssertEqual(line.spoken, "S 4 nach Feldkirch Bf, Ankunft um 08:10, pünktlich.")
    }

    func testFollowStaleSaysStand() {
        let line = ActivitySmallText.follow(lineName: "Railjet Xpress 166", alightName: "Salzburg Hbf", stage: .riding,
                                            plannedDeparture: nil, plannedArrival: at(2026, 11, 13, 9, 0), nextStopTime: nil,
                                            delayMinutes: 12, transferStation: nil, transferDeparture: nil,
                                            updatedAt: at(2026, 11, 13, 7, 40), isStale: true)
        XCTAssertEqual(line.headline, "Zug 09:00 +12")   // a long line name gives way to the mode word
        XCTAssertEqual(line.footnote, "Stand 07:40")
        XCTAssertTrue(line.spoken.hasSuffix("Stand 07:40, keine aktuellen Daten."))
        XCTAssertEqual(line.countdownTarget, at(2026, 11, 13, 9, 12))
    }

    func testFollowEndStatesHaveNoCountdown() {
        for stage in [FollowStage.arrived, .cancelled] {
            let line = ActivitySmallText.follow(lineName: "RJX 66", alightName: "Wien Hbf", stage: stage, plannedDeparture: nil,
                                                plannedArrival: nil, nextStopTime: nil, delayMinutes: nil, transferStation: nil,
                                                transferDeparture: nil, updatedAt: nil, isStale: false)
            XCTAssertNil(line.countdownTarget)
        }
        let cancelled = ActivitySmallText.follow(lineName: "RJX 66", alightName: "Wien Hbf", stage: .cancelled,
                                                 plannedDeparture: nil, plannedArrival: nil, nextStopTime: nil,
                                                 delayMinutes: nil, transferStation: nil, transferDeparture: nil,
                                                 updatedAt: nil, isStale: false)
        XCTAssertEqual(cancelled.headline, "RJX 66 fällt aus")
    }

    func testRideWithAndWithoutArrival() {
        let start = at(2026, 11, 13, 7, 42)
        let counting = ActivitySmallText.ride(modeName: "Zug", lineLabel: nil, toName: "Innsbruck Hauptbahnhof",
                                              startedAt: start, expectedArrival: nil, phase: .riding, isStale: false,
                                              endedAt: nil)
        XCTAssertEqual(counting.headline, "Zug 07:42")
        XCTAssertEqual(counting.destination, "Innsbruck Hbf")
        XCTAssertTrue(counting.countsUp)
        XCTAssertEqual(counting.countdownTarget, start)

        let arriving = ActivitySmallText.ride(modeName: "Zug", lineLabel: "RJX 662", toName: "Innsbruck Hbf",
                                              startedAt: start, expectedArrival: at(2026, 11, 13, 8, 30), phase: .riding,
                                              isStale: false, endedAt: nil)
        XCTAssertEqual(arriving.headline, "RJX 662 07:42")
        XCTAssertFalse(arriving.countsUp)
        XCTAssertEqual(arriving.countdownLabel, "Ankunft in")

        let stale = ActivitySmallText.ride(modeName: "Zug", lineLabel: nil, toName: "Innsbruck Hbf", startedAt: start,
                                           expectedArrival: at(2026, 11, 13, 8, 30), phase: .riding, isStale: true, endedAt: nil)
        XCTAssertEqual(stale.footnote, "Noch nicht gespeichert")
        XCTAssertTrue(stale.countsUp)
    }

    func testDelayBadges() {
        XCTAssertEqual(ActivitySmallText.delayBadge(3), "+3")
        XCTAssertNil(ActivitySmallText.delayBadge(0))
        XCTAssertEqual(ActivitySmallText.delayBadge(-2), "\u{2212}2")
        XCTAssertEqual(ActivitySmallText.departureDelay(planned: at(2026, 11, 13, 7, 42), effective: at(2026, 11, 13, 7, 44, 40)), 3)
        XCTAssertNil(ActivitySmallText.departureDelay(planned: nil, effective: at(2026, 11, 13, 7, 44)))
    }
}
