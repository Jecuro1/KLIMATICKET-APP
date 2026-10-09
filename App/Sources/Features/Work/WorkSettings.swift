import SwiftUI
import KlimaCore

/// Preferences of the "Auto-Vergleich & Arbeit/Steuer" module, persisted in UserDefaults (observable).
/// One shared instance, so the statistics card, the detail screen and the settings always agree.
@Observable
@MainActor
final class WorkSettings {
    static let shared = WorkSettings(defaults: WorkSettings.makeStore())

    private let defaults: UserDefaults

    // MARK: Car comparison

    var carMode: CarCostMode { didSet { defaults.set(carMode.rawValue, forKey: Key.carMode) } }
    var litersPer100Km: Double { didSet { defaults.set(litersPer100Km, forKey: Key.liters) } }
    var fuelPricePerLiter: Double { didSet { defaults.set(fuelPricePerLiter, forKey: Key.fuelPrice) } }
    /// nil = the catalog's ÖAMTC value (`TariffCatalog.carFullCostPerKmEUR`).
    var fullCostPerKm: Double? { didSet { defaults.set(fullCostPerKm, forKey: Key.fullCost) } }
    var carGivenUp: Bool { didSet { defaults.set(carGivenUp, forKey: Key.carGivenUp) } }
    var insurance: Double { didSet { defaults.set(insurance, forKey: Key.insurance) } }
    var vignette: Double { didSet { defaults.set(vignette, forKey: Key.vignette) } }
    var parking: Double { didSet { defaults.set(parking, forKey: Key.parking) } }
    var service: Double { didSet { defaults.set(service, forKey: Key.service) } }

    // MARK: Work & tax

    var role: WorkTaxRole { didSet { defaults.set(role.rawValue, forKey: Key.role) } }
    /// Self-employed: the way to the business premises counts as business use.
    var countsCommuteAsBusiness: Bool { didSet { defaults.set(countsCommuteAsBusiness, forKey: Key.countsCommute) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let fixed = CarFixedCosts.defaults
        carMode = CarCostMode(rawValue: defaults.string(forKey: Key.carMode) ?? "") ?? .kilometergeld
        litersPer100Km = defaults.object(forKey: Key.liters) as? Double ?? CarProfile.defaultLitersPer100Km
        fuelPricePerLiter = defaults.object(forKey: Key.fuelPrice) as? Double ?? CarProfile.defaultFuelPricePerLiter
        fullCostPerKm = defaults.object(forKey: Key.fullCost) as? Double
        carGivenUp = defaults.bool(forKey: Key.carGivenUp)
        insurance = defaults.object(forKey: Key.insurance) as? Double ?? fixed.insurance
        vignette = defaults.object(forKey: Key.vignette) as? Double ?? fixed.vignette
        parking = defaults.object(forKey: Key.parking) as? Double ?? fixed.parking
        service = defaults.object(forKey: Key.service) as? Double ?? fixed.service
        role = WorkTaxRole(rawValue: defaults.string(forKey: Key.role) ?? "") ?? .employee
        countsCommuteAsBusiness = defaults.object(forKey: Key.countsCommute) as? Bool ?? true
    }

    var fixedCosts: CarFixedCosts {
        CarFixedCosts(insurance: insurance, vignette: vignette, parking: parking, service: service)
    }

    /// Full cost per km actually used (own value or the catalog's ÖAMTC value).
    func effectiveFullCost(catalog: TariffCatalog) -> Double {
        fullCostPerKm ?? (catalog.carFullCostPerKmEUR > 0 ? catalog.carFullCostPerKmEUR : CarProfile.defaultFullCostPerKm)
    }

    func carProfile(catalog: TariffCatalog) -> CarProfile {
        CarProfile(mode: carMode,
                   kilometergeldPerKm: catalog.kilometergeldEUR > 0 ? catalog.kilometergeldEUR : CarProfile.defaultKilometergeld,
                   litersPer100Km: litersPer100Km, fuelPricePerLiter: fuelPricePerLiter,
                   fullCostPerKm: effectiveFullCost(catalog: catalog), carGivenUp: carGivenUp, fixedCosts: fixedCosts)
    }

    /// Back to the official/example values.
    func resetCar() {
        let fixed = CarFixedCosts.defaults
        carMode = .kilometergeld
        litersPer100Km = CarProfile.defaultLitersPer100Km
        fuelPricePerLiter = CarProfile.defaultFuelPricePerLiter
        fullCostPerKm = nil
        carGivenUp = false
        insurance = fixed.insurance
        vignette = fixed.vignette
        parking = fixed.parking
        service = fixed.service
    }

    var isCarAtDefaults: Bool {
        let fixed = CarFixedCosts.defaults
        return carMode == .kilometergeld && litersPer100Km == CarProfile.defaultLitersPer100Km
            && fuelPricePerLiter == CarProfile.defaultFuelPricePerLiter && fullCostPerKm == nil && !carGivenUp
            && fixedCosts == fixed
    }

    /// Screenshot runs use a throw-away store so every capture starts from known values.
    private static func makeStore() -> UserDefaults {
        guard LaunchMode.isScreenshot else { return .standard }
        let name = "screenshots.work"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

    private enum Key {
        static let carMode = "work.car.mode"
        static let liters = "work.car.litersPer100Km"
        static let fuelPrice = "work.car.fuelPrice"
        static let fullCost = "work.car.fullCostPerKm"
        static let carGivenUp = "work.car.givenUp"
        static let insurance = "work.car.fixed.insurance"
        static let vignette = "work.car.fixed.vignette"
        static let parking = "work.car.fixed.parking"
        static let service = "work.car.fixed.service"
        static let role = "work.tax.role"
        static let countsCommute = "work.tax.countsCommute"
    }
}

// MARK: - Presentation helpers

extension CarCostMode {
    var symbol: String {
        switch self {
        case .kilometergeld: "building.columns.fill"
        case .fuelOnly: "fuelpump.fill"
        case .fullCost: "chart.pie.fill"
        }
    }

    var tint: Color {
        switch self {
        case .kilometergeld: Theme.glacier
        case .fuelOnly: Theme.dawn
        case .fullCost: Theme.dusk
        }
    }

    /// One-line explanation used in the mode picker.
    var explanation: String {
        switch self {
        case .kilometergeld: "Amtlicher Satz – deckt Sprit, Wertverlust, Versicherung und Service ab"
        case .fuelOnly: "Verbrauch × Spritpreis – nur, was du an der Zapfsäule zahlst"
        case .fullCost: "Dein eigener Wert pro Kilometer, z. B. laut ÖAMTC"
        }
    }
}

enum WorkFormat {
    /// "€ 0,50/km"
    static func perKm(_ value: Double) -> String { "\(Format.euroPrecise(value))/km" }

    /// "6,5 l/100 km"
    static func liters(_ value: Double) -> String { "\(Format.number(value, decimals: 1)) l/100 km" }

    /// "9. Oktober 2026"
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Format.locale))
    }

    /// "Keine Steuerberatung – Angaben ohne Gewähr, Stand 9. Oktober 2026"
    static var disclaimer: String {
        "Keine Steuerberatung – Angaben ohne Gewähr, Stand \(longDate(WorkTax.rulesCheckedDate()))"
    }

    /// "≈ 64 h" / "≈ 45 min"
    static func duration(hours: Double) -> String {
        if hours < 1 { return "≈ \(Format.number(max(1, hours * 60))) min" }
        return "≈ \(Format.number(hours, decimals: hours < 10 ? 1 : 0)) h"
    }

    /// "1 Dienstreise" / "7 Dienstreisen"
    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(Format.number(Double(n))) \(n == 1 ? singular : plural)"
    }

    /// File-name friendly ticket year ("2026-27").
    static func fileYear(_ period: TicketPeriod) -> String {
        StatsCalc.ticketYearLabel(period).replacingOccurrences(of: "/", with: "-")
    }
}
