import XCTest
@testable import KlimaCore

final class CockpitSummaryTests: XCTestCase {
    typealias F = CockpitFixtures

    private func summary(_ route: CockpitRoute, km: Double, now: Date, speed: CockpitSpeedEstimator.Reading = .unknown, age: TimeInterval? = nil) -> CockpitSummary {
        CockpitSummary.make(route: route, km: km, now: now, speed: speed, fixAge: age, lineTitle: "RJX 66", destination: "Ziel")
    }

    private func between(_ route: CockpitRoute, _ from: Int, _ to: Int) -> Double {
        (route.stops[from].km + route.stops[to].km) / 2
    }

    func testUnderwayShowsTheNextStopEtaPlatformAndDistance() {
        var stops = F.fourStops()
        stops[2].arrDelay = 4
        stops[2].depDelay = 4
        let route = F.route(stops)
        let km = between(route, 1, 2)
        let s = summary(route, km: km, now: F.at(47), speed: .moving(kmh: 118), age: 8)
        XCTAssertEqual(s.phase, .underway)
        XCTAssertEqual(s.nextStop, "Halt 2")
        XCTAssertFalse(s.nextIsFinal)
        XCTAssertEqual(s.platform?.text, "Gl. 2")
        XCTAssertEqual(s.plannedETA, F.at(62))
        XCTAssertEqual(s.eta, F.at(66))
        XCTAssertEqual(s.delaySeconds, 240)
        XCTAssertEqual(s.delayState, .onTime)
        XCTAssertEqual(s.distanceKm ?? -1, (route.stops[2].km - route.stops[1].km) / 2, accuracy: 0.01)
        XCTAssertEqual(s.speed, .moving(kmh: 118))
        XCTAssertEqual(s.fixAge, 8)
        XCTAssertEqual(s.upcoming.map(\.id), [2, 3])
        XCTAssertEqual(s.upcoming.first?.eta, F.at(66))
        XCTAssertEqual(s.lineTitle, "RJX 66")
        XCTAssertFalse(s.isStraightLine)
    }

    func testFiveMinutesLateIsLate() {
        var stops = F.fourStops()
        stops[2].arrDelay = 5
        let route = F.route(stops)
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        XCTAssertEqual(s.delayState, .late)
        stops[2].arrDelay = 4.9
        let almost = F.route(stops)
        XCTAssertEqual(summary(almost, km: between(almost, 1, 2), now: F.at(47)).delayState, .onTime)
    }

    func testTheDelayCarriesOnToAStopWithoutAReport() {
        var stops = F.fourStops()
        stops[1].arrDelay = 7
        stops[1].depDelay = 7
        let route = F.route(stops)
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        XCTAssertEqual(s.delaySeconds, 420, "no report for C: the 7 minutes of B carry on")
        XCTAssertEqual(s.delayState, .late)
        XCTAssertEqual(s.eta, F.at(62), "the time stays the planned one: nothing is predicted")
    }

    func testNoRealtimeIsUnknown() {
        let route = F.route()
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        XCTAssertNil(s.delaySeconds)
        XCTAssertEqual(s.delayState, .unknown)
        XCTAssertEqual(CockpitText.delayChip(seconds: s.delaySeconds, state: s.delayState), "Keine Echtzeit")
    }

    func testCancelledRun() {
        let route = F.route(F.fourStops(delay: 0), cancelled: true)
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        XCTAssertEqual(s.phase, .cancelled)
        XCTAssertEqual(s.delayState, .cancelled)
        XCTAssertEqual(CockpitText.delayChip(seconds: s.delaySeconds, state: s.delayState), "Fällt aus")
        XCTAssertEqual(CockpitText.phaseLine(s), "Dieser Zug fällt aus")
        XCTAssertEqual(CockpitText.share(s), "RJX 66 nach Ziel fällt aus.")
    }

    func testStandingAtAStop() {
        let route = F.route(F.fourStops(delay: 0))
        let s = summary(route, km: route.stops[1].km, now: F.at(31))
        XCTAssertEqual(s.phase, .atStop(stop: "Halt 1", departure: F.at(32)))
        XCTAssertEqual(s.nextStop, "Halt 2", "the big stop is the one after the stop it stands at")
        XCTAssertEqual(CockpitText.phaseLine(s), "Hält in Halt 1 · weiter um 20:32")
    }

    func testBeforeDeparture() {
        let route = F.route()
        let s = summary(route, km: route.stops[0].km, now: F.at(-5))
        XCTAssertEqual(s.phase, .beforeDeparture(stop: "Halt 0", departure: F.at(0)))
        XCTAssertEqual(s.nextStop, "Halt 1")
        XCTAssertEqual(CockpitText.phaseLine(s), "Steht in Halt 0 · Abfahrt 20:00")
        XCTAssertEqual(s.progress, 0, accuracy: 1e-6)
    }

    func testArrived() {
        let route = F.route()
        let s = summary(route, km: route.lastKm, now: F.at(96))
        XCTAssertEqual(s.phase, .arrived(stop: "Halt 3"))
        XCTAssertNil(s.nextStop)
        XCTAssertNil(s.eta)
        XCTAssertNil(s.distanceKm)
        XCTAssertEqual(s.progress, 1, accuracy: 1e-6)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(CockpitText.stopLabel(s), "Ziel erreicht")
        XCTAssertEqual(CockpitText.share(s), "RJX 66 nach Ziel hat Halt 3 erreicht.")
    }

    func testTheLastStopIsLabelledZiel() {
        let route = F.route()
        let s = summary(route, km: between(route, 2, 3), now: F.at(80))
        XCTAssertTrue(s.nextIsFinal)
        XCTAssertEqual(CockpitText.stopLabel(s), "Ziel")
        XCTAssertEqual(CockpitText.stopLabel(summary(route, km: between(route, 0, 1), now: F.at(10))), "Nächster Halt")
    }

    func testProgressAndTicks() {
        let route = F.route()
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.02)
        XCTAssertEqual(s.stopTicks.count, 4)
        XCTAssertEqual(s.stopTicks.first ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(s.stopTicks.last ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(s.stopTicks, s.stopTicks.sorted())
        // Stops the train does not serve have no tick.
        var stops = F.fourStops()
        stops[1].passes = true
        XCTAssertEqual(summary(F.route(stops), km: 50, now: F.at(10)).stopTicks.count, 3)
    }

    func testCountdownRules() {
        let route = F.route(F.fourStops(delay: 0))
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))   // arrives at +62
        XCTAssertEqual(s.secondsToArrival(now: F.at(47)), 15 * 60)
        XCTAssertTrue(s.showsCountdown(now: F.at(47)))
        XCTAssertTrue(s.showsCountdown(now: F.at(63)), "a minute late is still 'gleich'")
        XCTAssertFalse(s.showsCountdown(now: F.at(65)), "long past: no countdown, the time stays")
        XCTAssertFalse(summary(route, km: route.lastKm, now: F.at(96)).showsCountdown(now: F.at(96)))
    }

    // MARK: Words

    func testCountdownText() {
        XCTAssertEqual(CockpitText.countdown(seconds: 12 * 60), "in 12 Min")
        XCTAssertEqual(CockpitText.countdown(seconds: 29), "gleich")
        XCTAssertEqual(CockpitText.countdown(seconds: -20), "gleich")
        XCTAssertEqual(CockpitText.countdown(seconds: 40), "in 1 Min")
        XCTAssertEqual(CockpitText.countdown(seconds: 65 * 60), "in 1 Std 05 Min")
        XCTAssertNil(CockpitText.countdown(seconds: -300))
        XCTAssertNil(CockpitText.countdown(seconds: .nan))
        XCTAssertEqual(CockpitText.spokenCountdown(seconds: 12 * 60), "in 12 Minuten")
        XCTAssertEqual(CockpitText.spokenCountdown(seconds: 60), "in einer Minute")
        XCTAssertEqual(CockpitText.spokenCountdown(seconds: 65 * 60), "in einer Stunde und 5 Minuten")
        XCTAssertEqual(CockpitText.spokenCountdown(seconds: 120 * 60), "in 2 Stunden")
    }

    func testDelayChipText() {
        XCTAssertEqual(CockpitText.delayChip(seconds: 0, state: .onTime), "pünktlich")
        XCTAssertEqual(CockpitText.delayChip(seconds: 29, state: .onTime), "pünktlich")
        XCTAssertEqual(CockpitText.delayChip(seconds: 240, state: .onTime), "+4 min")
        XCTAssertEqual(CockpitText.delayChip(seconds: 900, state: .late), "+15 min")
        XCTAssertEqual(CockpitText.delayChip(seconds: -120, state: .onTime), "\u{2212}2 min")
        XCTAssertEqual(CockpitText.delayChip(seconds: nil, state: .unknown), "Keine Echtzeit")
        XCTAssertEqual(CockpitText.delayChip(seconds: 600, state: .cancelled), "Fällt aus")
        XCTAssertEqual(CockpitText.spokenDelay(seconds: 240, state: .onTime), "4 Minuten verspätet")
        XCTAssertEqual(CockpitText.spokenDelay(seconds: 60, state: .onTime), "1 Minute verspätet")
        XCTAssertEqual(CockpitText.spokenDelay(seconds: -120, state: .onTime), "2 Minuten früher")
        XCTAssertEqual(CockpitText.spokenDelay(seconds: nil, state: .unknown), "ohne Echtzeit-Daten")
        XCTAssertEqual(CockpitText.spokenDelay(seconds: 0, state: .onTime), "pünktlich")
    }

    func testDistanceText() {
        XCTAssertEqual(CockpitText.distance(km: 0.03), "unter 50 m")
        XCTAssertEqual(CockpitText.distance(km: 0.85), "850 m")
        XCTAssertEqual(CockpitText.distance(km: 0.874), "850 m")
        XCTAssertEqual(CockpitText.distance(km: 0.9), "900 m")
        XCTAssertEqual(CockpitText.distance(km: 4.34), "4,3 km")
        XCTAssertEqual(CockpitText.distance(km: 18.4), "18 km")
        XCTAssertEqual(CockpitText.distance(km: -3), "unter 50 m")
        XCTAssertEqual(CockpitText.distance(km: .nan), "–")
        XCTAssertEqual(CockpitText.spokenDistance(km: 4.34), "4,3 Kilometer")
        XCTAssertEqual(CockpitText.spokenDistance(km: 0.85), "850 Meter")
        XCTAssertEqual(CockpitText.spokenDistance(km: 18.4), "18 Kilometer")
    }

    func testSpeedText() {
        XCTAssertEqual(CockpitText.speed(.moving(kmh: 117.6)), "ca. 118 km/h · geschätzt")
        XCTAssertEqual(CockpitText.speedValue(kmh: 117.6), "ca. 118 km/h")
        XCTAssertNil(CockpitText.speed(.standing), "nothing is shown while the train stands")
        XCTAssertNil(CockpitText.speed(.unknown), "nothing is shown without an estimate")
        XCTAssertEqual(CockpitText.spokenSpeed(.moving(kmh: 117.6)), "etwa 118 Kilometer pro Stunde, geschätzt")
        XCTAssertNil(CockpitText.spokenSpeed(.standing))
    }

    func testAgeText() {
        XCTAssertEqual(CockpitText.age(8), "Stand vor 8 s")
        XCTAssertEqual(CockpitText.age(1), "Stand gerade eben")
        XCTAssertEqual(CockpitText.age(130), "Stand vor 2 Min")
        XCTAssertEqual(CockpitText.spokenAge(8), "Stand vor 8 Sekunden")
    }

    func testLinkTexts() {
        XCTAssertEqual(CockpitText.lostTitle, "Keine Position mehr")
        XCTAssertEqual(CockpitText.lostDetail(reason: .notListed, sinceSeconds: 150), "Die Auskunft meldet den Zug gerade nicht. Zuletzt gesehen vor 2 Min.")
        XCTAssertEqual(CockpitText.lostDetail(reason: .noAnswers, sinceSeconds: nil), "Keine Verbindung zu ÖBB.")
        XCTAssertEqual(CockpitText.endedTitle, "Fahrt beendet")
        XCTAssertEqual(CockpitText.endedDetail(lastStop: "Linz Hbf", reachedLastStop: true), "Der Zug hat Linz Hbf erreicht.")
        XCTAssertEqual(CockpitText.endedDetail(lastStop: "Linz Hbf", reachedLastStop: false), "Die Fahrt ist laut Fahrplan zu Ende.")
    }

    func testTheHudIsOneSpokenSentence() {
        var stops = F.fourStops()
        stops[2].arrDelay = 4
        stops[2].depDelay = 4
        let route = F.route(stops)
        let s = summary(route, km: between(route, 1, 2), now: F.at(47), speed: .moving(kmh: 118), age: 8)
        let spoken = CockpitText.spoken(s, now: F.at(47))
        XCTAssertTrue(spoken.hasPrefix("RJX 66 nach Ziel. Nächster Halt Halt 2, Gleis 2."), spoken)
        XCTAssertTrue(spoken.contains("Ankunft 21:06 Uhr, 4 Minuten verspätet, in 19 Minuten"), spoken)
        XCTAssertTrue(spoken.contains("noch 37 Kilometer"), spoken)
        XCTAssertTrue(spoken.contains("50 Prozent der Strecke"), spoken)
        XCTAssertTrue(spoken.contains("etwa 118 Kilometer pro Stunde, geschätzt"), spoken)
        XCTAssertTrue(spoken.hasSuffix("Stand vor 8 Sekunden."), spoken)
    }

    func testSpokenWithoutSpeedWhenStanding() {
        let route = F.route(F.fourStops(delay: 0))
        let spoken = CockpitText.spoken(summary(route, km: route.stops[1].km, now: F.at(31), speed: .standing), now: F.at(31))
        XCTAssertFalse(spoken.contains("Kilometer pro Stunde"))
        XCTAssertTrue(spoken.contains("hält in Halt 1, weiter um 20:32 Uhr"), spoken)
    }

    func testSharedTextHasNoCoordinates() {
        var stops = F.fourStops()
        stops[2].arrDelay = 4
        stops[2].depDelay = 4
        let route = F.route(stops)
        let s = summary(route, km: between(route, 1, 2), now: F.at(47))
        let text = CockpitText.share(s)
        XCTAssertEqual(text, "RJX 66 nach Ziel: nächster Halt Halt 2, Ankunft 21:06 (+4 min). Live verfolgt mit KlimaBilanz.")
        XCTAssertFalse(text.contains("48."))
        XCTAssertFalse(text.contains("°"))
    }

    func testSharedTextWithoutRealtimeSaysNothingAboutTheDelay() {
        let route = F.route()
        let text = CockpitText.share(summary(route, km: between(route, 1, 2), now: F.at(47)))
        XCTAssertEqual(text, "RJX 66 nach Ziel: nächster Halt Halt 2, Ankunft 21:02. Live verfolgt mit KlimaBilanz.")
    }

    func testHonestyNotes() {
        XCTAssertTrue(CockpitText.positionNote.contains("keine GPS-Ortung"))
        XCTAssertEqual(CockpitText.straightLineNote, "Luftlinie zwischen den Halten")
    }
}
