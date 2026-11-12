import CryptoKit
import Foundation
import KlimaCore

// MARK: tarifstand – the relation-price table can be updated from the owner's repository host, like the tariffs
// (docs/TARIFF_FRESHNESS.md). The decisions (when to fetch, what to accept, atomic install) are KlimaCore's
// `RelationPackUpdater` / `RelationPackValidator` and run in Linux tests; this file adds only what the device does:
// SHA-256 (CryptoKit), the download (URLSession), the cache directory and the 24-hour clock.

/// The relation-price table in use: the bundled one, or – when a newer, validated pack is installed and valid from today –
/// the pack. Read from any thread; a pack installed while the app runs takes effect with the next estimate.
final class RelationsHolder: @unchecked Sendable {
    private let lock = NSLock()
    private let bundled: Preloaded<RelationPriceTable>
    private let loadInstalled: @Sendable (RelationPriceTable) -> RelationPriceTable?
    private var pack: RelationPriceTable?
    private var didLoad = false

    /// `loadInstalled` reads and re-validates the cached pack (nil = none, or not usable) against the bundled table; it runs
    /// once, off the main thread when `preload()` started it.
    init(bundled: Preloaded<RelationPriceTable>, loadInstalled: @escaping @Sendable (RelationPriceTable) -> RelationPriceTable?) {
        self.bundled = bundled
        self.loadInstalled = loadInstalled
    }

    /// Reads the cache in the background, right after the bundled table is built.
    func preload() {
        Task.detached(priority: .utility) { _ = self.installedPack() }
    }

    var bundledTable: RelationPriceTable { bundled.value }

    /// The table to estimate with today (Vienna day): the pack once it is valid, otherwise the bundled table.
    var current: RelationPriceTable {
        let base = bundled.value
        return RelationPriceTable.preferred(bundled: base, pack: installedPack(), today: TariffFreshness.isoDay(Date()))
    }

    /// The highest data version available (bundled or installed pack) – a download must beat it.
    var versionInUse: Int { max(bundled.value.version, installedPack()?.version ?? 0) }

    /// A pack that was just validated and written.
    func install(_ table: RelationPriceTable) {
        lock.lock()
        pack = table
        didLoad = true
        lock.unlock()
    }

    private func installedPack() -> RelationPriceTable? {
        let base = bundled.value   // outside the lock: it may wait for the build
        lock.lock()
        defer { lock.unlock() }
        if !didLoad {
            pack = loadInstalled(base)
            didLoad = true
        }
        return pack
    }
}

/// Downloads, validates and installs the remote relation pack (Application Support: `relations-pack.bin` and
/// `relations-pack-meta.json`). Any failure leaves the table in use as it is.
final class RelationPackService: Sendable {
    private let updater: RelationPackUpdater
    private let defaults: UserDefaults

    private static let lastAttemptKey = "relationPack.lastAttempt"

    init(directory: URL = URL.applicationSupportDirectory, defaults: UserDefaults = .standard) {
        self.updater = RelationPackUpdater(store: RelationPackStore(directory: directory),
                                           validator: RelationPackValidator(hasher: Self.sha256Hex))
        self.defaults = defaults
    }

    nonisolated static let sha256Hex: @Sendable (Data) -> String = { data in
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The installed pack as a table, checked again like a fresh download; nil without one. A cache that fails the check, or
    /// that the bundled table has caught up with, is deleted.
    func loadInstalledTable(reference bundled: RelationPriceTable) -> RelationPriceTable? {
        updater.store.loadValidated(validator: updater.validator, reference: .init(table: bundled),
                                    bundledVersion: bundled.version)?.table()
    }

    /// When the pack was last downloaded or tried (nil = never): at most one attempt per 24 hours.
    var lastAttempt: Date? { defaults.object(forKey: Self.lastAttemptKey) as? Date }

    /// One refresh. `force` ("Jetzt prüfen") ignores the 24-hour limit, never the version rule. Returns what happened and,
    /// for an installed pack, the new table.
    func refresh(catalog: TariffCatalog, tariffsURL: URL?, bundled: RelationPriceTable, versionInUse: Int,
                 force: Bool) async -> (outcome: RelationPackUpdater.Outcome, table: RelationPriceTable?) {
        let now = Date()
        let result = await updater.refresh(info: catalog.relationsPack, tariffsURL: tariffsURL, versionInUse: versionInUse,
                                           reference: .init(table: bundled), lastAttempt: lastAttempt, now: now, force: force,
                                           fetch: Self.download)
        if result.attempted { defaults.set(now, forKey: Self.lastAttemptKey) }
        guard case .installed = result.outcome else { return (result.outcome, nil) }
        return (result.outcome, loadInstalledTable(reference: bundled))
    }

    // MARK: Download

    /// No cache, no cookies; Low Data Mode is respected by the system. Aborts as soon as more than `maxBytes` arrive.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    nonisolated static let download: RelationPackUpdater.Fetch = { url, maxBytes in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        if response.expectedContentLength > Int64(maxBytes) { throw RelationPackError.tooLarge }
        var data = Data()
        data.reserveCapacity(max(0, min(Int(response.expectedContentLength), maxBytes)))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw RelationPackError.tooLarge }
        }
        return data
    }
}
