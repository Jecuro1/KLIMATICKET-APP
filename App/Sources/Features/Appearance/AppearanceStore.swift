import SwiftUI
import WidgetKit
import KlimaCore

// MARK: themes – Look & Feel: what you chose (theme.v1 in the App Group, docs/THEMES.md §7) and what the screens show.
//
// The choice is stored at once. Haptik works at once too (you feel the level you tap). Farbe, Bewegung and Zahlen reach the
// screens when the Settings sheet closes: `applyPending()` switches the runtimes and bumps `revision`, and RootView gives the
// tab interface that id, so every screen is built again with the new values under one cross-fade (no half-switched screen).

@Observable
@MainActor
final class AppearanceStore {
    /// What Look & Feel shows and stores.
    var prefs: AppearancePrefs {
        didSet {
            guard prefs != oldValue else { return }
            save()
        }
    }

    /// What the screens use right now. Differs from `prefs` while Einstellungen is open.
    private(set) var applied: AppearancePrefs

    /// Bumped whenever palette, motion or numbers on screen change (RootView re-identifies the tab interface).
    private(set) var revision = 0

    /// Where theme.v1 is written; nil for screenshot and perf runs (nothing is stored).
    @ObservationIgnored private let defaults: UserDefaults?

    /// `defaults`: the App Group defaults (or nil: not stored). `legacyHapticsEnabled`: the old switch „Haptisches Feedback“,
    /// carried over the first time. A screenshot scene and `-KBTheme` adjust the launch (applied, never stored).
    init(defaults: UserDefaults?, legacyHapticsEnabled: Bool?) {
        self.defaults = defaults
        var prefs = AppearancePrefs.load(defaults?.data(forKey: AppearancePrefs.storageKey), legacyHapticsEnabled: legacyHapticsEnabled)
        AppearanceLaunch.adjust(&prefs)
        self.prefs = prefs
        applied = prefs
        Self.activate(prefs)
    }

    /// The level every haptic plays at.
    var hapticLevel: HapticLevel { prefs.haptics }

    /// Farbe, Bewegung or Zahlen differ from what the screens show (they switch when Einstellungen closes).
    var hasPendingChanges: Bool { Self.visible(prefs) != Self.visible(applied) }

    /// Switches the screens to the stored choice. Returns whether anything visible changed (then `revision` moved).
    @discardableResult
    func applyPending() -> Bool {
        let paletteChanged = applied.palette != prefs.palette
        guard hasPendingChanges else {
            applied = prefs
            return false
        }
        applied = prefs
        Self.activate(prefs)
        revision &+= 1
        // Widgets read the palette from theme.v1 when they draw: ask for a redraw (iOS decides when; docs/THEMES.md §7).
        if paletteChanged, defaults != nil { WidgetCenter.shared.reloadAllTimelines() }
        return true
    }

    private static func activate(_ prefs: AppearancePrefs) {
        ThemeRuntime.activate(prefs.palette)
        AppearanceRuntime.apply(prefs)
    }

    /// What a screen shows (haptics are felt, not seen).
    private static func visible(_ prefs: AppearancePrefs) -> AppearancePrefs {
        var copy = prefs
        copy.haptics = .full
        return copy
    }

    private func save() {
        defaults?.set(prefs.encoded(), forKey: AppearancePrefs.storageKey)
    }
}

/// Launch arguments of Look & Feel (CI and perf runs).
enum AppearanceLaunch {
    /// The screenshot scene's choices, then `-KBTheme <id>` on top. Applied for this launch, never stored.
    static func adjust(_ prefs: inout AppearancePrefs) {
        if let screen = LaunchMode.screenshotScreen, let scene = screenshotPrefs(for: screen) { prefs = scene }
        if let raw = UserDefaults.standard.string(forKey: "KBTheme"), let id = ThemePaletteID(rawValue: raw) { prefs.palette = id }
    }

    /// The capture script passes no extra arguments per scene, so each theme scene (AppearanceScreenshotHost) names its
    /// choices here – the same as `-KBTheme <id>` would.
    static func screenshotPrefs(for screen: String) -> AppearancePrefs? {
        let numbers = FormatPrefs(amounts: .cents, weekStart: .sunday, co2: .kilograms)
        switch screen {
        case "themeDash", "themeGallery": return AppearancePrefs(palette: .zirbe)
        case "themeStats", "themeAX5", "themeAX5Lower": return AppearancePrefs(palette: .morgenrot)
        case "themeStatsFormat", "themeStatsWeek", "themeDashWeek": return AppearancePrefs(format: numbers)
        case "themeTicket": return AppearancePrefs(palette: .daemmerung)
        case "themeOptions": return AppearancePrefs(palette: .graphit, motion: .calm, haptics: .subtle, format: numbers)
        case "themeSettingsRow": return AppearancePrefs(palette: .alpengluehen)
        default: return nil
        }
    }
}
