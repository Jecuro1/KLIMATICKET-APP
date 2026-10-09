import Foundation
import XCTest
@testable import KlimaCore

/// The shipped place database: coverage, binary format, legacy station ids, StationIndex façade, loader, speed.
final class PlaceDatasetTests: XCTestCase {
    func testCoveragePerBundeslandAndMode() {
        let ds = PlaceFixtures.dataset
        XCTAssertGreaterThan(ds.stopCount, 39_000)
        XCTAssertGreaterThan(ds.localityCount, 20_000)
        var byState: [String: Int] = [:]
        var byMode: [String: Int] = [:]
        let modes: [(String, PlaceProducts)] = [("rail", .rail), ("subway", .subway), ("tram", .tram), ("bus", .bus),
                                                ("ship", .ship), ("cable", .onDemandOrCable)]
        var ids = Set<String>()
        for r in ds.stops {
            byState[r.state, default: 0] += 1
            for (n, m) in modes where r.products & m.rawValue != 0 { byMode[n, default: 0] += 1 }
            XCTAssertTrue(ids.insert(r.id).inserted, "duplicate id \(r.id)")
            XCTAssertFalse(r.name.isEmpty)
            XCTAssertFalse(r.name.contains("->"), r.name)
            if r.state != "X" {
                XCTAssertTrue((46.3...49.1).contains(r.lat) && (9.4...17.2).contains(r.lon), "\(r.name) \(r.lat),\(r.lon)")
            }
        }
        for s in ["W", "NÖ", "B", "OÖ", "S", "ST", "K", "T", "V"] { XCTAssertGreaterThan(byState[s] ?? 0, 1_500, s) }
        XCTAssertGreaterThan(byMode["rail"] ?? 0, 1_700)
        XCTAssertGreaterThan(byMode["subway"] ?? 0, 95)
        XCTAssertGreaterThan(byMode["tram"] ?? 0, 600)
        XCTAssertGreaterThan(byMode["bus"] ?? 0, 38_000)
        XCTAssertGreaterThan(byMode["ship"] ?? 0, 90)
        XCTAssertGreaterThan(byMode["cable"] ?? 0, 300)
        XCTAssertTrue(ds.localities.allSatisfy { $0.kind == .town && $0.localityClass != nil && $0.mainStopID != nil })
        XCTAssertGreaterThanOrEqual(ds.localities.filter { $0.localityClass == "city" }.count, 5)
    }

    func testBinaryFormatErrors() {
        XCTAssertThrowsError(try PlaceDataset(places: Data(repeating: 0, count: 80), localities: nil)) { e in
            XCTAssertEqual(e as? PlaceDataset.ReadError, .badMagic)
        }
        XCTAssertThrowsError(try PlaceDataset(places: Data("KBPL".utf8), localities: nil))
        var data = (try? Data(contentsOf: PlaceFixtures.placesURL)) ?? Data()
        data[4] = 9
        XCTAssertThrowsError(try PlaceDataset(places: data, localities: nil)) { e in
            XCTAssertEqual(e as? PlaceDataset.ReadError, .unsupportedVersion(9))
        }
    }

    /// Every id of the previous stations.json still resolves (existing trips, favourites, relation prices).
    func testLegacyStationIDsResolve() throws {
        let data = try Data(contentsOf: PlaceFixtures.resources.appendingPathComponent("stations.json"))
        let legacy = try JSONDecoder().decode([Station].self, from: data)
        XCTAssertEqual(legacy.count, 1_487)
        let index = PlaceFixtures.index
        var far = 0
        for s in legacy {
            let p = try XCTUnwrap(index.place(id: s.id), s.id)
            let d = s.location.distanceKm(to: p.coordinate)
            if d > 1.5 { far += 1 }
            let st = try XCTUnwrap(index.station(id: s.id))
            XCTAssertEqual(st.id, s.id, "station(id:) keeps the stored id")
        }
        XCTAssertEqual(far, 0)
        // the combined Wien Hbf record (rail at:49:1349 + U-Bahn wl:60201349) keeps the rail id for trips
        XCTAssertEqual(index.place(id: "wl:60201349")?.id, "at:49:1349")
        XCTAssertEqual(index.place(id: "at:49:1349")?.stationID, "at:49:1349")
        XCTAssertEqual(index.place(id: "at:47:1187")?.station.kind, .rail)
        XCTAssertEqual(index.place(id: "at:47:1187")?.station.primaryMode, .train)
    }

    func testStationBridgeForNewStops() throws {
        let index = PlaceFixtures.index
        let stop = try XCTUnwrap(PlaceFixtures.record(named: "Lech am Arlberg Dorfhus"))
        XCTAssertTrue(stop.legacyStationIDs.isEmpty)
        let st = stop.station
        XCTAssertEqual(st.id, stop.id)
        XCTAssertEqual(st.state, "V")
        XCTAssertEqual(st.primaryMode, .bus)
        XCTAssertEqual(index.station(id: stop.id)?.name, "Lech am Arlberg Dorfhus")
        XCTAssertEqual(stop.subtitle, "Bus · Vorarlberg")
        let tram = try XCTUnwrap(index.search("Graz Jakominiplatz", context: .tripLog, limit: 1).first)
        XCTAssertEqual(tram.name, "Graz Jakominiplatz")
        XCTAssertEqual(tram.products.primaryMode, .tram)
        XCTAssertEqual(tram.station.primaryMode, .tram)
        XCTAssertTrue(tram.products.modes.contains(.bus))
    }

    func testStationIndexFacade() throws {
        let data = try Data(contentsOf: PlaceFixtures.resources.appendingPathComponent("stations.json"))
        let stations = try StationIndex(jsonData: data)
        XCTAssertNil(stations.station(id: "at:80:12345"))
        let lech = try XCTUnwrap(PlaceFixtures.record(named: "Lech am Arlberg Dorfhus"))
        XCTAssertNil(stations.station(id: lech.id))
        let before = stations.search("innsbruck hbf", limit: 3).map(\.id)

        stations.attach(places: PlaceFixtures.index)
        defer { stations.attach(places: nil) }
        XCTAssertEqual(stations.station(id: lech.id)?.name, "Lech am Arlberg Dorfhus")
        XCTAssertEqual(stations.station(id: "at:47:1187")?.name, "Innsbruck Hauptbahnhof")   // stations.json entry first
        XCTAssertEqual(stations.search("Lech Dorfhus", limit: 3).first?.id, lech.id)
        XCTAssertEqual(stations.search("innsbruck hbf", limit: 3).first?.id, before.first)
        XCTAssertEqual(stations.station(named: "Lech am Arlberg Dorfhus")?.id, lech.id)
        let near = stations.nearest(to: GeoPoint(latitude: 47.2669, longitude: 11.3939), limit: 3)
        XCTAssertEqual(near.first?.station.name, "Innsbruck Maria-Theresien-Straße")
        XCTAssertLessThan(near.first?.distanceKm ?? 9, 0.1)
        XCTAssertEqual(stations.search("", limit: 1).first?.id, "at:49:1349")                // empty query unchanged
    }

    func testLoaderBuildsOnceOffMainThread() async throws {
        let loader = PlaceIndexLoader(placesURL: PlaceFixtures.placesURL, localitiesURL: PlaceFixtures.localitiesURL)
        XCTAssertNil(loader.current)
        guard case .idle = loader.state else { return XCTFail("not idle") }
        let notified = Locked(0)
        loader.whenReady { _ in notified.mutate { $0 += 1 } }
        async let a = loader.load()
        async let b = loader.load()
        let (x, y) = try await (a, b)
        XCTAssertTrue(x === y)
        XCTAssertTrue(loader.current === x)
        guard case .ready = loader.state else { return XCTFail("not ready") }
        XCTAssertEqual(notified.value, 1)
        let late = Locked(0)
        loader.whenReady { _ in late.mutate { $0 += 1 } }
        XCTAssertEqual(late.value, 1)

        let missing = PlaceIndexLoader(placesURL: nil, localitiesURL: nil)
        do {
            _ = try await missing.load()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PlaceIndexLoader.LoadError, .resourceMissing)
        }
        guard case .failed = missing.state else { return XCTFail("not failed") }
    }
}

/// Search speed on the full shipped dataset (~60k records). Release builds (CI step "Place search performance")
/// must answer 100 typical queries in < 50 ms; debug builds only guard against pathological regressions.
final class PlaceSearchPerformanceTests: XCTestCase {
    static let typical = [
        "inns", "innsbruck h", "wien w", "st anton", "hall in", "Hall i.T.", "ibk", "flughafen", "Stephansplatz",
        "Maria-Theresien-Straße 1 Innsbruck", "Hofburg", "Lech Postamt", "wien", "Wien Hbf", "Salzburg", "graz hbf", "linz",
        "Karlsplatz", "Zell am See", "St. Johann", "Mariahilfer Straße", "Schönbrunn", "Nordkette", "Gmunden", "Bregenz Bf",
        "Seefeld", "Westbahnhof", "schwaz", "St. Pölten", "st polten", "St Poelten Hbf", "Sankt Pölten Hauptbahnhof",
        "kitzbuehel", "Kitzbuhel", "insbruck", "innsbruk", "Woergl", "innsbruck", "mariahilferstrasse", "mariahilferstr",
        "innsbruckhbf", "bahnhofstrasse", "west bahnhof", "hall thaur", "6020", "innsbruck hbf", "wien mitte", "praterstern",
        "landeck zams", "zams", "ehrwald", "lienz", "obergurgl", "sölden", "ischgl", "mayrhofen", "zillertal", "bad ischl",
        "hallstatt", "st wolfgang", "graz jakomini", "jakominiplatz", "linz taubenmarkt", "klagenfurt", "villach", "kufstein",
        "wels", "steyr", "krems", "tulln", "baden", "mödling", "eisenstadt", "bregenz", "dornbirn", "feldkirch", "bludenz",
        "bahnhof", "hbf", "vie", "wr neustadt", "bruck mur", "St.Anton a.A.", "Wr. Neustadt", "Schwechat Flughafen",
        "Lauterach in Vlbg Hasenfeldgasse", "Steinbrunn im Bgld Bethausweg", "Nußdorf b.Lienz Volksschule",
        "Kleinmariazell NÖ Abzw Ort", "Leoben Hbf", "Wörgl", "Telfs", "Imst", "Landeck", "Reutte", "Kitzbühel Hahnenkamm",
        "Mittersill", "Saalbach", "Bad Gastein", "Obertauern",
    ]

    func testHundredTypicalQueries() {
        let index = PlaceFixtures.index
        XCTAssertEqual(Self.typical.count, 100)
        for q in Self.typical { _ = index.search(q, context: .planner, limit: 20) }      // warm up
        var best = Double.infinity
        for _ in 0..<5 {
            let t0 = DispatchTime.now().uptimeNanoseconds
            for q in Self.typical { _ = index.search(q, context: .planner, limit: 20) }
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        var worst = 0.0              // slowest query (each the best of 3 runs, so scheduler noise does not count)
        for q in Self.typical {
            var one = Double.infinity
            for _ in 0..<3 {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = index.search(q, context: .planner, limit: 20)
                one = min(one, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            }
            worst = max(worst, one)
        }
        print(String(format: "[places] 100 typical queries: %.1f ms (best of 5), slowest single query %.2f ms, index build %.2f s",
                     best, worst, index.buildSeconds))
        #if DEBUG
        XCTAssertLessThan(best, 5_000, "debug build: pathological slowdown (the real gate is the release CI step)")
        #else
        XCTAssertLessThan(best, 50, "100 queries must take < 50 ms (release)")
        XCTAssertLessThan(worst, 16, "one keystroke must fit a frame")
        #endif
    }
}

/// Tiny lock-protected box for test callbacks.
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
}
