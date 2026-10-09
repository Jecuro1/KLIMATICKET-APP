import Foundation
import SwiftUI
import UIKit
import StoreKit
import KlimaCore

/// Checks for new versions and opens the right place to install them – depending on how this copy was installed:
///   • App Store  → iTunes lookup (`itunes.apple.com/lookup?bundleId=…&country=at`), update in the App Store.
///   • TestFlight → published `update.json`, update in the TestFlight app (`itms-beta://`).
///   • Sideloaded → published `update.json`; AltStore (`altstore://install?url=…`) or SideStore
///                  (`sidestore://install?url=…`) installs it. Neither store installs silently: once the source is added
///                  they detect new versions, show a badge/notification and the user taps „Aktualisieren“.
///                  Which store installed this copy is read from the URL scheme / UTI the store adds to our Info.plist.
///   • Ad hoc     → our own signed build on a registered iPhone (docs/DIREKT_INSTALLIEREN.md): „Jetzt installieren“
///                  opens `itms-services://` with the release's `otaManifestURL`, iOS asks once and replaces the app in
///                  place – no computer, no store, data stays.
/// App Store vs. TestFlight is read from `AppTransaction` (environment `.sandbox` = TestFlight); sideloaded builds are
/// recognised by their `embedded.mobileprovision`, which App Store and TestFlight builds never contain.
@Observable
@MainActor
final class UpdateService {
    enum State: Equatable {
        case notConfigured
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(UpdateManifest)
        case required(UpdateManifest)
        case failed(String)
    }

    /// How this copy of KlimaBilanz was installed.
    enum Channel: String, Sendable {
        case appStore
        case testFlight
        /// AltStore, SideStore, Sideloadly or a development/ad-hoc profile.
        case sideloaded
        /// Simulator / Xcode StoreKit testing – behaves like `sideloaded` (manifest, sample sheet).
        case development
    }

    /// The sideloading store that manages this copy.
    enum SideloadStore: String, Sendable {
        case altStore
        case sideStore
        /// Sideloadly, Xcode, ad hoc … – direct .ipa download only.
        case other
    }

    static let baseBundleIdentifier = "com.knitelarlberg.klimabilanz"

    private(set) var state: State
    private(set) var manifest: UpdateManifest?
    /// Drives the "Update verfügbar" sheet.
    var isPresentingSheet = false
    /// Best-known install channel. App Store vs. TestFlight is refined asynchronously on the first check.
    private(set) var channel: Channel
    /// App Store product page of the newest version (App Store channel only).
    private(set) var appStoreURL: URL? = nil

    @ObservationIgnored private var isChannelResolved: Bool
    @ObservationIgnored private var cachedSideloadStore: SideloadStore?

    private let config: AppConfig
    private let defaults: UserDefaults

    init(config: AppConfig = .shared, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        let channel = Self.provisionalChannel
        self.channel = channel
        // Without a provisioning profile it's App Store or TestFlight – AppTransaction (async) tells which.
        self.isChannelResolved = channel != .appStore
        self.state = (channel != .appStore && config.updateManifest == nil) ? .notConfigured : .idle
    }

    var installedVersion: SemanticVersion { SemanticVersion(AppConfig.appVersion) ?? SemanticVersion(major: 1) }
    var installedBuild: Int { AppConfig.buildNumber }
    var lastCheck: Date? { defaults.object(forKey: "updates.lastCheck") as? Date }

    var availableManifest: UpdateManifest? {
        switch state {
        case .available(let m), .required(let m): m
        default: nil
        }
    }

    var isRequired: Bool { if case .required = state { true } else { false } }

    var isTestFlightBuild: Bool { channel == .testFlight }
    var isAppStoreBuild: Bool { channel == .appStore }
    /// AltStore/SideStore sources and .ipa links only make sense for sideloaded copies (never shown in App Store/TestFlight builds).
    var showsSideloadOptions: Bool { channel == .sideloaded || channel == .development }

    // MARK: Channel detection

    /// Synchronous first guess: simulator → development, profile → sideloaded, otherwise App Store (or TestFlight).
    static var provisionalChannel: Channel {
        #if targetEnvironment(simulator)
        return .development
        #else
        return ProvisioningProfile.isPresent ? .sideloaded : .appStore
        #endif
    }

    /// Resolves App Store vs. TestFlight once via `AppTransaction` (TestFlight runs in the sandbox environment).
    /// Offline or without an App Store account the App Store guess stays and is retried on the next check.
    @discardableResult
    func resolveChannel() async -> Channel {
        guard !isChannelResolved else { return channel }
        do {
            let result = try await AppTransaction.shared
            guard let transaction = Self.transaction(in: result) else { return channel }
            if transaction.environment == .sandbox {
                channel = .testFlight
            } else if transaction.environment == .production {
                channel = .appStore
            } else {
                channel = .development
            }
            isChannelResolved = true
            cachedSideloadStore = nil
            if channel != .appStore, config.updateManifest == nil, state == .idle { state = .notConfigured }
        } catch {
            // Keep the provisional channel.
        }
        return channel
    }

    /// The environment is the same for verified and unverified transactions – good enough to tell TestFlight apart.
    private static func transaction(in result: VerificationResult<AppTransaction>) -> AppTransaction? {
        if case .verified(let transaction) = result { return transaction }
        if case .unverified(let transaction, _) = result { return transaction }
        return nil
    }

    /// Which sideloading store installed this copy (cached).
    var sideloadStore: SideloadStore {
        if let cachedSideloadStore { return cachedSideloadStore }
        let store = showsSideloadOptions
            ? Self.detectSideloadStore(info: Bundle.main.infoDictionary ?? [:], canOpen: { self.canOpen($0) })
            : .other
        cachedSideloadStore = store
        return store
    }

    /// Both stores mark every app they install in its Info.plist: an open-app URL scheme `altstore-<bundle id>` /
    /// `sidestore-<bundle id>` (CFBundleURLTypes) and an exported UTI `io.altstore.Installed.<id>` /
    /// `io.sidestore.Installed.<id>`. Only AltStore also writes `ALTBundleIdentifier` / `ALTAppGroups` – current SideStore
    /// writes neither, so those keys alone must not decide. Falls back to which store app is installed.
    static func detectSideloadStore(info: [String: Any], canOpen: (String) -> Bool) -> SideloadStore {
        let schemes = (info["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .map { $0.lowercased() }
        let utis = (info["UTExportedTypeDeclarations"] as? [[String: Any]] ?? [])
            .compactMap { $0["UTTypeIdentifier"] as? String }
            .map { $0.lowercased() }
        let byAltStore = schemes.contains { $0.hasPrefix("altstore-") } || utis.contains { $0.hasPrefix("io.altstore.installed.") }
        let bySideStore = schemes.contains { $0.hasPrefix("sidestore-") } || utis.contains { $0.hasPrefix("io.sidestore.installed.") }
        if bySideStore && !byAltStore { return .sideStore }
        if byAltStore && !bySideStore { return .altStore }
        let hasAltKeys = info["ALTAppGroups"] != nil || info["ALTBundleIdentifier"] != nil
        if !byAltStore && !bySideStore && !hasAltKeys { return .other }
        // Marked by both (re-signed by the other store) or only ALT* keys (older store versions): ask the system.
        switch (canOpen("sidestore://"), canOpen("altstore://")) {
        case (true, false): return .sideStore
        case (false, true): return .altStore
        case (true, true): return hasAltKeys ? .altStore : .sideStore
        case (false, false): return .other
        }
    }

    /// The bundle id the sideloading store knows the app by: AltStore/SideStore rewrite it to `<id>.<TEAMID>` and keep the
    /// original in `ALTBundleIdentifier`.
    var storeBundleIdentifier: String {
        if let original = Bundle.main.object(forInfoDictionaryKey: "ALTBundleIdentifier") as? String, !original.isEmpty {
            return original
        }
        let current = Bundle.main.bundleIdentifier ?? Self.baseBundleIdentifier
        return current.hasPrefix(Self.baseBundleIdentifier + ".") ? Self.baseBundleIdentifier : current
    }

    // MARK: Checking

    /// Checks at most every 6 hours unless forced. Presents the sheet once per new version.
    func checkIfDue(force: Bool) async {
        let channel = await resolveChannel()
        if channel == .appStore {
            await checkAppStore(force: force)
            return
        }
        guard let url = config.updateManifest else { state = .notConfigured; return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        state = .checking
        do {
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: try await fetch(url))
            self.manifest = manifest
            defaults.set(Date(), forKey: "updates.lastCheck")
            apply(UpdateDecision.evaluate(installed: installedVersion, installedBuild: installedBuild, manifest: manifest), force: force)
        } catch {
            state = .failed("Update-Prüfung fehlgeschlagen")
        }
    }

    /// App Store builds: the App Store version is the truth (it may lag behind the GitHub release while in review).
    /// `update.json`, when configured, only contributes tariff hints and the minimum supported version.
    private func checkAppStore(force: Bool) async {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "bundleId", value: Bundle.main.bundleIdentifier ?? Self.baseBundleIdentifier),
                                  URLQueryItem(name: "country", value: "at")]
        guard let lookupURL = components?.url else { return }
        state = .checking
        var hint: UpdateManifest?
        if let url = config.updateManifest, let data = try? await fetch(url) {
            hint = try? JSONDecoder().decode(UpdateManifest.self, from: data)
            hint?.altstoreSourceURL = nil
            hint?.otaManifestURL = nil
        }
        do {
            let lookup = try JSONDecoder().decode(AppStoreLookup.self, from: try await fetch(lookupURL))
            defaults.set(Date(), forKey: "updates.lastCheck")
            guard let result = lookup.results.first, let version = SemanticVersion(result.version) else {
                // Not (yet) on the App Store in Austria.
                manifest = hint
                state = .upToDate(checkedAt: Date())
                return
            }
            let pageURL = result.trackViewUrl.flatMap { URL(string: $0) }
                ?? result.trackId.flatMap { URL(string: "https://apps.apple.com/at/app/id\($0)") }
            appStoreURL = pageURL
            var notes = Self.lines(of: result.releaseNotes)
            if notes.isEmpty, let hint, hint.version == version { notes = hint.releaseNotes }
            // Only force the update when the App Store already offers a version that satisfies the minimum.
            let minimum = hint?.minimumSupportedVersion.flatMap { version >= $0 ? $0 : nil }
            let storeManifest = UpdateManifest(
                version: version,
                build: hint.flatMap { $0.version == version ? $0.build : nil } ?? 0,
                publishedAt: result.currentVersionReleaseDate ?? ISO8601DateFormatter().string(from: Date()),
                minimumOSVersion: result.minimumOsVersion,
                downloadURL: pageURL?.absoluteString ?? "",
                releaseNotes: notes,
                minimumSupportedVersion: minimum,
                tariffsVersion: hint?.tariffsVersion,
                tariffsURL: hint?.tariffsURL
            )
            manifest = storeManifest
            // The App Store has no build numbers for us: compare marketing versions only.
            apply(UpdateDecision.evaluate(installed: installedVersion, installedBuild: Int.max, manifest: storeManifest), force: force)
        } catch {
            manifest = hint ?? manifest
            state = .failed("Update-Prüfung fehlgeschlagen")
        }
    }

    private func apply(_ decision: UpdateDecision, force: Bool) {
        switch decision {
        case .upToDate:
            state = .upToDate(checkedAt: Date())
        case .available(let m):
            state = .available(m)
            if force || !defaults.bool(forKey: Self.dismissedKey(m)) { isPresentingSheet = true }
        case .required(let m):
            state = .required(m)
            isPresentingSheet = true
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// App Store release notes are one text block – split into the sheet's bullet lines.
    private static func lines(of text: String?) -> [String] {
        guard let text else { return [] }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "•-–*· ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private struct AppStoreLookup: Decodable {
        struct Result: Decodable {
            var version: String
            var trackId: Int?
            var trackViewUrl: String?
            var releaseNotes: String?
            var currentVersionReleaseDate: String?
            var minimumOsVersion: String?
        }

        var results: [Result]
    }

    /// Shows the sheet with a sample manifest (screenshots / design review).
    func presentSample() {
        let sample = UpdateManifest(
            version: SemanticVersion(major: installedVersion.major, minor: installedVersion.minor + 1),
            build: installedBuild + 1,
            publishedAt: ISO8601DateFormatter().string(from: Date()),
            downloadURL: "https://example.com/KlimaBilanz.ipa",
            altstoreSourceURL: "https://example.com/altstore-source.json",
            releaseNotes: ["Neue Widgets für den Sperrbildschirm", "Schnellere Haltestellensuche", "Aktualisierte Ticketpreise 2027"]
        )
        manifest = sample
        state = .available(sample)
        isPresentingSheet = true
    }

    /// "Später" or swiping the sheet away: this release no longer presents itself on the next checks (a manual check
    /// still does, and a required update always does). Works with the sheet's pinned release while a re-check runs.
    func rememberDismissal(of manifest: UpdateManifest) {
        defaults.set(true, forKey: Self.dismissedKey(manifest))
    }

    private static func dismissedKey(_ m: UpdateManifest) -> String { "updates.dismissed.\(m.version).\(m.build)" }

    // MARK: Install actions

    /// URL query value encoding that also escapes `&`, `=`, `+`, `?` and `#` inside the nested URL.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return allowed
    }()

    private static func link(_ prefix: String, _ value: String?) -> URL? {
        guard let value, !value.isEmpty, let encoded = value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) else { return nil }
        return URL(string: prefix + encoded)
    }

    /// `altstore-source.json` – from the manifest, or next to the configured `update.json` before the first check.
    var sourceURLString: String? {
        if let source = availableManifest?.altstoreSourceURL ?? manifest?.altstoreSourceURL { return source }
        return config.updateManifest?.deletingLastPathComponent().appendingPathComponent("altstore-source.json").absoluteString
    }

    /// Adds our source to AltStore (afterwards AltStore detects new versions and shows „Aktualisieren“).
    var altStoreSourceURL: URL? {
        guard showsSideloadOptions else { return nil }
        return Self.link("altstore://source?url=", sourceURLString)
    }

    /// Adds our source to SideStore.
    var sideStoreSourceURL: URL? {
        guard showsSideloadOptions else { return nil }
        return Self.link("sidestore://source?url=", sourceURLString)
    }

    /// Opens KlimaBilanz's page in AltStore – only works once our source is added (otherwise AltStore silently ignores
    /// it), so `install()` prefers `altStoreInstallURL`. Use this for an optional „In AltStore ansehen“ button.
    var altStoreViewAppURL: URL? {
        guard showsSideloadOptions else { return nil }
        return Self.link("altstore://viewapp?bundleid=", storeBundleIdentifier)
    }

    /// Lets AltStore download and install the new .ipa directly (works without the source).
    var altStoreInstallURL: URL? {
        guard showsSideloadOptions else { return nil }
        return Self.link("altstore://install?url=", availableManifest?.downloadURL)
    }

    /// Lets SideStore download and install the new .ipa.
    var sideStoreInstallURL: URL? {
        guard showsSideloadOptions else { return nil }
        return Self.link("sidestore://install?url=", availableManifest?.downloadURL)
    }

    var directDownloadURL: URL? {
        guard showsSideloadOptions else { return nil }
        return availableManifest.flatMap { URL(string: $0.downloadURL) }
    }

    var otaInstallURL: URL? { directInstallURL(for: availableManifest) }

    // MARK: ota – Direkt installieren (ad-hoc builds, docs/DIREKT_INSTALLIEREN.md)

    /// This copy is our own ad-hoc build (registered iPhone): an itms-services install replaces it in place.
    /// AltStore/SideStore copies are development-signed under `<id>.<TEAMID>` – there the ad-hoc build would be a second app.
    static let isDirectInstallCopy: Bool = DirectInstall.replacesInPlace(
        kind: ProvisioningKind(profile: ProvisioningProfile.main),
        bundleIdentifier: Bundle.main.bundleIdentifier,
        expected: baseBundleIdentifier)

    /// The itms-services link of a release (nil without an ad-hoc build, and never for App Store / TestFlight copies).
    func directInstallURL(for manifest: UpdateManifest?) -> URL? {
        guard showsSideloadOptions else { return nil }
        return DirectInstall.link(manifestURL: manifest?.otaManifestURL)
    }

    /// „Jetzt installieren“ hands the release straight to iOS: our ad-hoc copy, or a copy no sideloading store manages
    /// (a store-managed copy would get the ad-hoc build as a second app, so AltStore/SideStore copies keep their store).
    func prefersDirectInstall(for manifest: UpdateManifest?) -> Bool {
        guard directInstallURL(for: manifest) != nil else { return false }
        return Self.isDirectInstallCopy || sideloadStore == .other
    }

    var prefersDirectInstall: Bool { prefersDirectInstall(for: availableManifest) }

    var testFlightURL: URL? { URL(string: "itms-beta://") }

    /// Install routes for this channel, best first.
    var installCandidates: [URL] {
        // MARK: ota – our own ad-hoc copy updates itself in place (otaInstallURL implies a sideloaded channel).
        if Self.isDirectInstallCopy, let ota = otaInstallURL { return [ota] + [directDownloadURL].compactMap { $0 } }
        let urls: [URL?]
        switch channel {
        case .appStore:
            urls = [appStoreURL, availableManifest.flatMap { URL(string: $0.downloadURL) }]
        case .testFlight:
            urls = [testFlightURL]
        case .sideloaded, .development:
            switch sideloadStore {
            // `install?url=` works with and without the source; `viewapp` does nothing in AltStore without it.
            // No itms-services here: AltStore/SideStore rename the bundle id, the ad-hoc build would be a second app.
            case .altStore: urls = [altStoreInstallURL, altStoreViewAppURL, directDownloadURL]
            case .sideStore: urls = [sideStoreInstallURL, directDownloadURL]
            case .other: urls = [otaInstallURL, directDownloadURL]
            }
        }
        return urls.compactMap { $0 }
    }

    /// Title for the primary update button.
    var installActionTitle: String {
        switch channel {
        case .appStore: return Copy.Updates.actionAppStore
        case .testFlight: return Copy.Updates.actionTestFlight
        case .sideloaded, .development: break
        }
        if prefersDirectInstall { return Copy.Updates.actionDirectInstall }   // MARK: ota
        switch sideloadStore {
        case .altStore: return Copy.Updates.actionAltStore
        case .sideStore: return Copy.Updates.actionSideStore
        case .other: return Copy.Updates.actionDownload
        }
    }

    /// One-line explanation of how updates arrive for this copy (footer under Einstellungen › Updates).
    var channelFooter: String {
        switch channel {
        case .appStore: return Copy.Updates.footerAppStore
        case .testFlight: return Copy.Updates.footerTestFlight
        case .sideloaded, .development:
            if Self.isDirectInstallCopy { return Copy.Updates.footerDirectInstall }   // MARK: ota
            return sideloadStore == .other ? Copy.Updates.footerDirect : Copy.Updates.footerSource
        }
    }

    /// Opens the best available installation route. Returns whether another app (store, TestFlight, Safari) took over –
    /// the update sheet shows the hand-off ("Weiter in AltStore") or says that nothing could be opened.
    @discardableResult
    func install() async -> Bool {
        let candidates = installCandidates
        guard let url = candidates.first(where: { $0.scheme == "https" || canOpen($0.absoluteString) }) ?? candidates.last else {
            return false
        }
        return await UIApplication.shared.open(url, options: [:])
    }

    /// The update button once `install()` handed over ("Weiter in AltStore").
    var installHandoffTitle: String {
        switch channel {
        case .appStore: return "Weiter im App Store"
        case .testFlight: return "Weiter in TestFlight"
        case .sideloaded, .development: break
        }
        if prefersDirectInstall { return Copy.Updates.handoffDirectInstall }   // MARK: ota
        switch sideloadStore {
        case .altStore: return "Weiter in AltStore"
        case .sideStore: return "Weiter in SideStore"
        case .other: return "Download gestartet"
        }
    }

    private func canOpen(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
