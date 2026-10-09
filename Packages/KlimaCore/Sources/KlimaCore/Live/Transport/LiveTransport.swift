import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// CONTRACT (Step 0) – owned by WP-A after the contracts commit. Public API must not change without the lead.

/// The three live back ends KlimaBilanz talks to (all called directly from the device, never via a KlimaBilanz server).
public enum LiveProvider: String, Codable, Sendable, CaseIterable, Hashable {
    /// ÖBB Scotty journey planner (HAFAS HCI, fahrplan.oebb.at).
    case oebbHafas
    /// ÖBB ticket shop JSON API (shop.oebbtickets.at) – Standard-Ticket prices.
    case oebbShop
    /// Verkehrsauskunft Österreich HAFAS (anachb.vor.at) – Verbund single-ticket prices.
    case vaoTariff
}

/// Every failure of the live layer is mapped to one of these. Callers decide the fallback; UI copy lives in the app.
public enum LiveError: Error, Sendable, Hashable {
    /// Disabled by the user (settings / no consent) or by the remote kill switch.
    case disabled(LiveProvider)
    /// No network path (URLError.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed).
    case offline
    /// Request exceeded its timeout.
    case timeout
    /// Any other transport error (description of the underlying URLError).
    case network(String)
    /// Unexpected HTTP status (5xx, 404, …) with a short body excerpt for logs.
    case http(status: Int, excerpt: String)
    /// Blocked: Cloudflare 403 HTML page (shop) or HAFAS top-level err "AUTH". Never retry automatically, never evade.
    case blocked(LiveProvider)
    /// HTTP 429 (shop) or Wiener-Linien-style rate code. `retryAfter` from the header when present.
    case rateLimited(LiveProvider, retryAfter: TimeInterval?)
    /// Circuit breaker is open for this provider until the given date.
    case circuitOpen(LiveProvider, until: Date)
    /// Shop session/token expired (401 code 13008, 440 code 3011) and the single automatic retry failed too.
    case sessionExpired
    /// JSON did not match the expected shape (top-level err "PARSE" also maps here – it means our request is wrong).
    case decoding(String)
    /// HAFAS service error code (svcResL[i].err), e.g. "LOCATION", "PARAMETER", "H9381", plus the German errTxtOut.
    case hafas(code: String, message: String?)
    /// HAFAS H890 / no connection found / empty result.
    case noConnection
    /// Shop `offerError: true` (departure in the past or not sellable), VAO `statusCode != OK`, or no FLEX ONEWAY offer.
    case noPrice(String)
}

public struct HTTPRequest: Sendable, Hashable {
    public var method: String
    public var url: URL
    /// Header names exactly as sent.
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 20) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public var status: Int
    /// Header names lower-cased.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        self.body = body
    }

    public var contentType: String { headers["content-type"] ?? "" }
    public var isJSON: Bool { contentType.contains("json") }
}

/// The only network seam of the live layer. Production: `URLSessionTransport`; tests: `FixtureTransport` (WP-A).
/// Implementations return every HTTP status as a response and only throw `LiveError.offline/.timeout/.network`.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Unambiguous names for app files that import both KlimaCore and KlimaCloud: KlimaCloud declares its own
/// `HTTPTransport` and `URLSessionTransport`, so there `URLSessionTransport()` does not compile. Use
/// `LiveURLSessionTransport()` / `any LiveHTTPTransport` (or the module-qualified `KlimaCore.` names).
public typealias LiveHTTPTransport = HTTPTransport
public typealias LiveURLSessionTransport = URLSessionTransport
