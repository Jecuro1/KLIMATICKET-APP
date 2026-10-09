import SwiftUI
import SwiftData
import KlimaCore

enum AppTab: String, Hashable, CaseIterable {
    case overview, trips, stats, ticket, add

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .trips: "Fahrten"
        case .stats: "Statistik"
        case .ticket: "Ticket"
        case .add: "Erfassen"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "mountain.2"
        case .trips: "tram.fill"
        case .stats: "chart.bar.fill"
        case .ticket: "ticket.fill"
        case .add: "plus"
        }
    }
}

/// Lightweight transient banner ("Fahrt gespeichert · +€ 22,80").
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String?
}

/// Prefill for the add-trip sheet (from favourites, widgets, intents, deep links, or "nochmal fahren").
struct TripDraft: Identifiable, Equatable {
    var id = UUID()
    var fromStationID: String?
    var toStationID: String?
    var fromName: String = ""
    var toName: String = ""
    var mode: TransportMode = .train
    var date: Date = Date()
    var isRoundTrip: Bool = false
    /// When editing an existing trip.
    var editingTripID: UUID?
}

/// Global app state & services, injected via `.environment(appState)`.
@Observable
@MainActor
final class AppState {
    let config = AppConfig.shared
    /// Bundled reference data (stations.json, the exact ÖBB price table). Built on a background thread that starts in
    /// `init`, so nothing of it runs before the first frame; reading waits only for whatever is left of that build.
    @ObservationIgnored let bundled: BundledData
    var stations: StationIndex { bundled.stations.value }
    var relations: RelationPriceTable { bundled.relations.value }
    private(set) var catalog: TariffCatalog
    let settings: AppSettings
    let auth: AuthService
    let sync: SyncService
    let updates: UpdateService
    let tariffs: TariffService
    let notifications: NotificationService
    let detection: TripDetectionService

    // Navigation / presentation
    var selectedTab: AppTab = .overview
    var tripDraft: TripDraft?
    var toast: Toast?
    var isShowingSettings = false
    var isShowingAchievements = false
    var celebrateBreakEven = false

    @ObservationIgnored private var remoteRefresh: Task<Void, Never>?
    @ObservationIgnored private var pendingOutsideDraft: TripDraft?

    init(settings: AppSettings? = nil) {
        let bundled = BundledData()
        bundled.preload()
        self.bundled = bundled
        self.settings = settings ?? AppSettings()
        let tariffs = TariffService()
        self.tariffs = tariffs
        self.catalog = tariffs.currentCatalog()
        self.auth = AuthService(config: AppConfig.shared)
        self.sync = SyncService(config: AppConfig.shared)
        self.updates = UpdateService(config: AppConfig.shared)
        self.notifications = NotificationService()
        self.detection = TripDetectionService()
        LaunchTrace.mark("state.services")
        // Region events relaunch the app in the background, without UI – so RootView never configures detection.
        // Resolve the monitored stations (region id = station id) and prices lazily instead.
        detection.stationResolver = { id in await bundled.station(id: id) }
        detection.estimatorProvider = { [weak self] in self?.estimator }
    }

    var estimator: FareEstimator { FareEstimator(catalog: catalog, relations: relations) }

    func reloadCatalog() { catalog = tariffs.currentCatalog() }

    /// Called once at launch and when returning to foreground. Concurrent calls share one pass (no duplicate downloads).
    func refreshRemoteContent() async {
        if let running = remoteRefresh {
            await running.value
            return
        }
        let task = Task { @MainActor in
            defer { self.remoteRefresh = nil }
            if await self.tariffs.refreshIfNeeded(manifestHint: self.updates.manifest) { self.reloadCatalog() }
            await self.updates.checkIfDue(force: false)
        }
        remoteRefresh = task
        await task.value
    }

    func showToast(_ symbol: String, _ title: String, _ subtitle: String? = nil) {
        // A failed save was just reported: the caller's "Fahrt gespeichert" right after the write must not replace it.
        if let failedAt = saveFailureReportedAt, Date().timeIntervalSince(failedAt) < 1.5 { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = Toast(symbol: symbol, title: title, subtitle: subtitle) }
        let id = toast?.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if toast?.id == id { withAnimation(.easeOut(duration: 0.3)) { toast = nil } }
        }
    }

    /// Called by Repository when SwiftData could not save. Toasts requested in the next 1.5 s (the caller's success
    /// toast right after the write, also after an `await`) are dropped so they cannot cover the failure.
    func reportSaveFailure() {
        saveFailureReportedAt = nil
        showToast("exclamationmark.triangle.fill", "Speichern fehlgeschlagen", "Noch nicht gesichert – wird erneut versucht")
        saveFailureReportedAt = Date()
    }

    @ObservationIgnored private var saveFailureReportedAt: Date?

    func presentAddTrip(_ draft: TripDraft = TripDraft()) { tripDraft = draft }

    /// "Fahrt erfassen" from outside the current screen (Control Center, Action button, Siri, widget link): RootView
    /// presents the editor, which SwiftUI cannot do while another sheet is up – so the app-level sheets (Einstellungen,
    /// Gipfelbuch, an optional update) are closed first and the editor follows once they are gone. An editor that is
    /// already open keeps its (unsaved) input, and a required update is never covered.
    func presentAddTripFromOutside(_ draft: TripDraft = TripDraft()) {
        guard tripDraft == nil, pendingOutsideDraft == nil else { return }
        if updates.isPresentingSheet && updates.isRequired { return }
        guard isShowingSettings || isShowingAchievements || updates.isPresentingSheet else {
            tripDraft = draft
            return
        }
        pendingOutsideDraft = draft
        isShowingSettings = false
        isShowingAchievements = false
        updates.isPresentingSheet = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // the sheet's dismissal (same delay as FavoritesManagerView)
            if self.tripDraft == nil, let pending = self.pendingOutsideDraft { self.tripDraft = pending }
            self.pendingOutsideDraft = nil
        }
    }
}

/// Bundled reference data, built once on a background thread (JSON decode + search normalisation of ~1.500 stations,
/// zlib inflate of the price table) instead of in `App.init` before the first frame.
final class BundledData: Sendable {
    let stations = Preloaded<StationIndex> { BundledData.loadStations() }
    let relations = Preloaded<RelationPriceTable> { BundledData.loadRelations() }

    /// Starts both builds in the background (called first thing at launch).
    func preload() {
        stations.preload()
        relations.preload()
    }

    /// A station by id – also any stop of the full place index (bus stops, …). Without UI (a background launch for a
    /// region event) nobody attached that index yet: then it is built and attached here. Never blocks the caller.
    func station(id: String) async -> Station? {
        let index = await stations.load()
        if let station = index.station(id: id) { return station }
        guard index.places == nil, let places = try? await PlaceIndexLoader.shared.load() else { return nil }
        index.attach(places: places)
        return index.station(id: id)
    }

    /// Exact ÖBB prices: relations-points.json + raw-DEFLATE compressed relations.bin (UInt16 triples).
    static func loadRelations() -> RelationPriceTable {
        guard let pointsURL = Bundle.main.url(forResource: "relations-points", withExtension: "json"),
              let binURL = Bundle.main.url(forResource: "relations", withExtension: "bin"),
              let pointsData = try? Data(contentsOf: pointsURL),
              let meta = try? JSONDecoder().decode(RelationPriceTable.PointsFile.self, from: pointsData),
              let packed = try? Data(contentsOf: binURL),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data else {
            return .empty
        }
        defer { LaunchTrace.mark("relations.built") }
        return RelationPriceTable(validFrom: meta.validFrom, source: meta.source,
                                  pointIDs: meta.points.map(\.stationID), triples: raw)
    }

    static func loadStations() -> StationIndex {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? StationIndex(jsonData: data) else {
            return StationIndex(stations: [])
        }
        LaunchTrace.mark("stations.built")
        return index
    }
}

/// A value built once, on a background thread when `preload()` ran first. `value` never builds twice: a reader that
/// arrives during the build waits for it (the build keeps running at `userInitiated`), one that arrives first builds it.
final class Preloaded<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    private var build: (@Sendable () -> Value)?

    init(_ build: @escaping @Sendable () -> Value) {
        self.build = build
    }

    /// Starts the build in the background (no-op when it is already built or running).
    func preload(priority: TaskPriority = .userInitiated) {
        Task.detached(priority: priority) { _ = self.value }
    }

    /// The value; waits for a running build.
    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        if let stored { return stored }
        guard let build else { preconditionFailure("Preloaded: neither a value nor a builder") }
        let built = build()
        stored = built
        self.build = nil
        return built
    }

    /// The value without blocking the calling thread (the wait happens in the background).
    func load() async -> Value {
        if let ready = peek { return ready }
        return await Task.detached(priority: .userInitiated) { self.value }.value
    }

    /// The value if it is built (never waits).
    var peek: Value? {
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        return stored
    }
}

/// User preferences backed by UserDefaults (observable).
@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: "onboardingCompleted") } }
    var defaultDiscount: FareDiscount { didSet { defaults.set(defaultDiscount.rawValue, forKey: "defaultDiscount") } }
    var defaultTravelClass: TravelClass { didSet { defaults.set(defaultTravelClass.rawValue, forKey: "defaultTravelClass") } }
    var homeStationID: String? { didSet { defaults.set(homeStationID, forKey: "homeStationID") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") } }
    var autoUpdateCheck: Bool { didSet { defaults.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    var renewalRemindersEnabled: Bool { didSet { defaults.set(renewalRemindersEnabled, forKey: "renewalRemindersEnabled") } }
    var weeklySummaryEnabled: Bool { didSet { defaults.set(weeklySummaryEnabled, forKey: "weeklySummaryEnabled") } }
    var selectedTicketID: UUID? { didSet { defaults.set(selectedTicketID?.uuidString, forKey: "selectedTicketID") } }
    var celebratedBreakEvenTicketIDs: [String] { didSet { defaults.set(celebratedBreakEvenTicketIDs, forKey: "celebratedBreakEven") } }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { self == .system ? "System" : (self == .light ? "Hell" : "Dunkel") }
        var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
        defaultDiscount = FareDiscount(rawValue: defaults.string(forKey: "defaultDiscount") ?? "") ?? .none
        defaultTravelClass = TravelClass(rawValue: defaults.string(forKey: "defaultTravelClass") ?? "") ?? .second
        homeStationID = defaults.string(forKey: "homeStationID")
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        autoUpdateCheck = defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true
        renewalRemindersEnabled = defaults.object(forKey: "renewalRemindersEnabled") as? Bool ?? true
        weeklySummaryEnabled = defaults.bool(forKey: "weeklySummaryEnabled")
        selectedTicketID = defaults.string(forKey: "selectedTicketID").flatMap(UUID.init(uuidString:))
        celebratedBreakEvenTicketIDs = defaults.stringArray(forKey: "celebratedBreakEven") ?? []
    }
}
