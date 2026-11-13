import Foundation
import Observation
import KlimaCore

// Pendel-Modus (docs/COMMUTE.md): the state of the Übersicht card. One search per refresh, only while the card is on screen,
// the app is in the foreground and the live window is open – at most once a minute (`CommuteSearch.minRefreshInterval`). The
// search goes through `CommuteSearch.connections`, which refuses before any I/O when `LiveDataService.timetable` is nil (no
// consent, switched off, kill switch, offline); the HAFAS client below it shares the app-wide `RequestThrottle`.
// No background work, no notification, no widget cache: the card says „aktualisiert beim Öffnen“.

@MainActor
@Observable
final class CommuteModel {
    static let shared = CommuteModel()

    enum Failure: Equatable {
        /// No network: the last rows stay (marked) or the plan shows.
        case offline
        /// Live data is not available (consent, switch, kill switch).
        case unavailable
        /// The search found nothing (or a station could not be matched).
        case noConnection
        /// Anything else (rate limit, server error): the last rows stay.
        case failed
    }

    enum Phase: Equatable { case idle, loading, loaded, failed(Failure) }

    /// What the rows were searched for.
    struct FetchKey: Hashable {
        var direction: CommuteDirection
        var slotDeparture: Date
    }

    let store: CommuteSettingsStore
    private(set) var phase: Phase = .idle
    /// Every connection of the last search (the card shows three; the advisor looks at all).
    private(set) var rows: [CommuteRow] = []
    private(set) var fetchedAt: Date?
    private(set) var rowsKey: FetchKey?
    /// The direction picked on the card for one slot („Richtung tauschen“); it ends with that slot.
    private(set) var directionOverride: (slot: CommuteSlot, direction: CommuteDirection)?
    /// klimabilanz://commute: the card pulses once.
    var focusTick = 0
    /// klimabilanz://commute while the mode is off: the setup page opens over the Übersicht.
    var showsSetup = false
    /// The guess of the detector for the invitation (computed off the body, see `CommuteCardSection`).
    var guess: CommuteGuess?

    @ObservationIgnored private var journeys: [String: Journey] = [:]
    @ObservationIgnored private var isFetching = false
    /// CI scenes: a fixed clock, fixed journeys and a fixed live availability. Never set outside screenshot runs.
    @ObservationIgnored private(set) var demo: CommuteDemoScene?

    init(store: CommuteSettingsStore = .shared) {
        self.store = store
    }

    var settings: CommuteSettings { store.settings }

    /// The card's clock (a demo scene pins it).
    func now() -> Date { demo?.now ?? Date() }

    func windowState(at date: Date) -> CommuteWindow.State {
        CommuteWindow.state(at: date, plan: settings.plan, calendar: .vienna)
    }

    /// The direction shown for `slot`: the slot's own, unless swapped on the card.
    func direction(for slot: CommuteSlot) -> CommuteDirection {
        if let o = directionOverride, o.slot == slot { return o.direction }
        return slot.direction
    }

    func swapDirection(for slot: CommuteSlot) {
        let next = direction(for: slot).opposite
        directionOverride = next == slot.direction ? nil : (slot, next)
    }

    /// Start and end for a direction.
    func ends(_ direction: CommuteDirection) -> (from: CommuteEndpoint, to: CommuteEndpoint)? {
        guard let origin = settings.origin, let destination = settings.destination else { return nil }
        return direction == .outbound ? (origin, destination) : (destination, origin)
    }

    /// Why live rows cannot be shown (nil: they can).
    func liveUnavailable(_ live: LiveDataService) -> LiveDataService.Unavailable? {
        if let demo { return demo.liveUnavailable }
        return live.timetableUnavailable
    }

    /// The rows still ahead at `date` (a train leaves the card a minute after it left).
    func visibleRows(at date: Date) -> [CommuteRow] {
        rows.filter { ($0.isCancelled ? $0.plannedDeparture : $0.effectiveDeparture) >= date.addingTimeInterval(-CommuteStatus.graceSeconds) }
    }

    func journey(for row: CommuteRow) -> Journey? { journeys[row.id] }

    // MARK: Refresh

    /// One search for `slot` in its shown direction. Skipped when the same rows are younger than a minute (unless the
    /// direction or slot changed), while another search runs, or without live data.
    func refresh(app: AppState, slot: CommuteSlot, force: Bool = false) async {
        let direction = direction(for: slot)
        let key = FetchKey(direction: direction, slotDeparture: slot.departure)
        if key == rowsKey, !CommuteSearch.mayRefresh(lastFetch: fetchedAt, now: now()) { return }
        guard !isFetching else { return }
        if key != rowsKey {
            rows = []
            journeys = [:]
            fetchedAt = nil
        }
        if rows.isEmpty { phase = .loading }
        isFetching = true
        defer { isFetching = false }
        do {
            let page = try await search(app: app, direction: direction)
            let at = now()
            let built = CommuteStatus.rows(page.journeys, now: at)
            var byID: [String: Journey] = [:]
            for journey in page.journeys { byID[journey.id] = journey }
            withMotion(Motion.smooth) {
                rows = built
                journeys = byID
                fetchedAt = at
                rowsKey = key
                phase = built.isEmpty ? .failed(.noConnection) : .loaded
            }
            if let ends = ends(direction) {
                CommuteSnapshotStore.save(CommuteSnapshot(fetchedAt: at, direction: direction, destinationName: ends.to.name, rows: built))
            }
        } catch is CancellationError {
            if rows.isEmpty { phase = .idle }
        } catch {
            rowsKey = key
            withMotion(Motion.smooth) { phase = .failed(Self.failure(error)) }
        }
    }

    private func search(app: AppState, direction: CommuteDirection) async throws -> JourneyPage {
        if let demo { return demo.page(direction: direction) }
        guard let ends = ends(direction), let fromID = ends.from.stationID, let toID = ends.to.stationID else {
            throw LiveError.noConnection
        }
        // Without live data nothing below runs – not even the station lookup (CommuteSearch refuses first).
        let timetable = app.live.timetable
        guard timetable != nil else { throw CommuteLiveError.consentRequired }
        guard let from = await Self.station(fromID, app: app), let to = await Self.station(toID, app: app) else {
            throw LiveError.noConnection
        }
        let linker = app.live.linker
        do {
            return try await CommuteSearch.connections(timetable: timetable, at: now()) {
                (try await linker.hafasLocation(for: from), try await linker.hafasLocation(for: to))
            }
        } catch LiveError.hafas(code: "LOCATION", _) {
            await linker.invalidate(stationID: from.id)
            await linker.invalidate(stationID: to.id)
            throw LiveError.noConnection
        }
    }

    static func station(_ id: String, app: AppState) async -> Station? {
        if let known = app.stations.station(id: id) { return known }
        return await app.bundled.station(id: id)
    }

    private static func failure(_ error: Error) -> Failure {
        if let commute = error as? CommuteLiveError, commute == .consentRequired { return .unavailable }
        guard let live = error as? LiveError else { return .failed }
        switch live {
        case .offline: return .offline
        case .disabled: return .unavailable
        case .noConnection, .hafas: return .noConnection
        default: return .failed
        }
    }

    // MARK: Lifecycle

    /// klimabilanz://commute: the card pulses once when the mode is set up, else the setup opens over the Übersicht.
    func openFromLink() {
        if settings.isActive { focusTick &+= 1 } else { showsSetup = true }
    }

    /// The settings changed (route, plan, mode): the rows belong to the old ones.
    func settingsChanged() {
        rows = []
        journeys = [:]
        fetchedAt = nil
        rowsKey = nil
        directionOverride = nil
        phase = .idle
    }

    /// A CI scene: pins the clock, the journeys and the availability; puts the scene's settings in the (memory-only) store.
    func install(_ scene: CommuteDemoScene) {
        guard LaunchMode.isSandboxed else { return }
        demo = scene
        store.replace(with: scene.settings)
        guess = scene.guess
        settingsChanged()
    }

    /// „Alle Daten löschen“: the Stammstrecke, the cached rows for Siri and queued Siri logs go.
    func deleteAll() {
        store.reset()
        settingsChanged()
        guess = nil
        CommuteSnapshotStore.save(nil)
        CommuteLogQueue.clear()
    }
}

// MARK: - Snapshot for Siri

/// The rows of the last search, for „Wann fährt mein nächster Zug?“ while the app is closed (no request from Siri: nothing
/// runs in the background but „Live verfolgen“, docs/OEBB_LIVE.md §2). App-only UserDefaults; not in screenshot/perf runs.
struct CommuteSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var direction: CommuteDirection
    var destinationName: String
    var rows: [CommuteRow]

    /// Older answers are not read out: delays change too quickly.
    static let maxAge: TimeInterval = 15 * 60
}

enum CommuteSnapshotStore {
    static let key = "commute.snapshot.v1"

    static func save(_ snapshot: CommuteSnapshot?) {
        guard !LaunchMode.isSandboxed else { return }
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> CommuteSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CommuteSnapshot.self, from: data)
    }
}
