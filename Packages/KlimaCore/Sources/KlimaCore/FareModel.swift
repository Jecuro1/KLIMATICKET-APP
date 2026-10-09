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

    public init(baseFee: Double, bands: [FareBand], minimumFare: Double, maximumFare: Double, roundingStep: Double,
                firstClassFactor: Double, detourFactor: Double, discountFactors: [String: Double]) {
        self.baseFee = baseFee
        self.bands = bands
        self.minimumFare = minimumFare
        self.maximumFare = maximumFare
        self.roundingStep = roundingStep
        self.firstClassFactor = firstClassFactor
        self.detourFactor = detourFactor
        self.discountFactors = discountFactors
    }

    /// Full 2nd-class fare for a given rail distance.
    public func fullFare(railKm: Double) -> Double {
        guard railKm > 0 else { return 0 }
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
        // Short hops detour relatively more (valleys, curves); converge to detourFactor for long trips.
        let shortBoost = km < 15 ? 0.15 * (1 - km / 15) : 0
        return km * (detourFactor + shortBoost)
    }

    func round(_ value: Double) -> Double {
        guard roundingStep > 0 else { return value }
        return (value / roundingStep).rounded() * roundingStep
    }

    /// Conservative fallback used when no catalog is available (fitted to 2025/26 ÖBB Standard-Ticket examples).
    public static let fallback = FareModel(
        baseFee: 1.4,
        bands: [
            FareBand(upToKm: 20, ratePerKm: 0.205),
            FareBand(upToKm: 50, ratePerKm: 0.195),
            FareBand(upToKm: 100, ratePerKm: 0.185),
            FareBand(upToKm: 200, ratePerKm: 0.175),
            FareBand(upToKm: 400, ratePerKm: 0.14),
            FareBand(upToKm: 2000, ratePerKm: 0.07),
        ],
        minimumFare: 2.4,
        maximumFare: 110,
        roundingStep: 0.1,
        firstClassFactor: 1.6,
        detourFactor: 1.22,
        discountFactors: ["none": 1.0, "vorteilscard": 0.5]
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

    public static let fallback = EmissionFactors(car: 166, train: 8, bus: 60, tram: 26)
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

    public init(version: Int, updatedAt: String, currency: String = "EUR", products: [TicketProduct], fareModel: FareModel,
                cityFares: [CityFare], kilometergeldEUR: Double, carFullCostPerKmEUR: Double, emissions: EmissionFactors, notes: [String] = []) {
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
    }

    public static func decode(from data: Data) throws -> TariffCatalog {
        try JSONDecoder().decode(TariffCatalog.self, from: data)
    }

    public func product(id: String) -> TicketProduct? { products.first { $0.id == id } }
}
