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
        let method: FareEstimate.Method = switch quote.source {
        case .liveOebb: .liveOebb
        case .liveVerbund: .liveVerbund
        case .table: .officialTable
        case .cityTicket: .cityTicket
        case .distanceModel: .distanceTariff
        case .manual: .manual
        }
        return FareEstimate(fareEUR: quote.amountEUR, distanceKm: offline.distanceKm, straightLineKm: offline.straightLineKm,
                            method: method, cityName: offline.cityName, explanation: quote.explanation, quote: quote)
    }
}
