import Foundation
import KlimaCloud

/// Build-time configuration from `AppConfig.json` (written by CI, see scripts/write_app_config.py).
struct AppConfig: Decodable, Sendable {
    /// Origin of the Cloudflare Worker (`https://klimabilanz-api.<subdomain>.workers.dev` or a custom domain).
    /// Empty = no cloud: the app runs locally only.
    var apiBaseURL: String = ""
    var updateManifestURL: String = ""
    var tariffsURL: String = ""

    init(apiBaseURL: String = "", updateManifestURL: String = "", tariffsURL: String = "") {
        self.apiBaseURL = apiBaseURL
        self.updateManifestURL = updateManifestURL
        self.tariffsURL = tariffsURL
    }

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL, updateManifestURL, tariffsURL
    }

    /// Every key is optional and unknown keys (e.g. the retired `supabaseURL`) are ignored, so one missing or extra
    /// key never switches the whole configuration off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = (try? c.decodeIfPresent(String.self, forKey: .apiBaseURL)).flatMap { $0 } ?? ""
        updateManifestURL = (try? c.decodeIfPresent(String.self, forKey: .updateManifestURL)).flatMap { $0 } ?? ""
        tariffsURL = (try? c.decodeIfPresent(String.self, forKey: .tariffsURL)).flatMap { $0 } ?? ""
    }

    static let shared: AppConfig = {
        guard let url = Bundle.main.url(forResource: "AppConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }()

    /// The API origin: `https` only, no path, query or fragment (a trailing "/" is tolerated). nil = cloud off.
    var api: URL? {
        var raw = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard !raw.isEmpty, let comps = URLComponents(string: raw), comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty, comps.path.isEmpty, comps.query == nil, comps.fragment == nil,
              comps.user == nil, comps.password == nil else { return nil }
        return comps.url
    }

    var isCloudConfigured: Bool { api != nil }
    var updateManifest: URL? { updateManifestURL.isEmpty ? nil : URL(string: updateManifestURL) }
    var remoteTariffs: URL? { tariffsURL.isEmpty ? nil : URL(string: tariffsURL) }

    /// HTTP client of the cloud backend (nil without `apiBaseURL`). Auth and sync share one URLSession.
    var cloudClient: CloudAPIClient? {
        api.map { CloudAPIClient(baseURL: $0, transport: Self.cloudTransport, appVersion: Self.appVersion,
                                 build: String(Self.buildNumber), osVersion: CloudAPIClient.systemVersion) }
    }

    private static let cloudTransport = URLSessionTransport()

    static let urlScheme = "klimabilanz"
    static let authCallback = "klimabilanz://auth-callback"

    /// Native Sign in with Apple is only possible in signed builds with the capability (CI sets KB_NATIVE_APPLE_SIGNIN=YES).
    static var supportsNativeAppleSignIn: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "KBNativeAppleSignIn") as? String)?.uppercased() == "YES"
    }

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var buildNumber: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1 }
}

/// Launch-argument driven modes used by CI to capture screenshots with demo data.
enum LaunchMode {
    static var screenshotScreen: String? { UserDefaults.standard.string(forKey: "KBScreenshot") }
    static var isScreenshot: Bool { screenshotScreen != nil }
    static var useDemoData: Bool { UserDefaults.standard.bool(forKey: "KBDemo") }

    // MARK: Diagnostics
    /// `-KBPerf YES`: CI performance tests (KlimaBilanzPerfTests) – the normal tab interface with in-memory demo data
    /// (`-KBPerfTrips <n>` adds n synthetic trips), no network, no sync, no permission prompts, animations on.
    static var isPerf: Bool { UserDefaults.standard.bool(forKey: "KBPerf") }
    /// Screenshot or performance run: isolated in-memory data, no side effects.
    static var isSandboxed: Bool { isScreenshot || isPerf }
}
