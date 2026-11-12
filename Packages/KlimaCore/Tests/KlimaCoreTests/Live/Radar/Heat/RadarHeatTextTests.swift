import XCTest
@testable import KlimaCore

/// The words of the delay heat map (docs/RADAR_HEATMAP.md §4): every sentence says only what the numbers say.
final class RadarHeatTextTests: XCTestCase {
    private func summary(onTime: Int = 0, delayed: Int = 0, severe: Int = 0, cancelled: Int = 0, noRealtime: Int = 0,
                         average: Double? = nil) -> HeatSummary {
        var s = HeatSummary()
        s.onTime = onTime; s.delayed = delayed; s.severe = severe; s.cancelled = cancelled; s.noRealtime = noRealtime
        s.total = onTime + delayed + severe + cancelled + noRealtime
        s.averageLateSeconds = average
        return s
    }

    func testTheHeadlineNamesItsBaseAndTheLimit() {
        XCTAssertEqual(RadarHeatText.headline(summary(onTime: 87, delayed: 9, severe: 4)), "Pünktlich (unter 5 Min): 87 %")
        XCTAssertEqual(RadarHeatText.headline(summary(noRealtime: 12)), "Noch keine Echtzeit-Daten", "no number without data")
        XCTAssertEqual(RadarHeatText.headline(HeatSummary()), "Noch keine Echtzeit-Daten")
        XCTAssertEqual(RadarHeatText.punctualLabel, "Pünktlich (unter 5 Min)")
    }

    func testTheRealtimeLineCountsBothKinds() {
        XCTAssertEqual(RadarHeatText.realtimeLine(summary(onTime: 400, delayed: 10, noRealtime: 38)), "410 Züge mit Echtzeit-Daten, 38 ohne")
        XCTAssertEqual(RadarHeatText.realtimeLine(summary(onTime: 1)), "1 Zug mit Echtzeit-Daten")
        XCTAssertEqual(RadarHeatText.realtimeLine(summary(onTime: 5, noRealtime: 1)), "5 Züge mit Echtzeit-Daten, 1 ohne")
        XCTAssertEqual(RadarHeatText.realtimeLine(summary(noRealtime: 3)), "Keine Echtzeit-Daten bei den 3 geladenen Zügen")
        XCTAssertEqual(RadarHeatText.realtimeLine(HeatSummary()), "Noch keine Züge geladen")
    }

    func testTheAverageLine() {
        XCTAssertEqual(RadarHeatText.averageLine(summary(onTime: 40, delayed: 2, severe: 1, average: 660)), "Ø 11 Min bei den 3 verspäteten Zügen")
        XCTAssertEqual(RadarHeatText.averageLine(summary(onTime: 40, delayed: 1, average: 420)), "Ø 7 Min bei dem verspäteten Zug")
        XCTAssertEqual(RadarHeatText.averageLine(summary(onTime: 40)), "Kein Zug ist 5 Min oder mehr verspätet")
        XCTAssertEqual(RadarHeatText.averageLine(summary(noRealtime: 4)), "", "nothing to say without data")
    }

    func testMinutesRoundDownLikeTheMarkers() {
        XCTAssertEqual(RadarHeatText.minutes(299), "4 Min")
        XCTAssertEqual(RadarHeatText.minutes(300), "5 Min")
        XCTAssertEqual(RadarHeatText.minutes(-60), "0 Min")
        XCTAssertEqual(RadarHeatText.minutes(.nan), "–")
        XCTAssertEqual(RadarHeatText.signedDelay(1080), "+18 Min")
        XCTAssertEqual(RadarHeatText.spokenMinutes(60), "1 Minute")
        XCTAssertEqual(RadarHeatText.spokenMinutes(1080), "18 Minuten")
    }

    func testTheLegendUsesTheSameWordsAsTheLimits() {
        XCTAssertEqual(HeatBucket.allCases.map(RadarHeatText.legend), ["unter 5 Min", "5 bis 15 Min", "über 15 Min", "ausgefallen", "ohne Echtzeit"])
    }

    func testTheSpokenSummaryCarriesTheNumbers() {
        let text = RadarHeatText.spokenSummary(summary(onTime: 87, delayed: 9, severe: 3, cancelled: 1, noRealtime: 40, average: 780), ageSeconds: 12)
        XCTAssertTrue(text.contains("87 Prozent"), text)
        XCTAssertTrue(text.contains("100 Züge mit Echtzeit-Daten, 40 ohne"), text)
        XCTAssertTrue(text.contains("Ø 13 Min"), text)
        XCTAssertTrue(text.contains("87 unter 5 Minuten"), text)
        XCTAssertTrue(text.contains("9 zwischen 5 und 15 Minuten"), text)
        XCTAssertTrue(text.contains("vor 12 Sekunden"), text)
        let none = RadarHeatText.spokenSummary(summary(noRealtime: 9), ageSeconds: nil)
        XCTAssertTrue(none.contains("noch keine Echtzeit-Daten"), none)
        XCTAssertFalse(none.contains("Prozent"))
    }

    func testCellsSayWhyTheyHaveNoColour() {
        let neutral = HeatCell(id: HeatCellID(q: 0, r: 0), center: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), tripIDs: ["a", "b"], sampleCount: 2,
                               cancelledCount: 0, noRealtimeCount: 0, lateCount: 2, medianDelaySeconds: nil, delaySumMinutes: 40, placeName: nil)
        XCTAssertTrue(RadarHeatText.cellTitle(neutral).contains("mindestens 3"))
        var coloured = neutral
        coloured.medianDelaySeconds = 960
        XCTAssertEqual(RadarHeatText.cellTitle(coloured), "Mittlere Verspätung 16 Min")
        coloured.cancelledCount = 1
        coloured.noRealtimeCount = 2
        coloured.tripIDs = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(RadarHeatText.cellBase(coloured), "5 Züge · 2 mit Verspätungswert · 1 ausgefallen · 2 ohne Echtzeit")
    }

    func testHotspotWords() {
        XCTAssertEqual(RadarHeatText.place("Jenbach"), "Raum Jenbach")
        XCTAssertEqual(RadarHeatText.place(nil), "Gebiet ohne Haltestelle")
        XCTAssertEqual(RadarHeatText.place(""), "Gebiet ohne Haltestelle")
        let spot = HeatHotspot(rank: 1, cellID: HeatCellID(q: 0, r: 0), center: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), placeName: "Jenbach",
                               sampleCount: 6, lateCount: 4, medianDelaySeconds: 840, delaySumMinutes: 63.4)
        XCTAssertEqual(RadarHeatText.hotspotDetail(spot), "Ø 14 Min · 4 von 6 verspätet · 63 Min zusammen")
    }

    func testTrainRows() {
        let late = HeatSample(tripID: "a", coordinate: HeatGrid.center(of: HeatCellID(q: 0, r: 0)), lineTitle: "RJX 66", direction: "Wien Hbf", delaySeconds: 1080)
        XCTAssertEqual(RadarHeatText.trainRow(late).title, "RJX 66")
        XCTAssertEqual(RadarHeatText.trainRow(late).detail, "nach Wien Hbf")
        XCTAssertEqual(RadarHeatText.trainRow(late).value, "+18 Min")
        XCTAssertEqual(RadarHeatText.spokenTrain(late), "RJX 66 nach Wien Hbf, 18 Minuten verspätet")
        var ok = late
        ok.delaySeconds = 30
        XCTAssertEqual(RadarHeatText.trainRow(ok).value, "pünktlich")
        XCTAssertEqual(RadarHeatText.spokenTrain(ok), "RJX 66 nach Wien Hbf, pünktlich")
        var small = late
        small.delaySeconds = 180
        XCTAssertEqual(RadarHeatText.trainRow(small).value, "+3 Min", "a train under 5 minutes shows its minutes, in green")
        var none = late
        none.delaySeconds = nil
        XCTAssertEqual(RadarHeatText.trainRow(none).value, "ohne Echtzeit")
        XCTAssertEqual(RadarHeatText.spokenTrain(none), "RJX 66 nach Wien Hbf, keine Echtzeit-Daten")
        let cancelled = HeatSample(tripID: "c", coordinate: late.coordinate, lineTitle: "REX 5", isCancelled: true)
        XCTAssertEqual(RadarHeatText.trainRow(cancelled).value, "fällt aus")
        XCTAssertEqual(RadarHeatText.trainRow(cancelled).detail, "")
    }

    func testCompletenessNotesSayWhatIsMissing() {
        var status = RadarStatus()
        XCTAssertNil(RadarHeatText.completenessNote(status))
        status.pendingTiles = 1
        XCTAssertTrue(RadarHeatText.completenessNote(status)?.contains("noch geladen") ?? false)
        status.failedTiles = 1
        XCTAssertTrue(RadarHeatText.completenessNote(status)?.contains("keine Antwort") ?? false)
        status.isPaused = true
        XCTAssertTrue(RadarHeatText.completenessNote(status)?.contains("pausiert") ?? false)
        var capped = RadarStatus()
        capped.cappedTiles = 1
        XCTAssertNotNil(RadarHeatText.completenessNote(capped))
    }

    func testTheMethodNoteSaysWhatTheNumbersAre() {
        XCTAssertTrue(RadarHeatText.methodNote.contains("nächsten Halt"))
        XCTAssertTrue(RadarHeatText.methodNote.contains("berechnet"))
        XCTAssertTrue(RadarHeatText.methodNote.contains("nie als pünktlich"))
    }
}
