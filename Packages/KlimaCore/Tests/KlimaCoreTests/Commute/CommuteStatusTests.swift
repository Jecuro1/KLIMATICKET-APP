import XCTest
@testable import KlimaCore

/// Pendel-Modus: severity thresholds, the rows of the card, the alternative, the spoken sentences and the consent gate.
final class CommuteStatusTests: XCTestCase {
    private typealias F = CommuteFixtures
    private let now = CommuteFixtures.at(2026, 11, 2, 7, 0)

    // MARK: Severity

    func testSeverityBoundaries() {
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: nil, cancelled: false), .scheduled)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: -1, cancelled: false), .onTime)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 0, cancelled: false), .onTime)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 2, cancelled: false), .slight)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 3, cancelled: false), .late)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 9, cancelled: false), .late)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 10, cancelled: false), .veryLate)
        XCTAssertEqual(CommuteStatus.severity(delayMinutes: 0, cancelled: true), .cancelled)
    }

    func testBadgesAlwaysCarryText() {
        XCTAssertEqual(CommuteStatus.badgeText(delayMinutes: 0, cancelled: false), "pünktlich")
        XCTAssertEqual(CommuteStatus.badgeText(delayMinutes: 2, cancelled: false), "+2")
        XCTAssertEqual(CommuteStatus.badgeText(delayMinutes: 12, cancelled: false), "+12")
        XCTAssertEqual(CommuteStatus.badgeText(delayMinutes: -1, cancelled: false), "−1")
        XCTAssertEqual(CommuteStatus.badgeText(delayMinutes: 5, cancelled: true), "Ausfall")
        XCTAssertNil(CommuteStatus.badgeText(delayMinutes: nil, cancelled: false))
    }

    // MARK: Rows

    func testRowsKeepWhatIsAheadInPlannedOrder() {
        let journeys = [F.journey(F.at(2026, 11, 2, 7, 42), delay: 5, number: "162"),
                        F.journey(F.at(2026, 11, 2, 6, 50), delay: 0, number: "160"),            // gone
                        F.journey(F.at(2026, 11, 2, 6, 58), delay: 3, number: "158"),            // left 07:01: still on (grace)
                        F.journey(F.at(2026, 11, 2, 7, 20), delay: nil, number: "164", changedTo: "6")]
        let rows = CommuteStatus.rows(journeys, now: now)
        XCTAssertEqual(rows.map(\.lineTitle), ["RJX 158", "RJX 164", "RJX 162"])
        XCTAssertEqual(rows[2].delayMinutes, 5)
        XCTAssertEqual(rows[2].severity, .late)
        XCTAssertEqual(rows[1].severity, .scheduled)
        XCTAssertEqual(rows[1].platform?.display, "6")
        XCTAssertEqual(rows[1].platform?.changed, true)
        XCTAssertEqual(rows[2].tripID, "trip|162")
    }

    func testACancelledConnectionStaysByItsPlan() {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 10), delay: 0, number: "1", cancelled: true)], now: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isCancelled)
        XCTAssertEqual(rows[0].badgeText, "Ausfall")
        XCTAssertNil(rows[0].delayMinutes)
    }

    func testDataAgeLine() {
        XCTAssertEqual(CommuteStatus.dataAge(fetchedAt: F.at(2026, 11, 2, 7, 31), hasRealtime: true, isOffline: false), "Stand 07:31 · Echtzeit")
        XCTAssertEqual(CommuteStatus.dataAge(fetchedAt: F.at(2026, 11, 2, 7, 31), hasRealtime: false, isOffline: false), "Stand 07:31 · Fahrplan")
        XCTAssertEqual(CommuteStatus.dataAge(fetchedAt: F.at(2026, 11, 2, 7, 31), hasRealtime: true, isOffline: true), "Stand 07:31 · jetzt offline")
        XCTAssertEqual(CommuteStatus.dataAge(fetchedAt: nil, hasRealtime: false, isOffline: true), "ohne Echtzeit (offline)")
    }

    func testEachRowIsOneSpokenElement() {
        let late = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 5)], now: now)[0]
        XCTAssertEqual(CommuteStatus.spoken(late, destination: "Wien Hbf"), "Zug 07:42 nach Wien Hbf, 5 Minuten verspätet, Gleis 4")
        let one = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 1, changedTo: "7")], now: now)[0]
        XCTAssertEqual(CommuteStatus.spoken(one, destination: "Wien Hbf"), "Zug 07:42 nach Wien Hbf, 1 Minute verspätet, Gleis 7, geändert")
        let gone = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), cancelled: true)], now: now)[0]
        XCTAssertEqual(CommuteStatus.spoken(gone, destination: "Wien Hbf"), "Zug 07:42 nach Wien Hbf fällt aus")
        let plan = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: nil, platform: nil)], now: now)[0]
        XCTAssertEqual(CommuteStatus.spoken(plan, destination: "Wien Hbf"), "Zug 07:42 nach Wien Hbf, laut Fahrplan")
    }

    // MARK: Alternative

    func testACancelledTrainPointsToTheNextConnection() throws {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), number: "162", cancelled: true),
                                       F.journey(F.at(2026, 11, 2, 7, 58), delay: 0, number: "164", platform: "3"),
                                       F.journey(F.at(2026, 11, 2, 8, 42), delay: 0, number: "166")], now: now)
        let advice = try XCTUnwrap(CommuteAdvisor.advice(rows: rows, now: now))
        XCTAssertEqual(advice.reason, .cancelled)
        XCTAssertEqual(advice.alternative?.lineTitle, "RJX 164")
        XCTAssertEqual(advice.headline, "Dein Zug fällt aus – nächste Verbindung 07:58, Gleis 3")
    }

    func testABigDelayPointsToAFasterConnection() throws {
        // 07:42 +12 arrives 09:09; the 07:50 (70 min) arrives 09:00 – faster.
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 12, minutes: 75, number: "162"),
                                       F.journey(F.at(2026, 11, 2, 7, 50), delay: 0, minutes: 70, number: "542", platform: "3")], now: now)
        let advice = try XCTUnwrap(CommuteAdvisor.advice(rows: rows, now: now))
        XCTAssertEqual(advice.reason, .delayed(minutes: 12))
        XCTAssertEqual(advice.alternative?.lineTitle, "RJX 542")
        XCTAssertEqual(advice.headline, "Dein Zug ist 12 Minuten verspätet – schneller: 07:50, Gleis 3")
    }

    func testABigDelayWithoutAFasterConnectionSaysSo() throws {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 10, minutes: 75, number: "162"),
                                       F.journey(F.at(2026, 11, 2, 8, 42), delay: 0, minutes: 75, number: "164")], now: now)
        let advice = try XCTUnwrap(CommuteAdvisor.advice(rows: rows, now: now))
        XCTAssertNil(advice.alternative)
        XCTAssertEqual(advice.headline, "Dein Zug ist 10 Minuten verspätet – keine schnellere Verbindung")
    }

    func testNineMinutesNeedNoAdvice() {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 9)], now: now)
        XCTAssertNil(CommuteAdvisor.advice(rows: rows, now: now))
    }

    func testTheAlternativeIsNeverCancelledItself() throws {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), number: "1", cancelled: true),
                                       F.journey(F.at(2026, 11, 2, 7, 58), number: "2", cancelled: true),
                                       F.journey(F.at(2026, 11, 2, 8, 42), delay: 2, number: "3", platform: "5")], now: now)
        let advice = try XCTUnwrap(CommuteAdvisor.advice(rows: rows, now: now))
        XCTAssertEqual(advice.alternative?.lineTitle, "RJX 3")
        XCTAssertEqual(advice.headline, "Dein Zug fällt aus – nächste Verbindung 08:42 (+2), Gleis 5")
    }

    func testABusSaysDeinBus() throws {
        let rows = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), cancelled: true, mode: .bus)], now: now)
        XCTAssertEqual(try XCTUnwrap(CommuteAdvisor.advice(rows: rows, now: now)).headline,
                       "Dein Bus fällt aus – keine weitere Verbindung in dieser Suche")
    }

    // MARK: Speech

    func testSpokenSingularAndPlural() {
        XCTAssertEqual(CommuteSpeech.delayPhrase(0), "pünktlich")
        XCTAssertEqual(CommuteSpeech.delayPhrase(1), "1 Minute verspätet")
        XCTAssertEqual(CommuteSpeech.delayPhrase(7), "7 Minuten verspätet")
        XCTAssertEqual(CommuteSpeech.delayPhrase(-1), "1 Minute früher")
    }

    func testSiriAnswersFromTheRows() {
        let fetched = F.at(2026, 11, 2, 7, 31)
        let onTime = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 0)], now: now)
        XCTAssertEqual(CommuteSpeech.next(rows: onTime, destination: "Wien", fetchedAt: fetched, now: now),
                       "Dein nächster Zug nach Wien fährt um 07:42, pünktlich, von Gleis 4. Stand 07:31.")
        let one = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: 1)], now: now)
        XCTAssertEqual(CommuteSpeech.next(rows: one, destination: "Wien", fetchedAt: fetched, now: now),
                       "Dein nächster Zug nach Wien fährt um 07:42, 1 Minute verspätet, von Gleis 4. Stand 07:31.")
        let cancelled = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), cancelled: true),
                                            F.journey(F.at(2026, 11, 2, 7, 58), delay: 0, number: "164", platform: "3")], now: now)
        XCTAssertEqual(CommuteSpeech.next(rows: cancelled, destination: "Wien", fetchedAt: fetched, now: now),
                       "Dein Zug um 07:42 nach Wien fällt aus. Die nächste Verbindung fährt um 07:58, von Gleis 3. Stand 07:31.")
        let plan = CommuteStatus.rows([F.journey(F.at(2026, 11, 2, 7, 42), delay: nil, platform: nil)], now: now)
        XCTAssertEqual(CommuteSpeech.next(rows: plan, destination: "Wien", fetchedAt: fetched, now: now),
                       "Dein nächster Zug nach Wien fährt laut Fahrplan um 07:42. Stand 07:31.")
        XCTAssertNil(CommuteSpeech.next(rows: [], destination: "Wien", fetchedAt: fetched, now: now))
    }

    func testSiriAnswersFromThePlan() {
        let slot = CommuteSlot(direction: .inbound, departure: F.at(2026, 11, 2, 17, 12))
        XCTAssertEqual(CommuteSpeech.planned(slot: slot, origin: "Linz", destination: "Wien", now: now, calendar: .vienna, hint: .openApp),
                       "Laut deinem Plan fährst du heute um 17:12 von Wien nach Linz. Verspätungen siehst du, wenn du KlimaBilanz öffnest.")
        let monday = CommuteSlot(direction: .outbound, departure: F.at(2026, 11, 9, 7, 20))
        XCTAssertEqual(CommuteSpeech.planned(slot: monday, origin: "Linz", destination: "Wien", now: F.at(2026, 11, 7, 10, 0),
                                             calendar: .vienna, hint: .liveOff),
                       "Laut deinem Plan fährst du am Montag um 07:20 von Linz nach Wien. Live-Daten sind ausgeschaltet, deshalb kenne ich keine Verspätungen.")
    }
}
