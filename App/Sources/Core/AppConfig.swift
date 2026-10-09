import Foundation

/// Build-time configuration from `AppConfig.json` (written by CI from repository variables).
struct AppConfig: Decodable, Sendable {
    var supabaseURL: String = ""
    var supabaseAnonKey: String = ""
    var updateManifestURL: String = ""
    var tariffsURL: String = ""

    static let shared: AppConfig = {
        guard let url = Bundle.main.url(forResource: "AppConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }()

    var supabase: URL? {
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else { return nil }
        return URL(string: supabaseURL)
    }

    var isCloudConfigured: Bool { supabase != nil }
    var updateManifest: URL? { updateManifestURL.isEmpty ? nil : URL(string: updateManifestURL) }
    var remoteTariffs: URL? { tariffsURL.isEmpty ? nil : URL(string: tariffsURL) }

    static let urlScheme = "klimabilanz"
    static let authCallback = "klimabilanz://auth-callback"

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    static var buildNumber: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1 }
}

/// Launch-argument driven modes used by CI to capture screenshots with demo data.
enum LaunchMode {
    static var screenshotScreen: String? { UserDefaults.standard.string(forKey: "KBScreenshot") }
    static var isScreenshot: Bool { screenshotScreen != nil }
    static var useDemoData: Bool { UserDefaults.standard.bool(forKey: "KBDemo") }
}
