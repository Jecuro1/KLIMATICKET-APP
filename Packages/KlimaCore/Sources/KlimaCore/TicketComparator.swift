import Foundation

/// "Was wäre wenn" – which ticket would have been cheapest for the logged trips?
public struct TicketOption: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ticketPrice: Double
    /// Regular fares for trips this option would NOT cover.
    public var uncoveredCost: Double
    public var coveredTrips: Int
    public var totalCost: Double { ticketPrice + uncoveredCost }
    public var isCurrent: Bool
}

public enum TicketComparator {
    /// - Parameters:
    ///   - variant: compare only products of this variant (e.g. `.klassik`), single tickets are always included.
    ///   - periodStart: start of the compared ticket period – every option is priced for that start date
    ///     (`TicketProduct.price(forStart:)`, KlimaTicket prices change by start date); nil = today's catalog price.
    ///   - annualize: scale the trips to a full year when the period has just started.
    public static func compare(trips: [TripRecord], products: [TicketProduct], variant: TicketVariant,
                               currentProductID: String?, periodStart: Date? = nil,
                               annualizationFactor: Double = 1) -> [TicketOption] {
        let factor = max(annualizationFactor, 1)
        let singleTotal = trips.reduce(0) { $0 + $1.totalValue } * factor
        var options = [TicketOption(id: "single", name: "Einzeltickets", ticketPrice: 0, uncoveredCost: singleTotal,
                                    coveredTrips: 0, isCurrent: currentProductID == nil)]
        for p in products where (p.variant == variant && p.isLocal != true) || p.id == currentProductID {
            var uncovered = 0.0
            var covered = 0
            for t in trips {
                let states = t.states.isEmpty ? Set<String>() : t.states
                if !states.isEmpty && p.covers(states: states) || (states.isEmpty && p.family == .oe) {
                    covered += 1
                } else {
                    uncovered += t.totalValue
                }
            }
            let price = periodStart.map { p.price(forStart: $0) } ?? p.priceEUR
            options.append(TicketOption(id: p.id, name: p.name, ticketPrice: price, uncoveredCost: uncovered * factor,
                                        coveredTrips: covered, isCurrent: p.id == currentProductID))
        }
        return options.sorted { $0.totalCost < $1.totalCost }
    }
}
