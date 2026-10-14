import Foundation
import Observation
import KlimaCore

/// The one door to the live layer (docs/OEBB_LIVE.md §E2, decisions D5/D6): consent, the two feature switches, the remote
/// kill switch, connectivity and the services the UI talks to.
///
/// **Nothing leaves the app without consent.** Three independent layers make sure of it:
/// 1. `timetable` / `priceProvider` are `nil` unless live data is available – every planner call goes through them.
/// 2. The clients themselves only ever see an *effective* config in which every provider is switched off while consent
///    is undecided or declined, a feature is off or the kill switch is set (they then throw `LiveError.disabled`
///    before any I/O).
/// 3. The remote config is fetched only while consent is granted.
///
/// The client stack (transport, throttle, health, HAFAS, shop, VAO, linker, price service) is built on first use – a
/// launch without live data never creates it. In demo mode (`-KBDemo`) the planner runs on `DemoTimetableService` /
/// `DemoPriceProvider` and the network is never touched.
@MainActor @Observable
final class LiveDataService {
    enum Consent: String { case undecided, granted, declined }

    /// Why a live surface is unavailable – drives the planner's consent / offline / off states.
    enum Unavailable: Equatable {
        case consentUndecided, declined, switchedOff, killSwitch(notice: String?), offline
    }

    // MARK: Observable state

    private(set) var config: LiveConfig
    private(set) var isOnline = true
    private(set) var health: [LiveProvider: LiveHealth.Status] = [:]
    /// Bumped whenever availability may have changed (consent, switches, kill switch) – views that cache a service reload.
    private(set) var generation = 0

    let isDemo: Bool
    var rideActivity: any RideActivityControlling = NoopRideActivityController()

    // MARK: Dependencies

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let appConfig: AppConfig
    @ObservationIgnored private let stationsProvider: () -> StationIndex
    @ObservationIgnored private let relationsProvider: () -> RelationPriceTable
    @ObservationIgnored private var catalog: TariffCatalog
    @ObservationIgnored private let store: LiveConfigStore
    @ObservationIgnored private let connectivity = Connectivity()
    @ObservationIgnored private var stackStorage: Stack?
    @ObservationIgnored private var coverageStorage: CoverageEvaluator??
    @ObservationIgnored private var started = false

    /// The client stack – built lazily, shared by every live call.
    private struct Stack {
        let transport: any HTTPTransport
        let throttle: RequestThrottle
        let health: LiveHealth
        let hafas: HafasClient
        let shop: OebbShopClient
        let verbund: VerbundTariffClient
        let linker: StationLinker
        let prices: LivePriceService
    }

    /// `stations` / `relations` are providers, not values: the bundled data is built on a background thread at launch and
    /// reading it early would block the first frame. They are called when the live stack is first needed.
    init(appConfig: AppConfig, settings: AppSettings, catalog: TariffCatalog,
         stations: @escaping () -> StationIndex, relations: @escaping () -> RelationPriceTable,
         demo: Bool = LaunchMode.useDemoData || LaunchMode.isSandboxed, store: LiveConfigStore = LiveConfigStore()) {
        self.appConfig = appConfig
        self.settings = settings
        self.catalog = catalog
        self.stationsProvider = stations
        self.relationsProvider = relations
        self.isDemo = demo
        self.store = store
        self.config = demo ? LiveConfig.default : store.load()
    }

    // MARK: Consent and switches

    var consent: Consent {
        get { Consent(rawValue: settings.liveConsentRaw) ?? .undecided }
        set { setConsent(newValue) }
    }

    var isTimetableEnabledBySettings: Bool { settings.liveTimetableEnabled }
    var isLivePriceEnabledBySettings: Bool { settings.livePricesEnabled }

    /// „Aktivieren“ / „Nur Offline-Daten“ / the master toggle. Granting starts the config refresh; declining keeps the app
    /// offline exactly as before.
    func setConsent(_ newValue: Consent) {
        guard settings.liveConsentRaw != newValue.rawValue else { return }
        settings.liveConsentRaw = newValue.rawValue
        WidgetCacheSync.consentDidChange(newValue)   // MARK: widgets – the widgets mirror the consent; withdrawn = caches emptied
        switchesChanged()
        if newValue == .granted {
            beginMonitoring()
            Task { await refreshConfigIfDue(manifest: nil) }
        } else {
            connectivity.stop()
        }
    }

    func setTimetableEnabled(_ on: Bool) {
        guard settings.liveTimetableEnabled != on else { return }
        settings.liveTimetableEnabled = on
        switchesChanged()
    }

    func setPricesEnabled(_ on: Bool) {
        guard settings.livePricesEnabled != on else { return }
        settings.livePricesEnabled = on
        switchesChanged()
    }

    private func switchesChanged() {
        generation &+= 1
        Task { await pushEffectiveConfig() }
    }

    // MARK: Availability

    var isTimetableAvailable: Bool { timetableUnavailable == nil }
    var isLivePriceAvailable: Bool { priceUnavailable == nil }

    var timetableUnavailable: Unavailable? {
        if isDemo { return nil }
        if let reason = consentBlock { return reason }
        if !settings.liveTimetableEnabled { return .switchedOff }
        if !config.isEnabled(.oebbHafas) { return .killSwitch(notice: config.notice) }
        if !isOnline { return .offline }
        return nil
    }

    var priceUnavailable: Unavailable? {
        if isDemo { return nil }
        if let reason = consentBlock { return reason }
        if !settings.livePricesEnabled { return .switchedOff }
        if !(config.isEnabled(.oebbShop) || config.isEnabled(.vaoTariff)) { return .killSwitch(notice: config.notice) }
        if !isOnline { return .offline }
        return nil
    }

    private var consentBlock: Unavailable? {
        switch consent {
        case .undecided: return .consentUndecided
        case .declined: return .declined
        case .granted: return config.killSwitch ? .killSwitch(notice: config.notice) : nil
        }
    }

    // MARK: Services

    /// The journey planner – nil whenever live data is not available (the only way the UI reaches HAFAS).
    var timetable: (any TimetableService)? {
        if isDemo { return DemoTimetableService() }
        guard isTimetableAvailable else { return nil }
        return stack.hafas
    }

    /// Zug-Radar positions (`JourneyGeoPos`) – same gate as the timetable (consent, switch, kill switch, connectivity).
    var radar: (any RadarService)? {
        if isDemo { return DemoRadarService() }
        guard isTimetableAvailable else { return nil }
        return stack.hafas
    }

    /// Live prices – nil whenever they are not available.
    var priceProvider: (any LivePriceProvider)? {
        if isDemo { return DemoPriceProvider() }
        guard isLivePriceAvailable else { return nil }
        return stack.prices
    }

    /// Offline-capable pricing (table → city ticket → distance model). Never makes a request by itself.
    var prices: LivePriceService { stack.prices }

    /// App station ⇄ live location. Its HAFAS lookups are gated by the effective config like every other client.
    var linker: StationLinker { stack.linker }

    /// KlimaTicket coverage rules from `coverage_rules.json` (nil when missing or invalid).
    var coverage: CoverageEvaluator? {
        if let cached = coverageStorage { return cached }
        var evaluator: CoverageEvaluator?
        if let url = Bundle.main.url(forResource: "coverage_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            evaluator = try? CoverageEvaluator(rulesJSON: data, stations: stationsProvider())
        }
        coverageStorage = .some(evaluator)
        return evaluator
    }

    var stations: StationIndex { stationsProvider() }

    var estimator: FareEstimator { FareEstimator(catalog: catalog, relations: relationsProvider()) }

    func ticketScope(productID: String?) -> TicketScope {
        guard let productID else { return .unsupported }
        return coverage?.scope(forProductID: productID) ?? .unsupported
    }

    /// The regular price of a request: demo → the demo provider (falls back to the offline chain), else live when
    /// available and offline otherwise. Never throws, never waits longer than the price service's 12 s budget.
    func quote(_ request: PriceRequest) async -> PriceQuote {
        if isDemo {
            if let demo = try? await DemoPriceProvider().livePrice(request) { return demo }
            return await stack.prices.offlineQuote(request)
        }
        return await stack.prices.quote(request, allowLive: isLivePriceAvailable)
    }

    /// Instant, no I/O (relation table → city ticket → distance model).
    func offlineQuote(_ request: PriceRequest) async -> PriceQuote {
        await stack.prices.offlineQuote(request)
    }

    // MARK: Lifecycle

    /// Cached config → connectivity → remote refresh (only with consent) → health.
    func start() async {
        guard !started, !isDemo else { return }
        started = true
        if consent == .granted {
            beginMonitoring()
            await refreshConfigIfDue(manifest: nil)
        }
        await refreshHealth()
    }

    private func beginMonitoring() {
        guard !isDemo else { return }
        connectivity.onChange = { [weak self] online in
            guard let self, self.isOnline != online else { return }
            self.isOnline = online
            self.generation &+= 1
        }
        connectivity.start()
    }

    /// At most every 12 h, only with consent. The URL comes from the update manifest, else from the build.
    func refreshConfigIfDue(manifest: UpdateManifest?) async {
        guard !isDemo, consent == .granted, store.isDue() else { return }
        let url = manifest?.liveConfigURL.flatMap(URL.init(string:)) ?? appConfig.remoteLiveConfig
        guard let url else { return }
        let agent = config.userAgent.replacingOccurrences(of: "{version}", with: AppConfig.appVersion)
        if let next = await store.fetch(from: url, current: config, userAgent: agent) {
            config = next
            generation &+= 1
            await pushEffectiveConfig()
        }
    }

    func catalogDidChange(_ catalog: TariffCatalog) async {
        self.catalog = catalog
        guard let stack = stackStorage else { return }
        await stack.prices.update(estimator: FareEstimator(catalog: catalog, relations: relationsProvider()))
    }

    func refreshHealth() async {
        guard let stack = stackStorage else { return }
        health = await stack.health.status()
    }

    /// Settings „Live-Cache leeren“.
    func resetCaches() async {
        WidgetCacheSync.liveCachesDidReset()   // MARK: widgets – the widgets' live caches go too
        guard let stack = stackStorage else { return }
        await stack.prices.clearCache()
        await stack.health.reset()
        await stack.hafas.update(config: effectiveConfig)
        health = await stack.health.status()
    }

    /// Settings „Verbindung testen“: one ServerInfo request. false without consent, switched off or offline.
    func testConnection() async -> Bool {
        guard !isDemo else { return true }
        guard isTimetableAvailable else { return false }
        let stack = self.stack
        await stack.health.reset(.oebbHafas)
        let ok = (try? await stack.hafas.serverInfo()) != nil
        health = await stack.health.status()
        return ok
    }

    // MARK: Stack

    /// The config the clients see: a provider is only enabled while its feature is on *and* consent is granted.
    private var effectiveConfig: LiveConfig {
        var c = config
        let consented = consent == .granted
        let timetable = consented && settings.liveTimetableEnabled
        let priceOn = consented && settings.livePricesEnabled
        c.hafas.enabled = c.hafas.enabled && timetable
        if var fallback = c.hafasFallback {
            fallback.enabled = fallback.enabled && timetable
            c.hafasFallback = fallback
        }
        c.shop.enabled = c.shop.enabled && priceOn
        c.vao.enabled = c.vao.enabled && priceOn
        return c
    }

    private func pushEffectiveConfig() async {
        guard let stack = stackStorage else { return }
        let effective = effectiveConfig
        await stack.hafas.update(config: effective)
        await stack.shop.update(config: effective)
        await stack.verbund.update(config: effective)
        await stack.prices.update(config: effective)
    }

    private var stack: Stack {
        if let stackStorage { return stackStorage }
        let effective = effectiveConfig
        let version = AppConfig.appVersion
        let transport = LiveURLSessionTransport()
        let throttle = RequestThrottle()
        let healthActor = LiveHealth()
        let hafas = HafasClient(config: effective, transport: transport, throttle: throttle, health: healthActor, appVersion: version)
        let shop = OebbShopClient(config: effective, transport: transport, throttle: throttle, health: healthActor, appVersion: version)
        let verbund = VerbundTariffClient(config: effective, transport: transport, throttle: throttle, health: healthActor,
                                          appVersion: version)
        let index = stationsProvider()
        let dir = URL.cachesDirectory.appending(path: "Live", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let linker = StationLinker(stations: index, timetable: hafas, vao: verbund,
                                   cacheURL: dir.appending(path: "stations-link.json", directoryHint: .notDirectory))
        let prices = LivePriceService(config: effective, shop: shop, verbund: verbund, linker: linker,
                                      estimator: FareEstimator(catalog: catalog, relations: relationsProvider()), stations: index,
                                      cacheURL: dir.appending(path: "prices.json", directoryHint: .notDirectory))
        let built = Stack(transport: transport, throttle: throttle, health: healthActor, hafas: hafas, shop: shop, verbund: verbund,
                          linker: linker, prices: prices)
        stackStorage = built
        return built
    }
}
