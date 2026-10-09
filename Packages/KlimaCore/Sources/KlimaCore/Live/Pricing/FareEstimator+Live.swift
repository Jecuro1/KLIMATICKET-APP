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
    /// value of a via route is the one every saved trip gets: one ticket on the summed tariff km, the official A → B price
    /// when the vias lie on the default path (`estimate(route:)`, docs/VIA.md §2).
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
        let offline = estimate(route: [from] + stops + [to], mode: mode, travelClass: travelClass, discount: discount, date: date)
        // A route inside one Kernzone keeps the city single ticket, as for direct trips.
        guard let live, offline.method != .cityTicket, let quote = try? await live.livePrice(request) else { return offline }
        return FareEstimate(fareEUR: quote.amountEUR, distanceKm: quote.distanceKm ?? offline.distanceKm, straightLineKm: offline.straightLineKm,
                            method: FareEstimate.Method(source: quote.source), explanation: quote.explanation, quote: quote)
    }
}
