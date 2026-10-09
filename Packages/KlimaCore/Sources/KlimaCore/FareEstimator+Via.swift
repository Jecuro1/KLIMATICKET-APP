import Foundation

// Fares and distances of routes with via stops ("Über Feldkirch") – the rule is documented in docs/VIA.md §2.
//
// ÖBB's distance tariff is degressive: one ticket A → B over the route through V costs the price of the whole route's
// tariff kilometres, never the sum of two tickets A → V and V → B. So the legs' kilometres are summed and priced once:
//   • a leg's tariff km come from its official relation price (inverted on the fitted price curve) when the table has it,
//     else from the straight line × detour factor, as for any estimate;
//   • the official A → B price stays when every via lies on the default path – the legs then add up to the direct
//     relation's tariff km (± the table's resolution) – because that route is what the official price covers;
//   • a via never makes the trip cheaper than the direct ticket;
//   • city / Kernzone single tickets include changes: one ticket when the whole route stays inside one Kernzone.
// The travelled distance (CO₂, km statistics) is the sum of the legs' rail-km estimates, never below the direct one.

public extension FareModel {
    /// Rail km at which the full 2nd-class fare reaches `price` – the inverse of `fullFare` on its rising part. Nil at the
    /// flat ends (minimum fare of short hops, the maximum fare), where any distance would fit, and for invalid prices.
    func railKm(forFullFare price: Double) -> Double? {
        guard price.isFinite, price > 0 else { return nil }
        let floor = fullFare(railKm: 0.1)
        guard price > floor + max(roundingStep, 0.05), price < maximumFare - max(roundingStep, 0.05) else { return nil }
        var lo = 0.1, hi = 3000.0
        guard fullFare(railKm: hi) >= price else { return nil }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if fullFare(railKm: mid) < price { lo = mid } else { hi = mid }
        }
        let km = (lo + hi) / 2
        // Ill-conditioned where the curve is (almost) flat: 10 cents of table rounding would move the km too far.
        let slope = (fullFare(railKm: km + 5) - fullFare(railKm: max(km - 5, 0.1))) / (km + 5 - max(km - 5, 0.1))
        return slope >= 0.03 ? km : nil
    }
}

public extension FareEstimator {
    /// The legs' tariff km may exceed the direct relation's by this much and the via still counts as "on the way":
    /// relative share + absolute km (the relation table is rounded to 10 cents, the price curve fits it to a few %).
    static let viaOnPathTolerance = (relative: 0.06, absoluteKm: 3.0)

    /// Estimate for start → vias → destination (vias in travel order; `estimate(from:to:…)` when there are none).
    /// Vias equal to a neighbouring stop are ignored.
    func estimate(from: Station, via: [Station], to: Station, mode: TransportMode, travelClass: TravelClass = .second,
                  discount: FareDiscount = .none, date: Date = Date()) -> FareEstimate {
        var stops: [Station] = [from]
        for station in via.prefix(TripVia.maxCount) where station.id != stops.last?.id && station.id != to.id {
            stops.append(station)
        }
        stops.append(to)
        return estimate(route: stops, mode: mode, travelClass: travelClass, discount: discount, date: date)
    }

    /// Estimate along `stops` (start, vias …, destination). See the rule at the top of this file.
    func estimate(route stops: [Station], mode: TransportMode, travelClass: TravelClass = .second,
                  discount: FareDiscount = .none, date: Date = Date()) -> FareEstimate {
        guard let a = stops.first, let b = stops.last else { preconditionFailure("a route needs a start and a destination") }
        let direct = estimate(from: a, to: b, mode: mode, travelClass: travelClass, discount: discount, date: date)
        guard stops.count > 2 else { return direct }
        let vias = Array(stops[1..<(stops.count - 1)])
        let label = "über " + FareEstimator.viaList(vias.map(\.name))
        let model = catalog.fareModel
        let legs = zip(stops, stops.dropFirst()).map { ($0, $1) }
        let legStraight = legs.map { $0.0.location.distanceKm(to: $0.1.location) }
        let legRailKm = legStraight.map { model.railDistance(fromStraightLineKm: $0) }
        let distance = viaRounded1(max(direct.distanceKm, legRailKm.reduce(0, +)))

        // One Kernzone holds the whole route: one single ticket (changes included).
        if let city = catalog.cityFares.first(where: { zone in stops.allSatisfy { zone.contains($0.location) } }),
           mode.isUrban || mode == .bus || legStraight.allSatisfy({ $0 <= city.radiusKm }) {
            return FareEstimate(fareEUR: city.singleTicketEUR, distanceKm: distance, straightLineKm: direct.straightLineKm,
                                method: .cityTicket, cityName: city.name,
                                explanation: "\(label) · Einzelfahrt \(city.name) · \(FareEstimator.euro(city.singleTicketEUR))")
        }

        // Tariff km per leg: official relation where the table has it (not for U-Bahn/Bim, as for direct trips).
        let usesTable = mode != .metro && mode != .tram
        let officialLegKm: [Double?] = legs.map { leg in
            guard usesTable, let price = relations.price(from: leg.0.id, to: leg.1.id) else { return nil }
            return model.railKm(forFullFare: price)
        }
        let tariffKm = zip(officialLegKm, legRailKm).map { $0 ?? $1 }.reduce(0, +)
        let classText = "\(travelClass == .first ? "1." : "2.") Kl."
        let discountText = discount == .vorteilscard ? " · mit Vorteilscard" : ""

        // Every via on the default path → the official A → B price covers this route.
        if direct.method == .officialTable, officialLegKm.allSatisfy({ $0 != nil }),
           let directPrice = relations.price(from: a.id, to: b.id), let directKm = model.railKm(forFullFare: directPrice),
           tariffKm <= directKm * (1 + Self.viaOnPathTolerance.relative) + Self.viaOnPathTolerance.absoluteKm {
            return FareEstimate(fareEUR: direct.fareEUR, distanceKm: distance, straightLineKm: direct.straightLineKm,
                                method: .officialTable,
                                explanation: "\(label) (am Weg) · ÖBB-Standardticket \(classText) · Tarif ab "
                                    + "\(FareEstimator.shortDate(relations.validFrom))\(discountText)")
        }

        // Otherwise: the whole route's tariff km, priced once – never below the direct ticket.
        let priced = model.round(model.fare(railKm: tariffKm, travelClass: travelClass, discount: discount) * catalog.fareFactor(on: date))
        return FareEstimate(fareEUR: max(priced, direct.fareEUR), distanceKm: distance, straightLineKm: direct.straightLineKm,
                            method: .distanceTariff,
                            explanation: "\(label) · geschätzt nach Tarif-km · \(classText)\(discountText)")
    }

    /// "Feldkirch", "Feldkirch und Bludenz", "A, B und C".
    static func viaList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " und " + names[names.count - 1]
        }
    }

    private func viaRounded1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}
