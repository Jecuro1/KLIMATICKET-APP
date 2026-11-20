import SwiftUI
import KlimaCore

// MARK: radar2-mine – „Meine Fahrzeuge“ (docs/RADAR_MINE.md, specs/radar2/radarmine.md). Part of `Radar2Parts`, so it lives exactly as long as the
// radar view. Three pages: „Linien“ (remembered lines, highlighted on the map), „In der Nähe“ (vehicles the radar holds around one location fix, which
// stays in memory) and „Haltestelle“ („Wo bleibt mein Bus?“: a departures board every 60 s as a side job of the radar's one loop and budget).
// Remembered lines and the last stops are kept in `RadarMine/mine.json` (`RadarMineStore`); the board, the fix and every position only in memory.

@MainActor
@Observable
final class RadarMineModel {
    typealias Page = RadarMineText.Page

    enum NearState: Equatable {
        /// Before the tap: the explanation and the button.
        case before
        case locating
        case ready
        case denied
        case noFix
    }

    // MARK: Remembered (the file)

    private(set) var file: RadarMineFile {
        didSet { if file.lines != oldValue.lines { cacheLines() } }
    }
    var lines: RadarMineLines { file.lines }
    var highlightOn: Bool { file.highlight && !file.lines.isEmpty }

    // MARK: Panel

    private(set) var isOpen = false
    var page: Page = .lines {
        didSet { if page != oldValue { pageChanged() } }
    }

    // MARK: In der Nähe (memory only, never stored, logged or sent)

    private(set) var nearState: NearState = .before
    /// The one fix of the tap, held while the panel is open.
    private(set) var fix: GeoPoint?
    /// Screenshot launches: a fixed synthetic place drawn as an own dot (no permission prompt, no simulator position).
    private(set) var fixIsSynthetic = false

    // MARK: Haltestelle (memory only)

    private(set) var stop: RadarMineStop?
    @ObservationIgnored private var station: Station?
    @ObservationIgnored private var location: Location?
    private(set) var board: Board?
    private(set) var boardFetchedAt: Date?
    private(set) var boardError: String?
    private(set) var unknownStop = false
    private(set) var plan = RadarStopWatchPlan()
    /// The rows with their positions (rebuilt with every board and every few seconds from the radar's markers).
    private(set) var arrivals: [RadarStopArrival] = []
    /// Row id → number on the map (the first five rows with a position whose mode is drawn).
    private(set) var numbers: [String: Int] = [:]
    /// Trip id → number for the arrivals whose position is the radar's marker (they get the badge instead of a board pin).
    @ObservationIgnored private(set) var numberedTrips: [String: Int] = [:]
    /// MARK: radar2-review-radarmine – the chosen stop's first board still has to frame the stop with its numbered arrivals (once per stop: the
    /// stop's own zoom left three of five numbers under the panel in the CI screenshots).
    @ObservationIgnored private(set) var framePending = false

    // MARK: Inputs from the radar view

    @ObservationIgnored private(set) var gate = RadarFeatureGate()
    @ObservationIgnored private var lowPower = false
    /// The modes whose markers are on the map now (a city mode only in zoom): numbers only for these.
    @ObservationIgnored var shownModes: Set<RadarMode> = Set(RadarModeSelection.default.modes)
    /// „Jetzt aktualisieren“ in Low Power Mode: the job rides the radar's manual round once.
    @ObservationIgnored private var manualRequested = false
    @ObservationIgnored var source: RadarStopBoardSource?
    /// Rebuilds the radar's markers and groups (highlight, numbers): set by the radar view.
    @ObservationIgnored var regroup: (() -> Void)?
    /// The pause line of the stop page, mirrored for the view (the gate itself is not observed).
    private(set) var pause: RadarStopPause? = .panelClosed

    // MARK: Highlight caches (read for every marker, so never observed)

    @ObservationIgnored private var identities: [String: String] = [:]
    /// The remembered lines as a set (read for every marker; rebuilt when the lines change).
    @ObservationIgnored private var wholeLineIDs: Set<String> = []
    @ObservationIgnored private var directedKeys: [RadarLineKey] = []
    @ObservationIgnored private var noIdentity: Set<String> = []
    /// MARK: radar2-review-radarmine – only the trips of the last pass stay single (the cap holds between two passes, `RadarMineHighlight.Selection`).
    @ObservationIgnored private var highlightSelection = RadarMineHighlight.Selection()

    @ObservationIgnored private let store: RadarMineStore
    /// Created on the first tap of „In meiner Nähe zeigen“ (creating it asks nothing).
    @ObservationIgnored private var locationService: LocationService?

    init(store: RadarMineStore? = nil) {
        let store = store ?? RadarMineStore.shared
        self.store = store
        file = store.load()
        cacheLines()
        if let scene = RadarMineDemo.scene { RadarMineDemo.prepare(self, scene: scene) }
    }

    // MARK: The seam (Radar2Parts)

    /// The access closed (consent, „Live-Fahrplan“ off, kill switch, Funktionen „Offline-Modus“): the board, its rows and the fix go, the side job
    /// stops. The remembered lines and stops stay (they are settings, not live data).
    func end(_ reason: RadarEndReason) {
        dropLiveData()
        fix = nil
        fixIsSynthetic = false
        nearState = .before
    }

    /// The departures board of the open stop page, when it is due and the radar may ask; nil: nothing to ask.
    func dueSideJob(now: Date) -> RadarSideJob? {
        // MARK: radar2-review-radarmine – no source yet: nothing to ask (a job without one was cancelled and due again in every round, each time
        // with a slot of the radar's budget)
        guard isOpen, page == .stop, station != nil, source != nil, mayAsk else { return nil }
        guard let job = plan.nextJob(now: now) else { return nil }
        let generation = plan.generation
        return RadarSideJob(id: "mine|\(job.rawValue)|\(generation)") { [weak self] in
            guard let self else { return nil }
            return await self.run(job, generation: generation)
        }
    }

    /// The loop took a slot for the job: it is in flight now.
    func sideJobStarted(_ job: RadarSideJob, at now: Date) {
        let kind = job.id.split(separator: "|").dropFirst().first.flatMap { RadarStopWatchPlan.Job(rawValue: String($0)) } ?? .board
        plan.started(kind, now: now)
        manualRequested = false
    }

    /// The vehicle's line is one you remembered (radartrail draws its trail for „Ausgewählte und meine“).
    func remembers(_ vehicle: RadarVehicle) -> Bool {
        guard !file.lines.isEmpty, let id = identity(of: vehicle) else { return false }
        if wholeLineIDs.contains(id) { return true }
        return directedKeys.contains { $0.matches(vehicle) }
    }

    /// Single markers: the stop page's numbered arrivals, and highlighted vehicles up to the cap (nearest the map's centre).
    func keepsSingle(_ vehicle: RadarVehicle) -> Bool {
        if stopPageShown, numberedTrips[vehicle.tripID] != nil { return true }
        guard highlightOn, remembers(vehicle) else { return false }
        return highlightSelection.keepsSingle(vehicle.tripID)
    }

    /// The Zeitreise card opened: one bottom panel at a time.
    func timeCardOpened() {
        guard isOpen else { return }
        withMotion(Motion.smooth) { close() }
    }

    // MARK: Gate

    /// What is on and open on the radar now (the view calls this whenever it changes).
    func update(gate: RadarFeatureGate, lowPower: Bool) {
        self.gate = gate
        self.lowPower = lowPower
        if !lowPower { manualRequested = false }
        let pause = gate.stopPanelPause(isOpen: isOpen && page == .stop, lowPower: lowPower)
        if pause != self.pause { self.pause = pause }
    }

    /// The radar may ask for the board now: the gate, or a manual round in Low Power Mode.
    private var mayAsk: Bool {
        if gate.stopPanelAsks(isOpen: true, lowPower: lowPower) { return true }
        return lowPower && manualRequested && gate.stopPanelAsks(isOpen: true, lowPower: false)
    }

    // MARK: Panel

    func open(page: Page? = nil) {
        if let page { self.page = page }
        isOpen = true
        update(gate: gate, lowPower: lowPower)
        if self.page == .stop, stop != nil { plan.interact(now: Date()) }
    }

    func close() {
        isOpen = false
        // The fix and the board are for this look only; the remembered lines and stops stay.
        fix = nil
        fixIsSynthetic = false
        if nearState != .denied { nearState = .before }
        dropLiveData()
        update(gate: gate, lowPower: lowPower)
    }

    private func pageChanged() {
        update(gate: gate, lowPower: lowPower)
        if page == .stop, stop != nil {
            plan.interact(now: Date())
        }
        regroupIfNeeded()
    }

    /// The board, its rows and its numbers go; the stop stays chosen until the panel closes.
    private func dropLiveData() {
        plan.stop()
        board = nil
        boardFetchedAt = nil
        boardError = nil
        unknownStop = false
        arrivals = []
        numbers = [:]
        let hadNumbers = !numberedTrips.isEmpty
        numberedTrips = [:]
        stop = nil
        station = nil
        location = nil
        framePending = false
        if hadNumbers { regroup?() }
    }

    // MARK: Linien

    enum RememberResult { case added, removed, full, notALine }

    /// „Linie merken“ / „Gemerkt“ in the trip sheet.
    @discardableResult
    func toggleRemember(_ vehicle: RadarVehicle) -> RememberResult {
        guard let key = RadarLineKey(vehicle: vehicle) else { return .notALine }
        if remembers(vehicle) {
            file.lines.remove(lineOf: vehicle)
            save()
            regroupIfNeeded(always: file.highlight)
            return .removed
        }
        switch file.lines.add(key) {
        case .added, .alreadyThere:
            save()
            regroupIfNeeded(always: file.highlight)
            return .added
        case .full:
            return .full
        }
    }

    func forget(_ key: RadarLineKey) {
        file.lines.remove(id: key.id)
        save()
        regroupIfNeeded(always: file.highlight)
    }

    func forgetAllLines() {
        file.lines.removeAll()
        file.highlight = false
        save()
        regroup?()
    }

    func forgetRecentStops() {
        file.stops = []
        save()
    }

    func setHighlight(_ on: Bool) {
        guard file.highlight != on else { return }
        file.highlight = on
        save()
        regroup?()
    }

    private func save() {
        store.save(file)
    }

    /// Demo and CI scenes only: the scene's lines and stops (screenshot launches keep the file in memory).
    func adoptDemo(_ file: RadarMineFile) {
        self.file = file
        save()
    }

    private func cacheLines() {
        wholeLineIDs = file.lines.wholeLineIDs
        directedKeys = file.lines.directedKeys
    }

    /// The line identity of a vehicle, cached per trip (a trip never changes its line).
    private func identity(of vehicle: RadarVehicle) -> String? {
        if let id = identities[vehicle.tripID] { return id }
        if noIdentity.contains(vehicle.tripID) { return nil }
        if identities.count + noIdentity.count > 6000 {
            identities = [:]
            noIdentity = []
        }
        guard let id = vehicle.line.flatMap(RadarLineKey.identity(of:))?.id else {
            noIdentity.insert(vehicle.tripID)
            return nil
        }
        identities[vehicle.tripID] = id
        return id
    }

    /// The vehicles the radar holds of one remembered line.
    func vehicles(of key: RadarLineKey, in vehicles: [RadarVehicle]) -> [RadarVehicle] {
        vehicles.filter { identity(of: $0) == key.lineID && (key.direction == nil || key.matches($0)) }
    }

    /// The highlighted markers that stay single: all of them up to 60, else the 60 nearest the map's centre (called by the view every few
    /// seconds while the highlight is on, and at once when it changes). A vehicle of your lines that came in since the last pass groups until
    /// the next one, so there are never more than 60.
    func refreshHighlightSingles(pins: [RadarPin], centre: GeoPoint) {
        guard highlightOn else {
            if highlightSelection.clear() { regroup?() }
            return
        }
        let candidates = pins.filter { remembers($0.vehicle) }.map { RadarMineHighlight.Candidate(tripID: $0.id, coordinate: $0.coordinate) }
        if highlightSelection.update(candidates, centre: centre) { regroup?() }
    }

    /// The stop page is what the panel shows: its numbers and lines are on the map.
    var stopPageShown: Bool { isOpen && page == .stop && stop != nil }

    private func regroupIfNeeded(always: Bool = false) {
        if always || !numberedTrips.isEmpty { regroup?() }
    }

    /// The decoration of one marker: the numbered arrivals of the stop page, then the highlight (star) and the dimmed rest.
    func decoration(for pin: RadarPin) -> RadarMarkerDecoration {
        if stopPageShown, !numbers.isEmpty {
            if let number = numberedTrips[pin.id] { return RadarMarkerDecoration(emphasis: .highlighted, badge: .number(number)) }
            return RadarMarkerDecoration(emphasis: .dimmed)
        }
        guard highlightOn else { return .plain }
        return remembers(pin.vehicle) ? RadarMarkerDecoration(emphasis: .highlighted, badge: .star) : RadarMarkerDecoration(emphasis: .dimmed)
    }

    // MARK: In der Nähe

    /// „In meiner Nähe zeigen“: the only path to the location. One fix (when-in-use, asked only now if never asked), kept in memory.
    func locate() async -> GeoPoint? {
        if LaunchMode.isSandboxed {
            setSyntheticFix(RadarMineDemo.place)
            return fix
        }
        let service = locationService ?? LocationService()
        locationService = service
        guard !service.isDenied else {
            nearState = .denied
            return nil
        }
        nearState = .locating
        let location = await service.currentLocation()
        // MARK: radar2-review-radarmine – the panel closed (or the access ended) meanwhile: the fix is not wanted any more. Another page is no
        // reason to drop it: before, the page stayed at „Suche deinen Standort …“ without a button when you came back. The fix is held (the page
        // offers „Zum Umkreis“), but the map moves only while the page is shown.
        guard isOpen, nearState == .locating else { return nil }
        guard let location else {
            nearState = service.isDenied ? .denied : .noFix
            return nil
        }
        fix = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        fixIsSynthetic = false
        nearState = .ready
        return page == .near ? fix : nil
    }

    /// Screenshot and demo scenes: a fixed invented place, never the device's.
    func setSyntheticFix(_ point: GeoPoint) {
        fix = point
        fixIsSynthetic = true
        nearState = .ready
    }

    /// The denied state of the CI scene (simulated: no prompt, no system state).
    func simulateDenied() {
        nearState = .denied
    }

    /// The fix is the device's own (the blue dot may be drawn).
    var hasLiveFix: Bool { fix != nil && !fixIsSynthetic && isOpen && page == .near }

    // MARK: Haltestelle

    /// A stop was chosen (search, map centre, near you, recent): the board is due at once.
    func choose(_ station: Station) {
        let chosen = RadarMineStop(id: station.id, name: station.name, coordinate: station.location)
        board = nil
        boardFetchedAt = nil
        boardError = nil
        unknownStop = false
        arrivals = []
        numbers = [:]
        let hadNumbers = !numberedTrips.isEmpty
        numberedTrips = [:]
        self.station = station
        location = nil
        stop = chosen
        plan.start(stopID: station.id, needsLink: source?.needsLink(station) ?? false, now: Date())
        framePending = true
        file.noteStop(chosen)
        save()
        if hadNumbers { regroup?() }
    }

    /// The first board framed the stop and its arrivals (or had nothing to frame).
    func didFrame() { framePending = false }

    /// „Andere Haltestelle“: back to the picker.
    func clearStop() {
        let hadNumbers = !numberedTrips.isEmpty
        framePending = false
        plan.stop()
        stop = nil
        station = nil
        location = nil
        board = nil
        boardFetchedAt = nil
        boardError = nil
        unknownStop = false
        arrivals = []
        numbers = [:]
        numberedTrips = [:]
        if hadNumbers { regroup?() }
    }

    /// A tap on the page: the idle clock starts again.
    func interact() {
        let wasIdle = plan.isIdle(now: Date())
        plan.interact(now: Date())
        if wasIdle { pause = gate.stopPanelPause(isOpen: isOpen && page == .stop, lowPower: lowPower) }
    }

    var isIdle: Bool { plan.isIdle(now: Date()) }

    /// „Jetzt aktualisieren“ (Low Power Mode, idle): due at once; in Low Power Mode it rides the radar's manual round.
    func refreshNow() {
        plan.refreshNow(now: Date())
        if lowPower { manualRequested = true }
    }

    /// The stop page is waiting for its first answer.
    var isLoadingBoard: Bool { stop != nil && board == nil && boardError == nil && !unknownStop }

    /// The rows with the radar's newest positions; numbers for the modes on the map. `held`: what the radar holds of the board's trips.
    func refreshArrivals(held: [String: RadarHeldVehicle], now: Date = Date()) {
        guard let board, let boardFetchedAt else {
            if !arrivals.isEmpty { arrivals = [] }
            return
        }
        let rows = RadarStopArrivals.rows(board: board, fetchedAt: boardFetchedAt, stop: stop?.coordinate, radar: held, now: now)
        let numbers = RadarStopArrivals.numbers(rows, shownModes: self.shownModes)
        var trips: [String: Int] = [:]
        for row in rows where row.source == .radar { if let n = numbers[row.id] { trips[row.tripID] = n } }
        if rows != arrivals { arrivals = rows }
        if numbers != self.numbers { self.numbers = numbers }
        if trips != numberedTrips {
            numberedTrips = trips
            regroup?()
        }
    }

    /// Groups of markers step back while your lines are highlighted (unless one of yours is inside) or the stop page numbers its arrivals.
    func groupOpacity(_ tripIDs: [String], vehicle: (String) -> RadarVehicle?) -> Double {
        if stopPageShown, !numbers.isEmpty { return 0.35 }
        guard highlightOn else { return 1 }
        return groupHoldsMine(tripIDs, vehicle: vehicle) ? 1 : 0.35
    }

    /// MARK: radar2-review-radarmine – a group that holds a vehicle of your lines (beyond the 60 single markers) gets the star on its ring (spec §7);
    /// before, only its full opacity told it apart.
    func groupHoldsMine(_ tripIDs: [String], vehicle: (String) -> RadarVehicle?) -> Bool {
        guard highlightOn, !(stopPageShown && !numbers.isEmpty) else { return false }
        return tripIDs.contains { id in vehicle(id).map(remembers) ?? false }
    }

    /// The trip ids of the board (the view looks only these up in the radar's store).
    var boardTripIDs: [String] { board?.entries.map(\.tripID) ?? [] }

    // MARK: The side job

    private func run(_ job: RadarStopWatchPlan.Job, generation: Int) async -> Error? {
        guard let source, let station else {
            if generation == plan.generation { plan.cancelled() }
            return nil
        }
        do {
            let location: Location
            if let linked = self.location {
                location = linked
            } else {
                location = try await source.link(station)
                guard generation == plan.generation else { return nil }
                self.location = location
                if job == .link {
                    plan.linked(now: Date())
                    return nil
                }
            }
            // MARK: radar2-review-radarmine – the board's positions belong to the moment it was asked, as the radar's tiles do (`RadarModel.fetch`):
            // „Stand“ and „vor 12 s“ were the answer's arrival, so a slow answer looked fresher than it was, and the radar's newer answer of the
            // same trip was compared with the wrong moment.
            let askedAt = Date()
            let board = try await source.board(at: location, station: station, now: askedAt)
            guard generation == plan.generation else { return nil }
            self.board = board
            boardFetchedAt = askedAt
            boardError = nil
            plan.answered(now: Date())
            return nil
        } catch is CancellationError {
            if generation == plan.generation { plan.cancelled() }
            return nil
        } catch {
            guard generation == plan.generation else { return error }
            if let live = error as? LiveError, case .hafas(code: "LOCATION", _) = live {
                if self.location != nil {
                    // The board refused a stored station link: forget it; the next slot links the stop again (one request per slot).
                    // MARK: radar2-review-radarmine – once per stop: a board that refuses the new link as well ends the stop below. Before, every
                    // refusal linked anew and asked again at once, so a stop the board never takes (a `uic:` id it does not know, a LocMatch hit
                    // that is no stop) took a slot in every round of the loop – up to the radar's whole 24 a minute, and the tiles starved.
                    self.location = nil
                    await source.forget(station)
                    guard generation == plan.generation else { return nil }   // another stop was chosen meanwhile
                    if plan.linkRefused(needsLink: source.needsLink(station), now: Date()) { return nil }
                }
                // The stop has no ÖBB station: say so instead of asking again every minute.
                unknownStop = true
                plan.stop()
                return nil
            }
            plan.failed(now: Date())
            boardError = LiveMessage.text(for: error)
            return error
        }
    }
}
