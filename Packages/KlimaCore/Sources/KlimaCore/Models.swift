import Foundation

// MARK: - Transport

/// Verkehrsmittel einer Fahrt. Raw values are persisted (SwiftData + Cloud) – never rename them.
public enum TransportMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case train      // Fern-/Regionalzug (RJ, RJX, IC, REX, R, Westbahn)
    case sBahn      // S-Bahn
    case metro      // U-Bahn
    case tram       // Straßenbahn / Bim
    case bus        // Stadt- & Regionalbus, Postbus
    case ferry      // Schiff (z. B. Bodensee, Wolfgangsee)
    case cableCar   // Seilbahn / Standseilbahn
    case other

    public var id: String { rawValue }

    /// German display name.
    public var displayName: String {
        switch self {
        case .train: "Zug"
        case .sBahn: "S-Bahn"
        case .metro: "U-Bahn"
        case .tram: "Bim"
        case .bus: "Bus"
        case .ferry: "Schiff"
        case .cableCar: "Seilbahn"
        case .other: "Sonstiges"
        }
    }

    /// SF Symbol name used throughout the app.
    public var symbolName: String {
        switch self {
        case .train: "train.side.front.car"
        case .sBahn: "lightrail"
        case .metro: "tram.fill.tunnel"
        case .tram: "tram"
        case .bus: "bus"
        case .ferry: "ferry"
        case .cableCar: "cablecar"
        case .other: "figure.walk"
        }
    }

    /// Urban modes are priced with a city single ticket when the trip is short.
    public var isUrban: Bool {
        switch self {
        case .metro, .tram: true
        default: false
        }
    }
}

public enum TravelClass: String, Codable, CaseIterable, Sendable, Identifiable {
    case second
    case first

    public var id: String { rawValue }
    public var displayName: String { self == .second ? "2. Klasse" : "1. Klasse" }
}

/// Discount card the user would otherwise use. Used to value trips realistically.
public enum FareDiscount: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case vorteilscard

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .none: "Ohne Ermäßigung"
        case .vorteilscard: "Mit Vorteilscard"
        }
    }
}

// MARK: - Geo

public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in kilometres (haversine).
    public func distanceKm(to other: GeoPoint) -> Double {
        let r = 6371.0088
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Austrian federal states (plus foreign) as used by the bundled station list.
public enum FederalState: String, Codable, CaseIterable, Sendable, Identifiable {
    case wien = "W"
    case niederoesterreich = "NÖ"
    case oberoesterreich = "OÖ"
    case salzburg = "S"
    case tirol = "T"
    case vorarlberg = "V"
    case kaernten = "K"
    case steiermark = "ST"
    case burgenland = "B"
    case foreign = "X"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wien: "Wien"
        case .niederoesterreich: "Niederösterreich"
        case .oberoesterreich: "Oberösterreich"
        case .salzburg: "Salzburg"
        case .tirol: "Tirol"
        case .vorarlberg: "Vorarlberg"
        case .kaernten: "Kärnten"
        case .steiermark: "Steiermark"
        case .burgenland: "Burgenland"
        case .foreign: "Ausland"
        }
    }
}

public struct Station: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case rail
        case metro
        case tramHub = "tram_hub"
    }

    public var id: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var state: String
    public var kind: Kind
    public var importance: Int
    /// Alternative spellings used in search ("Innsbruck Hbf", "St.Pölten Hbf", "Linz/Donau Hauptbahnhof").
    public var aliases: [String]?

    public init(id: String, name: String, lat: Double, lon: Double, state: String, kind: Kind = .rail, importance: Int = 0, aliases: [String]? = nil) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.state = state
        self.kind = kind
        self.importance = importance
        self.aliases = aliases
    }

    public var location: GeoPoint { GeoPoint(latitude: lat, longitude: lon) }
    public var federalState: FederalState? { FederalState(rawValue: state) }
}

// MARK: - Tickets

public enum TicketFamily: String, Codable, Sendable {
    case oe        // KlimaTicket Ö (österreichweit)
    case regional  // KlimaTicket einzelner Bundesländer / Verbünde
    case custom    // Benutzerdefiniert
}

public enum TicketVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case klassik
    case jugend
    case senior
    case spezial
    case familie

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .klassik: "Klassik"
        case .jugend: "Jugend"
        case .senior: "Senior"
        case .spezial: "Spezial"
        case .familie: "Familie"
        }
    }
}

/// A purchasable ticket product from the tariff catalog (e.g. "KlimaTicket Ö Klassik").
public struct TicketProduct: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var family: TicketFamily
    /// Federal states covered by a regional product. Empty for KlimaTicket Ö (= all of Austria).
    public var states: [String]
    public var name: String
    public var variant: TicketVariant
    public var priceEUR: Double
    public var validFrom: String
    public var eligibility: String
    public var coverage: String
    public var sourceUrl: String?
    /// Earlier prices (by ticket start date), oldest first. The current `priceEUR` applies from `validFrom`.
    public var priceHistory: [PricePoint]?
    /// Covers only part of the listed states (e.g. "KlimaTicket Innsbruck") – excluded from the ticket comparison.
    public var isLocal: Bool?

    public struct PricePoint: Codable, Hashable, Sendable {
        public var validFrom: String
        public var priceEUR: Double

        public init(validFrom: String, priceEUR: Double) {
            self.validFrom = validFrom
            self.priceEUR = priceEUR
        }
    }

    public init(id: String, family: TicketFamily, states: [String] = [], name: String, variant: TicketVariant,
                priceEUR: Double, validFrom: String, eligibility: String = "", coverage: String = "", sourceUrl: String? = nil,
                priceHistory: [PricePoint]? = nil, isLocal: Bool? = nil) {
        self.id = id
        self.family = family
        self.states = states
        self.name = name
        self.variant = variant
        self.priceEUR = priceEUR
        self.validFrom = validFrom
        self.eligibility = eligibility
        self.coverage = coverage
        self.sourceUrl = sourceUrl
        self.priceHistory = priceHistory
        self.isLocal = isLocal
    }

    /// Price for a ticket whose validity starts on `start` (KlimaTicket prices depend on the start date).
    public func price(forStart start: Date, calendar: Calendar = .vienna) -> Double {
        let points = (priceHistory ?? []) + [PricePoint(validFrom: validFrom, priceEUR: priceEUR)]
        let day = TicketProduct.isoDay(start, calendar: calendar)
        let applicable = points.filter { $0.validFrom <= day }.max { $0.validFrom < $1.validFrom }
        return applicable?.priceEUR ?? points.min { $0.validFrom < $1.validFrom }?.priceEUR ?? priceEUR
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether a trip touching the given federal states is covered by this product.
    public func covers(states tripStates: Set<String>) -> Bool {
        if family == .oe { return !tripStates.contains(FederalState.foreign.rawValue) }
        guard !states.isEmpty else { return false }
        return tripStates.isSubset(of: Set(states))
    }
}

/// Value-type snapshot of a user's ticket used for all calculations.
public struct TicketPeriod: Hashable, Sendable {
    public var productID: String
    public var name: String
    public var price: Double
    public var start: Date
    public var end: Date

    public init(productID: String, name: String, price: Double, start: Date, end: Date) {
        self.productID = productID
        self.name = name
        self.price = price
        self.start = start
        self.end = end
    }

    /// Standard KlimaTicket validity: 365 days (366 if the period contains 29 Feb) — ends the day before the anniversary.
    public static func standardEnd(for start: Date, calendar: Calendar = .vienna) -> Date {
        let anniversary = calendar.date(byAdding: .year, value: 1, to: calendar.startOfDay(for: start)) ?? start
        return calendar.date(byAdding: .second, value: -1, to: anniversary) ?? anniversary
    }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

// MARK: - Trips

/// Value-type snapshot of a logged trip used for all calculations.
/// Why a trip was made. Drives filters, statistics per purpose and the work/tax overview.
public enum TripCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case commute      // Arbeitsweg
    case business     // Dienstreise
    case education    // Schule / Uni / Ausbildung
    case leisure      // Freizeit / Ausflug
    case holiday      // Urlaub
    case visit        // Besuch (Familie, Freunde)
    case errand       // Erledigung / Einkauf / Arzt
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .commute: "Arbeitsweg"
        case .business: "Dienstreise"
        case .education: "Ausbildung"
        case .leisure: "Freizeit"
        case .holiday: "Urlaub"
        case .visit: "Besuch"
        case .errand: "Erledigung"
        case .other: "Sonstiges"
        }
    }

    public var symbolName: String {
        switch self {
        case .commute: "briefcase.fill"
        case .business: "suitcase.rolling.fill"
        case .education: "graduationcap.fill"
        case .leisure: "mountain.2.fill"
        case .holiday: "sun.max.fill"
        case .visit: "house.fill"
        case .errand: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Work-related purposes (shown in "Arbeit & Steuer").
    public var isWorkRelated: Bool { self == .commute || self == .business }
}

public struct TripRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var fromName: String
    public var toName: String
    public var fromStationID: String?
    public var toStationID: String?
    public var mode: TransportMode
    /// Distance of ONE direction in km.
    public var distanceKm: Double
    /// Regular fare for ONE direction and ONE person (what it would have cost without the KlimaTicket).
    public var fareEUR: Double
    public var isRoundTrip: Bool
    /// Additional people travelling on the same ticket (e.g. children on KlimaTicket Familie). Not valued by default.
    public var companions: Int
    public var states: Set<String>
    /// Purpose of the trip; nil = not categorised.
    public var category: TripCategory?
    /// "Ohne Ticket wäre ich nicht gefahren" – the trip was induced by the flat-rate ticket (counts as extra value, not as money saved).
    public var isInduced: Bool

    public init(id: UUID = UUID(), date: Date, fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil,
                mode: TransportMode, distanceKm: Double, fareEUR: Double, isRoundTrip: Bool = false, companions: Int = 0, states: Set<String> = [],
                category: TripCategory? = nil, isInduced: Bool = false) {
        self.id = id
        self.date = date
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.mode = mode
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.isRoundTrip = isRoundTrip
        self.companions = companions
        self.states = states
        self.category = category
        self.isInduced = isInduced
    }

    public var legs: Int { isRoundTrip ? 2 : 1 }
    /// Total value of this entry (all legs).
    public var totalValue: Double { fareEUR * Double(legs) }
    /// Total distance of this entry (all legs).
    public var totalDistanceKm: Double { distanceKm * Double(legs) }
    /// Direction-independent route key, e.g. "innsbruck hbf|st. anton am arlberg".
    public var routeKey: String {
        let a = fromName.lowercased(), b = toName.lowercased()
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

public extension Calendar {
    /// Gregorian calendar in Europe/Vienna, Monday-first – used for all date math.
    static var vienna: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        cal.locale = Locale(identifier: "de_AT")
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }
}
