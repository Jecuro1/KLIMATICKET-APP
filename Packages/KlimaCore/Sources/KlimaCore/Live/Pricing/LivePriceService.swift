import Foundation

/// The regular price of a trip, live (SPEC §B4) – „den richtigen Ticket Preis direkt holen, dass man den nicht händisch
/// eingeben muss“. The valuation basis is the regular single fare on the day of travel (D3): 2nd (or 1st) class,
/// FLEX, one way – the ÖBB Standard-Ticket, or inside one Verkehrsverbund the Verbund single ticket.
///
/// **Order of sources** (§B4.2): cache → VAO Verbund tariff (2nd class, both stations in the same Verbund) → ÖBB shop
/// (plan §B4.3, policy §B4.4) → the most informative error. `quote()` falls back to `offlineQuote()` (relation table
/// → city ticket → distance model) and never throws. Every quote explains its source in German (§B4.5).
///
/// **Limits:** one quote makes at most `maxRequestsPerQuote` (5) requests to the shop and VAO and finishes within
/// `timeBudget` (12 s, else `.timeout`). Tokens never reach the cache. Nothing is sent when both providers are
/// disabled (consent, settings, kill switch).
///
/// **Via stops** (owner request 2026-10-09): the via route is priced as ONE ticket where a back end supports it – VAO
/// with `viaLocL` when all points lie in one Verbund, or the shop connection of the planner journey (exact match, or
/// the same through train that serves the via stops: one Standard-Ticket, break of journey allowed). Otherwise the
/// route is priced as consecutive segments A → V → B and the explanation says „Summe von … Teilstrecken über …“.
public actor LivePriceService: LivePriceProvider {
    /// Total budget of one live quote (SPEC §B6).
    public static let timeBudget: TimeInterval = 12
    /// Worst case of requests to the price back ends per quote (W-B acceptance 4).
    public static let maxRequestsPerQuote = 5
    /// Detour guard: an ÖBB relation price more than 15 % above the table is another (longer) route.
    static let detourFactor = 1.15
    /// Table alternatives are listed when they differ by at least this amount.
    static let alternativeThreshold = 0.05
    /// A planner connection is priced exactly when it departs more than 2 min from now.
    static let connectionLead: TimeInterval = 120
    /// Relation proxy for today: the earliest departure is now + 10 min.
    static let proxyLead: TimeInterval = 600

    static let westbahnSuffix = "WESTbahn-Tarif nicht verfügbar – ÖBB-Standardticket als Vergleich"
    static let proxySuffix = "Preis von heute (gleicher Tarif)"
    static let advanceSuffix = "Vorverkaufspreis (heute gekauft)"

    private var config: LiveConfig
    private let shop: OebbShopClient?
    private let verbund: VerbundTariffClient?
    private let linker: StationLinker?
    private var estimator: FareEstimator
    private var periods: TariffPeriods
    private let stations: StationIndex
    private var cache: PriceCache
    private let clock: @Sendable () -> Date
    private let budgetSleeper: @Sendable (TimeInterval) async throws -> Void
    private var writeScheduled = false
    /// Shop stations found by `stations?name=` (§B3.5 rule 3), by endpoint key; in memory for the app session.
    private var shopStationCache: [String: OebbShopClient.Station] = [:]

    /// `budgetSleeper` races the whole flow against the real-time budget (tests keep the default; the fake-clock
    /// deadline is checked after every request).
    public init(config: LiveConfig, shop: OebbShopClient?, verbund: VerbundTariffClient?, linker: StationLinker?,
                estimator: FareEstimator, stations: StationIndex, cacheURL: URL?,
                clock: @escaping @Sendable () -> Date = { Date() },
                budgetSleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.config = config
        self.shop = shop
        self.verbund = verbund
        self.linker = linker
        self.estimator = estimator
        self.periods = TariffPeriods(estimator: estimator)
        self.stations = stations
        self.cache = PriceCache(fileURL: cacheURL)
        self.clock = clock
        self.budgetSleeper = budgetSleeper
    }

    /// New remote config (kill switch, endpoints); forwarded to the shop and VAO clients. The cache is kept.
    public func update(config: LiveConfig) async {
        self.config = config
        await shop?.update(config: config)
        await verbund?.update(config: config)
    }

    /// After a tariff catalog reload: drops cached `.table` quotes (they were computed with the old catalog).
    public func update(estimator: FareEstimator) {
        self.estimator = estimator
        periods = TariffPeriods(estimator: estimator)
        cache.removeAll { $0.source == .table }
        persistSoon()
    }

    /// Settings „Live-Cache leeren“.
    public func clearCache() {
        cache.removeAll()
        cache.write(now: clock())
    }

    /// Writes pending cache changes now (e.g. when the app moves to the background).
    public func flushCache() {
        cache.write(now: clock())
    }

    // MARK: - Public pricing API

    /// Live only (throws `LiveError`) – conforms to `LivePriceProvider`.
    public func livePrice(_ request: PriceRequest) async throws -> PriceQuote {
        let request = Self.normalized(request)
        guard config.isEnabled(.oebbShop) || config.isEnabled(.vaoTariff) else { throw LiveError.disabled(.oebbShop) }
        let now = clock()
        if let hit = cachedQuote(for: request, now: now) { return hit }
        let budget = PriceRequestBudget(limit: Self.maxRequestsPerQuote, deadline: now.addingTimeInterval(Self.timeBudget), clock: clock)
        return try await withTimeBudget(budget) { [self] in
            try await self.resolve(request, budget: budget)
        }
    }

    /// Live → offline. Never throws. `allowLive: false` = offline chain only (used when Live-Daten is off).
    /// City hops keep the catalog's Kernzone fare (SPEC §B5 open item, same rule as `FareEstimator.estimateLive`).
    public func quote(_ request: PriceRequest, allowLive: Bool = true) async -> PriceQuote {
        let request = Self.normalized(request)
        let offline = offlineQuote(request)
        guard allowLive, offline.source != .cityTicket else { return offline }
        do {
            return try await livePrice(request)
        } catch {
            return offline
        }
    }

    /// Offline chain, no I/O: relation table × fare index (both endpoints app stations) → city ticket → distance
    /// model from the coordinates → a 0 € quote „Kein Preis verfügbar – bitte eintragen“. Via routes between app
    /// stations: one ticket on the summed tariff km, like the trip editor (`FareEstimator.estimate(route:)`,
    /// docs/VIA.md §2 – the ÖBB tariff is degressive, two tickets would overstate it); other via routes: sum of segments.
    public func offlineQuote(_ request: PriceRequest) -> PriceQuote {
        let request = Self.normalized(request)
        guard !request.via.isEmpty else { return offlineDirect(request) }
        let points = ViaPricing.points(request)
        // MARK: via – the same rule as every saved trip.
        let route = points.compactMap(appStation)
        if route.count == points.count {
            let estimate = estimator.estimate(route: route, mode: request.mode, travelClass: request.travelClass,
                                              discount: request.discount, date: request.departure)
            var quote = PriceQuote(estimate: estimate, request: request)
            if let direct = directTableAlternative(request), abs(direct.amountEUR - quote.amountEUR) >= 0.05 {
                quote.alternatives = [direct]
            }
            return quote
        }
        let parts = (0..<(points.count - 1)).map { i in
            offlineDirect(segment(request, from: points[i], to: points[i + 1], index: i))
        }
        // A segment without any price (free text without coordinates): price the direct relation instead.
        guard parts.allSatisfy({ $0.amountEUR > 0 }) else {
            var direct = request
            direct.via = []
            return offlineDirect(direct)
        }
        return ViaPricing.combine(parts, points: points, request: request, direct: directTableAlternative(request))
    }

    // MARK: - Flow

    private func resolve(_ request: PriceRequest, budget: PriceRequestBudget) async throws -> PriceQuote {
        if request.via.isEmpty { return try await resolveDirect(request, budget: budget) }
        return try await resolveVia(request, budget: budget)
    }

    /// §B4.2 steps 3–5 for a relation or connection without via stops.
    private func resolveDirect(_ request: PriceRequest, budget: PriceRequestBudget) async throws -> PriceQuote {
        var errors: [LiveError] = []
        if wantsVerbund(request) {
            do {
                return try await verbundQuote(request, budget: budget)
            } catch let e as LiveError {
                if budget.isExpired { throw e }
                errors.append(e)
            }
        }
        if config.isEnabled(.oebbShop), let shop {
            do {
                return try await shopQuote(request, shop: shop, budget: budget)
            } catch let e as LiveError {
                if budget.isExpired { throw e }
                errors.append(e)
            }
        } else {
            errors.append(.disabled(.oebbShop))
        }
        throw Self.mostInformative(errors) ?? LiveError.disabled(.oebbShop)
    }

    /// Via route: one ticket where supported (VAO `viaLocL`, shop connection), else consecutive segments.
    private func resolveVia(_ request: PriceRequest, budget: PriceRequestBudget) async throws -> PriceQuote {
        var errors: [LiveError] = []
        let points = ViaPricing.points(request)
        if request.travelClass == .second, config.isEnabled(.vaoTariff), verbund != nil {
            let hints = points.map { VerbundArea.hint($0) }
            if let first = hints.first ?? nil, hints.allSatisfy({ $0 == first }) {
                do {
                    return try await verbundQuote(request, budget: budget)
                } catch let e as LiveError {
                    if budget.isExpired { throw e }
                    errors.append(e)
                }
            }
        }
        if let journey = request.journey, config.isEnabled(.oebbShop), let shop,
           case .connection(_, let dep, let tier) = shopPlan(request, now: clock()) {
            do {
                if let q = try await viaConnectionQuote(request, journey: journey, departure: dep, tier: tier, shop: shop, budget: budget) {
                    return q
                }
            } catch let e as LiveError {
                if budget.isExpired { throw e }
                errors.append(e)
            }
        }
        do {
            return try await segmentsQuote(request, points: points, budget: budget)
        } catch let e as LiveError {
            if budget.isExpired { throw e }
            errors.append(e)
        }
        throw Self.mostInformative(errors) ?? LiveError.noPrice("Teilstrecken")
    }

    /// Each segment through the normal chain (cache, VAO, shop), sharing the quote's request and time budget. A segment
    /// that cannot be priced live keeps its offline price (the explanation names each part's source); when no segment
    /// is live the most informative error is thrown. Only all-live results are cached.
    private func segmentsQuote(_ request: PriceRequest, points: [PriceEndpoint], budget: PriceRequestBudget) async throws -> PriceQuote {
        var parts: [PriceQuote] = []
        var errors: [LiveError] = []
        for i in 0..<(points.count - 1) {
            let sub = segment(request, from: points[i], to: points[i + 1], index: i)
            if let hit = cachedQuote(for: sub, now: clock()) {
                parts.append(hit)
                continue
            }
            do {
                parts.append(try await resolveDirect(sub, budget: budget))
            } catch let e as LiveError {
                if budget.isExpired { throw e }
                errors.append(e)
                parts.append(offlineDirect(sub))
            }
        }
        guard errors.count < parts.count else { throw Self.mostInformative(errors) ?? LiveError.noPrice("Teilstrecken") }
        let combined = ViaPricing.combine(parts, points: points, request: request, direct: directTableAlternative(request))
        try budget.checkDeadline()
        if errors.isEmpty { store(combined, for: request) }
        return combined
    }

    // MARK: - VAO (§B5)

    private func wantsVerbund(_ request: PriceRequest) -> Bool {
        request.travelClass == .second && config.isEnabled(.vaoTariff) && verbund != nil
            && VerbundArea.same(VerbundArea.hint(request.from), VerbundArea.hint(request.to))
    }

    /// `.liveVerbund` quote; VAO `NA` is negative-cached for 24 h.
    private func verbundQuote(_ request: PriceRequest, budget: PriceRequestBudget) async throws -> PriceQuote {
        guard let verbund else { throw LiveError.disabled(.vaoTariff) }
        let negKey = PriceCache.negativeKey(.vaoTariff, request)
        if let reason = cache.negative(for: negKey, now: clock()) { throw LiveError.noPrice(reason) }
        let fromLid = try await vaoLid(request.from)
        let toLid = try await vaoLid(request.to)
        var viaLids: [String] = []
        for v in request.via { viaLids.append(try await vaoLid(v)) }
        let fare: VerbundTariffClient.Fare
        do {
            fare = try await verbund.singleFare(fromLid: fromLid, toLid: toLid, via: viaLids, departure: request.departure)
        } catch LiveError.noPrice(let reason) {
            cache.insertNegative(reason, for: negKey, ttl: PriceCache.notAvailableTTL, now: clock())
            persistSoon()
            throw LiveError.noPrice(reason)
        } catch LiveError.hafas(let code, let message) where code == "LOCATION" {
            for e in [request.from, request.to] + request.via { if let id = e.stationID { await linker?.invalidate(stationID: id) } }
            throw LiveError.hafas(code: code, message: message)
        }
        try budget.checkDeadline()
        let now = clock()
        let table = tablePrice(request)
        var explanation = "\(fare.productName) · \(fare.fareSet) · Verkehrsauskunft Österreich"
        if request.discount == .vorteilscard { explanation += " · Verbundtarif · ohne Vorteilscard-Ermäßigung" }
        if !request.via.isEmpty { explanation += " · " + viaText(request) }
        var alternatives: [PriceAlternative] = []
        if let t = table, abs(t.amount - fare.amountEUR) >= Self.alternativeThreshold {
            alternatives.append(PriceAlternative(source: .table, amountEUR: t.amount, label: "Tarif-Tabelle"))
        }
        let quote = PriceQuote(amountEUR: fare.amountEUR, source: .liveVerbund, provider: fare.provider, productName: fare.productName,
                               travelClass: .second, discount: .none, travelDate: request.departure, fetchedAt: now,
                               leadTime: LeadTimeTier.tier(departure: request.departure, now: now), connectionID: nil,
                               shopURL: request.journey?.shopURL ?? deepLink(request, at: request.departure),
                               distanceKm: offlineDistance(request), explanation: explanation, alternatives: alternatives)
        store(quote, for: request)
        return quote
    }

    /// Direct IFOPT-derived lid (`at:`, `wl:`), else the linker (VAO LocMatch, cached 30 days).
    private func vaoLid(_ e: PriceEndpoint) async throws -> String {
        if let id = e.stationID, let lid = StationLinker.directVaoLid(for: id) { return lid }
        if let id = e.stationID, let station = stations.station(id: id), let linker { return try await linker.vaoLid(for: station) }
        throw LiveError.hafas(code: "LOCATION", message: nil)
    }

    // MARK: - Shop (§B3, §B4.3, §B4.4)

    enum ShopPlan: Equatable {
        case connection(Journey, departure: Date, tier: LeadTimeTier)
        case relation(at: Date, tier: LeadTimeTier, proxy: Bool)
        case skip(String)
    }

    /// SPEC §B4.3.
    func shopPlan(_ r: PriceRequest, now: Date) -> ShopPlan {
        if let journey = r.journey, let dep = journey.rideLegs.first?.departure.planned, dep > now.addingTimeInterval(Self.connectionLead) {
            return .connection(journey, departure: dep, tier: LeadTimeTier.tier(departure: dep, now: now))
        }
        let day = PriceCache.day(r.departure), today = PriceCache.day(now)
        if day > today { return .relation(at: r.departure, tier: LeadTimeTier.tier(departure: r.departure, now: now), proxy: false) }
        if day == today || periods.same(day: day, day: today) {
            let at = max(r.departure, now.addingTimeInterval(Self.proxyLead))
            return PriceCache.day(at) == today ? .relation(at: at, tier: .travelDay, proxy: day < today) : .skip("Heute keine Abfahrt mehr")
        }
        return .skip("Anderer Tarifzeitraum")
    }

    private func shopQuote(_ request: PriceRequest, shop: OebbShopClient, budget: PriceRequestBudget) async throws -> PriceQuote {
        let plan = shopPlan(request, now: clock())
        // A failure of one planner connection (e.g. `offerError` shortly before departure) blocks only that train; a
        // relation-level failure blocks the relation for the day.
        let negKey: String
        if case .connection(let journey, _, _) = plan {
            negKey = PriceCache.negativeConnectionKey(journey, travelClass: request.travelClass)
        } else {
            negKey = PriceCache.negativeKey(.oebbShop, request)
        }
        if let reason = cache.negative(for: negKey, now: clock()) { throw LiveError.noPrice(reason) }
        do {
            let quote: PriceQuote
            switch plan {
            case .skip(let reason):
                throw LiveError.noPrice(reason)
            case .connection(let journey, let dep, let tier):
                quote = try await connectionQuote(request, journey: journey, departure: dep, tier: tier, shop: shop, budget: budget)
            case .relation(let at, let tier, let proxy):
                let (from, to) = try await shopStations(request, shop: shop, budget: budget)
                let connections = try await shop.timetable(from: from, to: to, departure: at, discount: request.discount, count: 3)
                quote = try await relationQuote(request, connections: connections, at: at, tier: tier, proxy: proxy, from: from, to: to,
                                                suffixes: [], shop: shop)
            }
            try budget.checkDeadline()
            store(quote, for: request)
            return quote
        } catch LiveError.noPrice(let reason) {
            // Negative-cache what the shop said (offerError, no connection, no Standard fare), not local decisions.
            if case .skip = plan {} else if reason != PriceRequestBudget.exhausted {
                cache.insertNegative(reason, for: negKey, ttl: PriceCache.noPriceTTL, now: clock())
                persistSoon()
            }
            throw LiveError.noPrice(reason)
        }
    }

    /// `.connection`: the shop connection with the same departure and arrival minute (tie-break: train number);
    /// none (e.g. WESTbahn, not sold by ÖBB) → the relation price at that time as comparison.
    private func connectionQuote(_ request: PriceRequest, journey: Journey, departure dep: Date, tier: LeadTimeTier,
                                 shop: OebbShopClient, budget: PriceRequestBudget) async throws -> PriceQuote {
        let (from, to) = try await connectionStations(request, journey: journey, shop: shop, budget: budget)
        let connections = try await shop.timetable(from: from, to: to, departure: dep, discount: request.discount, count: 3)
        if let match = Self.match(connections, journey: journey), let id = match.id {
            let offers = try await shop.offers(connectionID: id, departure: dep, discount: request.discount)
            return try policy(request, fare: try Self.standardFare(offers, request.travelClass), kind: .connection, tier: tier,
                              connectionID: id, at: dep, from: from, to: to, proxy: false, suffixes: [])
        }
        let westbahn = journey.rideLegs.contains { $0.line?.category?.uppercased() == "WB" }
        return try await relationQuote(request, connections: connections, at: dep, tier: tier, proxy: false, from: from, to: to,
                                       suffixes: westbahn ? [Self.westbahnSuffix] : [], shop: shop)
    }

    /// Via + planner journey: the exact shop connection, or the same through train serving the via stops. nil when
    /// the shop has neither (the caller then prices segments).
    private func viaConnectionQuote(_ request: PriceRequest, journey: Journey, departure dep: Date, tier: LeadTimeTier,
                                    shop: OebbShopClient, budget: PriceRequestBudget) async throws -> PriceQuote? {
        let (from, to) = try await connectionStations(request, journey: journey, shop: shop, budget: budget)
        let connections = try await shop.timetable(from: from, to: to, departure: dep, discount: request.discount, count: 3)
        let suffix: String
        let chosen: ShopConnection
        if let exact = Self.match(connections, journey: journey) {
            chosen = exact
            suffix = viaText(request)
        } else if let through = Self.throughMatch(connections, journey: journey, via: request.via) {
            chosen = through
            suffix = viaText(request) + " (durchgehendes Ticket)"
        } else {
            return nil
        }
        guard let id = chosen.id else { return nil }
        let offers = try await shop.offers(connectionID: id, departure: dep, discount: request.discount)
        let quote = try policy(request, fare: try Self.standardFare(offers, request.travelClass), kind: .connection, tier: tier,
                               connectionID: id, at: dep, from: from, to: to, proxy: false, suffixes: [suffix])
        try budget.checkDeadline()
        store(quote, for: request)
        return quote
    }

    /// `.relation`: the fastest of the listed connections (avoids detour variants), then its offers.
    private func relationQuote(_ request: PriceRequest, connections: [ShopConnection], at: Date, tier: LeadTimeTier, proxy: Bool,
                               from: OebbShopClient.Station, to: OebbShopClient.Station, suffixes: [String],
                               shop: OebbShopClient) async throws -> PriceQuote {
        guard let fastest = Self.fastest(connections), let id = fastest.id else { throw LiveError.noPrice("keine buchbare Verbindung") }
        let offers = try await shop.offers(connectionID: id, departure: at, discount: request.discount)
        return try policy(request, fare: try Self.standardFare(offers, request.travelClass), kind: .relation, tier: tier,
                          connectionID: id, at: at, from: from, to: to, proxy: proxy, suffixes: suffixes)
    }

    static func standardFare(_ offers: ShopOffers, _ travelClass: TravelClass) throws -> ShopFare {
        guard let fare = ShopOfferSelector.standardFare(offers, travelClass: travelClass) else {
            throw LiveError.noPrice("kein Standard-Ticket")
        }
        return fare
    }

    enum PlanKind { case relation, connection }

    /// SPEC §B4.4 + §B4.5.
    private func policy(_ request: PriceRequest, fare: ShopFare, kind: PlanKind, tier: LeadTimeTier, connectionID: String, at: Date,
                        from: OebbShopClient.Station, to: OebbShopClient.Station, proxy: Bool, suffixes: [String]) throws -> PriceQuote {
        let now = clock()
        let table = tablePrice(request)
        let time = Self.hhmm(now)
        let classText = request.travelClass == .first ? "1." : "2."
        var discountApplied = request.discount
        var discountNote: String?
        if request.discount == .vorteilscard {
            if fare.reductions.isEmpty {
                discountApplied = .none
                discountNote = "ohne Vorteilscard-Ermäßigung"
            } else {
                discountNote = "mit Vorteilscard"
            }
        }

        var source = PriceSource.liveOebb
        var amount = fare.amountEUR
        var explanation: String
        var alternatives: [PriceAlternative] = []
        if fare.isVerbund {
            // Verbund tickets do not depend on lead time [LIVE VAO past/future equal].
            explanation = "\(fare.productName) · über ÖBB-Ticketshop · abgefragt \(time)"
            if let discountNote { explanation += " · \(discountNote)" }
        } else {
            var live = "Standard-Ticket \(classText) Kl. · ÖBB-Ticketshop · abgefragt \(time)"
            if let discountNote { live += " · \(discountNote)" }
            switch tier {
            case .travelDay:
                if kind == .relation, let t = table, fare.amountEUR > t.amount * Self.detourFactor {
                    source = .table
                    amount = t.amount
                    explanation = t.explanation
                    discountApplied = request.discount
                    alternatives.append(PriceAlternative(source: .liveOebb, amountEUR: fare.amountEUR, label: "ÖBB-Ticketshop (andere Route)"))
                } else {
                    explanation = live
                }
            case .advanceShort, .advanceLong:
                if let t = table {
                    // Valuation basis is the day of travel (D3): the table, with today's advance price as alternative.
                    source = .table
                    amount = t.amount
                    explanation = t.explanation
                    discountApplied = request.discount
                    alternatives.append(PriceAlternative(source: .liveOebb, amountEUR: fare.amountEUR, label: "Vorverkauf heute"))
                } else {
                    explanation = live + " · " + Self.advanceSuffix
                }
            }
        }
        if source.isLive, proxy { explanation += " · " + Self.proxySuffix }
        for s in suffixes { explanation += " · " + s }
        if let t = table, source != .table, abs(t.amount - amount) >= Self.alternativeThreshold {
            alternatives.append(PriceAlternative(source: .table, amountEUR: t.amount, label: "Tarif-Tabelle"))
        }
        return PriceQuote(amountEUR: amount, source: source, provider: fare.owner, productName: source == .table ? "Standard-Ticket" : fare.productName,
                          travelClass: request.travelClass, discount: discountApplied, travelDate: request.departure, fetchedAt: now,
                          leadTime: tier, connectionID: connectionID,
                          shopURL: request.journey?.shopURL ?? ShopDeepLink.url(from: from.number, to: to.number, date: at),
                          distanceKm: offlineDistance(request), explanation: explanation, alternatives: alternatives)
    }

    // MARK: - Shop stations (§B3.5)

    /// Shop stations of the journey's first and last ride leg (planner extIds), else of the request endpoints.
    private func connectionStations(_ request: PriceRequest, journey: Journey, shop: OebbShopClient,
                                    budget: PriceRequestBudget) async throws -> (OebbShopClient.Station, OebbShopClient.Station) {
        let rides = journey.rideLegs
        let from = rides.first.flatMap { OebbShopClient.Station(location: $0.origin) }
        let to = rides.last.flatMap { OebbShopClient.Station(location: $0.destination) }
        if let from, let to {
            try await ensureShopBudget(shop, budget: budget)
            return (from, to)
        }
        let resolved = try await shopStations(request, shop: shop, budget: budget)
        return (from ?? resolved.0, to ?? resolved.1)
    }

    private func shopStations(_ request: PriceRequest, shop: OebbShopClient,
                              budget: PriceRequestBudget) async throws -> (OebbShopClient.Station, OebbShopClient.Station) {
        let from = try await shopStation(request.from, shop: shop)
        let to = try await shopStation(request.to, shop: shop)
        try await ensureShopBudget(shop, budget: budget)
        return (from, to)
    }

    /// Fails early (nothing sent) when the rest of the shop flow (timetable + offers, + token/init when cold) would
    /// exceed the request budget.
    private func ensureShopBudget(_ shop: OebbShopClient, budget: PriceRequestBudget) async throws {
        let needed = (await shop.hasFreshSession ? 0 : 2) + 2
        if budget.remaining < needed { throw LiveError.noPrice(PriceRequestBudget.exhausted) }
    }

    /// 1. planner extId; 2. StationLinker (HAFAS LocMatch, cached); 3. shop `stations?name=` nearest within 1 km.
    private func shopStation(_ e: PriceEndpoint, shop: OebbShopClient) async throws -> OebbShopClient.Station {
        let appStation = e.stationID.flatMap { stations.station(id: $0) }
        let coordinate = e.coordinate ?? appStation?.location
        if let ext = e.hafasExtId?.trimmingCharacters(in: .whitespaces), let n = Int(ext), n > 0 {
            return OebbShopClient.Station(number: n, name: e.name, coordinate: coordinate)
        }
        if let appStation, let linker, let loc = try? await linker.hafasLocation(for: appStation),
           let ext = loc.extId, let n = Int(ext), n > 0 {
            return OebbShopClient.Station(number: n, name: loc.name, coordinate: loc.coordinate ?? coordinate)
        }
        let key = PriceCache.endpointKey(e)
        if let known = shopStationCache[key] { return known }
        let candidates = try await shop.stations(named: appStation?.name ?? e.name).filter { !$0.name.isEmpty }
        var found: OebbShopClient.Station?
        if let coordinate {
            let near = candidates.compactMap { c -> (OebbShopClient.Station, Double)? in
                guard let p = c.coordinate else { return nil }
                let km = coordinate.distanceKm(to: p)
                return km <= 1 ? (c, km) : nil
            }
            found = near.min(by: { $0.1 < $1.1 })?.0
        } else {
            let wanted = StationIndex.normalize(StationLinker.displayName(e.name))
            found = candidates.first { StationIndex.normalize(StationLinker.displayName($0.name)) == wanted }
        }
        guard let found else { throw LiveError.noPrice("Haltestelle im Ticketshop nicht gefunden") }
        shopStationCache[key] = found
        return found
    }

    // MARK: - Matching

    /// Same departure minute and same arrival minute; several → the one sharing a train number with the journey.
    static func match(_ connections: [ShopConnection], journey: Journey) -> ShopConnection? {
        let rides = journey.rideLegs
        guard let dep = rides.first?.departure.planned, let arr = rides.last?.arrival.planned else { return nil }
        let candidates = connections.filter { $0.id != nil && sameMinute($0.departureDate, dep) && sameMinute($0.arrivalDate, arr) }
        guard candidates.count > 1 else { return candidates.first }
        let numbers = Set(rides.compactMap { $0.line?.trainNumber?.nilIfEmpty })
        return candidates.first { $0.trainNumbers.contains(where: numbers.contains) } ?? candidates.first
    }

    /// Via journeys: a shop connection leaving at the same minute on the same first train, whose trains serve every
    /// via stop (the stop is an end or a stopover of a journey ride leg on one of those trains). One through
    /// Standard-Ticket covers that route; a break of journey at the via stop is allowed.
    static func throughMatch(_ connections: [ShopConnection], journey: Journey, via: [PriceEndpoint]) -> ShopConnection? {
        let rides = journey.rideLegs
        guard let first = rides.first, let dep = first.departure.planned, let number = first.line?.trainNumber?.nilIfEmpty else { return nil }
        for c in connections where c.id != nil && sameMinute(c.departureDate, dep) && c.trainNumbers.first == number {
            let shopTrains = Set(c.trainNumbers)
            let servesAll = via.allSatisfy { v in
                rides.contains { leg in (leg.line?.trainNumber).map(shopTrains.contains) == true && serves(leg, v) }
            }
            if servesAll { return c }
        }
        return nil
    }

    /// The leg starts, ends or stops at the endpoint.
    static func serves(_ leg: Leg, _ e: PriceEndpoint) -> Bool {
        same(leg.origin, e) || same(leg.destination, e) || leg.stopovers.contains { !$0.passesWithoutStop && same($0.location, e) }
    }

    /// A location is the endpoint: same extId, else ≤ 300 m apart.
    static func same(_ l: Location, _ e: PriceEndpoint) -> Bool {
        if let a = e.hafasExtId, let b = l.extId, a == b { return true }
        if let p = e.coordinate, let q = l.coordinate { return p.distanceKm(to: q) <= 0.3 }
        return false
    }

    static func fastest(_ connections: [ShopConnection]) -> ShopConnection? {
        connections.filter { $0.id != nil }.enumerated().min { a, b in
            let da = a.element.durationSeconds ?? .infinity, db = b.element.durationSeconds ?? .infinity
            return da != db ? da < db : a.offset < b.offset
        }?.element
    }

    static func sameMinute(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Int((a.timeIntervalSince1970 / 60).rounded(.down)) == Int((b.timeIntervalSince1970 / 60).rounded(.down))
    }

    // MARK: - Offline helpers

    private func appStation(_ e: PriceEndpoint) -> Station? {
        if let id = e.stationID, let s = stations.station(id: id) { return s }
        if let ext = e.hafasExtId?.nilIfEmpty { return stations.station(id: "uic:\(ext)") }
        return nil
    }

    /// The offline table price T for the same request (relation × fare index, class and discount applied), or nil.
    private func tablePrice(_ request: PriceRequest) -> (amount: Double, explanation: String)? {
        guard let a = appStation(request.from), let b = appStation(request.to) else { return nil }
        let e = estimator.estimate(from: a, to: b, mode: request.mode, travelClass: request.travelClass, discount: request.discount,
                                   date: request.departure)
        return e.method == .officialTable ? (Self.cents(e.fareEUR), e.explanation) : nil
    }

    private func directTableAlternative(_ request: PriceRequest) -> PriceAlternative? {
        tablePrice(request).map { PriceAlternative(source: .table, amountEUR: $0.amount, label: "Direkt ohne Zwischenhalt (Tarif-Tabelle)") }
    }

    private func offlineDistance(_ request: PriceRequest) -> Double? {
        let e = offlineEstimate(request)
        return e.map { $0.distanceKm > 0 ? $0.distanceKm : nil } ?? nil
    }

    private func offlineEstimate(_ request: PriceRequest) -> FareEstimate? {
        if let a = appStation(request.from), let b = appStation(request.to) {
            return estimator.estimate(from: a, to: b, mode: request.mode, travelClass: request.travelClass, discount: request.discount,
                                      date: request.departure)
        }
        let pa = request.from.coordinate ?? appStation(request.from)?.location
        let pb = request.to.coordinate ?? appStation(request.to)?.location
        guard let pa, let pb else { return nil }
        return estimator.estimate(from: pa, to: pb, mode: request.mode, travelClass: request.travelClass, discount: request.discount,
                                  date: request.departure)
    }

    private func offlineDirect(_ request: PriceRequest) -> PriceQuote {
        if let e = offlineEstimate(request), e.fareEUR > 0 { return PriceQuote(estimate: e, request: request) }
        return PriceQuote(amountEUR: 0, source: .distanceModel, travelClass: request.travelClass, discount: request.discount,
                          travelDate: request.departure, explanation: "Kein Preis verfügbar – bitte eintragen")
    }

    /// Segment `index` of a via request: no via, no journey; departure = the journey's departure from that point when
    /// known, else the request's.
    private func segment(_ request: PriceRequest, from: PriceEndpoint, to: PriceEndpoint, index: Int) -> PriceRequest {
        var departure = request.departure
        if index > 0, let journey = request.journey, let leg = journey.rideLegs.first(where: { Self.same($0.origin, from) }),
           let planned = leg.departure.planned {
            departure = planned
        }
        return PriceRequest(from: from, to: to, departure: departure, mode: request.mode, travelClass: request.travelClass,
                            discount: request.discount)
    }

    private func viaText(_ request: PriceRequest) -> String {
        "über " + request.via.map(ViaPricing.name).joined(separator: ", ")
    }

    private func deepLink(_ request: PriceRequest, at: Date) -> URL? {
        guard let a = request.from.hafasExtId, let b = request.to.hafasExtId else { return nil }
        return ShopDeepLink.url(from: a, to: b, date: at)
    }

    // MARK: - Cache

    private func cachedQuote(for request: PriceRequest, now: Date) -> PriceQuote? {
        if let journey = request.journey {
            if let q = cache.quote(for: PriceCache.connectionKey(journey, travelClass: request.travelClass, discount: request.discount,
                                                                 via: request.via), now: now) {
                return q
            }
            if let q = cache.quote(for: PriceCache.relationKey(request), now: now), q.source == .liveVerbund { return q }
            return nil
        }
        return cache.quote(for: PriceCache.relationKey(request), now: now)
    }

    /// Connection requests under `con|…`; relation requests and (relation-level) Verbund prices under `rel|…`.
    private func store(_ quote: PriceQuote, for request: PriceRequest) {
        let now = clock()
        if let journey = request.journey {
            cache.insert(quote, for: PriceCache.connectionKey(journey, travelClass: request.travelClass, discount: request.discount,
                                                              via: request.via), now: now)
        }
        if request.journey == nil || quote.source == .liveVerbund {
            cache.insert(quote, for: PriceCache.relationKey(request), now: now)
        }
        persistSoon()
    }

    /// Write-behind, at most one write per `PriceCache.writeInterval`.
    private func persistSoon() {
        let now = clock()
        if cache.shouldWrite(now: now) {
            cache.write(now: now)
            return
        }
        guard cache.fileURL != nil, cache.isDirty, !writeScheduled else { return }
        writeScheduled = true
        let delay = cache.writeDelay(now: now)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, delay) * 1e9))
            await self?.writeIfDue()
        }
    }

    private func writeIfDue() {
        writeScheduled = false
        cache.write(now: clock())
    }

    // MARK: - Helpers

    /// At most `JourneyQuery.maxViaStops` via stops; vias equal to an end or to each other are dropped.
    static func normalized(_ r: PriceRequest) -> PriceRequest {
        guard !r.via.isEmpty else { return r }
        var out = r
        var seen: Set<String> = [PriceCache.endpointKey(r.from), PriceCache.endpointKey(r.to)]
        out.via = r.via.filter { seen.insert(PriceCache.endpointKey($0)).inserted }
        out.via = Array(out.via.prefix(JourneyQuery.maxViaStops))
        return out
    }

    /// `.blocked` > `.rateLimited` > `.noPrice` > `.offline` > others (SPEC §B4.2 step 5).
    static func mostInformative(_ errors: [LiveError]) -> LiveError? {
        func rank(_ e: LiveError) -> Int {
            switch e {
            case .blocked: return 0
            case .rateLimited: return 1
            case .noPrice: return 2
            case .offline: return 3
            default: return 4
            }
        }
        return errors.enumerated().min { a, b in
            rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
        }?.element
    }

    /// EUR rounded to cents (removes binary noise such as 34.300000000000004).
    static func cents(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// "12:15" (Vienna).
    static func hhmm(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Races `body` against the real-time budget; the task-local budget is visible to the clients.
    private func withTimeBudget(_ budget: PriceRequestBudget,
                                _ body: @escaping @Sendable () async throws -> PriceQuote) async throws -> PriceQuote {
        let sleeper = budgetSleeper
        let seconds = Self.timeBudget
        return try await PriceRequestBudget.$current.withValue(budget) {
            try await withThrowingTaskGroup(of: PriceQuote?.self) { group in
                group.addTask { try await body() }
                group.addTask {
                    try await sleeper(seconds)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw LiveError.timeout }
                guard let quote = first else {
                    budget.markExpired()
                    throw LiveError.timeout
                }
                return quote
            }
        }
    }
}
