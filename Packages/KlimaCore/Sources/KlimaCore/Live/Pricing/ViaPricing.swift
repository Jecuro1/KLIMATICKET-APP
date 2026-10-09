import Foundation

/// Pricing a via route as consecutive segments (owner request 2026-10-09: „man sollte auch VIA Halte rein machen“).
/// Used when no single ticket for the via route could be priced: the regular fare is then the sum of the segment
/// fares A → V₁ → V₂ → B, and the explanation says so. Pure.
public enum ViaPricing {
    /// "Innsbruck Hbf – Feldkirch € 37,90 (ÖBB)" parts joined with " + ", prefixed by "Summe von 2 Teilstrecken über
    /// Feldkirch: ". `direct` (the table price without the via stops) is offered as an alternative.
    public static func combine(_ parts: [PriceQuote], points: [PriceEndpoint], request: PriceRequest,
                               direct: PriceAlternative? = nil) -> PriceQuote {
        let amount = (parts.reduce(0) { $0 + $1.amountEUR } * 100).rounded() / 100
        let source = combinedSource(parts.map(\.source))
        var providers: [String] = []
        for p in parts.compactMap(\.provider) where !providers.contains(p) { providers.append(p) }
        let products = parts.compactMap(\.productName)
        var lines: [String] = []
        for (i, part) in parts.enumerated() where i + 1 < points.count {
            lines.append("\(name(points[i])) – \(name(points[i + 1])) \(FareEstimator.euro(part.amountEUR)) (\(label(part)))")
        }
        let viaNames = points.dropFirst().dropLast().map(name).joined(separator: ", ")
        let explanation = "Summe von \(parts.count) Teilstrecken über \(viaNames): " + lines.joined(separator: " + ")
        let distances = parts.compactMap(\.distanceKm)
        let discount = parts.allSatisfy { $0.discount == request.discount } ? request.discount : .none
        var alternatives: [PriceAlternative] = []
        if let direct, abs(direct.amountEUR - amount) >= 0.05 { alternatives.append(direct) }
        return PriceQuote(amountEUR: amount, source: source, provider: providers.isEmpty ? nil : providers.joined(separator: " + "),
                          productName: products.count == parts.count && !products.isEmpty ? products.joined(separator: " + ") : nil,
                          travelClass: request.travelClass, discount: discount, travelDate: request.departure,
                          fetchedAt: parts.compactMap(\.fetchedAt).min(), leadTime: parts.first?.leadTime, connectionID: nil,
                          shopURL: request.journey?.shopURL ?? parts.first?.shopURL,
                          distanceKm: distances.count == parts.count && !distances.isEmpty ? (distances.reduce(0, +) * 10).rounded() / 10 : nil,
                          explanation: explanation, alternatives: alternatives)
    }

    /// All live → live (shop if any part came from the shop); otherwise the least authoritative offline source.
    static func combinedSource(_ sources: [PriceSource]) -> PriceSource {
        if sources.allSatisfy(\.isLive) { return sources.contains(.liveOebb) ? .liveOebb : .liveVerbund }
        if sources.contains(.distanceModel) { return .distanceModel }
        if sources.contains(.cityTicket) && !sources.contains(.table) { return .cityTicket }
        if sources.contains(.manual) && !sources.contains(.table) { return .manual }
        return .table
    }

    /// Short source label of a part: provider for live parts, else "Tarif-Tabelle" / "Stadttarif" / "Schätzung".
    static func label(_ q: PriceQuote) -> String {
        switch q.source {
        case .liveOebb, .liveVerbund: return q.provider ?? "live"
        case .table: return "Tarif-Tabelle"
        case .cityTicket: return "Stadttarif"
        case .distanceModel: return "Schätzung"
        case .manual: return "eigener Preis"
        }
    }

    /// Display name without parenthesised suffixes ("Wien Hbf (Bahnsteige 3-12)" → "Wien Hbf").
    static func name(_ e: PriceEndpoint) -> String {
        StationLinker.displayName(e.name)
    }

    /// Consecutive endpoint pairs of a via request: [A, V₁, …, B].
    public static func points(_ request: PriceRequest) -> [PriceEndpoint] {
        [request.from] + request.via.prefix(JourneyQuery.maxViaStops) + [request.to]
    }
}

extension PriceQuote {
    /// An offline estimate as a quote (no `fetchedAt`, no `provider` – the contract keeps both nil offline).
    init(estimate e: FareEstimate, request: PriceRequest) {
        let source: PriceSource
        switch e.method {
        case .officialTable: source = .table
        case .cityTicket: source = .cityTicket
        case .distanceTariff: source = .distanceModel
        case .liveOebb: source = .liveOebb
        case .liveVerbund: source = .liveVerbund
        case .manual: source = .manual
        }
        self.init(amountEUR: (e.fareEUR * 100).rounded() / 100, source: source, provider: nil,
                  productName: source == .table ? "Standard-Ticket" : nil, travelClass: request.travelClass, discount: request.discount,
                  travelDate: request.departure, distanceKm: e.distanceKm > 0 ? e.distanceKm : nil, explanation: e.explanation)
    }
}

extension FareEstimate.Method {
    /// Method for a quote source (SPEC §B7).
    init(source: PriceSource) {
        switch source {
        case .liveOebb: self = .liveOebb
        case .liveVerbund: self = .liveVerbund
        case .table: self = .officialTable
        case .cityTicket: self = .cityTicket
        case .distanceModel: self = .distanceTariff
        case .manual: self = .manual
        }
    }
}
