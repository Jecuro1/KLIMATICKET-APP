import Foundation

/// Tariff periods of the ÖBB price list (SPEC §B4.3). A boundary is the first day of a new tariff: every
/// `catalog.fareIndex[].validFrom` plus `relations.validFrom` (2025-12-14). Two days are in the same period when no
/// boundary lies in `(min, max]`. The shop's day-of-travel price for a relation only changes at a boundary, so
/// today's price is a valid proxy for an earlier day of the same period [ASSUMED, consistent with LIVE checks].
public struct TariffPeriods: Sendable, Hashable {
    /// ISO days "yyyy-MM-dd", ascending and unique.
    public let boundaries: [String]

    public init(boundaries: [String]) {
        self.boundaries = Array(Set(boundaries.filter { TariffPeriods.isISODay($0) })).sorted()
    }

    public init(catalog: TariffCatalog, relationsValidFrom: String) {
        self.init(boundaries: (catalog.fareIndex ?? []).map(\.validFrom) + [relationsValidFrom])
    }

    public init(estimator: FareEstimator) {
        self.init(catalog: estimator.catalog, relationsValidFrom: estimator.relations.validFrom)
    }

    /// True when no tariff boundary lies in `(min(a, b), max(a, b)]` (Vienna calendar days).
    public func same(_ a: Date, _ b: Date, calendar: Calendar = .vienna) -> Bool {
        same(day: TicketProduct.isoDay(a, calendar: calendar), day: TicketProduct.isoDay(b, calendar: calendar))
    }

    /// Same check on ISO days ("2026-10-08", "2026-10-09").
    public func same(day a: String, day b: String) -> Bool {
        let lo = min(a, b), hi = max(a, b)
        return !boundaries.contains { $0 > lo && $0 <= hi }
    }

    static func isISODay(_ s: String) -> Bool {
        let p = s.split(separator: "-")
        return p.count == 3 && p[0].count == 4 && p[1].count == 2 && p[2].count == 2 && p.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
