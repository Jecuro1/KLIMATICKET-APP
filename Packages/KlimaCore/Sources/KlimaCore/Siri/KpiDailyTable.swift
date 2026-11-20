import Foundation

// MARK: siri – „Fragen an KlimaBilanz“ (docs/SIRI_QUESTIONS.md). Siri and the Kurzbefehle-App answer from this table, never from the
// SwiftData store: the app writes it into the App Group after every save and whenever it refreshes the widgets, an intent only reads
// it. It holds sums per day and the ticket year's figures – no trips, no stations, no places.

/// The figures a question is answered from: the ticket year as Statistik shows it (SavingsSummary) and one row per Vienna day with
/// at least one trip in the last `dayWindow` days.
public struct KpiDailyTable: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Days kept: „Kalenderjahr“ reaches back at most 366 days, „letzter Monat“ at most 62.
    public static let dayWindow = 400
    /// After this the answer adds „Stand …“ and asks to open the app.
    public static let staleAfter: TimeInterval = 24 * 60 * 60

    /// The ticket year of the app's active ticket (the one the Übersicht shows), straight from its SavingsSummary.
    public struct Ticket: Codable, Equatable, Sendable {
        public var name: String
        public var start: Date
        public var end: Date
        /// The own share (price + add-ons − employer contribution) – what Statistik measures against.
        public var price: Double
        public var tripCount: Int
        public var totalValue: Double
        public var distanceKm: Double
        public var co2SavedKg: Double
        public var paidOffDate: Date?
        public var forecastBreakEvenDate: Date?
        public var forecastReachesBreakEven: Bool

        public init(name: String, start: Date, end: Date, price: Double, tripCount: Int, totalValue: Double, distanceKm: Double,
                    co2SavedKg: Double, paidOffDate: Date? = nil, forecastBreakEvenDate: Date? = nil, forecastReachesBreakEven: Bool = false) {
            self.name = name
            self.start = start
            self.end = end
            self.price = price
            self.tripCount = tripCount
            self.totalValue = totalValue
            self.distanceKm = distanceKm
            self.co2SavedKg = co2SavedKg
            self.paidOffDate = paidOffDate
            self.forecastBreakEvenDate = forecastBreakEvenDate
            self.forecastReachesBreakEven = forecastReachesBreakEven
        }

        public var period: TicketPeriod { TicketPeriod(productID: "", name: name, price: price, start: start, end: end) }
        public var isPaidOff: Bool { totalValue >= price }
        public var net: Double { totalValue - price }
        public var remainingToBreakEven: Double { max(0, price - totalValue) }
    }

    /// One Vienna calendar day with trips.
    public struct Day: Codable, Equatable, Sendable {
        /// „2026-10-25“ (Vienna time) – sorts like the day itself.
        public var day: String
        /// Fahrten: a journey (Bus → Zug → Bim) counts once, on the day of its first leg.
        public var journeys: Int
        /// Normal fares of the day's trips (Hin und Rück counted).
        public var value: Double
        public var km: Double
        public var co2: Double

        public init(day: String, journeys: Int, value: Double, km: Double, co2: Double) {
            self.day = day
            self.journeys = journeys
            self.value = value
            self.km = km
            self.co2 = co2
        }
    }

    public var version: Int
    public var generatedAt: Date
    /// Look & Feel › Zahlen: the week start for „diese Woche“, amounts and the CO₂ unit of the written figure.
    public var format: FormatPrefs
    public var ticket: Ticket?
    /// Ascending by `day`, only days with at least one trip.
    public var days: [Day]

    public init(generatedAt: Date, format: FormatPrefs = .standard, ticket: Ticket?, days: [Day]) {
        version = Self.currentVersion
        self.generatedAt = generatedAt
        self.format = format
        self.ticket = ticket
        self.days = days.sorted { $0.day < $1.day }
    }

    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(generatedAt) > Self.staleAfter }

    /// The same content, ignoring when it was written (the writer skips a write that would change nothing).
    public func hasSameFigures(as other: KpiDailyTable) -> Bool {
        format == other.format && ticket == other.ticket && days == other.days
    }

    // MARK: Days

    /// Sums of the days `first ... last` (day keys, inclusive).
    public func sum(from first: String, through last: String) -> Day {
        var total = Day(day: first, journeys: 0, value: 0, km: 0, co2: 0)
        for day in days where day.day >= first && day.day <= last {
            total.journeys += day.journeys
            total.value += day.value
            total.km += day.km
            total.co2 += day.co2
        }
        return total
    }

    /// The oldest day the table can hold a row for (`dayWindow` days up to the day it was written) – older days are not in it,
    /// whether there were trips or not. MARK: review-siri
    public func firstCoveredDay(calendar: Calendar = .vienna) -> String {
        let written = calendar.startOfDay(for: generatedAt)
        return Self.dayKey(calendar.date(byAdding: .day, value: -(Self.dayWindow - 1), to: written) ?? written, calendar: calendar)
    }

    /// „2026-10-25“ for `date` in `calendar` (Vienna by default).
    public static func dayKey(_ date: Date, calendar: Calendar = .vienna) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return dayKey(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    public static func dayKey(year: Int, month: Int, day: Int) -> String {
        let y = String(year), m = String(month), d = String(day)
        return String(repeating: "0", count: max(0, 4 - y.count)) + y + "-" + (m.count < 2 ? "0" + m : m) + "-" + (d.count < 2 ? "0" + d : d)
    }

    /// (year, month, day) of a well-formed key, nil for anything else.
    public static func parse(dayKey key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (y, m, d)
    }

    // MARK: JSON

    /// The file's bytes (ISO dates would drop the sub-seconds; the default keeps a round trip exact).
    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// nil for anything that is not a table (garbage, an empty file, a table without its time stamp).
    public static func decode(_ data: Data) -> KpiDailyTable? {
        try? JSONDecoder().decode(KpiDailyTable.self, from: data)
    }

    // Tolerant decoding: a bad field becomes its default and a bad day row is dropped; only a missing time stamp fails (an
    // answer could not tell how old it is).
    private enum CodingKeys: String, CodingKey { case version, generatedAt, format, ticket, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        format = (try? c.decodeIfPresent(FormatPrefs.self, forKey: .format)) ?? .standard
        let decodedTicket: Ticket? = (try? c.decodeIfPresent(Ticket.self, forKey: .ticket)) ?? nil
        ticket = decodedTicket.flatMap { $0.isUsable ? $0 : nil }
        let rows = (try? c.decodeIfPresent([KpiLenient<Day>].self, forKey: .days)) ?? []
        var seen = Set<String>()
        days = rows.compactMap(\.value)
            .filter { $0.isUsable && seen.insert($0.day).inserted }
            .sorted { $0.day < $1.day }
    }
}

extension KpiDailyTable.Day {
    var isUsable: Bool {
        KpiDailyTable.parse(dayKey: day) != nil && journeys >= 0
            && [value, km, co2].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

extension KpiDailyTable.Ticket {
    var isUsable: Bool {
        end >= start && tripCount >= 0 && [price, totalValue, distanceKm, co2SavedKg].allSatisfy(\.isFinite)
    }
}

/// One element of an array that may fail on its own without failing the array.
private struct KpiLenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
