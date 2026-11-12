import Foundation
import KlimaCore

/// Loads the tariff catalog (ticket prices, fare model, city fares) and keeps it up to date automatically.
/// Order: cached remote catalog (if newer) → bundled `tariffs.json` → built-in fallback.
@MainActor
final class TariffService {
    private let config: AppConfig
    private let defaults: UserDefaults
    private let cacheURL: URL

    init(config: AppConfig = .shared, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        let support = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cacheURL = support.appending(path: "tariffs-remote.json")
    }

    var lastRefresh: Date? { defaults.object(forKey: "tariffs.lastRefresh") as? Date }

    /// A cached remote catalog wins only when it is newer and usable (`TariffCatalog.isUsable`) – a malformed download
    /// that is already on disk is ignored instead of breaking every price estimate.
    func currentCatalog() -> TariffCatalog {
        let bundled = bundledCatalog()
        if let data = try? Data(contentsOf: cacheURL), let remote = try? TariffCatalog.decode(from: data),
           remote.version > (bundled?.version ?? 0), remote.isUsable {
            return remote
        }
        return bundled ?? TariffService.fallbackCatalog
    }

    /// The bundled tariffs.json (decoded once; it never changes while the app runs).
    func bundledCatalog() -> TariffCatalog? {
        if let cached = bundledCache { return cached }
        guard let url = Bundle.main.url(forResource: "tariffs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? TariffCatalog.decode(from: data) else { return nil }
        bundledCache = catalog
        return catalog
    }

    private var bundledCache: TariffCatalog?

    // MARK: tarifstand
    /// What a refresh found. `offline` = no connection, `failed` = the server answered with something that is not a usable
    /// catalogue (an HTTP error, a file that does not decode).
    enum RefreshOutcome: Equatable {
        case installed, upToDate, throttled, offline, failed, notConfigured
    }

    /// Where the tariffs document comes from: the update manifest's hint, else the build configuration.
    func tariffsURL(manifestHint: UpdateManifest?) -> URL? {
        manifestHint?.tariffsURL.flatMap(URL.init(string:)) ?? config.remoteTariffs
    }

    /// Downloads a newer catalog at most every 12 h. Returns true when a newer catalog was installed.
    @discardableResult
    func refreshIfNeeded(manifestHint: UpdateManifest?, force: Bool = false) async -> Bool {
        await refresh(manifestHint: manifestHint, force: force) == .installed
    }

    /// Like `refreshIfNeeded`, but says what happened (Einstellungen › „Jetzt prüfen“). `lastRefresh` moves only when the
    /// server delivered a usable catalogue, whether it was newer or not.
    func refresh(manifestHint: UpdateManifest?, force: Bool = false) async -> RefreshOutcome {
        guard let url = tariffsURL(manifestHint: manifestHint) else { return .notConfigured }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 12 * 3600 { return .throttled }
        if let hinted = manifestHint?.tariffsVersion, hinted <= currentCatalog().version, !force { return .upToDate }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed }
            let remote = try TariffCatalog.decode(from: data)
            defaults.set(Date(), forKey: "tariffs.lastRefresh")
            guard remote.isUsable, remote.version > currentCatalog().version else { return .upToDate }
            try data.write(to: cacheURL, options: .atomic)
            return .installed
        } catch is URLError {
            return .offline
        } catch {
            return .failed
        }
    }

    static let fallbackCatalog = TariffCatalog(
        version: 0,
        updatedAt: "2026-01-01",
        products: [
            TicketProduct(id: "oe-klassik", family: .oe, name: "KlimaTicket Ö Klassik", variant: .klassik, priceEUR: 1_400, validFrom: "2026-01-01"),
        ],
        fareModel: .fallback,
        cityFares: [],
        kilometergeldEUR: 0.50,
        carFullCostPerKmEUR: 0.47,
        emissions: .fallback
    )
}
