import Foundation

/// ÖBB Scotty journey planner (HAFAS HCI `fahrplan.oebb.at/gate`, SPEC §A3). Production `TimetableService`.
///
/// Every call: kill switch / provider toggle (`.disabled`, no I/O) → `health.check` → `throttle.acquire` → transport →
/// `health.record…`. At most one automatic retry (timeout, HTTP 502/503/504, network) after 1.5 s. When the primary
/// profile answers top-level AUTH/HAMM/PARSE the same call is retried once with `config.hafasFallback`; if that works the
/// fallback is used for 6 h. Blocks are never evaded: no user-agent rotation, honest User-Agent, no further retries.
public actor HafasClient: TimetableService {
    static let perMinute = 40
    static let fallbackHold: TimeInterval = 6 * 3600
    static let retryDelay: TimeInterval = 1.5

    private var config: LiveConfig
    private let transport: any HTTPTransport
    private let throttle: RequestThrottle
    private let health: LiveHealth
    private let appVersion: String
    private let clock: @Sendable () -> Date
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    private var fallbackUntil: Date?

    private var locationCache = TTLCache<String, [Location]>(ttl: 24 * 3600, capacity: 200)
    private var journeyCache = TTLCache<JourneyQuery, JourneyPage>(ttl: 30, capacity: 20)
    private var boardCache = TTLCache<BoardQuery, Board>(ttl: 20, capacity: 20)
    private var tripCache = TTLCache<String, TripDetails>(ttl: 60, capacity: 30)

    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth,
                appVersion: String, clock: @escaping @Sendable () -> Date = { Date() },
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.config = config
        self.transport = transport
        self.throttle = throttle
        self.health = health
        self.appVersion = appVersion
        self.clock = clock
        self.sleeper = sleeper
    }

    /// New endpoints / client ids / kill switch from the remote config; resets the fallback state and the caches.
    public func update(config: LiveConfig) {
        self.config = config
        fallbackUntil = nil
        locationCache.removeAll()
        journeyCache.removeAll()
        boardCache.removeAll()
        tripCache.removeAll()
    }

    /// True while the legacy fallback profile is in use (after the primary answered AUTH/HAMM/PARSE).
    public var isUsingFallback: Bool {
        guard let until = fallbackUntil else { return false }
        return until > clock()
    }

    /// Settings „Verbindung testen“.
    public func serverInfo() async throws -> HafasServerInfo {
        try HafasCodec.serverInfo(from: try await send([HafasRequests.serverInfo()]))
    }

    // MARK: - TimetableService

    public func locations(_ query: String, types: LocationTypes, maxResults: Int) async throws -> [Location] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        try ensureEnabled()
        let key = "\(StationIndex.normalize(q))|\(types.rawValue)|\(maxResults)"
        if let hit = locationCache.value(for: key, now: clock()) { return hit }
        let data = try await send([HafasRequests.locMatch(q, types: types, maxResults: maxResults)])
        let result = try HafasCodec.locations(from: data, query: q)
        locationCache.insert(result, for: key, now: clock())
        return result
    }

    public func nearby(_ point: GeoPoint, maxDistanceMeters: Int, maxResults: Int, products: ProductMask) async throws -> [Location] {
        let data = try await send([HafasRequests.locGeoPos(point, maxDistanceMeters: maxDistanceMeters, maxResults: maxResults, products: products)])
        return try HafasCodec.locations(from: data)
    }

    public func journeys(_ query: JourneyQuery) async throws -> JourneyPage {
        try ensureEnabled()
        if let hit = journeyCache.value(for: query, now: clock()) { return hit }
        let data = try await send([HafasRequests.tripSearch(query)])
        let page = try HafasCodec.journeyPage(from: data)
        journeyCache.insert(page, for: query, now: clock())
        return page
    }

    public func journeys(batch queries: [JourneyQuery]) async throws -> [Result<JourneyPage, LiveError>] {
        guard !queries.isEmpty else { return [] }
        let data = try await send(queries.map(HafasRequests.tripSearch))
        var results = try HafasCodec.journeyPages(from: data)
        while results.count < queries.count { results.append(.failure(.decoding("svcResL zu kurz"))) }
        return Array(results.prefix(queries.count))
    }

    public func refresh(_ refreshToken: String, includeStopovers: Bool, includePolyline: Bool) async throws -> Journey {
        let data = try await send([HafasRequests.reconstruction(refreshToken, includeStopovers: includeStopovers, includePolyline: includePolyline)])
        guard let journey = try HafasCodec.journeyPage(from: data).journeys.first else { throw LiveError.noConnection }
        return journey
    }

    public func refresh(batch refreshTokens: [String]) async throws -> [Result<Journey, LiveError>] {
        guard !refreshTokens.isEmpty else { return [] }
        let data = try await send(refreshTokens.map { HafasRequests.reconstruction($0, includeStopovers: true, includePolyline: false) })
        var results: [Result<Journey, LiveError>] = try HafasCodec.journeyPages(from: data).map { page in
            page.flatMap { p in p.journeys.first.map { .success($0) } ?? .failure(.noConnection) }
        }
        while results.count < refreshTokens.count { results.append(.failure(.decoding("svcResL zu kurz"))) }
        return Array(results.prefix(refreshTokens.count))
    }

    public func trip(_ tripID: String, includePolyline: Bool) async throws -> TripDetails {
        try ensureEnabled()
        let key = "\(tripID)|\(includePolyline)"
        if let hit = tripCache.value(for: key, now: clock()) { return hit }
        let data = try await send([HafasRequests.journeyDetails(tripID, includePolyline: includePolyline)])
        let trip = try HafasCodec.trip(from: data)
        tripCache.insert(trip, for: key, now: clock())
        return trip
    }

    public func board(_ query: BoardQuery) async throws -> Board {
        try ensureEnabled()
        if let hit = boardCache.value(for: query, now: clock()) { return hit }
        let data = try await send([HafasRequests.stationBoard(query)])
        var board = try HafasCodec.board(from: data)
        board.kind = query.kind
        boardCache.insert(board, for: query, now: clock())
        return board
    }

    public func remarks(_ query: RemarksQuery) async throws -> [Remark] {
        try HafasCodec.remarks(from: try await send([HafasRequests.himSearch(query)]))
    }

    // MARK: - Transport pipeline

    private func ensureEnabled() throws {
        guard config.isEnabled(.oebbHafas) else { throw LiveError.disabled(.oebbHafas) }
    }

    var userAgent: String { config.userAgent.replacingOccurrences(of: "{version}", with: appVersion) }

    /// Sends one envelope and returns the body of an envelope-OK response (service errors are left to the codec).
    func send<R: Encodable>(_ svcReqL: [HafasServiceRequest<R>]) async throws -> Data {
        try ensureEnabled()
        let now = clock()
        let fallback = config.hafasFallback.flatMap { $0.enabled ? $0 : nil }
        let onFallback = fallback != nil && (fallbackUntil.map { $0 > now } ?? false)
        if !onFallback { fallbackUntil = nil }
        let profile = onFallback ? fallback! : config.hafas
        guard profile.enabled else { throw LiveError.disabled(.oebbHafas) }

        try await health.check(.oebbHafas)
        let data = try await exchange(svcReqL, profile: profile)
        guard let primaryError = Self.profileError(data) else {
            if let e = HafasCodec.envelopeError(data) {
                // Other top-level codes (e.g. a server-side FAIL): no breaker effect, surface to the caller.
                await health.recordNotice(.oebbHafas, e)
                throw e
            }
            await health.recordSuccess(.oebbHafas)
            return data
        }

        // AUTH / HAMM / PARSE on the active profile: one retry with the fallback profile (SPEC §A3.1).
        if !onFallback, let fallback, fallback.url != profile.url || fallback.aid != profile.aid {
            let second = try await exchange(svcReqL, profile: fallback)
            if Self.profileError(second) == nil, HafasCodec.envelopeError(second) == nil {
                fallbackUntil = clock().addingTimeInterval(Self.fallbackHold)
                await health.recordSuccess(.oebbHafas)
                await health.recordNotice(.oebbHafas, primaryError)
                return second
            }
            let secondError = Self.profileError(second) ?? HafasCodec.envelopeError(second) ?? primaryError
            let final: LiveError
            if case .blocked = primaryError { final = .blocked(.oebbHafas) }
            else if case .blocked = secondError { final = .blocked(.oebbHafas) }
            else { final = primaryError }
            await health.recordFailure(.oebbHafas, final)
            throw final
        }
        await health.recordFailure(.oebbHafas, primaryError)
        throw primaryError
    }

    /// AUTH → `.blocked`, PARSE/HAMM → `.decoding`; nil for OK and other codes.
    static func profileError(_ data: Data) -> LiveError? {
        guard let raw = try? HafasCodec.decodeRaw(data) else { return nil }
        switch raw.err ?? "OK" {
        case "AUTH", "PARSE", "HAMM": return HafasCodec.topError(raw)
        default: return nil
        }
    }

    /// Throttle + transport + classification, with at most one retry. Transport-level failures are recorded in
    /// `health`; throttle rejections are local and not recorded.
    private func exchange<R: Encodable>(_ svcReqL: [HafasServiceRequest<R>], profile: HafasProfile) async throws -> Data {
        let body: Data
        do {
            body = try JSONEncoder().encode(HafasEnvelope(profile: profile, svcReqL: svcReqL))
        } catch {
            throw LiveError.decoding("Anfrage nicht kodierbar: \(error)")
        }
        let request = HTTPRequest(method: "POST", url: profile.url, headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
            "User-Agent": userAgent,
        ], body: body, timeout: profile.timeout)

        var attempt = 0
        while true {
            try await throttle.acquire(.oebbHafas, minInterval: max(profile.minInterval, 0.3), perMinute: Self.perMinute)
            do {
                let response = try await transport.send(request)
                return try Self.classify(response)
            } catch let error as LiveError {
                if attempt == 0, Self.isRetryable(error) {
                    attempt += 1
                    try await sleeper(Self.retryDelay)
                    continue
                }
                await health.recordFailure(.oebbHafas, error)
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

    /// HTTP status ≠ 200 or a non-JSON body → `.http(status, excerpt)`; Cloudflare-style HTML 403 → `.blocked`;
    /// 429 → `.rateLimited`.
    static func classify(_ r: HTTPResponse) throws -> Data {
        let looksJSON = r.body.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }) == UInt8(ascii: "{")
        if r.status == 429 {
            throw LiveError.rateLimited(.oebbHafas, retryAfter: r.headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        }
        if r.status == 403, !looksJSON { throw LiveError.blocked(.oebbHafas) }
        guard r.status == 200, looksJSON else {
            let excerpt = String(decoding: r.body.prefix(160), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            throw LiveError.http(status: r.status, excerpt: excerpt)
        }
        return r.body
    }
}

/// Small in-memory TTL + LRU cache for the client (SPEC §A3.5).
struct TTLCache<Key: Hashable, Value> {
    let ttl: TimeInterval
    let capacity: Int
    private var entries: [Key: (stored: Date, value: Value)] = [:]
    private var order: [Key] = []

    init(ttl: TimeInterval, capacity: Int) {
        self.ttl = ttl
        self.capacity = capacity
    }

    mutating func value(for key: Key, now: Date) -> Value? {
        guard let e = entries[key] else { return nil }
        guard now.timeIntervalSince(e.stored) < ttl, now >= e.stored.addingTimeInterval(-1) else {
            entries[key] = nil
            order.removeAll { $0 == key }
            return nil
        }
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
        return e.value
    }

    mutating func insert(_ value: Value, for key: Key, now: Date) {
        if entries[key] != nil, let i = order.firstIndex(of: key) { order.remove(at: i) }
        entries[key] = (now, value)
        order.append(key)
        while order.count > capacity {
            let old = order.removeFirst()
            entries[old] = nil
        }
    }

    mutating func removeAll() {
        entries = [:]
        order = []
    }
}
