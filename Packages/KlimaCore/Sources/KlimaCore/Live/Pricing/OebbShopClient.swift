import Foundation

/// ÖBB ticket shop JSON API, anonymous (SPEC §B3). Reads prices only; buying always hands off to the shop (§2.5).
///
/// Every call: kill switch / provider toggle (`.disabled`, no I/O) → `health.check` → per-quote budget → throttle
/// (≥ 1 s apart, ≤ 12 per minute) → transport → classification → `health.record…`.
///
/// Session: `GET anonymousToken` then `POST initUserData {}` (without it `timetable` answers 440/3011). The token is
/// kept **in memory only** (never persisted, never logged) and renewed after `config.shop.tokenRenewAfter` (240 s; it
/// lives 300 s). 401/13008 and 440/3011 drop the session, renew it and retry once; a second failure is
/// `.sessionExpired`. A Cloudflare HTML 403 is `.blocked` (circuit open 30 min) and is never evaded: honest
/// User-Agent, no header games, no retry. At most one automatic retry for timeouts, network errors and 502/503/504.
public actor OebbShopClient {
    static let retryDelay: TimeInterval = 1.5
    static let sessionCodes: Set<Int> = [13008, 3011]

    public struct Station: Codable, Sendable, Hashable {
        /// EVA number = HAFAS extId (meta stations such as 1290401 „Wien Hbf (U)“ work).
        public var number: Int
        public var name: String
        /// Micro-degrees.
        public var latitude: Int
        public var longitude: Int

        public init(number: Int, name: String, latitude: Int, longitude: Int) {
            self.number = number
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
        }

        /// From a HAFAS location (extId must be numeric).
        public init?(location: Location) {
            guard let ext = location.extId, let n = Int(ext.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
            self.init(number: n, name: location.name, coordinate: location.coordinate)
        }

        /// Micro-degree coordinates; a missing or invalid coordinate (NaN, ±∞, out of range) is sent as 0/0.
        public init(number: Int, name: String, coordinate: GeoPoint?) {
            let valid = coordinate.flatMap { HafasRequests.isValid($0) ? $0 : nil }
            self.init(number: number, name: name,
                      latitude: valid.map { Int(($0.latitude * 1e6).rounded()) } ?? 0,
                      longitude: valid.map { Int(($0.longitude * 1e6).rounded()) } ?? 0)
        }

        public var coordinate: GeoPoint? {
            guard latitude != 0 || longitude != 0 else { return nil }
            return GeoPoint(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6)
        }
    }

    private struct Session {
        var token: String
        var obtainedAt: Date
    }

    /// Internal classification result: the shop wants a new session (401/13008, 440/3011).
    private struct SessionRejected: Error {
        var status: Int
    }

    private var config: LiveConfig
    private let transport: any HTTPTransport
    private let throttle: RequestThrottle
    private let health: LiveHealth
    private let clock: @Sendable () -> Date
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private let appVersion: String
    private var session: Session?
    private var sessionTask: Task<Session, Error>?
    /// Requests sent since creation (tests, diagnostics).
    private(set) var requestCount = 0

    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth,
                clock: @escaping @Sendable () -> Date = { Date() }, appVersion: String? = nil,
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.config = config
        self.transport = transport
        self.throttle = throttle
        self.health = health
        self.clock = clock
        self.sleeper = sleeper
        self.appVersion = appVersion ?? OebbShopClient.bundleVersion
    }

    /// New base URL / limits / kill switch from the remote config. A changed base URL or a disabled shop drops the session.
    public func update(config: LiveConfig) {
        if config.shop.baseURL != self.config.shop.baseURL || !config.isEnabled(.oebbShop) { dropSession() }
        self.config = config
    }

    /// Drops the anonymous session (e.g. Settings „Live-Cache leeren“).
    public func resetSession() {
        dropSession()
    }

    /// True when a token younger than `tokenRenewAfter` is held (the next priced call needs no token/init requests).
    public var hasFreshSession: Bool {
        guard let s = session else { return false }
        return clock().timeIntervalSince(s.obtainedAt) <= config.shop.tokenRenewAfter
    }

    // MARK: - API

    /// `GET /api/hafas/v1/stations?name=<q>&count=5` – fallback station lookup only (SPEC §B3.5).
    public func stations(named name: String) async throws -> [Station] {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var comps = URLComponents(url: endpoint("/api/hafas/v1/stations"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "name", value: q), URLQueryItem(name: "count", value: "5")]
        let data = try await authorized(method: "GET", url: comps.url!, body: nil)
        let raw = try await decode([ShopStationRaw].self, data)
        return raw.compactMap { r in
            guard let n = r.number else { return nil }
            return Station(number: n, name: r.name ?? "", latitude: r.latitude ?? 0, longitude: r.longitude ?? 0)
        }
    }

    /// `POST /api/hafas/v4/timetable` (SPEC §B3.2). Empty result → `.noPrice(infos[0].header ?? "keine buchbare Verbindung")`.
    public func timetable(from: Station, to: Station, departure: Date, discount: FareDiscount, count: Int = 3) async throws -> [ShopConnection] {
        let body = TimetableBody(datetimeDeparture: ShopTime.string(departure), filter: .init(), passengers: [passenger(discount)],
                                 count: max(1, count), sortType: "DEPARTURE", from: from, to: to)
        let data = try await authorized(method: "POST", url: endpoint("/api/hafas/v4/timetable"), body: try encode(body))
        let response = try await decode(ShopTimetableResponse.self, data)
        let connections = (response.connections ?? []).filter { ($0.id ?? "").isEmpty == false }
        guard !connections.isEmpty else {
            throw LiveError.noPrice(response.infos?.first?.header?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "keine buchbare Verbindung")
        }
        return connections
    }

    /// `POST /api/offer/v6/offers`; `datetime` must equal the timetable `datetimeDeparture`. `offerError` → `.noPrice("offerError")`.
    public func offers(connectionID: String, departure: Date, discount: FareDiscount) async throws -> ShopOffers {
        let body = OffersBody(selection: .init(connectionId: connectionID, offerSections: []), passengers: [passenger(discount)],
                              datetime: ShopTime.string(departure))
        let data = try await authorized(method: "POST", url: endpoint("/api/offer/v6/offers"), body: try encode(body))
        let offers = try await decode(ShopOffers.self, data)
        if offers.offerError == true { throw LiveError.noPrice("offerError") }
        return offers
    }

    // MARK: - Bodies (SPEC §B3.2, minimal passenger)

    struct Card: Encodable, Hashable {
        var name: String
        var cardId: Int
    }

    struct Passenger: Encodable, Hashable {
        var type: String
        var id: Int
        var cards: [Card]
    }

    struct TimetableFilter: Encodable, Hashable {
        var regionaltrains = false
        var direct = false
        var wheelchair = false
        var bikes = false
        var trains = false
        var motorail = false
        var connections: [String] = []
    }

    struct TimetableBody: Encodable {
        var datetimeDeparture: String
        var filter: TimetableFilter
        var passengers: [Passenger]
        var count: Int
        var sortType: String
        var from: Station
        var to: Station
    }

    struct OffersSelection: Encodable {
        var connectionId: String
        var offerSections: [String]
    }

    struct OffersBody: Encodable {
        var selection: OffersSelection
        var passengers: [Passenger]
        var datetime: String
    }

    func passenger(_ discount: FareDiscount) -> Passenger {
        let cards = discount == .vorteilscard ? [Card(name: "Vorteilscard Classic", cardId: config.shop.vorteilscardCardID)] : []
        return Passenger(type: "ADULT", id: 1, cards: cards)
    }

    // MARK: - Session

    private func dropSession() {
        session = nil
        sessionTask?.cancel()
        sessionTask = nil
    }

    /// Current token, renewing it (token + initUserData) when missing or older than `tokenRenewAfter`. Concurrent callers
    /// share one renewal; a cancelled caller cancels it (its requests stop), and the other callers start over once.
    private func ensureSession(retry: Bool = true) async throws -> String {
        if let s = session, clock().timeIntervalSince(s.obtainedAt) <= config.shop.tokenRenewAfter { return s.token }
        session = nil
        let task: Task<Session, Error>
        if let running = sessionTask {
            task = running
        } else {
            task = Task { try await self.openSession() }
            sessionTask = task
        }
        do {
            let s = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            if sessionTask == task { sessionTask = nil }
            session = s
            return s.token
        } catch is CancellationError where retry && !Task.isCancelled {
            if sessionTask == task { sessionTask = nil }
            return try await ensureSession(retry: false)
        } catch {
            if sessionTask == task { sessionTask = nil }
            throw error
        }
    }

    private func openSession() async throws -> Session {
        let tokenData = try await exchange(request(method: "GET", url: endpoint("/api/domain/v1/anonymousToken"), token: nil, body: nil))
        guard let token = try await decode(ShopTokenResponse.self, tokenData).accessToken?.nilIfEmpty else {
            throw LiveError.decoding("anonymousToken ohne access_token")
        }
        let obtainedAt = clock()
        _ = try await exchange(request(method: "POST", url: endpoint("/api/domain/v1/initUserData"), token: token, body: Data("{}".utf8)))
        return Session(token: token, obtainedAt: obtainedAt)
    }

    /// An authenticated call: at most one session renewal + retry for 401/13008 and 440/3011.
    private func authorized(method: String, url: URL, body: Data?) async throws -> Data {
        try ensureEnabled()
        var renewed = false
        while true {
            let token = try await ensureSession()
            do {
                return try await exchange(request(method: method, url: url, token: token, body: body))
            } catch is SessionRejected {
                dropSession()
                if renewed {
                    await health.recordFailure(.oebbShop, .sessionExpired)
                    throw LiveError.sessionExpired
                }
                renewed = true
            }
        }
    }

    // MARK: - Transport pipeline

    private func ensureEnabled() throws {
        guard config.isEnabled(.oebbShop) else { throw LiveError.disabled(.oebbShop) }
    }

    var userAgent: String { config.userAgent.replacingOccurrences(of: "{version}", with: appVersion) }

    private func endpoint(_ path: String) -> URL {
        config.shop.baseURL.appendingPathComponent(String(path.dropFirst()))
    }

    /// Exactly the headers of SPEC §B3.1; nothing else (no cookies – the transport session stores none).
    func request(method: String, url: URL, token: String?, body: Data?) -> HTTPRequest {
        var headers = ["User-Agent": userAgent, "Accept": "application/json", "Channel": "inet"]
        if let token { headers["AccessToken"] = token }
        if method == "POST" { headers["Content-Type"] = "application/json" }
        return HTTPRequest(method: method, url: url, headers: headers, body: body, timeout: config.shop.timeout)
    }

    /// Health check, budget, throttle, transport, classification; one retry for timeout / network / 502–504.
    private func exchange(_ request: HTTPRequest) async throws -> Data {
        try ensureEnabled()
        try await health.check(.oebbShop)
        let budget = RequestThrottle.budget(for: .oebbShop)
        var attempt = 0
        while true {
            try PriceRequestBudget.spend(.oebbShop)
            try await throttle.acquire(.oebbShop, minInterval: max(config.shop.minInterval, budget.minInterval), perMinute: budget.perMinute)
            requestCount += 1
            do {
                let response = try await transport.send(request)
                let data = try Self.classify(response)
                await health.recordSuccess(.oebbShop)
                return data
            } catch let error as LiveError {
                if attempt == 0, Self.isRetryable(error) {
                    attempt += 1
                    try await sleeper(Self.retryDelay)
                    continue
                }
                await health.recordFailure(.oebbShop, error)
                throw error
            }
        }
    }

    static func isRetryable(_ e: LiveError) -> Bool {
        switch e {
        case .timeout, .network: return true
        case .http(let status, _): return [502, 503, 504].contains(status)
        default: return false
        }
    }

    /// SPEC §B3.4, in this order: HTML 403 → `.blocked`; 429 → `.rateLimited`; 401/13008 and 440/3011 → session
    /// renewal; any other ≥ 400 or a non-JSON body → `.http`.
    static func classify(_ r: HTTPResponse) throws -> Data {
        let looksJSON = r.isJSON || firstByte(r.body).map { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") } == true
        let isHTML = r.contentType.contains("html") || firstByte(r.body) == UInt8(ascii: "<")
        if r.status == 403, !looksJSON || isHTML { throw LiveError.blocked(.oebbShop) }
        if r.status == 429 {
            throw LiveError.rateLimited(.oebbShop, retryAfter: r.headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        }
        if r.status == 401 || r.status == 440, looksJSON,
           let code = (try? JSONDecoder().decode(ShopErrorResponse.self, from: r.body))?.error?.code, sessionCodes.contains(code) {
            throw SessionRejected(status: r.status)
        }
        guard (200..<300).contains(r.status), looksJSON, !isHTML else {
            let excerpt = String(decoding: r.body.prefix(160), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            throw LiveError.http(status: r.status, excerpt: excerpt)
        }
        return r.body
    }

    private static func firstByte(_ data: Data) -> UInt8? {
        data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) })
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) async throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let e = LiveError.decoding("Shop-Antwort unerwartet: \(T.self)")
            await health.recordFailure(.oebbShop, e)
            throw e
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw LiveError.decoding("Anfrage nicht kodierbar: \(error)")
        }
    }

    /// `CFBundleShortVersionString` of the host app ("1.0" when unknown, e.g. on Linux).
    static var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.nilIfEmpty ?? "1.0"
    }
}
