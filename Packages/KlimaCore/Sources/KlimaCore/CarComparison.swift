import Foundation

// MARK: - "Öffis vs. Auto" – what the same trips would have cost by car

/// How the car's running costs per km are valued.
public enum CarCostMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Amtliches Kilometergeld für Pkw: € 0,50/km seit 1. Jänner 2025 (oesterreich.gv.at › Pendlerpauschale und Kilometergeld).
    /// Meant to cover all costs of a private car (fuel, depreciation, insurance, service) – a realistic lower bound of full costs.
    case kilometergeld
    /// Fuel only: consumption (l/100 km) × fuel price (€/l) – what you pay at the pump.
    case fuelOnly
    /// The holder's own full cost per km (e.g. ÖAMTC-Autokostenrechner, typically € 0,45–0,60 per km).
    case fullCost

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .kilometergeld: "Kilometergeld"
        case .fuelOnly: "Nur Sprit"
        case .fullCost: "Vollkosten"
        }
    }
}

/// Yearly fixed costs a holder avoids by not owning a car ("Auto abgeschafft"), EUR per year.
public struct CarFixedCosts: Codable, Hashable, Sendable {
    /// Haftpflicht/Kasko incl. motorbezogene Versicherungssteuer.
    public var insurance: Double
    /// Autobahn-Jahresvignette.
    public var vignette: Double
    /// Parkpickerl, Garage, Stellplatz.
    public var parking: Double
    /// Service, Reifen, §-57a-Pickerl, kleinere Reparaturen.
    public var service: Double

    public init(insurance: Double, vignette: Double, parking: Double, service: Double) {
        self.insurance = insurance
        self.vignette = vignette
        self.parking = parking
        self.service = service
    }

    public var total: Double { max(0, insurance) + max(0, vignette) + max(0, parking) + max(0, service) }

    /// ASFINAG Jahresvignette 2026 für Pkw (+ 2,9 % HVPI; gültig 1.12.2025 – 31.1.2027).
    public static let vignette2026 = 106.80

    /// Example values for a compact car – the holder replaces them with their own.
    public static let defaults = CarFixedCosts(insurance: 950, vignette: vignette2026, parking: 0, service: 450)
}

/// Everything needed to value the car alternative.
public struct CarProfile: Codable, Hashable, Sendable {
    public var mode: CarCostMode
    /// Amtliches Kilometergeld, EUR/km (from the remotely updatable tariff catalog).
    public var kilometergeldPerKm: Double
    public var litersPer100Km: Double
    public var fuelPricePerLiter: Double
    /// Own full cost per km, EUR.
    public var fullCostPerKm: Double
    /// "Auto abgeschafft": avoided fixed costs are added (prorated per day of the ticket period).
    public var carGivenUp: Bool
    public var fixedCosts: CarFixedCosts
    /// Road km per rail km, see `CarProfile.defaultRoadDistanceFactor`.
    public var roadDistanceFactor: Double

    /// Pkw-Kilometergeld since 1 Jan 2025.
    public static let defaultKilometergeld = 0.50
    public static let defaultLitersPer100Km = 6.5
    public static let defaultFuelPricePerLiter = 1.65
    /// ÖAMTC full cost of a typical compact car (also `TariffCatalog.carFullCostPerKmEUR`).
    public static let defaultFullCostPerKm = 0.47
    /// Logged trips only know rail (or line) kilometres. By car you rarely drive station to station: the way to the
    /// station/your parking spot, road routing through valleys and town centres, and finding a parking space add up.
    /// KlimaBilanz therefore assumes road km ≈ rail km × 1,15 (documented in the app under "So rechnen wir").
    public static let defaultRoadDistanceFactor = 1.15

    public init(mode: CarCostMode = .kilometergeld, kilometergeldPerKm: Double = CarProfile.defaultKilometergeld,
                litersPer100Km: Double = CarProfile.defaultLitersPer100Km, fuelPricePerLiter: Double = CarProfile.defaultFuelPricePerLiter,
                fullCostPerKm: Double = CarProfile.defaultFullCostPerKm, carGivenUp: Bool = false,
                fixedCosts: CarFixedCosts = .defaults, roadDistanceFactor: Double = CarProfile.defaultRoadDistanceFactor) {
        self.mode = mode
        self.kilometergeldPerKm = kilometergeldPerKm
        self.litersPer100Km = litersPer100Km
        self.fuelPricePerLiter = fuelPricePerLiter
        self.fullCostPerKm = fullCostPerKm
        self.carGivenUp = carGivenUp
        self.fixedCosts = fixedCosts
        self.roadDistanceFactor = roadDistanceFactor
    }

    /// Fuel cost per km (l/100 km × €/l ÷ 100).
    public var fuelCostPerKm: Double { max(0, litersPer100Km) * max(0, fuelPricePerLiter) / 100 }

    /// Running cost per km for the selected mode, EUR.
    public var costPerKm: Double {
        switch mode {
        case .kilometergeld: max(0, kilometergeldPerKm)
        case .fuelOnly: fuelCostPerKm
        case .fullCost: max(0, fullCostPerKm)
        }
    }

    /// Avoided fixed costs per year (0 unless "Auto abgeschafft").
    public var fixedCostsPerYear: Double { carGivenUp ? fixedCosts.total : 0 }

    /// Kilometergeld and full costs already contain a prorated share of the fixed costs – adding the avoided fixed costs
    /// on top would count them twice. Fair combination: "Auto abgeschafft" + "Nur Sprit".
    public var mayDoubleCountFixedCosts: Bool { carGivenUp && mode != .fuelOnly }

    public func roadKm(railKm: Double) -> Double { max(0, railKm) * max(1, roadDistanceFactor) }
}

/// Cumulative car cost on a day (end of day).
public struct CarCostPoint: Hashable, Sendable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct CarComparisonResult: Hashable, Sendable {
    /// What the holder paid for the ticket (own share) – the flat "KlimaTicket" line.
    public var ticketCost: Double
    public var costPerKm: Double
    /// Rail/line km of all legs.
    public var railKm: Double
    /// Road km of all legs (rail km × road factor).
    public var roadKm: Double
    public var tripCount: Int
    public var legCount: Int
    /// Road km × cost per km.
    public var variableCost: Double
    public var fixedCostsPerYear: Double
    /// Avoided fixed costs prorated up to today (or the end of the period).
    public var fixedCostsToDate: Double
    /// Day the car would have become more expensive than the ticket (nil = not yet).
    public var breakEvenDate: Date?
    /// Forecast of that day at the current pace (only when it lies within the ticket period).
    public var forecastBreakEvenDate: Date?
    /// One point per day from the ticket start to today (end-of-day values; first point = 0 at the start).
    public var series: [CarCostPoint]
    /// Today → end of the period at the current pace (empty when the period is over).
    public var forecast: [CarCostPoint]
    public var projectedEndCarCost: Double
    public var co2CarKg: Double
    public var co2TransitKg: Double
    /// Rough hours behind the wheel for the same legs (no traffic jams, no parking search).
    public var drivingHours: Double

    public var carCost: Double { variableCost + fixedCostsToDate }
    /// Positive = the ticket is cheaper than the car so far.
    public var savings: Double { carCost - ticketCost }
    public var isCheaperThanCar: Bool { carCost >= ticketCost }
    public var remainingToBreakEven: Double { max(0, ticketCost - carCost) }
    public var co2SavedKg: Double { max(0, co2CarKg - co2TransitKg) }
    public var averageCarCostPerTrip: Double { tripCount > 0 ? carCost / Double(tripCount) : 0 }
    public var projectedEndSavings: Double { projectedEndCarCost - ticketCost }
}

public enum CarComparison {
    /// Compares the ticket's own share with the car alternative for all trips of the period up to `now`.
    public static func compare(ticket: TicketPeriod, trips allTrips: [TripRecord], profile: CarProfile,
                               emissions: EmissionFactors = .fallback, now: Date = Date(),
                               calendar: Calendar = .vienna) -> CarComparisonResult {
        let trips = allTrips.filter { ticket.contains($0.date) && $0.date <= now }.sorted { $0.date < $1.date }
        let costPerKm = profile.costPerKm
        let fixedPerYear = profile.fixedCostsPerYear

        var railKm = 0.0, roadKm = 0.0, legs = 0, co2Car = 0.0, co2Transit = 0.0, hours = 0.0
        var perDay: [Date: Double] = [:]
        var memo = DayMemo(calendar)
        for trip in trips {
            let road = profile.roadKm(railKm: trip.totalDistanceKm)
            railKm += trip.totalDistanceKm
            roadKm += road
            legs += trip.legs
            co2Car += emissions.car * road / 1000
            co2Transit += emissions.grams(for: trip.mode) * trip.totalDistanceKm / 1000
            hours += Double(trip.legs) * drivingHours(roadKmPerLeg: profile.roadKm(railKm: trip.distanceKm))
            perDay[memo.startOfDay(trip.date), default: 0] += road * costPerKm
        }

        let startDay = calendar.startOfDay(for: ticket.start)
        let endDay = calendar.startOfDay(for: ticket.end)
        let daysTotal = max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 364) + 1)
        let fixedPerDay = fixedPerYear / Double(daysTotal)

        // Daily end-of-day series up to today (or the end of the period).
        var series = [CarCostPoint(date: startDay, value: 0)]
        var running = 0.0
        var breakEven: Date?
        var elapsedDays = 0
        if now >= ticket.start {
            let lastDay = calendar.startOfDay(for: min(now, ticket.end))
            elapsedDays = min(daysTotal, (calendar.dateComponents([.day], from: startDay, to: lastDay).day ?? 0) + 1)
            for index in 0..<elapsedDays {
                guard let day = calendar.date(byAdding: .day, value: index, to: startDay) else { continue }
                running += perDay[day] ?? 0
                let value = running + fixedPerDay * Double(index + 1)
                if breakEven == nil, value >= ticket.price { breakEven = day }
                let endOfDay = calendar.date(byAdding: .second, value: 86_399, to: day) ?? day
                series.append(CarCostPoint(date: endOfDay, value: value))
            }
        }
        let variable = running
        let fixedToDate = fixedPerDay * Double(elapsedDays)
        let current = variable + fixedToDate

        // Forecast at the blended pace (long-run 40 %, last 42 days 60 % – same weighting as the savings forecast).
        var forecast: [CarCostPoint] = []
        var forecastBreakEven: Date?
        var projected = current
        if now >= ticket.start, now < ticket.end, elapsedDays > 0, let today = series.last {
            let remainingDays = max(0, daysTotal - elapsedDays)
            let longRun = variable / Double(elapsedDays)
            var pace = longRun
            if elapsedDays > 14 {
                let window = min(42, elapsedDays)
                let windowStart = calendar.date(byAdding: .day, value: elapsedDays - window, to: startDay) ?? startDay
                let recent = perDay.filter { $0.key >= windowStart }.reduce(0) { $0 + $1.value } / Double(window)
                pace = 0.4 * longRun + 0.6 * recent
            }
            let daily = pace + fixedPerDay
            projected = current + daily * Double(remainingDays)
            let endOfPeriod = calendar.date(byAdding: .second, value: 86_399, to: endDay) ?? endDay
            if remainingDays > 0 {
                forecast = [today, CarCostPoint(date: endOfPeriod, value: projected)]
            }
            if breakEven == nil, daily > 0.0001 {
                let needed = Int(((ticket.price - current) / daily).rounded(.up))
                if needed <= remainingDays, let lastDay = calendar.date(byAdding: .day, value: elapsedDays - 1, to: startDay) {
                    forecastBreakEven = calendar.date(byAdding: .day, value: max(1, needed), to: lastDay)
                }
            }
        }

        return CarComparisonResult(
            ticketCost: ticket.price,
            costPerKm: costPerKm,
            railKm: railKm,
            roadKm: roadKm,
            tripCount: JourneySummary.tripCount(trips),   // a journey is one "Fahrt" (docs/JOURNEYS.md)
            legCount: legs,
            variableCost: variable,
            fixedCostsPerYear: fixedPerYear,
            fixedCostsToDate: fixedToDate,
            breakEvenDate: breakEven,
            forecastBreakEvenDate: forecastBreakEven,
            series: series,
            forecast: forecast,
            projectedEndCarCost: projected,
            co2CarKg: co2Car,
            co2TransitKg: co2Transit,
            drivingHours: hours
        )
    }

    /// Typical average speed (km/h) of a car leg, including towns – deliberately without jams and parking search:
    /// up to 10 km 30 km/h (town), up to 40 km 50 km/h (Landstraße), up to 120 km 70 km/h, beyond 85 km/h (Autobahn).
    public static func averageSpeedKmh(forLegKm km: Double) -> Double {
        switch km {
        case ..<10: 30
        case ..<40: 50
        case ..<120: 70
        default: 85
        }
    }

    /// Hours behind the wheel for one leg.
    public static func drivingHours(roadKmPerLeg km: Double) -> Double {
        guard km > 0 else { return 0 }
        return km / averageSpeedKmh(forLegKm: km)
    }
}

// MARK: - Input

/// Tolerant parser for amounts typed with an Austrian keyboard: "1,65", "1.65", "1.100", "1.100,50", "€ 106,80".
/// Ambiguous dots are resolved with the allowed range ("1.659" €/l is a decimal, "1.100" €/Jahr is a thousand).
public enum CarInputParser {
    public static func decimal(_ text: String, in range: ClosedRange<Double>) -> Double? {
        let allowed = Set("0123456789.,-")
        let cleaned = String(text.filter { allowed.contains($0) })
        guard !cleaned.isEmpty, cleaned.contains(where: \.isNumber) else { return nil }
        var candidates: [Double] = []
        if cleaned.contains(","), cleaned.contains(".") {
            // "1.100,50": dot = grouping, comma = decimal.
            candidates.append(contentsOf: [Double(cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))].compactMap { $0 })
        } else if cleaned.contains(",") {
            candidates.append(contentsOf: [Double(cleaned.replacingOccurrences(of: ",", with: "."))].compactMap { $0 })
        } else if cleaned.contains(".") {
            let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
            let looksGrouped = parts.count >= 2 && parts.dropFirst().allSatisfy { $0.count == 3 } && (1...3).contains(parts[0].filter(\.isNumber).count)
            let asDecimal = parts.count == 2 ? Double(cleaned) : nil
            let asGrouped = looksGrouped ? Double(cleaned.replacingOccurrences(of: ".", with: "")) : nil
            // de-AT writes thousands with a dot: prefer the grouped reading when it fits the range ("1.100" €/Jahr),
            // otherwise the dot is a decimal point ("1.659" €/l, "0.500" €/km).
            candidates.append(contentsOf: [asGrouped, asDecimal].compactMap { $0 })
        } else {
            candidates.append(contentsOf: [Double(cleaned)].compactMap { $0 })
        }
        if let fitting = candidates.first(where: { range.contains($0) }) { return fitting }
        guard let first = candidates.first else { return nil }
        return min(max(first, range.lowerBound), range.upperBound)
    }
}
