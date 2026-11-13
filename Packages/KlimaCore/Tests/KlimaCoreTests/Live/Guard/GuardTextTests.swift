import XCTest
@testable import KlimaCore

/// Anschluss-Wächter: every string of docs/CONNECTION_GUARD.md §8.
final class GuardTextTests: XCTestCase {
    private func at(_ hhmm: String, second: Int = 0) -> Date { GuardFixture.at(hhmm, second: second) }

    /// The card example of the spec: RJX 66 14:31 (+3) on platform 4, REX 2 14:40 (+1) on platform 7 (planned 5), walk 3.
    private func example(state: GuardState = .shaky) -> GuardAssessment {
        GuardAssessment(
            state: state, rawState: state, bufferMinutes: 1, walkMinutes: 3, walkKnown: true, trend: .falling,
            trendReference: GuardSample(at: at("14:23"), minutes: 4), hasTrendHistory: true, stationName: "St. Pölten Hbf",
            feeder: GuardLegFigure(lineName: "RJX 66", planned: at("14:28"), expected: at("14:31"), delayMinutes: 3, platform: "4",
                                   plannedPlatform: "4"),
            connection: GuardLegFigure(lineName: "REX 2", planned: at("14:39"), expected: at("14:40"), delayMinutes: 1, platform: "7",
                                       plannedPlatform: "5", platformChanged: true),
            cancelledLeg: nil, flaggedUnreachable: false, basedOnPlan: false, feederDeparture: at("13:30"), dataAt: at("14:27"), connectionDataAt: at("14:27"),
            laterTransfers: [])
    }

    func testCard() {
        let a = example()
        XCTAssertEqual(GuardText.title(a.stationName), "Anschluss in St. Pölten Hbf")
        XCTAssertEqual(GuardText.arrivalLine(a.feeder), "Ankunft RJX 66 · 14:31 (+3) · Gleis 4")
        XCTAssertEqual(GuardText.departureLine(a.connection), "Abfahrt REX 2 · 14:40 (+1) · Gleis 7")
        XCTAssertEqual(GuardText.walk(a), "Fußweg laut Fahrplan: 3 Min")
        XCTAssertEqual(GuardText.platformChange(a.connection), "Gleis geändert: 5 → 7")
        XCTAssertNil(GuardText.platformChange(a.feeder))
        XCTAssertEqual(GuardText.trend(a, now: at("14:27")), "Wird knapper: vor 4 Min waren es 4 Min")
        var none = a
        none.walkKnown = false
        none.walkMinutes = 0
        XCTAssertEqual(GuardText.walk(none), "Fußweg nicht bekannt")
        var noWalk = a
        noWalk.walkMinutes = 0
        XCTAssertEqual(GuardText.walk(noWalk), "Kein eigener Fußweg laut Fahrplan")
        var scheduled = a.connection
        scheduled.expected = nil
        scheduled.delayMinutes = nil
        XCTAssertEqual(GuardText.legTime(scheduled), "14:39 laut Fahrplan")
        var early = a.feeder
        early.expected = at("14:27")
        early.delayMinutes = -1
        XCTAssertEqual(GuardText.legTime(early), "14:27 (-1)")
        var onTime = a.feeder
        onTime.expected = at("14:28")
        onTime.delayMinutes = 0
        XCTAssertEqual(GuardText.legTime(onTime), "14:28 (pünktlich)")
        var bay = a.connection
        bay.isStand = true
        XCTAssertEqual(GuardText.platform(bay), "Steig 7")
        XCTAssertEqual(GuardText.platformChange(bay), "Steig geändert: 5 → 7")
        var cancelled = a.connection
        cancelled.isCancelled = true
        XCTAssertEqual(GuardText.legTime(cancelled), "14:39 · fällt aus")
    }

    func testChips() {
        XCTAssertEqual(GuardState.allCases.map(GuardText.chip), ["Sicher", "Wird knapper", "Wackelt", "Wahrscheinlich verpasst", "Verpasst",
                                                                 "Fällt aus", "Nach Fahrplan", "Umstieg vorbei"])
    }

    func testHeadlines() {
        var a = example()
        func line(_ buffer: Int) -> String {
            a.bufferMinutes = buffer
            return GuardText.headline(a).full
        }
        XCTAssertEqual(line(6), "6 Min zum Umsteigen")
        XCTAssertEqual(line(1), "1 Min zum Umsteigen")
        XCTAssertEqual(line(0), "0 Min zum Umsteigen")
        XCTAssertEqual(line(-1), "Es fehlt dir 1 Min")
        XCTAssertEqual(line(-4), "Es fehlen dir 4 Min")
        a.bufferMinutes = -4
        let h = GuardText.headline(a)
        XCTAssertEqual(h.prefix, "Es fehlen dir")
        XCTAssertEqual(h.number, "4")
        XCTAssertEqual(h.suffix, "Min")
        a.state = .cancelled
        a.cancelledLeg = .connection
        XCTAssertEqual(GuardText.headline(a).full, "REX 2 fällt aus")
        XCTAssertNil(GuardText.headline(a).number)
        a.cancelledLeg = .feeder
        XCTAssertEqual(GuardText.headline(a).full, "RJX 66 fällt aus")
        a.state = .over
        a.rawState = .over
        a.cancelledLeg = nil
        XCTAssertEqual(GuardText.headline(a).full, "REX 2 ist abgefahren")
    }

    func testTrendTexts() {
        var a = example()
        a.bufferMinutes = 6
        a.trendReference = GuardSample(at: at("14:23"), minutes: 9)
        XCTAssertEqual(GuardText.trend(a, now: at("14:27")), "Wird knapper: vor 4 Min waren es 9 Min")
        a.trend = .steady
        XCTAssertEqual(GuardText.trend(a, now: at("14:27")), "Gleichbleibend")
        a.trend = .rising
        a.trendReference = GuardSample(at: at("14:24"), minutes: 2)
        XCTAssertEqual(GuardText.trend(a, now: at("14:27")), "Entspannt sich: vor 3 Min waren es 2 Min")
        a.hasTrendHistory = false
        XCTAssertNil(GuardText.trend(a, now: at("14:27")), "one answer is no trend")
    }

    func testNotes() {
        var a = example(state: .missed)
        a.bufferMinutes = -2
        XCTAssertEqual(GuardText.missedNote(a), "REX 2 ist laut Prognose um 14:40 abgefahren.")
        a.connection.expected = nil
        XCTAssertEqual(GuardText.missedNote(a), "REX 2 ist laut Fahrplan um 14:39 abgefahren.")
        XCTAssertNil(GuardText.missedNote(example()))
        XCTAssertEqual(GuardText.unreachableNote, "Die ÖBB-Auskunft markiert den Anschluss als nicht erreichbar.")
        XCTAssertEqual(GuardText.noRealtimeNote, "Keine Echtzeit-Daten: gerechnet nach Fahrplan.")
        XCTAssertEqual(GuardText.laterTransfer(GuardLaterTransfer(stationName: "Wiener Neustadt Hbf", plannedBufferMinutes: 12)),
                       "Danach: Umstieg in Wiener Neustadt Hbf, 12 Min laut Fahrplan")
    }

    func testStatusLines() {
        let now = at("14:27", second: 10)
        XCTAssertEqual(GuardText.status(.updated(at: at("14:27"), next: at("14:28")), now: now), "Stand 14:27 · nächste Prüfung in 1 Min")
        XCTAssertEqual(GuardText.status(.updated(at: at("14:27"), next: at("14:29")), now: now), "Stand 14:27 · nächste Prüfung in 2 Min")
        XCTAssertEqual(GuardText.status(.lowPower(lastAt: nil), now: now), "Stromspar-Modus: keine automatische Prüfung.")
        XCTAssertEqual(GuardText.status(.switchedOff, now: now), "Wächter für diese Fahrt aus.")
        XCTAssertEqual(GuardText.status(.offline(lastAt: at("14:21")), now: now), "Ohne Internet keine Prüfung. Gezeigt ist der Stand von 14:21.")
        XCTAssertEqual(GuardText.status(.liveOff, now: now), "Für die Prüfung braucht es Live-Daten.")
        XCTAssertEqual(GuardText.status(.beforeWindow(lastAt: nil, start: at("13:50")), now: now), "Automatische Prüfung ab 13:50")
        XCTAssertEqual(GuardText.status(.ended(lastAt: at("14:43")), now: now), "Stand 14:43 · Prüfung beendet")
        XCTAssertEqual(GuardText.status(.checking(lastAt: at("14:25")), now: now), "Stand 14:25 · Prüfe gerade …")
        XCTAssertEqual(GuardText.status(.failed(lastAt: at("14:25"), retry: at("14:28")), now: now),
                       "Stand 14:25 · Die Auskunft antwortet gerade nicht · neuer Versuch in 1 Min")
    }

    func testButtonsAndFooter() {
        XCTAssertEqual(GuardText.alternativesButton, "Alternativen ansehen")
        XCTAssertEqual(GuardText.alarmButton, "Wecker fürs Umsteigen")
        XCTAssertEqual(GuardText.checkButton, "Jetzt prüfen")
        XCTAssertEqual(GuardText.switchOff, "Wächter aus")
        XCTAssertEqual(GuardText.switchOn, "Wächter an")
        XCTAssertTrue(GuardText.footerOpenOnly.hasPrefix("KlimaBilanz prüft deinen Anschluss nur, solange die App offen ist."))
        XCTAssertTrue(GuardText.footerOpenOnly.contains("„Anschluss knapp“"))
        XCTAssertTrue(GuardText.footerOpenOnly.hasSuffix("Das ist nicht garantiert."))
        XCTAssertEqual(GuardText.footerNoWaiting,
                       "Ob ein Zug wartet, sagt die Auskunft nicht. Die Einschätzung rechnet mit den Prognosen beider Züge.")
    }

    func testVoiceOverSentence() {
        let a = example()
        XCTAssertEqual(GuardText.accessibility(a, now: at("14:27")),
                       "Anschluss in St. Pölten Hbf: wackelt, 1 Minute zum Umsteigen, wird knapper. Ankunft RJX 66 um 14 Uhr 31, "
                       + "3 Minuten später. Abfahrt REX 2 um 14 Uhr 40, 1 Minute später, Gleis 7. Fußweg 3 Minuten. Gleis geändert: 5 auf 7.")
        XCTAssertEqual(GuardText.spokenTime(at("09:05")), "9 Uhr 5")
        XCTAssertEqual(GuardText.spokenTime(at("14:00")), "14 Uhr")
        var short = example(state: .likelyMissed)
        short.bufferMinutes = -4
        short.connection.platformChanged = false
        XCTAssertTrue(GuardText.accessibility(short, now: at("14:27")).hasPrefix("Anschluss in St. Pölten Hbf: wahrscheinlich verpasst, es fehlen dir 4 Minuten"))
        var tighter = example(state: .tighter)
        tighter.bufferMinutes = 6
        XCTAssertTrue(GuardText.accessibility(tighter, now: at("14:27")).hasPrefix("Anschluss in St. Pölten Hbf: wird knapper, 6 Minuten zum Umsteigen. "),
                      "the trend is not said twice")
    }

    func testToastsAndBadges() {
        var a = example()
        let toasts: [(GuardState, String?)] = [
            (.tighter, "Anschluss in St. Pölten wird knapper"), (.shaky, "Anschluss in St. Pölten wackelt"),
            (.likelyMissed, "Anschluss in St. Pölten wahrscheinlich verpasst"), (.missed, "Anschluss in St. Pölten verpasst"),
            (.safe, nil), (.scheduled, nil), (.over, nil),
        ]
        for (state, text) in toasts {
            a.state = state
            XCTAssertEqual(GuardText.toast(a), text)
        }
        a.state = .cancelled
        a.cancelledLeg = .connection
        XCTAssertEqual(GuardText.toast(a), "REX 2 fällt aus")
        XCTAssertEqual(GuardText.shortStation("St.Pölten Hbf"), "St. Pölten")
        XCTAssertEqual(GuardText.shortStation("Wien Hauptbahnhof"), "Wien")
        XCTAssertEqual(GuardText.shortStation("Amstetten"), "Amstetten")

        XCTAssertEqual(GuardState.allCases.map(GuardText.badge), ["", "Anschluss wird knapper", "Anschluss wackelt",
                                                                  "Anschluss wahrscheinlich verpasst", "Anschluss verpasst",
                                                                  "Anschluss fällt aus", "", ""].map { $0.isEmpty ? nil : $0 })
        XCTAssertEqual(GuardState.allCases.map(GuardText.badgeCompact), [nil, "knapper", "wackelt", "wohl verpasst", "verpasst",
                                                                         "fällt aus", nil, nil])
    }

    func testAlternativesTexts() {
        XCTAssertEqual(GuardText.alternativesTitle("St.Pölten Hbf"), "Weiter ab St. Pölten Hbf")
        XCTAssertEqual(GuardText.alternativesSubtitle(destination: "Wiener Neustadt Hbf", from: at("14:42")), "Nach Wiener Neustadt Hbf · ab 14:42")
        let leg = Leg(id: "x", kind: .ride, origin: GuardFixture.stPoelten, destination: GuardFixture.neustadt,
                      departure: StopEvent(planned: at("14:52"), plannedPlatform: Platform(text: "3", kind: .track)),
                      arrival: StopEvent(planned: at("16:10")), line: GuardFixture.rex)
        let j = Journey(legs: [leg], changes: 1)
        XCTAssertEqual(GuardText.alternativeDeparture(j), "ab 14:52 · Gleis 3")
        XCTAssertEqual(GuardText.alternativeArrival(j), "an 16:10")
        XCTAssertEqual(GuardText.changes(j), "1 Umstieg")
        XCTAssertEqual(GuardText.followButton, "Verfolgen")
        XCTAssertEqual(GuardText.followButtonSpoken, "Diese Verbindung live verfolgen")
        XCTAssertEqual(GuardText.plannerButton, "Im Fahrplan öffnen")
        XCTAssertEqual(GuardText.alternativesTip, "Tipp: Mit „Verfolgen“ prüft KlimaBilanz auch den neuen Umstieg.")
        XCTAssertEqual(GuardText.alternativesLoading, "Suche Verbindungen …")
        XCTAssertEqual(GuardText.alternativesEmpty, "Die Auskunft kennt gerade keine passende Verbindung. Sieh im Fahrplan nach.")
        XCTAssertEqual(GuardText.plannerSearchButton, "Im Fahrplan suchen")
        XCTAssertEqual(GuardText.alternativesFooter(klimaTicketOnly: true),
                       "Eine Suche bei der ÖBB-Auskunft, gesucht wie im Fahrplan (Nur mit KlimaTicket gültig: an).")
        XCTAssertEqual(GuardText.alternativesFooter(klimaTicketOnly: false),
                       "Eine Suche bei der ÖBB-Auskunft, gesucht wie im Fahrplan (Nur mit KlimaTicket gültig: aus).")
    }

    /// Honesty: no string claims that a train waits or that a connection is secured; the only „wartet“ is the footer
    /// sentence that says the Auskunft does not tell.
    func testNoClaimThatATrainWaits() {
        var strings = GuardState.allCases.map(GuardText.chip) + GuardState.allCases.compactMap(GuardText.badge)
        strings += [GuardText.footerOpenOnly, GuardText.unreachableNote, GuardText.noRealtimeNote, GuardText.overNote,
                    GuardText.alternativesTip, GuardText.alternativesEmpty, GuardText.alternativesFailed]
        for state in GuardState.allCases {
            var a = example(state: state)
            a.rawState = state
            strings.append(GuardText.accessibility(a, now: at("14:27")))
            strings.append(GuardText.headline(a).full)
            if let t = GuardText.toast(a) { strings.append(t) }
        }
        for s in strings {
            XCTAssertFalse(s.lowercased().contains("wartet"), s)
            XCTAssertFalse(s.lowercased().contains("gesichert"), s)
            XCTAssertFalse(s.contains("GPS"), s)
        }
        XCTAssertTrue(GuardText.footerNoWaiting.hasPrefix("Ob ein Zug wartet, sagt die Auskunft nicht."))
    }
}
