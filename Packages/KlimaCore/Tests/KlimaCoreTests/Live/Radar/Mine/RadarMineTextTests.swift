import XCTest
@testable import KlimaCore

/// Every sentence of „Meine Fahrzeuge“ (docs/RADAR_MINE.md §9): units, minutes, delays, the VoiceOver forms, and the honesty rules (positions are
/// „berechnet“, no GPS; an empty list says what the Auskunft knows, never that nothing runs).
final class RadarMineTextTests: XCTestCase {
    private typealias F = MineFixture

    func testDistances() {
        XCTAssertEqual(RadarMineText.distance(0.24), "240 m")
        XCTAssertEqual(RadarMineText.distance(0.004), "10 m")
        XCTAssertEqual(RadarMineText.distance(0.996), "1 km")
        XCTAssertEqual(RadarMineText.distance(1.2), "1,2 km")
        XCTAssertEqual(RadarMineText.distance(1.0), "1 km")
        XCTAssertEqual(RadarMineText.distance(12.4), "12 km")
        XCTAssertEqual(RadarMineText.distance(.nan), "–")
        XCTAssertEqual(RadarMineText.spokenDistance(0.24), "240 Meter")
        XCTAssertEqual(RadarMineText.spokenDistance(1.2), "1,2 Kilometer")
        XCTAssertEqual(RadarMineText.spokenDistance(1.0), "1 Kilometer")
        XCTAssertEqual(RadarMineText.spokenDistance(.infinity), "unbekannt weit")
    }

    func testMinutesAndDelays() {
        XCTAssertEqual(RadarMineText.minutesText(4), "in 4 Min")
        XCTAssertEqual(RadarMineText.spokenMinutes(1), "in 1 Minute")
        XCTAssertEqual(RadarMineText.spokenMinutes(4), "in 4 Minuten")
        XCTAssertEqual(RadarMineText.spokenMinutes(0), "jetzt")
        let onTime = RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 20, isCancelled: false)
        let late = RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 70, isCancelled: false)
        let early = RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: -60, isCancelled: false)
        let plan = RadarMineETA(time: F.t0, isRealtime: false, delaySeconds: nil, isCancelled: false)
        let gone = RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 0, isCancelled: true)
        XCTAssertEqual(RadarMineText.delayChip(onTime), "pünktlich")
        XCTAssertEqual(RadarMineText.delayChip(late), "+1")
        XCTAssertEqual(RadarMineText.delayChip(early), "−1")
        XCTAssertEqual(RadarMineText.delayChip(plan), "laut Fahrplan")
        XCTAssertEqual(RadarMineText.delayChip(gone), "fällt aus")
        XCTAssertEqual(RadarMineText.delayChip(nil), "laut Fahrplan")
        XCTAssertEqual(RadarMineText.spokenDelay(late), "1 Minute verspätet")
        XCTAssertEqual(RadarMineText.spokenDelay(RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 300, isCancelled: false)), "5 Minuten verspätet")
        XCTAssertEqual(RadarMineText.spokenDelay(onTime), "pünktlich")
        XCTAssertEqual(RadarMineText.spokenDelay(plan), "laut Fahrplan")
    }

    func testTheLinesPage() {
        XCTAssertEqual(RadarMineText.running(3), "3 unterwegs in den geladenen Gebieten")
        let late = RadarMineETA(time: F.t0.addingTimeInterval(180), isRealtime: true, delaySeconds: 60, isCancelled: false)
        XCTAssertEqual(RadarMineText.nextVehicle(direction: "Hütteldorf", stop: "Westbahnhof", eta: late, now: F.t0),
                       "Nächster: Richtung Hütteldorf · Westbahnhof in 3 Min (+1)")
        let plan = RadarMineETA(time: F.t0.addingTimeInterval(180), isRealtime: false, delaySeconds: nil, isCancelled: false)
        XCTAssertEqual(RadarMineText.nextVehicle(direction: nil, stop: "Westbahnhof", eta: plan, now: F.t0), "Nächster: Westbahnhof in 3 Min laut Fahrplan")
        let gone = RadarMineETA(time: F.t0, isRealtime: true, delaySeconds: 0, isCancelled: true)
        XCTAssertEqual(RadarMineText.stopETA(stop: "Westbahnhof", eta: gone, now: F.t0), "Westbahnhof · fällt aus")
        XCTAssertEqual(RadarMineText.lineSpoken(title: "Bus 13A", running: 0, next: nil),
                       "Bus 13A. Gerade keine in den geladenen Gebieten. Die Auskunft kennt nur, was in den geladenen Gebieten fährt.")
        XCTAssertEqual(RadarMineText.lineSpoken(title: "Bus 13A", running: 2, next: "Nächster: Neubaugasse in 2 Min"),
                       "Bus 13A. 2 unterwegs in den geladenen Gebieten. Nächster: Neubaugasse in 2 Min")
        XCTAssertEqual(RadarMineText.modeOff(.bus), "„Bus“ ist oben ausgeschaltet. Das Radar fragt diese Linie gerade nicht ab.")
        XCTAssertEqual(RadarMineText.rememberSpoken("Bus 13A"), "Linie Bus 13A merken")
        XCTAssertEqual(RadarMineText.rememberedSpoken("Bus 13A"), "Bus 13A ist gemerkt. Doppeltippen zum Entfernen.")
        XCTAssertEqual(RadarMineText.rememberedToast("Bus 13A"), "Bus 13A gemerkt")
        XCTAssertEqual(RadarMineText.full, "Du kannst bis zu 20 Linien merken. Entferne zuerst eine.")
    }

    func testTheNearRowAndItsSentence() throws {
        let vehicle = F.vehicle("a", line: F.bus(), at: F.point(north: 240), nextIn: 60, delayMinutes: 1)
        let row = try XCTUnwrap(RadarNearby.rows([RadarMineSighting(vehicle: vehicle, coordinate: vehicle.coordinate)], from: F.neubau, now: F.t0).first)
        XCTAssertEqual(RadarMineText.vehicleTitle(row.title, direction: row.direction), "Bus 13A → Hauptbahnhof")
        XCTAssertEqual(RadarMineText.nearDetail(row, now: F.t0), "240 m · nächster Halt Neubaugasse in 2 Min (+1)")
        XCTAssertEqual(RadarMineText.nearSpoken(row, now: F.t0),
                       "Bus 13A nach Hauptbahnhof, 240 Meter entfernt, nächster Halt Neubaugasse in 2 Minuten, 1 Minute verspätet, Position berechnet")
        let tram = F.vehicle("b", line: F.tramD, at: F.point(north: 500))
        let tramRow = try XCTUnwrap(RadarNearby.rows([RadarMineSighting(vehicle: tram, coordinate: tram.coordinate, isEstimate: true)],
                                                     from: F.neubau, now: F.t0).first)
        XCTAssertTrue(RadarMineText.nearSpoken(tramRow, now: F.t0).hasPrefix("Straßenbahn D nach Hauptbahnhof"))
        XCTAssertTrue(RadarMineText.nearSpoken(tramRow, now: F.t0).hasSuffix("Position geschätzt"))
    }

    func testTheStopRowAndItsSentence() throws {
        let board = Board(kind: .departures, entries: [F.entry("a", inMinutes: 3, delayMinutes: 1, position: F.point(north: 1200))])
        let row = try XCTUnwrap(RadarStopArrivals.rows(board: board, fetchedAt: F.t0, stop: F.neubau, radar: [:], now: F.t0).first)
        XCTAssertEqual(RadarMineText.departure(row), "ab \(row.row.time) · Steig 2")
        XCTAssertEqual(RadarMineText.delayChip(row.eta), "+1")
        XCTAssertEqual(RadarMineText.position(row.position), "noch 1,2 km")
        let spoken = RadarMineText.arrivalSpoken(row, number: 1, now: F.t0)
        XCTAssertTrue(spoken.hasPrefix("Bus 13A nach Hauptbahnhof, ab "), spoken)
        XCTAssertTrue(spoken.contains(", in 4 Minuten, 1 Minute verspätet, Steig 2, noch 1,2 Kilometer entfernt, Position berechnet"), spoken)
        XCTAssertTrue(spoken.hasSuffix("Nummer 1 auf der Karte"))
        let stale = RadarMineText.arrivalSpoken(row, number: nil, now: F.t0.addingTimeInterval(200))
        XCTAssertTrue(stale.contains("Position vor 3 Minuten"), stale)
        XCTAssertTrue(RadarMineText.stand(F.t0).hasPrefix("Stand "))
        XCTAssertEqual(RadarMineText.from("Neubaugasse"), "Ab Neubaugasse")
    }

    func testHonesty() {
        let all = [RadarMineText.noneLoaded, RadarMineText.nearEmpty, RadarMineText.nearEmptyFiltered, RadarMineText.stopEmpty,
                   RadarMineText.stopFooter, RadarMineText.nearIntro, RadarMineText.nearFooter, RadarMineText.maybeTwice, RadarMineText.linesFooter,
                   RadarMineText.linesEmpty, RadarMineText.denied, RadarMineText.noFix, RadarMineText.cityOff, RadarMineText.highlightFooter]
        for text in all {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("es fährt nichts"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("keine Busse"), text)
            XCTAssertFalse(text.contains("Sie "), "du-Form: \(text)")
            XCTAssertFalse(text.contains("GPS") && !text.contains("kein GPS"), "never claims GPS: \(text)")
        }
        // Empty results say what the Auskunft knows.
        for text in [RadarMineText.noneLoaded, RadarMineText.nearEmpty, RadarMineText.stopEmpty] {
            XCTAssertTrue(text.contains("Auskunft kennt"), text)
        }
        XCTAssertTrue(RadarMineText.stopFooter.contains("berechnet, kein GPS"))
        XCTAssertTrue(RadarMineText.stopFooter.contains("Luftlinie"))
        // The near page says that the tiles around you are loaded.
        XCTAssertTrue(RadarMineText.nearIntro.contains("Kartenausschnitte rund um dich"))
        XCTAssertTrue(RadarMineText.nearIntro.contains("Standort bleibt auf dem iPhone"))
    }
}
