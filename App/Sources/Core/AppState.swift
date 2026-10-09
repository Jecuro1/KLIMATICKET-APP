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
        case .overview: "gauge.with.needle"
        case .trips: "list.bullet.rectangle.portrait"
        case .stats: "chart.xyaxis.line"
        case .ticket: "wallet.pass"
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
    let stations: StationIndex
    let relations: RelationPriceTable
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

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? AppSettings()
        self.stations = AppState.loadStations()
        self.relations = AppState.loadRelations()
        let tariffs = TariffService()
        self.tariffs = tariffs
        self.catalog = tariffs.currentCatalog()
        self.auth = AuthService(config: AppConfig.shared)
        self.sync = SyncService(config: AppConfig.shared)
        self.updates = UpdateService(config: AppConfig.shared)
        self.notifications = NotificationService()
        self.detection = TripDetectionService()
    }

    var estimator: FareEstimator { FareEstimator(catalog: catalog, relations: relations) }

    func reloadCatalog() { catalog = tariffs.currentCatalog() }

    /// Called once at launch and when returning to foreground.
    func refreshRemoteContent() async {
        if await tariffs.refreshIfNeeded(manifestHint: updates.manifest) { reloadCatalog() }
        await updates.checkIfDue(force: false)
    }

    func showToast(_ symbol: String, _ title: String, _ subtitle: String? = nil) {
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = Toast(symbol: symbol, title: title, subtitle: subtitle) }
        let id = toast?.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if toast?.id == id { withAnimation(.easeOut(duration: 0.3)) { toast = nil } }
        }
    }

    func presentAddTrip(_ draft: TripDraft = TripDraft()) { tripDraft = draft }

    /// Exact ÖBB prices: relations-points.json + raw-DEFLATE compressed relations.bin (UInt16 triples).
    private static func loadRelations() -> RelationPriceTable {
        guard let pointsURL = Bundle.main.url(forResource: "relations-points", withExtension: "json"),
              let binURL = Bundle.main.url(forResource: "relations", withExtension: "bin"),
              let pointsData = try? Data(contentsOf: pointsURL),
              let meta = try? JSONDecoder().decode(RelationPriceTable.PointsFile.self, from: pointsData),
              let packed = try? Data(contentsOf: binURL),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data else {
            return .empty
        }
        return RelationPriceTable(validFrom: meta.validFrom, source: meta.source,
                                  pointIDs: meta.points.map(\.stationID), triples: raw)
    }

    private static func loadStations() -> StationIndex {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? StationIndex(jsonData: data) else {
            return StationIndex(stations: [])
        }
        return index
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
