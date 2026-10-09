import Foundation

// CONTRACT (Step 0) – owned by WP-A after the contracts commit.
// Remotely updatable endpoint configuration + kill switch. Bundled defaults are the public web-app client identifiers
// that ÖBB / VAO ship in their own web apps (also published in hafas-client, KDE KPublicTransport) – not user secrets.

/// HAFAS client version: `/gate` requires an Int (string → err HAMM), legacy mgate.exe uses a String.
public enum HafasClientVersion: Codable, Sendable, Hashable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i) } else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

public struct HafasProfile: Codable, Sendable, Hashable {
    public struct Client: Codable, Sendable, Hashable {
        public var id: String
        public var type: String
        public var name: String
        public var l: String?
        public var v: HafasClientVersion?

        public init(id: String, type: String, name: String, l: String? = nil, v: HafasClientVersion? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.l = l
            self.v = v
        }
    }

    public var url: URL
    public var lang: String
    public var ver: String
    public var ext: String?
    public var client: Client
    public var aid: String
    public var enabled: Bool
    /// Minimum spacing between two requests to this host (seconds).
    public var minInterval: TimeInterval
    public var timeout: TimeInterval

    public init(url: URL, lang: String, ver: String, ext: String?, client: Client, aid: String, enabled: Bool = true,
                minInterval: TimeInterval = 0.3, timeout: TimeInterval = 20) {
        self.url = url
        self.lang = lang
        self.ver = ver
        self.ext = ext
        self.client = client
        self.aid = aid
        self.enabled = enabled
        self.minInterval = minInterval
        self.timeout = timeout
    }
}

public struct ShopProfile: Codable, Sendable, Hashable {
    public var baseURL: URL
    public var enabled: Bool
    /// Renew the anonymous token after this many seconds (token lives 300 s).
    public var tokenRenewAfter: TimeInterval
    public var minInterval: TimeInterval
    public var timeout: TimeInterval
    /// Vorteilscard Classic card id in the shop (VERIFIED-LIVE: halves the Standard-Ticket).
    public var vorteilscardCardID: Int

    public init(baseURL: URL, enabled: Bool = true, tokenRenewAfter: TimeInterval = 240, minInterval: TimeInterval = 1.0,
                timeout: TimeInterval = 15, vorteilscardCardID: Int = 108) {
        self.baseURL = baseURL
        self.enabled = enabled
        self.tokenRenewAfter = tokenRenewAfter
        self.minInterval = minInterval
        self.timeout = timeout
        self.vorteilscardCardID = vorteilscardCardID
    }
}

public struct LiveConfig: Codable, Sendable, Hashable {
    /// Monotonic; a downloaded config replaces the cached one only when `version` is higher.
    public var version: Int
    public var hafas: HafasProfile
    /// Used automatically when `hafas` answers AUTH/PARSE/HAMM at envelope level (SPEC §A3.1).
    public var hafasFallback: HafasProfile?
    public var shop: ShopProfile
    public var vao: HafasProfile
    /// Sent on every request. "{version}" is replaced by the app version.
    public var userAgent: String
    /// Global kill switch: all live features off, app falls back to offline data.
    public var killSwitch: Bool
    /// Optional German notice shown in Settings › Live-Daten (e.g. "Ticketpreise derzeit nur offline").
    public var notice: String?

    public init(version: Int, hafas: HafasProfile, hafasFallback: HafasProfile?, shop: ShopProfile, vao: HafasProfile,
                userAgent: String, killSwitch: Bool = false, notice: String? = nil) {
        self.version = version
        self.hafas = hafas
        self.hafasFallback = hafasFallback
        self.shop = shop
        self.vao = vao
        self.userAgent = userAgent
        self.killSwitch = killSwitch
        self.notice = notice
    }

    public func isEnabled(_ provider: LiveProvider) -> Bool {
        guard !killSwitch else { return false }
        switch provider {
        case .oebbHafas: return hafas.enabled
        case .oebbShop: return shop.enabled
        case .vaoTariff: return vao.enabled
        }
    }

    public static let `default` = LiveConfig(
        version: 1,
        hafas: HafasProfile(
            url: URL(string: "https://fahrplan.oebb.at/gate")!, lang: "deu", ver: "1.88", ext: "OEBB.14",
            client: .init(id: "OEBB", type: "WEB", name: "webapp", l: "vs_webapp", v: nil),
            aid: "5vHavmuWPWIfetEe", minInterval: 0.3, timeout: 20),
        hafasFallback: HafasProfile(
            url: URL(string: "https://fahrplan.oebb.at/bin/mgate.exe")!, lang: "de", ver: "1.41", ext: nil,
            client: .init(id: "OEBB", type: "IPH", name: "oebbIPH", l: nil, v: .string("6120300")),
            aid: "OWDL4fE4ixNiPBBm", minInterval: 0.5, timeout: 20),
        shop: ShopProfile(baseURL: URL(string: "https://shop.oebbtickets.at")!),
        vao: HafasProfile(
            url: URL(string: "https://anachb.vor.at/hamm/gate")!, lang: "deu", ver: "1.59", ext: "VAO.22",
            client: .init(id: "VAO", type: "WEB", name: "webapp", l: "vs_anachb", v: .int(10022)),
            aid: "wf7mcf9bv3nv8g5f", minInterval: 1.0, timeout: 12),
        userAgent: "KlimaBilanz/{version} (iPhone; iOS; private, low-volume)"
    )
}
