// Test helpers of the live layer (SPEC §A2.2). Owned by WP-A; other work packages add their own helper files here.
import Foundation
import XCTest
@testable import KlimaCore

/// Serves canned responses by route (first match wins) and records every request. A request without a route is a test
/// failure (and answers HTTP 599 so the code under test fails loudly).
final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    struct Route {
        let method: String
        let urlSuffix: String
        let bodyContains: String?
        let response: HTTPResponse
        /// Optional: answer each matching request from this list in order (the last one repeats).
        var sequence: [HTTPResponse]?
        /// Optional: throw instead of answering.
        var error: LiveError?

        init(method: String = "POST", urlSuffix: String, bodyContains: String? = nil, response: HTTPResponse,
             sequence: [HTTPResponse]? = nil, error: LiveError? = nil) {
            self.method = method
            self.urlSuffix = urlSuffix
            self.bodyContains = bodyContains
            self.response = response
            self.sequence = sequence
            self.error = error
        }
    }

    private let lock = NSLock()
    private var routes: [Route]
    private var hits: [Int: Int] = [:]
    private var _recorded: [HTTPRequest] = []
    private let file: StaticString
    private let line: UInt

    init(routes: [Route], file: StaticString = #filePath, line: UInt = #line) {
        self.routes = routes
        self.file = file
        self.line = line
    }

    private(set) var recorded: [HTTPRequest] {
        get { lock.lock(); defer { lock.unlock() }; return _recorded }
        set { lock.lock(); _recorded = newValue; lock.unlock() }
    }

    func send(_ r: HTTPRequest) async throws -> HTTPResponse {
        let body = r.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let (response, error) = match(r, body: body)
        if let error { throw error }
        guard let response else {
            XCTFail("FixtureTransport: no route for \(r.method) \(r.url) body: \(body.prefix(200))", file: file, line: line)
            return HTTPResponse(status: 599, headers: [:], body: Data("no route".utf8))
        }
        return response
    }

    private func match(_ r: HTTPRequest, body: String) -> (HTTPResponse?, LiveError?) {
        lock.lock()
        defer { lock.unlock() }
        _recorded.append(r)
        guard let index = routes.firstIndex(where: { route in
            route.method == r.method && r.url.absoluteString.hasSuffix(route.urlSuffix)
                && (route.bodyContains.map { body.contains($0) } ?? true)
        }) else { return (nil, nil) }
        let n = hits[index, default: 0]
        hits[index] = n + 1
        let route = routes[index]
        if let seq = route.sequence, !seq.isEmpty { return (seq[min(n, seq.count - 1)], route.error) }
        return (route.response, route.error)
    }

    /// Decoded JSON body of the n-th recorded request.
    func jsonBody(_ n: Int) throws -> [String: Any] {
        let body = try XCTUnwrap(recorded[n].body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

/// Fixture access (`Tests/KlimaCoreTests/Fixtures/OEBB`, bundled via `.copy("Fixtures")`; SPEC §D1).
enum Fixture {
    /// Directory of the OEBB fixtures (bundle copy; falls back to the source tree).
    static let root: URL = {
        if let url = Bundle.module.url(forResource: "Fixtures/OEBB", withExtension: nil) { return url }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/OEBB")
    }()

    /// `"hafas/tripsearch_st_anton_innsbruck.response"` (without `.json`).
    static func url(_ path: String) -> URL { root.appendingPathComponent(path + ".json") }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    static func json(_ path: String) throws -> Any {
        try JSONSerialization.jsonObject(with: data(path))
    }

    private static let goldenFile: [String: Any] = {
        guard let d = try? Data(contentsOf: root.appendingPathComponent("golden.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }()

    /// `FX/golden.json[key]`, e.g. `"hafas/tripsearch_st_anton_innsbruck"`.
    static func golden(_ key: String) throws -> [String: Any] {
        try XCTUnwrap(goldenFile[key] as? [String: Any], "golden key \(key) missing")
    }

    /// All golden keys with a prefix (e.g. "hafas/").
    static func goldenKeys(prefix: String) -> [String] {
        goldenFile.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// HAFAS response fixture served as an HTTP 200 JSON response.
    static func hafasResponse(_ scenario: String) throws -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: try data("hafas/\(scenario).response"))
    }

    /// Unwraps shop/VAO `{_meta, request, response}`; status from `_meta.status`. The Cloudflare block page
    /// (`response_body_html_ip_redacted`) is served as `text/html`.
    static func shopResponse(_ path: String) throws -> HTTPResponse {
        let obj = try XCTUnwrap(try json(path) as? [String: Any])
        let meta = obj["_meta"] as? [String: Any] ?? [:]
        let status = (meta["status"] as? Int) ?? 200
        let recorded = (obj["response_headers"] ?? meta["response_headers"]) as? [String: String] ?? [:]
        if let html = obj["response_body_html_ip_redacted"] as? String {
            var headers = recorded
            headers["content-type"] = headers["content-type"] ?? "text/html; charset=UTF-8"
            return HTTPResponse(status: status == 200 ? 403 : status, headers: headers, body: Data(html.utf8))
        }
        let response = obj["response"] ?? NSNull()
        let body: Data
        if JSONSerialization.isValidJSONObject(response) {
            body = try JSONSerialization.data(withJSONObject: response)
        } else if let s = response as? String {
            body = Data(s.utf8)
        } else {
            body = Data("null".utf8)
        }
        var headers = recorded.filter { $0.key.lowercased() != "content-encoding" && $0.key.lowercased() != "content-length" }
        headers["content-type"] = "application/json"
        return HTTPResponse(status: status, headers: headers, body: body)
    }
}

/// Mutable fake clock for actor tests.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    /// Clock closure for the code under test.
    var closure: @Sendable () -> Date { { [self] in self.now } }

    /// Sleeper that advances the fake clock instead of waiting; records the requested waits.
    private var _sleeps: [TimeInterval] = []
    var sleeps: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _sleeps
    }

    var sleeper: @Sendable (TimeInterval) async throws -> Void {
        { [self] seconds in self.sleep(seconds) }
    }

    private func sleep(_ seconds: TimeInterval) {
        lock.lock()
        _sleeps.append(seconds)
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// ISO-8601 parsing for golden values ("2026-10-09T11:16:00+02:00").
enum ISO {
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func viennaString(_ d: Date?) -> String? {
        guard let d else { return nil }
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

extension HafasClient {
    /// Client over a fixture transport with a fake clock (no real sleeping anywhere).
    static func testClient(_ transport: FixtureTransport, clock: FakeClock, config: LiveConfig = .default) -> (HafasClient, LiveHealth) {
        let health = LiveHealth(clock: clock.closure)
        let throttle = RequestThrottle(clock: clock.closure, sleeper: clock.sleeper)
        let client = HafasClient(config: config, transport: transport, throttle: throttle, health: health, appVersion: "1.0.0",
                                 clock: clock.closure, sleeper: clock.sleeper)
        return (client, health)
    }
}
