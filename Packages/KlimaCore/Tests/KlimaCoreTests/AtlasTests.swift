import XCTest
@testable import KlimaCore

final class AtlasTests: XCTestCase {
    let cal = Calendar.vienna

    // Real coordinates from App/Resources/stations.json.
    let stAnton = Station(id: "at:47:1222", name: "St. Anton am Arlberg", lat: 47.12739, lon: 10.26699, state: "T")
    let landeck = Station(id: "at:47:1212", name: "Landeck-Zams", lat: 47.14842, lon: 10.57828, state: "T")
    let innsbruck = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26353, lon: 11.40028, state: "T",
                            aliases: ["Innsbruck Hbf"])
    let bludenz = Station(id: "at:48:130", name: "Bludenz", lat: 47.15529, lon: 9.81408, state: "V")
    let wienRail = Station(id: "at:49:1349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W")
    let wienMetro = Station(id: "wl:60201349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W", kind: .metro)
    let praterstern = Station(id: "wl:60201040", name: "Wien Praterstern", lat: 48.21851, lon: 16.39233, state: "W", kind: .metro)
    let klagenfurt = Station(id: "at:42:3642", name: "Klagenfurt Hauptbahnhof", lat: 46.61621, lon: 14.31314, state: "K")
    let lindau = Station(id: "x:lindau", name: "Lindau-Reutin", lat: 47.5536, lon: 9.7034, state: "X")

    var index: StationIndex {
        StationIndex(stations: [stAnton, landeck, innsbruck, bludenz, wienRail, wienMetro, praterstern, klagenfurt, lindau])
    }

    func date(_ m: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    func trip(_ a: Station?, _ b: Station?, fromName: String? = nil, toName: String? = nil, mode: TransportMode = .train,
              fare: Double = 10, km: Double = 30, round: Bool = false, day: Int = 1, states: Set<String> = []) -> TripRecord {
        TripRecord(date: date(3, day), fromName: fromName ?? a?.name ?? "?", toName: toName ?? b?.name ?? "?",
                   fromStationID: a?.id, toStationID: b?.id, mode: mode, distanceKm: km, fareEUR: fare, isRoundTrip: round,
                   states: states)
    }

    // MARK: Aggregation

    func testRoutesMergeBothDirectionsAndCountLegs() {
        let trips = [
            trip(stAnton, landeck, round: true, day: 1),
            trip(landeck, stAnton, day: 2),
            trip(stAnton, landeck, mode: .bus, day: 3),
        ]
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.routes.count, 1)
        let r = s.routes[0]
        XCTAssertEqual(r.legs, 4)
        XCTAssertEqual(r.entries, 3)
        XCTAssertEqual(r.value, 40, accuracy: 0.001)
        XCTAssertEqual(r.distanceKm, 120, accuracy: 0.001)
        XCTAssertEqual(r.dominantMode, .train)
        XCTAssertEqual(r.modes, [.train, .bus])
        XCTAssertEqual(r.rank, 1)
        XCTAssertEqual(r.weight, 1, accuracy: 0.0001)
        // Canonical west → east orientation.
        XCTAssertEqual(r.from.name, "St. Anton am Arlberg")
        XCTAssertEqual(r.to.name, "Landeck-Zams")
        // Newest first.
        XCTAssertEqual(r.tripIDs.first, trips[2].id)
        XCTAssertEqual(s.mappedTripCount, 3)
        XCTAssertEqual(s.unmappedTripCount, 0)
    }

    func testPlacesWithSameCoordinatesMerge() {
        let trips = [trip(wienRail, praterstern), trip(wienMetro, praterstern, mode: .metro, round: true)]
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.places.count, 2, "rail and U-Bahn 'Wien Hauptbahnhof' are one place")
        XCTAssertEqual(s.routes.count, 1)
        XCTAssertEqual(s.routes[0].legs, 3)
        let hbf = s.places.first { $0.name == "Wien Hauptbahnhof" }
        XCTAssertEqual(hbf?.visits, 3)
        XCTAssertEqual(hbf?.dominantMode, .metro, "U-Bahn has more legs here (2 vs 1)")
    }

    func testPlaceModeTieGoesToMoreValuableMode() {
        let trips = [trip(wienRail, innsbruck, fare: 92.8), trip(wienMetro, praterstern, mode: .metro, fare: 3.2)]
        let hbf = Atlas.summarize(trips, stations: index).places.first { $0.name == "Wien Hauptbahnhof" }
        XCTAssertEqual(hbf?.visits, 2)
        XCTAssertEqual(hbf?.dominantMode, .train)
    }

    func testNameFallbackResolvesAliases() {
        let t = trip(nil, nil, fromName: "Innsbruck Hbf", toName: "St. Anton am Arlberg")
        let s = Atlas.summarize([t], stations: index)
        XCTAssertEqual(s.routes.count, 1)
        XCTAssertTrue(s.unmapped.isEmpty)
    }

    func testUnresolvedTripsAreListedSeparately() {
        let trips = [
            trip(nil, nil, fromName: "Innsbruck Congress", toName: "Hungerburg", mode: .cableCar, round: true),
            trip(innsbruck, nil, toName: "Innsbruck Marktplatz", mode: .tram),
            trip(innsbruck, nil, toName: "Innsbruck Marktplatz", mode: .tram, day: 4),
            trip(stAnton, innsbruck),
        ]
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.routes.count, 1)
        XCTAssertEqual(s.mappedTripCount, 1)
        XCTAssertEqual(s.unmappedTripCount, 3)
        XCTAssertEqual(s.unmapped.count, 2)
        // Entries vs. one-way journeys: the cable-car round trip counts twice.
        XCTAssertEqual(s.unmappedLegCount, 4)
        // Sorted by legs: the tram pair (2 legs, newest first) ties with the cable car round trip (2 legs) – value breaks the tie.
        let tram = s.unmapped.first { $0.mode == .tram }
        XCTAssertEqual(tram?.legs, 2)
        XCTAssertEqual(tram?.knownPlaceName, "Innsbruck Hauptbahnhof")
        XCTAssertEqual(tram?.tripIDs.first, trips[2].id)
        let cable = s.unmapped.first { $0.mode == .cableCar }
        XCTAssertNil(cable?.knownPlaceName)
        // The known end still counts as a visited station.
        XCTAssertEqual(s.places.first { $0.name == "Innsbruck Hauptbahnhof" }?.visits, 3)
    }

    func testSameStationIsAVisitWithoutRoute() {
        let s = Atlas.summarize([trip(wienRail, wienMetro)], stations: index)
        XCTAssertTrue(s.routes.isEmpty)
        XCTAssertEqual(s.places.count, 1)
        XCTAssertEqual(s.mappedTripCount, 1)
        XCTAssertTrue(s.unmapped.isEmpty)
    }

    func testVisitedStatesCombineTripStatesAndStationsButNeverForeign() {
        let trips = [
            trip(innsbruck, wienRail, states: ["T", "S", "OÖ", "NÖ", "W"]),
            trip(bludenz, lindau, states: ["V", "X"]),
        ]
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.visitedStates, [.tirol, .salzburg, .oberoesterreich, .niederoesterreich, .wien, .vorarlberg])
        XCTAssertFalse(s.visitedStates.contains(.foreign))
        XCTAssertFalse(s.isAllAustria)
        XCTAssertEqual(s.abroadPlaces.map(\.name), ["Lindau-Reutin"])
    }

    func testAllNineStatesFlag() {
        let t = trip(stAnton, landeck, states: Set(Atlas.austrianStates.map(\.rawValue)))
        let s = Atlas.summarize([t], stations: index)
        XCTAssertEqual(s.visitedStateCount, 9)
        XCTAssertTrue(s.isAllAustria)
    }

    func testExtremePoints() {
        let trips = [trip(bludenz, innsbruck), trip(wienRail, praterstern), trip(klagenfurt, innsbruck)]
        let e = Atlas.summarize(trips, stations: index).extremes
        XCTAssertEqual(e.north?.name, "Wien Praterstern")
        XCTAssertEqual(e.south?.name, "Klagenfurt Hauptbahnhof")
        XCTAssertEqual(e.west?.name, "Bludenz")
        XCTAssertEqual(e.east?.name, "Wien Praterstern")
        XCTAssertEqual(e.place(.west)?.name, "Bludenz")
    }

    func testExtremeDirectionsPerPlace() {
        let trips = [trip(bludenz, innsbruck), trip(wienRail, praterstern), trip(klagenfurt, innsbruck)]
        let s = Atlas.summarize(trips, stations: index)
        let id: (String) -> String = { name in s.places.first { $0.name == name }!.id }
        XCTAssertEqual(s.extremes.directions(of: id("Wien Praterstern")), [.north, .east])
        XCTAssertEqual(s.extremes.directions(of: id("Klagenfurt Hauptbahnhof")), [.south])
        XCTAssertEqual(s.extremes.directions(of: id("Bludenz")), [.west])
        XCTAssertEqual(s.extremes.directions(of: id("Innsbruck Hauptbahnhof")), [])
        XCTAssertEqual(AtlasExtremes().directions(of: "x"), [])
    }

    func testLongestTripAndTotals() {
        let trips = [trip(stAnton, landeck, km: 28), trip(innsbruck, wienRail, fare: 92.8, km: 476, round: true), trip(nil, nil, km: 2)]
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.longestTrip?.distanceKm, 476)
        XCTAssertEqual(s.tripCount, 3)
        XCTAssertEqual(s.totalDistanceKm, 28 + 952 + 2, accuracy: 0.001)
        XCTAssertEqual(s.totalValue, 10 + 185.6 + 10, accuracy: 0.001)
    }

    func testEmptyInputIsEmptySummary() {
        let s = Atlas.summarize([], stations: index)
        XCTAssertTrue(s.routes.isEmpty)
        XCTAssertNil(s.bounds)
        XCTAssertTrue(s.extremes.isEmpty)
    }

    func testRankingWeightsAndLabels() {
        var trips: [TripRecord] = []
        for d in 1...10 { trips.append(trip(stAnton, landeck, round: true, day: d)) }      // 20 legs
        for d in 1...3 { trips.append(trip(stAnton, bludenz, day: d)) }                    // 3 legs
        trips.append(trip(klagenfurt, wienRail))                                           // 1 leg
        let s = Atlas.summarize(trips, stations: index)
        XCTAssertEqual(s.routes.map(\.legs), [20, 3, 1])
        XCTAssertEqual(s.routes.map(\.rank), [1, 2, 3])
        XCTAssertEqual(s.routes[0].weight, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(s.routes[1].weight, s.routes[2].weight)
        XCTAssertGreaterThan(s.routes[2].weight, 0)
        XCTAssertEqual(s.places.first?.name, "St. Anton am Arlberg")
        XCTAssertEqual(s.places.first?.visits, 23)
        XCTAssertEqual(s.labelledPlaceIDs(limit: 2).count, 2)
        XCTAssertTrue(s.labelledPlaceIDs(limit: 1).contains(s.places[0].id))
        XCTAssertEqual(Atlas.weight(legs: 1, maxLegs: 1), 0.6)
    }

    // MARK: Arcs

    func testArcStartsAndEndsOnStationsAndBulgesNorth() {
        let a = stAnton.location, b = innsbruck.location
        let path = Atlas.arc(from: a, to: b, bend: 0.15, samples: 40)
        XCTAssertEqual(path.count, 41)
        XCTAssertEqual(path.first, a)
        XCTAssertEqual(path.last, b)
        let mid = path[20]
        let chordMidLat = (a.latitude + b.latitude) / 2
        XCTAssertGreaterThan(mid.latitude, chordMidLat, "positive bend bulges north for a west → east route")
        // Apex height ≈ 15 % of the chord.
        let apexKm = mid.distanceKm(to: GeoPoint(latitude: chordMidLat, longitude: (a.longitude + b.longitude) / 2))
        XCTAssertEqual(apexKm / a.distanceKm(to: b), 0.15, accuracy: 0.02)
        // Deterministic.
        XCTAssertEqual(path, Atlas.arc(from: a, to: b, bend: 0.15, samples: 40))
        // Negative bend mirrors to the south.
        XCTAssertLessThan(Atlas.arc(from: a, to: b, bend: -0.15, samples: 40)[20].latitude, chordMidLat)
    }

    func testDegenerateArc() {
        XCTAssertEqual(Atlas.arc(from: stAnton.location, to: stAnton.location, bend: 0.2).count, 2)
    }

    func testBaseBendShrinksWithLengthWithinLimits() {
        XCTAssertGreaterThan(Atlas.baseBend(chordKm: 5), Atlas.baseBend(chordKm: 100))
        XCTAssertGreaterThan(Atlas.baseBend(chordKm: 100), Atlas.baseBend(chordKm: 300))
        XCTAssertLessThanOrEqual(Atlas.baseBend(chordKm: 0.1), 0.24)
        XCTAssertGreaterThanOrEqual(Atlas.baseBend(chordKm: 2000), 0.07)
    }

    func testParallelRoutesFanOutToOppositeSides() {
        // St. Anton → Landeck and St. Anton → Innsbruck leave St. Anton almost in the same direction.
        var trips: [TripRecord] = []
        for d in 1...4 { trips.append(trip(stAnton, landeck, round: true, day: d)) }
        trips.append(trip(stAnton, innsbruck))
        let s = Atlas.summarize(trips, stations: index)
        let landeckRoute = s.routes.first { $0.to.name == "Landeck-Zams" }!
        let innsbruckRoute = s.routes.first { $0.to.name == "Innsbruck Hauptbahnhof" }!
        XCTAssertGreaterThan(landeckRoute.bend, 0)
        XCTAssertLessThan(innsbruckRoute.bend, 0, "the second route of a corridor bends to the other side")
        // Unrelated routes keep the default northward bend.
        let other = Atlas.summarize([trip(klagenfurt, wienRail)], stations: index).routes[0]
        XCTAssertGreaterThan(other.bend, 0)
    }

    func testBoundsIncludeArcs() {
        let s = Atlas.summarize([trip(innsbruck, wienRail)], stations: index)
        let bounds = s.bounds!
        XCTAssertTrue(bounds.contains(innsbruck.location))
        XCTAssertTrue(bounds.contains(wienRail.location))
        XCTAssertGreaterThan(bounds.maxLatitude, max(innsbruck.lat, wienRail.lat), "northward arc extends the bounds")
        for p in s.routes[0].path { XCTAssertTrue(bounds.contains(p)) }
    }

    // MARK: Viewport

    func testRegionFitsBoundsInVisibleBand() {
        let bounds = AtlasBounds.austria
        let w = 402.0, h = 874.0
        let insets = AtlasInsets(top: 140, bottom: 280)
        let r = Atlas.region(fitting: bounds, width: w, height: h, insets: insets, padding: 0.05)
        // Project a coordinate into view points with the same Web-Mercator maths MapKit uses.
        func point(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            let top = Atlas.mercatorY(r.centerLatitude + r.latitudeDelta / 2)
            let bottom = Atlas.mercatorY(r.centerLatitude - r.latitudeDelta / 2)
            let left = r.centerLongitude - r.longitudeDelta / 2
            let x = (lon - left) / r.longitudeDelta * w
            let y = (top - Atlas.mercatorY(lat)) / (top - bottom) * h
            return (x, y)
        }
        let nw = point(bounds.maxLatitude, bounds.minLongitude)
        let se = point(bounds.minLatitude, bounds.maxLongitude)
        XCTAssertGreaterThanOrEqual(nw.x, -0.5)
        XCTAssertLessThanOrEqual(se.x, w + 0.5)
        XCTAssertGreaterThanOrEqual(nw.y, insets.top - 0.5, "content starts below the top bar")
        XCTAssertLessThanOrEqual(se.y, h - insets.bottom + 0.5, "content ends above the bottom panel")
        // Aspect ratio matches the view (no MapKit re-fitting needed).
        let topY = Atlas.mercatorY(r.centerLatitude + r.latitudeDelta / 2)
        let bottomY = Atlas.mercatorY(r.centerLatitude - r.latitudeDelta / 2)
        let lonRad = r.longitudeDelta * .pi / 180
        XCTAssertEqual((topY - bottomY) / lonRad, h / w, accuracy: 0.001)
    }

    func testRegionRespectsMinimumSpanForTinyRoutes() {
        let b = AtlasBounds(points: [wienRail.location, praterstern.location])!
        let r = Atlas.region(fitting: b, width: 400, height: 300, minimumSpanKm: 8)
        XCTAssertGreaterThan(r.longitudeDelta * 111 * cos(48.2 * .pi / 180), 8)
    }

    func testProjectionMatchesRegionFitting() {
        let bounds = AtlasBounds(points: [stAnton.location, wienRail.location])!
        let r = Atlas.region(fitting: bounds, width: 400, height: 300, padding: 0)
        let west = Atlas.project(stAnton.location, in: r, width: 400, height: 300)
        let east = Atlas.project(wienRail.location, in: r, width: 400, height: 300)
        XCTAssertEqual(west.x, 0, accuracy: 0.5)
        XCTAssertEqual(east.x, 400, accuracy: 0.5)
        XCTAssertGreaterThan(west.y, east.y, "St. Anton lies south of Wien")
        let mid = Atlas.project(r.center, in: r, width: 400, height: 300)
        XCTAssertEqual(mid.x, 200, accuracy: 0.5)
    }

    func testMapKitCenterConversionRoundTrips() {
        let r = AtlasRegion(centerLatitude: 47.4, centerLongitude: 13, latitudeDelta: 4.5, longitudeDelta: 7.8)
        // Mercator centre of r = latitude in the middle of the view.
        let top = Atlas.mercatorY(r.centerLatitude + r.latitudeDelta / 2)
        let bottom = Atlas.mercatorY(r.centerLatitude - r.latitudeDelta / 2)
        let mercatorCenter = Atlas.inverseMercatorY((top + bottom) / 2)
        XCTAssertGreaterThan(mercatorCenter, r.centerLatitude)
        let back = Atlas.regionFromMapCenter(latitude: mercatorCenter, longitude: 13, latitudeDelta: 4.5, longitudeDelta: 7.8)
        XCTAssertEqual(back.centerLatitude, r.centerLatitude, accuracy: 0.0001)
        XCTAssertEqual(back.latitudeDelta, r.latitudeDelta, accuracy: 0.0001)
    }

    func testFanStepShrinksForLongRoutes() {
        XCTAssertEqual(Atlas.fanStep(chordKm: 50), 0.08, accuracy: 0.0001)
        XCTAssertLessThan(Atlas.fanStep(chordKm: 400), Atlas.fanStep(chordKm: 150))
        XCTAssertGreaterThanOrEqual(Atlas.fanStep(chordKm: 5000), 0.024)
    }

    func testStatesAreWestToEastAndAbbreviated() {
        XCTAssertEqual(Atlas.austrianStates.count, 9)
        XCTAssertEqual(Set(Atlas.austrianStates), Set(FederalState.allCases.filter { $0 != .foreign }))
        XCTAssertEqual(Atlas.austrianStates.first, .vorarlberg)
        XCTAssertEqual(Atlas.austrianStates.last, .burgenland)
        XCTAssertEqual(Atlas.abbreviation(.steiermark), "Stmk")
    }
}
