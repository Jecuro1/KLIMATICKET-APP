import Foundation

// MARK: funktionen – what the hub stores itself, as one JSON value under `features.v1` (docs/FUNCTIONS_HUB.md §4): the
// Offline-Modus and the hub switches that differ from their default. Switches that existed before the hub stay where they were.
// Garbage, an unknown id, a wrapped id or a value that is not a boolean never fails – it is ignored.

public struct FeatureSettings: Equatable, Sendable {
    /// UserDefaults key.
    public static let storageKey = "features.v1"
    public static let currentVersion = 1

    /// Hub switches that differ from their default (wrapped ids are never kept here).
    public private(set) var overrides: [FeatureID: Bool]
    /// Offline-Modus: no live data and no automatic update check, whatever the single switches say.
    public var offlineMode: Bool

    public init(overrides: [FeatureID: Bool] = [:], offlineMode: Bool = false) {
        self.overrides = [:]
        self.offlineMode = offlineMode
        for (id, on) in overrides { set(id, on) }
    }

    public static let standard = FeatureSettings()

    /// The hub switch of `id`: the stored override, else the default. nil for a switch that lives elsewhere.
    public func hubSwitch(_ id: FeatureID) -> Bool? {
        guard let fallback = id.descriptor.hubDefault else { return nil }
        return overrides[id] ?? fallback
    }

    /// Sets a hub switch. Only the difference to the default is stored, so a later default applies to whoever never touched it.
    /// Wrapped ids are ignored (their switch lives at its own place).
    public mutating func set(_ id: FeatureID, _ on: Bool) {
        guard let fallback = id.descriptor.hubDefault else { return }
        overrides[id] = on == fallback ? nil : on
    }

    /// Every hub switch back to its default; the Offline-Modus stays as it is.
    public mutating func resetSwitches() {
        overrides = [:]
    }

    // MARK: Storage

    /// The stored value, or the defaults for nothing, garbage, a non-object or an unreadable version.
    public static func decode(_ data: Data?) -> FeatureSettings {
        guard let data, !data.isEmpty,
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .standard }
        guard let version = stored.version, version >= 1 else { return .standard }
        var settings = FeatureSettings(offlineMode: stored.offlineMode ?? false)
        for (key, value) in stored.overrides {
            guard let id = FeatureID(rawValue: key) else { continue }
            settings.set(id, value)
        }
        return settings
    }

    public func encoded() -> Data {
        let stored = Stored(version: Self.currentVersion,
                            overrides: Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) }),
                            offlineMode: offlineMode)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(stored)) ?? Data()
    }

    /// The JSON shape. Decoding reads every key on its own: one bad value drops that value, not the rest.
    private struct Stored: Codable {
        var version: Int?
        var overrides: [String: Bool]
        var offlineMode: Bool?

        init(version: Int?, overrides: [String: Bool], offlineMode: Bool?) {
            self.version = version
            self.overrides = overrides
            self.offlineMode = offlineMode
        }

        private enum CodingKeys: String, CodingKey { case version, overrides, offlineMode }

        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try? c.decodeIfPresent(Int.self, forKey: .version)
            offlineMode = try? c.decodeIfPresent(Bool.self, forKey: .offlineMode)
            var read: [String: Bool] = [:]
            if let nested = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: .overrides) {
                for key in nested.allKeys {
                    if let value = try? nested.decode(Bool.self, forKey: key) { read[key.stringValue] = value }
                }
            }
            overrides = read
        }
    }
}
