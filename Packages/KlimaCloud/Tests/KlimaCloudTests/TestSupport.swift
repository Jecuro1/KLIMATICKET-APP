import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KlimaCloud

/// Scripted HTTP transport: records every request and answers with `handler(request, index)`.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest, Int) throws -> Reply

    init(handler: @escaping @Sendable (URLRequest, Int) throws -> Reply) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return recorded.count - 1
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = record(request)
        let reply = try handler(request, index)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: reply.headers)!
        return (reply.body, response)
    }

    /// An answer from our Worker (carries `X-KB-API: 1`).
    static func api(_ status: Int, _ json: Any, headers: [String: String] = [:]) -> Reply {
        var all = ["Content-Type": "application/json", "X-KB-API": "1"]
        for (k, v) in headers { all[k] = v }
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return Reply(status: status, headers: all, body: body)
    }

    /// Something in between (captive portal, proxy): no `X-KB-API`.
    static func foreign(_ status: Int, html: String = "<html><body>Login required</body></html>") -> Reply {
        Reply(status: status, headers: ["Content-Type": "text/html"], body: Data(html.utf8))
    }
}

/// Counts calls across tasks.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

enum TestData {
    static let base = URL(string: "https://klimabilanz-api.example.workers.dev")!
    static let fixedNow = Date(timeIntervalSince1970: 1_791_000_000)

    static func user(_ id: String = "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10") -> CloudUser {
        CloudUser(id: id, email: "a@b.at", emailVerified: true, displayName: "Marcel", provider: "google")
    }

    static func session(_ access: String = "access-A", refresh: String = "refresh-A", expiresIn: TimeInterval = 900,
                        now: Date = Date()) -> CloudSession {
        CloudSession(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expiresIn), user: user())
    }

    static func client(_ transport: FakeTransport) -> CloudAPIClient {
        CloudAPIClient(baseURL: base, transport: transport, appVersion: "1.2.3", build: "45", osVersion: "26.0",
                       now: { fixedNow })
    }

    static func tokenJSON(access: String = "jwt-1", refresh: String = "rt-1", userID: String = "0b9c6a4e-6f5e-4d2a-9a51-3f7d2c1e8b10") -> [String: Any] {
        ["access_token": access, "token_type": "Bearer", "expires_in": 900, "refresh_token": refresh,
         "refresh_token_expires_in": 5_184_000,
         "user": ["id": userID, "email": "a@b.at", "email_verified": true, "display_name": "Marcel", "avatar_url": NSNull(),
                  "provider": "google", "created_at": "2026-10-09T12:00:00.000000Z"]]
    }

    static func trip(_ index: Int, note: String = "", updated: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> TripDTO {
        TripDTO(id: UUID(), user_id: "u1", date: updated, from_name: "Bludenz", to_name: "Wien Hbf", mode: "train",
                distance_km: 683.4, fare_eur: 104.6, is_fare_manual: false, is_round_trip: index % 2 == 0,
                travel_class: "second", companions: 0, states: "V,T", note: note, category: "", is_induced: false,
                created_at: updated, updated_at: updated)
    }
}

extension URLRequest {
    /// Form or query parameters.
    var formFields: [String: String] {
        guard let body = httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        return Self.parse(text)
    }

    var queryFields: [String: String] {
        guard let query = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery }) else { return [:] }
        return Self.parse(query)
    }

    var jsonBody: [String: Any] {
        guard let body = httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            let value = parts.count > 1 ? (String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "") : ""
            out[key] = value
        }
        return out
    }
}
