import Foundation

// MARK: uebersicht – own figures on the Übersicht (docs/DASHBOARD_LAYOUT.md §3): up to four tiles out of a catalog of 16. Every value is
// read from what the app already computed for the ticket year (the SavingsSummary of Analytics.make, its records and top routes, the
// week card's count) – the catalog never computes a figure of its own, so a tile always says what Statistik says. Formatting is the
// app's (Format.*); this file only says which number, which unit and whether there is one.

/// The figures one can pick. The raw strings are stored – never rename one.
public enum KpiKind: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case totalValue, net, tripCount, travelDays, distance, co2, averageValue, costPerDay, valuePerDay, pricePerKm,
         carComparison, daysRemaining, forecastEndValue, tripsThisWeek, longestStreak, favoriteRoute

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .totalValue: "Wert deiner Fahrten"
        case .net: "Ersparnis nach Ticketkosten"
        case .tripCount: "Fahrten"
        case .travelDays: "Reisetage"
        case .distance: "Kilometer"
        case .co2: "CO₂ gespart"
        case .averageValue: "Ø Wert je Fahrt"
        case .costPerDay: "Kosten pro Tag"
        case .valuePerDay: "Wert pro Tag"
        case .pricePerKm: "Preis pro km"
        case .carComparison: "Auto-Vergleich"
        case .daysRemaining: "Tage bis Ablauf"
        case .forecastEndValue: "Prognose Endwert"
        case .tripsThisWeek: "Fahrten diese Woche"
        case .longestStreak: "Längste Serie"
        case .favoriteRoute: "Lieblingsstrecke"
        }
    }

    /// One line in the picker: where the number comes from.
    public var explanation: String {
        switch self {
        case .totalValue: "Normalpreise aller Fahrten im Ticketjahr – wie „€ … von € …“ im Gipfel."
        case .net: "Wert minus Ticketpreis. Vor dem Break-even: was noch offen ist."
        case .tripCount: "Eine Reise mit Umstieg zählt einmal – wie in Statistik."
        case .travelDays: "Tage mit mindestens einer Fahrt."
        case .distance: "Alle Kilometer im Ticketjahr, Hin und Rück gezählt."
        case .co2: "Ersparnis gegenüber dem Auto, ca."
        case .averageValue: "Wert deiner Fahrten geteilt durch die Fahrten."
        case .costPerDay: "Ticketpreis geteilt durch die Tage der Gültigkeit."
        case .valuePerDay: "Wert deiner Fahrten geteilt durch die Tage bisher."
        case .pricePerKm: "Ticketpreis geteilt durch deine Kilometer."
        case .carComparison: "Deine Kilometer mal amtliches Kilometergeld."
        case .daysRemaining: "Tage, bis dein Ticket abläuft."
        case .forecastEndValue: "Wert zum Ablauf bei deinem Tempo – eine Prognose."
        case .tripsThisWeek: "Wie die Karte „Diese Woche“."
        case .longestStreak: "Meiste Tage in Folge mit einer Fahrt."
        case .favoriteRoute: "Die Strecke, die du am öftesten fährst."
        }
    }

    public var unit: KpiUnit {
        switch self {
        case .totalValue, .net, .carComparison, .forecastEndValue: .euro
        case .averageValue, .costPerDay, .valuePerDay, .pricePerKm: .euroPrecise
        case .tripCount, .tripsThisWeek: .trips
        case .travelDays, .longestStreak, .daysRemaining: .days
        case .distance: .km
        case .co2: .kg
        case .favoriteRoute: .text
        }
    }

    public var symbol: String {
        switch self {
        case .totalValue: "eurosign.circle.fill"
        case .net: "plus.forwardslash.minus"
        case .tripCount: "tram.fill"
        case .travelDays: "calendar"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .co2: "leaf.fill"
        case .averageValue: "divide.circle.fill"
        case .costPerDay: "ticket.fill"
        case .valuePerDay: "chart.line.uptrend.xyaxis"
        case .pricePerKm: "ruler.fill"
        case .carComparison: "car.fill"
        case .daysRemaining: "hourglass"
        case .forecastEndValue: "chart.line.uptrend.xyaxis.circle"
        case .tripsThisWeek: "calendar.badge.clock"
        case .longestStreak: "flame.fill"
        case .favoriteRoute: "heart.fill"
        }
    }

    /// The tile's second line: „Ticketjahr 2026/27“ for figures of the ticket year, otherwise what the number is about.
    public func subtitle(ticketYear: String) -> String {
        switch self {
        case .daysRemaining: "Gültigkeit"
        case .forecastEndValue: "Prognose · zum Ablauf"
        case .tripsThisWeek: "diese Woche"
        case .carComparison: "mit dem Auto · Ticketjahr \(ticketYear)"
        default: "Ticketjahr \(ticketYear)"
        }
    }
}

/// How the app formats a reading.
public enum KpiUnit: String, Sendable, Hashable {
    /// Whole euros („€ 1.044“).
    case euro
    /// Euros and cents („€ 3,84“).
    case euroPrecise
    /// „12 Fahrten“.
    case trips
    /// „9 Tage“.
    case days
    case km
    case kg
    /// A short text (the favourite route).
    case text
}

/// What the catalog reads – filled by the app from the AnalyticsSnapshot of the Übersicht (one computation for the whole screen).
public struct KpiInput: Equatable, Sendable {
    public var summary: SavingsSummary
    public var longestStreakDays: Int
    /// The most-travelled route of the ticket year (StatsAggregator.topRoutes(…).first).
    public var topRoute: RouteStat?
    /// The count of the card „Diese Woche“; nil when the Übersicht has none.
    public var tripsThisWeek: Int?
    /// „2026/27“.
    public var ticketYear: String

    public init(summary: SavingsSummary, longestStreakDays: Int, topRoute: RouteStat?, tripsThisWeek: Int?, ticketYear: String) {
        self.summary = summary
        self.longestStreakDays = longestStreakDays
        self.topRoute = topRoute
        self.tripsThisWeek = tripsThisWeek
        self.ticketYear = ticketYear
    }

    /// A forecast exists while the ticket runs and there is a pace (like Statistik's dotted line and „Prognose“ label).
    public var hasForecast: Bool { summary.daysRemaining > 0 && summary.tripCount > 0 }
}

/// One tile's content.
public struct KpiReading: Equatable, Sendable, Identifiable {
    public var kind: KpiKind
    /// The figure (nil when there is none yet, or for a text reading).
    public var value: Double?
    /// The text of a text reading (the favourite route).
    public var text: String?
    /// A detail under a text reading („14 Fahrten“).
    public var count: Int?
    public var subtitle: String

    public var id: KpiKind { kind }
    /// No figure yet („–“): no trips for an average, no kilometres for a price per km, no forecast, no route.
    public var isEmpty: Bool { value == nil && text == nil }
}

public enum KpiCatalog {
    /// At most this many tiles on the Übersicht (a 2 × 2 grid).
    public static let maxTiles = 4
    /// What „Zahlen“ and „Alles“ pick when nothing is picked yet.
    public static let defaultTiles: [KpiKind] = [.net, .tripCount, .co2, .costPerDay]

    /// The kinds the picker offers. „Prognose Endwert“ only while there is a forecast.
    public static func offered(for input: KpiInput) -> [KpiKind] {
        KpiKind.allCases.filter { $0 != .forecastEndValue || input.hasForecast }
    }

    /// The reading of `kind` – a value of `input`, never computed anew.
    public static func reading(_ kind: KpiKind, input: KpiInput) -> KpiReading {
        let s = input.summary
        let subtitle = kind.subtitle(ticketYear: input.ticketYear)
        func number(_ value: Double?) -> KpiReading {
            KpiReading(kind: kind, value: value.flatMap { $0.isFinite ? $0 : nil }, text: nil, count: nil, subtitle: subtitle)
        }
        switch kind {
        case .totalValue: return number(s.totalValue)
        case .net: return number(s.net)
        case .tripCount: return number(Double(s.tripCount))
        case .travelDays: return number(Double(s.travelDays))
        case .distance: return number(s.distanceKm)
        case .co2: return number(s.co2SavedKg)
        case .averageValue: return number(s.tripCount > 0 ? s.averageValuePerTrip : nil)
        case .costPerDay: return number(s.costPerDay)
        case .valuePerDay: return number(s.valuePerDay)
        case .pricePerKm: return number(s.effectivePricePerKm)
        case .carComparison: return number(s.carCostEquivalent)
        case .daysRemaining: return number(Double(s.daysRemaining))
        case .forecastEndValue: return number(input.hasForecast ? s.forecastEndValue : nil)
        case .tripsThisWeek: return number(input.tripsThisWeek.map(Double.init))
        case .longestStreak: return number(Double(input.longestStreakDays))
        case .favoriteRoute:
            guard let route = input.topRoute, route.trips > 0 else { return number(nil) }
            return KpiReading(kind: kind, value: nil, text: "\(route.fromName) ↔ \(route.toName)", count: route.trips,
                              subtitle: subtitle)
        }
    }

    public static func readings(_ kinds: [KpiKind], input: KpiInput) -> [KpiReading] {
        KpiSelection.cleaned(kinds).map { reading($0, input: input) }
    }
}

/// The picked tiles, stored under `dash.kpis.v1`.
public struct KpiSelection: Equatable, Sendable {
    public static let storageKey = "dash.kpis.v1"
    public static let currentVersion = 1

    /// At most `KpiCatalog.maxTiles`, no duplicates, in the order they show.
    public private(set) var kinds: [KpiKind]

    public init(_ kinds: [KpiKind] = []) {
        self.kinds = Self.cleaned(kinds)
    }

    public static let empty = KpiSelection()

    public func contains(_ kind: KpiKind) -> Bool { kinds.contains(kind) }
    public var isFull: Bool { kinds.count >= KpiCatalog.maxTiles }

    /// Adds `kind` at the end, or removes it when picked. False when it was not picked and four already are.
    @discardableResult
    public mutating func toggle(_ kind: KpiKind) -> Bool {
        if let index = kinds.firstIndex(of: kind) {
            kinds.remove(at: index)
            return true
        }
        guard !isFull else { return false }
        kinds.append(kind)
        return true
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        kinds = DashLayout.moved(kinds, fromOffsets: source, toOffset: destination)
    }

    static func cleaned(_ kinds: [KpiKind]) -> [KpiKind] {
        var result: [KpiKind] = []
        for kind in kinds where !result.contains(kind) && result.count < KpiCatalog.maxTiles { result.append(kind) }
        return result
    }

    public static func decode(_ data: Data?) -> KpiSelection {
        guard let data, !data.isEmpty, let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let version = stored.version, version >= 1, version <= currentVersion else { return .empty }
        return KpiSelection(stored.kinds.compactMap(KpiKind.init(rawValue:)))
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Stored(version: Self.currentVersion, kinds: kinds.map(\.rawValue)))) ?? Data()
    }

    private struct Stored: Codable {
        var version: Int?
        var kinds: [String]

        init(version: Int?, kinds: [String]) {
            self.version = version
            self.kinds = kinds
        }

        private enum CodingKeys: String, CodingKey { case version, kinds }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            kinds = DashTolerant.strings(c, .kinds)
        }
    }
}
