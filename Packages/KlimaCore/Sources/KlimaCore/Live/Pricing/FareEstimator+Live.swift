import Foundation

// CONTRACT signature (Step 0) – implementation owned by WP-B. Additive: the synchronous `estimate(...)` APIs are unchanged.
extension FareEstimator {
    /// Live-first estimate: live provider (shop / VAO) → offline chain (relation table → city ticket → distance model).
    /// Never throws; returns the offline estimate when `live` is nil, disabled, offline or fails.
    public func estimateLive(from: Station, to: Station, mode: TransportMode, travelClass: TravelClass = .second,
                             discount: FareDiscount = .none, date: Date = Date(), journey: Journey? = nil,
                             live: (any LivePriceProvider)?) async -> FareEstimate {
        let offline = estimate(from: from, to: to, mode: mode, travelClass: travelClass, discount: discount, date: date)
        guard let live, offline.method != .cityTicket else { return offline }
        let request = PriceRequest(from: PriceEndpoint(station: from), to: PriceEndpoint(station: to), departure: date, mode: mode,
                                   travelClass: travelClass, discount: discount, journey: journey)
        guard let quote = try? await live.livePrice(request) else { return offline }
        return FareEstimate(fareEUR: quote.amountEUR, distanceKm: offline.distanceKm, straightLineKm: offline.straightLineKm,
                            method: FareEstimate.Method(source: quote.source), cityName: offline.cityName, explanation: quote.explanation,
                            quote: quote)
    }

    /// Same with via stops (owner request 2026-10-09). Without via stops this is `estimateLive(from:to:…)`. The offline
    /// value of a via route is the sum of its segments (each: table → city ticket → distance model); distances add up.
    public func estimateLive(from: Station, to: Station, via: [Station], mode: TransportMode, travelClass: TravelClass = .second,
                             discount: FareDiscount = .none, date: Date = Date(), journey: Journey? = nil,
                             live: (any LivePriceProvider)?) async -> FareEstimate {
        let stops = Array(via.filter { $0.id != from.id && $0.id != to.id }.prefix(JourneyQuery.maxViaStops))
        guard !stops.isEmpty else {
            return await estimateLive(from: from, to: to, mode: mode, travelClass: travelClass, discount: discount, date: date,
                                      journey: journey, live: live)
        }
        let request = PriceRequest(from: PriceEndpoint(station: from), to: PriceEndpoint(station: to), departure: date, mode: mode,
                                   travelClass: travelClass, discount: discount, journey: journey, via: stops.map(PriceEndpoint.init(station:)))
        let offline = estimate(through: [from] + stops + [to], request: request)
        guard let live, let quote = try? await live.livePrice(request) else { return offline }
        return FareEstimate(fareEUR: quote.amountEUR, distanceKm: quote.distanceKm ?? offline.distanceKm, straightLineKm: offline.straightLineKm,
                            method: FareEstimate.Method(source: quote.source), explanation: quote.explanation, quote: quote)
    }

    /// Offline estimate of consecutive segments (sum), with the via explanation of `ViaPricing.combine`.
    func estimate(through stations: [Station], request: PriceRequest) -> FareEstimate {
        var estimates: [FareEstimate] = []
        for i in 0..<(stations.count - 1) {
            estimates.append(estimate(from: stations[i], to: stations[i + 1], mode: request.mode, travelClass: request.travelClass,
                                      discount: request.discount, date: request.departure))
        }
        let quote = ViaPricing.combine(estimates.map { PriceQuote(estimate: $0, request: request) },
                                       points: stations.map(PriceEndpoint.init(station:)), request: request)
        let km = estimates.reduce(0) { $0 + $1.distanceKm }
        let straight = estimates.reduce(0) { $0 + $1.straightLineKm }
        return FareEstimate(fareEUR: quote.amountEUR, distanceKm: (km * 10).rounded() / 10, straightLineKm: (straight * 10).rounded() / 10,
                            method: FareEstimate.Method(source: quote.source), explanation: quote.explanation)
    }
}
