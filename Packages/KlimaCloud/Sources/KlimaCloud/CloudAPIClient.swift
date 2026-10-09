import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies a valid session for a request. `rejected` is the session whose access token just got
/// `401 invalid_token`: the provider refreshes (once, serialized) and returns the new session, or throws.
public typealias SessionProvider = @Sendable (_ rejected: CloudSession?) async throws -> CloudSession

/// HTTP client of the KlimaBilanz API (`/v1`, contract §3). Stateless and Sendable; session handling lives in
/// `SessionCoordinator`.
public struct CloudAPIClient: Sendable {
    public let baseURL: URL
    public let transport: any HTTPTransport
    public let appVersion: String
    public let build: String
    public let osVersion: String
    /// Device clock for token lifetimes (tests inject a fixed one).
    public let now: @Sendable () -> Date

    public static let pushMaxRows = 500
    /// Below the server's 1 MiB limit, leaving room for headers and rounding.
    public static let pushMaxBytes = 1_000_000
    public static let pullMaxLimit = 500
    public static let defaultTimeout: TimeInterval = 30
    public static let deleteTimeout: TimeInterval = 60

    public init(baseURL: URL, transport: any HTTPTransport, appVersion: String = "1.0.0", build: String = "1",
                osVersion: String = CloudAPIClient.systemVersion, now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.transport = transport
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.now = now
    }

    /// "26.0.1" from the running OS.
    public static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
    }

    // MARK: Config

    public func fetchConfig() async throws -> CloudConfig {
        let data = try await send(makeRequest("GET", "/v1/config"))
        return try CloudCoding.decoder.decode(CloudConfig.self, from: data)
    }

    // MARK: Browser sign-in (§2.3)

    /// The Worker's start URL for `ASWebAuthenticationSession`.
    public func authorizeURL(provider: String, codeChallenge: String, state: String, redirectURI: String) -> URL {
        url("/v1/auth/\(provider)/start", query: [
            ("code_challenge", codeChallenge),
            ("code_challenge_method", "S256"),
            ("state", state),
            ("redirect_uri", redirectURI),
        ])
    }

    /// Redeems the one-time app code from the callback (PKCE).
    public func exchangeCode(_ code: String, codeVerifier: String, redirectURI: String) async throws -> CloudSession {
        try await token(["grant_type": "authorization_code", "code": code, "code_verifier": codeVerifier,
                         "redirect_uri": redirectURI], fallbackUser: nil)
    }

    /// Native Sign in with Apple (signed builds, §2.4). `rawNonce` is the value whose SHA-256 hex went into the request.
    public func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?,
                                fullName: String?) async throws -> CloudSession {
        var body: [String: String] = ["identity_token": identityToken, "raw_nonce": rawNonce]
        if let authorizationCode, !authorizationCode.isEmpty { body["authorization_code"] = authorizationCode }
        if let fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty {
            body["full_name"] = String(fullName.prefix(100))
        }
        var request = makeRequest("POST", "/v1/auth/apple/native")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try decodeSession(try await send(request), fallbackUser: nil)
    }

    /// Rotates the refresh token (single use: callers must serialize refreshes, `SessionCoordinator` does).
    public func refresh(_ session: CloudSession) async throws -> CloudSession {
        try await token(["grant_type": "refresh_token", "refresh_token": session.refreshToken], fallbackUser: session.user)
    }

    /// Ends this device's session on the server. Best effort: errors are ignored (it always answers 204 anyway).
    public func logout(_ session: CloudSession) async {
        var request = makeRequest("POST", "/v1/auth/logout", session: session, timeout: 15)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(["refresh_token": session.refreshToken]).utf8)
        _ = try? await transport.send(request)
    }

    private func token(_ fields: [String: String], fallbackUser: CloudUser?) async throws -> CloudSession {
        var request = makeRequest("POST", "/v1/auth/token")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try decodeSession(try await send(request), fallbackUser: fallbackUser)
    }

    // MARK: Account

    public func me(session: CloudSession) async throws -> CloudUser {
        let data = try await send(makeRequest("GET", "/v1/me", session: session))
        return try CloudCoding.decoder.decode(UserEnvelope.self, from: data).user
    }

    /// `PATCH /v1/me`: 1–100 characters, or nil to clear.
    public func updateDisplayName(_ name: String?, session: CloudSession) async throws -> CloudUser {
        var request = makeRequest("PATCH", "/v1/me", session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(100)) }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["display_name": value.map { $0 as Any } ?? NSNull()])
        let data = try await send(request)
        return try CloudCoding.decoder.decode(UserEnvelope.self, from: data).user
    }

    /// Deletes the account and all of its cloud data (§3.9). Every session of the user ends.
    public func deleteAccount(session: CloudSession) async throws {
        var request = makeRequest("POST", "/v1/account/delete", session: session, timeout: Self.deleteTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await send(request)
    }

    // MARK: Sync (§3.6–3.8)

    /// Pushes `rows` in chunks of at most `maxRows` rows and `maxBytes` encoded bytes. Each chunk asks `session`
    /// for a token and retries once after `401 invalid_token`.
    public func push<Row: SyncRow>(table: String, rows: [Row], session: SessionProvider,
                                   maxRows: Int = CloudAPIClient.pushMaxRows,
                                   maxBytes: Int = CloudAPIClient.pushMaxBytes) async throws -> PushResult {
        var result = PushResult()
        guard !rows.isEmpty else { return result }
        let encoder = CloudCoding.encoder
        let encoded = try rows.map { row -> Data in
            var row = row
            row.server_rev = nil
            return try encoder.encode(row)
        }
        for chunk in Self.chunks(encoded, table: table, maxRows: maxRows, maxBytes: maxBytes) {
            let body = Self.pushBody(table: table, rows: chunk)
            let answer = try await Self.withSession(session) { s -> PushAnswer in
                var request = makeRequest("POST", "/v1/sync/push", session: s)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
                return try CloudCoding.decoder.decode(PushAnswer.self, from: try await send(request))
            }
            result.applied += answer.applied
            result.skipped += answer.skipped
            result.serverRev = max(result.serverRev ?? answer.server_rev, answer.server_rev)
            result.requests += 1
        }
        return result
    }

    /// Every row of `table` with `server_rev > after`, following `next` until the server says there is no more.
    /// Returns the rows and the highest `server_rev` seen (never below `after`).
    public func pullAll<Row: SyncRow>(table: String, after cursor: Int64, pageSize: Int = CloudAPIClient.pullMaxLimit,
                                      maxPages: Int = 4000, session: SessionProvider) async throws -> (rows: [Row], maxRev: Int64) {
        let limit = min(max(pageSize, 1), Self.pullMaxLimit)
        var after = max(cursor, 0)
        var rows: [Row] = []
        var maxRev = after
        for _ in 0..<maxPages {
            let position = after
            let page: PullPage<Row> = try await Self.withSession(session) { s in
                let request = makeRequest("GET", "/v1/sync/pull", query: [
                    ("table", table), ("after", String(position)), ("limit", String(limit)),
                ], session: s)
                return try CloudCoding.decoder.decode(PullPage<Row>.self, from: try await send(request))
            }
            rows.append(contentsOf: page.rows)
            for row in page.rows { if let rev = row.server_rev, rev > maxRev { maxRev = rev } }
            guard let next = page.next else { return (rows, maxRev) }
            guard next > position else { throw CloudError.invalidResponse }   // no progress: never loop forever
            after = next
        }
        throw CloudError.invalidResponse
    }

    /// Runs `operation` with a session from `provider`; after `401 invalid_token` asks for a refreshed session and
    /// retries exactly once.
    public static func withSession<R>(_ provider: SessionProvider,
                                      _ operation: (CloudSession) async throws -> R) async throws -> R {
        let session = try await provider(nil)
        do {
            return try await operation(session)
        } catch let error as CloudError where error.isUnauthorized {
            let fresh = try await provider(session)
            return try await operation(fresh)
        }
    }

    // MARK: Chunking

    static let pushEnvelopeOverhead = 24   // {"table":"","rows":[]}

    /// Greedy split: ≤ `maxRows` rows and ≤ `maxBytes` body bytes per chunk (a single oversized row goes alone).
    static func chunks(_ rows: [Data], table: String, maxRows: Int, maxBytes: Int) -> [[Data]] {
        let envelope = pushEnvelopeOverhead + table.utf8.count
        var chunks: [[Data]] = []
        var current: [Data] = []
        var size = envelope
        for row in rows {
            let added = row.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty, current.count >= maxRows || size + added > maxBytes {
                chunks.append(current)
                current = []
                size = envelope
            }
            size += row.count + (current.isEmpty ? 0 : 1)
            current.append(row)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func pushBody(table: String, rows: [Data]) -> Data {
        var body = Data("{\"table\":".utf8)
        body.append((try? JSONEncoder().encode(table)) ?? Data("\"\"".utf8))
        body.append(Data(",\"rows\":[".utf8))
        for (index, row) in rows.enumerated() {
            if index > 0 { body.append(UInt8(ascii: ",")) }
            body.append(row)
        }
        body.append(Data("]}".utf8))
        return body
    }

    // MARK: Requests

    func url(_ path: String, query: [(String, String)] = []) -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var string = base + path
        if !query.isEmpty {
            string += "?" + query.map { "\(Self.percentEncode($0.0))=\(Self.percentEncode($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: string) else { preconditionFailure("invalid API URL \(string)") }
        return url
    }

    func makeRequest(_ method: String, _ path: String, query: [(String, String)] = [], session: CloudSession? = nil,
                     timeout: TimeInterval = CloudAPIClient.defaultTimeout) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KlimaBilanz/\(appVersion) (\(build); iOS \(osVersion))", forHTTPHeaderField: "User-Agent")
        request.setValue(appVersion, forHTTPHeaderField: "X-KB-App-Version")
        if let session { request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization") }
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.send(request)
        try Self.validate(data, response)
        return data
    }

    /// Maps a non-2xx answer to `CloudError` (§3.1). Only answers with `X-KB-API: 1` are trusted as our API's.
    static func validate(_ data: Data, _ response: HTTPURLResponse) throws {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        guard response.value(forHTTPHeaderField: "X-KB-API") == "1" else {
            throw CloudError.http(status, excerpt(data))
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = json?["error"] as? String ?? ""
        let description = json?["error_description"] as? String ?? ""
        if status == 426 || code == "upgrade_required" {
            throw CloudError.upgradeRequired(minVersion: json?["min_app_version"] as? String)
        }
        if status == 429 || code == "rate_limited" {
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            throw CloudError.rateLimited(retryAfter: retry)
        }
        switch code {
        case "unknown_field", "unknown_table":
            throw CloudError.schemaOutdated
        case "invalid_row":
            let details = json?["details"] as? [String: Any]
            throw CloudError.invalidRow(field: details?["field"] as? String)
        case "":
            throw CloudError.http(status, description.isEmpty ? excerpt(data) : description)
        default:
            throw CloudError.api(status: status, code: code, message: description)
        }
    }

    private static func excerpt(_ data: Data) -> String {
        String(decoding: data.prefix(200), as: UTF8.self)
    }

    /// Token response (§2.7.1) → session. Lifetimes count from the device clock.
    func decodeSession(_ data: Data, fallbackUser: CloudUser?) throws -> CloudSession {
        let response: TokenResponse
        do {
            response = try CloudCoding.decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw CloudError.invalidResponse
        }
        guard !response.access_token.isEmpty, !response.refresh_token.isEmpty,
              let user = response.user ?? fallbackUser else { throw CloudError.invalidResponse }
        let issued = now()
        let lifetime = response.expires_in.flatMap { $0 > 0 ? $0 : nil } ?? 900
        return CloudSession(accessToken: response.access_token, refreshToken: response.refresh_token,
                            expiresAt: issued.addingTimeInterval(lifetime),
                            refreshExpiresAt: response.refresh_token_expires_in.map { issued.addingTimeInterval($0) },
                            user: user)
    }

    // MARK: Encoding helpers

    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    /// RFC 3986 strict: everything but unreserved characters is percent-encoded (so "+" never turns into a space).
    static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// `application/x-www-form-urlencoded`, keys sorted for stable output.
    static func formEncode(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }.map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }.joined(separator: "&")
    }
}

// MARK: - Wire envelopes

struct TokenResponse: Decodable {
    var access_token: String
    var token_type: String?
    var expires_in: Double?
    var refresh_token: String
    var refresh_token_expires_in: Double?
    var user: CloudUser?
}

struct UserEnvelope: Decodable {
    var user: CloudUser
}

struct PushAnswer: Decodable {
    var applied: Int
    var skipped: Int
    var server_rev: Int64
}

struct PullPage<Row: Decodable>: Decodable {
    var rows: [Row]
    var next: Int64?
}
