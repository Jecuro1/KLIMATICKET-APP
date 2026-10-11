import Foundation
import KlimaCore

/// The live configuration with its remote kill switch (docs/OEBB_LIVE.md §A3.8, §E2).
///
/// Order: cache in Application Support (`live-config.json`) → bundled default (`LiveConfig.default`) → remote JSON,
/// at most every 12 hours. A downloaded config only replaces the current one when its `version` is higher; it is
/// validated and clamped by `LiveConfigLoader` (a remote file can switch providers off and slow requests down, never
/// loosen the volume budget). The remote file is only fetched while live data is switched on.
struct LiveConfigStore {
    static let refreshInterval: TimeInterval = 12 * 3600
    private static let checkedKey = "live.config.checkedAt"

    let fileURL: URL
    let defaults: UserDefaults

    init(fileURL: URL = LiveConfigStore.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "live-config.json", directoryHint: .notDirectory)
    }

    /// Cached config when it is valid and newer than the bundled default, else the default.
    func load() -> LiveConfig {
        let fallback = LiveConfig.default
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(LiveConfig.self, from: data),
              let clean = LiveConfigLoader.sanitized(cached), clean.version >= fallback.version else { return fallback }
        return clean
    }

    func isDue(now: Date = Date()) -> Bool {
        guard let last = defaults.object(forKey: Self.checkedKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= Self.refreshInterval
    }

    /// Downloads the remote config (GET, honest user agent, 12 s). Returns the new config when it is valid and newer.
    func fetch(from url: URL, current: LiveConfig, userAgent: String, now: Date = Date()) async -> LiveConfig? {
        guard url.scheme == "https" else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        defaults.set(now, forKey: Self.checkedKey)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 64_000,
              let next = LiveConfigLoader.decode(data, current: current) else { return nil }
        persist(next)
        return next
    }

    func persist(_ config: LiveConfig) {
        guard let data = try? LiveConfigLoader.encode(config) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func resetCheckDate() { defaults.removeObject(forKey: Self.checkedKey) }
}
