import Foundation

/// One band of a degressive distance tariff: every km up to `upToKm` costs `ratePerKm`.
public struct FareBand: Codable, Hashable, Sendable {
    public var upToKm: Double
    public var ratePerKm: Double

    public init(upToKm: Double, ratePerKm: Double) {
        self.upToKm = upToKm
        self.ratePerKm = ratePerKm
    }
}

/// Distance-based regular fare (ÖBB Standard-Ticket approximation). Fully data-driven so it can be
/// updated remotely via the tariff catalog without an app update.
public struct FareModel: Codable, Hashable, Sendable {
    public var baseFee: Double
    public var bands: [FareBand]
    public var minimumFare: Double
    public var maximumFare: Double
    public var roundingStep: Double
    public var firstClassFactor: Double
    /// Multiplier converting straight-line distance into typical rail distance.
    public var detourFactor: Double
    /// Discount factors by card, e.g. ["vorteilscard": 0.5] means 50 % of the full fare.
    public var discountFactors: [String: Double]
    /// Piecewise-linear price curve [[railKm, EUR], …] (preferred over `bands` when present).
    public var knots: [[Double]]?
    /// Distance-dependent detour factors [[upToStraightKm, factor], …] (preferred over `detourFactor`).
    public var detourBands: [[Double]]?

    public init(baseFee: Double, bands: [FareBand], minimumFare: Double, maximumFare: Double, roundingStep: Double,
                firstClassFactor: Double, detourFactor: Double, discountFactors: [String: Double],
                knots: [[Double]]? = nil, detourBands: [[Double]]? = nil) {
        self.baseFee = baseFee
        self.bands = bands
        self.minimumFare = minimumFare
        self.maximumFare = maximumFare
        self.roundingStep = roundingStep
        self.firstClassFactor = firstClassFactor
        self.detourFactor = detourFactor
        self.discountFactors = discountFactors
        self.knots = knots
        self.detourBands = detourBands
    }

    /// Full 2nd-class fare for a given rail distance.
    public func fullFare(railKm: Double) -> Double {
        guard railKm > 0 else { return 0 }
        // Only well-formed points count ([km, EUR], finite); fewer than two fall back to the band model – the catalog
        // can come from the update server, and a malformed curve must never trap on every price estimate.
        let pts = (knots ?? []).filter { $0.count >= 2 && $0[0].isFinite && $0[1].isFinite }.sorted { $0[0] < $1[0] }
        if pts.count >= 2 {
            var value = pts[pts.count - 1][1]
            if railKm <= pts[0][0] {
                value = pts[0][1]
            } else if railKm >= pts[pts.count - 1][0] {
                // extrapolate with the last segment's slope
                let a = pts[pts.count - 2], b = pts[pts.count - 1]
                value = b[1] + (railKm - b[0]) * (b[1] - a[1]) / max(b[0] - a[0], 0.001)
            } else {
                for i in 1..<pts.count where railKm <= pts[i][0] {
                    let a = pts[i - 1], b = pts[i]
                    value = a[1] + (railKm - a[0]) * (b[1] - a[1]) / max(b[0] - a[0], 0.001)
                    break
                }
            }
            return min(max(value, minimumFare), maximumFare)
        }
        var remaining = railKm
        var lower = 0.0
        var total = baseFee
        for band in bands.sorted(by: { $0.upToKm < $1.upToKm }) {
            let span = min(remaining, band.upToKm - lower)
            if span <= 0 { lower = band.upToKm; continue }
            total += span * band.ratePerKm
            remaining -= span
            lower = band.upToKm
            if remaining <= 0 { break }
        }
        if remaining > 0, let last = bands.max(by: { $0.upToKm < $1.upToKm }) {
            total += remaining * last.ratePerKm
        }
        return min(max(total, minimumFare), maximumFare)
    }

    public func fare(railKm: Double, travelClass: TravelClass = .second, discount: FareDiscount = .none) -> Double {
        var value = fullFare(railKm: railKm)
        if travelClass == .first { value *= firstClassFactor }
        if let factor = discountFactors[discount.rawValue] { value *= factor }
        return round(value)
    }

    public func railDistance(fromStraightLineKm km: Double) -> Double {
        if let bands = detourBands?.filter({ $0.count >= 2 }).sorted(by: { $0[0] < $1[0] }), !bands.isEmpty {
            let factor = bands.first(where: { km <= $0[0] })?[1] ?? bands.last![1]
            return km * factor
        }
        // Short hops detour relatively more (valleys, curves); converge to detourFactor for long trips.
        let shortBoost = km < 15 ? 0.15 * (1 - km / 15) : 0
        return km * (detourFactor + shortBoost)
    }

    func round(_ value: Double) -> Double {
        guard roundingStep > 0 else { return value }
        return (value / roundingStep).rounded() * roundingStep
    }

    /// Fallback fitted to 208,510 official ÖBB relations (Tarif ab 14.12.2025, 2. Kl., online, Reisetag; median error 4 %).
    public static let fallback = FareModel(
        baseFee: 0.456,
        bands: [FareBand(upToKm: 260.6, ratePerKm: 0.2193), FareBand(upToKm: 5000, ratePerKm: 0.1274)],
        minimumFare: 2.4,
        maximumFare: 101.2,
        roundingStep: 0.1,
        firstClassFactor: 1.951,
        detourFactor: 1.2,
        discountFactors: ["none": 1.0, "vorteilscard": 0.5],
        knots: [[0, 2.36], [10, 2.42], [20, 4.70], [30, 7.10], [50, 11.68], [75, 17.23], [100, 22.34], [150, 33.92],
                [200, 44.55], [250, 53.62], [300, 62.65], [400, 77.56], [500, 88.80], [600, 94.83], [1000, 114.77]],
        detourBands: [[25, 1.15], [10_000, 1.22]]
    )
}

/// Flat urban fare (single ticket) for a city / Kernzone.
public struct CityFare: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var singleTicketEUR: Double
    public var latitude: Double
    public var longitude: Double
    public var radiusKm: Double

    public init(id: String, name: String, singleTicketEUR: Double, latitude: Double, longitude: Double, radiusKm: Double) {
        self.id = id
        self.name = name
        self.singleTicketEUR = singleTicketEUR
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
    }

    public var center: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
    public func contains(_ p: GeoPoint) -> Bool { center.distanceKm(to: p) <= radiusKm }
}

/// Grams of CO₂e per passenger-km.
public struct EmissionFactors: Codable, Hashable, Sendable {
    public var car: Double
    public var train: Double
    public var bus: Double
    public var tram: Double

    public init(car: Double, train: Double, bus: Double, tram: Double) {
        self.car = car
        self.train = train
        self.bus = bus
        self.tram = tram
    }

    public func grams(for mode: TransportMode) -> Double {
        switch mode {
        case .train, .sBahn, .cableCar: train
        case .bus, .ferry, .other: bus
        case .tram, .metro: tram
        }
    }

    /// CO₂ saved (kg) by taking `mode` instead of driving alone for `km`.
    public func savedKg(km: Double, mode: TransportMode) -> Double {
        max(0, (car - grams(for: mode)) * km / 1000)
    }

    /// Umweltbundesamt, data year 2024 (published 05/2026), direct + upstream, g/pkm.
    public static let fallback = EmissionFactors(car: 174.0, train: 7.2, bus: 50.7, tram: 7.2)
}

/// Remotely updatable tariff catalog (bundled `tariffs.json`, refreshed from the update server).
public struct TariffCatalog: Codable, Hashable, Sendable {
    public var version: Int
    public var updatedAt: String
    public var currency: String
    public var products: [TicketProduct]
    public var fareModel: FareModel
    public var cityFares: [CityFare]
    /// Amtliches Kilometergeld (EUR/km) – used for the "vs. Auto" comparison.
    public var kilometergeldEUR: Double
    /// Realistic full cost of car ownership per km (ÖAMTC), EUR/km.
    public var carFullCostPerKmEUR: Double
    public var emissions: EmissionFactors
    public var notes: [String]
    /// Tariff increases by travel date, e.g. [{"validFrom": "2026-12-13", "factor": 1.035}] (applied cumulatively).
    public var fareIndex: [FareIndexPoint]?

    public struct FareIndexPoint: Codable, Hashable, Sendable {
        public var validFrom: String
        public var factor: Double

        public init(validFrom: String, factor: Double) {
            self.validFrom = validFrom
            self.factor = factor
        }
    }

    /// Cumulative price factor for trips on `date`.
    public func fareFactor(on date: Date, calendar: Calendar = .vienna) -> Double {
        guard let fareIndex, !fareIndex.isEmpty else { return 1 }
        let day = TicketProduct.isoDay(date, calendar: calendar)
        return fareIndex.filter { $0.validFrom <= day }.reduce(1) { $0 * $1.factor }
    }

    public init(version: Int, updatedAt: String, currency: String = "EUR", products: [TicketProduct], fareModel: FareModel,
                cityFares: [CityFare], kilometergeldEUR: Double, carFullCostPerKmEUR: Double, emissions: EmissionFactors, notes: [String] = [],
                fareIndex: [FareIndexPoint]? = nil) {
        self.version = version
        self.updatedAt = updatedAt
        self.currency = currency
        self.products = products
        self.fareModel = fareModel
        self.cityFares = cityFares
        self.kilometergeldEUR = kilometergeldEUR
        self.carFullCostPerKmEUR = carFullCostPerKmEUR
        self.emissions = emissions
        self.notes = notes
        self.fareIndex = fareIndex
    }

    public static func decode(from data: Data) throws -> TariffCatalog {
        try JSONDecoder().decode(TariffCatalog.self, from: data)
    }

    public func product(id: String) -> TicketProduct? { products.first { $0.id == id } }

    /// Sanity check for a catalog from the update server before it replaces the bundled one: products with real prices
    /// and a fare model that prices short, medium and long trips. A file that decodes but fails this is ignored.
    public var isUsable: Bool {
        guard !products.isEmpty, products.allSatisfy({ $0.priceEUR.isFinite && $0.priceEUR > 0 }) else { return false }
        guard kilometergeldEUR.isFinite, kilometergeldEUR >= 0 else { return false }
        return [10.0, 100, 500].allSatisfy { km in
            let fare = fareModel.fullFare(railKm: km)
            return fare.isFinite && fare > 0
        }
    }
}
