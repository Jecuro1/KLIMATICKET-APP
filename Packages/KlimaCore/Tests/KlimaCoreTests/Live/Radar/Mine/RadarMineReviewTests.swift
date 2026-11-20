import XCTest
@testable import KlimaCore

/// MARK: radar2-review-radarmine – what the review of „Meine Fahrzeuge“ found: a board that refuses its stop is linked anew once, not in every free
/// slot of the radar's budget; „In der Nähe“ says „kennt kein Fahrzeug“ only for the whole, loaded circle; a mode that is on but out of zoom is not
/// „aus“; VoiceOver hears the star, the number and the dimmed rest; the first board frames the stop with its numbered arrivals.
final class RadarMineReviewTests: XCTestCase {
    private typealias F = MineFixture
    private let t0 = MineFixture.t0

    // MARK: A board that refuses its link

    func testABoardThatRefusesTheNewLinkAsWellEndsTheStop() {
        var plan = RadarStopWatchPlan()
        plan.start(stopID: "osm:1", needsLink: true, now: t0)
        plan.started(.link, now: t0)
        plan.linked(now: t0.addingTimeInterval(1))
        plan.started(.board, now: t0.addingTimeInterval(2))
        XCTAssertTrue(plan.linkRefused(needsLink: true, now: t0.addingTimeInterval(3)), "the first refusal links the stop anew")
        XCTAssertNil(plan.inFlight)
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(3)), .link, "the new link in its own slot")
        plan.started(.link, now: t0.addingTimeInterval(4))
        plan.linked(now: t0.addingTimeInterval(5))
        plan.started(.board, now: t0.addingTimeInterval(6))
        XCTAssertFalse(plan.linkRefused(needsLink: true, now: t0.addingTimeInterval(7)), "the second refusal ends the stop")
        // A new stop may be linked anew once again.
        plan.start(stopID: "osm:2", needsLink: false, now: t0.addingTimeInterval(8))
        XCTAssertFalse(plan.relinked)
        plan.started(.board, now: t0.addingTimeInterval(8))
        XCTAssertTrue(plan.linkRefused(needsLink: false, now: t0.addingTimeInterval(9)))
        XCTAssertEqual(plan.nextJob(now: t0.addingTimeInterval(9)), .board, "a `uic:` stop needs no lookup: its board is due at once")
        plan.stop()
        XCTAssertFalse(plan.linkRefused(needsLink: false, now: t0.addingTimeInterval(10)), "no stop, nothing to link")
    }

    /// The loop as `RadarMineModel.run` drives it, with a board that refuses every link: before the fix it linked and asked again in every round
    /// (up to the radar's whole 24 a minute); now it asks at most twice for each and gives up.
    func testARefusingBoardCostsAtMostFourRequestsInTenMinutes() {
        for needsLink in [true, false] {
            var plan = RadarStopWatchPlan()
            plan.start(stopID: "stop", needsLink: needsLink, now: t0)
            var requests = 0
            var ended = false
            var second = 0.0
            while second < 600 && !ended {
                let now = t0.addingTimeInterval(second)
                if let job = plan.nextJob(now: now) {
                    plan.started(job, now: now)
                    requests += 1
                    if job == .link {
                        plan.linked(now: now)
                    } else if !plan.linkRefused(needsLink: needsLink, now: now) {
                        plan.stop()
                        ended = true
                    }
                }
                second += 1
            }
            XCTAssertTrue(ended, "needsLink \(needsLink)")
            XCTAssertLessThanOrEqual(requests, needsLink ? 4 : 2, "needsLink \(needsLink)")
            XCTAssertNil(plan.nextJob(now: t0.addingTimeInterval(600)))
        }
    }

    // MARK: In der Nähe: what the list covers

    private func view(around point: GeoPoint, latitudeSpan: Double) -> RadarBox {
        let lon = latitudeSpan * 1.5
        return RadarBox(north: point.latitude + latitudeSpan / 2, west: point.longitude - lon / 2,
                        south: point.latitude - latitudeSpan / 2, east: point.longitude + lon / 2)
    }

    func testTheEmptyListIsTrueOnlyForTheWholeLoadedCircle() {
        let fix = F.neubau
        // The page's own camera move: about 3 km around the fix.
        let around = view(around: fix, latitudeSpan: RadarNearby.viewSpanKm / RadarLanePlan.kmPerDegreeLatitude)
        XCTAssertTrue(RadarNearby.circleShown(fix, in: around))
        func coverage(_ box: RadarBox, loads: Bool = true, pending: Bool = false, city: Bool = true, out: Bool = false) -> RadarNearby.Coverage {
            RadarNearby.coverage(fix: fix, box: box, loads: loads, pending: pending, cityModesOn: city, cityOutOfZoom: out)
        }
        XCTAssertEqual(coverage(around), .complete)
        XCTAssertEqual(coverage(around, pending: true), .loading, "the new tiles have not answered yet")
        XCTAssertEqual(coverage(around, loads: false), .notLoading, "train layer off, no live data, Zeitreise, Cockpit, Low Power Mode")
        XCTAssertEqual(coverage(view(around: F.point(east: 1200), latitudeSpan: 0.027)), .offMap, "the map moved a kilometre east")
        XCTAssertEqual(coverage(view(around: fix, latitudeSpan: 0.01)), .offMap, "zoomed in: part of the circle is off the map")
        XCTAssertEqual(coverage(view(around: fix, latitudeSpan: 1.2), out: true), .cityOutOfZoom, "zoomed out past the city lane")
        XCTAssertEqual(coverage(view(around: fix, latitudeSpan: 1.2), city: false, out: true), .complete, "only trains: nothing is missing")
        XCTAssertFalse(RadarNearby.circleShown(GeoPoint(latitude: .nan, longitude: 16), in: around))
        XCTAssertFalse(RadarNearby.circleShown(fix, in: around, radiusKm: .infinity))
    }

    func testEveryCoverageTextSaysWhatItKnows() {
        for text in [RadarMineText.nearOffMap, RadarMineText.nearNotLoading, RadarMineText.modesOutOfZoom([.bus])] {
            XCTAssertFalse(text.contains("fährt nichts"), text)
            XCTAssertFalse(text.contains("keine Fahrzeuge unterwegs"), text)
        }
        XCTAssertEqual(RadarMineText.nearOffMap, "Die Karte zeigt gerade nicht den ganzen Umkreis. Die Liste nennt nur, was dort zu sehen ist.")
        XCTAssertEqual(RadarMineText.nearNotLoading, "Das Radar lädt gerade nichts nach. Die Liste nennt nur, was schon geladen ist.")
        XCTAssertEqual(RadarMineText.toCircle, "Zum Umkreis")
    }

    // MARK: Haltestelle: off or out of zoom

    func testAModeOutOfZoomIsNotCalledOff() {
        XCTAssertEqual(RadarMineText.modesOutOfZoom([.bus]),
                       "Bus erscheint auf der Karte, wenn du näher heranzoomst – diese Abfahrten stehen schon in der Liste.")
        XCTAssertEqual(RadarMineText.modesOutOfZoom([.bus, .tram]),
                       "Bus und Bim erscheinen auf der Karte, wenn du näher heranzoomst – diese Abfahrten stehen schon in der Liste.")
        XCTAssertFalse(RadarMineText.modesOutOfZoom([.bus, .tram, .subway]).contains(" aus"))
        XCTAssertTrue(RadarMineText.modesOffMap([.bus]).hasPrefix("Bus ist aus"))
    }

    // MARK: VoiceOver on the map

    func testTheMarkerSaysWhatTheDecorationDraws() {
        XCTAssertEqual(RadarMineText.markerValue(star: false, number: 2, dimmed: false), "Nummer 2 der Abfahrten")
        XCTAssertEqual(RadarMineText.markerValue(star: true, number: nil, dimmed: false), "deine Linie")
        XCTAssertEqual(RadarMineText.markerValue(star: false, number: nil, dimmed: true), "nicht hervorgehoben")
        XCTAssertEqual(RadarMineText.markerValue(star: false, number: nil, dimmed: false), "")
    }

    // MARK: The highlight's cap between two passes (second review)

    /// Only what the last pass chose stays single: before the first pass nothing (switching the highlight on used to make every vehicle of your
    /// lines single until the pass ran), never more than 60, and a vehicle that came in after the pass groups until the next one.
    func testTheHighlightCapHoldsBetweenTwoPasses() {
        var selection = RadarMineHighlight.Selection()
        XCTAssertFalse(selection.keepsSingle("t0"), "before the first pass nothing is single")
        let many = (0..<200).map { RadarMineHighlight.Candidate(tripID: "t\($0)", coordinate: F.point(north: Double($0) * 50)) }
        XCTAssertTrue(selection.update(many, centre: F.neubau))
        XCTAssertEqual(selection.tripIDs.count, RadarMineHighlight.singleCap)
        XCTAssertEqual(many.filter { selection.keepsSingle($0.tripID) }.count, 60)
        XCTAssertTrue(selection.keepsSingle("t0"))
        XCTAssertFalse(selection.keepsSingle("t199"), "the far ones group")
        XCTAssertFalse(selection.update(many, centre: F.neubau), "the same markers: no regrouping")
        XCTAssertFalse(selection.keepsSingle("new"), "a vehicle the last pass did not see groups until the next")
        let few = Array(many.prefix(12)) + [RadarMineHighlight.Candidate(tripID: "new", coordinate: F.neubau)]
        XCTAssertTrue(selection.update(few, centre: F.neubau))
        XCTAssertEqual(selection.tripIDs, Set(few.map(\.tripID)), "up to the cap every one of them")
        XCTAssertTrue(selection.clear())
        XCTAssertFalse(selection.keepsSingle("new"))
        XCTAssertFalse(selection.clear(), "nothing left to regroup")
        XCTAssertEqual(RadarMineText.groupValue, "mit deiner Linie")
    }

    /// The board is a side job of the radar's loop: while the whole radar pauses, the page says so instead of letting its „Stand“ grow old in silence.
    func testThePausedRadarIsSaid() {
        XCTAssertEqual(RadarMineText.radarPaused, "Das Radar pausiert gerade – die Abfahrten auch, bis es weiterlädt.")
        XCTAssertFalse(RadarMineText.radarPaused.contains("Sie "), "du-Form")
    }

    // MARK: The first board frames the stop and its arrivals

    func testTheFrameHoldsTheStopAndEveryNumberedArrival() throws {
        let stop = F.neubau
        let points = [F.point(north: 600, east: 200), F.point(east: 1100), F.point(north: -2300, east: 600), F.point(north: -2000, east: -2600)]
        let frame = try XCTUnwrap(RadarStopArrivals.frame(stop: stop, points: points))
        for point in [stop] + points {
            XCTAssertLessThanOrEqual(abs(point.latitude - frame.centre.latitude), frame.latitudeSpan / 2, "\(point)")
            XCTAssertLessThanOrEqual(abs(point.longitude - frame.centre.longitude), frame.longitudeSpan / 2, "\(point)")
        }
        XCTAssertLessThanOrEqual(frame.latitudeSpan, 0.3, "inside the city lane's zoom")
        let alone = try XCTUnwrap(RadarStopArrivals.frame(stop: stop, points: []))
        XCTAssertEqual(alone.latitudeSpan, 0.012, accuracy: 1e-12, "the stop alone: the stop page's own zoom")
        XCTAssertEqual(alone.longitudeSpan, 0.018, accuracy: 1e-12)
        XCTAssertEqual(alone.centre, stop)
        let far = try XCTUnwrap(RadarStopArrivals.frame(stop: stop, points: [F.point(north: 80_000)]))
        XCTAssertEqual(far.latitudeSpan, 0.3, accuracy: 1e-12, "a far point never zooms out of the city lane")
        XCTAssertNil(RadarStopArrivals.frame(stop: stop, points: [GeoPoint(latitude: .nan, longitude: 16)]))
    }
}
