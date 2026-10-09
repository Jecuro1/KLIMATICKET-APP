import Foundation

/// Remote live config (`data/live_config.json`, SPEC §A3.8): decode, validate, version compare.
/// A remote file can switch endpoints, rotate the public client ids, turn providers off (kill switch) and raise the
/// request spacing – it can never loosen the volume budget of SPEC §2.3 (intervals are clamped to the floors).
public enum LiveConfigLoader {
    /// Lowest allowed `minInterval` per provider (SPEC §2.3).
    public static let minimumInterval: [LiveProvider: TimeInterval] = [.oebbHafas: 0.3, .oebbShop: 1.0, .vaoTariff: 1.0]

    /// The decoded, validated and clamped config, or nil when the data is invalid or `version <= current.version`.
    public static func decode(_ data: Data, current: LiveConfig) -> LiveConfig? {
        guard let config = try? JSONDecoder().decode(LiveConfig.self, from: data), config.version > current.version else { return nil }
        return sanitized(config)
    }

    /// Validates and clamps a config (also used for the cached copy). nil when structurally unusable.
    public static func sanitized(_ config: LiveConfig) -> LiveConfig? {
        guard config.version > 0, isUsable(config.hafas), isUsable(config.vao), config.shop.baseURL.scheme == "https",
              config.shop.baseURL.host?.isEmpty == false,
              config.hafasFallback.map(isUsable) ?? true,
              !config.userAgent.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var c = config
        c.hafas = clamp(c.hafas, floor: minimumInterval[.oebbHafas] ?? 0.3)
        c.hafasFallback = c.hafasFallback.map { clamp($0, floor: minimumInterval[.oebbHafas] ?? 0.3) }
        c.vao = clamp(c.vao, floor: minimumInterval[.vaoTariff] ?? 1.0)
        c.shop.minInterval = max(c.shop.minInterval, minimumInterval[.oebbShop] ?? 1.0)
        c.shop.timeout = min(max(c.shop.timeout, 3), 60)
        c.shop.tokenRenewAfter = min(max(c.shop.tokenRenewAfter, 30), 290)
        if let notice = c.notice?.trimmingCharacters(in: .whitespacesAndNewlines) { c.notice = notice.isEmpty ? nil : notice }
        return c
    }

    /// Encoded template (`data/live_config.json`), pretty-printed with sorted keys.
    public static func encode(_ config: LiveConfig) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(config)
    }

    private static func isUsable(_ p: HafasProfile) -> Bool {
        p.url.scheme == "https" && p.url.host != nil && !p.aid.isEmpty && !p.ver.isEmpty && !p.lang.isEmpty && !p.client.id.isEmpty
    }

    private static func clamp(_ p: HafasProfile, floor: TimeInterval) -> HafasProfile {
        var p = p
        p.minInterval = max(p.minInterval, floor)
        p.timeout = min(max(p.timeout, 3), 60)
        return p
    }
}
