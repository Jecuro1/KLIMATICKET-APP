import XCTest
@testable import KlimaCore

/// The words of the Zug-Radar status line (docs/OEBB_LIVE.md §R11): count, age and the honest note about tiles.
final class RadarStatusTextTests: XCTestCase {
    func testAgeReadsLikeTheOwnerWroteIt() {
        XCTAssertEqual(RadarStatusText.age(0), "gerade eben")
        XCTAssertEqual(RadarStatusText.age(2.4), "gerade eben")
        XCTAssertEqual(RadarStatusText.age(12), "vor 12 s")
        XCTAssertEqual(RadarStatusText.age(59.4), "vor 59 s")
        XCTAssertEqual(RadarStatusText.age(60), "vor 1 Min")
        XCTAssertEqual(RadarStatusText.age(190), "vor 3 Min")
        XCTAssertEqual(RadarStatusText.age(-5), "gerade eben")
        XCTAssertEqual(RadarStatusText.spokenAge(12), "vor 12 Sekunden")
        XCTAssertEqual(RadarStatusText.spokenAge(75), "vor einer Minute")
        XCTAssertEqual(RadarStatusText.spokenAge(250), "vor 4 Minuten")
    }

    func testPillShowsTheCountInTheViewAndTheAge() {
        XCTAssertEqual(RadarStatusText.pill(count: 923, rail: true, age: 12), "923 Züge · vor 12 s")
        XCTAssertEqual(RadarStatusText.pill(count: 1, rail: true, age: 30), "1 Zug · vor 30 s")
        XCTAssertEqual(RadarStatusText.pill(count: 0, rail: true, age: 4), "0 Züge · vor 4 s")
        XCTAssertEqual(RadarStatusText.pill(count: 640, rail: false, age: 70), "640 Fahrzeuge · vor 1 Min")
        XCTAssertEqual(RadarStatusText.pill(count: 5, rail: true, age: nil), "5 Züge")
    }

    func testNoNoteWhenEverythingIsFresh() {
        var status = RadarStatus()
        status.visibleTiles = 2
        status.answeredTiles = 2
        status.period = 20
        status.latitudeSpan = 4.2
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).isEmpty)
    }

    func testSlowRefreshIsSaidWithTheScopeOfTheView() {
        var status = RadarStatus()
        status.visibleTiles = 12
        status.answeredTiles = 12
        status.period = 41
        status.coversCountry = true
        XCTAssertEqual(RadarStatusText.notes(status, rail: true), ["Ganz Österreich · aktualisiert alle ~45 s"], "rounded up to five seconds")
        status.coversCountry = false
        XCTAssertEqual(RadarStatusText.notes(status, rail: true), ["Dieser Ausschnitt · aktualisiert alle ~45 s"],
                       "a view of a few Bundesländer is not 'Ganz Österreich', whatever its latitude span")
        status.period = 25
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).isEmpty, "25 s is still the normal rhythm")
    }

    func testALeafStillAtTheCapIsOwnedUpToAndOldTextIsGone() {
        var status = RadarStatus()
        status.answeredTiles = 3
        status.cappedTiles = 1
        let one = RadarStatusText.notes(status, rail: false)
        XCTAssertEqual(one.count, 1)
        XCTAssertTrue(one[0].contains("mehr Fahrzeuge"))
        status.cappedTiles = 3
        XCTAssertTrue(RadarStatusText.notes(status, rail: true)[0].hasPrefix("In 3 Gebieten fahren mehr Züge"))
        // The claim "Zoom hinein für alle Züge" was true when one tile was cut off at 256; it is not any more. And only a tile on
        // the finest level can still be cut off: zooming in would not make it finer, so the note must not promise it.
        let text = RadarStatusText.notes(status, rail: true).joined().lowercased()
        XCTAssertFalse(text.contains("zoom"))
        XCTAssertTrue(text.contains("fehlt auf der karte"), "it says what is missing")
        XCTAssertFalse(RadarStatusText.notes(RadarStatus(), rail: true).joined().contains("256"))
    }

    func testTilesNotLoadedYetAreSaidWhileTheMapShowsVehicles() {
        var status = RadarStatus()
        status.visibleTiles = 4
        status.answeredTiles = 2
        status.pendingTiles = 2
        XCTAssertEqual(RadarStatusText.notes(status, rail: true), ["Ein Teil der Karte wird noch geladen."])
        XCTAssertTrue(RadarStatusText.notes(status, rail: true, hasVehicles: false).isEmpty,
                      "with nothing on the map the pill already says 'Lade Fahrzeuge …'")
        status.pendingTiles = 0
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).isEmpty)
    }

    func testPartialFailureAndOutsideCoverage() {
        var status = RadarStatus()
        status.visibleTiles = 4
        status.answeredTiles = 3
        status.failedTiles = 1
        XCTAssertEqual(RadarStatusText.notes(status, rail: true), ["Für einen Teil der Karte kam keine Antwort. Es wird neu versucht."])
        status.answeredTiles = 0
        status.failedTiles = 4
        status.isPaused = true
        XCTAssertTrue(RadarStatusText.notes(status, rail: true).isEmpty, "a full pause has its own card, no extra note")
        var outside = RadarStatus()
        outside.outsideCoverage = true
        XCTAssertEqual(RadarStatusText.notes(outside, rail: true).count, 1)
    }
}
