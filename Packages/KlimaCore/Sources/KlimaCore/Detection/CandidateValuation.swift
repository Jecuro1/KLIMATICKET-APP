import Foundation

/// The numbers of a ride that is confirmed from the inbox. It is the SAME computation the trip editor does for a hand
/// entered ride (`FareEstimator.estimate(from:via:to:…)` with the person's default class and discount at the ride's
/// date, the federal states of the stops, the price source of the method) – so Statistik, Jahresrückblick and widgets see
/// no difference between a detected and a typed ride. The recorded or detected path length never enters: the editor
/// does not know it either.
public struct CandidateTripFacts: Hashable, Sendable {
    public var fareEUR: Double
    public var distanceKm: Double
    /// Federal state codes of all stops, sorted (the editor saves them the same way).
    public var states: [String]
    public var priceSource: PriceSource
    public var explanation: String
    public var method: FareEstimate.Method
}

public enum CandidateValuation {
    public static func facts(from: Station, to: Station, via: [Station] = [], mode: TransportMode, date: Date,
                             estimator: FareEstimator, travelClass: TravelClass = .second,
                             discount: FareDiscount = .none) -> CandidateTripFacts {
        let estimate = estimator.estimate(from: from, via: via, to: to, mode: mode, travelClass: travelClass, discount: discount, date: date)
        let source: PriceSource
        switch estimate.method {
        case .officialTable: source = .table
        case .cityTicket: source = .cityTicket
        case .liveOebb: source = .liveOebb
        case .liveVerbund: source = .liveVerbund
        case .manual: source = .manual
        case .distanceTariff: source = .distanceModel
        }
        let stops = [from, to] + via
        return CandidateTripFacts(fareEUR: estimate.fareEUR, distanceKm: estimate.distanceKm, states: Array(Set(stops.map(\.state))).sorted(),
                                  priceSource: source, explanation: estimate.explanation, method: estimate.method)
    }
}
