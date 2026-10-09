import Foundation

/// A signed-in session with the KlimaBilanz API (contract §2.7).
public struct CloudSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    /// Device clock, computed from `expires_in` when the token arrives: a skewed device clock neither keeps using
    /// expired tokens nor refreshes on every request.
    public var expiresAt: Date
    /// Device clock; the refresh token slides (every refresh moves it), so this is informational.
    public var refreshExpiresAt: Date?
    public var user: CloudUser

    public init(accessToken: String, refreshToken: String, expiresAt: Date, refreshExpiresAt: Date? = nil, user: CloudUser) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.user = user
    }

    /// The access token expires within 60 s.
    public var isExpired: Bool { isExpired(at: Date()) }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt.addingTimeInterval(-60) }
}

/// The user object of the token response, `/v1/me` and `PATCH /v1/me` (contract §2.6).
public struct CloudUser: Codable, Equatable, Sendable {
    /// Internal UUID (lowercase).
    public var id: String
    public var email: String?
    public var emailVerified: Bool
    public var displayName: String?
    public var avatarURL: String?
    /// Provider of the current session: "apple", "google" or "microsoft".
    public var provider: String
    public var createdAt: Date?

    public init(id: String, email: String? = nil, emailVerified: Bool = false, displayName: String? = nil,
                avatarURL: String? = nil, provider: String, createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.emailVerified = emailVerified
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.provider = provider
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, email, provider
        case emailVerified = "email_verified"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }

    /// Wire format (snake_case); also used for the Keychain copy. Dates are canonical strings, independent of the
    /// coder's date strategy. Unknown keys are ignored, missing optional keys are nil.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        emailVerified = (try? c.decodeIfPresent(Bool.self, forKey: .emailVerified)) ?? false
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        provider = (try? c.decodeIfPresent(String.self, forKey: .provider)) ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)).flatMap { $0 }.flatMap(APITimestamp.date(from:))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encode(emailVerified, forKey: .emailVerified)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(createdAt.map(APITimestamp.string(from:)), forKey: .createdAt)
    }
}

/// Names in `CloudConfig.features` (contract §3.3).
public enum CloudFeature {
    /// `via` on trips and favorite_routes (backend migration 0002, docs/VIA.md §3).
    public static let tripVia = "trip_via"
}

/// `GET /v1/config` (contract §3.3). Decoding tolerates unknown and missing keys (missing provider flags = disabled).
public struct CloudConfig: Codable, Equatable, Sendable {
    public var apiVersion: Int
    public var googleWeb: Bool
    public var microsoftWeb: Bool
    public var appleWeb: Bool
    public var appleNative: Bool
    public var minAppVersion: String?
    public var syncTables: [String]
    public var serverTime: Date?
    public var pushMaxRows: Int?
    public var pullMaxLimit: Int?
    public var maxBodyBytes: Int?
    /// Additive server capabilities (`features`, contract §3.3), e.g. `CloudFeature.tripVia`. Empty for older Workers.
    public var features: [String]

    public init(apiVersion: Int = 1, googleWeb: Bool = false, microsoftWeb: Bool = false, appleWeb: Bool = false,
                appleNative: Bool = false, minAppVersion: String? = nil, syncTables: [String] = [], serverTime: Date? = nil,
                pushMaxRows: Int? = nil, pullMaxLimit: Int? = nil, maxBodyBytes: Int? = nil, features: [String] = []) {
        self.apiVersion = apiVersion
        self.googleWeb = googleWeb
        self.microsoftWeb = microsoftWeb
        self.appleWeb = appleWeb
        self.appleNative = appleNative
        self.minAppVersion = minAppVersion
        self.syncTables = syncTables
        self.serverTime = serverTime
        self.pushMaxRows = pushMaxRows
        self.pullMaxLimit = pullMaxLimit
        self.maxBodyBytes = maxBodyBytes
        self.features = features
    }

    /// The server lists `feature` (e.g. `CloudFeature.tripVia`): the app may send the sync keys that come with it.
    public func supports(_ feature: String) -> Bool { features.contains(feature) }

    /// At least one way to sign in is enabled on the server (`native` = this build can use native Sign in with Apple).
    public func hasAnyProvider(native: Bool) -> Bool {
        googleWeb || microsoftWeb || appleWeb || (native && appleNative)
    }

    private enum Keys: String, CodingKey {
        case apiVersion = "api_version", providers, minAppVersion = "min_app_version", syncTables = "sync_tables"
        case limits, serverTime = "server_time", features
    }

    private enum ProviderKeys: String, CodingKey { case google, microsoft, apple }
    private enum FlagKeys: String, CodingKey { case web, native }
    private enum LimitKeys: String, CodingKey {
        case pushMaxRows = "push_max_rows", pullMaxLimit = "pull_max_limit", maxBodyBytes = "max_body_bytes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        apiVersion = (try? c.decodeIfPresent(Int.self, forKey: .apiVersion)).flatMap { $0 } ?? 1
        minAppVersion = (try? c.decodeIfPresent(String.self, forKey: .minAppVersion)).flatMap { $0 }
        syncTables = (try? c.decodeIfPresent([String].self, forKey: .syncTables)).flatMap { $0 } ?? []
        serverTime = (try? c.decodeIfPresent(String.self, forKey: .serverTime)).flatMap { $0 }.flatMap(APITimestamp.date(from:))
        features = (try? c.decodeIfPresent([String].self, forKey: .features)).flatMap { $0 } ?? []

        func flag(_ provider: ProviderKeys, _ key: FlagKeys) -> Bool {
            guard let providers = try? c.nestedContainer(keyedBy: ProviderKeys.self, forKey: .providers),
                  let flags = try? providers.nestedContainer(keyedBy: FlagKeys.self, forKey: provider) else { return false }
            return (try? flags.decodeIfPresent(Bool.self, forKey: key)).flatMap { $0 } ?? false
        }
        googleWeb = flag(.google, .web)
        microsoftWeb = flag(.microsoft, .web)
        appleWeb = flag(.apple, .web)
        appleNative = flag(.apple, .native)

        let limits = try? c.nestedContainer(keyedBy: LimitKeys.self, forKey: .limits)
        pushMaxRows = (try? limits?.decodeIfPresent(Int.self, forKey: .pushMaxRows)).flatMap { $0 }
        pullMaxLimit = (try? limits?.decodeIfPresent(Int.self, forKey: .pullMaxLimit)).flatMap { $0 }
        maxBodyBytes = (try? limits?.decodeIfPresent(Int.self, forKey: .maxBodyBytes)).flatMap { $0 }
    }

    /// Same shape as the server's answer, so a cached copy decodes with `init(from:)`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(apiVersion, forKey: .apiVersion)
        var providers = c.nestedContainer(keyedBy: ProviderKeys.self, forKey: .providers)
        var google = providers.nestedContainer(keyedBy: FlagKeys.self, forKey: .google)
        try google.encode(googleWeb, forKey: .web)
        var microsoft = providers.nestedContainer(keyedBy: FlagKeys.self, forKey: .microsoft)
        try microsoft.encode(microsoftWeb, forKey: .web)
        var apple = providers.nestedContainer(keyedBy: FlagKeys.self, forKey: .apple)
        try apple.encode(appleWeb, forKey: .web)
        try apple.encode(appleNative, forKey: .native)
        try c.encodeIfPresent(minAppVersion, forKey: .minAppVersion)
        try c.encode(syncTables, forKey: .syncTables)
        try c.encodeIfPresent(serverTime.map(APITimestamp.string(from:)), forKey: .serverTime)
        if !features.isEmpty { try c.encode(features, forKey: .features) }
        if pushMaxRows != nil || pullMaxLimit != nil || maxBodyBytes != nil {
            var limits = c.nestedContainer(keyedBy: LimitKeys.self, forKey: .limits)
            try limits.encodeIfPresent(pushMaxRows, forKey: .pushMaxRows)
            try limits.encodeIfPresent(pullMaxLimit, forKey: .pullMaxLimit)
            try limits.encodeIfPresent(maxBodyBytes, forKey: .maxBodyBytes)
        }
    }
}

/// Answer of `POST /v1/sync/push`, summed over every chunk.
public struct PushResult: Equatable, Sendable {
    public var applied: Int
    public var skipped: Int
    /// The highest revision the server reported (nil when nothing was sent).
    public var serverRev: Int64?
    /// Number of HTTP requests (chunks) sent.
    public var requests: Int

    public init(applied: Int = 0, skipped: Int = 0, serverRev: Int64? = nil, requests: Int = 0) {
        self.applied = applied
        self.skipped = skipped
        self.serverRev = serverRev
        self.requests = requests
    }
}
