import Foundation
import CryptoKit
import Security

/// Minimal, dependency-free Supabase client (GoTrue auth + PostgREST) – keeps builds fast and small.
struct SupabaseSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
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

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud-Anmeldung ist noch nicht eingerichtet."
        case .http(let code, let message): "Serverfehler (\(code)): \(message)"
        case .invalidResponse: "Unerwartete Antwort vom Server."
        case .missingCode: "Die Anmeldung wurde abgebrochen."
        }
    }
}

struct SupabaseClient: Sendable {
    let baseURL: URL
    let anonKey: String

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
        return comps.url!
    }

    func exchangeCode(_ code: String, codeVerifier: String) async throws -> SupabaseSession {
        try await tokenRequest(grantType: "pkce", body: ["auth_code": code, "code_verifier": codeVerifier])
    }

    func refresh(_ session: SupabaseSession) async throws -> SupabaseSession {
        try await tokenRequest(grantType: "refresh_token", body: ["refresh_token": session.refreshToken])
    }

    func signOut(_ session: SupabaseSession) async {
        var request = URLRequest(url: baseURL.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func tokenRequest(grantType: String, body: [String: String]) async throws -> SupabaseSession {
        var comps = URLComponents(url: baseURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(data, response)
        return try Self.decodeSession(data)
    }

    // MARK: PostgREST

    func select<T: Decodable>(_ table: String, query: [URLQueryItem], session: SupabaseSession) async throws -> [T] {
        var comps = URLComponents(url: baseURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var request = URLRequest(url: comps.url!)
        authorize(&request, session: session)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(data, response)
        return try Self.decoder.decode([T].self, from: data)
    }

    func upsert<T: Encodable>(_ table: String, rows: [T], session: SupabaseSession) async throws {
        guard !rows.isEmpty else { return }
        var comps = URLComponents(url: baseURL.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        authorize(&request, session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try Self.encoder.encode(rows)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(data, response)
    }

    private func authorize(_ request: inout URLRequest, session: SupabaseSession) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    // MARK: Helpers

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
            // Postgres "2026-10-09 10:00:00.123+00" style
            let pg = DateFormatter()
            pg.locale = Locale(identifier: "en_US_POSIX")
            pg.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
            if let date = pg.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(raw)")
        }
        return d
    }()

    static func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap {
                ($0["error_description"] ?? $0["msg"] ?? $0["message"] ?? $0["error"]) as? String
            } ?? String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(http.statusCode, message)
        }
    }

    static func decodeSession(_ data: Data) throws -> SupabaseSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let id = user["id"] as? String else { throw SupabaseError.invalidResponse }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let expiresAt = (json["expires_at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(expiresIn)
        let meta = user["user_metadata"] as? [String: Any] ?? [:]
        let app = user["app_metadata"] as? [String: Any] ?? [:]
        return SupabaseSession(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            user: SupabaseUser(
                id: id,
                email: user["email"] as? String,
                provider: app["provider"] as? String,
                fullName: (meta["full_name"] ?? meta["name"]) as? String,
                avatarURL: (meta["avatar_url"] ?? meta["picture"]) as? String
            )
        )
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
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
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

    static func set(_ data: Data?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
