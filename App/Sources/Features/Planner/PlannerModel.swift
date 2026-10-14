import SwiftUI
import Observation
import CoreLocation
import KlimaCore

/// State and logic of the Fahrplan tab (docs/OEBB_LIVE.md §E3). Every network call goes through `LiveDataService`:
/// `live.timetable` is nil unless live data is switched on and available, so with consent undecided or declined no request
/// is ever made from here.
@MainActor @Observable
final class PlannerModel {
    enum NavigationStyle { case searchTab, plainTab }
    /// One-line fallback (R4): `.plainTab` drops the search role and shows the planner's own search field.
    static let navigationStyle: NavigationStyle = .searchTab

    enum Mode: String, CaseIterable, Identifiable {
        case connections, departures
        var id: String { rawValue }
        var title: String { self == .connections ? "Verbindungen" : "Abfahrten" }
        var symbol: String { self == .connections ? "point.topleft.down.to.point.bottomright.curvepath" : "list.bullet.rectangle" }
    }

    enum BoardFilter: String, CaseIterable, Identifiable {
        case all, train, sBahn, tram, bus
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Alle"
            case .train: "Zug"
            case .sBahn: "S-Bahn"
            case .tram: "Tram"
            case .bus: "Bus"
            }
        }
        var mode: TransportMode? {
            switch self {
            case .all: nil
            case .train: .train
            case .sBahn: .sBahn
            case .tram: .tram
            case .bus: .bus
            }
        }
        func matches(_ row: BoardRow) -> Bool { mode.map { row.mode == $0 } ?? true }
    }

    struct HereStop: Equatable {
        var location: Location
        var distanceMeters: Int?
        var resolvedAt: Date
    }

    let live: LiveDataService
    @ObservationIgnored let stationsProvider: () -> StationIndex
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var locator: LocationService?

    // MARK: Search form

    var query = ""
    var searchTarget: PlannerSearchTarget = .destination
    var isSearchFocused = false
    var mode: Mode = .connections
    var origin: PlannerPlace? = .currentLocation
    var destination: PlannerPlace?
    var vias: [PlannerPlace] = []
    /// nil = „Jetzt“.
    var when: Date?
    var isArrival = false
    var options = PlannerOptions.load() {
        didSet {
            options.save()
            rebuildRows()
        }
    }
    /// Order of the result list (UserDefaults `planner.sort`). The list is only re-sorted, never searched again.
    var sort: ConnectionSort = ConnectionSort(rawValue: UserDefaults.standard.string(forKey: "planner.sort") ?? "") ?? .departure {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "planner.sort") }
    }
    var path: [PlannerRoute] = []
    var showsOptions = false
    var showsTimeSheet = false

    // MARK: Ticket

    private(set) var ticketName = "KlimaTicket"
    private(set) var scope: TicketScope = .oe

    // MARK: Results

    @ObservationIgnored private var journeys: [Journey] = []
    @ObservationIgnored private var viaStops: [ViaStop] = []
    @ObservationIgnored private var coverageCache: [String: JourneyCoverage] = [:]
    @ObservationIgnored private var priceStates: [String: PlannerPriceState] = [:]
    @ObservationIgnored private var earlierContext: String?
    @ObservationIgnored private var laterContext: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var priceTask: Task<Void, Never>?
    private(set) var rows: [ConnectionRow] = []
    /// Connections the walking limit of the options hides (on the current result pages).
    private(set) var hiddenByWalkCount = 0
    private(set) var phase: PlannerPhase = .idle
    private(set) var resultsUpdatedAt: Date?
    private(set) var isLoadingMore = false
    private(set) var resolvedOrigin: Location?
    private(set) var resolvedDestination: Location?
    private(set) var hereStop: HereStop?
    /// The via stops of the search the rows belong to (stored with a logged trip).
    var queriedVias: [ViaStop] { viaStops }
    var canLoadEarlier: Bool { earlierContext != nil }
    var canLoadLater: Bool { laterContext != nil }

    // MARK: Departures

    var boardStation: PlannerPlace?
    var boardKind: BoardKind = .departures
    var boardDate: Date?
    var boardFilter: BoardFilter = .all
    private(set) var boardRows: [BoardRow] = []
    @ObservationIgnored private var boardEntries: [BoardEntry] = []
    private(set) var boardPhase: PlannerPhase = .idle
    private(set) var boardUpdatedAt: Date?
    @ObservationIgnored private var boardMinutes = 60

    // MARK: Home sections

    private(set) var routes: [RouteSuggestion] = []
    /// CI screenshots: fixed „Deine Strecken“ instead of the user's trips.
    var screenshotRoutes: [(from: Station, to: Station)]?
    private(set) var nearby: NearbyBoard?

    init(live: LiveDataService, stations: @escaping () -> StationIndex, settings: AppSettings) {
        self.live = live
        self.stationsProvider = stations
        self.settings = settings
    }

    var stations: StationIndex { stationsProvider() }

    // MARK: Derived

    var searchPrompt: String { mode == .departures ? PlannerSearchTarget.board.prompt : searchTarget.prompt }

    var isKlimaTicketOnly: Bool { options.klimaTicketOnly ?? (scope == .oe) }

    var activeOptionCount: Int { options.activeCount(klimaTicketDefault: scope == .oe) }

    /// Rows after „Nur mit KlimaTicket gültig“ (not-covered connections are hidden; partial ones stay), in the chosen order.
    var visibleRows: [ConnectionRow] {
        let base = isKlimaTicketOnly ? rows.filter { $0.coverage?.overall != .notCovered } : rows
        return ConnectionSorting.sorted(base, by: sort)
    }

    /// The price class and discount the prices of a search use: the options, else the settings.
    var effectiveTravelClass: TravelClass { options.travelClass ?? settings.defaultTravelClass }
    var effectiveDiscount: FareDiscount { options.discount ?? settings.defaultDiscount }

    /// The Vorteilscard switch of the options. The value that equals the setting is stored as „wie Einstellungen“ (nil).
    func setVorteilscard(_ on: Bool) {
        let discount: FareDiscount = on ? .vorteilscard : FareDiscount.none
        options.discount = discount == settings.defaultDiscount ? nil : discount
    }

    var hiddenByKlimaTicketCount: Int { rows.count - visibleRows.count }

    var hasBoth: Bool { origin != nil && destination != nil }

    var filteredBoardRows: [BoardRow] { boardRows.filter(boardFilter.matches) }

    /// Called with the active ticket (product id and name); coverage is judged against it.
    func configure(ticketProductID: String?, ticketName: String?) {
        let name = ticketName?.nilIfEmptyText ?? "KlimaTicket"
        let newScope: TicketScope = ticketProductID.map { live.ticketScope(productID: $0) } ?? .oe
        guard name != self.ticketName || newScope != scope else { return }
        self.ticketName = name
        scope = newScope
        coverageCache.removeAll()
        rebuildRows()
    }

    // MARK: Form actions

    func beginSearch(_ target: PlannerSearchTarget) {
        searchTarget = target
        query = ""
        isSearchFocused = true
    }

    func addVia() { beginSearch(.via(vias.count)) }

    func removeVia(at index: Int) {
        guard vias.indices.contains(index) else { return }
        vias.remove(at: index)
        if hasBoth, path.contains(.results) { restartSearch() }
    }

    func swap() {
        let previousOrigin = origin
        origin = destination
        destination = previousOrigin
        vias.reverse()
        if hasBoth, path.contains(.results) { restartSearch() }
    }

    func setWhen(_ date: Date?, arrival: Bool) {
        when = date
        isArrival = arrival
        if hasBoth, path.contains(.results) { restartSearch() }
    }

    /// A place was picked in the search: it fills the slot being edited. With both ends set the search starts.
    func choose(_ place: PlannerPlace) {
        PlannerRecents.remember(place)
        query = ""
        isSearchFocused = false
        switch searchTarget {
        case .origin:
            origin = place
            if destination == nil { searchTarget = .destination }
        case .destination:
            destination = place
        case .via(let index):
            if vias.indices.contains(index) { vias[index] = place } else if vias.count < JourneyQuery.maxViaStops { vias.append(place) }
        case .board:
            boardStation = place
            mode = .departures
            Task { await loadBoard() }
            return
        }
        mode = .connections
        if hasBoth { startSearch() }
    }

    func startSearch() {
        guard hasBoth else { return }
        if !path.contains(.results) { path = [.results] }
        restartSearch()
    }

    func restartSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    // MARK: Deep links

    /// `klimabilanz://plan?from=…&to=…&via=…&at=<ISO8601>&arr=0|1` (`PlannerLink`): fills the form and starts the search.
    /// The search starts only when both ends are known places. An unknown name never leaves the default origin
    /// („Aktueller Standort“) in place, so an external link cannot start a location lookup by itself.
    func handleDeepLink(_ link: PlannerLink) {
        mode = .connections
        path = []
        guard let from = place(for: link.from), let to = place(for: link.to) else { return }
        origin = from
        destination = to
        vias = link.vias.compactMap { place(for: $0) }
        when = link.at
        isArrival = link.isArrival
        startSearch()
    }

    /// Zug-Radar: the departures of a stop from a live run. No station index entry is needed for it.
    func showBoard(live location: Location) {
        path = []
        mode = .departures
        boardStation = .live(location)
        boardDate = nil
        Task { await loadBoard() }
    }

    /// Moves a via stop one place up (`by: -1`) or down (`by: 1`): the order of the stops is the order of the trip.
    func moveVia(at index: Int, by delta: Int) {
        let target = index + delta
        guard vias.indices.contains(index), vias.indices.contains(target) else { return }
        vias.swapAt(index, target)
        if hasBoth, path.contains(.results) { restartSearch() }
    }

    /// Set by `klimabilanz://radar` and the Live-verfolgen control: the Zug-Radar opens over the Fahrplan (PlannerRootView).
    var radarRequested = false   // MARK: widgets

    /// `klimabilanz://board?station=<stationID>`
    func showBoard(stationID: String) {
        guard let station = place(for: stationID) else { return }
        path = []
        mode = .departures
        boardStation = station
        boardDate = nil
        Task { await loadBoard() }
    }

    private func place(for text: String) -> PlannerPlace? {
        let index = stations
        if let s = index.station(id: text) { return .station(s) }
        if let s = index.station(named: text) { return .station(s) }
        return index.search(text, limit: 1).first.map { .station($0) }
    }

    // MARK: Place resolution

    /// A planner location for a place: app stations through the `StationLinker` (no request for `uic:` ids), live
    /// locations as they are, „Aktueller Standort“ through the nearest stop.
    func resolve(_ place: PlannerPlace) async throws -> Location {
        switch place {
        case .live(let location):
            return location
        case .station(let station):
            if live.isDemo { return Self.demoLocation(station) }
            do {
                return try await live.linker.hafasLocation(for: station)
            } catch let error as LiveError {
                if case .hafas(code: "LOCATION", _) = error { await live.linker.invalidate(stationID: station.id) }
                throw error
            }
        case .currentLocation:
            return try await resolveHere().location
        }
    }

    static func demoLocation(_ station: Station) -> Location {
        let extId = station.id.hasPrefix("uic:") ? String(station.id.dropFirst(4)) : station.id
        var location = Location.station(extId: extId, name: station.name)
        location.coordinate = station.location
        return location
    }

    func resolveHere(force: Bool = false) async throws -> HereStop {
        if !force, let cached = hereStop, Date().timeIntervalSince(cached.resolvedAt) < 120 { return cached }
        guard let timetable = live.timetable else { throw LiveError.disabled(.oebbHafas) }
        let point: GeoPoint
        if live.isDemo {
            point = GeoPoint(latitude: 47.2633, longitude: 11.4010)
        } else {
            let locator = self.locator ?? LocationService()
            self.locator = locator
            guard let fix = await locator.currentLocation() else { throw PlannerError.noLocation }
            point = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        }
        let stops = try await timetable.nearby(point, maxDistanceMeters: 1000, maxResults: 5, products: .all)
        guard let first = stops.first(where: { $0.kind == .station }) ?? stops.first else { throw LiveError.hafas(code: "LOCATION", message: nil) }
        let here = HereStop(location: first, distanceMeters: first.distanceMeters, resolvedAt: Date())
        hereStop = here
        return here
    }

    /// Resolves „Aktueller Standort“ quietly when the permission is already granted (no prompt on appearing).
    func refreshHereIfAuthorized() async {
        guard origin == .currentLocation || destination == .currentLocation, live.timetable != nil else { return }
        if !live.isDemo {
            let status = CLLocationManager().authorizationStatus
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        }
        _ = try? await resolveHere()
    }

    // MARK: Search

    private func makeQuery(pageContext: String? = nil) async throws -> JourneyQuery {
        guard let origin, let destination else { throw LiveError.noConnection }
        let from = try await resolve(origin)
        let to = try await resolve(destination)
        var viaList: [ViaStop] = []
        for via in vias.prefix(JourneyQuery.maxViaStops) { viaList.append(ViaStop(location: try await resolve(via))) }
        resolvedOrigin = from
        resolvedDestination = to
        return JourneyQuery(origin: from, destination: to, via: viaList, date: when ?? Date(), isArrival: isArrival,
                            maxChanges: options.maxChanges, minTransferMinutes: options.extraTransferMinutes > 0 ? options.extraTransferMinutes : nil,
                            products: options.effectiveProducts(klimaTicketOnly: isKlimaTicketOnly), bikeCarriage: options.bike,
                            accessibility: options.accessible ? .complete : nil, results: 5, includeStopovers: true,
                            includePolyline: false, pageContext: pageContext)
    }

    func search() async {
        guard hasBoth else { return }
        guard let timetable = live.timetable else {
            phase = .failed(.unavailable(live.timetableUnavailable ?? .offline))
            return
        }
        generation += 1
        let mine = generation
        priceTask?.cancel()
        if rows.isEmpty { phase = .loading } else { withMotion(Motion.snappy) { phase = .loading } }
        var failure: PlannerFailure?
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            do {
                let query = try await makeQuery()
                let page = try await timetable.journeys(query)
                guard mine == generation, !Task.isCancelled else { return }
                journeys = page.journeys
                viaStops = query.via
                earlierContext = page.earlierContext
                laterContext = page.laterContext
                coverageCache.removeAll()
                priceStates.removeAll()
                resultsUpdatedAt = Date()
                rebuildRows()
                withMotion(Motion.smooth) { phase = .loaded }
                if page.journeys.isEmpty { failure = .noConnection; break }
                startPrices(generation: mine)
                return
            } catch is CancellationError {
                return
            } catch {
                failure = PlannerFailure(error)
                if failure?.isTransient == true, attempt < 2 {
                    try? await Task.sleep(for: .seconds(2 << attempt))
                    continue
                }
                break
            }
        }
        guard mine == generation, !Task.isCancelled else { return }
        if failure == .noConnection {
            journeys = []
            rows = []
        }
        withMotion(Motion.smooth) { phase = .failed(failure ?? .unreachable) }
    }

    /// „Früher“ / „Später“: one more page in the given direction.
    func loadMore(earlier: Bool) async {
        guard !isLoadingMore, let timetable = live.timetable, let context = earlier ? earlierContext : laterContext else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let mine = generation
        do {
            let query = try await makeQuery(pageContext: context)
            let page = try await timetable.journeys(query)
            // A search that started meanwhile (other places, time or options) owns the list: this page belongs to the old one.
            guard mine == generation, !Task.isCancelled else { return }
            let known = Set(journeys.map(\.id))
            let fresh = page.journeys.filter { !known.contains($0.id) }
            journeys = PlannerResults.merge(journeys, page: page.journeys)
            if earlier { earlierContext = page.earlierContext } else { laterContext = page.laterContext }
            rebuildRows()
            startPrices(generation: generation, only: Set(fresh.map(\.id)))
        } catch {
            // The list stays as it is; the button can be tapped again.
        }
    }

    /// Re-reads the realtime data of the listed connections (visible screen only, every 60 s).
    func refreshRows() async {
        guard !journeys.isEmpty, let timetable = live.timetable else { return }
        if phase == .loading { return }
        let tokens = journeys.compactMap { journey in journey.refreshToken.map { (journey.id, $0) } }
        guard !tokens.isEmpty else { return }
        let mine = generation
        do {
            let results = try await timetable.refresh(batch: tokens.map(\.1))
            // The list may have changed while the request was in flight (a new search, a page merged in between). The answers
            // go to the connection they were asked for, found by id, never by the position it had when the request left.
            guard mine == generation else { return }
            var changed = false
            for (offset, result) in results.enumerated() where tokens.indices.contains(offset) {
                guard case .success(let fresh) = result,
                      let index = journeys.firstIndex(where: { $0.id == tokens[offset].0 }) else { continue }
                var merged = fresh
                if merged.legs.count == journeys[index].legs.count {
                    // A refresh may come without stopovers: keep the ones we have.
                    for i in merged.legs.indices where merged.legs[i].stopovers.isEmpty {
                        merged.legs[i].stopovers = journeys[index].legs[i].stopovers
                    }
                }
                journeys[index] = merged
                changed = true
            }
            if changed {
                resultsUpdatedAt = Date()
                rebuildRows()
                if case .failed = phase { withMotion(Motion.smooth) { phase = .loaded } }
            }
        } catch {
            // Keep the last data; the offline pill says how old it is.
            if case .loaded = phase, PlannerFailure(error) == .offline { phase = .failed(.offline) }
        }
    }

    // MARK: Rows

    private func coverage(for journey: Journey) -> JourneyCoverage? {
        if let cached = coverageCache[journey.id] { return cached }
        guard let evaluated = live.coverage?.evaluate(journey, scope: scope) else { return nil }
        coverageCache[journey.id] = evaluated
        return evaluated
    }

    func rebuildRows() {
        // The walking limit filters the connections; `journeys` keeps every page so the refresh keeps its indices.
        let shown = PlannerResults.withinWalk(journeys, maxMeters: options.maxWalkMeters)
        hiddenByWalkCount = journeys.count - shown.count
        let summaries = JourneyPresentation.summaries(shown, now: Date(), via: viaStops)
        rows = zip(shown, summaries).map { journey, summary in
            ConnectionRow(journey: journey, summary: summary,
                          badges: journey.rideLegs.compactMap(\.line).map { LineBadge(line: $0, size: .s) },
                          coverage: coverage(for: journey), price: priceStates[journey.id] ?? PlannerPriceState(),
                          co2Kg: PlannerEmissions.co2Kg(journey))
        }
    }

    func row(id: String) -> ConnectionRow? { rows.first { $0.id == id } }

    /// Prices the listed connections again (a price class or discount changed): no new search, no new connections.
    func repriceRows() { startPrices(generation: generation) }

    // MARK: Prices

    /// The request for the price a card or the detail shows: the whole connection, or – for a partly covered one – the
    /// covered part only (docs/OEBB_LIVE.md §E6.2).
    func priceRequest(for journey: Journey, coverage: JourneyCoverage?) -> PriceRequest {
        var request = PriceRequest(journey: journey, travelClass: effectiveTravelClass, discount: effectiveDiscount,
                                   stations: stations, via: viaStops)
        if let coverage, coverage.overall == .partial, let segment = JourneyMetrics.coveredSegment(journey, coverage: coverage) {
            request.to = PriceEndpoint(location: segment.to, stations: stations)
            request.journey = nil
            request.via = []
        }
        return request
    }

    private func startPrices(generation mine: Int, only: Set<String>? = nil) {
        priceTask?.cancel()
        priceTask = Task { [weak self] in
            guard let self else { return }
            let targets = rows.enumerated().filter { only?.contains($0.element.id) ?? true }
            let livePossible = live.isLivePriceAvailable
            let offline = live.priceUnavailable == .offline
            // 1. Instant offline values for every card (a shimmer marks the ones a live quote is coming for).
            for (position, row) in targets {
                if Task.isCancelled || mine != generation { return }
                let request = priceRequest(for: row.journey, coverage: row.coverage)
                let quote = await live.offlineQuote(request)
                priceStates[row.id] = PlannerPriceState(quote: quote, isLoading: livePossible && position < 3 && !live.isDemo, isOffline: offline)
            }
            rebuildRows()
            guard livePossible else { return }
            // 2. Live quotes for the first three cards.
            for (position, row) in targets where position < 3 {
                if Task.isCancelled || mine != generation { return }
                let quote = await live.quote(priceRequest(for: row.journey, coverage: row.coverage))
                priceStates[row.id] = PlannerPriceState(quote: quote, isLoading: false, isOffline: false)
                withMotion(Motion.number) { rebuildRows() }
            }
        }
    }

    // MARK: Departures

    func loadBoard(reset: Bool = true) async {
        guard let station = boardStation else { return }
        guard let timetable = live.timetable else {
            boardPhase = .failed(.unavailable(live.timetableUnavailable ?? .offline))
            return
        }
        if reset { boardMinutes = 60 }
        if boardRows.isEmpty { boardPhase = .loading }
        do {
            let location = try await resolve(station)
            let query = BoardQuery(station: location, kind: boardKind, date: boardDate ?? Date(), durationMinutes: boardMinutes, maxResults: 40)
            let board = try await timetable.board(query)
            boardEntries = board.entries
            boardRows = BoardPresentation.rows(board)
            boardUpdatedAt = Date()
            withMotion(Motion.smooth) { boardPhase = .loaded }
        } catch is CancellationError {
            return
        } catch {
            withMotion(Motion.smooth) { boardPhase = .failed(PlannerFailure(error)) }
        }
    }

    /// HAFAS run id of a board row (rows only carry the entry id).
    func tripID(forBoardRow id: String) -> String? { boardEntries.first { $0.id == id }?.tripID }

    /// „Später“: 60 more minutes.
    func loadLaterBoard() async {
        boardMinutes = min(boardMinutes + 60, 360)
        await loadBoard(reset: false)
    }

    /// Station of the board when none was picked: the nearest one, else the home station.
    func prepareBoardStation() async {
        guard boardStation == nil else { return }
        if let near = nearby?.station { boardStation = .station(near); await loadBoard(); return }
        if let id = settings.homeStationID, let home = stations.station(id: id) { boardStation = .station(home); await loadBoard() }
    }

    // MARK: Home: Deine Strecken, In der Nähe

    struct RouteSuggestion: Identifiable, Equatable {
        var id: String
        var from: Station
        var to: Station
        var journey: Journey?
        var summary: ConnectionSummary?
        var badges: [LineBadge]
    }

    struct NearbyBoard: Equatable {
        var station: Station
        var distanceMeters: Int?
        var rows: [BoardRow]
    }

    /// The top relations of the user's own trips (the caller picks them), with the next departure of each.
    func loadRoutes(_ relations: [(from: Station, to: Station)]) async {
        let relations = Array(relations.prefix(3))
        let skeleton = relations.map { RouteSuggestion(id: "\($0.from.id)>\($0.to.id)", from: $0.from, to: $0.to, journey: nil, summary: nil, badges: []) }
        if routes.map(\.id) != skeleton.map(\.id) { routes = skeleton }
        guard !relations.isEmpty, let timetable = live.timetable else { return }
        do {
            var queries: [JourneyQuery] = []
            for relation in relations {
                let a = try await resolve(.station(relation.from)), b = try await resolve(.station(relation.to))
                queries.append(JourneyQuery(origin: a, destination: b, date: Date(), products: .all, results: 1, includeStopovers: false))
            }
            let results = try await timetable.journeys(batch: queries)
            var updated = skeleton
            for (index, result) in results.enumerated() where updated.indices.contains(index) {
                if case .success(let page) = result, let journey = page.journeys.first {
                    updated[index].journey = journey
                    updated[index].summary = JourneyPresentation.summary(journey, now: Date())
                    updated[index].badges = journey.rideLegs.compactMap(\.line).map { LineBadge(line: $0, size: .s) }
                }
            }
            withMotion(Motion.smooth) { routes = updated }
        } catch {
            // The relations stay without times (offline behaviour, docs/OEBB_LIVE.md §E12).
        }
    }

    /// The nearest station (from the device's position when the permission is granted, else the home station) with its next
    /// two departures.
    func loadNearby() async {
        var found: (Station, Int?)?
        let index = stations
        if live.isDemo {
            if let s = index.station(named: "Innsbruck Hbf") { found = (s, 120) }
        } else if CLLocationManager().authorizationStatus == .authorizedWhenInUse || CLLocationManager().authorizationStatus == .authorizedAlways {
            let locator = self.locator ?? LocationService()
            self.locator = locator
            if let fix = await locator.currentLocation() {
                let point = GeoPoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
                if let hit = index.nearest(to: point, limit: 1).first { found = (hit.station, Int(hit.distanceKm * 1000)) }
            }
        }
        if found == nil, let id = settings.homeStationID, let home = index.station(id: id) { found = (home, nil) }
        guard let (station, distance) = found else { return }
        var board = NearbyBoard(station: station, distanceMeters: distance, rows: nearby?.station.id == station.id ? (nearby?.rows ?? []) : [])
        nearby = board
        guard let timetable = live.timetable else { return }
        do {
            let location = try await resolve(.station(station))
            let result = try await timetable.board(BoardQuery(station: location, kind: .departures, date: Date(), durationMinutes: 30, maxResults: 2))
            board.rows = Array(BoardPresentation.rows(result).prefix(2))
            withMotion(Motion.smooth) { nearby = board }
        } catch {
            // The station stays without departures.
        }
    }
}

private extension String {
    var nilIfEmptyText: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}
