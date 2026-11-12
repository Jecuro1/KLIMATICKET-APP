import SwiftUI
import KlimaCore

/// The user's choices on „Was wäre wenn?“: which mode, the routes and filters, the saved scenarios. The numbers are not
/// stored here – `result(using:source:)` calculates them from these inputs every time (it is cheap: no network, no storage).
@Observable
@MainActor
final class WhatIfModel {
    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case history, assumptions

        var id: String { rawValue }
        var title: String { self == .history ? "Meine Fahrten" : "Eigene Annahmen" }
    }

    var mode: Mode
    /// „Eigene Annahmen“: routes, variant, start.
    var assumptions: WhatIfInput
    /// „Meine Fahrten“: variant, exclusions, region, class, slider.
    var history: WhatIfInput
    /// Start month of the assumptions: 0 = this month (today's prices), 1…11 = the first of the following months.
    var startOffset: Int {
        get { startMonthStorage }
        set {
            startMonthStorage = min(max(newValue, 0), 11)
            assumptions.startDate = startDate(forOffset: startMonthStorage)
        }
    }
    private var startMonthStorage = 0
    var scenarios: [WhatIfScenario]
    /// A short hint after saving ("Gespeichert") or when the book is full.
    var scenarioNotice: String?

    let now: Date
    private let calendar = Calendar.vienna

    init(source: WhatIfSource, launch: WhatIfLaunch, scenarios seeded: [WhatIfScenario]? = nil, now: Date = Date()) {
        self.now = now
        scenarios = seeded ?? WhatIfStore.load().scenarios
        let variant = source.defaultVariant
        history = WhatIfInput(variant: variant, startDate: source.ticketStart ?? now, currentProductID: source.currentProductID)
        assumptions = WhatIfInput(variant: variant, startDate: now)
        mode = source.hasRichHistory ? .history : .assumptions
        switch launch {
        case .automatic:
            break
        case .historyFiltered:
            mode = .history
            history.volumeFactor = 1.5
            history.excludedMonths = [7, 8]
            history.regionFilter = source.regions.first?.state.rawValue
        case .preset(let id):
            mode = .assumptions
            if let preset = WhatIfPreset.preset(id: id) { assumptions.routes = preset.input(startDate: now, variant: variant).routes }
        case .empty:
            mode = .assumptions
        case .extreme:
            mode = .assumptions
            assumptions.routes = WhatIfPreset.all.prefix(2).flatMap { $0.routes }.map {
                WhatIfRoute(fromStationID: $0.fromStationID, toStationID: $0.toStationID, tripsPerMonth: WhatIfLimits.maxTripsPerMonth)
            }
        }
    }

    // MARK: Calculation

    var activeInput: WhatIfInput { mode == .history ? history : assumptions }

    func result(using calculator: WhatIfCalculator, source: WhatIfSource) -> WhatIfResult {
        switch mode {
        case .history:
            let trips = source.history ?? WhatIfHistory(trips: [], annualizationFactor: source.baseline.annualizationFactor)
            return calculator.evaluate(history, history: trips)
        case .assumptions:
            return calculator.evaluate(assumptions)
        }
    }

    // MARK: Routes (assumptions)

    var canAddRoute: Bool { assumptions.routes.count < WhatIfLimits.maxRoutes }

    /// A new route without stations yet (the picker asks for them right away); returns its id.
    @discardableResult
    func addRoute() -> UUID? {
        guard canAddRoute else { return nil }
        let route = WhatIfRoute(fromStationID: "", toStationID: "", tripsPerMonth: 4)
        assumptions.routes.append(route)
        return route.id
    }

    func removeRoute(id: UUID) {
        assumptions.routes.removeAll { $0.id == id }
    }

    func setStation(_ station: Station, routeID: UUID, isFrom: Bool) {
        guard let index = assumptions.routes.firstIndex(where: { $0.id == routeID }) else { return }
        if isFrom { assumptions.routes[index].fromStationID = station.id } else { assumptions.routes[index].toStationID = station.id }
    }

    func swapStations(routeID: UUID) {
        guard let index = assumptions.routes.firstIndex(where: { $0.id == routeID }) else { return }
        let route = assumptions.routes[index]
        assumptions.routes[index].fromStationID = route.toStationID
        assumptions.routes[index].toStationID = route.fromStationID
    }

    func apply(_ preset: WhatIfPreset) {
        assumptions.routes = preset.input(startDate: assumptions.startDate, variant: assumptions.variant).routes
    }

    /// Whether the routes are exactly the preset's (the preset chip shows as selected).
    func matches(_ preset: WhatIfPreset) -> Bool {
        let routes = assumptions.routes
        guard routes.count == preset.routes.count else { return false }
        return zip(routes, preset.routes).allSatisfy {
            $0.fromStationID == $1.fromStationID && $0.toStationID == $1.toStationID && $0.tripsPerMonth == $1.tripsPerMonth
        }
    }

    // MARK: Start month

    func startDate(forOffset offset: Int) -> Date {
        guard offset > 0 else { return now }
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return calendar.date(byAdding: .month, value: offset, to: first) ?? now
    }

    /// "November 2026" for the start-month menu.
    func startLabel(forOffset offset: Int) -> String {
        let date = startDate(forOffset: offset)
        return "\(StatsNames.wideMonth(date)) \(calendar.component(.year, from: date))"
    }

    // MARK: Filters (real data)

    var excludesSummer: Bool {
        get { history.excludedMonths.isSuperset(of: [7, 8]) }
        set {
            if newValue { history.excludedMonths.formUnion([7, 8]) } else { history.excludedMonths.subtract([7, 8]) }
        }
    }

    // MARK: Scenarios

    var canSaveScenario: Bool { scenarios.count < WhatIfLimits.maxScenarios }

    func saveScenario(named name: String, headline: String) {
        guard canSaveScenario else {
            scenarioNotice = "Maximal \(WhatIfLimits.maxScenarios) Szenarien – lösche eines, um Platz zu schaffen."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scenario = WhatIfScenario(name: trimmed.isEmpty ? defaultName : String(trimmed.prefix(40)),
                                      usesHistory: mode == .history, input: activeInput, savedHeadline: headline)
        var book = WhatIfScenarioBook(scenarios: scenarios)
        book.add(scenario)
        scenarios = book.scenarios
        WhatIfStore.save(book)
        scenarioNotice = "Gespeichert"
    }

    func delete(_ scenario: WhatIfScenario) {
        var book = WhatIfScenarioBook(scenarios: scenarios)
        book.remove(id: scenario.id)
        scenarios = book.scenarios
        WhatIfStore.save(book)
        scenarioNotice = nil
    }

    func load(_ scenario: WhatIfScenario) {
        // A scenario brings its own start date; the start-month menu follows it as far as it can.
        if scenario.usesHistory {
            var input = scenario.input
            input.currentProductID = history.currentProductID
            input.startDate = history.startDate
            history = input
            mode = .history
        } else {
            assumptions = scenario.input
            startOffset = 0
            assumptions.startDate = now
            mode = .assumptions
        }
        scenarioNotice = nil
    }

    /// "Täglich pendeln" when the routes are a preset, else "Szenario 3".
    private var defaultName: String {
        if mode == .assumptions, let preset = WhatIfPreset.all.first(where: { matches($0) }) { return preset.title }
        return mode == .history ? "Meine Fahrten" : "Szenario \(scenarios.count + 1)"
    }
}

// MARK: - Saved scenarios

/// The saved scenarios in UserDefaults (versioned JSON, this device only – never synced).
enum WhatIfStore {
    static let key = "kb.whatif.scenarios.v1"

    static func load(_ defaults: UserDefaults = .standard) -> WhatIfScenarioBook {
        WhatIfScenarioBook.decode(defaults.data(forKey: key))
    }

    static func save(_ book: WhatIfScenarioBook, to defaults: UserDefaults = .standard) {
        guard let data = book.encoded() else { return }
        defaults.set(data, forKey: key)
    }
}
