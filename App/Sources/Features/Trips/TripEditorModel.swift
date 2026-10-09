import Foundation
import SwiftData
import KlimaCore

/// A stop of the form's route: the start, a transfer ("Umstieg") or the destination.
struct TripEdStop: Equatable {
    var station: Station?
    /// Free-text name when no station matches (e.g. "Lech").
    var name: String = ""

    var resolvedName: String { station?.name ?? name.trimmingCharacters(in: .whitespaces) }
}

/// One leg ("Etappe") of the form – a single trip is a journey of one leg (docs/JOURNEYS.md). A leg runs from stop `i` to
/// stop `i + 1` and keeps its own mode, vias and price.
struct TripEdLeg: Identifiable {
    let id = UUID()
    var mode: TransportMode
    /// Via stations in travel order, at most `TripVia.maxCount` (TripEdViaRows.swift, docs/VIA.md).
    var vias: [TripEdViaStop] = []
    var manualFare: Double?
    var manualDistanceKm: Double?
    var estimate: FareEstimate?
    /// Editing: fare and distance saved with the leg. They stay until something that sets the price changes – a new
    /// note, time or purpose must not re-price an older trip with today's tariff or drop its Vorteilscard price.
    var storedFare: Double?
    var storedDistanceKm: Double?
    /// Route, mode, class, Vorteilscard or a date in another tariff period changed: from then on the estimate counts.
    var pricingChanged = false
    /// Start or destination changed (a leg without tariff data then needs a new price).
    var routeChanged = false
    /// The saved trip this leg edits (nil = a new leg).
    var trip: TripEntity?

    init(mode: TransportMode, vias: [TripEdViaStop] = []) {
        self.mode = mode
        self.vias = vias
    }

    var keepsStoredPrice: Bool { !pricingChanged || (estimate == nil && !routeChanged) }

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
}

/// State + logic of the add/edit trip sheet. UI-agnostic: `TripEditorView` binds to it.
///
/// The form is a chain of stops with a leg between each two ("Reise mit Etappen", docs/JOURNEYS.md); a single trip is the
/// chain of two stops. The single-trip API (`fromStation`, `mode`, `fare`, `vias` …) reads and edits the *selected* leg –
/// the mode strip, the price card and the via rows work on whichever leg is selected; the route card shows the chain.
@Observable
@MainActor
final class TripEditorModel {
    enum Endpoint { case from, to }

    // Route (MARK: trips – stops and legs; `selectedLeg` is the one the mode strip and price card edit)
    private(set) var stops: [TripEdStop] = [TripEdStop(), TripEdStop()]
    private(set) var legs: [TripEdLeg] = [TripEdLeg(mode: .train)]
    private(set) var selectedLeg = 0

    // Details (shared by every leg)
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

    /// Amortisation preview: the ticket's other trips, summed once per ticket period (see `tripEdBaseline`).
    @ObservationIgnored private let openedAt = Date()
    @ObservationIgnored private var baseline: (ticketID: UUID, period: TicketPeriod, value: Double)?

    /// Editing: every saved leg of the trip or journey in travel order (empty for a new trip).
    private(set) var editingLegs: [TripEntity] = []
    /// The journey being edited (nil for a trip of its own).
    @ObservationIgnored private var editingJourneyID: UUID?
    let app: AppState

    /// `editing`: the saved legs of the trip or journey in travel order (one for a trip of its own); `focus` – the leg the
    /// sheet opens on (e.g. the one whose detail "Bearbeiten" came from).
    init(app: AppState, draft: TripDraft, editing trips: [TripEntity], focus: UUID? = nil) {
        self.app = app
        discount = app.settings.defaultDiscount
        travelClass = app.settings.defaultTravelClass
        if let first = trips.first {
            editingLegs = trips
            editingJourneyID = trips.count > 1 ? first.journeyID : nil
            stops = [TripEdStop(station: Self.station(id: first.fromStationID, name: first.fromName, in: app.stations),
                                name: first.fromName)]
            legs = []
            for trip in trips {
                stops.append(TripEdStop(station: Self.station(id: trip.toStationID, name: trip.toName, in: app.stations),
                                        name: trip.toName))
                var leg = TripEdLeg(mode: trip.mode, vias: TripEdViaStop.stops(for: trip.via, stations: app.stations))   // MARK: via
                leg.trip = trip
                // An own price stays an own price; an estimated one is kept as saved (see `TripEdLeg.fare`).
                if trip.isFareManual { leg.manualFare = trip.fareEUR } else { leg.storedFare = trip.fareEUR }
                leg.storedDistanceKm = trip.distanceKm
                legs.append(leg)
            }
            date = first.date
            isRoundTrip = first.isRoundTrip
            travelClass = first.travelClass
            companions = first.companions
            note = trips.lazy.map(\.note).first { !$0.isEmpty } ?? ""
            category = first.category
            isInduced = trips.contains(where: \.isInduced)
            // Editing never re-categorises silently.
            categoryWasChosen = true
            selectedLeg = focus.flatMap { id in trips.firstIndex { $0.id == id } } ?? 0
        } else {
            let from = draft.fromStationID.flatMap(app.stations.station(id:))
                ?? (draft.fromName.isEmpty ? nil : app.stations.station(named: draft.fromName))
                ?? (draft.fromName.isEmpty ? app.settings.homeStationID.flatMap(app.stations.station(id:)) : nil)
            let to = draft.toStationID.flatMap(app.stations.station(id:))
                ?? (draft.toName.isEmpty ? nil : app.stations.station(named: draft.toName))
            stops = [TripEdStop(station: from, name: from?.name ?? draft.fromName),
                     TripEdStop(station: to, name: to?.name ?? draft.toName)]
            legs = [TripEdLeg(mode: draft.mode, vias: TripEdViaStop.stops(for: draft.via, stations: app.stations))]   // MARK: via
            date = draft.date
            isRoundTrip = draft.isRoundTrip
            // MARK: dashboardTicket – „Bearbeiten & erfassen“ of a favourite: same as picking it in the favourites row.
            if let favorite = draft.favorite, favorite.deletedAt == nil {
                apply(favorite: favorite)
            }
        }
        recompute()
        if !trips.isEmpty { restoreDiscount() }
    }

    private static func station(id: String?, name: String, in stations: StationIndex) -> Station? {
        id.flatMap(stations.station(id:)) ?? stations.station(named: name)
    }

    /// The Vorteilscard switch is not saved per trip: show it on when only the reduced estimate explains the saved price
    /// (judged on the first leg with an estimated price and tariff data).
    private func restoreDiscount() {
        guard let index = legs.indices.first(where: { legs[$0].manualFare == nil && legs[$0].storedFare != nil }),
              let stored = legs[index].storedFare, let current = legs[index].estimate,
              abs(current.fareEUR - stored) >= 0.005,
              let a = stops[index].station, let b = stops[index + 1].station else { return }
        let other: FareDiscount = discount == .none ? .vorteilscard : .none
        let alternative = app.estimator.estimate(from: a, via: legs[index].vias.compactMap(\.station), to: b,   // MARK: via
                                                 mode: legs[index].mode, travelClass: travelClass, discount: other, date: date)
        guard abs(alternative.fareEUR - stored) < 0.005 else { return }
        discount = other
        recompute()
    }

    var isEditing: Bool { !editingLegs.isEmpty }
    /// The first saved leg being edited (purpose suggestions skip it).
    var editingTrip: TripEntity? { editingLegs.first }
    var title: String {
        if isEditing { return isJourney ? "Reise bearbeiten" : "Fahrt bearbeiten" }
        return isJourney ? "Neue Reise" : "Neue Fahrt"
    }

    // MARK: Selected leg (the single-trip API)

    var fromStation: Station? { stops[selectedLeg].station }
    var toStation: Station? { stops[selectedLeg + 1].station }
    /// Free-text names when no bundled station matches (e.g. a bus stop).
    var fromName: String { stops[selectedLeg].name }
    var toName: String { stops[selectedLeg + 1].name }

    var resolvedFromName: String { stops[selectedLeg].resolvedName }
    var resolvedToName: String { stops[selectedLeg + 1].resolvedName }

    var mode: TransportMode { legs[selectedLeg].mode }

    /// Via stations of the selected leg in travel order, at most `TripVia.maxCount`.  // MARK: via
    var vias: [TripEdViaStop] {
        get { legs[selectedLeg].vias }
        set { legs[selectedLeg].vias = newValue }
    }

    var manualFare: Double? {
        get { legs[selectedLeg].manualFare }
        set { legs[selectedLeg].manualFare = newValue }
    }

    var manualDistanceKm: Double? {
        get { legs[selectedLeg].manualDistanceKm }
        set { legs[selectedLeg].manualDistanceKm = newValue }
    }

    var estimate: FareEstimate? { legs[selectedLeg].estimate }
    var pricingChanged: Bool { legs[selectedLeg].pricingChanged }
    var routeChanged: Bool { legs[selectedLeg].routeChanged }

    /// Fare of the selected leg for one direction: own price → (editing) the saved price → the estimate.
    var fare: Double { legs[selectedLeg].fare }
    var distanceKm: Double { legs[selectedLeg].distanceKm }
    var isFareManual: Bool { manualFare != nil }

    /// Value of the whole trip or journey (all legs, both directions for "hin & retour").
    var totalValue: Double { journeyFare * (isRoundTrip ? 2 : 1) }

    /// Editing: the saved price is shown and today's estimate differs from it (older tariff) or there is none ("Lech").
    var showsStoredFare: Bool {
        let leg = legs[selectedLeg]
        guard leg.manualFare == nil, let storedFare = leg.storedFare, leg.keepsStoredPrice else { return false }
        guard let estimate = leg.estimate else { return true }
        return abs(estimate.fareEUR - storedFare) >= 0.005
    }

    /// "Zurücksetzen" / "Aktualisieren" back to today's estimate.
    var canResetFare: Bool { (isFareManual || showsStoredFare) && estimate != nil }

    var canSave: Bool { validationHint == nil }

    var validationHint: String? {
        guard isJourney else {
            if resolvedFromName.isEmpty || resolvedToName.isEmpty { return "Wähle Start und Ziel." }
            if resolvedFromName == resolvedToName { return "Start und Ziel sind gleich." }
            if fare <= 0 { return "Gib einen Normalpreis ein." }
            return nil
        }
        for index in legs.indices {
            let a = stops[index].resolvedName, b = stops[index + 1].resolvedName
            if a.isEmpty || b.isEmpty { return "Wähle Start und Ziel der \(index + 1). Etappe." }
            if a == b { return "Start und Ziel der \(index + 1). Etappe sind gleich." }
            if legs[index].fare <= 0 { return "Gib einen Normalpreis für die \(index + 1). Etappe ein." }
        }
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

    /// Federal states touched by the whole trip (for regional ticket comparison).
    var states: [String] {
        Array(Set(stops.compactMap(\.station?.state) + legs.flatMap { $0.vias.compactMap(\.station?.state) })).sorted()   // MARK: via
    }

    // MARK: Journey (MARK: trips – docs/JOURNEYS.md)

    /// More than one leg: a journey ("Reise mit Etappen").
    var isJourney: Bool { legs.count > 1 }
    var journeyFare: Double { legs.reduce(0) { $0 + $1.fare } }
    var journeyDistanceKm: Double { legs.reduce(0) { $0 + $1.distanceKm } }
    var journeyStartName: String { stops.first?.resolvedName ?? "" }
    var journeyEndName: String { stops.last?.resolvedName ?? "" }
    /// Another leg can follow (up to `JourneyLeg.maxCount`) once the route has a start and a destination.
    var canAddLeg: Bool { legs.count < JourneyLeg.maxCount && !journeyStartName.isEmpty && !journeyEndName.isEmpty }

    /// Resolved names of leg `index`'s start and destination.
    func legEnds(_ index: Int) -> (from: String, to: String) {
        guard legs.indices.contains(index) else { return ("", "") }
        return (stops[index].resolvedName, stops[index + 1].resolvedName)
    }

    func selectLeg(_ index: Int) {
        guard legs.indices.contains(index), index != selectedLeg else { return }
        selectedLeg = index
    }

    /// "Etappe anhängen": a new leg from the current destination to `station`; it becomes the selected one.
    func appendLeg(to station: Station) {
        guard legs.count < JourneyLeg.maxCount else { return }
        let previous = legs[legs.count - 1].mode
        stops.append(TripEdStop(station: station, name: station.name))
        var leg = TripEdLeg(mode: previous)
        leg.routeChanged = true
        leg.pricingChanged = true
        legs.append(leg)
        selectedLeg = legs.count - 1
        adjustMode(ofLeg: selectedLeg, picked: station, atStart: false)
        recompute()
    }

    /// A free-text destination for a new leg (a stop without tariff data – the price is then entered).
    func appendLeg(customName name: String) {
        guard legs.count < JourneyLeg.maxCount else { return }
        stops.append(TripEdStop(station: nil, name: name))
        var leg = TripEdLeg(mode: legs[legs.count - 1].mode)
        leg.routeChanged = true
        leg.pricingChanged = true
        legs.append(leg)
        selectedLeg = legs.count - 1
        recompute()
    }

    /// Removes leg `index` and its destination: the following leg then starts where this one started (the last leg: the
    /// previous transfer becomes the destination).
    func removeLeg(_ index: Int) {
        guard isJourney, legs.indices.contains(index) else { return }
        legs.remove(at: index)
        stops.remove(at: index + 1)
        if legs.indices.contains(index) {
            legs[index].routeChanged = true
            legs[index].pricingChanged = true
        }
        selectedLeg = min(selectedLeg >= index && selectedLeg > 0 ? selectedLeg - 1 : selectedLeg, legs.count - 1)
        recompute()
    }

    /// Removes transfer stop `stop` (1 … legs.count − 1): the leg before it now runs on to the next stop (its mode stays).
    func removeTransfer(_ stop: Int) {
        guard stop > 0, stop < stops.count - 1 else { return }
        stops.remove(at: stop)
        legs.remove(at: stop)
        legs[stop - 1].routeChanged = true
        legs[stop - 1].pricingChanged = true
        selectedLeg = min(selectedLeg >= stop ? selectedLeg - 1 : selectedLeg, legs.count - 1)
        recompute()
    }

    // MARK: Actions

    /// `.from` = the start of the whole route, `.to` = its destination.
    func setStation(_ station: Station, for endpoint: Endpoint) {
        setStop(endpoint == .from ? 0 : stops.count - 1, station: station)
    }

    /// A station for stop `index` (start, transfer or destination): the legs on both sides re-price.
    func setStop(_ index: Int, station: Station) {
        guard stops.indices.contains(index) else { return }
        stops[index] = TripEdStop(station: station, name: station.name)
        for leg in [index - 1, index] where legs.indices.contains(leg) {
            legs[leg].routeChanged = true
            legs[leg].pricingChanged = true
            adjustMode(ofLeg: leg, picked: station, atStart: leg == index)
        }
        recompute()
    }

    func setCustomName(_ name: String, for endpoint: Endpoint) {
        setCustomStop(endpoint == .from ? 0 : stops.count - 1, name: name)
    }

    func setCustomStop(_ index: Int, name: String) {
        guard stops.indices.contains(index) else { return }
        stops[index] = TripEdStop(station: nil, name: name)
        for leg in [index - 1, index] where legs.indices.contains(leg) {
            legs[leg].routeChanged = true
            legs[leg].pricingChanged = true
        }
        recompute()
    }

    /// The mode a picked stop implies for the leg it starts (`atStart`) or ends: U-Bahn entries, long hops that began at a
    /// U-Bahn entry, and stops from the complete place database (a bus stop → Bus).
    private func adjustMode(ofLeg index: Int, picked station: Station, atStart: Bool) {
        let a = stops[index].station, b = stops[index + 1].station
        var mode = legs[index].mode
        if station.kind == .metro && (mode == .train || mode == .sBahn) {
            mode = .metro
        } else if mode == .metro, let a, let b, a.kind != .metro || b.kind != .metro, a.location.distanceKm(to: b.location) > 15 {
            // A long hop that began at a U-Bahn entry (Wien Hbf exists as rail and as U-Bahn station): as U-Bahn it
            // would miss the official ÖBB price.
            mode = .train
        }
        // Stops from the complete place database: pick the mode both ends share (e.g. bus stop → bus).
        if station.kind == .stop {
            let other = atStart ? b : a
            let candidate = station.primaryMode
            if other == nil || other?.kind == .stop || other?.primaryMode == candidate { mode = candidate }
        }
        legs[index].mode = mode
    }

    func setMode(_ newMode: TransportMode) {
        guard newMode != mode else { return }
        legs[selectedLeg].mode = newMode
        legs[selectedLeg].pricingChanged = true
        recompute()
    }

    func setTravelClass(_ newClass: TravelClass) {
        guard newClass != travelClass else { return }
        travelClass = newClass
        markAllPricingChanged()
        recompute()
    }

    func setDiscount(_ newDiscount: FareDiscount) {
        guard newDiscount != discount else { return }
        discount = newDiscount
        markAllPricingChanged()
        recompute()
    }

    private func markAllPricingChanged() {
        for index in legs.indices { legs[index].pricingChanged = true }
    }

    /// A new time or day keeps a saved price; only a date in another tariff period (the estimate moves) re-prices.
    func setDate(_ newDate: Date) {
        let previous = legs.map(\.estimate?.fareEUR)
        date = newDate
        recompute()
        for index in legs.indices {
            if let before = previous[index], let now = legs[index].estimate?.fareEUR, abs(before - now) >= 0.005 {
                legs[index].pricingChanged = true
            }
        }
    }

    /// The whole route turns around: stops, legs and every leg's vias.
    func swap() {
        stops.reverse()
        legs.reverse()
        for index in legs.indices { legs[index].vias.reverse() }   // MARK: via
        selectedLeg = legs.count - 1 - selectedLeg
        recompute()
    }

    // MARK: via – a via was added, changed or removed: priced like a new start or destination.
    func viaDidChange() {
        legs[selectedLeg].routeChanged = true
        legs[selectedLeg].pricingChanged = true
        recompute()
    }

    func apply(favorite: FavoriteRouteEntity) {
        let stations = app.stations
        let favoriteLegs = favorite.legs   // MARK: trips – a Kombi-Vorlage fills every leg
        if favoriteLegs.count > 1 {
            stops = [TripEdStop(station: Self.station(id: favoriteLegs[0].fromStationID, name: favoriteLegs[0].fromName, in: stations),
                                name: favoriteLegs[0].fromName)]
            legs = favoriteLegs.map { leg in
                stops.append(TripEdStop(station: Self.station(id: leg.toStationID, name: leg.toName, in: stations), name: leg.toName))
                var edited = TripEdLeg(mode: leg.mode, vias: TripEdViaStop.stops(for: leg.via, stations: stations))
                edited.routeChanged = true
                edited.pricingChanged = true
                return edited
            }
        } else {
            stops = [TripEdStop(station: Self.station(id: favorite.fromStationID, name: favorite.fromName, in: stations),
                                name: favorite.fromName),
                     TripEdStop(station: Self.station(id: favorite.toStationID, name: favorite.toName, in: stations),
                                name: favorite.toName)]
            var leg = TripEdLeg(mode: favorite.mode, vias: TripEdViaStop.stops(for: favorite.via, stations: stations))   // MARK: via
            leg.routeChanged = true
            leg.pricingChanged = true
            legs = [leg]
        }
        // Editing keeps the saved legs it replaces in `editingLegs` – they are tombstoned on save.
        selectedLeg = 0
        isRoundTrip = favorite.isRoundTrip
        if let favoriteCategory = TripCategory(rawValue: favorite.categoryRaw) {
            // The favourite is a template: its purpose wins over an earlier pick.
            category = favoriteCategory
            categorySource = .favorite
            categoryWasChosen = false
        }
        recompute()
        // Without tariff data (custom places) the favourite's own price is taken.
        if favoriteLegs.count > 1 {
            for index in legs.indices where legs[index].estimate == nil {
                legs[index].manualFare = favoriteLegs[index].fareEUR
                legs[index].manualDistanceKm = favoriteLegs[index].distanceKm
            }
        } else if legs[0].estimate == nil {
            legs[0].manualFare = favorite.fareEUR
            legs[0].manualDistanceKm = favorite.distanceKm
        }
    }

    /// Back to today's estimate (also replaces a saved price when editing).
    func resetManualFare() {
        legs[selectedLeg].manualFare = nil
        legs[selectedLeg].pricingChanged = true
        recompute()
    }

    /// Recomputes every leg's estimate after any input change.
    func recompute() {
        for index in legs.indices {
            guard let a = stops[index].station, let b = stops[index + 1].station, a.id != b.id else {
                legs[index].estimate = nil
                continue
            }
            legs[index].estimate = app.estimator.estimate(from: a, via: legs[index].vias.compactMap(\.station), to: b,   // MARK: via
                                                          mode: legs[index].mode, travelClass: travelClass, discount: discount,
                                                          date: date)
        }
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
        let editingIDs = Set(editingLegs.map(\.id))
        let value = trips.reduce(0) { editingIDs.contains($1.id) ? $0 : $0 + $1.totalValue }
        baseline = (ticket.id, period, value)
        return (period, value)
    }

    /// Federal states of leg `index` (its stops and vias).
    private func states(ofLeg index: Int) -> [String] {
        let stations = [stops[index].station, stops[index + 1].station].compactMap { $0 } + legs[index].vias.compactMap(\.station)
        return Array(Set(stations.map(\.state))).sorted()
    }

    /// What leg `index` saves as vias: travel order, without one that is the leg's start or destination itself.
    private func viaRecords(ofLeg index: Int) -> [TripVia] {
        let endpoints = [stops[index].station?.id, stops[index + 1].station?.id].compactMap { $0 }
        let names = [stops[index].resolvedName, stops[index + 1].resolvedName].filter { !$0.isEmpty }
        return TripViaCodec.sanitized(legs[index].vias.map(\.record).filter { via in
            if let id = via.stationID, endpoints.contains(id) { return false }
            return !names.contains(via.name)
        })
    }

    /// Persists the trip – or every leg of the journey – in one commit (inserts, updates, legs dropped while editing are
    /// tombstoned). Returns the saved first leg.
    @discardableResult
    func save(context: ModelContext) -> TripEntity? {
        guard canSave else { return nil }
        let repo = Repository(context: context, app: app)
        let journeyID: UUID? = isJourney ? (editingJourneyID ?? UUID()) : nil
        var inserted: [TripEntity] = [], updated: [TripEntity] = [], saved: [TripEntity] = []
        for index in legs.indices {
            let leg = legs[index]
            let from = stops[index], to = stops[index + 1]
            let trip: TripEntity
            if let existing = leg.trip, existing.deletedAt == nil {
                trip = existing
                updated.append(trip)
            } else {
                trip = TripEntity(date: date, fromName: from.resolvedName, toName: to.resolvedName, mode: leg.mode,
                                  distanceKm: leg.distanceKm, fareEUR: leg.fare)
                inserted.append(trip)
            }
            trip.date = date
            trip.fromName = from.resolvedName
            trip.toName = to.resolvedName
            trip.fromStationID = from.station?.id
            trip.toStationID = to.station?.id
            trip.mode = leg.mode
            trip.distanceKm = leg.distanceKm
            trip.fareEUR = leg.fare
            trip.isFareManual = leg.manualFare != nil
            trip.isRoundTrip = isRoundTrip
            trip.travelClass = travelClass
            trip.companions = companions
            trip.states = states(ofLeg: index)
            trip.note = index == 0 ? note : ""   // a journey's note lives on its first leg
            trip.category = category
            trip.isInduced = isInduced
            trip.via = viaRecords(ofLeg: index)   // MARK: via
            trip.journeyID = journeyID
            trip.legIndex = isJourney ? index : 0
            saved.append(trip)
        }
        let kept = Set(saved.map(\.id))
        let removed = editingLegs.filter { !kept.contains($0.id) }
        guard repo.saveJourney(inserting: inserted, updating: updated, removing: removed) else { return saved.first }
        if saveAsFavorite {
            if saved.count > 1 { repo.metaAddFavorite(fromJourney: saved) } else if let trip = saved.first { repo.metaAddFavorite(from: trip) }
        }
        return saved.first
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
