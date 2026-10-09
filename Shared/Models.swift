import Foundation
import SwiftData
import KlimaCore

// All persisted enums are stored as raw strings (SwiftData #Predicate cannot filter on enums).
// Every property has a default value so lightweight migration and CloudSync merging stay safe.

@Model
final class TicketEntity {
    var id: UUID = UUID()
    var productID: String = "oe-klassik"
    var name: String = "KlimaTicket Ö Klassik"
    var variantRaw: String = TicketVariant.klassik.rawValue
    var familyRaw: String = TicketFamily.oe.rawValue
    /// Comma separated federal state codes covered (empty = all of Austria).
    var statesRaw: String = ""
    var price: Double = 0
    var startDate: Date = Date()
    var endDate: Date = Date()
    var holderName: String = ""
    var ticketNumber: String = ""
    /// Visual theme of the ticket card (see TicketTheme).
    var themeRaw: String = "aurora"
    /// Reminder offsets in days before expiry, comma separated ("30,7,1").
    var remindersRaw: String = "30,7,1"
    /// Paid in 12 monthly instalments instead of once (KlimaTicket Ö option).
    var isMonthlyPayment: Bool = false
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(productID: String, name: String, variant: TicketVariant, family: TicketFamily, states: [String] = [],
         price: Double, startDate: Date, endDate: Date? = nil, holderName: String = "", ticketNumber: String = "") {
        self.id = UUID()
        self.productID = productID
        self.name = name
        self.variantRaw = variant.rawValue
        self.familyRaw = family.rawValue
        self.statesRaw = states.joined(separator: ",")
        self.price = price
        self.startDate = startDate
        self.endDate = endDate ?? TicketPeriod.standardEnd(for: startDate)
        self.holderName = holderName
        self.ticketNumber = ticketNumber
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var variant: TicketVariant {
        get { TicketVariant(rawValue: variantRaw) ?? .klassik }
        set { variantRaw = newValue.rawValue }
    }

    var family: TicketFamily {
        get { TicketFamily(rawValue: familyRaw) ?? .oe }
        set { familyRaw = newValue.rawValue }
    }

    var states: [String] {
        get { statesRaw.split(separator: ",").map(String.init) }
        set { statesRaw = newValue.joined(separator: ",") }
    }

    var reminderOffsets: [Int] {
        get { remindersRaw.split(separator: ",").compactMap { Int($0) } }
        set { remindersRaw = newValue.map(String.init).joined(separator: ",") }
    }

    var period: TicketPeriod {
        TicketPeriod(productID: productID, name: name, price: price, start: startDate, end: endDate)
    }

    var isActive: Bool { period.contains(Date()) }

    /// Amount paid so far (monthly instalments are due at the start of each validity month).
    func paidSoFar(now: Date = Date()) -> Double {
        guard isMonthlyPayment else { return price }
        let cal = Calendar.vienna
        let months = (cal.dateComponents([.month], from: cal.startOfDay(for: startDate), to: min(now, endDate)).month ?? 0) + 1
        return price / 12 * Double(min(max(months, 1), 12))
    }
    var isExpired: Bool { Date() > endDate }
    var isTrashed: Bool { deletedAt != nil }

    func touch() { updatedAt = Date() }
}

@Model
final class TripEntity {
    var id: UUID = UUID()
    var date: Date = Date()
    var fromName: String = ""
    var toName: String = ""
    var fromStationID: String?
    var toStationID: String?
    var modeRaw: String = TransportMode.train.rawValue
    /// One direction, km.
    var distanceKm: Double = 0
    /// Regular fare for one direction and one person, EUR.
    var fareEUR: Double = 0
    /// True when the user overrode the estimated fare.
    var isFareManual: Bool = false
    var isRoundTrip: Bool = false
    var travelClassRaw: String = TravelClass.second.rawValue
    var companions: Int = 0
    /// Comma separated federal state codes touched by the trip.
    var statesRaw: String = ""
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(date: Date, fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil,
         mode: TransportMode, distanceKm: Double, fareEUR: Double, isFareManual: Bool = false, isRoundTrip: Bool = false,
         travelClass: TravelClass = .second, companions: Int = 0, states: [String] = [], note: String = "") {
        self.id = UUID()
        self.date = date
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.modeRaw = mode.rawValue
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.isFareManual = isFareManual
        self.isRoundTrip = isRoundTrip
        self.travelClassRaw = travelClass.rawValue
        self.companions = companions
        self.statesRaw = states.joined(separator: ",")
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var mode: TransportMode {
        get { TransportMode(rawValue: modeRaw) ?? .train }
        set { modeRaw = newValue.rawValue }
    }

    var travelClass: TravelClass {
        get { TravelClass(rawValue: travelClassRaw) ?? .second }
        set { travelClassRaw = newValue.rawValue }
    }

    var states: [String] {
        get { statesRaw.split(separator: ",").map(String.init) }
        set { statesRaw = newValue.joined(separator: ",") }
    }

    var totalValue: Double { fareEUR * (isRoundTrip ? 2 : 1) }
    var totalDistanceKm: Double { distanceKm * (isRoundTrip ? 2 : 1) }
    var isTrashed: Bool { deletedAt != nil }

    var record: TripRecord {
        TripRecord(id: id, date: date, fromName: fromName, toName: toName, fromStationID: fromStationID, toStationID: toStationID,
                   mode: mode, distanceKm: distanceKm, fareEUR: fareEUR, isRoundTrip: isRoundTrip, companions: companions,
                   states: Set(states))
    }

    func touch() { updatedAt = Date() }
}

@Model
final class FavoriteRouteEntity {
    var id: UUID = UUID()
    var title: String = ""
    var fromName: String = ""
    var toName: String = ""
    var fromStationID: String?
    var toStationID: String?
    var modeRaw: String = TransportMode.train.rawValue
    var distanceKm: Double = 0
    var fareEUR: Double = 0
    var isRoundTrip: Bool = false
    var statesRaw: String = ""
    var sortIndex: Int = 0
    var usageCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(title: String = "", fromName: String, toName: String, fromStationID: String? = nil, toStationID: String? = nil,
         mode: TransportMode, distanceKm: Double, fareEUR: Double, isRoundTrip: Bool = false, states: [String] = [], sortIndex: Int = 0) {
        self.id = UUID()
        self.title = title
        self.fromName = fromName
        self.toName = toName
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.modeRaw = mode.rawValue
        self.distanceKm = distanceKm
        self.fareEUR = fareEUR
        self.isRoundTrip = isRoundTrip
        self.statesRaw = states.joined(separator: ",")
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var mode: TransportMode {
        get { TransportMode(rawValue: modeRaw) ?? .train }
        set { modeRaw = newValue.rawValue }
    }

    var states: [String] {
        get { statesRaw.split(separator: ",").map(String.init) }
        set { statesRaw = newValue.joined(separator: ",") }
    }

    var displayTitle: String { title.isEmpty ? "\(fromName) – \(toName)" : title }
    var isTrashed: Bool { deletedAt != nil }

    /// Creates a new trip entity from this favourite for the given date.
    func makeTrip(on date: Date = Date()) -> TripEntity {
        TripEntity(date: date, fromName: fromName, toName: toName, fromStationID: fromStationID, toStationID: toStationID,
                   mode: mode, distanceKm: distanceKm, fareEUR: fareEUR, isRoundTrip: isRoundTrip, states: states)
    }

    func touch() { updatedAt = Date() }
}

enum DataSchema {
    static let models: [any PersistentModel.Type] = [TicketEntity.self, TripEntity.self, FavoriteRouteEntity.self]

    /// Persistent container in the App Group (shared with widgets) when available, otherwise the app sandbox.
    /// Falls back to in-memory storage if the store cannot be opened, so the app never crashes on launch.
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        if inMemory {
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        let storeURL: URL
        if let group = AppGroup.containerURL {
            storeURL = group.appending(path: "KlimaBilanz.store")
        } else {
            let support = URL.applicationSupportDirectory
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            storeURL = support.appending(path: "KlimaBilanz.store")
        }
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
        } catch {
            print("⚠️ ModelContainer failed: \(error) – using in-memory store")
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }
}
