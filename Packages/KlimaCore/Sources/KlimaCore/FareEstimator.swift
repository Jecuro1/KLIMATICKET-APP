import Foundation

public struct FareEstimate: Hashable, Sendable {
    public enum Method: String, Sendable {
        case distanceTariff
        case cityTicket
        case manual
    }

    public var fareEUR: Double
    /// Estimated travelled distance (one direction), km.
    public var distanceKm: Double
    public var straightLineKm: Double
    public var method: Method
    public var cityName: String?
    /// Short German explanation shown under the price ("≈ 128 km Bahnstrecke · ÖBB-Standardticket 2. Kl.").
    public var explanation: String

    public init(fareEUR: Double, distanceKm: Double, straightLineKm: Double, method: Method, cityName: String? = nil, explanation: String) {
        self.fareEUR = fareEUR
        self.distanceKm = distanceKm
        self.straightLineKm = straightLineKm
        self.method = method
        self.cityName = cityName
        self.explanation = explanation
    }
}

/// Estimates what a trip would have cost with regular tickets.
public struct FareEstimator: Sendable {
    public var catalog: TariffCatalog

    public init(catalog: TariffCatalog) {
        self.catalog = catalog
    }

    public func estimate(from: GeoPoint, to: GeoPoint, mode: TransportMode,
                         travelClass: TravelClass = .second, discount: FareDiscount = .none) -> FareEstimate {
        let straight = from.distanceKm(to: to)
        let model = catalog.fareModel

        // Same city & short hop (or an urban mode) → city single ticket.
        if let city = catalog.cityFares.first(where: { $0.contains(from) && $0.contains(to) }),
           mode.isUrban || mode == .bus || straight <= city.radiusKm {
            let km = model.railDistance(fromStraightLineKm: straight)
            return FareEstimate(
                fareEUR: city.singleTicketEUR,
                distanceKm: rounded1(km),
                straightLineKm: rounded1(straight),
                method: .cityTicket,
                cityName: city.name,
                explanation: "Einzelfahrt \(city.name) · \(FareEstimator.euro(city.singleTicketEUR))"
            )
        }

        let km = model.railDistance(fromStraightLineKm: straight)
        let fare = model.fare(railKm: km, travelClass: travelClass, discount: discount)
        var parts = ["≈ \(Int(km.rounded())) km", "Standardticket \(travelClass == .first ? "1." : "2.") Kl."]
        if discount == .vorteilscard { parts.append("mit Vorteilscard") }
        return FareEstimate(
            fareEUR: fare,
            distanceKm: rounded1(km),
            straightLineKm: rounded1(straight),
            method: .distanceTariff,
            explanation: parts.joined(separator: " · ")
        )
    }

    public func estimate(from: Station, to: Station, mode: TransportMode,
                         travelClass: TravelClass = .second, discount: FareDiscount = .none) -> FareEstimate {
        estimate(from: from.location, to: to.location, mode: mode, travelClass: travelClass, discount: discount)
    }

    private func rounded1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    /// Minimal, locale-independent euro formatting for explanations ("€ 3,20").
    public static func euro(_ value: Double) -> String {
        let cents = Int((value * 100).rounded())
        let euros = cents / 100
        let rest = abs(cents % 100)
        return "€ \(euros),\(rest < 10 ? "0" : "")\(rest)"
    }
}
