import Foundation
import SwiftData
import KlimaCore

/// State + logic of the add/edit trip sheet. UI-agnostic: `TripEditorView` binds to it.
@Observable
@MainActor
final class TripEditorModel {
    enum Endpoint { case from, to }

    // Route
    var fromStation: Station?
    var toStation: Station?
    /// Free-text names when no bundled station matches (e.g. a bus stop).
    var fromName: String = ""
    var toName: String = ""

    // Details
    var mode: TransportMode = .train
    var date: Date = Date()
    var isRoundTrip: Bool = false
    var travelClass: TravelClass = .second
    var discount: FareDiscount = .none
    var companions: Int = 0
    var note: String = ""
    var saveAsFavorite: Bool = false

    // Purpose & honest balance (see MetaTripPurposeSection)
    /// Why the trip was made; nil = not categorised.
    var category: TripCategory?
    /// "Ohne KlimaTicket wäre ich nicht gefahren" – counted as extra value, not as money saved.
    var isInduced: Bool = false
    /// Where a preselected category came from (nil = chosen by the user, or none).
    var categorySource: MetaCategorySource?
    /// The user picked or cleared the category – suggestions never overwrite that choice.
    var categoryWasChosen = false

    // Price
    var manualFare: Double?
    var manualDistanceKm: Double?
    private(set) var estimate: FareEstimate?

    private(set) var editingTrip: TripEntity?
    let app: AppState

    init(app: AppState, draft: TripDraft, editing trip: TripEntity?) {
        self.app = app
        discount = app.settings.defaultDiscount
        travelClass = app.settings.defaultTravelClass
        if let trip {
            editingTrip = trip
            fromStation = trip.fromStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: trip.fromName)
            toStation = trip.toStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: trip.toName)
            fromName = trip.fromName
            toName = trip.toName
            mode = trip.mode
            date = trip.date
            isRoundTrip = trip.isRoundTrip
            travelClass = trip.travelClass
            companions = trip.companions
            note = trip.note
            category = trip.category
            isInduced = trip.isInduced
            // Editing never re-categorises silently.
            categoryWasChosen = true
            if trip.isFareManual { manualFare = trip.fareEUR }
            if fromStation == nil || toStation == nil { manualDistanceKm = trip.distanceKm }
        } else {
            fromStation = draft.fromStationID.flatMap(app.stations.station(id:))
                ?? (draft.fromName.isEmpty ? nil : app.stations.station(named: draft.fromName))
                ?? (draft.fromName.isEmpty ? app.settings.homeStationID.flatMap(app.stations.station(id:)) : nil)
            toStation = draft.toStationID.flatMap(app.stations.station(id:))
                ?? (draft.toName.isEmpty ? nil : app.stations.station(named: draft.toName))
            fromName = fromStation?.name ?? draft.fromName
            toName = toStation?.name ?? draft.toName
            mode = draft.mode
            date = draft.date
            isRoundTrip = draft.isRoundTrip
            // MARK: dashboardTicket – „Bearbeiten & erfassen“ of a favourite: same as picking it in the favourites row.
            if let favorite = draft.favorite, favorite.deletedAt == nil {
                apply(favorite: favorite)
            }
        }
        recompute()
    }

    var isEditing: Bool { editingTrip != nil }
    var title: String { isEditing ? "Fahrt bearbeiten" : "Neue Fahrt" }

    var resolvedFromName: String { fromStation?.name ?? fromName.trimmingCharacters(in: .whitespaces) }
    var resolvedToName: String { toStation?.name ?? toName.trimmingCharacters(in: .whitespaces) }

    /// Fare for one direction (manual override wins).
    var fare: Double { manualFare ?? estimate?.fareEUR ?? 0 }
    var distanceKm: Double { manualDistanceKm ?? estimate?.distanceKm ?? 0 }
    var totalValue: Double { fare * (isRoundTrip ? 2 : 1) }
    var isFareManual: Bool { manualFare != nil }

    var canSave: Bool {
        !resolvedFromName.isEmpty && !resolvedToName.isEmpty && resolvedFromName != resolvedToName && fare > 0
    }

    var validationHint: String? {
        if resolvedFromName.isEmpty || resolvedToName.isEmpty { return "Wähle Start und Ziel." }
        if resolvedFromName == resolvedToName { return "Start und Ziel sind gleich." }
        if fare <= 0 { return "Gib einen Normalpreis ein." }
        return nil
    }

    /// Short explanation under the price ("ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025").
    var fareExplanation: String {
        if isFareManual { return "Eigener Preis" }
        if let e = estimate { return e.explanation }
        return "Preis wird nach Wahl von Start und Ziel geschätzt"
    }

    var isOfficialPrice: Bool { !isFareManual && estimate?.method == .officialTable }

    /// Federal states touched (for regional ticket comparison).
    var states: [String] {
        Array(Set([fromStation?.state, toStation?.state].compactMap { $0 })).sorted()
    }

    // MARK: Actions

    func setStation(_ station: Station, for endpoint: Endpoint) {
        switch endpoint {
        case .from:
            fromStation = station
            fromName = station.name
        case .to:
            toStation = station
            toName = station.name
        }
        if station.kind == .metro && (mode == .train || mode == .sBahn) { mode = .metro }
        // Stops from the complete place database: pick the mode both ends share (e.g. bus stop → bus).
        if station.kind == .stop {
            let other = endpoint == .from ? toStation : fromStation
            let candidate = station.primaryMode
            if other == nil || other?.kind == .stop || other?.primaryMode == candidate { mode = candidate }
        }
        recompute()
    }

    func setCustomName(_ name: String, for endpoint: Endpoint) {
        switch endpoint {
        case .from:
            fromStation = nil
            fromName = name
        case .to:
            toStation = nil
            toName = name
        }
        recompute()
    }

    func swap() {
        Swift.swap(&fromStation, &toStation)
        Swift.swap(&fromName, &toName)
        recompute()
    }

    func apply(favorite: FavoriteRouteEntity) {
        fromStation = favorite.fromStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: favorite.fromName)
        toStation = favorite.toStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: favorite.toName)
        fromName = favorite.fromName
        toName = favorite.toName
        mode = favorite.mode
        isRoundTrip = favorite.isRoundTrip
        if let favoriteCategory = TripCategory(rawValue: favorite.categoryRaw) {
            // The favourite is a template: its purpose wins over an earlier pick.
            category = favoriteCategory
            categorySource = .favorite
            categoryWasChosen = false
        }
        manualFare = nil
        manualDistanceKm = nil
        recompute()
        if estimate == nil {
            manualFare = favorite.fareEUR
            manualDistanceKm = favorite.distanceKm
        }
    }

    func resetManualFare() {
        manualFare = nil
        recompute()
    }

    /// Recomputes the estimate after any input change.
    func recompute() {
        guard let a = fromStation, let b = toStation, a.id != b.id else {
            estimate = nil
            return
        }
        estimate = app.estimator.estimate(from: a, to: b, mode: mode, travelClass: travelClass, discount: discount, date: date)
    }

    /// Amortisation preview: fraction before and after saving this trip.
    func impact(on summary: SavingsSummary?) -> (before: Double, after: Double)? {
        guard let summary, summary.ticketPrice > 0 else { return nil }
        let currentValue = isEditing ? (summary.totalValue - (editingTrip?.totalValue ?? 0)) : summary.totalValue
        return (currentValue / summary.ticketPrice, (currentValue + totalValue) / summary.ticketPrice)
    }

    /// Persists the trip (insert or update). Returns the saved entity.
    @discardableResult
    func save(context: ModelContext) -> TripEntity? {
        guard canSave else { return nil }
        let repo = Repository(context: context, app: app)
        let trip: TripEntity
        if let existing = editingTrip {
            trip = existing
            trip.date = date
            trip.fromName = resolvedFromName
            trip.toName = resolvedToName
            trip.fromStationID = fromStation?.id
            trip.toStationID = toStation?.id
            trip.mode = mode
            trip.distanceKm = distanceKm
            trip.fareEUR = fare
            trip.isFareManual = isFareManual
            trip.isRoundTrip = isRoundTrip
            trip.travelClass = travelClass
            trip.companions = companions
            trip.states = states
            trip.note = note
            trip.category = category
            trip.isInduced = isInduced
            repo.updateTrip(trip)
        } else {
            trip = TripEntity(date: date, fromName: resolvedFromName, toName: resolvedToName, fromStationID: fromStation?.id,
                              toStationID: toStation?.id, mode: mode, distanceKm: distanceKm, fareEUR: fare,
                              isFareManual: isFareManual, isRoundTrip: isRoundTrip, travelClass: travelClass,
                              companions: companions, states: states, note: note)
            trip.category = category
            trip.isInduced = isInduced
            repo.addTrip(trip)
        }
        if saveAsFavorite { repo.metaAddFavorite(from: trip) }
        return trip
    }
}

/// Recently used stations (most recent first) for the station picker.
enum RecentStations {
    private static let key = "recentStationIDs"

    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func remember(_ id: String) {
        var ids = load().filter { $0 != id }
        ids.insert(id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(12)), forKey: key)
    }
}
