import XCTest
@testable import KlimaCore

/// SPEC §C3.4 / §D2 WP-C 6: connection cards against `FX/ux/vm_trips_*.json` and `vm_board_innsbruck_hbf.json`.
final class JourneyPresentationTests: XCTestCase {
    /// Before every connection of the fixtures (2026-10-09).
    let morning = Vienna.date("2026-10-09 06:00")

    func testInnsbruckLechCardMatchesGolden() throws {
        let journeys = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys
        let s = JourneyPresentation.summaries(journeys, now: morning)[0]
        let g = try VM.connections("vm_trips_innsbruck_lech")[0]

        let bar = try XCTUnwrap(g["bar"] as? [[String: Any]])
        XCTAssertEqual(s.bar.map(\.kind.rawValue), bar.map { $0["kind"] as! String })
        XCTAssertEqual(s.bar.map(\.minutes), [76, 1, 37, 22])
        XCTAssertEqual(s.bar.map(\.minutes), bar.map { $0["minutes"] as! Int })
        for (seg, gs) in zip(s.bar, bar) {
            XCTAssertEqual(seg.fraction, gs["fraction"] as! Double, accuracy: 0.0005)
        }
        XCTAssertEqual(s.bar.reduce(0) { $0 + $1.fraction }, 1, accuracy: 0.001)
        XCTAssertEqual(s.bar.map(\.plate), ["RJX", nil, nil, "750"])
        XCTAssertEqual(s.bar.map(\.mode), [.train, nil, nil, .bus])

        XCTAssertEqual(s.transfers, [TransferInfo(stationName: "Langen am Arlberg", walkMinutes: 1, bufferMinutes: 37, risk: .ok,
                                                  text: "38 min Umstiegszeit")])
        XCTAssertEqual(s.notices.first?.severity, .crowd)
        XCTAssertEqual(s.topNotice?.severity, .crowd)
        XCTAssertEqual(s.topNotice?.title, "Andere Zuggarnitur, verringertes Platzangebot der 2. Klasse")
        XCTAssertEqual(s.topNotice?.priority, 100)
        XCTAssertEqual(s.metaLine, "ab Gl. 3 · 1 Umstieg · Langen am Arlberg")
        XCTAssertEqual(s.metaLine, g["metaLine"] as? String)
        XCTAssertEqual(s.durationText, "2 h 16 min")
        XCTAssertEqual(s.durationMinutes, 136)
        XCTAssertEqual(s.changesText, "1 Umstieg")
        XCTAssertEqual(s.changeStations, ["Langen am Arlberg"])
        XCTAssertEqual(s.lineSummary, "RJX 19960 · Bus 750")
        XCTAssertNil(s.viaText)
        VM.assert(s.departurePlatform, (g["dep"] as? [String: Any])?["platform"] as? [String: Any], "dep platform")
        XCTAssertEqual(s.departurePlatform?.text, "Gl. 3")
        XCTAssertFalse(s.isPast)
        XCTAssertFalse(s.isCancelled)
        XCTAssertEqual(s.id, journeys[0].id)

        // Detail chips: golden order (alphabetical), capped at 6 by the chip table order (Businessabteil drops out).
        let legs = try XCTUnwrap(g["legs"] as? [[String: Any]])
        let goldenChips = try XCTUnwrap(legs[0]["attributes"] as? [String])
        XCTAssertEqual(JourneyPresentation.attributes(journeys[0].legs[0].remarks, limit: nil), goldenChips)
        let capped = JourneyPresentation.attributes(journeys[0].legs[0].remarks)
        XCTAssertEqual(capped, ["bicycle", "figure.2.and.child.holdinghands", "figure.roll", "fork.knife", "moon", "wifi"])
        XCTAssertEqual(capped, goldenChips.filter(capped.contains), "same relative order as the golden")
        XCTAssertEqual(JourneyPresentation.attributes(journeys[0].legs[2].remarks), [])
    }

    /// Every connection of the three trips goldens: times, states, texts, bar, transfers, meta line, platforms, tags.
    func testAllTripsGoldens() throws {
        for (vm, scenario) in VM.trips {
            let journeys = try CoverageFixtures.page(scenario).journeys
            let cards = JourneyPresentation.summaries(journeys, now: morning)
            let golden = try VM.connections(vm)
            XCTAssertEqual(cards.count, golden.count, vm)
            for (i, (s, g)) in zip(cards, golden).enumerated() {
                let ctx = "\(vm)[\(i)]"
                let dep = try XCTUnwrap(g["dep"] as? [String: Any]), arr = try XCTUnwrap(g["arr"] as? [String: Any])
                XCTAssertEqual(s.plannedDeparture.map(RealtimePresentation.time), dep["planned"] as? String, ctx)
                XCTAssertEqual(s.plannedArrival.map(RealtimePresentation.time), arr["planned"] as? String, ctx)
                VM.assert(s.departure, dep, ctx)
                VM.assert(s.arrival, arr, ctx)
                VM.assert(s.departurePlatform, dep["platform"] as? [String: Any], ctx)
                XCTAssertEqual(s.durationMinutes, g["durationMin"] as? Int, ctx)
                XCTAssertEqual(s.durationText, g["durationText"] as? String, ctx)
                XCTAssertEqual(s.changes, g["changes"] as? Int, ctx)
                XCTAssertEqual(s.changesText, g["changesText"] as? String, ctx)
                XCTAssertEqual(s.metaLine, g["metaLine"] as? String, ctx)
                XCTAssertEqual(s.changeStations, g["via"] as? [String], ctx)
                let bar = try XCTUnwrap(g["bar"] as? [[String: Any]])
                XCTAssertEqual(s.bar.map(\.kind.rawValue), bar.map { $0["kind"] as! String }, ctx)
                XCTAssertEqual(s.bar.map(\.minutes), bar.map { $0["minutes"] as! Int }, ctx)
                for (seg, gs) in zip(s.bar, bar) {
                    XCTAssertEqual(seg.fraction, gs["fraction"] as! Double, accuracy: 0.0005, ctx)
                    if let plate = gs["plate"] as? String {
                        XCTAssertEqual(seg.plate, VM.badgePlate(plate, mode: gs["mode"] as? String), ctx)
                        XCTAssertEqual(seg.mode?.rawValue, gs["mode"] as? String, ctx)
                    }
                }
                let transfers = try XCTUnwrap(g["transfers"] as? [[String: Any]])
                XCTAssertEqual(s.transfers.count, transfers.count, ctx)
                for (t, gt) in zip(s.transfers, transfers) {
                    XCTAssertEqual(t.stationName, gt["at"] as? String, ctx)
                    XCTAssertEqual(t.walkMinutes, gt["walkMin"] as? Int, ctx)
                    XCTAssertEqual(t.bufferMinutes, gt["bufferMin"] as? Int, ctx)
                    XCTAssertEqual(t.risk.rawValue, gt["risk"] as? String, ctx)
                    XCTAssertEqual(t.text, gt["text"] as? String, ctx)
                }
                let notices = try XCTUnwrap(g["notices"] as? [[String: Any]])
                XCTAssertEqual(s.notices.map(\.severity.rawValue), notices.map { $0["severity"] as! String }, ctx)
                XCTAssertEqual(s.notices.map(\.title), notices.map { $0["title"] as! String }, ctx)
                let tags = (g["tags"] as? [String] ?? []).map { $0 == "Schnellste" ? ConnectionSummary.Tag.fastest : .fewestChanges }
                XCTAssertEqual(s.tags, Set(tags), ctx)
                XCTAssertEqual(s.tags.map(\.title).sorted(), (g["tags"] as? [String] ?? []).sorted(), ctx)
                // Chips of every ride leg (uncapped) in golden order.
                for (leg, gl) in zip(journeys[i].legs, try XCTUnwrap(g["legs"] as? [[String: Any]])) where leg.kind == .ride {
                    XCTAssertEqual(JourneyPresentation.attributes(leg.remarks, limit: nil), gl["attributes"] as? [String], ctx)
                    VM.assert(JourneyPresentation.platformLabel(leg.departure, mode: leg.line?.mode),
                              (gl["dep"] as? [String: Any])?["platform"] as? [String: Any], "\(ctx) leg dep")
                    VM.assert(JourneyPresentation.platformLabel(leg.arrival, mode: leg.line?.mode),
                              (gl["arr"] as? [String: Any])?["platform"] as? [String: Any], "\(ctx) leg arr")
                }
            }
        }
    }

    /// Tags skip departed and cancelled connections; „Wenigste Umstiege“ only when change counts differ.
    func testTags() throws {
        let journeys = try CoverageFixtures.page("tripsearch_st_anton_innsbruck").journeys
        // At 12:40 the 12:33 RJX has left: the next direct RJX (14:33) is the fastest, and every remaining connection
        // that is not the fastest has more changes → no „Wenigste Umstiege“ duplicate on another direct train.
        let later = JourneyPresentation.summaries(journeys, now: Vienna.date("2026-10-09 12:40"))
        XCTAssertTrue(later[0].isPast)
        XCTAssertEqual(later.map(\.tags), [[], [], [.fastest], []])
        var cancelled = journeys
        cancelled[0].legs[0].isCancelled = true
        let c = JourneyPresentation.summaries(cancelled, now: morning)
        XCTAssertTrue(c[0].isCancelled)
        XCTAssertEqual(c.map(\.tags), [[], [], [.fastest], []])
        let same = JourneyPresentation.summaries([journeys[0], journeys[2]], now: morning)
        XCTAssertEqual(same.map(\.tags), [[.fastest], []], "equal change counts → no fewest-changes tag")
    }

    func testTransferRiskLevels() throws {
        var j = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys[0]
        let busDeparture = try XCTUnwrap(j.legs[2].departure.planned)
        func risk(busDelay minutes: Double) -> TransferInfo {
            // Bus leaves earlier → the buffer shrinks (realtime wins).
            j.legs[2].departure.realtime = busDeparture.addingTimeInterval(minutes * 60)
            return JourneyPresentation.transfers(j)[0]
        }
        XCTAssertEqual(risk(busDelay: -33).risk, .tight)
        XCTAssertEqual(risk(busDelay: -33).text, "Knapp: 4 min zum Umsteigen")
        XCTAssertEqual(risk(busDelay: -35).text, "Knapp: 2 min zum Umsteigen")
        XCTAssertEqual(risk(busDelay: -36).risk, .atRisk)
        XCTAssertEqual(risk(busDelay: -36).text, "Anschluss gefährdet")
        XCTAssertEqual(risk(busDelay: -32), TransferInfo(stationName: "Langen am Arlberg", walkMinutes: 1, bufferMinutes: 5, risk: .ok,
                                                         text: "6 min Umstiegszeit"))
    }

    func testNoticeSeverities() {
        func sev(_ kind: Remark.Kind, _ title: String?, _ text: String, prio: Int? = nil) -> NoticeSeverity {
            JourneyPresentation.notices([Remark(kind: kind, id: "x", title: title, text: text, priority: prio)])[0].severity
        }
        XCTAssertEqual(sev(.disruption, "ACHTUNG: Starker Reisetag", "…", prio: 10), .crowd, "crowd wins")
        XCTAssertEqual(sev(.disruption, "Bauarbeiten", "Hohe Auslastung erwartet"), .crowd)
        XCTAssertEqual(sev(.disruption, "Bauarbeiten", "Zwischen A und B Schienenersatzverkehr", prio: 100), .critical)
        XCTAssertEqual(sev(.disruption, "Störung", "Der Zug fällt aus", prio: 100), .critical)
        XCTAssertEqual(sev(.disruption, "Störung", "Verspätungen möglich", prio: 50), .critical)
        XCTAssertEqual(sev(.disruption, "Störung", "Verspätungen möglich", prio: 51), .warning)
        XCTAssertEqual(sev(.disruption, "Störung", "Verspätungen möglich"), .warning)
        XCTAssertEqual(sev(.attribute, nil, "Sitzplatzreservierung empfohlen"), .info, "attributes stay in the detail")
        XCTAssertEqual(sev(.info, nil, "Zugname"), .info)
        XCTAssertEqual(sev(.realtime, nil, "Halt fällt aus"), .critical)
        XCTAssertEqual(sev(.hint, nil, "Hält nur zum Aussteigen", prio: 10), .info)

        let rem = [Remark(kind: .realtime, text: "Halt fällt aus"), Remark(kind: .realtime, text: "Halt fällt aus"),
                   Remark(kind: .disruption, id: "H1", title: "A", text: "x", priority: 80),
                   Remark(kind: .disruption, id: "H2", title: "B", text: "x", priority: 20),
                   Remark(kind: .disruption, id: "H1", title: "A", text: "x", priority: 80)]
        let notices = JourneyPresentation.notices(rem)
        XCTAssertEqual(notices.count, 3, "deduplicated by id")
        XCTAssertEqual(notices[0].title, "Halt fällt aus")
        XCTAssertNil(notices[0].text)
        XCTAssertEqual(notices[0].id, JourneyPresentation.notices([Remark(kind: .realtime, text: "Halt fällt aus")])[0].id, "stable id")
        XCTAssertEqual(JourneyPresentation.topNotice(notices)?.id, "H2", "highest severity, then lowest priority")
    }

    func testTextsAndFormatting() {
        XCTAssertEqual(JourneyPresentation.durationText(minutes: 41), "41 min")
        XCTAssertEqual(JourneyPresentation.durationText(minutes: 136), "2 h 16 min")
        XCTAssertEqual(JourneyPresentation.durationText(minutes: 180), "3 h")
        XCTAssertEqual(JourneyPresentation.changesText(0), "direkt")
        XCTAssertEqual(JourneyPresentation.changesText(1), "1 Umstieg")
        XCTAssertEqual(JourneyPresentation.changesText(3), "3 Umstiege")
        XCTAssertNil(JourneyPresentation.viaText([]))
        XCTAssertEqual(JourneyPresentation.viaText(["Feldkirch"]), "über Feldkirch")
        XCTAssertEqual(JourneyPresentation.viaText(["Feldkirch", "Bludenz"]), "über Feldkirch und Bludenz")
    }

    /// Owner request 2026-10-09 (via stops): the card and VoiceOver say „über Feldkirch“.
    func testViaStopsInSummaryAndAccessibility() throws {
        let journeys = try CoverageFixtures.page(HafasViaTests.scenario).journeys
        let via = [ViaStop(location: HafasViaTests.feldkirch, minimumDwellMinutes: 10)]
        let cards = JourneyPresentation.summaries(journeys, now: morning, via: via)
        XCTAssertEqual(cards.count, 3)
        for s in cards {
            XCTAssertEqual(s.viaNames, ["Feldkirch"])
            XCTAssertEqual(s.viaText, "über Feldkirch")
            XCTAssertTrue(s.metaLine.hasSuffix("1 Umstieg · über Feldkirch"), s.metaLine)
            XCTAssertFalse(s.metaLine.contains("Feldkirch · über"), "the change station is not repeated")
            XCTAssertTrue(JourneyPresentation.accessibilityLabel(s, priceText: nil).contains("über Feldkirch"))
            // The change at Feldkirch is a wait (no walk), so the buffer is the whole stay.
            XCTAssertEqual(s.transfers.first?.risk, .ok)
            XCTAssertEqual(s.transfers.first?.walkMinutes, 0)
            XCTAssertGreaterThanOrEqual(s.transfers.first?.bufferMinutes ?? 0, 10)
            XCTAssertEqual(s.bar.map(\.kind), [.ride, .wait, .ride])
        }
        // A via stop the connection does not pass is not claimed; without via stops nothing changes.
        let salzburg = ViaStop(location: .station(extId: "8100002", name: "Salzburg Hbf"))
        XCTAssertEqual(JourneyPresentation.summaries(journeys, now: morning, via: [salzburg])[0].viaText, nil)
        let plain = JourneyPresentation.summaries(journeys, now: morning)[0]
        XCTAssertTrue(plain.metaLine.hasSuffix("1 Umstieg · Feldkirch"), plain.metaLine)
        // Two via stops: both named in travel order when the connection passes both.
        let innsbruck = ViaStop(location: .station(extId: "8100108", name: "Innsbruck Hbf"))
        XCTAssertEqual(JourneyPresentation.summaries(journeys, now: morning, via: [innsbruck, via[0]])[0].viaText,
                       "über Innsbruck Hbf und Feldkirch")
    }

    func testAccessibilityLabel() throws {
        let journeys = try CoverageFixtures.page("tripsearch_innsbruck_lech_bus").journeys
        let s = JourneyPresentation.summaries(journeys, now: morning)[0]
        XCTAssertEqual(JourneyPresentation.accessibilityLabel(s, priceText: "Normalpreis € 29,70"),
                       "Abfahrt 11:16, pünktlich, Ankunft 13:32, 2 Stunden 16 Minuten, 1 Umstieg in Langen am Arlberg, ab Gleis 3, "
                       + "RJX 19960, Bus 750, Normalpreis € 29,70, "
                       + "Hinweis: Andere Zuggarnitur, verringertes Platzangebot der 2. Klasse")
        let landeck = JourneyPresentation.summaries(try CoverageFixtures.page("tripsearch_tyrol_bus_landeck_ischgl").journeys, now: morning)[0]
        XCTAssertEqual(JourneyPresentation.accessibilityLabel(landeck, priceText: nil),
                       "Abfahrt 11:10, 3 Minuten später, 11:13, Ankunft 12:01, 4 Minuten später, 12:05, 51 Minuten, direkt, "
                       + "ab Steig C, Bus 260, Schnellste Verbindung")
    }

    /// `vm_board_innsbruck_hbf.json`: row states, texts, plates (BADGE_SPEC form), destinations and platform labels.
    /// Rows are matched by planned time, plate and destination (our board is sorted by realtime, the golden is not).
    func testBoardRowsMatchGolden() throws {
        let board = try HafasCodec.board(from: Fixture.data("hafas/stationboard_dep_innsbruck_hbf.response"))
        var rows = BoardPresentation.rows(board)
        let golden = try XCTUnwrap((try Fixture.json("ux/vm_board_innsbruck_hbf") as? [String: Any])?["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, golden.count)
        for g in golden {
            let plate = VM.badgePlate(g["plate"] as! String, mode: g["mode"] as? String)
            let ctx = "\(g["time"] ?? "") \(plate) \(g["destination"] ?? "")"
            guard let i = rows.firstIndex(where: { $0.time == g["time"] as? String && $0.plate == plate && $0.destination.name == g["destination"] as? String })
            else { XCTFail("no row for \(ctx)"); continue }
            let row = rows.remove(at: i)
            VM.assert(row.realtime, g, ctx)
            XCTAssertEqual(row.mode.rawValue, g["mode"] as? String, ctx)
            VM.assert(row.platform, g["platform"] as? [String: Any], ctx)
            let notices = try XCTUnwrap(g["notices"] as? [[String: Any]])
            XCTAssertEqual(row.notices.map(\.severity.rawValue), notices.map { $0["severity"] as! String }, ctx)
        }
        XCTAssertTrue(rows.isEmpty)
        let first = BoardPresentation.rows(board)[0]
        XCTAssertEqual(first.lineTitle, "Bus F")
        XCTAssertEqual(first.lineKind, .bus)
        XCTAssertEqual(first.platform?.text, "Steig F")
        let jenbach = try XCTUnwrap(BoardPresentation.rows(board).first { $0.destination.name == "Jenbach" })
        XCTAssertEqual(jenbach.platform, PlatformLabel(label: "Gl.", planned: "4", realtime: "3", changed: true, display: "3"))
        XCTAssertEqual(jenbach.lineTitle, "S 4")
    }

    func testPlatformLabels() {
        XCTAssertNil(JourneyPresentation.platformLabel(StopEvent()))
        let legacy = StopEvent(plannedPlatform: Platform(text: "7"))
        XCTAssertEqual(JourneyPresentation.platformLabel(legacy, mode: .train)?.text, "Gl. 7")
        XCTAssertEqual(JourneyPresentation.platformLabel(legacy, mode: .bus)?.text, "Steig 7")
        let flagged = StopEvent(plannedPlatform: Platform(text: "2", kind: .track), platformChangeFlag: true)
        XCTAssertEqual(JourneyPresentation.platformLabel(flagged)?.changed, true)
        XCTAssertEqual(PlatformLabel(label: "Gl.", planned: "3", realtime: nil, changed: false, display: "3").spoken, "Gleis 3")
    }
}
