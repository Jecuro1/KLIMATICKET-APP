import Foundation

// Raw mirrors of the ÖBB ticket shop JSON API (SPEC §B3.3). Every field is optional and tolerant: unknown keys are
// ignored and a field whose JSON type drifted decodes as nil instead of failing the whole response. Only the fields the
// price policy reads are declared. Shop times are Vienna wall clock without an offset ("2026-10-10T08:28:00.000").

/// Localised shop text `{"de": "…", "en": "…", "it": "…"}`; a plain string is accepted too.
public struct ShopText: Codable, Sendable, Hashable {
    public var de: String?
    public var en: String?

    public init(de: String?, en: String? = nil) {
        self.de = de
        self.en = en
    }

    private enum CodingKeys: String, CodingKey { case de, en }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let s = try? single.decode(String.self) {
            de = s
            en = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        de = c.soft(String.self, .de)
        en = c.soft(String.self, .en)
    }

    /// German text, else English.
    public var text: String? { de ?? en }
}

/// One connection of `POST /api/hafas/v4/timetable` (`connections[]`).
public struct ShopConnection: Codable, Sendable, Hashable {
    public struct Stop: Codable, Sendable, Hashable {
        public var name: String?
        /// EVA number (= HAFAS extId) of the stop.
        public var esn: Int?
        public var departure: String?
        public var arrival: String?
        public var departurePlatform: String?
        public var arrivalPlatform: String?

        public init(name: String? = nil, esn: Int? = nil, departure: String? = nil, arrival: String? = nil,
                    departurePlatform: String? = nil, arrivalPlatform: String? = nil) {
            self.name = name
            self.esn = esn
            self.departure = departure
            self.arrival = arrival
            self.departurePlatform = departurePlatform
            self.arrivalPlatform = arrivalPlatform
        }

        private enum CodingKeys: String, CodingKey { case name, esn, departure, arrival, departurePlatform, arrivalPlatform }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.soft(String.self, .name)
            esn = c.softInt(.esn)
            departure = c.soft(String.self, .departure)
            arrival = c.soft(String.self, .arrival)
            departurePlatform = c.softString(.departurePlatform)
            arrivalPlatform = c.softString(.arrivalPlatform)
        }
    }

    public struct Category: Codable, Sendable, Hashable {
        /// "RJX", "IC", "NJ", "s", "Bus" …
        public var name: String?
        /// Train / line number ("19962", "4").
        public var number: String?
        public var displayName: String?
        public var longName: ShopText?
        public var parallelName: String?
        public var parallelNumber: String?
        public var train: Bool?

        public init(name: String? = nil, number: String? = nil, displayName: String? = nil, longName: ShopText? = nil,
                    parallelName: String? = nil, parallelNumber: String? = nil, train: Bool? = nil) {
            self.name = name
            self.number = number
            self.displayName = displayName
            self.longName = longName
            self.parallelName = parallelName
            self.parallelNumber = parallelNumber
            self.train = train
        }

        private enum CodingKeys: String, CodingKey { case name, number, displayName, longName, parallelName, parallelNumber, train }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.soft(String.self, .name)
            number = c.softString(.number)
            displayName = c.soft(String.self, .displayName)
            longName = c.soft(ShopText.self, .longName)
            parallelName = c.soft(String.self, .parallelName)
            parallelNumber = c.softString(.parallelNumber)
            train = c.soft(Bool.self, .train)
        }
    }

    public struct Section: Codable, Sendable, Hashable {
        public var from: Stop?
        public var to: Stop?
        /// Milliseconds.
        public var duration: Double?
        public var category: Category?
        /// "journey", "walk" …
        public var type: String?

        public init(from: Stop? = nil, to: Stop? = nil, duration: Double? = nil, category: Category? = nil, type: String? = nil) {
            self.from = from
            self.to = to
            self.duration = duration
            self.category = category
            self.type = type
        }

        private enum CodingKeys: String, CodingKey { case from, to, duration, category, type }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            from = c.soft(Stop.self, .from)
            to = c.soft(Stop.self, .to)
            duration = c.soft(Double.self, .duration)
            category = c.soft(Category.self, .category)
            type = c.soft(String.self, .type)
        }
    }

    public struct Info: Codable, Sendable, Hashable {
        public var header: String?
        public var text: String?
        public var textPlain: String?

        public init(header: String? = nil, text: String? = nil, textPlain: String? = nil) {
            self.header = header
            self.text = text
            self.textPlain = textPlain
        }

        private enum CodingKeys: String, CodingKey { case header, text, textPlain }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            header = c.soft(String.self, .header)
            text = c.soft(String.self, .text)
            textPlain = c.soft(String.self, .textPlain)
        }
    }

    /// Opaque 64-hex connection id for `offers`.
    public var id: String?
    public var from: Stop?
    public var to: Stop?
    public var sections: [Section]?
    public var switches: Int?
    /// Milliseconds.
    public var duration: Double?
    public var infos: [Info]?

    public init(id: String?, from: Stop? = nil, to: Stop? = nil, sections: [Section]? = nil, switches: Int? = nil,
                duration: Double? = nil, infos: [Info]? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.sections = sections
        self.switches = switches
        self.duration = duration
        self.infos = infos
    }

    private enum CodingKeys: String, CodingKey { case id, from, to, sections, switches, duration, infos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.soft(String.self, .id)
        from = c.soft(Stop.self, .from)
        to = c.soft(Stop.self, .to)
        sections = c.softList(Section.self, .sections)
        switches = c.softInt(.switches)
        duration = c.soft(Double.self, .duration)
        infos = c.softList(Info.self, .infos)
    }

    /// Planned departure (absolute) parsed from the Vienna wall-clock `from.departure`.
    public var departureDate: Date? { ShopTime.date(from?.departure ?? sections?.first?.from?.departure) }
    /// Planned arrival (absolute) parsed from `to.arrival`.
    public var arrivalDate: Date? { ShopTime.date(to?.arrival ?? sections?.last?.to?.arrival) }
    /// Train / line numbers of all sections in order ("19962").
    public var trainNumbers: [String] { (sections ?? []).compactMap { $0.category?.number?.trimmingCharacters(in: .whitespaces).nilIfEmpty } }
    /// Duration in seconds (`duration` ms, else arrival − departure).
    public var durationSeconds: Double? {
        if let d = duration, d > 0 { return d / 1000 }
        guard let a = departureDate, let b = arrivalDate else { return nil }
        return b.timeIntervalSince(a)
    }
}

/// Response of `POST /api/offer/v6/offers` (SPEC §B3.3).
public struct ShopOffers: Codable, Sendable, Hashable {
    public struct Owner: Codable, Sendable, Hashable {
        /// "ÖBB", "VVT", "VOR", "OÖVV" …
        public var nameShort: String?
        public var description: String?

        public init(nameShort: String?, description: String? = nil) {
            self.nameShort = nameShort
            self.description = description
        }

        private enum CodingKeys: String, CodingKey { case nameShort, description }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nameShort = c.soft(String.self, .nameShort)
            description = c.soft(String.self, .description)
        }
    }

    public struct Product: Codable, Sendable, Hashable {
        public var name: ShopText?
        public var price: Double?
        /// "2", "1" or "B".
        public var travelClass: String?
        /// "ONEWAY" (single ticket) or "MULTIPLE" (day / multi-ride ticket).
        public var trafficType: String?
        public var owners: [Owner]?
        public var relevantReductions: [ShopText]?

        public init(name: ShopText?, price: Double? = nil, travelClass: String? = nil, trafficType: String? = nil,
                    owners: [Owner]? = nil, relevantReductions: [ShopText]? = nil) {
            self.name = name
            self.price = price
            self.travelClass = travelClass
            self.trafficType = trafficType
            self.owners = owners
            self.relevantReductions = relevantReductions
        }

        private enum CodingKeys: String, CodingKey {
            case name, price, travelClass = "class", trafficType, owners, relevantReductions
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.soft(ShopText.self, .name)
            price = c.soft(Double.self, .price)
            travelClass = c.softString(.travelClass)
            trafficType = c.soft(String.self, .trafficType)
            owners = c.softList(Owner.self, .owners)
            relevantReductions = c.softList(ShopText.self, .relevantReductions)
        }
    }

    public struct Reservation: Codable, Sendable, Hashable {
        public var price: Double?

        public init(price: Double?) { self.price = price }

        private enum CodingKeys: String, CodingKey { case price }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            price = c.soft(Double.self, .price)
        }
    }

    public struct Offer: Codable, Sendable, Hashable {
        /// `flexibility.de`: "NON-FLEX" (Sparschiene), "SEMI-FLEX", "FLEX" (Standard-Ticket / Verbund ticket).
        public var flexibility: ShopText?
        /// Total for all passengers, EUR.
        public var price: Double?
        public var products: [Product]?
        public var reservation: Reservation?

        public init(flexibility: ShopText?, price: Double?, products: [Product]? = nil, reservation: Reservation? = nil) {
            self.flexibility = flexibility
            self.price = price
            self.products = products
            self.reservation = reservation
        }

        private enum CodingKeys: String, CodingKey { case flexibility, price, products, reservation }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            flexibility = c.soft(ShopText.self, .flexibility)
            price = c.soft(Double.self, .price)
            products = c.softList(Product.self, .products)
            reservation = c.soft(Reservation.self, .reservation)
        }
    }

    public struct TravelClassOffers: Codable, Sendable, Hashable {
        /// "2", "1" or "B" (business).
        public var travelClass: String?
        public var offers: [Offer]?

        public init(travelClass: String?, offers: [Offer]?) {
            self.travelClass = travelClass
            self.offers = offers
        }

        private enum CodingKeys: String, CodingKey { case travelClass = "class", offers }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            travelClass = c.softString(.travelClass)
            offers = c.softList(Offer.self, .offers)
        }
    }

    public struct Section: Codable, Sendable, Hashable {
        public var travelClasses: [TravelClassOffers]?

        public init(travelClasses: [TravelClassOffers]?) { self.travelClasses = travelClasses }

        private enum CodingKeys: String, CodingKey { case travelClasses }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            travelClasses = c.softList(TravelClassOffers.self, .travelClasses)
        }
    }

    /// `true` for departures in the past or connections that cannot be sold.
    public var offerError: Bool?
    public var offerSections: [Section]?

    public init(offerError: Bool?, offerSections: [Section]?) {
        self.offerError = offerError
        self.offerSections = offerSections
    }

    private enum CodingKeys: String, CodingKey { case offerError, offerSections }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offerError = c.soft(Bool.self, .offerError)
        offerSections = c.softList(Section.self, .offerSections)
    }
}

// MARK: - Internal response envelopes

/// `GET /api/domain/v1/anonymousToken`.
struct ShopTokenResponse: Decodable {
    var accessToken: String?
    var expiresIn: Double?

    private enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresIn = "expires_in" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = c.soft(String.self, .accessToken)
        expiresIn = c.soft(Double.self, .expiresIn)
    }
}

/// `POST /api/hafas/v4/timetable` → `{connections[], infos[]}`.
struct ShopTimetableResponse: Decodable {
    var connections: [ShopConnection]?
    var infos: [ShopConnection.Info]?

    private enum CodingKeys: String, CodingKey { case connections, infos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connections = c.softList(ShopConnection.self, .connections)
        infos = c.softList(ShopConnection.Info.self, .infos)
    }
}

/// `GET /api/hafas/v1/stations` element; meta entries have `name: ""`.
struct ShopStationRaw: Decodable {
    var number: Int?
    var name: String?
    var latitude: Int?
    var longitude: Int?

    private enum CodingKeys: String, CodingKey { case number, name, latitude, longitude }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = c.softInt(.number)
        name = c.soft(String.self, .name)
        latitude = c.softInt(.latitude)
        longitude = c.softInt(.longitude)
    }
}

/// Error body `{"error": {"code": 3011, "status": 440, …}}`.
struct ShopErrorResponse: Decodable {
    struct Body: Decodable {
        var code: Int?
        var message: String?

        private enum CodingKeys: String, CodingKey { case code, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = c.softInt(.code)
            message = c.soft(String.self, .message)
        }
    }

    var error: Body?
}

/// Shop wall-clock times: `yyyy-MM-dd'T'HH:mm:ss.SSS`, Europe/Vienna, no offset (SPEC §B3.2: UTC by mistake gives
/// `offerError` everywhere).
enum ShopTime {
    /// "2026-10-10T08:00:00.000" for 08:00 Vienna.
    static func string(_ date: Date) -> String {
        let c = Calendar.vienna.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.000", c.year ?? 1970, c.month ?? 1, c.day ?? 1,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Parses "2026-10-10T08:28:00.000" (also without fraction or seconds) as Vienna wall clock.
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let parts = s.split(separator: "T", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let ymd = parts[0].split(separator: "-").compactMap { Int($0) }
        let timePart = parts[1].split(separator: ".").first ?? ""
        let hms = timePart.split(separator: ":").compactMap { Int($0) }
        guard ymd.count == 3, hms.count >= 2 else { return nil }
        var comps = DateComponents()
        comps.year = ymd[0]
        comps.month = ymd[1]
        comps.day = ymd[2]
        comps.hour = hms[0]
        comps.minute = hms[1]
        comps.second = hms.count > 2 ? hms[2] : 0
        return Calendar.vienna.date(from: comps)
    }
}

// MARK: - Tolerant decoding helpers

extension KeyedDecodingContainer {
    /// Value when present and well-typed, else nil (never throws).
    func soft<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Int from a JSON number or a numeric string.
    func softInt(_ key: Key) -> Int? {
        if let i = soft(Int.self, key) { return i }
        if let d = soft(Double.self, key), d.rounded() == d, abs(d) < 1e15 { return Int(d) }
        if let s = soft(String.self, key) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// String from a JSON string or number.
    func softString(_ key: Key) -> String? {
        if let s = soft(String.self, key) { return s }
        if let i = soft(Int.self, key) { return String(i) }
        return nil
    }

    /// Array whose malformed elements are skipped (instead of failing the whole list).
    func softList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        guard var items = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var out: [T] = []
        while !items.isAtEnd {
            if let v = try? items.decode(T.self) {
                out.append(v)
            } else {
                _ = try? items.decode(SkipValue.self)
            }
        }
        return out
    }
}

/// Consumes one JSON value of any type (used to skip malformed list elements).
private struct SkipValue: Decodable {
    init(from decoder: Decoder) throws {}
}
