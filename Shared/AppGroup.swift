import Foundation

/// Resolves the App Group identifier at runtime.
/// AltStore/SideStore rewrite app group IDs per Apple ID and expose the real ones via the `ALTAppGroups` Info.plist key.
enum AppGroup {
    static let defaultIdentifier = "group.com.knitelarlberg.klimabilanz"

    static var identifier: String {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let match = groups.first(where: { $0.hasPrefix(defaultIdentifier) }) ?? groups.first {
            return match
        }
        return Bundle.main.object(forInfoDictionaryKey: "KBAppGroup") as? String ?? defaultIdentifier
    }

    /// Shared container URL, nil when the entitlement is missing (e.g. unsigned simulator builds).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Shared defaults; falls back to standard defaults when the group is unavailable.
    static var defaults: UserDefaults {
        guard containerURL != nil, let d = UserDefaults(suiteName: identifier) else { return .standard }
        return d
    }
}
