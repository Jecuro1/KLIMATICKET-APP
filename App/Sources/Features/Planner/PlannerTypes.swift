import SwiftUI
import KlimaCore

// Value types of the Fahrplan: places, options, routes, failures and the result rows (docs/OEBB_LIVE.md §E3).

// MARK: - Places

/// A start, destination or via of a search: an app station (offline index), a live location (address, POI, stop only
/// the planner knows) or „Aktueller Standort“.
enum PlannerPlace: Hashable, Identifiable {
    case station(Station)
    case live(Location)
    case currentLocation

    var id: String {
        switch self {
        case .station(let s): "s:\(s.id)"
        case .live(let l): "l:\(l.lid)"
        case .currentLocation: "here"
        }
    }

    var displayName: DisplayName {
        switch self {
        case .station(let s): DisplayNames.make(s.name)
        case .live(let l): DisplayNames.make(l.name)
        case .currentLocation: DisplayName(raw: "Aktueller Standort", name: "Aktueller Standort")
        }
    }

    var title: String { displayName.name }

    /// „Bahnhof · Tirol“, „Bushaltestelle · Vorarlberg“, „Adresse“.
    var subtitle: String? {
        switch self {
        case .station(let s): s.rowSubtitle
        case .live(let l):
            [displayName.sub, Self.kindText(l)].compactMap { $0 }.joined(separator: " · ").nilIfBlank
        case .currentLocation: nil
        }
    }

    var coordinate: GeoPoint? {
        switch self {
        case .station(let s): s.location
        case .live(let l): l.coordinate
        case .currentLocation: nil
        }
    }

    var symbol: String {
        switch self {
        case .station(let s): s.primaryMode.symbolName
        case .live(let l): l.kind == .address ? "house.fill" : (l.kind == .poi ? "mappin.circle.fill" : "tram.fill")
        case .currentLocation: "location.fill"
        }
    }

    var mode: TransportMode? {
        if case .station(let s) = self { return s.primaryMode }
        return nil
    }

    static func kindText(_ l: Location) -> String? {
        switch l.kind {
        case .address: "Adresse"
        case .poi: "Ort"
        case .station: nil
        }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}

/// What a search field is currently choosing.
enum PlannerSearchTarget: Hashable {
    case origin, destination, via(Int), board

    var prompt: String {
        switch self {
        case .origin: "Von wo?"
        case .destination: "Wohin?"
        case .via: "Über …"
        case .board: "Station suchen"
        }
    }
}

// MARK: - Options

/// The options sheet (UserDefaults `planner.options`, JSON).
struct PlannerOptions: Codable, Equatable {
    /// „Nur mit KlimaTicket gültig“; nil = follow the ticket (on for a KlimaTicket Ö).
    var klimaTicketOnly: Bool? = nil
    var productsRaw: Int = ProductMask.all.rawValue
    /// nil = any, 0 = direct only, 1, 2.
    var maxChanges: Int? = nil
    /// Extra buffer on top of the minimum change time: 0 / 5 / 10 minutes.
    var extraTransferMinutes: Int = 0
    var accessible = false
    var bike = false
    /// Walking limit in metres for each connection; nil = no limit. The planner has no such request option, so the
    /// connections are filtered after the search (`PlannerResults.withinWalk`).
    var maxWalkMeters: Int? = nil
    /// Price class of the prices shown and of a logged trip; nil = the class of the settings.
    var travelClass: TravelClass? = nil
    /// Discount of the prices shown (Vorteilscard); nil = the discount of the settings.
    var discount: FareDiscount? = nil

    var products: ProductMask {
        get { ProductMask(rawValue: productsRaw) }
        set { productsRaw = newValue.rawValue }
    }

    var isDefault: Bool { self == PlannerOptions() }

    /// Whether the options a search sends to ÖBB differ (KlimaTicket filter, products, changes, transfer time, accessibility,
    /// bikes). Only these need a new search; the others filter or price the rows that are there.
    func changesSearch(from other: PlannerOptions) -> Bool {
        klimaTicketOnly != other.klimaTicketOnly || productsRaw != other.productsRaw || maxChanges != other.maxChanges
            || extraTransferMinutes != other.extraTransferMinutes || accessible != other.accessible || bike != other.bike
    }

    /// Whether the price class or the discount differ: the prices of the rows are asked again, the connections are not.
    func changesPrices(from other: PlannerOptions) -> Bool {
        travelClass != other.travelClass || discount != other.discount
    }

    /// Number of non-default settings (badge on the options button).
    func activeCount(klimaTicketDefault: Bool) -> Int {
        var n = 0
        if (klimaTicketOnly ?? klimaTicketDefault) != klimaTicketDefault { n += 1 }
        if productsRaw != ProductMask.all.rawValue { n += 1 }
        if maxChanges != nil { n += 1 }
        if extraTransferMinutes != 0 { n += 1 }
        if accessible { n += 1 }
        if bike { n += 1 }
        if maxWalkMeters != nil { n += 1 }
        if travelClass != nil { n += 1 }
        if discount != nil { n += 1 }
        return n
    }

    /// Product filter that is sent to the planner.
    func effectiveProducts(klimaTicketOnly on: Bool) -> ProductMask {
        on ? products.intersection(.klimaTicket) : products
    }

    private static let key = "planner.options"

    static func load() -> PlannerOptions {
        guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode(PlannerOptions.self, from: data) else {
            return PlannerOptions()
        }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// The vehicle groups of the options sheet.
    enum Group: String, CaseIterable, Identifiable {
        case train, sBahn, bus, tram, subway, other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .train: "Zug"
            case .sBahn: "S-Bahn"
            case .bus: "Bus"
            case .tram: "Tram"
            case .subway: "U-Bahn"
            case .other: "Schiff & Seilbahn"
            }
        }
        var symbol: String {
            switch self {
            case .train: "train.side.front.car"
            case .sBahn: "lightrail"
            case .bus: "bus"
            case .tram: "tram"
            case .subway: "tram.fill.tunnel"
            case .other: "ferry"
            }
        }
        var mask: ProductMask {
            switch self {
            case .train: [.highSpeed, .railReplacement, .intercity, .night, .regional, .westbahn]
            case .sBahn: .suburban
            case .bus: [.bus, .coach]
            case .tram: .tram
            case .subway: .subway
            case .other: [.ship, .onDemand]
            }
        }
    }
}

// MARK: - Routes

/// Pushed screens of the Fahrplan stack.
enum PlannerRoute: Hashable {
    case results
    case detail(String)
}

// MARK: - Failures

/// Planner-side errors (not from the live layer).
enum PlannerError: Error { case noLocation }

/// A `LiveError` as the planner shows it (docs/OEBB_LIVE.md §E3 error table).
enum PlannerFailure: Equatable {
    case offline
    case noConnection
    case rateLimited
    case unreachable
    case tooClose
    case stationNotFound
    case locationUnavailable
    case unavailable(LiveDataService.Unavailable)

    init(_ error: Error) {
        if error is PlannerError { self = .locationUnavailable; return }
        switch error as? LiveError {
        case .offline?: self = .offline
        case .noConnection?: self = .noConnection
        case .rateLimited?, .circuitOpen?: self = .rateLimited
        case .hafas(let code, _)?:
            switch code {
            case "H9380", "H9381": self = .tooClose
            case "LOCATION": self = .stationNotFound
            default: self = .unreachable
            }
        case .disabled?: self = .unavailable(.switchedOff)
        default: self = .unreachable
        }
    }

    /// Worth an automatic retry (backoff 2 / 4 / 8 s, at most 3 tries).
    var isTransient: Bool { self == .unreachable }
}

// MARK: - Result rows

/// One connection of the results list with everything the card shows.
struct ConnectionRow: Identifiable, Equatable {
    var journey: Journey
    var summary: ConnectionSummary
    var badges: [LineBadge]
    var coverage: JourneyCoverage?
    var price: PlannerPriceState
    /// Estimated CO₂ in kg (`PlannerEmissions`), nil without coordinates.
    var co2Kg: Double? = nil

    var id: String { journey.id }

    static func == (a: ConnectionRow, b: ConnectionRow) -> Bool {
        a.journey == b.journey && a.summary == b.summary && a.coverage == b.coverage && a.price == b.price && a.co2Kg == b.co2Kg
    }
}

/// The result sort sees the price the card shows (the regular fare, live or table) and the CO₂ estimate.
extension ConnectionRow: SortableConnection {
    var sortFacts: ConnectionSortFacts {
        PlannerResults.sortFacts(journey, priceEUR: price.quote?.amountEUR)
    }
}

enum PlannerPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(PlannerFailure)
}
