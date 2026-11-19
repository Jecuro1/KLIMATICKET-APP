import Foundation
import KlimaCore

// MARK: radar2-radartrail – the one thing „Spuren“ keeps: the setting (Aus / Ausgewählte und meine / Alle im Ausschnitt, 5 / 10 / 20 Min) under
// `radar.trail.v1`, per device, like every radar setting in the iPhone's own backup. Never a position. Screenshot and perf launches neither read nor
// write it: they start from the default or from their scene (`RadarTrailDemo.scene`). The only file of this feature that may name the defaults
// (`RadarTrailSourceGuardTests`).

@MainActor
enum RadarTrailSettingStore {
    static func load() -> RadarTrailSetting {
        if LaunchMode.isSandboxed { return RadarTrailDemo.scene?.setting ?? .standard }
        return RadarTrailSetting(storage: UserDefaults.standard.string(forKey: RadarTrailSetting.storageKey) ?? "")
    }

    static func save(_ setting: RadarTrailSetting) {
        guard !LaunchMode.isSandboxed else { return }
        UserDefaults.standard.set(setting.storageValue, forKey: RadarTrailSetting.storageKey)
    }
}
