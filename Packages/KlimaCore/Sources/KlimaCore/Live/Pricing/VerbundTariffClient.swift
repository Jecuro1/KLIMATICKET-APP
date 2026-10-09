import Foundation

/// Verbund single-ticket prices from the VAO HAFAS (Verkehrsauskunft Österreich, `anachb.vor.at/hamm/gate`,
/// SPEC §B5). `trfRes.totalPrice` of a TripSearch with `getTariff` is the adult 2nd-class Verbund single ticket for
/// trips inside ONE Verbund; across Verbund borders VAO answers `statusCode: "NA"`.
///
/// Uses WP-A's envelope encoder (`HafasEnvelope`, `config.vao` profile) but NOT the ÖBB product bit table: VAO bitmasks
/// differ. Pipeline as the other clients: kill switch / toggle → `health.check` → per-quote budget → throttle (≥ 1 s,
/// ≤ 20 per minute) → transport → `health.record…`; one retry for timeouts, network errors and 502/503/504.
public actor VerbundTariffClient: VaoLocationSearching {
    static let retryDelay: TimeInterval = 1.5

    public struct Fare: Sendable, Hashable {
        public var amountEUR: Double
        /// First token of the fare set name: VVT, VOR, OÖVV, VKG, VVV, SVV, STV.
        public var provider: String
        /// Trimmed fare name, prefixed with the provider unless it already contains it ("VVT Einzelticket",
        /// "Einzelfahrt VOR + Wien Kernzone").
        public var productName: String
        /// Fare set ("VVT 14 Zonen", "OÖVV 5 Zonen", "VVV MAXIMO").
        public var fareSet: String

        public init(amountEUR: Double, provider: String, productName: String, fareSet: String) {
            self.amountEUR = amountEUR
            self.provider = provider
            self.productName = productName
            self.fareSet = fareSet
        }
    }

    private var config: LiveConfig
    private let transport: any HTTPTransport
    private let throttle: RequestThrottle
    private let health: LiveHealth
    private let appVersion: String
    private let sleeper: @Sendable (TimeInterval) async throws -> Void
    /// Requests sent since creation (tests, diagnostics).
    private(set) var requestCount = 0

    public init(config: LiveConfig, transport: any HTTPTransport, throttle: RequestThrottle, health: LiveHealth,
                appVersion: String? = nil,
                sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.config = config
        self.transport = transport
        self.throttle = throttle
        self.health = health
        self.appVersion = appVersion ?? OebbShopClient.bundleVersion
        self.sleeper = sleeper
    }

    public func update(config: LiveConfig) {
        self.config = config
    }

    // MARK: - API

    /// Adult 2nd-class Verbund single ticket between two VAO lids (`A=1@L=<IFOPT-derived>@`). `.noPrice("NA")` when
    /// no connection is priced (Verbund border); `.hafas(code: "LOCATION")` for an unknown lid (e.g. an ÖBB EVA lid).
    public func singleFare(fromLid: String, toLid: String, departure: Date) async throws -> Fare {
        try await singleFare(fromLid: fromLid, toLid: toLid, via: [], departure: departure)
    }

    /// Same with via stops (HAFAS `viaLocL`, at most `JourneyQuery.maxViaStops`): the Verbund price of the via route.
    public func singleFare(fromLid: String, toLid: String, via viaLids: [String], departure: Date) async throws -> Fare {
        let via = viaLids.prefix(JourneyQuery.maxViaStops).map { VaoVia(loc: HafasLocationRef(lid: $0)) }
        let req = VaoTripSearch(
            depLocL: [HafasLocationRef(lid: fromLid)], arrLocL: [HafasLocationRef(lid: toLid)], viaLocL: via.isEmpty ? nil : Array(via),
            outDate: HafasTime.dateString(departure), outTime: HafasTime.timeString(departure), outFrwd: true, numF: 2,
            getPasslist: false, getPolyline: false, getTariff: true,
            trfReq: TariffRequest(jnyCl: 2, tvlrProf: [TravellerProfile(type: "E")], cType: "PK"))
        let data = try await send([HafasServiceRequest(meth: "TripSearch", req: req)])
        if let e = HafasCodec.serviceError(data, serviceIndex: 0, provider: .vaoTariff) { throw e }
        return try Self.fare(from: data)
    }

    /// VAO LocMatch (stations), for `StationLinker.vaoLid(for:)`. VAO lids embed the IFOPT id (`…@i=A×at:44:42505@`).
    public func vaoLocations(_ query: String) async throws -> [Location] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let req = HafasRequests.LocMatch(input: .init(loc: .init(type: "S", name: q), maxLoc: 5, field: "S"))
        let data = try await send([HafasServiceRequest(meth: "LocMatch", req: req)])
        if let e = HafasCodec.serviceError(data, serviceIndex: 0, provider: .vaoTariff) { throw e }
        return try HafasCodec.locations(from: data, query: q)
    }

    // MARK: - Request bodies (SPEC §B5.1, exact key set of FX/vao/*)

    struct VaoVia: Encodable { var loc: HafasLocationRef }
    struct TravellerProfile: Encodable { var type: String }
    struct TariffRequest: Encodable {
        var jnyCl: Int
        var tvlrProf: [TravellerProfile]
        var cType: String
    }

    struct VaoTripSearch: Encodable {
        var depLocL: [HafasLocationRef]
        var arrLocL: [HafasLocationRef]
        var viaLocL: [VaoVia]?
        var outDate: String
        var outTime: String
        var outFrwd: Bool
        var numF: Int
        var getPasslist: Bool
        var getPolyline: Bool
        var getTariff: Bool
        var trfReq: TariffRequest
    }

    // MARK: - Response → fare (SPEC §B5.2)

    struct RawPrice: Decodable {
        var amount: Int?

        private enum CodingKeys: String, CodingKey { case amount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            amount = c.softInt(.amount)
        }
    }

    struct RawFare: Decodable {
        var name: String?
        var price: RawPrice?

        private enum CodingKeys: String, CodingKey { case name, price }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.soft(String.self, .name)
            price = c.soft(RawPrice.self, .price)
        }
    }

    struct RawFareSet: Decodable {
        var name: String?
        var fareL: [RawFare]?

        private enum CodingKeys: String, CodingKey { case name, fareL }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.soft(String.self, .name)
            fareL = c.softList(RawFare.self, .fareL)
        }
    }

    struct RawTariff: Decodable {
        var statusCode: String?
        var totalPrice: RawPrice?
        var fareSetL: [RawFareSet]?

        private enum CodingKeys: String, CodingKey { case statusCode, totalPrice, fareSetL }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            statusCode = c.soft(String.self, .statusCode)
            totalPrice = c.soft(RawPrice.self, .totalPrice)
            fareSetL = c.softList(RawFareSet.self, .fareSetL)
        }
    }

    struct RawConnection: Decodable {
        var trfRes: RawTariff?

        private enum CodingKeys: String, CodingKey { case trfRes }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            trfRes = c.soft(RawTariff.self, .trfRes)
        }
    }

    struct RawRes: Decodable {
        var outConL: [RawConnection]?

        private enum CodingKeys: String, CodingKey { case outConL }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            outConL = c.softList(RawConnection.self, .outConL)
        }
    }

    struct RawService: Decodable {
        var res: RawRes?

        private enum CodingKeys: String, CodingKey { case res }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            res = c.soft(RawRes.self, .res)
        }
    }

    struct RawResponse: Decodable {
        var svcResL: [RawService]?

        private enum CodingKeys: String, CodingKey { case svcResL }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            svcResL = c.softList(RawService.self, .svcResL)
        }
    }

    /// First connection with `statusCode == "OK"`: total price in cents; the fare is the first `fareSetL[].fareL[]`
    /// entry with the same amount (all connections of a relation have the same price [LIVE]). None → `.noPrice("NA")`.
    static func fare(from data: Data) throws -> Fare {
        let raw: RawResponse
        do {
            raw = try JSONDecoder().decode(RawResponse.self, from: data)
        } catch {
            throw LiveError.decoding("VAO-Antwort unerwartet")
        }
        let connections = raw.svcResL?.first?.res?.outConL ?? []
        for c in connections {
            guard let trf = c.trfRes, trf.statusCode?.uppercased() == "OK", let cents = trf.totalPrice?.amount, cents > 0 else { continue }
            var fareName: String?
            var setName: String?
            search: for set in trf.fareSetL ?? [] {
                for f in set.fareL ?? [] where f.price?.amount == cents {
                    fareName = f.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    setName = set.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    break search
                }
            }
            let fareSet = setName ?? trf.fareSetL?.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Verbundtarif"
            let provider = fareSet.split(separator: " ").first.map(String.init) ?? fareSet
            let name = fareName ?? "Einzelticket"
            let product = name.localizedCaseInsensitiveContains(provider) ? name : "\(provider) \(name)"
            return Fare(amountEUR: Double(cents) / 100, provider: provider, productName: product, fareSet: fareSet)
        }
        throw LiveError.noPrice("NA")
    }

    // MARK: - Transport pipeline

    private func ensureEnabled() throws {
        guard config.isEnabled(.vaoTariff) else { throw LiveError.disabled(.vaoTariff) }
    }

    var userAgent: String { config.userAgent.replacingOccurrences(of: "{version}", with: appVersion) }

    /// One envelope; returns the body of an envelope-OK response (service errors are left to the caller).
    private func send<R: Encodable>(_ svcReqL: [HafasServiceRequest<R>]) async throws -> Data {
        try ensureEnabled()
        let profile = config.vao
        try await health.check(.vaoTariff)
        let body: Data
        do {
            body = try JSONEncoder().encode(HafasEnvelope(profile: profile, svcReqL: svcReqL))
        } catch {
            throw LiveError.decoding("Anfrage nicht kodierbar: \(error)")
        }
        let request = HTTPRequest(method: "POST", url: profile.url, headers: [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": userAgent,
        ], body: body, timeout: profile.timeout)
        let budget = RequestThrottle.budget(for: .vaoTariff)
        var attempt = 0
        while true {
            try PriceRequestBudget.spend(.vaoTariff)
            try await throttle.acquire(.vaoTariff, minInterval: max(profile.minInterval, budget.minInterval), perMinute: budget.perMinute)
            requestCount += 1
            let data: Data
            do {
                data = try Self.classify(try await transport.send(request))
            } catch let error as LiveError {
                if attempt == 0, OebbShopClient.isRetryable(error) {
                    attempt += 1
                    try await sleeper(Self.retryDelay)
                    continue
                }
                await health.recordFailure(.vaoTariff, error)
                throw error
            }
            // Envelope errors: AUTH → .blocked (circuit 30 min), PARSE/HAMM → .decoding; never retried.
            if let e = HafasCodec.envelopeError(data, provider: .vaoTariff) {
                await health.recordFailure(.vaoTariff, e)
                throw e
            }
            await health.recordSuccess(.vaoTariff)
            return data
        }
    }

    /// 429 → `.rateLimited`; HTML 403 → `.blocked`; status ≠ 200 or non-JSON → `.http`.
    static func classify(_ r: HTTPResponse) throws -> Data {
        let looksJSON = r.body.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }) == UInt8(ascii: "{")
        if r.status == 429 {
            throw LiveError.rateLimited(.vaoTariff, retryAfter: r.headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        }
        if r.status == 403, !looksJSON { throw LiveError.blocked(.vaoTariff) }
        guard r.status == 200, looksJSON else {
            let excerpt = String(decoding: r.body.prefix(160), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
            throw LiveError.http(status: r.status, excerpt: excerpt)
        }
        return r.body
    }
}
