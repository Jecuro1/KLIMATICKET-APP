import XCTest
@testable import KlimaCore

/// App station ⇄ live location mapping (SPEC §A3.7, §D2 WP-A 12).
final class StationLinkerTests: XCTestCase {
    static let start = ISO.date("2026-10-09T10:00:00Z")!
    static let ibkHbf = Station(id: "at:47:1187", name: "Innsbruck Hauptbahnhof", lat: 47.26330, lon: 11.40085, state: "T", kind: .rail)
    static let ibkWest = Station(id: "at:47:1189", name: "Innsbruck Westbahnhof", lat: 47.25553, lon: 11.39148, state: "T", kind: .rail)
    static let wienHbf = Station(id: "wl:60201349", name: "Wien Hauptbahnhof", lat: 48.18519, lon: 16.37641, state: "W", kind: .metro)
    static let index = StationIndex(stations: [ibkHbf, ibkWest, wienHbf])

    struct NoTimetable: TimetableService {
        func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location] { throw LiveError.offline }
        func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location] { throw LiveError.offline }
        func journeys(_ query: JourneyQuery) async throws -> JourneyPage { throw LiveError.offline }
        func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>] { throw LiveError.offline }
        func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey { throw LiveError.offline }
        func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>] { throw LiveError.offline }
        func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails { throw LiveError.offline }
        func board(_ query: BoardQuery) async throws -> Board { throw LiveError.offline }
        func remarks(_ query: RemarksQuery) async throws -> [Remark] { throw LiveError.offline }
    }

    struct FixtureVao: VaoLocationSearching {
        func vaoLocations(_ query: String) async throws -> [Location] {
            let r = try Fixture.shopResponse("vao/arch_vao_locmatch_eferding")
            return try HafasCodec.locations(from: r.body)
        }
    }

    func testUICIsDirectWithoutIO() async throws {
        let linker = StationLinker(stations: Self.index, timetable: nil, vao: nil, cacheURL: nil)
        let s = Station(id: "uic:8100227", name: "Wels Hbf", lat: 48.16588, lon: 14.02618, state: "OÖ")
        let loc = try await linker.hafasLocation(for: s)
        XCTAssertEqual(loc.lid, "A=1@L=8100227@")
        XCTAssertEqual(loc.extId, "8100227")
        XCTAssertEqual(loc.name, "Wels Hbf")
        // Anything else needs a timetable.
        do { _ = try await linker.hafasLocation(for: Self.ibkHbf); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .disabled(.oebbHafas)) }
    }

    func testVaoLidRules() {
        XCTAssertEqual(StationLinker.directVaoLid(for: "at:47:1187"), "A=1@L=470118700@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "at:45:50002"), "A=1@L=455000200@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "at:44:41164"), "A=1@L=444116400@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "at:48:452"), "A=1@L=480045200@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "wl:60201349"), "A=1@L=490134900@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "wl:60200657"), "A=1@L=490065700@")
        XCTAssertEqual(StationLinker.directVaoLid(for: "at:47:1187:1:3"), "A=1@L=470118703@")
        XCTAssertNil(StationLinker.directVaoLid(for: "uic:8100227"))
        XCTAssertNil(StationLinker.directVaoLid(for: "osm:hub:123"))
        XCTAssertNil(StationLinker.directVaoLid(for: "wl:12345678"))
        XCTAssertNil(StationLinker.directVaoLid(for: "at:47:1234567"))
    }

    func testVaoLidFromFixtureGoldens() throws {
        // FX/vao request lids were derived with the same rule (22/22 live).
        let golden = try Fixture.golden("vao/vao_tripsearch_tariff_stanton-ibk")
        XCTAssertEqual(golden["arrLid"] as? String, StationLinker.directVaoLid(for: "at:47:1187"))
    }

    func testVaoLocMatchFallbackPicksNearestWithin400m() async throws {
        let eferding = Station(id: "osm:hub:eferding", name: "Eferding Bahnhof", lat: 48.30352, lon: 14.01598, state: "OÖ")
        let linker = StationLinker(stations: Self.index, timetable: nil, vao: FixtureVao(), cacheURL: nil)
        let lid = try await linker.vaoLid(for: eferding)
        XCTAssertEqual(lid, "A=1@L=444250500@", "VAO LocMatch embeds the IFOPT id at:44:42505")
        let far = Station(id: "osm:hub:far", name: "Eferding Bahnhof", lat: 48.40, lon: 14.20, state: "OÖ")
        do { _ = try await linker.vaoLid(for: far); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .hafas(code: "LOCATION", message: nil)) }
        let noVao = StationLinker(stations: Self.index, timetable: nil, vao: nil, cacheURL: nil)
        do { _ = try await noVao.vaoLid(for: eferding); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .disabled(.vaoTariff)) }
        XCTAssertEqual(StationLinker.minimalLid("A=1@O=Eferding Bahnhof@X=14015999@Y=48303500@U=81@L=444250500@p=1@i=A×at:44:42505@"), "A=1@L=444250500@")
    }

    func testLocMatchMappingInnsbruck() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: "/gate", response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let linker = StationLinker(stations: Self.index, timetable: client, vao: nil, cacheURL: nil)
        let loc = try await linker.hafasLocation(for: Self.ibkHbf)
        XCTAssertEqual(loc.extId, "8100108")
        XCTAssertEqual(t.recorded.count, 1)
        let svc = try XCTUnwrap((try t.jsonBody(0)["svcReqL"] as? [[String: Any]])?.first?["req"] as? [String: Any])
        let input = svc["input"] as? [String: Any]
        XCTAssertEqual((input?["loc"] as? [String: Any])?["name"] as? String, "Innsbruck Hauptbahnhof?")
        XCTAssertEqual((input?["loc"] as? [String: Any])?["type"] as? String, "S")
        XCTAssertEqual(input?["maxLoc"] as? Int, 8)
        // Second call: memory cache, no I/O.
        _ = try await linker.hafasLocation(for: Self.ibkHbf)
        XCTAssertEqual(t.recorded.count, 1)
    }

    func testCandidateScoring() throws {
        let locs = try HafasCodec.locations(from: Fixture.data("hafas/locmatch_innsbruck.response"))
        XCTAssertEqual(StationLinker.bestHafasCandidate(for: Self.ibkHbf, among: locs)?.extId, "8100108")
        XCTAssertEqual(StationLinker.bestHafasCandidate(for: Self.ibkWest, among: locs)?.extId, "8100109")
        // Metro / tram hubs prefer the meta station.
        let tramHub = Station(id: "osm:hub:ibk", name: "Innsbruck", lat: 47.26377, lon: 11.40097, state: "T", kind: .tramHub)
        XCTAssertEqual(StationLinker.bestHafasCandidate(for: tramHub, among: locs)?.extId, "1170101")
        // Nothing within 300 m (800 m for meta) → nil.
        let far = Station(id: "at:47:9999", name: "Innsbruck Hauptbahnhof", lat: 47.30, lon: 11.50, state: "T")
        XCTAssertNil(StationLinker.bestHafasCandidate(for: far, among: locs))
        XCTAssertEqual(StationLinker.ifoptUIC("at:47:1187"), "8101187")
    }

    func testNoCandidateIsLocationError() async throws {
        let t = FixtureTransport(routes: [.init(urlSuffix: "/gate", response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let (client, _) = HafasClient.testClient(t, clock: FakeClock(Self.start))
        let linker = StationLinker(stations: Self.index, timetable: client, vao: nil, cacheURL: nil)
        let far = Station(id: "at:47:9999", name: "Innsbruck Hauptbahnhof", lat: 47.30, lon: 11.50, state: "T")
        do { _ = try await linker.hafasLocation(for: far); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .hafas(code: "LOCATION", message: nil)) }
    }

    func testReverseMapping() throws {
        let hbf = Location(lid: "A=1@L=8100108@", extId: "8100108", name: "Innsbruck Hbf",
                           coordinate: GeoPoint(latitude: 47.263043, longitude: 11.401019))
        XCTAssertEqual(StationLinker.appStation(for: hbf, in: Self.index)?.id, "at:47:1187")
        let wien = Location(lid: "A=1@L=1290401@", extId: "1290401", name: "Wien Hbf (Bahnsteige 3-12)",
                            coordinate: GeoPoint(latitude: 48.18505, longitude: 16.37701))
        XCTAssertEqual(StationLinker.appStation(for: wien, in: Self.index)?.id, "wl:60201349")
        // Same place, unrelated name → nil; no coordinate → nil.
        let other = Location(lid: "x", name: "Rum Bahnhst", coordinate: GeoPoint(latitude: 47.263043, longitude: 11.401019))
        XCTAssertNil(StationLinker.appStation(for: other, in: Self.index))
        XCTAssertNil(StationLinker.appStation(for: Location(lid: "y", name: "Innsbruck Hbf"), in: Self.index))
        // Golden journeys from TripSearch map back to app stations.
        let page = try HafasCodec.journeyPage(from: Fixture.data("hafas/tripsearch_st_anton_innsbruck.response"))
        let dest = try XCTUnwrap(page.journeys.first?.destination)
        XCTAssertEqual(StationLinker.appStation(for: dest, in: Self.index)?.id, "at:47:1187")
    }

    func testDiskCacheRoundTripAndInvalidate() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("linker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("station_links.json")
        let clock = FakeClock(Self.start)
        let t = FixtureTransport(routes: [.init(urlSuffix: "/gate", response: try Fixture.hafasResponse("locmatch_innsbruck"))])
        let (client, _) = HafasClient.testClient(t, clock: clock)
        let first = StationLinker(stations: Self.index, timetable: client, vao: FixtureVao(), cacheURL: url, clock: clock.closure)
        let loc = try await first.hafasLocation(for: Self.ibkHbf)
        let eferding = Station(id: "osm:hub:eferding", name: "Eferding Bahnhof", lat: 48.30352, lon: 14.01598, state: "OÖ")
        _ = try await first.vaoLid(for: eferding)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let entries = try XCTUnwrap(json["entries"] as? [String: Any])
        let e = try XCTUnwrap(entries["at:47:1187"] as? [String: Any])
        XCTAssertEqual((e["hafas"] as? [String: Any])?["extId"] as? String, "8100108")
        XCTAssertNotNil(e["fetchedAt"])
        XCTAssertEqual((entries["osm:hub:eferding"] as? [String: Any])?["vaoLid"] as? String, "A=1@L=444250500@")

        // A fresh linker without network answers from disk.
        let second = StationLinker(stations: Self.index, timetable: NoTimetable(), vao: nil, cacheURL: url, clock: clock.closure)
        let cached = try await second.hafasLocation(for: Self.ibkHbf)
        XCTAssertEqual(cached.extId, loc.extId)
        XCTAssertEqual(cached.lid, loc.lid)
        let cachedLid = try await second.vaoLid(for: eferding)
        XCTAssertEqual(cachedLid, "A=1@L=444250500@")
        // 30 days later the entry is stale.
        clock.advance(31 * 86_400)
        do { _ = try await second.hafasLocation(for: Self.ibkHbf); XCTFail() } catch { XCTAssertEqual(error as? LiveError, .offline) }
        // Invalidate removes it from disk.
        await second.invalidate(stationID: "at:47:1187")
        let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil((after["entries"] as? [String: Any])?["at:47:1187"])
        XCTAssertNotNil((after["entries"] as? [String: Any])?["osm:hub:eferding"])
    }
}

/// Remote config: round trip, version gate, kill switch, budget floors (SPEC §A3.8, §D2 WP-A 13).
final class LiveConfigTests: XCTestCase {
    func testRoundTripAndVersionGate() throws {
        let data = try LiveConfigLoader.encode(LiveConfig.default)
        XCTAssertEqual(try JSONDecoder().decode(LiveConfig.self, from: data), .default)
        XCTAssertNil(LiveConfigLoader.decode(data, current: .default), "same version is ignored")
        var newer = LiveConfig.default
        newer.version = 2
        newer.notice = "  Ticketpreise derzeit nur offline  "
        let decoded = try XCTUnwrap(LiveConfigLoader.decode(try LiveConfigLoader.encode(newer), current: .default))
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.notice, "Ticketpreise derzeit nur offline")
        var older = LiveConfig.default
        older.version = 0
        XCTAssertNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(older), current: .default))
        XCTAssertNil(LiveConfigLoader.decode(Data("{".utf8), current: .default))
        XCTAssertNil(LiveConfigLoader.decode(Data("[]".utf8), current: .default))
    }

    func testKillSwitchAndProviderToggles() throws {
        var c = LiveConfig.default
        XCTAssertTrue(LiveProvider.allCases.allSatisfy(c.isEnabled))
        c.shop.enabled = false
        XCTAssertFalse(c.isEnabled(.oebbShop))
        XCTAssertTrue(c.isEnabled(.oebbHafas))
        c.killSwitch = true
        c.version = 5
        XCTAssertTrue(LiveProvider.allCases.allSatisfy { !c.isEnabled($0) })
        let decoded = try XCTUnwrap(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default))
        XCTAssertTrue(decoded.killSwitch)
        XCTAssertFalse(decoded.isEnabled(.oebbHafas))
    }

    func testRemoteConfigCannotLoosenTheBudget() throws {
        var c = LiveConfig.default
        c.version = 3
        c.hafas.minInterval = 0.01
        c.vao.minInterval = 0
        c.shop.minInterval = 0.2
        c.hafas.timeout = 600
        let d = try XCTUnwrap(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default))
        XCTAssertEqual(d.hafas.minInterval, 0.3)
        XCTAssertEqual(d.vao.minInterval, 1.0)
        XCTAssertEqual(d.shop.minInterval, 1.0)
        XCTAssertEqual(d.hafas.timeout, 60)
        // Raising is fine.
        c.hafas.minInterval = 2
        XCTAssertEqual(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default)?.hafas.minInterval, 2)
    }

    func testRejectsUnusableEndpoints() throws {
        var c = LiveConfig.default
        c.version = 9
        c.hafas.url = URL(string: "http://fahrplan.oebb.at/gate")!
        XCTAssertNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default), "plain http is rejected")
        c = .default
        c.version = 9
        c.hafas.aid = ""
        XCTAssertNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default))
        c = .default
        c.version = 9
        c.hafasFallback = nil
        XCTAssertNotNil(LiveConfigLoader.decode(try LiveConfigLoader.encode(c), current: .default), "no fallback is allowed")
    }

    func testUserAgentIsHonest() {
        XCTAssertEqual(LiveConfig.default.userAgent, "KlimaBilanz/{version} (iPhone; iOS; private, low-volume)")
    }
}
