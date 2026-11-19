import Foundation

// MARK: data – the settings block of a version-3 backup (docs/DATA_HUB.md §3). An allow-list decides what goes in; a deny-list that
// always wins keeps sign-in, tokens, user ids, the live-data consent and device state out. The Keychain is never read for a backup.

/// One stored setting, as a property-list value the app can write back.
public enum BackupSettingValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])
    case data(Data)

    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
        case "int": self = .int(try c.decode(Int.self, forKey: .value))
        case "double": self = .double(try c.decode(Double.self, forKey: .value))
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "strings": self = .strings(try c.decode([String].self, forKey: .value))
        case "data": self = .data(try c.decode(Data.self, forKey: .value))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown setting type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let v): try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
        case .int(let v): try c.encode("int", forKey: .type); try c.encode(v, forKey: .value)
        case .double(let v): try c.encode("double", forKey: .type); try c.encode(v, forKey: .value)
        case .string(let v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
        case .strings(let v): try c.encode("strings", forKey: .type); try c.encode(v, forKey: .value)
        case .data(let v): try c.encode("data", forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    /// A property-list value from UserDefaults; nil for types a backup does not carry (dictionaries, dates, nested arrays).
    public init?(plist value: Any) {
        // Exact Swift types first: on Apple platforms an NSNumber holding a Bool would also bridge to Int.
        if let v = value as? Bool, type(of: value) == Bool.self { self = .bool(v); return }
        if let v = value as? Int, type(of: value) == Int.self { self = .int(v); return }
        if let v = value as? Double, type(of: value) == Double.self { self = .double(v); return }
        if let v = value as? String { self = .string(v); return }
        if let v = value as? [String] { self = .strings(v); return }
        if let v = value as? Data { self = .data(v); return }
        if let v = value as? NSNumber {
            // UserDefaults hands numbers over as NSNumber: a boolean one has the Objective-C type "c" (or "B").
            let type = String(cString: v.objCType)
            if type == "c" || type == "B" { self = .bool(v.boolValue) }
            else if v.doubleValue.rounded() == v.doubleValue, abs(v.doubleValue) < 9.0e15 { self = .int(v.intValue) }
            else { self = .double(v.doubleValue) }
            return
        }
        return nil
    }

    /// The value to hand UserDefaults.
    public var plistValue: Any {
        switch self {
        case .bool(let v): v
        case .int(let v): v
        case .double(let v): v
        case .string(let v): v
        case .strings(let v): v
        case .data(let v): v
        }
    }

    var byteCount: Int {
        switch self {
        case .bool, .int, .double: 8
        case .string(let v): v.utf8.count
        case .strings(let v): v.reduce(0) { $0 + $1.utf8.count }
        case .data(let v): v.count
        }
    }

    var strings: [String] {
        switch self {
        case .string(let v): [v]
        case .strings(let v): v
        case .data(let v): String(data: v, encoding: .utf8).map { [$0] } ?? []
        case .bool, .int, .double: []
        }
    }
}

public enum BackupSettingsPolicy {
    /// Settings by exact key (AppSettings and the stores of the tracks).
    public static let allowedKeys: Set<String> = [
        "appearance", "defaultDiscount", "defaultTravelClass", "homeStationID", "hapticsEnabled", "autoUpdateCheck",
        "renewalRemindersEnabled", "weeklySummaryEnabled", "localAIEnabled", "map.layers", "atlas.mapLook",
        "planner.options", "planner.sort", "commute.settings.v1", "calendarSuggestions.prefs.v1", "kb.whatif.scenarios.v1",
        "rules.v1",
    ]

    /// Settings by prefix (Look & Feel, Übersicht, goals, the feature switches, the radar's display and filters).
    public static let allowedPrefixes = ["theme.", "dash.", "goals.", "features.", "radar.", "radar2."]

    /// Never in a backup, even under an allowed prefix: compared in lower case, anywhere in the key.
    public static let deniedFragments = [
        "token", "secret", "password", "passwort", "credential", "session", "consent", "auth", "cookie", "apikey", "api_key",
        "userid", "user_id", "user.id", "keychain", "bookmark", "pushkey", "deviceid", "udid",
    ]

    /// Never in a backup: live data and its consent, account and sync state, the backup's own state, letters (name and address),
    /// the store, demo marks, launch switches and the system's own keys.
    public static let deniedPrefixes = [
        "live", "cloud.", "sync.", "auth.", "backup.", "letters.", "store.", "demo.", "KB", "widgetSnapshot", "NS", "Apple",
        "com.apple", "rules.log", "rules.ledger",
    ]

    /// At most this much per value – a settings value is small; a large blob is state, not a setting.
    public static let maxValueBytes = 256 * 1024

    public static func isDenied(_ key: String) -> Bool {
        let lower = key.lowercased()
        return deniedFragments.contains { lower.contains($0) } || deniedPrefixes.contains { key.hasPrefix($0) }
    }

    public static func allows(_ key: String) -> Bool {
        guard !isDenied(key) else { return false }
        return allowedKeys.contains(key) || allowedPrefixes.contains { key.hasPrefix($0) }
    }

    /// A value that looks like a token (a JSON Web Token, a bearer string) is refused even under an allowed key.
    public static func looksSecret(_ value: BackupSettingValue) -> Bool {
        value.strings.contains { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("bearer ") { return true }
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
            return trimmed.hasPrefix("eyJ") && parts.count == 3 && parts.allSatisfy { $0.count >= 8 }
                && !trimmed.contains(" ")
        }
    }

    public struct Result: Equatable, Sendable {
        public var kept: [String: BackupSettingValue]
        /// Keys that were asked for but refused (denied, too large, token-like). Allowed-list misses are not listed.
        public var refused: [String]
    }

    /// The settings a backup carries. Keys outside the allow-list are skipped silently; keys the allow-list matches but the
    /// deny-list or the value check refuses are reported.
    public static func filter(_ values: [String: BackupSettingValue]) -> Result {
        var kept: [String: BackupSettingValue] = [:]
        var refused: [String] = []
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            let matches = allowedKeys.contains(key) || allowedPrefixes.contains { key.hasPrefix($0) }
            guard matches else { continue }
            if isDenied(key) || looksSecret(value) || value.byteCount > maxValueBytes {
                refused.append(key)
            } else {
                kept[key] = value
            }
        }
        return Result(kept: kept, refused: refused)
    }

    /// The settings of a file that would change something here: allowed again on this device and different from now.
    public static func changes(file: [String: BackupSettingValue], current: [String: BackupSettingValue]) -> [String] {
        file.keys.filter { allows($0) && file[$0] != current[$0] }.sorted()
    }

    public static let note = "Einstellungen sind dabei – ohne Anmeldung, Schlüssel, Live-Daten-Zustimmung und Briefdaten. Die bleiben nur auf diesem iPhone."
}
