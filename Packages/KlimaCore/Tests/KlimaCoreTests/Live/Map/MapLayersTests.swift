import XCTest
@testable import KlimaCore

/// Scotty-style map layers (docs/OEBB_LIVE.md §R10): layer state, the stations in view, clustering, the route sketch. Offline.
final class MapLayersTests: XCTestCase {
    private func pin(_ id: String, _ name: String, _ lat: Double, _ lon: Double) -> MapStationPin {
        MapStationPin(id: id, name: name, coordinate: GeoPoint(latitude: lat, longitude: lon))
    }

    private let vienna = RadarBox(north: 48.30, west: 16.20, south: 48.10, east: 16.50)

    // MARK: - Layer state

    func testInitialViewIsStationsAndTrains() {
        XCTAssertEqual(MapLayerSelection.initial.layers, [.stations, .trains])
        XCTAssertFalse(MapLayerSelection.initial.isOn(.disruptions))
        XCTAssertFalse(MapLayerSelection.initial.isOn(.routes))
    }

    func testToggleAddsAndRemoves() {
        var selection = MapLayerSelection.initial
        selection.toggle(.routes)
        XCTAssertTrue(selection.isOn(.routes))
        selection.toggle(.trains)
        XCTAssertFalse(selection.isOn(.trains))
        XCTAssertEqual(selection.layers, [.stations, .routes])
    }

    func testStorageRoundTripKeepsOrderAndDropsUnknownWords() {
        let all = MapLayerSelection.all
        XCTAssertEqual(all.storageValue, "stations,trains,disruptions,routes")
        XCTAssertEqual(MapLayerSelection(storageValue: all.storageValue), all)
        XCTAssertEqual(MapLayerSelection(storageValue: "routes,unbekannt,trains").layers, [.trains, .routes])
        XCTAssertEqual(MapLayerSelection(storageValue: "").layers, [], "an empty value means every layer is off")
        XCTAssertEqual(MapLayerSelection(storageValue: "nonsense").layers, [])
    }

    func testLayerTitlesAreGerman() {
        XCTAssertEqual(MapLayer.allCases.map(\.title), ["Stationen", "Züge", "Störungen", "Meine Routen"])
    }

    // MARK: - Stations in view

    func testOnlyStationsInsideTheBoxAreVisible() {
        let stations = [
            pin("a", "Wien Hbf", 48.185, 16.375),
            pin("b", "St. Pölten Hbf", 48.200, 15.620),
            pin("c", "Wien Meidling", 48.177, 16.333),
        ]
        let visible = MapStations.visible(stations, in: vienna)
        XCTAssertEqual(visible.map(\.id), ["a", "c"], "Wien Hbf and Wien Meidling are in the box, St. Pölten is not")
    }

    func testVisibleIsInNameOrderAndLimited() {
        let stations = (0..<10).map { pin("id\($0)", "Station \(9 - $0)", 48.2, 16.3) }
        let visible = MapStations.visible(stations, in: vienna, limit: 3)
        XCTAssertEqual(visible.map(\.name), ["Station 0", "Station 1", "Station 2"])
    }

    func testEveryStationInTheBoxIsKept() {
        // No cap in name order: a dense area keeps all its stations, the clusters bound the markers (see MapClustering).
        let dense = (0..<400).map { pin("s\($0)", "Station \($0)", 48.2, 16.3) }
        XCTAssertEqual(MapStations.visible(dense, in: vienna).count, 400)
    }

    func testInvalidBoxShowsNothing() {
        let broken = RadarBox(north: 48, west: 16, south: 48, east: 17)
        XCTAssertTrue(MapStations.visible([pin("a", "Wien", 48.2, 16.3)], in: broken).isEmpty)
    }

    func testBoxContainsIsInclusiveOnTheEdge() {
        XCTAssertTrue(vienna.contains(GeoPoint(latitude: 48.10, longitude: 16.20)))
        XCTAssertFalse(vienna.contains(GeoPoint(latitude: 48.31, longitude: 16.30)))
    }

    func testStationMarkersOnlyWhenZoomedIn() {
        XCTAssertTrue(MapStations.isDrawn(latitudeSpan: 0.5))
        XCTAssertTrue(MapStations.isDrawn(latitudeSpan: MapStations.maxLatitudeSpan))
        XCTAssertFalse(MapStations.isDrawn(latitudeSpan: 4.2), "a country-wide view draws no station markers")
        XCTAssertFalse(MapStations.isDrawn(latitudeSpan: .nan))
        XCTAssertFalse(MapStations.isDrawn(latitudeSpan: 0))
    }

    // MARK: - Clustering

    func testNearbyStationsMergeAndFarOnesStayApart() {
        let pins = [pin("a", "A", 48.200, 16.300), pin("b", "B", 48.201, 16.301), pin("c", "C", 48.500, 16.800)]
        let clusters = MapClustering.group(pins, cellDegrees: 0.1)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.first(where: { $0.count == 2 })?.memberIDs, ["a", "b"])
        XCTAssertEqual(clusters.first(where: { $0.isSingle })?.memberIDs, ["c"])
    }

    func testClusterIdsAreStableForTheSameInput() {
        let pins = [pin("a", "A", 48.2, 16.3), pin("b", "B", 47.9, 13.0), pin("c", "C", 47.2, 11.4)]
        let first = MapClustering.group(pins, cellDegrees: 0.05)
        XCTAssertEqual(first, MapClustering.group(pins.reversed(), cellDegrees: 0.05))
        XCTAssertEqual(first.map(\.count).reduce(0, +), 3)
    }

    func testBadCellSizeGivesNoClusters() {
        XCTAssertTrue(MapClustering.group([pin("a", "A", 48, 16)], cellDegrees: 0).isEmpty)
        XCTAssertTrue(MapClustering.group([pin("a", "A", 48, 16)], cellDegrees: .nan).isEmpty)
    }

    // MARK: - Route sketch

    func testRouteSketchNeedsTwoKnownPlaces() {
        let a = GeoPoint(latitude: 48.2, longitude: 16.3), b = GeoPoint(latitude: 47.8, longitude: 13.0)
        XCTAssertEqual(MapRouteSketch.points([a, nil, b]), [a, b], "an unknown stop is left out")
        XCTAssertNil(MapRouteSketch.points([a, nil]), "one known place is not a route")
        XCTAssertNil(MapRouteSketch.points([nil, nil]))
    }
}
