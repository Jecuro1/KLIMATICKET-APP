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
    /// Via stations in travel order, at most `TripVia.maxCount` (TripEdViaRows.swift, docs/VIA.md).  // MARK: via
    var vias: [TripEdViaStop] = []

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
    /// Editing: fare and distance saved with the trip. They stay until something that sets the price changes – a new
    /// note, time or purpose must not re-price an older trip with today's tariff or drop its Vorteilscard price.
    @ObservationIgnored private var storedFare: Double?
    @ObservationIgnored private var storedDistanceKm: Double?
    /// Route, mode, class, Vorteilscard or a date in another tariff period changed: from then on the estimate counts.
    private(set) var pricingChanged = false
    /// Start or destination changed (a trip without tariff data then needs a new price).
    private(set) var routeChanged = false

    /// Amortisation preview: the ticket's other trips, summed once per ticket period (see `tripEdBaseline`).
    @ObservationIgnored private let openedAt = Date()
    @ObservationIgnored private var baseline: (ticketID: UUID, period: TicketPeriod, value: Double)?

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
            vias = TripEdViaStop.stops(for: trip.via, stations: app.stations)   // MARK: via
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
            // An own price stays an own price; an estimated one is kept as saved (see `fare`).
            if trip.isFareManual { manualFare = trip.fareEUR } else { storedFare = trip.fareEUR }
            storedDistanceKm = trip.distanceKm
        } else {
            fromStation = draft.fromStationID.flatMap(app.stations.station(id:))
                ?? (draft.fromName.isEmpty ? nil : app.stations.station(named: draft.fromName))
                ?? (draft.fromName.isEmpty ? app.settings.homeStationID.flatMap(app.stations.station(id:)) : nil)
            toStation = draft.toStationID.flatMap(app.stations.station(id:))
                ?? (draft.toName.isEmpty ? nil : app.stations.station(named: draft.toName))
            fromName = fromStation?.name ?? draft.fromName
            toName = toStation?.name ?? draft.toName
            vias = TripEdViaStop.stops(for: draft.via, stations: app.stations)   // MARK: via
            mode = draft.mode
            date = draft.date
            isRoundTrip = draft.isRoundTrip
            // MARK: dashboardTicket – „Bearbeiten & erfassen“ of a favourite: same as picking it in the favourites row.
            if let favorite = draft.favorite, favorite.deletedAt == nil {
                apply(favorite: favorite)
            }
        }
        recompute()
        if let trip { restoreDiscount(of: trip) }
    }

    /// The Vorteilscard switch is not saved per trip: show it on when only the reduced estimate explains the saved price.
    private func restoreDiscount(of trip: TripEntity) {
        guard !trip.isFareManual, let current = estimate, abs(current.fareEUR - trip.fareEUR) >= 0.005,
              let a = fromStation, let b = toStation else { return }
        let other: FareDiscount = discount == .none ? .vorteilscard : .none
        let alternative = app.estimator.estimate(from: a, via: viaStations, to: b, mode: mode, travelClass: travelClass,   // MARK: via
                                                 discount: other, date: date)
        guard abs(alternative.fareEUR - trip.fareEUR) < 0.005 else { return }
        discount = other
        estimate = alternative
    }

    var isEditing: Bool { editingTrip != nil }
    var title: String { isEditing ? "Fahrt bearbeiten" : "Neue Fahrt" }

    var resolvedFromName: String { fromStation?.name ?? fromName.trimmingCharacters(in: .whitespaces) }
    var resolvedToName: String { toStation?.name ?? toName.trimmingCharacters(in: .whitespaces) }

    /// Fare for one direction: own price → (editing) the saved price → the estimate.
    var fare: Double {
        if let manualFare { return manualFare }
        if let storedFare, keepsStoredPrice { return storedFare }
        return estimate?.fareEUR ?? 0
    }

    var distanceKm: Double {
        if let manualDistanceKm { return manualDistanceKm }
        if let storedDistanceKm, keepsStoredPrice { return storedDistanceKm }
        return estimate?.distanceKm ?? 0
    }

    var totalValue: Double { fare * (isRoundTrip ? 2 : 1) }
    var isFareManual: Bool { manualFare != nil }

    /// Editing keeps the saved price until a pricing input changes – without tariff data for the route, until the route does.
    private var keepsStoredPrice: Bool { !pricingChanged || (estimate == nil && !routeChanged) }

    /// Editing: the saved price is shown and today's estimate differs from it (older tariff) or there is none ("Lech").
    var showsStoredFare: Bool {
        guard manualFare == nil, let storedFare, keepsStoredPrice else { return false }
        guard let estimate else { return true }
        return abs(estimate.fareEUR - storedFare) >= 0.005
    }

    /// "Zurücksetzen" / "Aktualisieren" back to today's estimate.
    var canResetFare: Bool { (isFareManual || showsStoredFare) && estimate != nil }

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
        if showsStoredFare {
            guard let e = estimate else { return "Beim Erfassen gespeichert" }
            return "Beim Erfassen gespeichert · aktuell \(Format.euroPrecise(e.fareEUR))"
        }
        if let e = estimate { return e.explanation }
        return "Preis wird nach Wahl von Start und Ziel geschätzt"
    }

    var isOfficialPrice: Bool { !isFareManual && !showsStoredFare && estimate?.method == .officialTable }

    /// Federal states touched (for regional ticket comparison).
    var states: [String] {
        Array(Set(([fromStation?.state, toStation?.state] + viaStations.map(\.state)).compactMap { $0 })).sorted()   // MARK: via
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
        routeChanged = true
        pricingChanged = true
        if station.kind == .metro && (mode == .train || mode == .sBahn) {
            mode = .metro
        } else if mode == .metro, let a = fromStation, let b = toStation, a.kind != .metro || b.kind != .metro,
                  a.location.distanceKm(to: b.location) > 15 {
            // A long hop that began at a U-Bahn entry (Wien Hbf exists as rail and as U-Bahn station): as U-Bahn it
            // would miss the official ÖBB price.
            mode = .train
        }
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
        routeChanged = true
        pricingChanged = true
        recompute()
    }

    func setMode(_ newMode: TransportMode) {
        guard newMode != mode else { return }
        mode = newMode
        pricingChanged = true
        recompute()
    }

    func setTravelClass(_ newClass: TravelClass) {
        guard newClass != travelClass else { return }
        travelClass = newClass
        pricingChanged = true
        recompute()
    }

    func setDiscount(_ newDiscount: FareDiscount) {
        guard newDiscount != discount else { return }
        discount = newDiscount
        pricingChanged = true
        recompute()
    }

    /// A new time or day keeps a saved price; only a date in another tariff period (the estimate moves) re-prices.
    func setDate(_ newDate: Date) {
        let previous = estimate
        date = newDate
        recompute()
        if let previous, let estimate, abs(previous.fareEUR - estimate.fareEUR) >= 0.005 { pricingChanged = true }
    }

    func swap() {
        Swift.swap(&fromStation, &toStation)
        Swift.swap(&fromName, &toName)
        vias.reverse()   // MARK: via – the whole route turns around
        recompute()
    }

    // MARK: via – a via was added, changed or removed: priced like a new start or destination.
    func viaDidChange() {
        routeChanged = true
        pricingChanged = true
        recompute()
    }

    func apply(favorite: FavoriteRouteEntity) {
        fromStation = favorite.fromStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: favorite.fromName)
        toStation = favorite.toStationID.flatMap(app.stations.station(id:)) ?? app.stations.station(named: favorite.toName)
        fromName = favorite.fromName
        toName = favorite.toName
        vias = TripEdViaStop.stops(for: favorite.via, stations: app.stations)   // MARK: via
        mode = favorite.mode
        isRoundTrip = favorite.isRoundTrip
        routeChanged = true
        pricingChanged = true
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

    /// Back to today's estimate (also replaces a saved price when editing).
    func resetManualFare() {
        manualFare = nil
        pricingChanged = true
        recompute()
    }

    /// Recomputes the estimate after any input change.
    func recompute() {
        guard let a = fromStation, let b = toStation, a.id != b.id else {
            estimate = nil
            return
        }
        estimate = app.estimator.estimate(from: a, via: viaStations, to: b, mode: mode, travelClass: travelClass,   // MARK: via
                                          discount: discount, date: date)
    }

    /// Value of `ticket`'s period without the trip being edited, from the trips saved before the sheet opened (the one this
    /// sheet saves stays out, so the preview holds still while the sheet slides away). One fetch per ticket period – not a
    /// pass over every trip on each keystroke in the price field or tick of the date wheel.
    func tripEdBaseline(ticket: TicketEntity, context: ModelContext) -> (period: TicketPeriod, value: Double) {
        let period = ticket.period
        if let baseline, baseline.ticketID == ticket.id, baseline.period == period { return (period, baseline.value) }
        let start = period.start, end = period.end, opened = openedAt
        let predicate = #Predicate<TripEntity> { $0.deletedAt == nil && $0.date >= start && $0.date <= end && $0.createdAt < opened }
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>(predicate: predicate))) ?? []
        let editingID = editingTrip?.id
        let value = trips.reduce(0) { $1.id == editingID ? $0 : $0 + $1.totalValue }
        baseline = (ticket.id, period, value)
        return (period, value)
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
            trip.via = viaRecords   // MARK: via
            repo.updateTrip(trip)
        } else {
            trip = TripEntity(date: date, fromName: resolvedFromName, toName: resolvedToName, fromStationID: fromStation?.id,
                              toStationID: toStation?.id, mode: mode, distanceKm: distanceKm, fareEUR: fare,
                              isFareManual: isFareManual, isRoundTrip: isRoundTrip, travelClass: travelClass,
                              companions: companions, states: states, note: note)
            trip.category = category
            trip.isInduced = isInduced
            trip.via = viaRecords   // MARK: via
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
