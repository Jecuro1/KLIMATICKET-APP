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
    var themeRaw: String = "twilight"
    /// Reminder offsets in days before expiry, comma separated ("30,7,1").
    var remindersRaw: String = "30,7,1"
    /// Paid in 12 monthly instalments instead of once (KlimaTicket Ö option).
    var isMonthlyPayment: Bool = false
    /// Renews automatically (SEPA direct debit) unless the holder objects before the deadline in the renewal letter.
    var autoRenews: Bool = false
    /// Amount the employer pays (Jobticket / Zuschuss); the payoff is measured against the holder's own share.
    var employerContribution: Double = 0
    /// Price of add-ons bought for this ticket year (e.g. ÖBB 1st-class upgrade, Vorteilsabo), EUR.
    var addOnPrice: Double = 0
    /// Comma separated add-on identifiers ("firstClass", "vorteilsabo", "business").
    var addOnsRaw: String = ""
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

    /// The payoff is measured against what the holder actually paid (own share incl. add-ons).
    var period: TicketPeriod {
        TicketPeriod(productID: productID, name: name, price: ownShare, start: startDate, end: endDate)
    }

    var isActive: Bool { period.contains(Date()) }
    /// What the holder paid themselves (price + add-ons − employer contribution, never negative).
    var ownShare: Double { max(0, price + addOnPrice - employerContribution) }
    var addOns: [String] {
        get { addOnsRaw.split(separator: ",").map(String.init) }
        set { addOnsRaw = newValue.joined(separator: ",") }
    }

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
    /// TripCategory raw value; empty = not categorised.
    var categoryRaw: String = ""
    /// "Ohne Ticket wäre ich nicht gefahren" – counted as extra value, shown separately from money actually saved.
    var isInduced: Bool = false
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

    var category: TripCategory? {
        get { categoryRaw.isEmpty ? nil : TripCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }

    var totalValue: Double { fareEUR * (isRoundTrip ? 2 : 1) }
    var totalDistanceKm: Double { distanceKm * (isRoundTrip ? 2 : 1) }
    var isTrashed: Bool { deletedAt != nil }

    var record: TripRecord {
        TripRecord(id: id, date: date, fromName: fromName, toName: toName, fromStationID: fromStationID, toStationID: toStationID,
                   mode: mode, distanceKm: distanceKm, fareEUR: fareEUR, isRoundTrip: isRoundTrip, companions: companions,
                   states: Set(states), category: category, isInduced: isInduced)
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
    /// TripCategory raw value applied to trips logged from this favourite; empty = none.
    var categoryRaw: String = ""
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
        let trip = TripEntity(date: date, fromName: fromName, toName: toName, fromStationID: fromStationID, toStationID: toStationID,
                              mode: mode, distanceKm: distanceKm, fareEUR: fareEUR, isRoundTrip: isRoundTrip, states: states)
        trip.categoryRaw = categoryRaw
        return trip
    }

    func touch() { updatedAt = Date() }
}

/// A used KlimaTicket holder benefit ("Vorteilswelt": CAT −50 %, nextbike, museums, cable cars …).
/// Shown as "Zusatz-Ersparnis", always separate from the trip-based payoff.
@Model
final class BenefitEntity {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Catalogue id (see BenefitCatalog) or "custom".
    var partnerID: String = "custom"
    var title: String = ""
    /// Money saved thanks to the benefit, EUR.
    var savedEUR: Double = 0
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(date: Date = Date(), partnerID: String = "custom", title: String, savedEUR: Double, note: String = "") {
        self.id = UUID()
        self.date = date
        self.partnerID = partnerID
        self.title = title
        self.savedEUR = savedEUR
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isTrashed: Bool { deletedAt != nil }
    func touch() { updatedAt = Date() }
}

enum DataSchema {
    static let models: [any PersistentModel.Type] = [TicketEntity.self, TripEntity.self, FavoriteRouteEntity.self, BenefitEntity.self]
    static let storeName = "KlimaBilanz.store"

    /// The persistent store: in the App Group container (shared with widgets) when available, otherwise in the app
    /// sandbox's Application Support.
    static var storeURL: URL {
        if let group = AppGroup.containerURL { return group.appending(path: storeName) }
        let support = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appending(path: storeName)
    }

    /// Opens the persistent store. Throws instead of falling back to memory: an in-memory store would show an empty
    /// app (onboarding, "Noch kein Ticket") and silently drop everything entered. The app target retries and shows a
    /// recovery screen (StoreLoader); nothing may write before this succeeded.
    @MainActor
    static func openPersistentContainer() throws -> ModelContainer {
        let schema = Schema(models)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
    }

    /// Throwaway store for CI screenshots and previews only – never for real user data.
    @MainActor
    static func makeInMemoryContainer() -> ModelContainer {
        let schema = Schema(models)
        // An in-memory SQLite store has no file, no migration and no data protection – it cannot fail to open.
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                                                  groupContainer: .none, cloudKitDatabase: .none)])
    }
}
