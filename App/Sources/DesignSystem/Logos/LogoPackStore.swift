import CryptoKit
import KlimaCore
import Observation
import SwiftUI
import UIKit

// MARK: stops – LOGO_SPEC §3.3: remote config → download on first need → verified cache → resolver.
// The pack comes from the owner's Cloudflare (R2); without it (no config block, offline, switch off, revoked) every
// view shows the own Wegzeichen in the same size. Contains no logo data. Ski-area and region logos are never part of
// the repository or the app bundle; only the public-domain Landeswappen are (Assets.xcassets/Wappen).

@MainActor
@Observable
final class LogoPackStore {
    static let shared = LogoPackStore()

    enum Phase: Equatable { case idle, downloading, ready(Int), failed(String), disabled }

    private(set) var config: LogoConfig
    private(set) var manifest: LogoPackManifest?
    private(set) var resolver: BrandResolver?
    private(set) var phase: Phase = .idle
    /// Bumps whenever images may have changed (new pack, revoked files): views fade the logo in on change.
    private(set) var generation = 0

    /// Einstellungen › Darstellung › „Offizielle Logos & Wappen“ (default on). Off = own Wegzeichen, no download.
    var userEnabled: Bool {
        didSet {
            UserDefaults.standard.set(userEnabled, forKey: Keys.userEnabled)
            generation += 1
        }
    }

    /// Logos may be shown at all: remote switch and user switch on.
    var isActive: Bool { config.enabled && userEnabled }

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private let root: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var demoPackDirectory: URL?

    private enum Keys {
        static let userEnabled = "logos.userEnabled"
        static let config = "logos.config"
        static let failedVersion = "logos.failedVersion"
        static let failedAt = "logos.failedAt"
    }

    /// At most one new try per 12 hours after a failed download (LOGO_SPEC §3.3).
    nonisolated private static let retryInterval: TimeInterval = 12 * 3600

    /// Cellular allowed (1–3 MB), but not in Low Data Mode – there the own badges stay.
    nonisolated private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.allowsConstrainedNetworkAccess = false
        c.allowsExpensiveNetworkAccess = true
        c.urlCache = nil
        c.timeoutIntervalForRequest = 60
        return URLSession(configuration: c)
    }()

    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LogoPack", isDirectory: true)
        self.userEnabled = defaults.object(forKey: Keys.userEnabled) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.config), let stored = try? JSONDecoder().decode(LogoConfig.self, from: data) {
            config = stored
        } else {
            config = .default
        }
        cache.countLimit = 120
        loadInstalled()
    }

    // MARK: Config

    /// The `logos` block of GET /v1/config (`CloudConfig.logos`); nil or invalid = `LogoConfig.default` semantics:
    /// the installed pack keeps working, nothing new is fetched.
    func apply(configBlock data: Data?) {
        let new = data.flatMap { try? JSONDecoder().decode(LogoConfig.self, from: $0) } ?? .default
        apply(config: new, persist: data != nil)
    }

    func apply(config new: LogoConfig, persist: Bool = true) {
        let old = config
        config = new
        if persist, let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Keys.config) }
        if let m = manifest {
            if Set(new.revoked) != Set(old.revoked) {
                resolver = BrandResolver(manifest: m, revoked: Set(new.revoked))
                if let dir = packDirectory(m) {
                    LogoPackInstaller.removeFiles(of: Set(new.revoked), manifest: m, packDirectory: dir)
                }
            }
        }
        cache.removeAllObjects()
        generation += 1
        if !new.enabled { phase = .disabled } else if phase == .disabled { phase = manifest.map { .ready($0.packVersion) } ?? .idle }
    }

    // MARK: Download

    /// „Erster Bedarf“: views call this when they would show a brand. Cheap no-op when up to date, switched off, or
    /// when the last try failed less than 12 hours ago.
    func ensurePack() {
        guard isActive, let pack = config.pack, pack.schema == LogoPackManifest.supportedSchema,
              let url = URL(string: pack.url), url.scheme == "https" else { return }
        if manifest?.packVersion == pack.version || downloadTask != nil { return }
        if defaults.integer(forKey: Keys.failedVersion) == pack.version,
           let at = defaults.object(forKey: Keys.failedAt) as? Date, Date().timeIntervalSince(at) < Self.retryInterval { return }
        phase = .downloading
        let dir = root
        downloadTask = Task { [weak self] in
            do {
                let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                let (data, resp) = try await Self.session.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LogoPackError.corrupt("HTTP") }
                let manifest = try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let m = try LogoPackInstaller(hasher: Self.sha256Hex).install(zip: data, expected: pack, into: dir)
                    var folder = dir
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true                // re-downloadable, keep it out of backups
                    try? folder.setResourceValues(values)
                    return m
                }.value
                self?.activate(manifest)
                LogoPackInstaller.removeVersions(in: dir, except: manifest.packVersion)
                self?.defaults.removeObject(forKey: Keys.failedVersion)
            } catch {
                self?.phase = .failed(String(describing: error))      // own badges stay; retry at the next config refresh
                self?.defaults.set(pack.version, forKey: Keys.failedVersion)
                self?.defaults.set(Date(), forKey: Keys.failedAt)
            }
            self?.downloadTask = nil
        }
    }

    nonisolated static let sha256Hex: @Sendable (Data) -> String = { data in
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Lookup

    /// The brands of a stop from the pack, or nil (off, no pack yet – which also starts the download).
    func brands(for query: AreaBrandQuery) -> StopBrands? {
        guard isActive else { return nil }
        guard let resolver else { ensurePack(); return nil }
        return resolver.resolve(StopBrandInput(query))
    }

    func brand(id: String) -> LogoPackManifest.Brand? { isActive ? resolver?.brand(id) : nil }

    /// The pack as the provider of `PlaceMarkSelection` (nil without pack or when off).
    var areaBrandProvider: (any AreaBrandProviding)? { isActive ? resolver : nil }

    /// Decoded logo for the colour scheme (the official dark variant if the pack has one).
    func image(_ brand: LogoPackManifest.Brand, large: Bool, dark: Bool) -> UIImage? {
        guard isActive, let m = manifest, resolver?.brand(brand.id) != nil else { return nil }
        let rec: LogoPackManifest.Image = switch (large, dark) {
        case (false, true): brand.img.sd ?? brand.img.s
        case (true, true): brand.img.ld ?? brand.img.l
        case (false, false): brand.img.s
        case (true, false): brand.img.l
        }
        return decode(rec.f, in: m)
    }

    /// Where the Wappen of a state comes from: the bundle, the pack (NÖ after approval) or nowhere (own Landesmarke).
    enum Wappen { case asset(String), pack(UIImage) }

    func wappen(_ state: Bundesland, size: Landeswappen.Size) -> Wappen? {
        guard userEnabled else { return nil }
        if let name = Landeswappen.assetName(state: state.rawValue, size: size, config: config) { return .asset(name) }
        if let path = Landeswappen.packImagePath(state: state.rawValue, size: size, config: config, manifest: manifest),
           let m = manifest, let img = decode(path, in: m) { return .pack(img) }
        return nil
    }

    // MARK: Private

    private func packDirectory(_ m: LogoPackManifest) -> URL? {
        if let demoPackDirectory { return demoPackDirectory }
        return root.appendingPathComponent(String(m.packVersion), isDirectory: true)
    }

    private func decode(_ path: String, in m: LogoPackManifest) -> UIImage? {
        let key = "\(m.packVersion)/\(path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard StoredZip.isSafe(path), let dir = packDirectory(m),
              let data = try? Data(contentsOf: dir.appendingPathComponent(path)),
              let img = UIImage(data: data, scale: CGFloat(m.scale)) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    private func loadInstalled() {
        guard let installed = LogoPackInstaller.installed(in: root) else { return }
        activate(installed.manifest)
    }

    func activate(_ m: LogoPackManifest, directory: URL? = nil) {
        demoPackDirectory = directory
        manifest = m
        resolver = BrandResolver(manifest: m, revoked: Set(config.revoked))
        cache.removeAllObjects()
        generation += 1
        phase = config.enabled ? .ready(m.packVersion) : .disabled
    }
}

// MARK: - Texts

enum BrandText {
    /// „Skigebiet“, „Region“, „Tourismusverband“ (VoiceOver, Gebietsleiste caption).
    static func kind(_ b: LogoPackManifest.Brand) -> String {
        switch b.level {
        case .ski: "Skigebiet"
        case .region: "Region"
        case .ort: "Tourismusverband"
        case .lift: "Bergbahnen"
        case .land: "Tourismus"
        }
    }

    static func spoken(_ b: LogoPackManifest.Brand) -> String { "\(kind(b)) \(b.name)" }

    /// „Logo © Ski Arlberg“ + owners for the footer.
    static func owners(_ brands: [LogoPackManifest.Brand]) -> [String] {
        var seen = Set<String>()
        return brands.map { $0.owner.isEmpty ? $0.name : $0.owner }.filter { seen.insert($0).inserted }
    }
}
