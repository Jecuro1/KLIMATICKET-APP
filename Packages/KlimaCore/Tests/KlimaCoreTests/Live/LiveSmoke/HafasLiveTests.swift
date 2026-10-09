// Opt-in live checks against the real ÖBB HAFAS (SPEC §D3). Never part of CI:
//   KB_LIVE_TESTS=1 swift test --package-path Packages/KlimaCore --filter LiveSmoke --no-parallel
// Budget ≤ 20 requests per run through the real RequestThrottle; structure is asserted, not exact values.
// A .blocked / .rateLimited / .offline / .circuitOpen result skips with the reason – it never fails.
// KB_LIVE_RECORD_DIR=<dir> additionally writes <scenario>.request.json / .response.json (FX/hafas format).
import Foundation
import XCTest
@testable import KlimaCore

final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let base: HTTPTransport
    private let lock = NSLock()
    private var _last: (HTTPRequest, HTTPResponse, TimeInterval)?

    init(_ base: HTTPTransport) { self.base = base }

    var last: (HTTPRequest, HTTPResponse, TimeInterval)? {
        lock.lock(); defer { lock.unlock() }
        return _last
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let t0 = Date()
        let response = try await base.send(request)
        store(request, response, Date().timeIntervalSince(t0))
        return response
    }

    private func store(_ r: HTTPRequest, _ s: HTTPResponse, _ seconds: TimeInterval) {
        lock.lock()
        _last = (r, s, seconds)
        lock.unlock()
    }

    /// Writes the last exchange as `FX/hafas` fixture pair (request `{_meta, body}`; response raw).
    func record(_ scenario: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["KB_LIVE_RECORD_DIR"], let (req, resp, seconds) = last else { return }
        let url = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        let meta: [String: Any] = [
            "scenario": scenario, "fetchedAt": f.string(from: Date()), "httpStatus": resp.status, "seconds": (seconds * 100).rounded() / 100,
            "url": req.url.absoluteString, "method": req.method,
            "headers": req.headers.filter { $0.key != "User-Agent" },
            "responseHeaders": resp.headers.filter { !["set-cookie", "cookie"].contains($0.key) },
        ]
        let body = try JSONSerialization.jsonObject(with: req.body ?? Data("{}".utf8))
        let request = try JSONSerialization.data(withJSONObject: ["_meta": meta, "body": body], options: [.sortedKeys])
        try request.write(to: url.appendingPathComponent("\(scenario).request.json"))
        try resp.body.write(to: url.appendingPathComponent("\(scenario).response.json"))
    }
}

final class HafasLiveTests: XCTestCase {
    static let enabled = ProcessInfo.processInfo.environment["KB_LIVE_TESTS"] == "1"
    static let throttle = RequestThrottle()
    static let health = LiveHealth()
    static let recorder = RecordingTransport(URLSessionTransport())
    static let client = HafasClient(config: .default, transport: recorder, throttle: throttle, health: health, appVersion: "live-test")

    static let ibk = Location.station(extId: "8100108", name: "Innsbruck Hbf")
    static let stAnton = Location.station(extId: "8100064", name: "St. Anton am Arlberg Bahnhof")
    static let feldkirch = Location.station(extId: "8100197", name: "Feldkirch Bahnhof")
    static let bregenz = Location.station(extId: "8100090", name: "Bregenz Bahnhof")

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.enabled, "set KB_LIVE_TESTS=1 for live checks")
    }

    /// Runs a live call; blocks, rate limits and missing connectivity skip instead of failing.
    func live<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let e as LiveError {
            switch e {
            case .blocked, .rateLimited, .offline, .circuitOpen, .network:
                throw XCTSkip("live service not usable here: \(e)")
            default:
                throw e
            }
        }
    }

    static func tomorrow(hour: Int) -> Date {
        let cal = Calendar.vienna
        let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    // 1
    func testLocMatchInnsbruckHbf() async throws {
        let locs = try await live { try await Self.client.locations("Innsbruck Hbf", types: .stations, maxResults: 8) }
        XCTAssertTrue(locs.contains { $0.extId == "8100108" }, "\(locs.map(\.name))")
    }

    // 2, 3, 5
    func testTripSearchReconstructionAndJourneyDetails() async throws {
        let q = JourneyQuery(origin: Self.stAnton, destination: Self.ibk, date: Date().addingTimeInterval(3600), results: 3)
        let page = try await live { try await Self.client.journeys(q) }
        let j = try XCTUnwrap(page.journeys.first { !$0.rideLegs.isEmpty && $0.refreshToken != nil })
        let token = try XCTUnwrap(j.refreshToken)
        let refreshed = try await live { try await Self.client.refresh(token, includeStopovers: true, includePolyline: false) }
        XCTAssertEqual(refreshed.id, j.id)
        let tripID = try XCTUnwrap(j.rideLegs.first?.tripID)
        let trip = try await live { try await Self.client.trip(tripID, includePolyline: true) }
        XCTAssertGreaterThan(trip.polyline?.count ?? 0, 100)
    }

    // 4
    func testStationBoardInnsbruck() async throws {
        let board = try await live { try await Self.client.board(BoardQuery(station: Self.ibk, date: Date(), durationMinutes: 30, maxResults: 20)) }
        XCTAssertFalse(board.entries.isEmpty)
    }

    // 6a: the legacy profile accepts outReconL (SPEC §A3.1 [ASSUMED]).
    func testLegacyProfileAcceptsOutReconL() async throws {
        var config = LiveConfig.default
        config.hafas = try XCTUnwrap(config.hafasFallback)
        config.hafasFallback = nil
        let legacy = HafasClient(config: config, transport: URLSessionTransport(), throttle: Self.throttle, health: LiveHealth(), appVersion: "live-test")
        let q = JourneyQuery(origin: Self.stAnton, destination: Self.ibk, date: Date().addingTimeInterval(3600), results: 1)
        let page = try await live { try await legacy.journeys(q) }
        let token = try XCTUnwrap(page.journeys.first?.refreshToken)
        let j = try await live { try await legacy.refresh(token, includeStopovers: false, includePolyline: false) }
        XCTAssertFalse(j.legs.isEmpty)
    }

    // 6b: VAO accepts the wl: → at:49 lid derivation (SPEC §A3.7 rule 2 [ASSUMED]).
    func testVaoWienerLinienLid() async throws {
        struct TrfReq: Encodable { var jnyCl = 2; var tvlrProf = [["type": "E"]]; var cType = "PK" }
        struct Trip: Encodable {
            var depLocL: [HafasLocationRef]; var arrLocL: [HafasLocationRef]
            var outDate: String; var outTime: String; var outFrwd = true; var numF = 1
            var getPasslist = false; var getPolyline = false; var getTariff = true; var trfReq = TrfReq()
        }
        let karlsplatz = try XCTUnwrap(StationLinker.directVaoLid(for: "wl:60200657"))
        XCTAssertEqual(karlsplatz, "A=1@L=490065700@")
        let when = Self.tomorrow(hour: 10)
        let req = HafasServiceRequest(meth: "TripSearch", req: Trip(
            depLocL: [HafasLocationRef(lid: karlsplatz)], arrLocL: [HafasLocationRef(lid: "A=1@L=490146800@")],
            outDate: HafasTime.dateString(when), outTime: HafasTime.timeString(when)))
        let profile = LiveConfig.default.vao
        try await Self.throttle.acquire(.vaoTariff, minInterval: 1, perMinute: 20)
        let body = try JSONEncoder().encode(HafasEnvelope(profile: profile, svcReqL: [req]))
        let response = try await live {
            try await URLSessionTransport().send(HTTPRequest(method: "POST", url: profile.url, headers: [
                "Content-Type": "application/json", "Accept": "application/json",
                "User-Agent": LiveConfig.default.userAgent.replacingOccurrences(of: "{version}", with: "live-test"),
            ], body: body, timeout: profile.timeout))
        }
        XCTAssertEqual(response.status, 200)
        XCTAssertNil(HafasCodec.envelopeError(response.body, provider: .vaoTariff))
        XCTAssertNil(HafasCodec.serviceError(response.body, provider: .vaoTariff), "VAO rejected the derived lid")
    }

    /// Owner request 2026-10-09: via stops. ONE request: Innsbruck Hbf → Bregenz via Feldkirch with a 10 min stay.
    func testViaFeldkirchWithDwell() async throws {
        let q = JourneyQuery(origin: Self.ibk, destination: Self.bregenz, via: [ViaStop(location: Self.feldkirch, minimumDwellMinutes: 10)],
                             date: Self.tomorrow(hour: 9), products: .klimaTicket, results: 3, includeStopovers: true)
        let page = try await live { try await Self.client.journeys(q) }
        try Self.recorder.record("tripsearch_via_feldkirch_dwell_ibk_bregenz")
        XCTAssertFalse(page.journeys.isEmpty)
        for j in page.journeys {
            XCTAssertTrue(j.passes(Self.feldkirch), "journey \(j.id) does not pass Feldkirch")
        }
    }
}
