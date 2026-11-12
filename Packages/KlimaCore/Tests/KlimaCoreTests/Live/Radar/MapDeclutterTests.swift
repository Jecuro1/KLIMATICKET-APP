import XCTest
@testable import KlimaCore

/// Trains win over stations on the Zug-Radar's map (docs/OEBB_LIVE.md §R11): a station marker that would sit under a train marker
/// is left out. The test map is 400 × 800 points and shows 1° of latitude and 2° of longitude, so 1° of longitude is 200 points
/// and 0.01° of latitude is 8 points.
final class MapDeclutterTests: XCTestCase {
    private let box = RadarBox(north: 48, west: 12, south: 47, east: 14)

    private func station(_ id: String, lat: Double, lon: Double, members: Int = 1) -> MapCluster {
        MapCluster(id: id, center: GeoPoint(latitude: lat, longitude: lon), memberIDs: (0..<members).map { "\(id)-\($0)" })
    }

    private func declutter(_ stations: [MapCluster], trains: [GeoPoint]) -> [String] {
        MapDeclutter.stations(stations, awayFromTrains: trains, in: box, widthPoints: 400, heightPoints: 800).map(\.id)
    }

    func testAStationUnderATrainIsLeftOut() {
        let stations = [station("under", lat: 47.5, lon: 13.0), station("far", lat: 47.9, lon: 12.2)]
        XCTAssertEqual(declutter(stations, trains: [GeoPoint(latitude: 47.5, longitude: 13.0)]), ["far"])
    }

    func testTheClearanceIsMeasuredInPointsInBothDirections() {
        // A bubble (half width 17) and a train (half width 36, half height 17): 53 points across, 34 up and down.
        // 0.2° of longitude is 40 points (inside 53), 0.3° is 60 points (outside).
        let near = station("near", lat: 47.5, lon: 13.2), farX = station("farX", lat: 47.5, lon: 13.3)
        // 0.04° of latitude is 32 points (inside 34), 0.05° is 40 points (outside).
        let nearY = station("nearY", lat: 47.54, lon: 13.0), farY = station("farY", lat: 47.55, lon: 13.0)
        let train = GeoPoint(latitude: 47.5, longitude: 13.0)
        XCTAssertEqual(declutter([near, farX, nearY, farY], trains: [train]), ["farX", "farY"])
        XCTAssertEqual(declutter([station("diagonal", lat: 47.54, lon: 13.2)], trains: [train]), [], "inside in both directions")
        XCTAssertEqual(declutter([station("corner", lat: 47.55, lon: 13.2)], trains: [train]), ["corner"], "outside in one direction is enough")
    }

    func testAStationNameCapsuleReachesAsFarAsItsNameAndOnlyUpwards() {
        // "Leobendorf-Burg Kreuzenstein": 28 characters, about 194 points wide, 32 points above its dot.
        let name = "Leobendorf-Burg Kreuzenstein"
        let single = [station("capsule", lat: 47.5, lon: 13.0)]
        func hidden(trainLat: Double, trainLon: Double) -> Bool {
            MapDeclutter.stations(single, awayFromTrains: [GeoPoint(latitude: trainLat, longitude: trainLon)], in: box,
                                  widthPoints: 400, heightPoints: 800, footprint: { _ in .capsule(nameLength: name.count) }).isEmpty
        }
        // 0.6° of longitude is 120 points: beside the capsule (97 + 36 = 133 points reach), at the height of the dot.
        XCTAssertTrue(hidden(trainLat: 47.5, trainLon: 13.6), "a train at the end of the capsule is covered by it")
        XCTAssertFalse(hidden(trainLat: 47.5, trainLon: 13.8), "160 points away is clear")
        // 0.05° of latitude is 40 points: above the dot, inside the capsule's 32 + 17 points.
        XCTAssertTrue(hidden(trainLat: 47.55, trainLon: 13.0))
        XCTAssertFalse(hidden(trainLat: 47.57, trainLon: 13.0), "56 points above is clear")
        // Below the dot there is only the dot itself (2 + 17 points): 0.03° is 24 points.
        XCTAssertFalse(hidden(trainLat: 47.47, trainLon: 13.0), "24 points below is clear: nothing of the capsule is there")
        XCTAssertEqual(MapDeclutter.Footprint.capsule(nameLength: 28).halfWidth, 96.8, accuracy: 1e-9)
    }

    func testBubblesAndSingleStationsAreTreatedAlikeAndTheOrderStays() {
        let stations = [station("a", lat: 47.9, lon: 12.1, members: 12), station("b", lat: 47.5, lon: 13.0), station("c", lat: 47.1, lon: 13.9, members: 3)]
        XCTAssertEqual(declutter(stations, trains: [GeoPoint(latitude: 47.5, longitude: 13.0)]), ["a", "c"])
    }

    func testNothingChangesWithoutTrainsOrWithoutAUsableMap() {
        let stations = [station("a", lat: 47.5, lon: 13.0)]
        XCTAssertEqual(declutter(stations, trains: []), ["a"])
        let train = [GeoPoint(latitude: 47.5, longitude: 13.0)]
        XCTAssertEqual(MapDeclutter.stations(stations, awayFromTrains: train, in: box, widthPoints: 0, heightPoints: 800).map(\.id), ["a"])
        XCTAssertEqual(MapDeclutter.stations(stations, awayFromTrains: train, in: RadarBox(north: 47, west: 13, south: 47, east: 14),
                                             widthPoints: 400, heightPoints: 800).map(\.id), ["a"], "an invalid rectangle decides nothing")
    }
}
