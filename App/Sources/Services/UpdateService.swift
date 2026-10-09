import Foundation
import SwiftUI
import UIKit
import KlimaCore

/// Checks the published `update.json` manifest and offers in-app updates.
/// Installation paths (in order of convenience):
///   1. AltStore / SideStore source → the store updates the app automatically in the background.
///   2. TestFlight (signed builds) → TestFlight auto-updates.
///   3. Direct .ipa download.
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

    private(set) var state: State
    private(set) var manifest: UpdateManifest?
    /// Drives the "Update verfügbar" sheet.
    var isPresentingSheet = false

    private let config: AppConfig
    private let defaults: UserDefaults

    init(config: AppConfig = .shared, defaults: UserDefaults = .standard) {
        self.config = config
        self.defaults = defaults
        self.state = config.updateManifest == nil ? .notConfigured : .idle
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

    /// Checks at most every 6 hours unless forced. Presents the sheet once per new version.
    func checkIfDue(force: Bool) async {
        guard let url = config.updateManifest else { state = .notConfigured; return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        state = .checking
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            self.manifest = manifest
            defaults.set(Date(), forKey: "updates.lastCheck")
            switch UpdateDecision.evaluate(installed: installedVersion, installedBuild: installedBuild, manifest: manifest) {
            case .upToDate:
                state = .upToDate(checkedAt: Date())
            case .available(let m):
                state = .available(m)
                let key = "updates.dismissed.\(m.version).\(m.build)"
                if force || !defaults.bool(forKey: key) { isPresentingSheet = true }
            case .required(let m):
                state = .required(m)
                isPresentingSheet = true
            }
        } catch {
            state = .failed("Update-Prüfung fehlgeschlagen")
        }
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

    func dismissCurrent() {
        if let m = availableManifest { defaults.set(true, forKey: "updates.dismissed.\(m.version).\(m.build)") }
        isPresentingSheet = false
    }

    // MARK: Install actions

    var altStoreSourceURL: URL? {
        guard let source = availableManifest?.altstoreSourceURL ?? manifest?.altstoreSourceURL,
              let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "altstore://source?url=\(encoded)")
    }

    var sideStoreSourceURL: URL? {
        guard let source = availableManifest?.altstoreSourceURL ?? manifest?.altstoreSourceURL,
              let encoded = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "sidestore://source?url=\(encoded)")
    }

    var altStoreInstallURL: URL? {
        guard let ipa = availableManifest?.downloadURL,
              let encoded = ipa.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "altstore://install?url=\(encoded)")
    }

    var directDownloadURL: URL? { availableManifest.flatMap { URL(string: $0.downloadURL) } }

    var otaInstallURL: URL? {
        guard let manifestURL = availableManifest?.otaManifestURL,
              let encoded = manifestURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")
    }

    var isTestFlightBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Opens the best available installation route.
    func install() {
        let candidates: [URL?] = isTestFlightBuild
            ? [URL(string: "itms-beta://"), directDownloadURL]
            : [otaInstallURL, altStoreInstallURL, sideStoreSourceURL, directDownloadURL]
        for case let url? in candidates where UIApplication.shared.canOpenURL(url) || url.scheme == "https" {
            UIApplication.shared.open(url)
            return
        }
        if let url = directDownloadURL { UIApplication.shared.open(url) }
    }
}
