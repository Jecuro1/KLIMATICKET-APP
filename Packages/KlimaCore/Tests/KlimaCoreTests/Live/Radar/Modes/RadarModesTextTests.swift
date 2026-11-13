import XCTest
@testable import KlimaCore

// MARK: radarmodes – the words of the modes, counts and notes (docs/RADAR_MODES.md §9).
final class RadarModesTextTests: XCTestCase {
    private let city: [RadarMode] = [.bus, .tram, .subway]

    func testNamesAndPlurals() {
        XCTAssertEqual(RadarModesText.names([.bus]), "Bus")
        XCTAssertEqual(RadarModesText.names([.bus, .tram]), "Bus und Bim")
        XCTAssertEqual(RadarModesText.names(city), "Bus, Bim und U-Bahn")
        XCTAssertEqual(RadarModesText.pluralNames([.bus, .tram]), "Busse und Bims")
        XCTAssertEqual(RadarModesText.counted(1, .rail), "1 Zug")
        XCTAssertEqual(RadarModesText.counted(21, .rail), "21 Züge")
        XCTAssertEqual(RadarModesText.counted(1, .suburban), "1 S-Bahn")
        XCTAssertEqual(RadarModesText.counted(28, .suburban), "28 S-Bahnen")
        XCTAssertEqual(RadarModesText.counted(1, .bus), "1 Bus")
        XCTAssertEqual(RadarModesText.counted(180, .bus), "180 Busse")
        XCTAssertEqual(RadarModesText.counted(0, .tram), "0 Bims")
        XCTAssertEqual(RadarModesText.counted(1, .subway), "1 U-Bahn")
        XCTAssertEqual(RadarModesText.counted(1, nil), "1 anderes Fahrzeug")
        XCTAssertEqual(RadarModesText.counted(3, nil), "3 andere Fahrzeuge")
    }

    func testChipValueAndFooter() {
        XCTAssertEqual(RadarModesText.chipValue(isOn: false, outOfZoom: true), "aus")
        XCTAssertEqual(RadarModesText.chipValue(isOn: true, outOfZoom: false), "an")
        XCTAssertEqual(RadarModesText.chipValue(isOn: true, outOfZoom: true), "an, erscheint beim Heranzoomen")
        XCTAssertTrue(RadarModesText.modesFooter().contains("etwa \(RadarLanePlan.cityLimitKilometres()) km hoch"))
        XCTAssertTrue(RadarModesText.modesFooter(limit: 0.3).contains("etwa 33 km hoch"))
    }

    func testEveryNoteWithZeroOneAndTwo() {
        XCTAssertEqual(RadarModesText.zoomHint(city), "Bus, Bim und U-Bahn erscheinen, wenn du näher heranzoomst.")
        XCTAssertEqual(RadarModesText.zoomHint([.bus]), "Bus erscheint, wenn du näher heranzoomst.")
        XCTAssertEqual(RadarModesText.loading(city, answered: 4, of: 9), "Bus, Bim und U-Bahn: 4 von 9 Gebieten geladen.")
        XCTAssertEqual(RadarModesText.loading([.bus], answered: 0, of: 1), "Bus: 0 von 1 Gebiet geladen.")
        XCTAssertEqual(RadarModesText.loading([.bus], answered: 0, of: 2), "Bus: 0 von 2 Gebieten geladen.")
        XCTAssertEqual(RadarModesText.crowded([.bus, .tram]),
                       "Für alle Busse und Bims hier bräuchte das Radar mehr Abfragen, als es senden darf. Ein Teil fehlt. Zoom näher heran.")
        XCTAssertEqual(RadarModesText.cityCapped(1),
                       "In einem kleinen Gebiet fahren mehr Fahrzeuge, als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.")
        XCTAssertEqual(RadarModesText.cityCapped(2),
                       "In 2 kleinen Gebieten fahren mehr Fahrzeuge, als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.")
        XCTAssertEqual(RadarModesText.dataEstimate(city, megabytes: 12), "Bus, Bim und U-Bahn: etwa 12 MB pro Minute (geschätzt).")
        XCTAssertEqual(RadarModesText.metered(city), "Über mobile Daten kommen Bus, Bim und U-Bahn alle 60 s.")
        XCTAssertEqual(RadarModesText.metered([.bus]), "Über mobile Daten kommt Bus alle 60 s.")
        XCTAssertEqual(RadarModesText.empty, "Die Auskunft kennt in diesem Ausschnitt gerade keine Fahrzeuge.")
        XCTAssertEqual(RadarModesText.emptyWithFilter(unfiltered: 84), "Kein Fahrzeug passt zum Filter. Ohne Filter wären es 84.")
        XCTAssertEqual(RadarModesText.emptyWithFilter(unfiltered: 2), "Kein Fahrzeug passt zum Filter. Ohne Filter wären es 2.")
        XCTAssertEqual(RadarModesText.emptyWithFilter(unfiltered: 1), "Kein Fahrzeug passt zum Filter. Ohne Filter wäre es eins.")
        XCTAssertEqual(RadarModesText.timeTravelHint, "Zeitreise gibt es nur mit Zügen und S-Bahn.")
    }

    func testNoTextSaysNothingRuns() {
        let all = [RadarModesText.empty, RadarModesText.emptyWithFilter(unfiltered: 0), RadarModesText.zoomHint(city), RadarModesText.crowded(city)]
        for text in all {
            XCTAssertFalse(text.contains("fährt nichts"))
            XCTAssertFalse(text.contains("Keine Busse"))
            XCTAssertFalse(text.contains("GPS"))
        }
    }

    // MARK: The notes of a situation

    private func situation(_ status: RadarStatus, modes: Set<RadarMode> = [.rail, .suburban, .bus, .tram, .subway], metered: Bool = false,
                           pins: Int = 10, unfiltered: Int = 10, filter: Bool = false) -> RadarModesText.Situation {
        RadarModesText.Situation(status: status, selection: RadarModeSelection(modes), meteredCity: metered, pinCount: pins,
                                 unfilteredCount: unfiltered, filterActive: filter)
    }

    func testOutOfZoomSaysWhyTheCityModesAreMissing() {
        var status = RadarStatus()
        status.visibleTiles = 2
        status.answeredTiles = 2
        status.city.isActive = true
        status.city.outOfZoom = true
        let notes = RadarModesText.notes(situation(status))
        XCTAssertEqual(notes.first, "Bus, Bim und U-Bahn erscheinen, wenn du näher heranzoomst.")
        XCTAssertEqual(RadarModesText.notes(situation(status, modes: [.rail, .bus])).first, "Bus erscheint, wenn du näher heranzoomst.")
    }

    func testCityLaneNotes() {
        var status = RadarStatus()
        status.visibleTiles = 2
        status.answeredTiles = 2
        status.period = 50
        status.budgetLimited = true
        status.city.isActive = true
        status.city.visibleTiles = 16
        status.city.answeredTiles = 12
        status.city.pendingTiles = 4
        status.city.crowdedTiles = 2
        status.city.cappedTiles = 2
        status.city.period = 50
        status.city.vehicleCounts = Array(repeating: 600, count: 12)
        let notes = RadarModesText.notes(situation(status))
        XCTAssertEqual(notes, [
            "Bus, Bim und U-Bahn: 12 von 16 Gebieten geladen.",
            "Für alle Busse, Bims und U-Bahnen hier bräuchte das Radar mehr Abfragen, als es senden darf. Ein Teil fehlt. Zoom näher heran.",
            "In 2 kleinen Gebieten fahren mehr Fahrzeuge, als die Auskunft je Abfrage liefert. Ein Teil davon fehlt auf der Karte.",
            "Dieser Ausschnitt · aktualisiert alle ~50 s",
            "Bus, Bim und U-Bahn: etwa 15 MB pro Minute (geschätzt).",
        ])
        XCTAssertEqual(notes.filter { $0.contains("aktualisiert alle") }.count, 1, "one cadence note for both lanes")
    }

    func testTheMeteredNoteReplacesTheCadenceNoteOfASixtySecondCityRefresh() {
        var status = RadarStatus()
        status.city.isActive = true
        status.city.visibleTiles = 3
        status.city.answeredTiles = 3
        status.city.period = 60
        status.city.vehicleCounts = [100, 100, 100]
        let notes = RadarModesText.notes(situation(status, modes: [.bus], metered: true))
        XCTAssertEqual(notes, ["Über mobile Daten kommt Bus alle 60 s."], "300 buses a minute: 0.5 MB, no data note")
        let wifi = RadarModesText.notes(situation(status, modes: [.bus], metered: false))
        XCTAssertEqual(wifi, ["Dieser Ausschnitt · aktualisiert alle ~60 s"])
    }

    func testEmptyMapSaysTheAuskunftKnowsNothingOrBlamesTheFilter() {
        var status = RadarStatus()
        status.visibleTiles = 2
        status.answeredTiles = 2
        XCTAssertEqual(RadarModesText.notes(situation(status, modes: [.rail], pins: 0, unfiltered: 0)), [RadarModesText.empty])
        XCTAssertEqual(RadarModesText.notes(situation(status, modes: [.rail], pins: 0, unfiltered: 84, filter: true)),
                       ["Kein Fahrzeug passt zum Filter. Ohne Filter wären es 84."])
        XCTAssertEqual(RadarModesText.notes(situation(status, modes: [.rail], pins: 0, unfiltered: 0, filter: true)), [RadarModesText.empty])
        status.pendingTiles = 1
        XCTAssertFalse(RadarModesText.notes(situation(status, modes: [.rail], pins: 0, unfiltered: 0)).contains(RadarModesText.empty),
                       "not while tiles are still to come")
    }

    func testTheDefaultRadarKeepsItsNotes() {
        // Without the city lane the notes are exactly those of RadarStatusText.
        var status = RadarStatus()
        status.visibleTiles = 9
        status.answeredTiles = 9
        status.cappedTiles = 1
        status.period = 45
        let expected = RadarStatusText.notes(status, rail: true)
        XCTAssertEqual(RadarModesText.notes(situation(status, modes: [.rail, .suburban])), expected)
    }
}

// MARK: radarmodes – legend and marker words
final class RadarModesLegendTextTests: XCTestCase {
    func testLegendSaysCalculatedAndNotGPS() {
        XCTAssertTrue(RadarModesText.legendFooter.contains("berechnet"))
        XCTAssertTrue(RadarModesText.legendFooter.contains("kein GPS"))
        XCTAssertEqual(RadarModesText.legendSpoken(.bus), "Bus: Kapsel mit Liniennummer, orange")
        XCTAssertEqual(RadarModesText.legendSpoken(.tram), "Bim: abgerundetes Schild mit Bim-Symbol, violett")
        XCTAssertEqual(RadarMode.allCases.map(RadarModesText.legendLabel), ["Zug", "S-Bahn", "Bus", "Bim", "U-Bahn"])
        XCTAssertEqual(RadarModesText.legendOnTime, "Grüner Ring: pünktlich (unter 5 Min)")
        XCTAssertEqual(RadarModesText.legendLate, "Oranger Ring: ab 5 Min verspätet")
    }

    func testSpokenLineAddsTheNounWhereTheTitleHasNone() {
        XCTAssertEqual(RadarModesText.spokenLine(title: "S 45", kind: .sBahn), "S-Bahn S 45")
        XCTAssertEqual(RadarModesText.spokenLine(title: "Tram D", kind: .tram), "Straßenbahn D")
        XCTAssertEqual(RadarModesText.spokenLine(title: "D", kind: .tram), "Straßenbahn D")
        XCTAssertEqual(RadarModesText.spokenLine(title: "U6", kind: .uBahn), "U-Bahn-Linie U6")
        XCTAssertEqual(RadarModesText.spokenLine(title: "Bus 13A", kind: .bus), "Bus 13A")
        XCTAssertEqual(RadarModesText.spokenLine(title: "RJX 66", kind: .fern), "RJX 66")
        XCTAssertEqual(RadarModesText.positionNote(isEstimate: false), "Position berechnet")
        XCTAssertEqual(RadarModesText.positionNote(isEstimate: true), "Position geschätzt")
    }
}

// MARK: radarmodes – the words of the sheet and the row
final class RadarModesSheetTextTests: XCTestCase {
    func testSheetWords() {
        XCTAssertEqual(RadarModesText.countNow(180), "gerade 180")
        XCTAssertEqual(RadarModesText.activeFilter(RadarFilter(onlyLate: true, trainClasses: [.rjx, .rj])), "Filter: RJX, RJ · nur verspätet")
        XCTAssertEqual(RadarModesText.removeLine("13A"), "13A entfernen")
        XCTAssertTrue(RadarModesText.groupsFooter.contains("250"))
        XCTAssertTrue(RadarModesText.labelFooter.contains("80"))
        XCTAssertEqual(RadarModesText.searchPlaceholder, "Linie oder Zugnummer, z. B. RJX 66 oder 13A")
        XCTAssertFalse(RadarModesText.searchNoMatch.contains("Kein Zug"), "the search finds buses too")
        XCTAssertEqual(RadarModesText.filterOff, "Filter aus")
    }
}
