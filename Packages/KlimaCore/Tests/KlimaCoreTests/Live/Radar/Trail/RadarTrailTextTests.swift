import XCTest
@testable import KlimaCore

/// Every word of „Spuren“ (docs/RADAR_TRAILS.md §8): „berechnet“, never GPS; what this iPhone got, never a recording.
final class RadarTrailTextTests: XCTestCase {
    /// 14:21 in Vienna (winter time, UTC+1).
    private let at1421: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 19; c.hour = 14; c.minute = 21
        return Calendar.vienna.date(from: c)!
    }()

    func testSettingWords() {
        XCTAssertEqual(RadarTrailText.sectionTitle, "Spuren")
        XCTAssertEqual(RadarTrailSetting.Mode.allCases.map(\.title), ["Aus", "Ausgewählte und meine", "Alle im Ausschnitt"])
        XCTAssertEqual(RadarTrailText.lengthTitle, "Länge")
        XCTAssertEqual(RadarTrailSetting.lengths.map(RadarTrailText.length), ["5 Min", "10 Min", "20 Min"])
        XCTAssertEqual(RadarTrailText.spokenLength(20), "20 Minuten")
        XCTAssertEqual(RadarTrailText.footer, "Eine Spur zeigt, wo die Auskunft das Fahrzeug berechnet hat, seit das Radar offen ist. Das Radar merkt sich das nur im Arbeitsspeicher und vergisst es beim Schließen.")
    }

    func testCaption() {
        XCTAssertEqual(RadarTrailText.caption(since: at1421), "Spuren seit 14:21 · berechnete Positionen, kein GPS-Verlauf")
        XCTAssertEqual(RadarTrailText.spokenCaption(since: at1421),
                       "Spuren zeigen die Positionen, die dieses iPhone seit 14 Uhr 21 bekommen hat. Berechnet, kein GPS-Verlauf.")
        XCTAssertEqual(RadarTrailText.limited(.tooMany, hasMine: true), "Zu viele Fahrzeuge für alle Spuren. Gezeigt werden deine. Zoom näher heran.")
        XCTAssertEqual(RadarTrailText.limited(.tooMany, hasMine: false), "Zu viele Fahrzeuge für alle Spuren. Zoom näher heran.")
        XCTAssertEqual(RadarTrailText.limited(.tooWide, hasMine: true), "Für alle Spuren ist die Karte zu weit. Gezeigt werden deine. Zoom näher heran.")
        XCTAssertEqual(RadarTrailText.limited(.tooWide, hasMine: false), "Für alle Spuren ist die Karte zu weit. Zoom näher heran.")
        XCTAssertEqual(RadarTrailText.onlyNow, "Spuren gibt es nur bei „Jetzt“.")
    }

    func testTwentyFourHoursInVienna() {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 1; c.hour = 21; c.minute = 5
        let summer = Calendar.vienna.date(from: c)!
        XCTAssertEqual(RadarTrailText.caption(since: summer), "Spuren seit 21:05 · berechnete Positionen, kein GPS-Verlauf")
        XCTAssertTrue(RadarTrailText.spokenCaption(since: summer).contains("seit 21 Uhr 5 bekommen"))
        c.hour = 9; c.minute = 0
        XCTAssertEqual(RadarTrailText.sinceLine(Calendar.vienna.date(from: c)!), "Seit 09:00 · aus den Antworten, die dieses iPhone bekommen hat")
    }

    func testTheCaptionStartsAtTheFirstAnswerButNeverBeforeTheLength() {
        let now = at1421.addingTimeInterval(3_600)
        XCTAssertEqual(RadarTrailText.since(firstRecordedAt: at1421, now: now, length: 600), now.addingTimeInterval(-600))
        XCTAssertEqual(RadarTrailText.since(firstRecordedAt: at1421, now: at1421.addingTimeInterval(120), length: 600), at1421)
    }

    func testRowTitleAndSinceLine() {
        XCTAssertEqual(RadarTrailText.rowTitle, "Verspätung, seit du zuschaust")
        XCTAssertEqual(RadarTrailText.sinceLine(at1421), "Seit 14:21 · aus den Antworten, die dieses iPhone bekommen hat")
    }

    private func series(_ minutes: [Int], cancelled: Bool = false) -> RadarDelaySeries {
        var samples = minutes.enumerated().map {
            RadarTrailSample(from: at1421.addingTimeInterval(Double($0.offset) * 60), coordinate: GeoPoint(latitude: 48, longitude: 16),
                             delaySeconds: $0.element * 60)
        }
        if cancelled {
            samples.append(RadarTrailSample(from: at1421.addingTimeInterval(600), coordinate: GeoPoint(latitude: 48, longitude: 16),
                                            isCancelled: true))
        }
        return RadarDelaySeries(samples: samples)
    }

    func testVoiceOverSentences() {
        XCTAssertEqual(RadarTrailText.spoken(series([3, 4, 5])), "Verspätung seit 14 Uhr 21 von 3 auf 5 Minuten gestiegen.")
        XCTAssertEqual(RadarTrailText.spoken(series([6, 4, 2])), "Verspätung seit 14 Uhr 21 von 6 auf 2 Minuten gesunken.")
        XCTAssertEqual(RadarTrailText.spoken(series([4, 4, 4])), "Verspätung seit 14 Uhr 21 gleich bei 4 Minuten.")
        XCTAssertEqual(RadarTrailText.spoken(series([0, 2, 5])), "Verspätung seit 14 Uhr 21 von pünktlich auf 5 Minuten gestiegen.")
        XCTAssertEqual(RadarTrailText.spoken(series([5, 2, 0])), "Verspätung seit 14 Uhr 21 von 5 Minuten auf pünktlich gesunken.")
        XCTAssertEqual(RadarTrailText.spoken(series([3, 4, 4])), "Verspätung seit 14 Uhr 21 etwa gleich, von 3 auf 4 Minuten.")
        XCTAssertEqual(RadarTrailText.spoken(series([0, 0, 0])), "Verspätung seit 14 Uhr 21 unverändert pünktlich.")
        XCTAssertEqual(RadarTrailText.spoken(series([1, 1, 1])), "Verspätung seit 14 Uhr 21 gleich bei 1 Minute.")
        XCTAssertEqual(RadarTrailText.spoken(series([3, 3, 3], cancelled: true)),
                       "Verspätung seit 14 Uhr 21 zuletzt 3 Minuten, dann als ausgefallen gemeldet.")
        XCTAssertEqual(RadarTrailText.spoken(series([-2, 0, 1])), "Verspätung seit 14 Uhr 21 von 2 Minuten zu früh auf 1 Minute gestiegen.")
    }

    func testChartLabels() {
        XCTAssertEqual(RadarTrailText.label(3), "+3")
        XCTAssertEqual(RadarTrailText.label(0), "pünktlich")
        XCTAssertEqual(RadarTrailText.label(-1), "\u{2212}1")
        XCTAssertEqual(RadarTrailText.trendWord(.rising), "steigt")
        XCTAssertEqual(RadarTrailText.trendWord(.falling), "sinkt")
        XCTAssertEqual(RadarTrailText.trendWord(.steady), "etwa gleich")
    }

    /// The honesty vocabulary: positions are calculated, never GPS; nothing says it was seen or recorded by ÖBB.
    func testHonestWords() {
        let all = [RadarTrailText.footer, RadarTrailText.caption(since: at1421), RadarTrailText.spokenCaption(since: at1421),
                   RadarTrailText.limited(.tooMany, hasMine: true), RadarTrailText.limited(.tooWide, hasMine: true), RadarTrailText.onlyNow, RadarTrailText.rowTitle, RadarTrailText.sinceLine(at1421)]
        for text in all {
            XCTAssertFalse(text.contains("live gesehen"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("echt"), text)
            XCTAssertFalse(text.contains("Aufzeichnung"), text)
        }
        XCTAssertTrue(RadarTrailText.caption(since: at1421).contains("berechnete Positionen"))
        XCTAssertTrue(RadarTrailText.caption(since: at1421).contains("kein GPS"))
        XCTAssertTrue(RadarTrailText.footer.contains("berechnet"))
        XCTAssertTrue(RadarTrailText.rowTitle.contains("seit du zuschaust"))
    }
}
