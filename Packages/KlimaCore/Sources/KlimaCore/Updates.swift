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

    public init(version: SemanticVersion, build: Int, publishedAt: String, minimumOSVersion: String? = nil, downloadURL: String,
                altstoreSourceURL: String? = nil, otaManifestURL: String? = nil, releaseNotes: [String] = [],
                minimumSupportedVersion: SemanticVersion? = nil, tariffsVersion: Int? = nil, tariffsURL: String? = nil) {
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
