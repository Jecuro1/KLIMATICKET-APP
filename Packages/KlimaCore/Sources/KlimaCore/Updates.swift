import Foundation

/// Semantic version ("1.4.2") with optional build number, comparable.
public struct SemanticVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let core = s.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? s
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }), parts.count <= 3 else { return nil }
        major = parts[0]!
        minor = parts.count > 1 ? parts[1]! : 0
        patch = parts.count > 2 ? parts[2]! : 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let v = SemanticVersion(raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid version \(raw)")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (l: SemanticVersion, r: SemanticVersion) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }
}

/// JSON manifest published by CI with every release (`update.json`).
public struct UpdateManifest: Codable, Hashable, Sendable {
    public var version: SemanticVersion
    public var build: Int
    public var publishedAt: String
    public var minimumOSVersion: String?
    /// Direct .ipa download.
    public var downloadURL: String
    /// AltStore / SideStore source: the store detects new versions and updates with one tap.
    public var altstoreSourceURL: String?
    /// Optional itms-services manifest for signed ad-hoc builds.
    public var otaManifestURL: String?
    public var releaseNotes: [String]
    /// Force the update sheet (non-dismissible) when the installed version is below this.
    public var minimumSupportedVersion: SemanticVersion?
    /// Newer tariff catalog version available at `tariffsURL`.
    public var tariffsVersion: Int?
    public var tariffsURL: String?
    // MARK: settings – Manuell aktualisieren: the .ipa behind `downloadURL` (scripts/make_release_metadata.py writes both).
    /// Size of the .ipa in bytes.
    public var size: Int?
    /// Lowercase hex SHA-256 of the .ipa.
    public var sha256: String?
    // MARK: planner – where the remote live config (kill switch, endpoints) lives; nil = the build's `liveConfigURL`.
    public var liveConfigURL: String?

    public init(version: SemanticVersion, build: Int, publishedAt: String, minimumOSVersion: String? = nil, downloadURL: String,
                altstoreSourceURL: String? = nil, otaManifestURL: String? = nil, releaseNotes: [String] = [],
                minimumSupportedVersion: SemanticVersion? = nil, tariffsVersion: Int? = nil, tariffsURL: String? = nil,
                size: Int? = nil, sha256: String? = nil, liveConfigURL: String? = nil) {
        self.version = version
        self.build = build
        self.publishedAt = publishedAt
        self.minimumOSVersion = minimumOSVersion
        self.downloadURL = downloadURL
        self.altstoreSourceURL = altstoreSourceURL
        self.otaManifestURL = otaManifestURL
        self.releaseNotes = releaseNotes
        self.minimumSupportedVersion = minimumSupportedVersion
        self.tariffsVersion = tariffsVersion
        self.tariffsURL = tariffsURL
        self.size = size
        self.sha256 = sha256
        self.liveConfigURL = liveConfigURL
    }
}

public enum UpdateDecision: Hashable, Sendable {
    case upToDate
    case available(UpdateManifest)
    case required(UpdateManifest)

    public static func evaluate(installed: SemanticVersion, installedBuild: Int, manifest: UpdateManifest) -> UpdateDecision {
        if let min = manifest.minimumSupportedVersion, installed < min { return .required(manifest) }
        if manifest.version > installed { return .available(manifest) }
        if manifest.version == installed && manifest.build > installedBuild { return .available(manifest) }
        return .upToDate
    }
}

// MARK: ota – Direkt installieren (ad-hoc builds over the air, docs/DIREKT_INSTALLIEREN.md)

/// How the provisioning profile embedded in this copy (`embedded.mobileprovision`) was made.
public enum ProvisioningKind: Equatable, Sendable {
    /// No profile: App Store, TestFlight or the simulator.
    case none
    /// Development profile (`get-task-allow`): AltStore, SideStore, Sideloadly, Xcode.
    case development
    /// Ad hoc: a device list without `get-task-allow` – our own signed build for registered iPhones.
    case adHoc
    /// Enterprise (`ProvisionsAllDevices`).
    case enterprise
    /// A profile without devices (App Store distribution) – never embedded in an installed app.
    case other

    /// Classifies the parsed profile plist (nil = no profile).
    public init(profile: [String: Any]?) {
        guard let profile else { self = .none; return }
        if profile["ProvisionsAllDevices"] as? Bool == true { self = .enterprise; return }
        let entitlements = profile["Entitlements"] as? [String: Any]
        if entitlements?["get-task-allow"] as? Bool == true { self = .development; return }
        let devices = profile["ProvisionedDevices"] as? [String] ?? []
        self = devices.isEmpty ? .other : .adHoc
    }
}

public enum DirectInstall {
    /// An itms-services install of our ad-hoc build replaces this copy in place – same app, same data – only when this
    /// copy is itself our ad-hoc build: AltStore and SideStore rename the bundle id (`<id>.<TEAMID>`), so there the new
    /// build would arrive as a second app.
    public static func replacesInPlace(kind: ProvisioningKind, bundleIdentifier: String?, expected: String) -> Bool {
        kind == .adHoc && bundleIdentifier == expected
    }

    /// `itms-services://?action=download-manifest&url=…` for an https manifest URL (iOS refuses anything else).
    public static func link(manifestURL: String?) -> URL? {
        guard let manifestURL, let url = URL(string: manifestURL), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = manifestURL.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "itms-services://?action=download-manifest&url=" + encoded)
    }
}

// MARK: settings – Manuell aktualisieren (docs/MANUAL_UPDATE.md)

/// The in-app .ipa download: where the file is kept and whether a finished download is the release it claims to be.
/// iOS installs no .ipa by itself – the verified file goes to SideStore/AltStore (Teilen) or into the Files app.
public enum ManualUpdate {
    public enum Verification: Equatable, Sendable {
        case verified
        /// The manifest names no checksum – only the size could be compared (or nothing at all).
        case unverifiable
        case sizeMismatch(expected: Int, actual: Int)
        case checksumMismatch
    }

    /// "KlimaBilanz-1.0.5-361.ipa" – version and build, so an older download is never taken for a newer release.
    public static func fileName(for manifest: UpdateManifest) -> String {
        "KlimaBilanz-\(manifest.version)-\(manifest.build).ipa"
    }

    /// The manifest's checksum when it is a well-formed SHA-256 (64 hex digits), lowercased.
    public static func expectedChecksum(_ manifest: UpdateManifest) -> String? {
        guard let raw = manifest.sha256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.count == 64, raw.allSatisfy({ $0.isHexDigit }) else { return nil }
        return raw
    }

    /// The size to show and to compare against: the manifest's, else what the server announced.
    public static func expectedSize(_ manifest: UpdateManifest, announced: Int64? = nil) -> Int64? {
        if let size = manifest.size, size > 0 { return Int64(size) }
        if let announced, announced > 0 { return announced }
        return nil
    }

    /// Size first (cheap, catches truncated files), then the checksum when the manifest has one.
    public static func verify(manifest: UpdateManifest, actualSize: Int64, actualChecksum: String?) -> Verification {
        if let size = manifest.size, size > 0, Int64(size) != actualSize {
            return .sizeMismatch(expected: size, actual: Int(actualSize))
        }
        guard let expected = expectedChecksum(manifest) else { return .unverifiable }
        guard let actualChecksum, actualChecksum.lowercased() == expected else { return .checksumMismatch }
        return .verified
    }

    /// A kept download is only worth offering while it is newer than (or a rebuild of) the installed copy.
    public static func isStale(fileVersion: SemanticVersion, fileBuild: Int, installed: SemanticVersion, installedBuild: Int) -> Bool {
        if fileVersion != installed { return fileVersion < installed }
        return fileBuild <= installedBuild
    }

    /// 0…1 progress, clamped; nil while the total is unknown.
    public static func fraction(received: Int64, total: Int64?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(max(Double(received) / Double(total), 0), 1)
    }
}
