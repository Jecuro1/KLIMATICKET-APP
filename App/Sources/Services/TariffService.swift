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

    func currentCatalog() -> TariffCatalog {
        let bundled = bundledCatalog()
        if let data = try? Data(contentsOf: cacheURL), let remote = try? TariffCatalog.decode(from: data),
           remote.version > (bundled?.version ?? 0) {
            return remote
        }
        return bundled ?? TariffService.fallbackCatalog
    }

    func bundledCatalog() -> TariffCatalog? {
        guard let url = Bundle.main.url(forResource: "tariffs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? TariffCatalog.decode(from: data)
    }

    /// Downloads a newer catalog at most every 12 h. Returns true when a newer catalog was installed.
    @discardableResult
    func refreshIfNeeded(manifestHint: UpdateManifest?, force: Bool = false) async -> Bool {
        let url = manifestHint?.tariffsURL.flatMap(URL.init(string:)) ?? config.remoteTariffs
        guard let url else { return false }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 12 * 3600 { return false }
        if let hinted = manifestHint?.tariffsVersion, hinted <= currentCatalog().version, !force { return false }
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let remote = try TariffCatalog.decode(from: data)
            defaults.set(Date(), forKey: "tariffs.lastRefresh")
            guard remote.version > currentCatalog().version else { return false }
            try data.write(to: cacheURL, options: .atomic)
            return true
        } catch {
            return false
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
        carFullCostPerKmEUR: 0.60,
        emissions: .fallback
    )
}
