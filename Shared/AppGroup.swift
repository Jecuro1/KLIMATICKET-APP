import Foundation

/// Resolves the App Group identifier at runtime – used by the app AND the widget extension.
///
/// Sideloading tools re-sign with the user's Apple ID and rename the group to `<group>.<TEAMID>`:
///   • AltStore writes the real groups into the Info.plist key `ALTAppGroups`.
///   • SideStore (and Sideloadly) do NOT – but the provisioning profile they embed in the app and in every
///     extension (`embedded.mobileprovision`) lists the real group in its entitlements.
/// App Store / TestFlight builds keep the original group (`KBAppGroup` in Info.plist).
///
/// Candidates, in order: (a) `ALTAppGroups` entry matching our base group, (b) matching group from the
/// embedded provisioning profile, (c) `KBAppGroup` / built-in default, then any other group we were given.
/// The first candidate for which `containerURL(forSecurityApplicationGroupIdentifier:)` returns a container
/// wins; the result is resolved once per process and cached. An extension also looks at its host app's bundle.
enum AppGroup {
    static let defaultIdentifier = "group.com.knitelarlberg.klimabilanz"

    /// The group this process is entitled to (best guess when none verifies, e.g. unsigned builds).
    static var identifier: String { resolved.identifier }

    /// Shared container URL, nil when the entitlement is missing (e.g. unsigned simulator builds).
    static var containerURL: URL? { resolved.containerURL }

    /// Shared defaults; falls back to standard defaults when the group is unavailable.
    static var defaults: UserDefaults { resolved.defaults ?? .standard }

    /// True when the shared container is really available (widgets and app see the same data).
    static var isAvailable: Bool { resolved.containerURL != nil }

    /// All candidates in resolution order (diagnostics, e.g. a debug row in Einstellungen).
    static var candidates: [String] { resolved.candidates }

    // MARK: Resolution

    private struct Resolution {
        var identifier: String
        var containerURL: URL?
        var defaults: UserDefaults?
        var candidates: [String]
    }

    private static let resolved: Resolution = {
        let ids = candidateIdentifiers()
        for id in ids {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                if !isExtension { adoptSandboxStore(into: url) }
                return Resolution(identifier: id, containerURL: url, defaults: UserDefaults(suiteName: id), candidates: ids)
            }
        }
        return Resolution(identifier: ids.first ?? defaultIdentifier, containerURL: nil, defaults: nil, candidates: ids)
    }()

    /// Base group from Info.plist (`KBAppGroup`), so a renamed project only needs project.yml changes.
    static var baseIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "KBAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultIdentifier
    }

    static func candidateIdentifiers() -> [String] {
        let bundles = [Bundle.main] + [hostAppBundle].compactMap { $0 }
        return orderedCandidates(base: baseIdentifier,
                                 altStoreGroups: bundles.map { $0.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? [] },
                                 profiles: bundles.compactMap { ProvisioningProfile.load(from: $0) })
    }

    /// Pure ordering logic (unit-testable): AltStore groups, then profile groups, then the base/default group,
    /// then any other group we were given.
    static func orderedCandidates(base: String, altStoreGroups: [[String]], profiles: [[String: Any]]) -> [String] {
        var ordered: [String] = []
        var leftovers: [String] = []
        func add(_ ids: [String], teamID: String? = nil) {
            let usable = ids.filter { !$0.isEmpty && !$0.contains("*") }
            let matching = usable.filter { $0 == base || $0.hasPrefix(base + ".") }
            // Prefer "<base>.<TEAMID>" (sideload rename), then the exact base group, then other matches.
            let ranked = matching.sorted { rank($0, base: base, teamID: teamID) < rank($1, base: base, teamID: teamID) }
            for id in ranked where !ordered.contains(id) { ordered.append(id) }
            for id in usable where !matching.contains(id) && !leftovers.contains(id) { leftovers.append(id) }
        }
        // (a) AltStore
        for groups in altStoreGroups {
            add(groups)
        }
        // (b) Provisioning profile (SideStore, Sideloadly, development / ad hoc)
        for profile in profiles {
            add(ProvisioningProfile.applicationGroups(in: profile), teamID: ProvisioningProfile.teamIdentifier(in: profile))
        }
        // (c) Info.plist default
        for id in [base, defaultIdentifier] where !ordered.contains(id) { ordered.append(id) }
        // Last resort: groups we own that don't match our base id.
        return ordered + leftovers.filter { !ordered.contains($0) }
    }

    private static func rank(_ id: String, base: String, teamID: String?) -> Int {
        if let teamID, id == "\(base).\(teamID)" { return 0 }
        if id == base { return 1 }
        return 2
    }

    private static var isExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }

    /// The containing app's bundle when running inside an extension (`App.app/PlugIns/X.appex`).
    private static var hostAppBundle: Bundle? {
        guard isExtension else { return nil }
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { return nil }
        return Bundle(url: appURL)
    }

    /// Builds that could not resolve their group before (SideStore/Sideloadly) kept the SwiftData store in
    /// Application Support. Move it into the shared container once, so no trips get lost after the fix.
    private static func adoptSandboxStore(into container: URL, storeName: String = "KlimaBilanz.store") {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              fm.fileExists(atPath: support.appendingPathComponent(storeName).path),
              !fm.fileExists(atPath: container.appendingPathComponent(storeName).path),
              let items = try? fm.contentsOfDirectory(atPath: support.path) else { return }
        let supportFolder = "." + storeName.replacingOccurrences(of: ".store", with: "") + "_SUPPORT"
        for item in items where item.hasPrefix(storeName) || item == supportFolder {
            try? fm.moveItem(at: support.appendingPathComponent(item), to: container.appendingPathComponent(item))
        }
    }
}

/// Reads the plist embedded in the CMS-signed `embedded.mobileprovision`. Present in sideloaded
/// (AltStore/SideStore/Sideloadly), development and ad-hoc builds – absent in App Store and TestFlight builds.
enum ProvisioningProfile {
    /// This bundle's (app or extension) profile file exists.
    static let isPresent: Bool = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil

    /// Parsed profile of `Bundle.main`, nil for App Store / TestFlight / simulator builds.
    static let main: [String: Any]? = load(from: .main)

    static var entitlements: [String: Any]? { main?["Entitlements"] as? [String: Any] }
    static var teamIdentifier: String? { main.flatMap(teamIdentifier(in:)) }
    static var applicationGroups: [String] { main.map(applicationGroups(in:)) ?? [] }

    /// Sideloaded with AltStore/SideStore/Sideloadly or a development/ad-hoc profile.
    static var isSideloadedOrDevelopment: Bool { isPresent }

    /// App Store / TestFlight builds always carry the target's entitlements; re-signed builds only what the profile grants.
    static var hasSignInWithApple: Bool {
        guard isPresent else { return true }
        return entitlements?["com.apple.developer.applesignin"] != nil
    }

    static func load(from bundle: Bundle) -> [String: Any]? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// The profile is a CMS (PKCS#7) envelope around an XML plist – cut out `<?xml … </plist>` and parse that.
    static func parse(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: [], in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)) as? [String: Any]
    }

    static func applicationGroups(in profile: [String: Any]) -> [String] {
        (profile["Entitlements"] as? [String: Any])?["com.apple.security.application-groups"] as? [String] ?? []
    }

    static func teamIdentifier(in profile: [String: Any]) -> String? {
        if let ids = profile["TeamIdentifier"] as? [String], let first = ids.first { return first }
        return (profile["Entitlements"] as? [String: Any])?["com.apple.developer.team-identifier"] as? String
    }
}
