import Foundation
import CryptoKit
import Security

/// Minimal, dependency-free Supabase client (GoTrue auth, PostgREST, Edge Functions) – keeps builds fast and small.
struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// Device-clock based (computed from `expires_in` when the token arrives), so a skewed device clock
    /// neither keeps using expired tokens nor refreshes on every request.
    var expiresAt: Date
    var user: SupabaseUser

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

struct SupabaseUser: Codable, Equatable, Sendable {
    var id: String
    var email: String?
    var provider: String?
    var fullName: String?
    var avatarURL: String?
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case invalidResponse
    case missingCode
    /// HTTP error with a machine-readable code (GoTrue `error_code`, PostgREST `code`).
    case api(status: Int, code: String, message: String)
    /// The identity provider sent an error back to the redirect URL.
    case authorization(String)
    /// The refresh token was rejected (expired, revoked, account deleted) – sign in again.
    case sessionExpired
    /// The database lacks migration 0002 (server_rev, primary key (user_id, id)).
    case schemaOutdated

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud-Anmeldung ist noch nicht eingerichtet."
        case .http(let code, let message): "Serverfehler (\(code)): \(message)"
        case .invalidResponse: "Unerwartete Antwort vom Server."
        case .missingCode: "Die Anmeldung wurde abgebrochen."
        case .api(let status, _, let message): "Serverfehler (\(status)): \(message)"
        case .authorization(let message): "Die Anmeldung hat nicht geklappt: \(message)"
        case .sessionExpired: "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."
        case .schemaOutdated:
            "Die Cloud-Datenbank ist nicht auf dem neuesten Stand. Führe im Supabase SQL Editor supabase/migrations/0002_sync_hardening.sql aus."
        }
    }

    var status: Int? {
        switch self {
        case .http(let status, _), .api(let status, _, _): status
        default: nil
        }
    }

    var code: String? {
        if case .api(_, let code, _) = self { return code }
        return nil
    }

    /// The access token was not accepted (expired or revoked) – refresh and retry once.
    var isUnauthorized: Bool { status == 401 }

    /// A token-endpoint answer that means the refresh token is dead (as opposed to being offline, rate limited or
    /// behind a captive portal / proxy). Only GoTrue's own JSON errors count (machine-readable code, 400/401/403 –
    /// e.g. `refresh_token_not_found`, `refresh_token_already_used`, legacy `invalid_grant`); an HTML 403/404 from a
    /// hotel Wi-Fi must not sign the user out.
    var isDefinitiveAuthFailure: Bool {
        switch self {
        case .sessionExpired: return true
        case .api(let status, let code, _): return [400, 401, 403].contains(status) && !code.isEmpty
        default: return false
        }
    }
}

/// A row that carries the server-assigned revision used as pull cursor (see 0002_sync_hardening.sql).
protocol ServerRevisioned {
    var id: UUID { get }
    var server_rev: Int64? { get }
}

struct SupabaseClient: Sendable {
    let baseURL: URL
    let anonKey: String

    /// Supplies a valid session for a request. `rejected` is the session whose access token just got HTTP 401:
    /// the provider refreshes (once, serialized) and returns the new session, or throws.
    typealias SessionProvider = @Sendable (_ rejected: SupabaseSession?) async throws -> SupabaseSession

    /// Columns the server assigns; never sent on upsert.
    static let serverManagedColumns: Set<String> = ["server_rev"]

    // MARK: Auth

    /// Native Sign in with Apple → Supabase session.
    func signInWithIdToken(provider: String, idToken: String, nonce: String?) async throws -> SupabaseSession {
        var body: [String: String] = ["provider": provider, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        return try await tokenRequest(grantType: "id_token", body: body)
    }

    /// URL for the OAuth (PKCE) web flow, opened in ASWebAuthenticationSession.
    func authorizeURL(provider: String, redirectTo: String, codeChallenge: String, scopes: String? = nil) -> URL {
        var comps = URLComponents(url: baseURL.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        if let scopes { items.append(URLQueryItem(name: "scopes", value: scopes)) }
        comps.queryItems = items
        comps.percentEncodedQuery = Self.escapingPlus(comps.percentEncodedQuery)
        return comps.url!
    }

    func exchangeCode(_ code: String, codeVerifier: String) async throws -> SupabaseSession {
        try await tokenRequest(grantType: "pkce", body: ["auth_code": code, "code_verifier": codeVerifier])
    }

    /// Refresh tokens are single use: callers must serialize refreshes (AuthService does).
    func refresh(_ session: SupabaseSession) async throws -> SupabaseSession {
        try await tokenRequest(grantType: "refresh_token", body: ["refresh_token": session.refreshToken],
                               fallbackUser: session.user)
    }

    /// Ends the session on the server. `scope` "local" = only this device (GoTrue's default "global" would sign the
    /// user out on every device).
    func signOut(_ session: SupabaseSession, scope: String = "local") async {
        var comps = URLComponents(url: baseURL.appending(path: "auth/v1/logout"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "scope", value: scope)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await Self.http.data(for: request)
    }

    /// Merges `data` into the user's `user_metadata` (e.g. the name Apple only sends on the first sign-in).
    func updateUserMetadata(_ data: [String: String], session: SupabaseSession) async throws {
        var request = URLRequest(url: baseURL.appending(path: "auth/v1/user"))
        request.httpMethod = "PUT"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["data": data])
        _ = try await send(request)
    }

    private func tokenRequest(grantType: String, body: [String: String], fallbackUser: SupabaseUser? = nil) async throws -> SupabaseSession {
        var comps = URLComponents(url: baseURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await send(request)
        return try Self.decodeSession(data, fallbackUser: fallbackUser)
    }

    // MARK: Edge Functions

    /// POST {SUPABASE_URL}/functions/v1/<name> with the user's access token.
    @discardableResult
    func invokeFunction(_ name: String, body: Data = Data("{}".utf8), session: SupabaseSession) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    // MARK: PostgREST

    func select<T: Decodable>(_ table: String, query: [URLQueryItem], session: SupabaseSession) async throws -> [T] {
        var comps = URLComponents(url: baseURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        // URLComponents leaves "+" alone, but servers read it as a space (e.g. in "+02:00" offsets).
        comps.percentEncodedQuery = Self.escapingPlus(comps.percentEncodedQuery)
        var request = URLRequest(url: comps.url!)
        authorize(&request, session: session)
        let data = try await send(request)
        return try Self.decoder.decode([T].self, from: data)
    }

    /// Bulk upsert. Every JSON object carries the same keys (nil → explicit `null`) and `columns=` lists them, so
    /// PostgREST never answers 400 PGRST102 "All object keys must match" for batches that mix rows with and
    /// without optional values. Server-managed columns are stripped.
    func upsert<T: Encodable>(_ table: String, rows: [T], onConflict: String = "id", session: SupabaseSession) async throws {
        guard !rows.isEmpty else { return }
        let payload = try RowPayload.make(rows, encoder: Self.encoder, dropping: Self.serverManagedColumns)
        var comps = URLComponents(url: baseURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict),
                            URLQueryItem(name: "columns", value: payload.columns.joined(separator: ","))]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = payload.body
        _ = try await send(request)
    }

    /// Upserts in chunks; each chunk asks `session` for a valid token and retries once after HTTP 401.
    func upsertAll<T: Encodable>(_ table: String, rows: [T], onConflict: String, chunkSize: Int = 500,
                                 session: SessionProvider) async throws {
        var start = 0
        while start < rows.count {
            let chunk = Array(rows[start..<min(start + chunkSize, rows.count)])
            try await Self.withSession(session) { try await upsert(table, rows: chunk, onConflict: onConflict, session: $0) }
            start += chunkSize
        }
    }

    /// Every row of `table` written after `cursor` (minus `overlap`), as keyset pages ordered by (server_rev, id).
    /// Supabase caps a response at "Max rows" (default 1000) without any error, so a single request is never enough.
    /// Returns the rows and the highest server_rev seen (never below `cursor`).
    func pullAll<T: Decodable & ServerRevisioned>(_ table: String, ownerColumn: String = "user_id", userID: String,
                                                  since cursor: Int64, overlap: Int64, pageSize: Int = 500,
                                                  maxPages: Int = 4000, session: SessionProvider) async throws -> (rows: [T], maxRev: Int64) {
        let start = max(0, cursor - overlap)
        var after: KeysetPosition?
        var rows: [T] = []
        var maxRev = cursor
        for _ in 0..<maxPages {
            let query = Self.keysetQuery(ownerColumn: ownerColumn, userID: userID, start: start, after: after, limit: pageSize)
            let page: [T] = try await Self.withSession(session) { try await select(table, query: query, session: $0) }
            rows.append(contentsOf: page)
            for row in page { if let rev = row.server_rev, rev > maxRev { maxRev = rev } }
            guard page.count >= pageSize, let last = page.last else { return (rows, maxRev) }
            guard let lastRev = last.server_rev else { throw SupabaseError.schemaOutdated }
            let next = KeysetPosition(rev: lastRev, id: last.id)
            if next == after { throw SupabaseError.invalidResponse }   // no progress – never loop forever
            after = next
        }
        throw SupabaseError.invalidResponse
    }

    struct KeysetPosition: Equatable, Sendable {
        var rev: Int64
        var id: UUID
    }

    static func keysetQuery(ownerColumn: String = "user_id", userID: String, start: Int64, after: KeysetPosition?,
                            limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "select", value: "*"),
                     URLQueryItem(name: ownerColumn, value: "eq.\(userID)")]
        if let after {
            let id = after.id.uuidString.lowercased()
            items.append(URLQueryItem(name: "or", value: "(server_rev.gt.\(after.rev),and(server_rev.eq.\(after.rev),id.gt.\(id)))"))
        } else {
            items.append(URLQueryItem(name: "server_rev", value: "gte.\(start)"))
        }
        items.append(URLQueryItem(name: "order", value: "server_rev.asc,id.asc"))
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        return items
    }

    /// Runs `operation` with a session from `provider`; after HTTP 401 asks for a refreshed session and retries once.
    static func withSession<R>(_ provider: SessionProvider, _ operation: (SupabaseSession) async throws -> R) async throws -> R {
        let session = try await provider(nil)
        do {
            return try await operation(session)
        } catch let error as SupabaseError where error.isUnauthorized {
            let fresh = try await provider(session)
            return try await operation(fresh)
        }
    }

    private func authorize(_ request: inout URLRequest, session: SupabaseSession) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.http.data(for: request)
        try Self.validate(data, response)
        return data
    }

    // MARK: Helpers

    /// No disk cache, no cookies, bounded timeouts.
    static let http: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(PostgresTimestamp.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            if let date = PostgresTimestamp.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unbekanntes Datumsformat: \(raw)")
        }
        return d
    }()

    static func escapingPlus(_ query: String?) -> String? {
        query?.replacingOccurrences(of: "+", with: "%2B")
    }

    static func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard !(200..<300).contains(http.statusCode) else { return }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = json.flatMap { ($0["error_description"] ?? $0["msg"] ?? $0["message"] ?? $0["error"]) as? String }
            ?? String(data: data, encoding: .utf8) ?? ""
        // GoTrue: "error_code" (newer) or "error" next to "error_description" (older); PostgREST: "code".
        let code = json.flatMap { j -> String? in
            (j["error_code"] as? String) ?? (j["code"] as? String) ?? (j["error_description"] != nil ? j["error"] as? String : nil)
        }
        if let code, isSchemaErrorCode(code) { throw SupabaseError.schemaOutdated }
        if let code, !code.isEmpty { throw SupabaseError.api(status: http.statusCode, code: code, message: message) }
        throw SupabaseError.http(http.statusCode, message)
    }

    /// 42703 undefined column (server_rev), 42P10 no unique constraint for on_conflict=user_id,id,
    /// PGRST204 column missing from the schema cache, PGRST205 / 42P01 table missing (benefits).
    static func isSchemaErrorCode(_ code: String) -> Bool {
        ["42703", "42P10", "PGRST204", "PGRST205", "42P01"].contains(code)
    }

    static func decodeSession(_ data: Data, fallbackUser: SupabaseUser? = nil, now: Date = Date()) throws -> SupabaseSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String, !access.isEmpty,
              let refresh = json["refresh_token"] as? String, !refresh.isEmpty else { throw SupabaseError.invalidResponse }
        let user: SupabaseUser
        if let raw = json["user"] as? [String: Any], let id = raw["id"] as? String {
            let meta = raw["user_metadata"] as? [String: Any] ?? [:]
            let app = raw["app_metadata"] as? [String: Any] ?? [:]
            user = SupabaseUser(
                id: id,
                email: raw["email"] as? String,
                provider: app["provider"] as? String,
                fullName: (meta["full_name"] ?? meta["name"]) as? String,
                avatarURL: (meta["avatar_url"] ?? meta["picture"]) as? String
            )
        } else if let fallbackUser {
            user = fallbackUser
        } else {
            throw SupabaseError.invalidResponse
        }
        // Prefer the relative lifetime: `expires_at` is the server's clock, the device clock may differ.
        let expiresAt: Date
        if let expiresIn = number(json["expires_in"]), expiresIn > 0 {
            expiresAt = now.addingTimeInterval(expiresIn)
        } else if let absolute = number(json["expires_at"]) {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else {
            expiresAt = now.addingTimeInterval(3600)
        }
        return SupabaseSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, user: user)
    }

    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

// MARK: - JSON rows

/// Untyped JSON value, used to normalise upsert payloads.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

enum RowPayload {
    /// Encodes `rows` as a JSON array whose objects all have the same keys: the union of every row's keys, with
    /// missing ones (synthesized `Encodable` omits nil optionals) set to `null`. Returns the body and the sorted keys.
    static func make<T: Encodable>(_ rows: [T], encoder: JSONEncoder, dropping: Set<String> = []) throws -> (body: Data, columns: [String]) {
        let decoded = try JSONDecoder().decode([JSONValue].self, from: encoder.encode(rows))
        var objects: [[String: JSONValue]] = []
        objects.reserveCapacity(decoded.count)
        for value in decoded {
            guard case .object(var object) = value else { throw SupabaseError.invalidResponse }
            for key in dropping { object.removeValue(forKey: key) }
            objects.append(object)
        }
        var keys = Set<String>()
        for object in objects { keys.formUnion(object.keys) }
        let columns = keys.sorted()
        let normalized = objects.map { object -> [String: JSONValue] in
            var filled = object
            for key in columns where filled[key] == nil { filled[key] = .null }
            return filled
        }
        let out = JSONEncoder()
        out.outputFormatting = [.sortedKeys]
        return (try out.encode(normalized), columns)
    }
}

// MARK: - Timestamps

/// Postgres `timestamptz` <-> Date without DateFormatter: microsecond precision, any fraction length, offsets
/// `Z`, `±HH`, `±HHMM`, `±HH:MM`, `±HH:MM:SS`, "T" or space separator (PostgREST JSON and psql text output).
enum PostgresTimestamp {
    /// `2026-10-09T07:00:00.123456Z` (UTC, microseconds).
    static func string(from date: Date) -> String {
        let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
        var seconds = micros / 1_000_000
        var fraction = micros % 1_000_000
        if fraction < 0 { fraction += 1_000_000; seconds -= 1 }
        var days = seconds / 86_400
        var secondOfDay = seconds % 86_400
        if secondOfDay < 0 { secondOfDay += 86_400; days -= 1 }
        let (year, month, day) = civil(fromDays: days)
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(secondOfDay / 3600, 2)):\(pad(secondOfDay % 3600 / 60, 2)):"
            + "\(pad(secondOfDay % 60, 2)).\(pad(fraction, 6))Z"
    }

    static func date(from string: String) -> Date? {
        let b = Array(string.utf8)
        var i = 0

        func digits(_ count: Int) -> Int64? {
            guard i + count <= b.count else { return nil }
            var value: Int64 = 0
            for k in i..<(i + count) {
                guard b[k] >= 48, b[k] <= 57 else { return nil }
                value = value * 10 + Int64(b[k] - 48)
            }
            i += count
            return value
        }
        func take(_ char: UInt8) -> Bool {
            guard i < b.count, b[i] == char else { return false }
            i += 1
            return true
        }

        guard let year = digits(4), take(45), let month = digits(2), take(45), let day = digits(2),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        var hour: Int64 = 0, minute: Int64 = 0, second: Int64 = 0
        var nanos: Int64 = 0
        var offset: Int64 = 0
        if i < b.count {
            guard take(84) || take(116) || take(32) else { return nil }   // "T", "t", " "
            guard let h = digits(2), take(58), let m = digits(2) else { return nil }
            hour = h
            minute = m
            if take(58) {
                guard let s = digits(2) else { return nil }
                second = s
                if take(46) || take(44) {   // "." or ","
                    var scale: Int64 = 100_000_000
                    var count = 0
                    while i < b.count, b[i] >= 48, b[i] <= 57 {
                        nanos += Int64(b[i] - 48) * scale
                        scale /= 10
                        i += 1
                        count += 1
                    }
                    guard count > 0 else { return nil }
                }
            }
            guard hour <= 24, minute <= 59, second <= 60 else { return nil }
            if i < b.count {
                if take(90) || take(122) {   // "Z" / "z"
                    offset = 0
                } else {
                    let sign: Int64
                    if take(43) { sign = 1 } else if take(45) { sign = -1 } else { return nil }
                    guard let oh = digits(2) else { return nil }
                    var om: Int64 = 0, os: Int64 = 0
                    if take(58) {
                        guard let m = digits(2) else { return nil }
                        om = m
                        if take(58) {
                            guard let s = digits(2) else { return nil }
                            os = s
                        }
                    } else if let m = digits(2) {
                        om = m
                    }
                    guard oh <= 23, om <= 59, os <= 59 else { return nil }
                    offset = sign * (oh * 3600 + om * 60 + os)
                }
            }
            guard i == b.count else { return nil }
        }
        let seconds = days(fromCivil: year, month, day) * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000)
    }

    private static func pad(_ value: Int64, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    private static func isLeap(_ year: Int64) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    private static func daysIn(month: Int64, year: Int64) -> Int64 {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Days since 1970-01-01 (proleptic Gregorian, H. Hinnant's algorithm).
    private static func days(fromCivil year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func civil(fromDays days: Int64) -> (Int64, Int64, Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

// MARK: - PKCE & nonce

enum PKCE {
    static func makeVerifier() -> String { randomURLSafe(byteCount: 48) }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            // Never fall back to a predictable value: SystemRandomNumberGenerator is a CSPRNG on Apple platforms.
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        }
        return base64URL(Data(bytes))
    }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Keychain

enum Keychain {
    static let service = "com.knitelarlberg.klimabilanz"

    enum ReadResult {
        case found(Data)
        case notFound
        /// Protected data is not available yet (background launch before the first unlock after a reboot).
        case locked
        case failed(OSStatus)
    }

    /// Writes (`SecItemUpdate`, else `SecItemAdd` – never delete-then-add, so a failed write keeps the old item) or
    /// deletes (`nil`). Returns false when the keychain refused (e.g. still locked).
    @discardableResult
    static func set(_ data: Data?, for key: String, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: accessibility]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            for (name, value) in attributes { add[name] = value }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func read(_ key: String) -> ReadResult {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data { return .found(data) }
            return .notFound
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            return .locked
        default:
            return .failed(status)
        }
    }

    static func data(for key: String) -> Data? {
        if case .found(let data) = read(key) { return data }
        return nil
    }
}
