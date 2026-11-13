import Foundation

// MARK: themes – everything Look & Feel stores, as one JSON value under the App Group key `theme.v1` (docs/THEMES.md §7).
// The widgets read the palette from it; garbage, an unknown value or a newer field never fails – it becomes the default.

public struct AppearancePrefs: Codable, Equatable, Hashable, Sendable {
    /// App Group defaults key.
    public static let storageKey = "theme.v1"
    public static let currentVersion = 1

    public var version: Int
    public var palette: ThemePaletteID
    public var motion: MotionLevel
    public var haptics: HapticLevel
    public var format: FormatPrefs

    public init(palette: ThemePaletteID = .standard, motion: MotionLevel = .full, haptics: HapticLevel = .full,
                format: FormatPrefs = .standard) {
        version = Self.currentVersion
        self.palette = palette
        self.motion = motion
        self.haptics = haptics
        self.format = format
    }

    public static let standard = AppearancePrefs()

    /// Everything as before themes: Gletscher, full motion, the app's number format – only haptics depend on the old switch.
    public var isStandardLook: Bool {
        palette == .standard && motion == .full && format == .standard
    }

    private enum CodingKeys: String, CodingKey { case version, palette, motion, haptics, format }

    public init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        version = Self.decoded(c, .version) ?? Self.currentVersion
        palette = Self.decoded(c, .palette) ?? .standard
        motion = Self.decoded(c, .motion) ?? .full
        haptics = Self.decoded(c, .haptics) ?? .full
        format = Self.decoded(c, .format) ?? .standard
    }

    private static func decoded<T: Decodable>(_ container: KeyedDecodingContainer<CodingKeys>?, _ key: CodingKeys) -> T? {
        guard let container else { return nil }
        return try? container.decodeIfPresent(T.self, forKey: key)
    }

    /// The stored value, or nil when nothing (or nothing readable as an object) is stored.
    public static func decode(_ data: Data?) -> AppearancePrefs? {
        guard let data, !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        return try? JSONDecoder().decode(AppearancePrefs.self, from: data)
    }

    /// What the app starts with: the stored value, or – the first time – the defaults with the old haptics switch carried over.
    public static func load(_ data: Data?, legacyHapticsEnabled: Bool?) -> AppearancePrefs {
        if let stored = decode(data) { return stored }
        var prefs = AppearancePrefs()
        prefs.haptics = HapticLevel.migrated(hapticsEnabled: legacyHapticsEnabled)
        return prefs
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
